import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// Пауза перед записью позиции. В приложении это две секунды; в тестах
/// столько ждать незачем, но и слишком коротко брать нельзя — тест начнёт
/// падать от случайной задержки на загруженном раннере.
const Duration _saveDelay = Duration(milliseconds: 150);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<ReaderController> openController({
    int pages = 20,
    ReadingPosition? saved,
    List<OutlineEntry> outline = const <OutlineEntry>[],
  }) async {
    final Book book = fakeBook(pageCount: pages);
    await data.library.save(book);
    if (saved != null) {
      await data.reading.savePosition(saved);
    }
    final FakeReaderDocument document = FakeReaderDocument(
      pages: List<String>.generate(pages, (int i) => 'страница ${i + 1}'),
      outlineNodes: outline,
    );
    return ReaderController.open(
      book: book,
      opener: FakeDocumentOpener(document),
      reading: data.reading,
      saveDelay: _saveDelay,
    );
  }

  group('открытие книги', () {
    test('книга без истории открывается с первой страницы', () async {
      final ReaderController controller = await openController();
      expect(controller.initialPage, 1);
      expect(controller.page, 1);
      expect(controller.pageCount, 20);
      await controller.close();
      controller.dispose();
    });

    test('книга с историей открывается там, где её оставили', () async {
      final ReaderController controller = await openController(
        saved: const ReadingPosition(bookId: 'book-read', page: 13),
      );
      expect(controller.initialPage, 13);
      expect(controller.page, 13);
      await controller.close();
      controller.dispose();
    });

    test('позиция за краем книги прижимается к последней странице', () async {
      final ReaderController controller = await openController(
        pages: 10,
        saved: const ReadingPosition(bookId: 'book-read', page: 500),
      );
      expect(controller.initialPage, 10);
      await controller.close();
      controller.dispose();
    });

    test('нечитаемый файл не открывается и не течёт', () async {
      final Book book = fakeBook();
      await data.library.save(book);
      const DocumentOpenException failure = DocumentOpenException(
        DocumentProblem.damaged,
        '/books/read.pdf',
      );
      await expectLater(
        ReaderController.open(
          book: book,
          opener: FakeDocumentOpener(
            FakeReaderDocument.blank(1),
            failure: failure,
          ),
          reading: data.reading,
        ),
        throwsA(isA<DocumentOpenException>()),
      );
    });
  });

  group('сохранение позиции', () {
    test('место записывается в базу и переживает переоткрытие', () async {
      final ReaderController controller = await openController();
      controller.onPageChanged(7);
      await controller.close();
      controller.dispose();

      final ReadingPosition? saved = await data.reading.position('book-read');
      expect(saved, isNotNull);
      expect(saved!.page, 7);
      expect(saved.progress, closeTo(0.35, 1e-9));

      final ReaderController reopened = await openController();
      expect(reopened.initialPage, 7);
      await reopened.close();
      reopened.dispose();
    });

    test('быстрое листание не пишет в базу на каждой странице', () async {
      final ReaderController controller = await openController(pages: 100);
      for (int page = 2; page <= 40; page++) {
        controller.onPageChanged(page);
      }
      // Записи ещё не было: таймер не успел сработать.
      expect(await data.reading.position('book-read'), isNull);

      await _settle();
      final ReadingPosition? saved = await data.reading.position('book-read');
      expect(saved, isNotNull);
      expect(saved!.page, 40);

      await controller.close();
      controller.dispose();
    });

    test('долгое листание доходит до базы, не дожидаясь остановки', () async {
      // Таймер намеренно не перезапускается на каждой странице: иначе при
      // непрерывном листании запись откладывалась бы бесконечно, и
      // закрытое по питанию приложение теряло бы место в книге.
      final ReaderController controller = await openController(pages: 100);
      ReadingPosition? midway;
      for (int page = 2; page <= 30; page++) {
        controller.onPageChanged(page);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        midway ??= await data.reading.position('book-read');
      }
      expect(
        midway,
        isNotNull,
        reason: 'позиция обязана сохраниться прямо во время листания',
      );

      await _settle();
      final ReadingPosition? saved = await data.reading.position('book-read');
      expect(saved!.page, 30);
      await controller.close();
      controller.dispose();
    });

    test('flush записывает немедленно', () async {
      final ReaderController controller = await openController();
      controller.onPageChanged(4);
      await controller.flush();
      expect((await data.reading.position('book-read'))!.page, 4);
      await controller.close();
      controller.dispose();
    });

    test('без изменений в базу не пишем', () async {
      final ReaderController controller = await openController();
      controller.onPageChanged(1); // та же страница
      await controller.flush();
      expect(await data.reading.position('book-read'), isNull);
      await controller.close();
      controller.dispose();
    });

    test('страница за краем не попадает в базу как есть', () async {
      final ReaderController controller = await openController(pages: 10);
      controller.onPageChanged(999);
      await controller.flush();
      expect((await data.reading.position('book-read'))!.page, 10);
      await controller.close();
      controller.dispose();
    });
  });

  group('оглавление', () {
    test('читается один раз и запоминается', () async {
      final ReaderController controller = await openController(
        outline: const <OutlineEntry>[
          OutlineEntry(title: 'Глава 1', pageNumber: 1),
        ],
      );
      expect(controller.outline, isNull);
      expect(controller.hasOutline, isNull);

      await controller.loadOutline();
      expect(controller.hasOutline, isTrue);
      expect(controller.outline!.single.title, 'Глава 1');

      await controller.loadOutline();
      expect(controller.outline!.length, 1);

      await controller.close();
      controller.dispose();
    });

    test('испорченное оглавление не мешает читать книгу', () async {
      final Book book = fakeBook();
      await data.library.save(book);
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['раз', 'два'],
      )..failOutline = true;
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: data.reading,
      );
      await controller.loadOutline();
      expect(controller.hasOutline, isFalse);
      expect(controller.pageCount, 2);
      await controller.close();
      controller.dispose();
    });
  });

  group('закрытие', () {
    test('документ закрывается вместе с контроллером', () async {
      final Book book = fakeBook();
      await data.library.save(book);
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['раз'],
      );
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: data.reading,
      );
      expect(document.closed, isFalse);
      await controller.close();
      expect(document.closed, isTrue);
      controller.dispose();
    });

    test('повторное закрытие безвредно', () async {
      final ReaderController controller = await openController();
      await controller.close();
      await controller.close();
      controller.dispose();
    });
  });

  group('подписи', () {
    test('счётчик страниц и прогресс', () async {
      final ReaderController controller = await openController(pages: 200);
      controller.onPageChanged(50);
      expect(controller.label, '50 / 200');
      expect(controller.progress, closeTo(0.25, 1e-9));
      await controller.close();
      controller.dispose();
    });
  });
}
