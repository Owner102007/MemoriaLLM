import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/map/book_bag.dart';
import '../../domain/map/book_map.dart';
import '../../domain/map/map_layout.dart';
import '../../domain/map/map_vectors.dart';
import '../../domain/reading/page_text.dart';

/// Собирает мешок слов одной книги.
typedef BagRunner = Future<BookBag> Function(BagRequest request);

/// Считает карту по мешкам книг.
typedef MapRunner = Future<BookMap?> Function(List<BookBag> bags);

/// Мешок книги в фоновом изоляте: разбор текста толстого учебника —
/// доли секунды чистого счёта, и на главном потоке это рывок полки.
Future<BookBag> bagInIsolate(BagRequest request) {
  return Isolate.run(() => bagOfBook(request));
}

/// Карта в фоновом изоляте: разложение и раскладка — секунды счёта.
Future<BookMap?> mapInIsolate(List<BookBag> bags) {
  return Isolate.run(() => buildBookMap(bags));
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
  });

  /// Книга полки.
  final Book book;

  /// Название её категории; пусто — «Без категории».
  final String group;

  /// Сколько страниц книги лежит в кэше текста.
  final int cachedPages;

  /// Последняя запомненная страница; ноль — текста нет.
  final int lastPage;
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
  });

  /// Чем кончилось.
  final MapOutcomeKind kind;

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
/// ходит: кэш наполняет проход по полке (`sno/index/shelf_reading.dart`)
/// или открытая книга. Книга, у которой текста в кэше нет, получает
/// место по одному названию.
///
/// Карта **стабильна**: пересчитывается, только когда изменился набор
/// книг, их категории, названия, запомненный текст или версия расчёта, —
/// всё это сложено в ключ набора.
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
    int textVersion = kPageTextVersion,
  }) : _library = library,
       _categories = categories,
       _texts = texts,
       _store = store,
       _bags = bags,
       _layout = layout,
       _textVersion = textVersion;

  final LibraryRepository _library;
  final CategoryRepository _categories;
  final PageTextRepository _texts;
  final BookMapRepository _store;
  final BagRunner _bags;
  final MapRunner _layout;
  final int _textVersion;

  /// Ключ набора книг: SHA-256 от версий и от каждой книги — отпечаток
  /// файла, группа, название, автор, сколько её страниц запомнено.
  ///
  /// В ключе всё, от чего зависит карта, и ничего сверх: идентификатора
  /// книги в нём нет — он у каждого устройства свой, а карта общая.
  static String keyOf(List<MapSource> sources, {required int textVersion}) {
    final StringBuffer text = StringBuffer()
      ..write('map/$kBookMapVersion/text/$textVersion\n');
    for (final MapSource source in sources) {
      text
        ..write(source.book.fileHash)
        ..write('\u001f')
        ..write(source.group)
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
      groups: _groupsOf(sources),
      fingerprint: mapFingerprint(points),
    );
  }

  int _groupsOf(List<MapSource> sources) {
    return <String>{for (final MapSource source in sources) source.group}
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
  Future<MapOutcome> build(
    MapPlan plan, {
    void Function(int done, int total)? onProgress,
    bool Function()? stopped,
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
    final List<BookBag> bags = <BookBag>[];
    for (int i = 0; i < sources.length; i++) {
      if (stopped?.call() ?? false) {
        return const MapOutcome(kind: MapOutcomeKind.stopped);
      }
      final MapSource source = sources[i];
      bags.add(
        await _bags(
          BagRequest(
            key: source.book.fileHash,
            group: source.group,
            title: source.book.title,
            author: source.book.author,
            pages: await _pagesOf(source),
          ),
        ),
      );
      onProgress?.call(i + 1, sources.length);
    }
    if (stopped?.call() ?? false) {
      return const MapOutcome(kind: MapOutcomeKind.stopped);
    }
    final BookMap? map = await _layout(bags);
    if (map == null) {
      await _store.clear();
      return const MapOutcome(kind: MapOutcomeKind.tooFew);
    }
    final Map<String, MapPoint> byKey = <String, MapPoint>{
      for (final MapPoint point in map.points) point.key: point,
    };
    await _store.replace(
      StoredBookMap(
        layoutKey: plan.key,
        version: kBookMapVersion,
        points: <String, MapPoint>{
          for (final MapSource source in sources)
            if (byKey[source.book.fileHash] != null)
              source.book.id: byKey[source.book.fileHash]!,
        },
      ),
    );
    return MapOutcome(
      kind: MapOutcomeKind.built,
      books: map.points.length,
      groups: map.groups,
      fingerprint: map.fingerprint,
    );
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
