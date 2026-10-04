import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/book_text.dart';
import 'package:memoria/domain/reading/page_text.dart';

import '../support/fake_reading.dart';

/// F-TEXT-04, ALG-TXT-09: текст страниц книги — производный артефакт.
///
/// Здесь — кэш без экрана и без базы: подставной документ считает,
/// сколько раз читали каждую страницу, хранилище в памяти — сколько раз
/// писали. По этим счётчикам и видно главное: страница читается движком
/// один раз за жизнь книги на устройстве.
void main() {
  const String bookId = 'book-1';
  const String hash = 'hash-1';

  FakeReaderDocument book({int pages = 40}) {
    return FakeReaderDocument(
      pages: List<String>.generate(pages, (int i) => 'страница ${i + 1}'),
    );
  }

  BookTextCache cacheOf(
    FakeReaderDocument document,
    MemoryPageTextStore store, {
    String fingerprint = hash,
    int version = kPageTextVersion,
    int passBatch = kTextPassBatch,
  }) {
    return BookTextCache(
      document: document,
      store: store,
      bookId: bookId,
      fingerprint: fingerprint,
      version: version,
      passBatch: passBatch,
    );
  }

  /// Сколько раз движок читал страницы — всего.
  int reads(FakeReaderDocument document) {
    int total = 0;
    for (final int count in document.textReads.values) {
      total += count;
    }
    return total;
  }

  group('F-TEXT-04: текст страниц по запросу', () {
    test('первый раз читает движок, второй — база', () async {
      final FakeReaderDocument document = book();
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);

      final Map<int, String> first = await cache.textsOf(1, 8);
      expect(first.keys, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(first[3], 'страница 3');
      expect(reads(document), 8);
      expect(cache.cachedCount, 8);

      final Map<int, String> second = await cache.textsOf(1, 8);
      expect(second, first);
      expect(reads(document), 8, reason: 'к движку второй раз не ходили');
      expect(store.textQueries, 1);
    });

    test('половина в кэше — движком читается только остаток', () async {
      final FakeReaderDocument document = book();
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);
      await cache.textsOf(5, 8);
      document.textReads.clear();

      final Map<int, String> texts = await cache.textsOf(1, 12);

      expect(texts.length, 12);
      expect(texts[6], 'страница 6');
      expect(document.textReads.keys.toSet(), <int>{1, 2, 3, 4, 9, 10, 11, 12});
      expect(cache.cachedCount, 12);
    });

    test('страницы за краем книги не спрашиваются', () async {
      final FakeReaderDocument document = book(pages: 5);
      final BookTextCache cache = cacheOf(document, MemoryPageTextStore());

      final Map<int, String> texts = await cache.textsOf(-3, 99);

      expect(texts.keys, <int>[1, 2, 3, 4, 5]);
      expect(await cache.textsOf(6, 9), isEmpty);
    });

    test('новое открытие книги берёт запомненное из базы', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache before = cacheOf(book(), store);
      await before.textsOf(1, 40);
      before.close();

      final FakeReaderDocument document = book();
      final BookTextCache after = cacheOf(document, store);
      await after.load();
      expect(after.isComplete, isTrue);
      expect(after.cachedCount, 40);

      final Map<int, String> texts = await after.textsOf(17, 24);
      expect(texts[20], 'страница 20');
      expect(reads(document), 0, reason: 'движок не понадобился вовсе');
    });

    test('страница без текста запоминается пустой — это тоже ответ', () async {
      // Скан без текстового слоя: кэш пустой, и это не ошибка.
      final FakeReaderDocument document = FakeReaderDocument.blank(6);
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);

      await cache.textsOf(1, 6);
      expect(cache.isComplete, isTrue);
      expect(cache.cachedSize, 0);
      expect(store.rowCount(bookId), 6);

      await cache.textsOf(1, 6);
      expect(reads(document), 6, reason: 'за пустыми страницами не ходят');
    });

    test('нечитаемая страница приходит пустой и не запоминается', () async {
      final _BrokenPageDocument document = _BrokenPageDocument();
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);

      final Map<int, String> texts = await cache.textsOf(1, 3);

      expect(texts, <int, String>{1: 'начало', 2: '', 3: 'здесь цель'});
      expect(cache.isCached(1), isTrue);
      expect(cache.isCached(2), isFalse, reason: 'попробуют ещё раз');
      expect(cache.isCached(3), isTrue);
      expect(store.rowCount(bookId), 2);
    });
  });

  group('F-TEXT-04: версия алгоритма и отпечаток файла', () {
    test('совпавшая версия не пересчитывает ничего', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      await cacheOf(book(), store).textsOf(1, 40);
      final int saved = store.savedPages;

      final FakeReaderDocument document = book();
      final BookTextCache cache = cacheOf(document, store);
      cache.startPass(from: 1);
      await cache.passDone();

      expect(reads(document), 0);
      expect(store.savedPages, saved);
    });

    test('поднятая версия пересчитывает только отставшее', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      // Первые десять страниц запомнены прежним алгоритмом, следующие
      // десять — нынешним.
      await cacheOf(book(), store, version: 1).textsOf(1, 10);
      await cacheOf(book(), store, version: 2).textsOf(11, 20);

      final FakeReaderDocument document = book();
      final BookTextCache cache = cacheOf(document, store, version: 2);
      await cache.load();
      expect(cache.cachedCount, 10, reason: 'прежняя версия — не в счёт');

      cache.startPass(from: 1);
      await cache.passDone();

      expect(cache.isComplete, isTrue);
      expect(
        document.textReads.keys.where((int page) => page >= 11 && page <= 20),
        isEmpty,
        reason: 'запомненное нынешним алгоритмом не перечитывается',
      );
      expect(reads(document), 30);
      expect(store.rowCount(bookId), 40, reason: 'новое легло поверх старого');
    });

    test('другой файл у книги — прежний текст не годится', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      await cacheOf(book(), store).textsOf(1, 40);

      final FakeReaderDocument document = FakeReaderDocument(
        pages: List<String>.generate(40, (int i) => 'другой файл ${i + 1}'),
      );
      final BookTextCache cache = cacheOf(
        document,
        store,
        fingerprint: 'hash-2',
      );
      await cache.load();
      expect(cache.cachedCount, 0);

      final Map<int, String> texts = await cache.textsOf(1, 8);
      expect(texts[1], 'другой файл 1');
      expect(reads(document), 8);
    });
  });

  group('F-TEXT-04: фоновый проход', () {
    test('идёт вперёд от места чтения, потом — с начала книги', () async {
      final FakeReaderDocument document = book(pages: 10);
      final List<int> order = <int>[];
      final _OrderedDocument watched = _OrderedDocument(document, order);
      final BookTextCache cache = BookTextCache(
        document: watched,
        store: MemoryPageTextStore(),
        bookId: bookId,
        fingerprint: hash,
      );

      cache.startPass(from: 7);
      await cache.passDone();

      expect(order, <int>[7, 8, 9, 10, 1, 2, 3, 4, 5, 6]);
      expect(cache.isComplete, isTrue);
      expect(cache.isPassing, isFalse);
    });

    test('запомненные страницы пропускает', () async {
      final FakeReaderDocument document = book(pages: 20);
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);
      await cache.textsOf(5, 12);
      document.textReads.clear();

      cache.startPass(from: 1);
      await cache.passDone();

      expect(reads(document), 12);
      expect(
        document.textReads.keys.where((int page) => page >= 5 && page <= 12),
        isEmpty,
      );
      expect(cache.isComplete, isTrue);
    });

    test('двойной запуск не дублирует работу', () async {
      final FakeReaderDocument document = book(pages: 30);
      final BookTextCache cache = cacheOf(document, MemoryPageTextStore());

      cache.startPass(from: 1);
      cache.startPass(from: 15);
      cache.startPass(from: 1);
      await cache.passDone();

      expect(document.textReads.length, 30);
      expect(
        document.textReads.values.every((int count) => count == 1),
        isTrue,
        reason: 'каждая страница прочитана ровно один раз',
      );
    });

    test('уход из книги останавливает, возвращение продолжает', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      final FakeReaderDocument first = book(pages: 64);
      late final BookTextCache leaving;
      // Книгу закрывают, когда проход добрался до тридцатой страницы.
      final _OrderedDocument watched = _OrderedDocument(
        first,
        <int>[],
        onRead: (int page) {
          if (page == 30) {
            leaving.close();
          }
        },
      );
      leaving = BookTextCache(
        document: watched,
        store: store,
        bookId: bookId,
        fingerprint: hash,
        passBatch: 8,
      );
      leaving.startPass(from: 1);
      await leaving.passDone();

      final int kept = store.rowCount(bookId);
      expect(kept, greaterThanOrEqualTo(24), reason: 'записанное — на месте');
      expect(kept, lessThan(64), reason: 'проход остановлен');
      expect(reads(first), lessThanOrEqualTo(31));

      // Книгу открыли снова: проход читает только то, чего в базе нет.
      final FakeReaderDocument second = book(pages: 64);
      final BookTextCache back = cacheOf(second, store, passBatch: 8);
      back.startPass(from: 1);
      await back.passDone();

      expect(back.isComplete, isTrue);
      expect(reads(second), 64 - kept);
      expect(store.rowCount(bookId), 64);
    });

    test('остановленный проход прочитанное записывает', () async {
      final MemoryPageTextStore store = MemoryPageTextStore();
      late final BookTextCache cache;
      final _OrderedDocument watched = _OrderedDocument(
        book(pages: 40),
        <int>[],
        onRead: (int page) {
          if (page == 5) {
            cache.stopPass();
          }
        },
      );
      cache = BookTextCache(
        document: watched,
        store: store,
        bookId: bookId,
        fingerprint: hash,
      );
      cache.startPass(from: 1);
      // Проход остановлен, но не оборван на полуслове: дождаться его
      // можно только по базе.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cache.isPassing, isFalse);
      expect(store.rowCount(bookId), 5);

      // И запускается заново — с того, что осталось.
      cache.startPass(from: 1);
      await cache.passDone();
      expect(cache.isComplete, isTrue);
    });

    test('поиск и проход за одной страницей к движку идут один раз', () async {
      final FakeReaderDocument document = book(pages: 24);
      final BookTextCache cache = cacheOf(document, MemoryPageTextStore());

      cache.startPass(from: 1);
      final Map<int, String> texts = await cache.textsOf(1, 24);
      await cache.passDone();

      expect(texts.length, 24);
      expect(
        document.textReads.values.every((int count) => count == 1),
        isTrue,
      );
    });
  });

  group('F-TEXT-04: база отказала — книга читается', () {
    test('не читается: текст приходит из движка', () async {
      final FakeReaderDocument document = book(pages: 8);
      final MemoryPageTextStore store = MemoryPageTextStore()..failReads = true;
      final BookTextCache cache = cacheOf(document, store);

      final Map<int, String> texts = await cache.textsOf(1, 8);

      expect(texts[8], 'страница 8');
      expect(reads(document), 8);
    });

    test('не пишется: текст отдан, но страницы не запомнены', () async {
      final FakeReaderDocument document = book(pages: 8);
      final MemoryPageTextStore store = MemoryPageTextStore()
        ..failWrites = true;
      final BookTextCache cache = cacheOf(document, store);

      final Map<int, String> texts = await cache.textsOf(1, 8);
      expect(texts.length, 8);
      expect(cache.cachedCount, 0);

      // База ожила — те же страницы читаются движком ещё раз и ложатся.
      store.failWrites = false;
      await cache.textsOf(1, 8);
      expect(cache.cachedCount, 8);
      expect(reads(document), 16);
    });

    test('закрытый кэш к движку и к базе не ходит', () async {
      final FakeReaderDocument document = book(pages: 8);
      final MemoryPageTextStore store = MemoryPageTextStore();
      final BookTextCache cache = cacheOf(document, store);
      cache.close();

      cache.startPass(from: 1);
      await cache.passDone();
      final Map<int, String> texts = await cache.textsOf(1, 8);

      expect(reads(document), 0);
      expect(store.saveCount, 0);
      expect(texts.values.every((String text) => text.isEmpty), isTrue);
    });
  });
}

/// Документ, у которого вторая страница не читается.
class _BrokenPageDocument extends FakeReaderDocument {
  _BrokenPageDocument()
    : super(pages: <String>['начало', 'битая', 'здесь цель']);

  @override
  Future<String> pageText(int pageNumber) {
    if (pageNumber == 2) {
      throw StateError('страница не читается');
    }
    return super.pageText(pageNumber);
  }
}

/// Документ, который записывает порядок чтения страниц.
class _OrderedDocument extends FakeReaderDocument {
  _OrderedDocument(this._inner, this._order, {this.onRead})
    : super(pages: _inner.pages);

  final FakeReaderDocument _inner;
  final List<int> _order;

  /// Зовётся после того, как страница прочитана.
  final void Function(int page)? onRead;

  @override
  Future<String> pageText(int pageNumber) async {
    _order.add(pageNumber);
    final String text = await _inner.pageText(pageNumber);
    onRead?.call(pageNumber);
    return text;
  }
}
