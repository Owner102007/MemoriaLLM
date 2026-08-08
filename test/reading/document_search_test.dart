import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
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
