import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/reading/page_text.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/sno/index/shelf_reading.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';

/// Книга прохода: страницы, которые можно придержать и сломать.
class _Volume extends FakeReaderDocument {
  _Volume({required super.pages});

  /// Страницы, которые движок не отдаёт.
  final Set<int> broken = <int>{};

  /// Что сделать перед тем, как отдать страницу.
  Future<void> Function(int page)? onRead;

  /// Сколько раз документ открывали и закрывали.
  int opens = 0;
  int closes = 0;

  @override
  Future<String> pageText(int pageNumber) async {
    await onRead?.call(pageNumber);
    if (broken.contains(pageNumber)) {
      textReads[pageNumber] = (textReads[pageNumber] ?? 0) + 1;
      throw StateError('страница не читается');
    }
    return super.pageText(pageNumber);
  }

  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

/// Открыватель полки: у каждой книги свой документ, по её источнику.
class _ShelfOpener implements DocumentOpener {
  final Map<String, _Volume> volumes = <String, _Volume>{};

  /// Источники, которые не открываются.
  final Set<String> missing = <String>{};

  /// Что просили открыть, по порядку.
  final List<String> opened = <String>[];

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    final String path = (source as FilePathSource).path;
    opened.add(path);
    final _Volume? volume = volumes[path];
    if (volume == null || missing.contains(path)) {
      throw DocumentOpenException(DocumentProblem.missing, source);
    }
    volume.opens++;
    return volume;
  }
}

/// SNO-F-IDX-04: проход по полке — текст всех книг заранее.
///
/// База настоящая, в памяти; движок — подставной, и каждую страницу
/// тест может придержать или сломать. Мешки и карта считаются на
/// месте, без изолята.
void main() {
  late AppData data;
  late _ShelfOpener opener;
  late MemorySettings settings;
  late FakeDeviceStatus device;
  final List<ShelfReading> made = <ShelfReading>[];

  setUp(() async {
    data = await openTestData();
    opener = _ShelfOpener();
    settings = MemorySettings();
    device = FakeDeviceStatus();
    await data.categories.save(
      BookCategory(
        id: 'angio',
        title: 'Ангиология',
        position: 0,
        createdAt: DateTime.utc(2026, 10, 5),
      ),
    );
  });

  tearDown(() async {
    for (final ShelfReading reading in made) {
      reading.dispose();
    }
    made.clear();
    await data.close();
  });

  /// Кладёт книгу на полку и её документ — открывателю.
  Future<_Volume> shelve(
    String id,
    List<String> pages, {
    int? pageCount,
    bool? hasTextLayer,
  }) async {
    final Book book = testBook(id: id, title: 'Том $id', hash: 'hash-$id')
        .copyWith(
          pageCount: pageCount ?? pages.length,
          hasTextLayer: hasTextLayer,
        );
    await data.library.save(book);
    await placeBook(data, id, 'angio');
    final _Volume volume = _Volume(pages: pages);
    opener.volumes['/books/$id.pdf'] = volume;
    return volume;
  }

  PageTextKey keyOf(String id) {
    return PageTextKey(bookId: id, fingerprint: 'hash-$id');
  }

  ShelfReading reading({
    int Function()? nowMs,
    bool Function()? screenBusy,
    int batch = 2,
  }) {
    final ShelfReading pass = ShelfReading(
      library: data.library,
      opener: opener,
      texts: data.pageTexts,
      settings: settings,
      map: MapBuilder(
        library: data.library,
        categories: data.categories,
        texts: data.pageTexts,
        store: data.bookMap,
        bags: (BagRequest request) async => bagOfBook(request),
        layout: (List<BookBag> bags) async => buildBookMap(bags),
      ),
      device: device,
      screenBusy: screenBusy,
      nowMs: nowMs,
      batch: batch,
    );
    made.add(pass);
    return pass;
  }

  List<String> pagesOf(String word, int count) {
    return <String>[
      for (int i = 1; i <= count; i++) 'Страница $i про $word и сосуды.',
    ];
  }

  test('SNO-F-IDX-04: проход читает все книги полки и считает карту', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 5));
    final _Volume b = await shelve('b', pagesOf('вены', 3));
    final _Volume c = await shelve('c', pagesOf('лимфу', 4));
    final ShelfReading pass = reading();
    final List<ShelfReadingPhase> phases = <ShelfReadingPhase>[];
    pass.addListener(() {
      final ShelfReadingPhase phase = pass.progress.phase;
      if (phase == ShelfReadingPhase.idle) {
        return;
      }
      if (phases.isEmpty || phases.last != phase) {
        phases.add(phase);
      }
    });

    pass.start();
    await pass.settled();

    // Текст каждой страницы лежит в кэше — том же, что у открытой книги.
    expect(await data.pageTexts.cachedPages(keyOf('a')), hasLength(5));
    expect(await data.pageTexts.cachedPages(keyOf('b')), hasLength(3));
    expect(await data.pageTexts.cachedPages(keyOf('c')), hasLength(4));
    expect(
      (await data.pageTexts.pageTexts(keyOf('b'), from: 2, to: 2))[2],
      'Страница 2 про вены и сосуды.',
    );
    // Каждая страница прочитана движком один раз, файлы закрыты.
    for (final _Volume volume in <_Volume>[a, b, c]) {
      expect(volume.textReads.values, everyElement(1));
      expect(volume.opens, 1);
      expect(volume.closes, 1);
    }

    expect(phases, <ShelfReadingPhase>[
      ShelfReadingPhase.reading,
      ShelfReadingPhase.mapping,
      ShelfReadingPhase.done,
    ]);
    expect(pass.progress.busy, isFalse);
    expect(pass.progress.booksDone, 3);
    expect(pass.progress.booksTotal, 3);

    final ShelfIndexSummary summary = pass.summary!;
    expect(summary.complete, isTrue);
    expect(summary.books, 3);
    expect(summary.pages, 12);
    expect(summary.scans, 0);
    expect(summary.unread, isEmpty);
    expect(summary.map!.state, MapSummary.built);
    expect(summary.map!.books, 3);
    expect(summary.map!.groups, 1);
    expect(summary.map!.fingerprint, hasLength(8));
    // Карта лежит в базе, у каждой книги — место.
    expect((await data.bookMap.load())!.points.keys.toSet(), <String>{
      'a',
      'b',
      'c',
    });
  });

  test('SNO-F-IDX-04: прочитанное не перечитывается и файл не '
      'открывается', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 5));
    await shelve('b', pagesOf('вены', 3));
    await shelve('c', pagesOf('лимфу', 4));
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();
    final int opened = opener.opened.length;
    final String print = pass.summary!.map!.fingerprint;

    // Второй запуск приложения: новый проход поверх той же базы.
    final ShelfReading again = reading();
    await again.restore();
    expect(again.summary!.books, 3);
    // Делать нечего — и подготовки не видно: полоска над полкой не
    // мелькает при каждом запуске.
    bool shown = false;
    again.addListener(() => shown = shown || again.progress.busy);
    again.start();
    await again.settled();
    expect(shown, isFalse);
    expect(again.progress.phase, ShelfReadingPhase.done);

    expect(opener.opened.length, opened);
    expect(a.textReads.values, everyElement(1));
    expect(again.summary!.complete, isTrue);
    expect(again.summary!.pages, 12);
    // Карта та же и второй раз не считалась: время расчёта — прежнее.
    expect(again.summary!.map!.fingerprint, print);
    expect(again.summary!.map!.ms, pass.summary!.map!.ms);
  });

  test('SNO-F-IDX-04: проход продолжает с места остановки', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 6));
    // Три страницы запомнены прежним запуском.
    await data.pageTexts.savePageTexts(keyOf('a'), <int, String>{
      1: 'Страница 1 про артерии и сосуды.',
      2: 'Страница 2 про артерии и сосуды.',
      4: 'Страница 4 про артерии и сосуды.',
    });
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();

    expect(a.textReads.keys.toSet(), <int>{3, 5, 6});
    expect(await data.pageTexts.cachedPages(keyOf('a')), hasLength(6));
    expect(pass.summary!.books, 1);
    expect(pass.summary!.pages, 6);
    // Книг меньше трёх — карты нет, и об этом сказано.
    expect(pass.summary!.map!.state, MapSummary.tooFew);
  });

  test('SNO-F-IDX-04: пока открыта книга, проход стоит', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 6));
    final ShelfReading pass = reading();
    // Книгу открыли на третьей странице прохода.
    a.onRead = (int page) async {
      if (page == 3) {
        pass.held = true;
      }
    };
    pass.start();
    // Проход дочитывает страницу, записывает прочитанное и встаёт.
    while (pass.progress.phase != ShelfReadingPhase.held) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(pass.progress.busy, isTrue);
    expect(a.textReads.keys.toSet(), <int>{1, 2, 3});
    // Свой файл проход закрыл: движок отдан читателю.
    expect(a.closes, 1);
    expect((await data.pageTexts.cachedPages(keyOf('a'))).keys.toSet(), <int>{
      1,
      2,
      3,
    });
    expect(pass.summary, isNull);

    // Книгу закрыли — проход продолжает с четвёртой страницы.
    a.onRead = null;
    pass.held = false;
    await pass.settled();
    expect(a.textReads.values, everyElement(1));
    expect(a.textReads.keys.toSet(), <int>{1, 2, 3, 4, 5, 6});
    expect(a.opens, 2);
    expect(a.closes, 2);
    expect(pass.summary!.complete, isTrue);
    expect(pass.progress.phase, ShelfReadingPhase.done);
  });

  test('SNO-F-IDX-04: страницы, которые за время простоя запомнил '
      'читатель, не перечитываются', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 6));
    final ShelfReading pass = reading();
    a.onRead = (int page) async {
      if (page == 2) {
        pass.held = true;
      }
    };
    pass.start();
    while (pass.progress.phase != ShelfReadingPhase.held) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Читатель открыл эту же книгу, и его проход запомнил ещё три
    // страницы — в тот же кэш.
    await data.pageTexts.savePageTexts(keyOf('a'), <int, String>{
      3: 'Страница 3 про артерии и сосуды.',
      4: 'Страница 4 про артерии и сосуды.',
      5: 'Страница 5 про артерии и сосуды.',
    });
    a.onRead = null;
    pass.held = false;
    await pass.settled();

    expect(a.textReads.keys.toSet(), <int>{1, 2, 6});
    expect(pass.summary!.books, 1);
    expect(pass.summary!.pages, 6);
  });

  test('SNO-F-IDX-04: книга открыта до начала — проход ждёт её '
      'закрытия', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 2));
    final ShelfReading pass = reading();
    pass.held = true;
    pass.start();
    while (pass.progress.phase != ShelfReadingPhase.held) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(a.opens, 0);
    expect(a.textReads, isEmpty);

    pass.held = false;
    await pass.settled();
    expect(a.textReads.keys.toSet(), <int>{1, 2});
  });

  test('SNO-F-IDX-04: книга не открылась — названа, остальные '
      'читаются', () async {
    await shelve('a', pagesOf('артерии', 2));
    await shelve('b', pagesOf('вены', 2));
    await shelve('c', pagesOf('лимфу', 2));
    opener.missing.add('/books/b.pdf');
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();

    expect(pass.summary!.complete, isTrue);
    expect(pass.summary!.books, 2);
    expect(pass.summary!.pages, 4);
    expect(pass.summary!.unread, <String>['Том b']);
    expect(await data.pageTexts.cachedPages(keyOf('b')), isEmpty);
    // Карта считается и с ней: место ей даёт название.
    expect(pass.summary!.map!.state, MapSummary.built);
    expect(pass.summary!.map!.books, 3);
  });

  test('SNO-F-IDX-04: страница не прочиталась — книга прочитана не '
      'вся', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 4));
    a.broken.add(2);
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();

    // «Не знаю» не запоминается как «текста нет».
    expect((await data.pageTexts.cachedPages(keyOf('a'))).keys.toSet(), <int>{
      1,
      3,
      4,
    });
    expect(pass.summary!.books, 0);
    expect(pass.summary!.unread, <String>['Том a']);

    // В следующий раз читается только она — и книга прочитана.
    a.broken.clear();
    pass.start();
    await pass.settled();
    expect(a.textReads, <int, int>{1: 1, 2: 2, 3: 1, 4: 1});
    expect(pass.summary!.books, 1);
    expect(pass.summary!.unread, isEmpty);
  });

  test('SNO-F-IDX-04: скан без текста посчитан отдельно', () async {
    await shelve('a', pagesOf('артерии', 2));
    await shelve('scan', <String>['', '', '']);
    // Скан, о котором сказал ещё импорт: у его страниц одни пробелы.
    await shelve('blank', <String>[' \n', '\n'], hasTextLayer: false);
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();

    expect(pass.summary!.books, 3);
    expect(pass.summary!.scans, 2);
    expect(pass.summary!.unread, isEmpty);
    // Пустая страница — тоже ответ: за ней к движку больше не ходят.
    expect(await data.pageTexts.cachedPages(keyOf('scan')), <int, int>{
      1: 0,
      2: 0,
      3: 0,
    });
  });

  test('SNO-F-IDX-04: число страниц берётся у файла, а не у полки', () async {
    // На полке записано три страницы, а в файле их пять.
    final _Volume a = await shelve('a', pagesOf('артерии', 5), pageCount: 3);
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();
    expect(a.textReads.keys.toSet(), <int>{1, 2, 3, 4, 5});
    expect(pass.summary!.pages, 5);
  });

  test('SNO-F-IDX-04: пока проход читает, экран не гаснет', () async {
    await shelve('a', pagesOf('артерии', 3));
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();
    expect(device.screen, <bool>[true, false]);

    // Читать нечего — экран не трогают.
    device.screen.clear();
    pass.start();
    await pass.settled();
    expect(device.screen, isEmpty);
  });

  test('SNO-F-IDX-04: экран, который держит запись, проход не '
      'трогает', () async {
    await shelve('a', pagesOf('артерии', 3));
    final ShelfReading pass = reading(screenBusy: () => true);
    pass.start();
    await pass.settled();
    expect(device.screen, isEmpty);
    expect(pass.summary!.complete, isTrue);
  });

  test('SNO-F-IDX-04: время чтения копится и без чтения не '
      'растёт', () async {
    int now = 1000;
    final _Volume a = await shelve('a', pagesOf('артерии', 4));
    final _Volume b = await shelve('b', pagesOf('вены', 2));
    // Страница читается сто миллисекунд.
    Future<void> slow(int page) async => now += 100;
    a.onRead = slow;
    b.onRead = slow;
    final ShelfReading pass = reading(nowMs: () => now);
    pass.start();
    await pass.settled();
    expect(pass.summary!.readMs, 600);

    // Прошёл час, читать нечего: счёт стоит.
    now += 3600000;
    pass.start();
    await pass.settled();
    expect(pass.summary!.readMs, 600);

    // Новая книга: её время прибавляется к прежнему.
    final _Volume c = await shelve('c', pagesOf('лимфу', 3));
    c.onRead = slow;
    pass.start();
    await pass.settled();
    expect(pass.summary!.readMs, 900);
    expect(pass.summary!.books, 3);
  });

  test('SNO-F-IDX-04: простой с открытой книгой во время чтения не '
      'считается', () async {
    int now = 0;
    final _Volume a = await shelve('a', pagesOf('артерии', 4));
    final ShelfReading pass = reading(nowMs: () => now);
    a.onRead = (int page) async {
      now += 100;
      if (page == 2) {
        pass.held = true;
      }
    };
    pass.start();
    while (pass.progress.phase != ShelfReadingPhase.held) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // Книгу читали десять минут.
    now += 600000;
    pass.held = false;
    await pass.settled();
    expect(pass.summary!.readMs, 400);
  });

  test('SNO-F-IDX-04: книги, вставшие на полку во время прохода, '
      'читаются следом', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 3));
    final ShelfReading pass = reading();
    _Volume? added;
    a.onRead = (int page) async {
      if (page == 2 && added == null) {
        // Архив добавили второй раз, пока шёл проход.
        added = await shelve('late', pagesOf('вены', 2));
        pass.start();
      }
    };
    pass.start();
    await pass.settled();
    expect(added!.textReads.keys.toSet(), <int>{1, 2});
    expect(pass.summary!.books, 2);
    expect(pass.summary!.pages, 5);
  });

  test('SNO-F-IDX-04: итог переживает перезапуск', () async {
    await shelve('a', pagesOf('артерии', 2));
    await shelve('scan', <String>['', '']);
    await shelve('gone', pagesOf('вены', 2));
    opener.missing.add('/books/gone.pdf');
    final ShelfReading pass = reading();
    pass.start();
    await pass.settled();
    final ShelfIndexSummary before = pass.summary!;

    final ShelfReading again = reading();
    expect(again.summary, isNull);
    await again.restore();
    final ShelfIndexSummary after = again.summary!;
    expect(after.complete, before.complete);
    expect(after.books, 2);
    expect(after.pages, 4);
    expect(after.scans, 1);
    expect(after.unread, <String>['Том gone']);
    expect(after.readMs, before.readMs);
    expect(after.map!.state, before.map!.state);
    expect(after.map!.fingerprint, before.map!.fingerprint);
  });

  test('SNO-F-IDX-04: запись итога читается, а мусор — нет', () {
    const ShelfIndexSummary summary = ShelfIndexSummary(
      complete: true,
      books: 40,
      pages: 16212,
      scans: 3,
      unread: <String>['Атлас', 'Том 2'],
      readMs: 400000,
      map: MapSummary(
        state: MapSummary.built,
        books: 40,
        groups: 2,
        ms: 1400,
        fingerprint: '5f3a9c1e',
      ),
    );
    final ShelfIndexSummary back = ShelfIndexSummary.decode(summary.encode())!;
    expect(back.complete, isTrue);
    expect(back.books, 40);
    expect(back.pages, 16212);
    expect(back.scans, 3);
    expect(back.unread, <String>['Атлас', 'Том 2']);
    expect(back.readMs, 400000);
    expect(back.map!.state, MapSummary.built);
    expect(back.map!.books, 40);
    expect(back.map!.groups, 2);
    expect(back.map!.ms, 1400);
    expect(back.map!.fingerprint, '5f3a9c1e');

    expect(ShelfIndexSummary.decode(null), isNull);
    expect(ShelfIndexSummary.decode(''), isNull);
    expect(ShelfIndexSummary.decode('не JSON'), isNull);
    expect(ShelfIndexSummary.decode('[1, 2]'), isNull);
    expect(ShelfIndexSummary.decode('{"schema": "чужая/9"}'), isNull);
    // Запись без карты — итог без карты.
    final ShelfIndexSummary bare = ShelfIndexSummary.decode(
      '{"schema": "${ShelfIndexSummary.schema}", "books": "много"}',
    )!;
    expect(bare.books, 0);
    expect(bare.complete, isFalse);
    expect(bare.map, isNull);
  });

  test('SNO-F-IDX-04: настройки не пишутся и не читаются — проход '
      'идёт', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 2));
    settings.failReads = true;
    settings.failWrites = true;
    final ShelfReading pass = reading();
    await pass.restore();
    expect(pass.summary, isNull);
    pass.start();
    await pass.settled();
    expect(a.textReads.keys.toSet(), <int>{1, 2});
    expect(pass.summary!.complete, isTrue);
    expect(settings.values[SnoSettingsKeys.shelfIndex], isNull);
  });

  test('SNO-F-IDX-04: снятая подготовка останавливается и ничего не '
      'роняет', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 6));
    final ShelfReading pass = reading();
    a.onRead = (int page) async {
      if (page == 3) {
        pass.dispose();
      }
    };
    pass.start();
    await pass.settled();
    made.remove(pass);
    expect(a.textReads.keys.toSet(), <int>{1, 2, 3});
    expect(a.closes, 1);
  });

  test('SNO-F-IDX-04: отложенное начало ждёт своего срока', () async {
    final _Volume a = await shelve('a', pagesOf('артерии', 2));
    final ShelfReading pass = reading();
    pass.start(delay: const Duration(milliseconds: 60));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(a.opens, 0);
    expect(pass.progress.phase, ShelfReadingPhase.idle);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await pass.settled();
    expect(a.textReads.keys.toSet(), <int>{1, 2});
  });
}
