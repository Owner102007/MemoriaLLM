import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/reading/book_frame.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';

/// Текст обычной страницы книги.
List<TextBox> _usual() => textBlock(
  left: 0.15,
  top: 0.12,
  right: 0.85,
  bottom: 0.88,
  lines: 14,
  charsPerLine: 24,
);

/// Текст страницы с зеркальными полями, как в переплёте: у чётной широкое
/// поле справа, у нечётной — слева.
List<TextBox> _bound(int page) {
  return page.isEven
      ? textBlock(left: 0.08, right: 0.85, lines: 14)
      : textBlock(left: 0.15, right: 0.92, lines: 14);
}

List<String> _texts(int pages) =>
    List<String>.generate(pages, (int i) => 'страница ${i + 1}');

Map<int, List<TextBox>> _boxes(int pages) {
  return <int, List<TextBox>>{
    for (int page = 1; page <= pages; page++) page: _usual(),
  };
}

/// Документ, в котором разбор отдельных страниц можно придержать.
///
/// Так ведёт себя скан: его рамка — это рендер и попиксельный разбор, и
/// считается она в разы дольше рамки страницы с текстом.
class _GatedDocument extends FakeReaderDocument {
  _GatedDocument({required super.pages, super.boxes});

  /// Страницы, разбор которых ждёт отмашки.
  final Map<int, Completer<void>> gates = <int, Completer<void>>{};

  @override
  Future<List<TextBox>> pageTextBoxes(int pageNumber) async {
    final Completer<void>? gate = gates[pageNumber];
    if (gate != null) {
      await gate.future;
    }
    return super.pageTextBoxes(pageNumber);
  }
}

/// Хранилище, у которого рамка книги не читается и не пишется: так
/// ведёт себя база, в которой таблица рамок испорчена.
class _BrokenFrames implements ReadingRepository {
  _BrokenFrames(this._inner);

  final ReadingRepository _inner;

  @override
  Future<ReadingPosition?> position(String bookId) => _inner.position(bookId);

  @override
  Stream<ReadingPosition?> watchPosition(String bookId) =>
      _inner.watchPosition(bookId);

  @override
  Stream<Map<String, ReadingPosition>> watchPositions() =>
      _inner.watchPositions();

  @override
  Future<void> savePosition(ReadingPosition position) =>
      _inner.savePosition(position);

  @override
  Future<BookReadingSettings> settings(
    String bookId,
    ScreenOrientation orientation,
  ) => _inner.settings(bookId, orientation);

  @override
  Future<void> saveSettings(BookReadingSettings settings) =>
      _inner.saveSettings(settings);

  @override
  Future<BookFrame?> bookFrame(String bookId) async {
    throw StateError('таблица рамок не читается');
  }

  @override
  Future<void> saveBookFrame(String bookId, BookFrame frame) async {
    throw StateError('таблица рамок не пишется');
  }
}

/// Даёт досчитаться всему, что считается без ожидания.
Future<void> _idle() => Future<void>.delayed(Duration.zero);

/// Рамка книги проверяется на хранилище в памяти: так видно, сколько раз
/// её записали, а настоящая запись в базу проверена в тестах слоя данных.
void main() {
  late FakeReadingRepository reading;

  setUp(() => reading = FakeReadingRepository());

  FakeReaderDocument plain(int pages, {Map<int, List<TextBox>>? boxes}) =>
      FakeReaderDocument(pages: _texts(pages), boxes: boxes ?? _boxes(pages));

  _GatedDocument gated(int pages) =>
      _GatedDocument(pages: _texts(pages), boxes: _boxes(pages));

  /// Открывает книгу; [load] — дождаться рамки первой страницы и всего,
  /// что считается следом за ней.
  Future<ReaderController> open(
    FakeReaderDocument document, {
    bool load = true,
  }) async {
    final ReaderController controller = await ReaderController.open(
      book: fakeBook(pageCount: document.pageCount),
      opener: FakeDocumentOpener(document),
      reading: reading,
      saveDelay: const Duration(milliseconds: 150),
      frameWait: Duration.zero,
    );
    if (load) {
      await controller.loadFrame();
      await _idle();
    }
    return controller;
  }

  /// Книга, у которой обрезка уже включена в настройках.
  Future<void> cropSaved() {
    return reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-read',
        orientation: kSettingsSlot,
        autoCrop: true,
      ),
    );
  }

  Future<void> shut(ReaderController controller) async {
    await controller.close();
    controller.dispose();
  }

  group('F-READ-15: рамка книги считается один раз', () {
    test('F-READ-15: без обрезки рамка книги не считается вовсе', () async {
      final FakeReaderDocument document = plain(40);
      final ReaderController controller = await open(document);

      expect(controller.bookFrame, isNull);
      expect(controller.isBookFrameLoading, isFalse);
      expect(controller.contentBox, CropBox.full);
      expect(document.boxReads.keys.toSet(), <int>{1, 2, 3});
      expect(reading.frameSaveCount, 0);
      await shut(controller);
    });

    test('F-READ-15: включённая обрезка считает рамку и пишет её', () async {
      final ReaderController controller = await open(plain(12));
      await controller.setAutoCrop(true);

      final BookFrame? frame = controller.bookFrame;
      expect(frame, isNotNull);
      expect(frame!.samples, 12, reason: 'короткая книга — вся в выборке');
      expect(frame.version, kBookFrameVersion);
      expect(controller.contentBox, frame.odd);
      expect(controller.contentBox.width, lessThan(0.85));
      expect(reading.frameSaveCount, 1);
      expect(await reading.bookFrame(controller.book.id), frame);
      await shut(controller);
    });

    test('F-READ-15: второе открытие берёт рамку из базы', () async {
      final ReaderController first = await open(plain(12));
      await first.setAutoCrop(true);
      final BookFrame? saved = first.bookFrame;
      expect(saved, isNotNull);
      await shut(first);

      // ALG-DATA-09: версия совпала — рамка не пересчитывается, и книга
      // встаёт по ней с первого кадра, не разобрав ни одной страницы.
      final FakeReaderDocument again = plain(12);
      final ReaderController second = await open(again, load: false);
      expect(second.bookFrame, saved);
      expect(again.boxReads, isEmpty);
      expect(second.contentBox, saved!.odd);

      await second.loadFrame();
      await _idle();
      expect(again.boxReads.keys.toSet(), <int>{
        1,
        2,
        3,
      }, reason: 'выборка не разбиралась заново');
      expect(reading.frameSaveCount, 1);
      await shut(second);
    });

    test('F-READ-15: рамка прежней версии пересчитывается сама', () async {
      // ALG-DATA-09: поменяли алгоритм — отставшее пересчитывается при
      // открытии, без «очистить кэш».
      await cropSaved();
      await reading.saveBookFrame(
        'book-read',
        const BookFrame(
          odd: CropBox(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7),
          samples: 4,
          version: kBookFrameVersion - 1,
        ),
      );

      final ReaderController controller = await open(plain(12));
      final BookFrame? frame = controller.bookFrame;
      expect(frame?.version, kBookFrameVersion);
      expect(frame?.samples, 12);
      expect(frame?.odd.left, lessThan(0.3));
      final BookFrame? stored = await reading.bookFrame('book-read');
      expect(stored, frame);
      await shut(controller);
    });

    test('F-READ-15: рамка другого файла пересчитывается сама', () async {
      // Книгу привязали к другому файлу: идентификатор прежний, отпечаток
      // новый. Рамка прежнего файла новому не годится.
      await cropSaved();
      await reading.saveBookFrame(
        'book-read',
        const BookFrame(
          odd: CropBox(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7),
          samples: 16,
          fingerprint: 'hash-of-another-file',
        ),
      );

      final ReaderController controller = await open(plain(12));
      final BookFrame? frame = controller.bookFrame;
      expect(frame?.fingerprint, controller.book.fileHash);
      expect(frame?.samples, 12);
      expect(frame?.odd.left, lessThan(0.3));
      await shut(controller);
    });

    test('F-READ-15: рамка не читается — книга открывается', () async {
      await cropSaved();
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 12),
        opener: FakeDocumentOpener(plain(12)),
        reading: _BrokenFrames(reading),
        frameWait: Duration.zero,
      );
      expect(controller.page, 1);
      expect(controller.bookFrame, isNull);

      // Рамка — производное: не прочиталась и не записалась — считается
      // заново и действует до закрытия книги.
      await controller.loadFrame();
      await _idle();
      expect(controller.bookFrame, isNotNull);
      expect(controller.contentBox.width, lessThan(0.85));
      await shut(controller);
    });

    test('F-READ-15: смена настройки колонтитулов пересчитывает', () async {
      final ReaderController controller = await open(plain(12));
      await controller.setAutoCrop(true);
      expect(controller.bookFrame?.ignoreRunningHeads, isTrue);

      await controller.setIgnoreRunningHeads(false);
      expect(controller.bookFrame?.ignoreRunningHeads, isFalse);
      expect(reading.frameSaveCount, 2);
      final BookFrame? stored = await reading.bookFrame(controller.book.id);
      expect(stored?.ignoreRunningHeads, isFalse);
      await shut(controller);
    });

    test('F-READ-15: в ленте рамка книги не считается', () async {
      await cropSaved();
      final ReaderController controller = await open(plain(12), load: false);
      controller.setSheetModes(enabled: false);
      await controller.loadFrame();
      await _idle();
      expect(controller.bookFrame, isNull);
      expect(reading.frameSaveCount, 0);

      // Вернулись к листам — рамка считается.
      controller.setSheetModes(enabled: true);
      await controller.loadFrame();
      await _idle();
      expect(controller.bookFrame, isNotNull);
      expect(reading.frameSaveCount, 1);
      await shut(controller);
    });
  });

  group('F-READ-15: ширина текста стоит на месте', () {
    test('F-READ-15: рамка одна на все страницы книги', () async {
      // Прежде у каждой страницы была своя рамка: страница с короткими
      // строками и концевая страница главы показывались крупнее соседних.
      final Map<int, List<TextBox>> boxes = _boxes(12);
      boxes[4] = textBlock(
        left: 0.3,
        top: 0.3,
        right: 0.7,
        bottom: 0.5,
        lines: 4,
      );
      boxes[7] = textBlock(
        left: 0.15,
        top: 0.12,
        right: 0.8,
        bottom: 0.88,
        lines: 14,
      );
      boxes[9] = textBlock(
        left: 0.15,
        top: 0.12,
        right: 0.85,
        bottom: 0.4,
        lines: 5,
        charsPerLine: 24,
      );
      final ReaderController controller = await open(plain(12, boxes: boxes));
      await controller.setAutoCrop(true);

      final BookFrame? frame = controller.bookFrame;
      expect(frame, isNotNull);
      expect(frame!.isMirrored, isFalse);
      for (int page = 1; page <= 12; page++) {
        await controller.goToPage(page);
        await _idle();
        expect(controller.frame?.pageNumber, page);
        expect(controller.contentBox, frame.odd, reason: 'страница $page');
      }
      await shut(controller);
    });

    test('F-READ-15: зеркальные поля — ширина одна, чётные сдвинуты', () async {
      final ReaderController controller = await open(
        plain(
          12,
          boxes: <int, List<TextBox>>{
            for (int page = 1; page <= 12; page++) page: _bound(page),
          },
        ),
      );
      await controller.setAutoCrop(true);

      expect(controller.bookFrame?.isMirrored, isTrue);
      final CropBox odd = controller.contentBox;
      await controller.goToPage(2);
      await _idle();
      final CropBox even = controller.contentBox;
      expect(even.width, closeTo(odd.width, 1e-9));
      expect(even.left, lessThan(odd.left));
      // Общая рамка на оба поля сразу была бы шире на само поле.
      expect(odd.width, lessThan(0.82));
      await shut(controller);
    });

    test('F-READ-15: просветы строк остаются у страницы', () async {
      // На книгу переезжает только прямоугольник содержимого. Просветы у
      // каждой страницы свои: по ним делятся половины и трети.
      final ReaderController controller = await open(plain(12));
      await controller.setAutoCrop(true);
      await controller.setDisplayMode(PageDisplayMode.half);

      expect(controller.fragmentCount, 2);
      expect(controller.frame, isNotNull);
      expect(controller.breaks, isNotEmpty);
      expect(controller.breaks, controller.frame?.breaks);
      expect(controller.contentBox, controller.bookFrame?.odd);
      await shut(controller);
    });

    test('F-READ-15: текст за рамкой книги расширяет рамку страницы', () async {
      // Широкая таблица на одной странице. Рамка книги её не замечает,
      // а сама страница получает рамку до своего текста: кегль на ней
      // мельче, зато ни один символ не срезан.
      final Map<int, List<TextBox>> boxes = _boxes(40);
      expect(bookFrameSamplePages(40), isNot(contains(21)));
      boxes[21] = textBlock(
        left: 0.05,
        top: 0.12,
        right: 0.95,
        bottom: 0.88,
        lines: 14,
        charsPerLine: 24,
      );
      final FakeReaderDocument document = plain(40, boxes: boxes);
      final ReaderController controller = await open(document);
      await controller.setAutoCrop(true);
      final BookFrame? frame = controller.bookFrame;
      expect(frame, isNotNull);

      await controller.goToPage(21);
      await _idle();
      final CropBox wide = controller.contentBox;
      expect(wide.left, lessThan(frame!.odd.left));
      expect(wide.right, greaterThan(frame.odd.right));
      for (final TextBox box in boxes[21]!) {
        expect(box.left, greaterThanOrEqualTo(wide.left));
        expect(box.right, lessThanOrEqualTo(wide.right));
        expect(box.top, greaterThanOrEqualTo(wide.top));
        expect(box.bottom, lessThanOrEqualTo(wide.bottom));
      }

      await controller.goToPage(22);
      await _idle();
      expect(
        controller.contentBox,
        frame.forPage(22),
        reason: 'следующая страница — снова по рамке книги',
      );
      await shut(controller);
    });
  });

  group('F-READ-15: страница не ждёт рамку', () {
    test('F-READ-15: страница на экране, рамка приходит следом', () async {
      final _GatedDocument document = gated(40);
      final Completer<void> gate = Completer<void>();
      document.gates[bookFrameSamplePages(40).last] = gate;
      final ReaderController controller = await open(document);

      final Future<void> switched = controller.setAutoCrop(true);
      await _idle();
      expect(controller.settings.autoCrop, isTrue);
      expect(controller.isBookFrameLoading, isTrue);
      expect(
        controller.contentBox,
        CropBox.full,
        reason: 'пока рамка считается, страница показана целиком',
      );

      gate.complete();
      await switched;
      expect(controller.isBookFrameLoading, isFalse);
      expect(controller.contentBox.width, lessThan(0.85));
      await shut(controller);
    });

    test('F-READ-15: незнакомая страница встаёт по рамке книги', () async {
      // Прежде страница без своей рамки занимала её у соседней (BUG-23)
      // и подрезалась, когда своя досчитывалась. Рамка книги известна
      // до прихода на страницу, и подрезать нечего.
      final _GatedDocument document = gated(40);
      expect(bookFrameSamplePages(40), isNot(contains(21)));
      final Completer<void> gate = Completer<void>();
      document.gates[21] = gate;
      final ReaderController controller = await open(document);
      await controller.setAutoCrop(true);
      final BookFrame? frame = controller.bookFrame;
      expect(frame, isNotNull);

      expect(await controller.goToPage(21), isTrue);
      expect(controller.frame, isNull, reason: 'своя рамка ещё считается');
      expect(controller.contentBox, frame!.forPage(21));

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 21);
      expect(
        controller.contentBox,
        frame.forPage(21),
        reason: 'своя рамка пришла — страница не сдвинулась',
      );
      await shut(controller);
    });

    test('F-READ-15: первый кадр ждёт рамку книги не дольше срока', () async {
      await cropSaved();
      final _GatedDocument document = gated(40);
      final Completer<void> gate = Completer<void>();
      document.gates[bookFrameSamplePages(40).first] = gate;
      final ReaderController controller = await open(document, load: false);

      await controller.settleFrame(limit: const Duration(milliseconds: 30));
      expect(controller.frame?.pageNumber, 1);
      expect(controller.bookFrame, isNull, reason: 'скан: рамка считается');
      expect(controller.contentBox, CropBox.full);

      gate.complete();
      await _idle();
      expect(controller.bookFrame, isNotNull);
      expect(controller.contentBox.width, lessThan(0.85));
      await shut(controller);
    });

    test('F-READ-15: рамка успела — первый кадр уже по ней', () async {
      await cropSaved();
      final ReaderController controller = await open(plain(40), load: false);

      await controller
          .settleFrame(limit: const Duration(seconds: 30))
          .timeout(const Duration(seconds: 5));
      expect(controller.bookFrame, isNotNull);
      expect(controller.contentBox.width, lessThan(0.85));
      await shut(controller);
    });

    test('F-READ-15: закрытая книга обрывает расчёт рамки', () async {
      final _GatedDocument document = gated(40);
      final Completer<void> gate = Completer<void>();
      document.gates[bookFrameSamplePages(40).first] = gate;
      final ReaderController controller = await open(document);

      unawaited(controller.setAutoCrop(true));
      await _idle();
      expect(controller.isBookFrameLoading, isTrue);

      await controller.close();
      gate.complete();
      await _idle();
      expect(controller.bookFrame, isNull);
      expect(reading.frameSaveCount, 0);
      controller.dispose();
    });
  });

  group('F-READ-15: ручная рамка', () {
    test('F-READ-15: ручная рамка отменяет рамку книги', () async {
      final ReaderController controller = await open(plain(12));
      await controller.setAutoCrop(true);
      const CropBox manual = CropBox(
        left: 0.05,
        top: 0.05,
        right: 0.95,
        bottom: 0.95,
      );
      await controller.setManualCrop(manual);
      for (final int page in <int>[1, 2, 7]) {
        await controller.goToPage(page);
        await _idle();
        expect(controller.contentBox, manual, reason: 'страница $page');
      }
      await shut(controller);
    });

    test('F-READ-15: «Пересчитать» возвращает рамку книги', () async {
      final ReaderController controller = await open(plain(12));
      await controller.setAutoCrop(true);
      final CropBox counted = controller.contentBox;
      await controller.setManualCrop(
        const CropBox(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
      );
      expect(controller.contentBox, isNot(counted));

      await controller.recomputeBookFrame();
      expect(controller.settings.manualCrop, isNull);
      expect(controller.contentBox, counted);
      expect(reading.frameSaveCount, 2, reason: 'рамка посчитана заново');
      await shut(controller);
    });

    test('F-READ-15: ручная рамка есть — рамка книги не считается', () async {
      final FakeReaderDocument document = plain(40);
      final ReaderController controller = await open(document);
      await controller.setManualCrop(
        const CropBox(left: 0.05, top: 0.05, right: 0.95, bottom: 0.95),
      );
      await controller.setAutoCrop(true);

      expect(controller.bookFrame, isNull);
      expect(reading.frameSaveCount, 0);
      expect(document.boxReads.keys.toSet(), <int>{1, 2, 3});
      await shut(controller);
    });
  });
}
