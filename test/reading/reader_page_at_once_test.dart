import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/page_frames.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/crop.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// Текст страницы с зеркальными полями, как в переплёте: у чётной широкое
/// поле справа, у нечётной — слева.
List<TextBox> _pageText(int page) {
  return page.isEven
      ? textBlock(left: 0.08, right: 0.85, lines: 14)
      : textBlock(left: 0.15, right: 0.92, lines: 14);
}

List<String> _texts(int pages) =>
    List<String>.generate(pages, (int i) => 'страница ${i + 1}');

Map<int, List<TextBox>> _boxes(int pages) {
  return <int, List<TextBox>>{
    for (int page = 1; page <= pages; page++) page: _pageText(page),
  };
}

/// Документ, в котором разбор отдельных страниц можно придержать.
///
/// Так ведёт себя скан: его рамка — это рендер и попиксельный разбор, и
/// считается она в разы дольше рамки страницы с текстом. В подставном
/// документе все страницы разбираются мгновенно, и без задвижки ожидание
/// рамки не воспроизвести.
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

/// Даёт досчитаться всему, что считается без ожидания: подрезке и рамкам
/// соседних листов.
Future<void> _idle() => Future<void>.delayed(Duration.zero);

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  FakeReaderDocument plain(int pages) =>
      FakeReaderDocument(pages: _texts(pages), boxes: _boxes(pages));

  _GatedDocument gated(int pages, {Map<int, List<TextBox>>? boxes}) =>
      _GatedDocument(pages: _texts(pages), boxes: boxes ?? _boxes(pages));

  /// Открывает книгу и ждёт рамку первой страницы и её соседей.
  ///
  /// Срок ожидания рамки по умолчанию нулевой: переход не ждёт её вовсе,
  /// и тесты не зависят от того, как быстро идут часы на раннере.
  Future<ReaderController> open(
    FakeReaderDocument document, {
    Duration frameWait = Duration.zero,
    ReadingPosition? saved,
  }) async {
    final Book book = fakeBook(pageCount: document.pageCount);
    await data.library.save(book);
    if (saved != null) {
      await data.reading.savePosition(saved);
    }
    final ReaderController controller = await ReaderController.open(
      book: book,
      opener: FakeDocumentOpener(document),
      reading: data.reading,
      saveDelay: const Duration(milliseconds: 150),
      frameWait: frameWait,
    );
    await controller.loadFrame();
    await _idle();
    return controller;
  }

  Future<void> shut(ReaderController controller) async {
    await controller.close();
    controller.dispose();
  }

  group('BUG-23: переход не ждёт рамку', () {
    test('BUG-23: рамка посчитана заранее — страница меняется сразу', () async {
      final ReaderController controller = await open(plain(12));

      // Не дожидаясь: рамка второй страницы посчитана, пока читатель был
      // на первой, и нажатию ждать нечего.
      final Future<bool> step = controller.nextFragment();
      expect(controller.page, 2);
      expect(controller.frame?.pageNumber, 2);
      expect(await step, isTrue);
      await shut(controller);
    });

    test('BUG-23: непосчитанную рамку не ждут, она приходит следом', () async {
      // Прежде переход ждал рамку до победного: пока восьмая страница
      // не разобрана, читатель смотрел на прежнюю.
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[8] = gate;
      final ReaderController controller = await open(document);

      expect(await controller.goToPage(8), isTrue);
      expect(controller.page, 8, reason: 'страница уже на экране');
      expect(controller.frame, isNull, reason: 'а рамка ещё считается');

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 8, reason: 'страница подрезана');
      await shut(controller);
    });

    test('BUG-23: рамку ждут не дольше отведённого срока', () async {
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[8] = gate;
      final ReaderController controller = await open(
        document,
        frameWait: const Duration(milliseconds: 30),
      );

      final Future<bool> jump = controller.goToPage(8);
      expect(controller.page, 1, reason: 'срок ещё не вышел');
      expect(await jump, isTrue);
      expect(controller.page, 8);
      expect(controller.frame, isNull);

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 8);
      await shut(controller);
    });

    test('BUG-23: рамка успела в срок — страница встаёт уже по ней', () async {
      // Страница с текстом считается быстро, и показывать её по чужой
      // рамке, чтобы тут же подрезать, незачем.
      final ReaderController controller = await open(
        plain(12),
        frameWait: const Duration(seconds: 30),
      );

      final bool moved = await controller
          .goToPage(8)
          .timeout(const Duration(seconds: 5));
      expect(moved, isTrue);
      expect(controller.frame?.pageNumber, 8);
      await shut(controller);
    });

    test('BUG-23: незнакомая страница встаёт по рамке ближайшей', () async {
      // На девятой странице текст стоит иначе, чем на остальных, — так
      // видно, чья рамка действует: взятая взаймы или своя.
      final Map<int, List<TextBox>> boxes = _boxes(12);
      boxes[9] = textBlock(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7);
      final _GatedDocument document = gated(12, boxes: boxes);
      final Completer<void> gate = Completer<void>();
      document.gates[9] = gate;
      final ReaderController controller = await open(document);
      await controller.setAutoCrop(true);
      await controller.goToPage(6);
      await _idle();

      // Эталон считается отдельным источником рамок с теми же
      // настройками обрезки, что у книги.
      final PageFrame seventh = await PageFrameSource(
        document: document,
        options: CropOptions(
          ignoreRunningHeads: controller.settings.ignoreRunningHeads,
        ),
      ).frameFor(7);
      await controller.goToPage(9);
      expect(controller.frame, isNull);
      expect(
        controller.contentBox,
        seventh.content,
        reason: 'рамка седьмой: та же чётность, зеркальные поля совпадают',
      );

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 9);
      expect(controller.contentBox.top, greaterThan(seventh.content.top));
      expect(controller.contentBox.left, greaterThan(seventh.content.left));
      await shut(controller);
    });

    test('BUG-23: занять рамку не у кого — страница целиком', () async {
      final _GatedDocument document = gated(40);
      final Completer<void> gate = Completer<void>();
      document.gates[30] = gate;
      final ReaderController controller = await open(document);
      await controller.setAutoCrop(true);

      await controller.goToPage(30);
      expect(controller.contentBox, CropBox.full);

      gate.complete();
      await _idle();
      expect(controller.contentBox, isNot(CropBox.full));
      await shut(controller);
    });

    test('BUG-23: опоздавшая рамка чужую страницу не подрезает', () async {
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[8] = gate;
      final ReaderController controller = await open(document);

      await controller.goToPage(8);
      await controller.goToPage(3);
      expect(controller.frame?.pageNumber, 3);

      // Рамка восьмой досчиталась, когда читатель уже на третьей.
      gate.complete();
      await _idle();
      expect(controller.page, 3);
      expect(controller.frame?.pageNumber, 3);
      await shut(controller);
    });

    test('BUG-23: назад читатель попадает в низ и остаётся в нём', () async {
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[5] = gate;
      final ReaderController controller = await open(document);
      await controller.setDisplayMode(PageDisplayMode.half);
      await controller.goToPage(6);
      await _idle();

      expect(await controller.previousFragment(), isTrue);
      expect(controller.page, 5);
      expect(controller.fragment, 1, reason: 'низ предыдущей страницы');

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 5);
      expect(controller.fragment, 1, reason: 'подрезка места не сбила');
      await shut(controller);
    });

    test('BUG-23: закрытая книга отпускает переход, ждавший рамку', () async {
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[8] = gate;
      final ReaderController controller = await open(
        document,
        frameWait: const Duration(seconds: 30),
      );

      final Future<bool> jump = controller.goToPage(8);
      await controller.close();
      expect(await jump.timeout(const Duration(seconds: 5)), isFalse);
      gate.complete();
      controller.dispose();
    });
  });

  group('F-READ-02: рамки соседних листов считаются заранее', () {
    test('F-READ-02: после открытия готовы два листа вперёд', () async {
      final FakeReaderDocument document = plain(12);
      final ReaderController controller = await open(document);

      expect(document.boxReads.keys.toSet(), <int>{1, 2, 3});
      await shut(controller);
    });

    test('F-READ-02: после перехода — вперёд по ходу и лист назад', () async {
      final FakeReaderDocument document = plain(20);
      final ReaderController controller = await open(document);

      await controller.goToPage(9);
      await _idle();
      expect(document.boxReads.keys.toSet(), <int>{1, 2, 3, 8, 9, 10, 11});
      await shut(controller);
    });

    test('F-READ-02: листают назад — готовится то, что позади', () async {
      final FakeReaderDocument document = plain(20);
      final ReaderController controller = await open(document);
      await controller.goToPage(9);
      await _idle();

      expect(await controller.previousFragment(), isTrue);
      await _idle();
      expect(controller.page, 8);
      expect(document.boxReads.keys, containsAll(<int>[6, 7]));
      expect(document.boxReads[12], isNull, reason: 'вперёд не готовили');
      await shut(controller);
    });

    test('F-READ-02: в развороте готовятся обе страницы листа', () async {
      final FakeReaderDocument document = plain(20);
      final ReaderController controller = await open(document);
      await controller.setDisplayMode(PageDisplayMode.spread);

      await controller.goToPage(2);
      await _idle();
      expect(controller.sheetPages, <int>[2, 3]);
      expect(document.boxReads.keys, containsAll(<int>[4, 5, 6, 7]));
      await shut(controller);
    });

    test('F-READ-02: уход обрывает подготовку рамок', () async {
      // Рамки вокруг страницы, с которой читатель уже ушёл, ему не
      // соседние: считать их значит отнимать движок у страницы на экране.
      final _GatedDocument document = gated(20);
      final Completer<void> gate = Completer<void>();
      document.gates[10] = gate;
      final ReaderController controller = await open(document);

      await controller.goToPage(9);
      await _idle();
      // Подготовка встала на десятой; одиннадцатая и восьмая — за ней.
      await controller.goToPage(15);
      await _idle();
      gate.complete();
      await _idle();

      expect(document.boxReads[11], isNull);
      expect(document.boxReads[8], isNull);
      expect(document.boxReads[16], 1, reason: 'готовится новое место');
      await shut(controller);
    });

    test('F-READ-02: при чтении подряд каждая рамка считается раз', () async {
      final FakeReaderDocument document = plain(12);
      final ReaderController controller = await open(document);

      for (int step = 0; step < 8; step++) {
        expect(await controller.nextFragment(), isTrue);
        expect(
          controller.frame?.pageNumber,
          controller.page,
          reason: 'рамка страницы ${controller.page} готова к приходу',
        );
        await _idle();
      }
      expect(controller.page, 9);
      expect(document.boxReads.values.toSet(), <int>{1});
      await shut(controller);
    });
  });

  group('BUG-23: лента', () {
    test('BUG-23: рамка пролистанной в ленте страницы не считается', () async {
      // Прежде каждая страница, мелькнувшая в ленте, запускала разбор —
      // на скане это рендер за рендером, пока читатель просто листает.
      final FakeReaderDocument document = plain(60);
      final ReaderController controller = await open(document);
      controller.setSheetModes(enabled: false);

      for (int page = 2; page <= 40; page++) {
        controller.onPageChanged(page);
      }
      await _idle();
      expect(controller.page, 40);
      expect(document.boxReads.keys.toSet(), <int>{1, 2, 3});

      // Вернулись к листам — рамка считается там, где читатель встал.
      controller.setSheetModes(enabled: true);
      await controller.loadFrame();
      expect(controller.frame?.pageNumber, 40);
      await shut(controller);
    });
  });

  group('F-READ-02: открытие книги', () {
    test('F-READ-02: страница открытия измеряется до первого кадра', () async {
      // Книга открывается, не измеряя все свои страницы; та, с которой
      // начнётся чтение, и её соседи обязаны лечь по настоящим размерам.
      final FakeReaderDocument document = plain(20);
      final ReaderController controller = await open(
        document,
        saved: const ReadingPosition(bookId: 'book-read', page: 13),
      );

      expect(document.measured, <int>[12, 13, 14]);
      await shut(controller);
    });

    test('F-READ-02: первый кадр ждёт рамку, но не дольше срока', () async {
      final _GatedDocument document = gated(12);
      final Completer<void> gate = Completer<void>();
      document.gates[1] = gate;
      final Book book = fakeBook(pageCount: 12);
      await data.library.save(book);
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: data.reading,
      );

      await controller.settleFrame(limit: const Duration(milliseconds: 30));
      expect(controller.frame, isNull, reason: 'скан: рамка ещё считается');

      gate.complete();
      await _idle();
      expect(controller.frame?.pageNumber, 1);
      await shut(controller);
    });

    test('F-READ-02: рамка готова — первый кадр срока не ждёт', () async {
      final Book book = fakeBook(pageCount: 12);
      await data.library.save(book);
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(plain(12)),
        reading: data.reading,
      );

      await controller
          .settleFrame(limit: const Duration(seconds: 30))
          .timeout(const Duration(seconds: 5));
      expect(controller.frame?.pageNumber, 1);
      await shut(controller);
    });
  });
}
