import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/book_text.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_search.dart';

import '../support/fake_reading.dart';

FakeReaderDocument _book({int pages = 30}) {
  return FakeReaderDocument(
    pages: List<String>.generate(
      pages,
      (int i) => i == 4
          ? 'Германн стоял, прислонясь к холодной печке.'
          : 'Обычный текст страницы ${i + 1}.',
    ),
  );
}

void main() {
  test('находит слово и указывает страницу', () async {
    final DocumentSearch search = DocumentSearch(document: _book());
    await search.start('Германн');
    expect(search.hits.length, 1);
    expect(search.hits.single.pageNumber, 5);
    expect(search.isRunning, isFalse);
    expect(search.isFinished, isTrue);
    search.dispose();
  });

  test('результаты идут по возрастанию страниц', () async {
    final DocumentSearch search = DocumentSearch(
      document: FakeReaderDocument(
        pages: <String>['слово', 'мимо', 'слово', 'слово'],
      ),
    );
    await search.start('слово');
    expect(search.hits.map((SearchHit h) => h.pageNumber), <int>[1, 3, 4]);
    search.dispose();
  });

  test('слишком короткий запрос не запускает проход по книге', () async {
    final FakeReaderDocument document = _book();
    final DocumentSearch search = DocumentSearch(document: document);
    await search.start('а');
    expect(search.hits, isEmpty);
    expect(search.isRunning, isFalse);
    expect(document.textReads, isEmpty);
    search.dispose();
  });

  test('ничего не найдено — так и сказано', () async {
    final DocumentSearch search = DocumentSearch(document: _book());
    await search.start('тролль');
    expect(search.isEmptyResult, isTrue);
    search.dispose();
  });

  test('предел совпадений останавливает поиск', () async {
    final DocumentSearch search = DocumentSearch(
      document: FakeReaderDocument(
        pages: List<String>.filled(50, 'эхо эхо эхо эхо эхо'),
      ),
      hitLimit: 12,
    );
    await search.start('эхо');
    expect(search.hits.length, 12);
    expect(search.reachedLimit, isTrue);
    // Останавливаемся, а не дочитываем книгу до конца ради выброшенного.
    expect(search.scannedPages, lessThan(50));
    search.dispose();
  });

  test('новый запрос отменяет старый и не смешивает результаты', () async {
    final DocumentSearch search = DocumentSearch(
      document: FakeReaderDocument(
        pages: List<String>.generate(
          200,
          (int i) => 'первое слово и второе слово',
        ),
      ),
    );
    final Future<void> first = search.start('первое');
    final Future<void> second = search.start('второе');
    await Future.wait(<Future<void>>[first, second]);

    expect(search.query, 'второе');
    expect(search.isRunning, isFalse);
    expect(
      search.hits.every((SearchHit h) => h.matchedText == 'второе'),
      isTrue,
    );
    search.dispose();
  });

  test('очистка сбрасывает состояние', () async {
    final DocumentSearch search = DocumentSearch(document: _book());
    await search.start('Германн');
    expect(search.hits, isNotEmpty);
    search.clear();
    expect(search.hits, isEmpty);
    expect(search.query, isEmpty);
    expect(search.isFinished, isFalse);
    search.dispose();
  });

  test('прогресс доходит до конца книги', () async {
    final DocumentSearch search = DocumentSearch(document: _book(pages: 40));
    expect(search.progress, 0);
    await search.start('Германн');
    expect(search.scannedPages, 40);
    expect(search.progress, 1.0);
    search.dispose();
  });

  test('нечитаемая страница не обрывает поиск по книге', () async {
    final _BrokenPageDocument document = _BrokenPageDocument();
    final DocumentSearch search = DocumentSearch(document: document);
    await search.start('цель');
    expect(search.hits.single.pageNumber, 3);
    expect(search.scannedPages, 3);
    search.dispose();
  });

  test('каждая страница читается ровно один раз', () async {
    final FakeReaderDocument document = _book(pages: 25);
    final DocumentSearch search = DocumentSearch(document: document);
    await search.start('текст');
    expect(document.textReads.length, 25);
    expect(document.textReads.values.every((int count) => count == 1), isTrue);
    search.dispose();
  });

  group('SNO-F-READ-01: другие написания запроса', () {
    /// Слово, разрезанное переносом: между частями стоит знак движка.
    String cut(String head, String tail) {
      return '$head${String.fromCharCode(kLineBreakHyphen)}$tail';
    }

    FakeReaderDocument heart() {
      return FakeReaderDocument(
        pages: <String>[
          'Болезни ${cut('сердечно', 'сосудистой')} системы.',
          'Обычный текст.',
          'Сердечно-сосудистая система.',
        ],
      );
    }

    test('SNO-F-READ-01: найденное по ним стоит в том же списке', () async {
      final FakeReaderDocument document = heart();
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start(
        'сердечнососудист',
        also: <String>['сердечно-сосудист'],
      );

      // Запросом остаётся основной; найденное — по порядку страниц.
      expect(search.query, 'сердечнососудист');
      expect(search.hits.map((SearchHit h) => h.pageNumber), <int>[1, 3]);
      // Проход по книге один, сколько бы написаний ни искалось.
      expect(document.textReads, <int, int>{1: 1, 2: 1, 3: 1});
      search.dispose();
    });

    test('SNO-F-READ-01: место, найденное дважды, в списке одно', () async {
      final DocumentSearch search = DocumentSearch(document: heart());
      await search.start(
        'сердечно-сосудист',
        also: <String>['сердечнососудист', ' сердечно-сосудист '],
      );
      expect(search.hits.map((SearchHit h) => h.pageNumber), <int>[1, 3]);
      search.dispose();
    });

    test('SNO-F-READ-01: без других написаний поиск прежний', () async {
      final DocumentSearch search = DocumentSearch(document: heart());
      await search.start('сердечнососудист');
      expect(search.hits.map((SearchHit h) => h.pageNumber), <int>[1]);
      search.dispose();
    });

    test('SNO-F-READ-01: слишком короткое написание не ищется', () async {
      final DocumentSearch search = DocumentSearch(document: heart());
      await search.start('систем', also: <String>['о', '']);
      expect(search.hits.map((SearchHit h) => h.pageNumber), <int>[1, 3]);
      search.dispose();
    });

    test('SNO-F-READ-01: предел считается по общему списку', () async {
      final DocumentSearch search = DocumentSearch(
        document: FakeReaderDocument(
          pages: List<String>.filled(20, 'раз два раз два раз два'),
        ),
        hitLimit: 7,
      );
      await search.start('раз', also: <String>['два']);
      expect(search.hits.length, 7);
      expect(search.reachedLimit, isTrue);
      // На странице найденное идёт вперемешку, как в тексте.
      expect(search.hits.take(4).map((SearchHit h) => h.sourceStart), <int>[
        0,
        4,
        8,
        12,
      ]);
      search.dispose();
    });
  });

  group('F-TEXT-04: поиск по кэшу текста', () {
    BookTextCache cacheOf(FakeReaderDocument document, MemoryPageTextStore s) {
      return BookTextCache(
        document: document,
        store: s,
        bookId: 'book-1',
        fingerprint: 'hash-1',
      );
    }

    int reads(FakeReaderDocument document) {
      int total = 0;
      for (final int count in document.textReads.values) {
        total += count;
      }
      return total;
    }

    test('второй поиск идёт без обращения к движку', () async {
      final FakeReaderDocument document = _book(pages: 60);
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, MemoryPageTextStore()),
      );

      await search.start('Германн');
      expect(search.hits.single.pageNumber, 5);
      expect(reads(document), 60, reason: 'первый поиск наполнил кэш');

      await search.start('страницы 42');
      expect(search.hits.single.pageNumber, 42);
      expect(search.scannedPages, 60);
      expect(reads(document), 60, reason: 'книгу второй раз не читали');
      search.dispose();
    });

    test('слово с непосещённой страницы находится сразу', () async {
      // Книгу только что открыли: ни одной страницы в кэше нет, читатель
      // стоит на первой, а слово — в самом конце.
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>[
          ...List<String>.filled(119, 'обычный текст'),
          'здесь лежит редкое слово',
        ],
      );
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, MemoryPageTextStore()),
      );

      await search.start('редкое');

      expect(search.hits.single.pageNumber, 120);
      expect(search.unscannedPages, 0);
      search.dispose();
    });

    test('по кэшу находится то же, что по документу', () async {
      final List<String> pages = List<String>.generate(
        45,
        (int i) => i.isEven
            ? 'Тройка, семёрка,\r\nтуз — страница ${i + 1}'
            : 'ничего особенного ${i + 1}',
      );
      final DocumentSearch live = DocumentSearch(
        document: FakeReaderDocument(pages: pages),
      );
      final FakeReaderDocument document = FakeReaderDocument(pages: pages);
      final MemoryPageTextStore store = MemoryPageTextStore();
      // Кэш наполнен наполовину и заранее: поиск идёт и по базе, и по
      // движку.
      await cacheOf(document, store).textsOf(10, 30);
      final DocumentSearch cached = DocumentSearch(
        document: document,
        cache: cacheOf(document, store),
      );

      const List<String> queries = <String>[
        'семёрка, туз',
        'ОСОБЕННОГО',
        'нет',
      ];
      for (final String query in queries) {
        await live.start(query);
        await cached.start(query);
        expect(cached.hits, live.hits, reason: 'запрос «$query»');
        expect(
          <String>[for (final SearchHit hit in cached.hits) hit.snippet],
          <String>[for (final SearchHit hit in live.hits) hit.snippet],
        );
        expect(cached.scannedPages, live.scannedPages);
      }
      live.dispose();
      cached.dispose();
    });

    test('неполный поиск называет остаток, и он убывает', () async {
      final FakeReaderDocument document = _book(pages: 40);
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, MemoryPageTextStore()),
      );
      final List<int> left = <int>[];
      search.addListener(() {
        if (search.isRunning) {
          left.add(search.unscannedPages);
        }
      });

      expect(search.pageCount, 40);
      await search.start('текст');

      // Первое сообщение — до первой страницы, дальше — после каждой
      // пачки, кроме последней.
      expect(left, <int>[40, 32, 24, 16, 8]);
      expect(search.unscannedPages, 0);
      expect(search.isRunning, isFalse);
      search.dispose();
    });

    test('скан без текста: искать не в чем — так и сказано', () async {
      final FakeReaderDocument document = FakeReaderDocument.blank(12);
      final MemoryPageTextStore store = MemoryPageTextStore();
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, store),
      );

      await search.start('что угодно');

      expect(search.isEmptyResult, isTrue);
      expect(search.bookHasNoText, isTrue);
      expect(store.rowCount('book-1'), 12, reason: 'пустой кэш — не ошибка');
      search.dispose();
    });

    test('книга с текстом, но без находок — не скан', () async {
      final DocumentSearch search = DocumentSearch(document: _book());
      await search.start('тролль');
      expect(search.isEmptyResult, isTrue);
      expect(search.bookHasNoText, isFalse);

      // И без кэша скан опознаётся так же.
      final DocumentSearch scan = DocumentSearch(
        document: FakeReaderDocument.blank(3),
      );
      await scan.start('тролль');
      expect(scan.bookHasNoText, isTrue);
      // Слишком короткий запрос книгу не просматривал — судить не о чем.
      await scan.start('а');
      expect(scan.bookHasNoText, isFalse);
      search.dispose();
      scan.dispose();
    });

    test('нечитаемая страница не обрывает поиск и с кэшем', () async {
      final _BrokenPageDocument document = _BrokenPageDocument();
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, MemoryPageTextStore()),
      );
      await search.start('цель');
      expect(search.hits.single.pageNumber, 3);
      expect(search.scannedPages, 3);
      search.dispose();
    });

    test('книга, которая не прочиталась, — не скан', () async {
      // Движок не отдал ни одной страницы: это «не знаю», а не «текста
      // нет». Сказать «скан» можно только о книге, прочитанной на деле.
      final _UnreadableDocument plain = _UnreadableDocument();
      final DocumentSearch live = DocumentSearch(document: plain);
      await live.start('что угодно');
      expect(live.isEmptyResult, isTrue);
      expect(live.bookHasNoText, isFalse);

      final _UnreadableDocument document = _UnreadableDocument();
      final MemoryPageTextStore store = MemoryPageTextStore();
      final DocumentSearch cached = DocumentSearch(
        document: document,
        cache: cacheOf(document, store),
      );
      await cached.start('что угодно');
      expect(cached.isEmptyResult, isTrue);
      expect(cached.bookHasNoText, isFalse);
      expect(store.rowCount('book-1'), 0, reason: 'незнание не запоминается');
      live.dispose();
      cached.dispose();
    });

    test('нечитаемая страница не прячет текст книги', () async {
      expect(await hasTextLayer(_BrokenFirstPageDocument()), isTrue);
    });

    test('F-DEV-13: книга, которая не прочиталась, — «не знаю»', () async {
      // Не «скан»: с меткой на обложке это было бы враньё.
      expect(await hasTextLayer(_UnreadableDocument()), isNull);
    });

    test('F-DEV-13: прочитанная книга без текста — скан', () async {
      expect(await hasTextLayer(FakeReaderDocument.blank(3)), isFalse);
    });

    test('F-DEV-13: текст после первых страниц находится', () async {
      // Обложка и шмуцтитулы картинками, текст — с седьмой страницы:
      // прежняя проверка смотрела пять страниц и называла книгу сканом.
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>[
          for (int page = 1; page <= 30; page++) page < 7 ? '' : 'текст',
        ],
      );
      expect(await hasTextLayer(document), isTrue);
    });

    test('F-DEV-13: дальше двадцатой страницы проверка не ходит', () async {
      final FakeReaderDocument document = FakeReaderDocument.blank(60);
      expect(await hasTextLayer(document), isFalse);
      expect(document.textReads.length, kTextLayerProbePages);
    });

    test('F-DEV-13: три ответа проверки', () {
      expect(textLayerVerdict(found: true, unread: false), isTrue);
      expect(textLayerVerdict(found: true, unread: true), isTrue);
      expect(textLayerVerdict(found: false, unread: false), isFalse);
      expect(textLayerVerdict(found: false, unread: true), isNull);
    });

    test('база отказала — поиск идёт движком, как раньше', () async {
      final FakeReaderDocument document = _book();
      final MemoryPageTextStore store = MemoryPageTextStore()
        ..failReads = true
        ..failWrites = true;
      final DocumentSearch search = DocumentSearch(
        document: document,
        cache: cacheOf(document, store),
      );
      await search.start('Германн');
      expect(search.hits.single.pageNumber, 5);
      search.dispose();
    });
  });
}

/// Документ, из которого не читается ни одна страница.
class _UnreadableDocument extends FakeReaderDocument {
  _UnreadableDocument() : super(pages: <String>['раз', 'два', 'три']);

  @override
  Future<String> pageText(int pageNumber) {
    throw StateError('текст страницы $pageNumber не прочитан');
  }
}

/// Документ, у которого не читается первая страница.
class _BrokenFirstPageDocument extends FakeReaderDocument {
  _BrokenFirstPageDocument() : super(pages: <String>['битая', 'текст']);

  @override
  Future<String> pageText(int pageNumber) {
    if (pageNumber == 1) {
      throw StateError('страница не читается');
    }
    return super.pageText(pageNumber);
  }
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
