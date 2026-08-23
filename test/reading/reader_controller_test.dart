import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// Пауза перед записью позиции. В приложении это две секунды; в тестах
/// столько ждать незачем, но и слишком коротко брать нельзя — тест начнёт
/// падать от случайной задержки на загруженном раннере.
const Duration _saveDelay = Duration(milliseconds: 150);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

/// Область показа телефона. Положение экрана выбирает сама раскладка,
/// поэтому здесь важны только длины сторон.
const DisplayArea _phone = DisplayArea(width: 1080, height: 2400);

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
        FilePathSource('/books/read.pdf'),
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

  group('читательская рамка', () {
    Future<ReaderController> openFramed({
      int pages = 6,
      bool twoColumns = false,
    }) async {
      final Book book = fakeBook(pageCount: pages);
      await data.library.save(book);
      final List<TextBox> page = twoColumns
          ? <TextBox>[
              ...textBlock(
                left: 0.08,
                top: 0.1,
                right: 0.46,
                bottom: 0.9,
                lines: 20,
                charsPerLine: 15,
              ),
              ...textBlock(
                left: 0.54,
                top: 0.1,
                right: 0.92,
                bottom: 0.9,
                lines: 20,
                charsPerLine: 15,
              ),
            ]
          : textBlock(
              left: 0.15,
              top: 0.12,
              right: 0.85,
              bottom: 0.88,
              lines: 14,
              charsPerLine: 24,
            );
      final FakeReaderDocument document = FakeReaderDocument(
        pages: List<String>.generate(pages, (int i) => 'страница ${i + 1}'),
        boxes: <int, List<TextBox>>{for (int i = 1; i <= pages; i++) i: page},
      );
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: data.reading,
        saveDelay: _saveDelay,
      );
      await controller.loadFrame();
      return controller;
    }

    test('по умолчанию показывается вся страница, с полями', () async {
      // Читатель просил страницу такой, какой её свёрстали: обрезка —
      // отдельная возможность, а не поведение по умолчанию.
      final ReaderController controller = await openFramed();
      expect(controller.frame, isNotNull);
      expect(controller.contentBox, CropBox.full);
      expect(controller.fragmentBox, CropBox.full);
      await controller.close();
      controller.dispose();
    });

    test('включённая обрезка срезает поля', () async {
      final ReaderController controller = await openFramed();
      await controller.setAutoCrop(true);
      expect(controller.contentBox.isValid, isTrue);
      expect(controller.contentBox.width, lessThan(0.85));
      expect(controller.fragmentBox, controller.contentBox);
      await controller.close();
      controller.dispose();
    });

    test('половина страницы вдвое ниже целой', () async {
      final ReaderController controller = await openFramed();
      final double whole = controller.fragmentBox.height;
      await controller.setDisplayMode(PageDisplayMode.half);
      expect(controller.fragmentCount, 2);
      expect(whole / controller.fragmentBox.height, closeTo(2, 0.15));
      await controller.close();
      controller.dispose();
    });

    test('на двухколоночной странице половина — это колонка', () async {
      final ReaderController controller = await openFramed(twoColumns: true);
      await controller.setDisplayMode(PageDisplayMode.half);
      expect(controller.fragmentCount, 2);
      // Колонка занимает всю высоту содержимого и половину ширины.
      expect(
        controller.fragmentBox.height,
        closeTo(controller.contentBox.height, 1e-9),
      );
      expect(
        controller.fragmentBox.width,
        lessThan(controller.contentBox.width * 0.6),
      );
      await controller.close();
      controller.dispose();
    });

    test('смена режима не теряет место на странице', () async {
      final ReaderController controller = await openFramed();
      await controller.setDisplayMode(PageDisplayMode.half);
      await controller.nextFragment();
      expect(controller.fragment, 1);

      await controller.setDisplayMode(PageDisplayMode.third);
      expect(controller.fragmentCount, 3);
      expect(controller.fragment, 2, reason: 'низ страницы остался низом');
      expect(controller.page, 1, reason: 'страница не сменилась');

      await controller.setDisplayMode(PageDisplayMode.full);
      expect(controller.fragment, 0);
      await controller.close();
      controller.dispose();
    });

    test('режим отображения переживает переоткрытие книги', () async {
      final ReaderController controller = await openFramed();
      await controller.setDisplayMode(PageDisplayMode.third);
      await controller.close();
      controller.dispose();

      final ReaderController reopened = await openFramed();
      expect(reopened.settings.displayMode, PageDisplayMode.third);
      await reopened.close();
      reopened.dispose();
    });

    test('настройки книги одни на все положения экрана', () async {
      // Читатель настроил книгу один раз и ждёт её такой же после
      // поворота — а когда появится синхронизация, и на другом устройстве.
      final ReaderController controller = await openFramed();
      await controller.setFilter(ReadingFilter.nightRed);
      await controller.setDisplayMode(PageDisplayMode.half);
      await controller.close();
      controller.dispose();

      // Настройки лежат под одним ключом, каким бы боком ни держали
      // телефон в прошлый раз.
      final BookReadingSettings saved = await data.reading.settings(
        'book-read',
        kSettingsSlot,
      );
      expect(saved.filter, ReadingFilter.nightRed);
      expect(saved.displayMode, PageDisplayMode.half);

      final ReaderController reopened = await openFramed();
      expect(reopened.settings.filter, ReadingFilter.nightRed);
      expect(reopened.settings.displayMode, PageDisplayMode.half);
      await reopened.close();
      reopened.dispose();
    });

    test('полосы одноколоночной книги просят альбом', () async {
      final ReaderController controller = await openFramed();
      controller.setDisplayArea(_phone);
      expect(controller.preferredOrientation, ScreenOrientation.portrait);

      expect(
        await controller.setDisplayMode(PageDisplayMode.half),
        DisplayModeOutcome.applied,
      );
      expect(controller.preferredOrientation, ScreenOrientation.landscape);
      expect(controller.layout.gain, greaterThan(1.3));
      await controller.close();
      controller.dispose();
    });

    test('на двухколоночной книге половина не поворачивает экран', () async {
      // Жалоба владельца: страница делилась вдоль, а экран поворачивался
      // в альбом — узкая высокая колонка вписывалась в широкий низкий
      // экран по высоте, и текст выходил мельче целой страницы.
      final ReaderController controller = await openFramed(twoColumns: true);
      controller.setDisplayArea(_phone);

      expect(
        await controller.setDisplayMode(PageDisplayMode.half),
        DisplayModeOutcome.applied,
      );
      expect(controller.preferredOrientation, ScreenOrientation.portrait);
      expect(
        controller.layout.gain,
        greaterThan(1.2),
        reason: 'текст обязан вырасти, а не уменьшиться',
      );
      await controller.close();
      controller.dispose();
    });

    test('режим без выигрыша не включается и не молчит', () async {
      // Широкое низкое окно на ПК: повернуть его нельзя, а колонка
      // вписывается в него ровно так же, как целая страница.
      final ReaderController controller = await openFramed(twoColumns: true);
      controller.setDisplayArea(
        const DisplayArea(width: 2560, height: 1080),
        canTurn: false,
      );

      expect(
        await controller.setDisplayMode(PageDisplayMode.half),
        DisplayModeOutcome.noGain,
      );
      expect(
        controller.settings.displayMode,
        PageDisplayMode.full,
        reason: 'страница осталась целой',
      );
      await controller.close();
      controller.dispose();
    });

    test('пока область показа не измерена, не запрещается ничего', () async {
      // Запрет по незнанию хуже разрешения: экран сообщит форму области
      // через кадр, и раскладка пересчитается сама.
      final ReaderController controller = await openFramed(twoColumns: true);
      expect(controller.displayArea.isKnown, isFalse);
      expect(
        await controller.setDisplayMode(PageDisplayMode.half),
        DisplayModeOutcome.applied,
      );
      await controller.close();
      controller.dispose();
    });

    test('разворот не гасится за отсутствие выигрыша в кегле', () async {
      final ReaderController controller = await openFramed();
      controller.setDisplayArea(_phone);
      expect(
        await controller.setDisplayMode(PageDisplayMode.spread),
        DisplayModeOutcome.applied,
      );
      expect(controller.preferredOrientation, ScreenOrientation.landscape);
      await controller.close();
      controller.dispose();
    });

    test('половина разворота делит его по горизонтали', () async {
      final ReaderController controller = await openFramed(twoColumns: true);
      await controller.setDisplayMode(PageDisplayMode.spreadHalf);

      expect(controller.fragmentCount, 2);
      // Колонки внутри страниц тут ни при чём: строка идёт через обе
      // страницы разворота сразу.
      expect(
        controller.fragmentBox.width,
        closeTo(controller.contentBox.width, 1e-9),
      );
      await controller.close();
      controller.dispose();
    });

    test('фрагменты листаются вперёд и переходят на страницу', () async {
      final ReaderController controller = await openFramed();
      await controller.setDisplayMode(PageDisplayMode.half);

      expect(await controller.nextFragment(), isTrue);
      expect(controller.page, 1);
      expect(controller.fragment, 1);

      expect(await controller.nextFragment(), isTrue);
      expect(controller.page, 2);
      expect(controller.fragment, 0);
      await controller.close();
      controller.dispose();
    });

    test('назад читатель попадает в низ предыдущей страницы', () async {
      final ReaderController controller = await openFramed();
      await controller.setDisplayMode(PageDisplayMode.half);
      await controller.goToPage(3);

      expect(await controller.previousFragment(), isTrue);
      expect(controller.page, 2);
      expect(controller.fragment, 1, reason: 'низ предыдущей страницы');
      await controller.close();
      controller.dispose();
    });

    test('на краях книги листание упирается, а не ломается', () async {
      final ReaderController controller = await openFramed(pages: 2);
      await controller.setDisplayMode(PageDisplayMode.full);
      expect(await controller.previousFragment(), isFalse);
      expect(controller.page, 1);

      await controller.goToPage(2);
      expect(await controller.nextFragment(), isFalse);
      expect(controller.page, 2);
      await controller.close();
      controller.dispose();
    });

    test('в базу пишется и страница, и фрагмент', () async {
      final ReaderController controller = await openFramed();
      await controller.setDisplayMode(PageDisplayMode.third);
      await controller.nextFragment();
      await controller.flush();

      final ReadingPosition saved = (await data.reading.position('book-read'))!;
      expect(saved.page, 1);
      expect(saved.fragment, 1);
      await controller.close();
      controller.dispose();
    });

    test('ручная рамка главнее автообрезки и снимается сбросом', () async {
      final ReaderController controller = await openFramed();
      await controller.setAutoCrop(true);
      const CropBox manual = CropBox(
        left: 0.05,
        top: 0.05,
        right: 0.95,
        bottom: 0.95,
      );
      await controller.setManualCrop(manual);
      expect(controller.contentBox, manual);

      await controller.setManualCrop(null);
      expect(controller.contentBox, isNot(manual));
      expect(controller.contentBox.isValid, isTrue);
      await controller.close();
      controller.dispose();
    });

    test('вывернутая ручная рамка не принимается', () async {
      final ReaderController controller = await openFramed();
      await controller.setManualCrop(
        const CropBox(left: 0.9, top: 0.9, right: 0.1, bottom: 0.1),
      );
      expect(controller.settings.manualCrop, isNull);
      expect(controller.contentBox.isValid, isTrue);
      await controller.close();
      controller.dispose();
    });

    test('колонтитулы можно вернуть в содержимое', () async {
      final ReaderController controller = await openFramed();
      final CropBox before = controller.contentBox;
      await controller.setIgnoreRunningHeads(false);
      expect(controller.settings.ignoreRunningHeads, isFalse);
      expect(controller.contentBox.isValid, isTrue);
      // Рамка пересчитана заново, а не осталась от прошлых настроек.
      expect(controller.frame, isNotNull);
      expect(before.isValid, isTrue);
      await controller.close();
      controller.dispose();
    });

    test('запас по краям запоминается и не выходит за предел', () async {
      final ReaderController controller = await openFramed();
      expect(controller.settings.stripFit, 1);

      await controller.setStripFit(0.85);
      expect(controller.settings.stripFit, closeTo(0.85, 1e-9));

      // Щипок легко уносит масштаб куда угодно, а полоса мельче предела
      // перестаёт быть чтением.
      await controller.setStripFit(0.1);
      expect(controller.settings.stripFit, kMinStripFit);
      await controller.setStripFit(3);
      expect(controller.settings.stripFit, 1);

      await controller.setStripFit(0.9);
      final BookReadingSettings saved = await data.reading.settings(
        controller.book.id,
        kSettingsSlot,
      );
      expect(saved.stripFit, closeTo(0.9, 1e-9));
      await controller.close();
      controller.dispose();
    });

    test('затемнение запоминается и не доходит до черноты', () async {
      final ReaderController controller = await openFramed();
      expect(controller.settings.dimOutside, kDefaultDimOutside);

      await controller.setDimOutside(0.35);
      expect(controller.settings.dimOutside, closeTo(0.35, 1e-9));

      // Полная чернота вернула бы обрезку, от которой мы и ушли: смысл
      // затемнения в том, что страница остаётся видна целиком.
      await controller.setDimOutside(1);
      expect(controller.settings.dimOutside, kMaxDimOutside);
      // Ноль — законный выбор: гасить перестаём совсем.
      await controller.setDimOutside(-1);
      expect(controller.settings.dimOutside, 0);

      await controller.setDimOutside(0.5);
      final BookReadingSettings saved = await data.reading.settings(
        controller.book.id,
        kSettingsSlot,
      );
      expect(saved.dimOutside, closeTo(0.5, 1e-9));
      await controller.close();
      controller.dispose();
    });

    test('светофильтр собирается из настроек книги', () async {
      final ReaderController controller = await openFramed();
      expect(controller.filter.isIdentity, isTrue);

      await controller.setFilter(ReadingFilter.nightRed);
      expect(controller.filter.filter, ReadingFilter.nightRed);
      expect(controller.filter.isIdentity, isFalse);

      await controller.setGamma(1.4);
      expect(controller.filter.needsShader, isTrue);
      await controller.close();
      controller.dispose();
    });
  });
}
