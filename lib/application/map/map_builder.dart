import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/map/book_bag.dart';
import '../../domain/map/book_map.dart';
import '../../domain/map/book_passport.dart';
import '../../domain/map/file_passport.dart';
import '../../domain/map/map_layout.dart';
import '../../domain/map/map_seating.dart';
import '../../domain/map/map_trusted.dart';
import '../../domain/map/map_vectors.dart';
import '../../domain/map/text_trust.dart';
import '../../domain/reading/page_text.dart';

/// Собирает мешок слов одной книги.
typedef BagRunner = Future<BookBag> Function(BagRequest request);

/// Считает карту по мешкам книг.
typedef MapRunner = Future<BookMap?> Function(List<BookBag> bags);

/// Досаживает новые книги к готовой карте (ALG-MAP-08): [kept] —
/// прежние места книг, которые свои места сохраняют.
typedef SeatRunner = Future<BookMap?> Function(
  List<BookBag> bags,
  Map<String, MapPoint> kept,
);

/// Судит текст книги (F-MAP-18): `null` — язык книги без словаря, она
/// идёт в карту как есть.
typedef TrustRunner = Future<TextTrust?> Function(
  List<String> pages,
  Lexicon lexicon,
  List<PageKind>? kinds,
);

/// Мешок книги в фоновом изоляте: разбор текста толстого учебника —
/// доли секунды чистого счёта, и на главном потоке это рывок полки.
Future<BookBag> bagInIsolate(BagRequest request) {
  return Isolate.run(() => bagOfBook(request));
}

/// Суд над текстом книги в фоновом изоляте: регулярное выражение и
/// поиск в словаре по каждому слову толстой книги — заметный рывок на
/// главном потоке. Словарь уходит в изолят копией (~4 МБ байтов —
/// миллисекунда).
Future<TextTrust?> trustInIsolate(
  List<String> pages,
  Lexicon lexicon,
  List<PageKind>? kinds,
) {
  return Isolate.run(() => judgeText(pages, lexicon, kinds));
}

/// Суд над текстом на месте: язык без словаря — `null`.
TextTrust? judgeText(
  List<String> pages,
  Lexicon lexicon,
  List<PageKind>? kinds,
) {
  return hasLexiconScript(pages)
      ? textTrustOf(pages, lexicon, kinds: kinds)
      : null;
}

/// Карта в фоновом изоляте: разложение и раскладка — секунды счёта.
Future<BookMap?> mapInIsolate(List<BookBag> bags) {
  return Isolate.run(() => buildBookMap(bags));
}

/// Досадка в фоновом изоляте: разложение — то же, что у полной карты.
Future<BookMap?> seatInIsolate(List<BookBag> bags, Map<String, MapPoint> kept) {
  return Isolate.run(() => seatBooks(bags, kept));
}

/// Сколько страниц читается из кэша текста одним запросом.
const int kMapTextBatch = 64;

/// Книга как вход расчёта карты.
class MapSource {
  /// Создаёт запись.
  const MapSource({
    required this.book,
    required this.group,
    required this.cachedPages,
    required this.lastPage,
    this.pageNumbers = const <int>[],
  });

  /// Книга полки.
  final Book book;

  /// Название её категории; пусто — «Без категории».
  final String group;

  /// Сколько страниц книги лежит в кэше текста.
  final int cachedPages;

  /// Последняя запомненная страница; ноль — текста нет.
  final int lastPage;

  /// Номера запомненных страниц по возрастанию — по ним вид страницы из
  /// паспорта сопоставляется с её текстом (F-MAP-18).
  final List<int> pageNumbers;
}

/// Что известно о карте до расчёта.
class MapPlan {
  /// Создаёт план.
  const MapPlan({
    required this.sources,
    required this.key,
    required this.current,
  });

  /// Книги полки, по возрастанию отпечатка файла.
  final List<MapSource> sources;

  /// Ключ набора: по нему карта узнаёт, что считалась по этим же книгам.
  final String key;

  /// Карта на устройстве, если она посчитана по этому набору этой
  /// версией расчёта; `null` — карты нет или она устарела.
  final MapOutcome? current;

  /// Свежа ли карта.
  bool get upToDate => current != null;
}

/// Чем кончился расчёт карты.
enum MapOutcomeKind {
  /// Карта посчитана и лежит на устройстве.
  built,

  /// Книг меньше [kMinMapBooks]: карты нет.
  tooFew,

  /// Книг больше [kExactBooksLimit]: карты нет.
  tooMany,

  /// Расчёт остановили.
  stopped,
}

/// Итог расчёта карты.
class MapOutcome {
  /// Создаёт итог.
  const MapOutcome({
    required this.kind,
    this.books = 0,
    this.groups = 0,
    this.fingerprint = '',
    this.seated = 0,
  });

  /// Чем кончилось.
  final MapOutcomeKind kind;

  /// Сколько книг досажено этим расчётом (ALG-MAP-08); ноль — карта
  /// посчитана целиком или только сняты убранные книги.
  final int seated;

  /// Сколько книг на карте.
  final int books;

  /// Сколько групп на карте.
  final int groups;

  /// Отпечаток карты; пусто — карты нет.
  final String fingerprint;
}

/// Считает карту книг полки и кладёт её на устройство (F-MAP-02,
/// SNO-F-MAP-01).
///
/// Текст книг берётся из кэша текста страниц — к движку PDF расчёт не
/// ходит: кэш наполняет проход по полке (`shelf_reading.dart`)
/// или открытая книга. Книга, у которой текста в кэше нет, получает
/// место по одному названию.
///
/// Карта **стабильна**: пересчитывается, только когда изменился набор
/// книг, их названия, запомненный текст или версия расчёта, — всё это
/// сложено в ключ набора.
///
/// И пересчёт не перекладывает карту (F-MAP-04, D-049): новые и
/// изменившиеся книги досаживаются к прежним звёздам (`map_seating.dart`),
/// убранные просто снимаются. Заново, как в первый раз, карта считается,
/// когда карты нет, поднялась версия расчёта, читатель нажал
/// «Перестроить» или изменилось больше четверти книг.
class MapBuilder {
  /// Создаёт расчёт.
  ///
  /// [bags] и [layout] в тестах подменяются счётом на месте: изолят под
  /// подменённым временем widget-тест не дожидается.
  MapBuilder({
    required LibraryRepository library,
    required CategoryRepository categories,
    required PageTextRepository texts,
    required BookMapRepository store,
    BagRunner bags = bagInIsolate,
    MapRunner layout = mapInIsolate,
    SeatRunner seat = seatInIsolate,
    bool seating = true,
    int textVersion = kPageTextVersion,
    PassportRepository? passports,
    PassportReader? passportReader,
    Future<Lexicon> Function()? lexicon,
    TrustRunner trust = trustInIsolate,
  }) : _trust = trust,
       _passports = passports,
       _passportReader = passportReader,
       _lexiconLoader = lexicon,
       _library = library,
       _categories = categories,
       _texts = texts,
       _store = store,
       _bags = bags,
       _layout = layout,
       _seat = seat,
       _seating = seating,
       _textVersion = textVersion;

  final LibraryRepository _library;
  final CategoryRepository _categories;
  final PageTextRepository _texts;
  final BookMapRepository _store;
  final BagRunner _bags;
  final MapRunner _layout;
  final SeatRunner _seat;

  /// Досаживать ли книги (D-049); `false` — любая перемена считает карту
  /// заново, как до S60 (ветвь II СНО2026: кнопки «Перестроить» там нет,
  /// и ответвление новым не меняется).
  final bool _seating;
  final int _textVersion;

  /// Паспорт и доверие (F-MAP-18). Без хранилища и словаря текст не
  /// судится — книги идут в карту как есть (так в тестах прежних шагов).
  final PassportRepository? _passports;
  final PassportReader? _passportReader;
  final Future<Lexicon> Function()? _lexiconLoader;
  final TrustRunner _trust;
  Lexicon? _lexicon;

  /// Ключ набора книг: SHA-256 от версий и от каждой книги — отпечаток
  /// файла, группа, название, автор, сколько её страниц запомнено.
  ///
  /// В ключе всё, от чего зависит карта, и ничего сверх: идентификатора
  /// книги в нём нет — он у каждого устройства свой, а карта общая.
  static String keyOf(List<MapSource> sources, {required int textVersion}) {
    final StringBuffer text = StringBuffer()
      ..write('map/$kBookMapVersion/text/$textVersion/passport/')
      ..write('$kPassportVersion\n');
    for (final MapSource source in sources) {
      text
        ..write(source.book.fileHash)
        ..write('\u001f')
        ..write(source.book.title)
        ..write('\u001f')
        ..write(source.book.author ?? '')
        ..write('\u001f')
        ..write(source.cachedPages)
        ..write('\n');
    }
    return sha256.convert(utf8.encode(text.toString())).toString();
  }

  /// Отпечаток входа книги — того, от чего зависит её место: версии
  /// текста и паспорта, название, автор, сколько страниц запомнено.
  ///
  /// Лежит у точки карты (`MapPoint.input`): изменился — книга
  /// досаживается заново (ALG-MAP-08), остальные стоят.
  static String inputOf(MapSource source, {required int textVersion}) {
    final String text =
        'text/$textVersion/passport/$kPassportVersion\u001f'
        '${source.book.title}\u001f${source.book.author ?? ''}\u001f'
        '${source.cachedPages}';
    return sha256.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  /// Смотрит, по каким книгам считать карту и свежа ли лежащая.
  Future<MapPlan> plan() async {
    final List<Book> books = await _library.books();
    final Map<String, String> titles = <String, String>{
      for (final BookCategory category in await _categories.categories())
        category.id: category.title,
    };
    // Одна книга — один отпечаток; повтор отпечатка на полке быть не
    // должен, а случись он — второй книге на карте места нет.
    final Map<String, Book> byHash = <String, Book>{};
    for (final Book book in books) {
      byHash.putIfAbsent(book.fileHash, () => book);
    }
    final List<String> hashes = byHash.keys.toList()..sort();
    final List<MapSource> sources = <MapSource>[];
    for (final String hash in hashes) {
      final Book book = byHash[hash]!;
      final Map<int, int> cached = await _texts.cachedPages(_keyOf(book));
      int last = 0;
      for (final int page in cached.keys) {
        if (page > last) {
          last = page;
        }
      }
      sources.add(
        MapSource(
          book: book,
          group: titles[book.categoryId] ?? '',
          cachedPages: cached.length,
          lastPage: last,
          pageNumbers: cached.keys.toList()..sort(),
        ),
      );
    }
    final String key = keyOf(sources, textVersion: _textVersion);
    return MapPlan(
      sources: sources,
      key: key,
      current: await _current(sources, key),
    );
  }

  /// Карта на устройстве, если она посчитана по набору [sources].
  Future<MapOutcome?> _current(List<MapSource> sources, String key) async {
    final StoredBookMap? stored = await _store.load();
    if (stored == null ||
        stored.version != kBookMapVersion ||
        stored.layoutKey != key ||
        stored.points.length != sources.length) {
      return null;
    }
    final List<MapPoint> points = <MapPoint>[];
    for (final MapSource source in sources) {
      final MapPoint? point = stored.points[source.book.id];
      if (point == null || point.key != source.book.fileHash) {
        return null;
      }
      points.add(point);
    }
    return MapOutcome(
      kind: MapOutcomeKind.built,
      books: points.length,
      groups: _groupsOf(points),
      fingerprint: mapFingerprint(points),
    );
  }

  /// Сколько групп на карте — созвездий; книги без созвездия — тоже
  /// группа (F-MAP-16).
  int _groupsOf(List<MapPoint> points) {
    return <int>{for (final MapPoint point in points) point.constellation}
        .length;
  }

  PageTextKey _keyOf(Book book) {
    return PageTextKey(
      bookId: book.id,
      fingerprint: book.fileHash,
      version: _textVersion,
    );
  }

  /// Считает карту по плану [plan] и кладёт её на устройство.
  ///
  /// [onProgress] зовётся после каждой разобранной книги: сколько
  /// разобрано и сколько всего. [stopped] спрашивается между книгами:
  /// `true` — расчёт бросается, прежняя карта остаётся как была.
  /// [fresh] — «Перестроить» (F-MAP-04): карта считается заново, как в
  /// первый раз, даже если книги можно досадить.
  Future<MapOutcome> build(
    MapPlan plan, {
    void Function(int done, int total)? onProgress,
    bool Function()? stopped,
    Future<bool> Function()? turn,
    bool fresh = false,
  }) async {
    final List<MapSource> sources = plan.sources;
    if (sources.length < kMinMapBooks) {
      await _store.clear();
      return const MapOutcome(kind: MapOutcomeKind.tooFew);
    }
    if (sources.length > kExactBooksLimit) {
      await _store.clear();
      return const MapOutcome(kind: MapOutcomeKind.tooMany);
    }
    final Map<String, String> inputs = <String, String>{
      for (final MapSource source in sources)
        source.book.id: inputOf(source, textVersion: _textVersion),
    };
    // ALG-MAP-08, D-049: какие книги сохраняют места. «Перестроить» —
    // ни одна.
    final Map<String, MapPoint> kept = fresh || !_seating
        ? const <String, MapPoint>{}
        : await _keptPlaces(sources, inputs);
    final int changed = sources.length - kept.length;
    if (changed == 0) {
      // Книги только убрали (или ключ набора сменился без перемен в
      // книгах): убранные снимаются, остальные стоят — считать нечего.
      return _keep(plan, sources, kept, inputs);
    }
    final bool seating = seatingFits(kept: kept.length, changed: changed);
    final List<BookBag> bags = <BookBag>[];
    for (int i = 0; i < sources.length; i++) {
      // Своя очередь к движку PDF (паспорт файла): пока открыта книга,
      // расчёт ждёт; `false` — расчёт сняли.
      if (turn != null && !await turn()) {
        return const MapOutcome(kind: MapOutcomeKind.stopped);
      }
      if (stopped?.call() ?? false) {
        return const MapOutcome(kind: MapOutcomeKind.stopped);
      }
      final MapSource source = sources[i];
      final List<String> pages = await _pagesOf(source);
      final PassportRecord? record = await _trustOf(source, pages);
      final BookTrust trust = record?.bookTrust ?? const BookTrust.asIs();
      final BookBag bag = await _bags(
        BagRequest(
          key: source.book.fileHash,
          group: source.group,
          title: source.book.title,
          author: source.book.author,
          pages: _trustedPages(pages, record),
        ),
      );
      bags.add(bag.withTrust(trust));
      onProgress?.call(i + 1, sources.length);
    }
    if (stopped?.call() ?? false) {
      return const MapOutcome(kind: MapOutcomeKind.stopped);
    }
    final BookMap? map = seating
        ? await _seat(bags, kept)
        : await _layout(bags);
    if (map == null) {
      await _store.clear();
      return const MapOutcome(kind: MapOutcomeKind.tooFew);
    }
    await _save(plan, sources, map.points, inputs);
    return MapOutcome(
      kind: MapOutcomeKind.built,
      books: map.points.length,
      groups: map.groups,
      fingerprint: map.fingerprint,
      seated: seating ? changed : 0,
    );
  }

  /// Прежние места книг [sources], которые их сохраняют (ALG-MAP-08):
  /// отпечаток файла → точка. Место сохраняет книга, у которой точка
  /// лежит на устройстве, посчитана этой версией расчёта, и вход книги
  /// с тех пор не изменился. Карты нет или версия другая — ни одна.
  Future<Map<String, MapPoint>> _keptPlaces(
    List<MapSource> sources,
    Map<String, String> inputs,
  ) async {
    final StoredBookMap? stored = await _store.load();
    if (stored == null || stored.version != kBookMapVersion) {
      return const <String, MapPoint>{};
    }
    // Точка ищется по книге, а если её нет — по файлу: у двух книг
    // полки с одним файлом место одно (`plan`), и если «первую» убрали,
    // вторая наследует её звезду, а не досаживается заново.
    final Map<String, MapPoint> byFile = <String, MapPoint>{
      for (final MapPoint point in stored.points.values) point.key: point,
    };
    final Map<String, MapPoint> kept = <String, MapPoint>{};
    for (final MapSource source in sources) {
      final MapPoint? point =
          stored.points[source.book.id] ?? byFile[source.book.fileHash];
      if (point != null &&
          point.key == source.book.fileHash &&
          point.input.isNotEmpty &&
          point.input == inputs[source.book.id]) {
        kept[point.key] = point;
      }
    }
    return kept;
  }

  /// Все книги сохраняют места: карта кладётся без убранных, под новым
  /// ключом набора.
  Future<MapOutcome> _keep(
    MapPlan plan,
    List<MapSource> sources,
    Map<String, MapPoint> kept,
    Map<String, String> inputs,
  ) async {
    final List<MapPoint> points = <MapPoint>[
      for (final MapSource source in sources) kept[source.book.fileHash]!,
    ];
    await _save(plan, sources, points, inputs);
    return MapOutcome(
      kind: MapOutcomeKind.built,
      books: points.length,
      groups: _groupsOf(points),
      fingerprint: mapFingerprint(points),
    );
  }

  /// Кладёт точки [points] на устройство: у книги — её точка с
  /// отпечатком входа.
  Future<void> _save(
    MapPlan plan,
    List<MapSource> sources,
    List<MapPoint> points,
    Map<String, String> inputs,
  ) async {
    final Map<String, MapPoint> byKey = <String, MapPoint>{
      for (final MapPoint point in points) point.key: point,
    };
    await _store.replace(
      StoredBookMap(
        layoutKey: plan.key,
        version: kBookMapVersion,
        points: <String, MapPoint>{
          for (final MapSource source in sources)
            if (byKey[source.book.fileHash] case final MapPoint point)
              source.book.id: point.withInput(inputs[source.book.id]!),
        },
      ),
    );
  }

  /// Паспорт и доверие книги (F-MAP-18): из хранилища, а если их нет
  /// или текст книги с тех пор дочитан — считаются и кладутся туда.
  /// `null` — судить нечем (нет хранилища или словаря).
  Future<PassportRecord?> _trustOf(MapSource source, List<String> pages) async {
    final PassportRepository? store = _passports;
    if (store == null || _lexiconLoader == null) {
      return null;
    }
    final String fingerprint = source.book.fileHash;
    PassportRecord? record = await store.load(fingerprint);
    // Записывать ли паспорт: прочитанный (или «файл битый») — да, это
    // навсегда; «до файла не добраться» — нет, прочитаем в другой раз.
    bool lasting = true;
    if (record == null || record.version != kPassportVersion) {
      // Паспорт — один проход по PDF; дальше он не повторяется.
      FilePassport? passport;
      try {
        passport = await _passportReader?.read(source.book.source);
      } on Object {
        // Нет доступа к файлу, нет пути, сбой движка — всё это может
        // пройти: без паспорта сейчас, без записи.
        passport = null;
        lasting = false;
      }
      record = PassportRecord(
        fingerprint: fingerprint,
        version: kPassportVersion,
        passport: passport,
      );
    } else if (record.trustFits(_textVersion, source.cachedPages)) {
      return record;
    }
    // Судить текст можно, только когда он запомнен целиком: у книги,
    // дочитанной до десятой страницы, «мало надёжного текста» значило бы
    // «ещё не дочитали». До того книга идёт в карту как есть.
    final int? total = source.book.pageCount;
    if (total == null || total <= 0 || source.cachedPages < total) {
      final PassportRecord pending = PassportRecord(
        fingerprint: fingerprint,
        version: kPassportVersion,
        passport: record.passport,
      );
      if (lasting) await store.save(pending);
      return pending;
    }
    final Lexicon? lexicon = await _lexiconOrNull();
    if (lexicon == null) {
      // Словарь не загрузился: судить нечем — книга как есть (изящная
      // деградация, правило 5). Паспорт записывается, доверие — нет: оно
      // посчитается, когда словарь загрузится.
      final PassportRecord pending = PassportRecord(
        fingerprint: fingerprint,
        version: kPassportVersion,
        passport: record.passport,
      );
      if (lasting) await store.save(pending);
      return pending;
    }
    final List<PageKind>? kinds = record.passport?.pageKinds;
    final TextTrust? trust = await _trust(
      pages,
      lexicon,
      kinds == null ? null : _kindsOf(source, kinds),
    );
    record = record.withTrust(
      trust,
      textVersion: _textVersion,
      pages: source.cachedPages,
    );
    if (lasting) await store.save(record);
    return record;
  }

  /// Словарь — загружается один раз за жизнь расчёта; не загрузился —
  /// `null`, и попытка повторится при следующем расчёте.
  Future<Lexicon?> _lexiconOrNull() async {
    final Lexicon? have = _lexicon;
    if (have != null) return have;
    try {
      return _lexicon = await _lexiconLoader!();
    } on Object {
      return null;
    }
  }

  /// Вид запомненных страниц по паспорту — в том же порядке, что их
  /// тексты: запомнены могут быть не все страницы книги.
  List<PageKind> _kindsOf(MapSource source, List<PageKind> kinds) {
    return <PageKind>[
      for (final int page in source.pageNumbers)
        page - 1 < kinds.length ? kinds[page - 1] : PageKind.text,
    ];
  }

  /// Какие страницы идут в мешок (F-MAP-18): у книги, чей текст судили,
  /// — только «да» и «коротко»; без надёжного текста — ни одной (мешок
  /// из названия и автора).
  List<String> _trustedPages(List<String> pages, PassportRecord? record) {
    if (record == null || record.trustKind == TrustKind.asIs) {
      return pages;
    }
    if (record.trustKind == TrustKind.littleText) {
      return const <String>[];
    }
    final List<PageTrust> states = record.pageTrust;
    if (states.length != pages.length) {
      return pages;
    }
    return <String>[
      for (int i = 0; i < pages.length; i++)
        if (states[i] == PageTrust.yes || states[i] == PageTrust.short)
          pages[i],
    ];
  }

  /// Запомненный текст страниц книги, по порядку страниц.
  Future<List<String>> _pagesOf(MapSource source) async {
    final List<String> pages = <String>[];
    final PageTextKey key = _keyOf(source.book);
    for (int from = 1; from <= source.lastPage; from += kMapTextBatch) {
      final int to = from + kMapTextBatch - 1 > source.lastPage
          ? source.lastPage
          : from + kMapTextBatch - 1;
      final Map<int, String> texts = await _texts.pageTexts(
        key,
        from: from,
        to: to,
      );
      final List<int> numbers = texts.keys.toList()..sort();
      for (final int number in numbers) {
        pages.add(texts[number]!);
      }
    }
    return pages;
  }
}
