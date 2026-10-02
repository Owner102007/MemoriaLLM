import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// Текст страницы с зеркальными полями, как в переплёте: у чётной
/// (левой на развороте) широкое поле справа, у нечётной — слева.
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
/// Гонку переходов иначе не воспроизвести: в подставном документе все
/// страницы разбираются одинаково быстро, а в настоящем скан считается
/// дольше страницы с текстом, и рамки приходят не в том порядке, в каком
/// их просили.
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

/// Что сейчас на экране: страницы листа и номер полосы.
String _screen(ReaderController controller) =>
    '${controller.sheetPages.join('+')}:${controller.fragment}';

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<ReaderController> open({
    int pages = 7,
    FakeReaderDocument? document,
  }) async {
    final Book book = fakeBook(pageCount: pages);
    await data.library.save(book);
    final FakeReaderDocument source =
        document ??
        FakeReaderDocument(pages: _texts(pages), boxes: _boxes(pages));
    final ReaderController controller = await ReaderController.open(
      book: book,
      opener: FakeDocumentOpener(source),
      reading: data.reading,
      saveDelay: const Duration(milliseconds: 150),
    );
    await controller.loadFrame();
    return controller;
  }

  /// Листает до упора и записывает каждый экран по дороге.
  Future<List<String>> walk(
    ReaderController controller, {
    required bool forward,
  }) async {
    final List<String> screens = <String>[_screen(controller)];
    // Потолок шагов: зацикленное листание должно упасть в сравнении, а
    // не повесить прогон.
    for (int step = 0; step < 100; step++) {
      final bool moved = forward
          ? await controller.nextFragment()
          : await controller.previousFragment();
      if (!moved) {
        break;
      }
      screens.add(_screen(controller));
    }
    return screens;
  }

  group('F-READ-06: листание разворота', () {
    test('BUG-01: разворот листается парами, экран не повторяется', () async {
      // Прежде шаг вёл на страницу + 1, и вместо четырёх экранов выходило
      // семь: каждый разворот показывался дважды.
      final ReaderController controller = await open();
      await controller.setDisplayMode(PageDisplayMode.spread);

      expect(await walk(controller, forward: true), <String>[
        '1:0',
        '2+3:0',
        '4+5:0',
        '6+7:0',
      ]);
      expect(await walk(controller, forward: false), <String>[
        '6+7:0',
        '4+5:0',
        '2+3:0',
        '1:0',
      ]);
      await controller.close();
      controller.dispose();
    });

    test('BUG-01: книга с чётным числом страниц кончается одной', () async {
      final ReaderController controller = await open(pages: 6);
      await controller.setDisplayMode(PageDisplayMode.spread);

      expect(await walk(controller, forward: true), <String>[
        '1:0',
        '2+3:0',
        '4+5:0',
        '6:0',
      ]);
      await controller.close();
      controller.dispose();
    });

    test('BUG-01: полразворота идёт полосами через лист', () async {
      final ReaderController controller = await open(pages: 5);
      await controller.setDisplayMode(PageDisplayMode.spreadHalf);

      expect(await walk(controller, forward: true), <String>[
        '1:0',
        '1:1',
        '2+3:0',
        '2+3:1',
        '4+5:0',
        '4+5:1',
      ]);
      // Назад — в низ предыдущего разворота, а не в его начало.
      expect(await walk(controller, forward: false), <String>[
        '4+5:1',
        '4+5:0',
        '2+3:1',
        '2+3:0',
        '1:1',
        '1:0',
      ]);
      await controller.close();
      controller.dispose();
    });

    test('шаг с правой страницы разворота уводит на следующий', () async {
      // На правую страницу читатель попадает из поиска или оглавления.
      final ReaderController controller = await open();
      await controller.setDisplayMode(PageDisplayMode.spread);
      await controller.goToPage(3);
      expect(controller.sheetPages, <int>[2, 3]);

      expect(await controller.nextFragment(), isTrue);
      expect(controller.sheetPages, <int>[4, 5]);
      await controller.close();
      controller.dispose();
    });

    test('стрелки панели шагают листами', () async {
      final ReaderController controller = await open();
      expect(controller.nextSheetStart, 2);
      expect(controller.previousSheetStart, isNull);

      await controller.setDisplayMode(PageDisplayMode.spread);
      await controller.goToPage(4);
      expect(controller.nextSheetStart, 6);
      expect(controller.previousSheetStart, 2);

      await controller.goToPage(6);
      expect(controller.nextSheetStart, isNull);
      await controller.close();
      controller.dispose();
    });

    test('подпись называет обе страницы, конец книги — 100 %', () async {
      final ReaderController controller = await open();
      await controller.setDisplayMode(PageDisplayMode.spread);
      expect(controller.label, '1 / 7');

      await controller.goToPage(2);
      expect(controller.label, '2–3 / 7');
      expect(controller.progress, closeTo(3 / 7, 1e-9));

      // Последний разворот: правая страница — последняя в книге. По
      // левой вышло бы 86 %, хотя книга дочитана.
      await controller.goToPage(6);
      expect(controller.label, '6–7 / 7');
      expect(controller.progress, 1);
      expect(controller.lastShownPage, 7);

      await controller.flush();
      final ReadingPosition saved = (await data.reading.position('book-read'))!;
      expect(saved.page, 6, reason: 'место — страница, а не лист');
      expect(saved.progress, 1);
      await controller.close();
      controller.dispose();
    });

    test('в ленте разворота нет: лист — одна страница', () async {
      // Лента режимов листа не знает. Режим «разворот» при этом остаётся
      // в настройках книги и вернётся вместе с листанием по страницам.
      final ReaderController controller = await open();
      await controller.setDisplayMode(PageDisplayMode.spread);
      await controller.goToPage(2);

      controller.setSheetModes(enabled: false);
      expect(controller.sheetPages, <int>[2]);
      expect(controller.label, '2 / 7');
      expect(controller.nextSheetStart, 3);
      expect(controller.previousSheetStart, 1);

      controller.setSheetModes(enabled: true);
      expect(controller.sheetPages, <int>[2, 3]);
      await controller.close();
      controller.dispose();
    });
  });

  group('F-READ-06: рамка разворота', () {
    test('BUG-02: автообрезка не срезает текст ни одной страницы', () async {
      final ReaderController controller = await open(pages: 6);
      await controller.setAutoCrop(true);
      await controller.goToPage(2);
      await controller.setDisplayMode(PageDisplayMode.spread);
      expect(controller.sheetPages, <int>[2, 3]);

      // Текст левой страницы начинается с 0,08 её ширины — это 0,04
      // ширины листа. Прежде рамка страницы (около 0,07) шла в лист как
      // есть, и левый край текста оказывался за рамкой.
      final CropBox sheet = controller.contentBox;
      expect(sheet.isValid, isTrue);
      expect(sheet.left, lessThanOrEqualTo(0.04));
      expect(sheet.left, greaterThan(0), reason: 'поле всё же обрезано');
      // Текст правой страницы кончается на 0,916 её ширины.
      expect(sheet.right, greaterThanOrEqualTo(0.5 + 0.916 / 2));
      expect(sheet.right, lessThan(1), reason: 'рамка соседней посчитана');

      // Рамка самой страницы осталась в долях страницы: её правит
      // редактор рамки, а он показывает одну страницу.
      expect(controller.pageContentBox.left, greaterThan(sheet.left));
      await controller.close();
      controller.dispose();
    });

    test('BUG-02: ручная рамка разворота — поля страницы, не листа', () async {
      final ReaderController controller = await open(pages: 6);
      const CropBox manual = CropBox(
        left: 0.05,
        top: 0.06,
        right: 0.95,
        bottom: 0.94,
      );
      await controller.setManualCrop(manual);
      await controller.goToPage(4);
      await controller.setDisplayMode(PageDisplayMode.spread);

      final CropBox sheet = controller.contentBox;
      expect(sheet.left, closeTo(0.025, 1e-9));
      expect(sheet.right, closeTo(0.975, 1e-9));
      expect(sheet.top, closeTo(0.06, 1e-9));
      expect(sheet.bottom, closeTo(0.94, 1e-9));
      expect(controller.pageContentBox, manual);
      await controller.close();
      controller.dispose();
    });

    test('на обложке и на одной странице рамка прежняя', () async {
      final ReaderController controller = await open(pages: 6);
      await controller.setAutoCrop(true);
      final CropBox page = controller.contentBox;

      await controller.setDisplayMode(PageDisplayMode.spread);
      expect(controller.sheetPages, <int>[1]);
      expect(controller.contentBox, page);
      expect(controller.pageContentBox, page);
      await controller.close();
      controller.dispose();
    });

    test('полразворота делит лист, а не страницу', () async {
      final ReaderController controller = await open(pages: 6);
      await controller.setAutoCrop(true);
      await controller.goToPage(2);
      await controller.setDisplayMode(PageDisplayMode.spreadHalf);

      final CropBox sheet = controller.contentBox;
      expect(controller.fragmentCount, 2);
      expect(controller.fragmentBox.left, sheet.left);
      expect(controller.fragmentBox.right, sheet.right);
      expect(
        controller.fragmentBox.height,
        lessThan(sheet.height * 0.6),
        reason: 'полоса — половина листа по высоте',
      );
      await controller.close();
      controller.dispose();
    });
  });

  group('гонка переходов', () {
    test('BUG-11: побеждает последний запрошенный переход', () async {
      // Пятая страница считается долго (скан), третья — сразу. Прежде
      // экран вставал на ту, чья рамка досчиталась последней, то есть на
      // пятую, хотя читатель уже ушёл на третью.
      final _GatedDocument document = _GatedDocument(pages: _texts(10));
      final Completer<void> gate = Completer<void>();
      document.gates[5] = gate;
      final ReaderController controller = await open(
        pages: 10,
        document: document,
      );

      final Future<bool> slow = controller.goToPage(5);
      final Future<bool> fast = controller.goToPage(3);
      expect(await fast, isTrue);
      expect(controller.page, 3);

      gate.complete();
      expect(await slow, isFalse, reason: 'переход обогнали');
      expect(controller.page, 3, reason: 'устаревший переход отброшен');
      await controller.close();
      controller.dispose();
    });

    test('BUG-11: стрелка панели считает от цели перехода', () async {
      // Стрелку нажали, рамка ещё считается — второе нажатие обязано
      // вести дальше, а не на ту же страницу.
      final _GatedDocument document = _GatedDocument(pages: _texts(10));
      final Completer<void> gate = Completer<void>();
      document.gates[2] = gate;
      final ReaderController controller = await open(
        pages: 10,
        document: document,
      );
      expect(controller.nextSheetStart, 2);

      final Future<bool> jump = controller.goToPage(2);
      expect(controller.page, 1, reason: 'экран ещё на первой');
      expect(controller.nextSheetStart, 3);
      expect(controller.previousSheetStart, 1);

      gate.complete();
      expect(await jump, isTrue);
      expect(controller.page, 2);
      expect(controller.nextSheetStart, 3);
      await controller.close();
      controller.dispose();
    });

    test('BUG-11: два быстрых шага вперёд — это два шага', () async {
      // Прежде второе нажатие считало от страницы на экране, а не от
      // той, куда уже шёл первый переход: два нажатия давали один шаг.
      final _GatedDocument document = _GatedDocument(pages: _texts(10));
      final Completer<void> gate = Completer<void>();
      document.gates[2] = gate;
      final ReaderController controller = await open(
        pages: 10,
        document: document,
      );

      final Future<bool> first = controller.nextFragment();
      final Future<bool> second = controller.nextFragment();
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(controller.page, 3);
      await controller.close();
      controller.dispose();
    });

    test('BUG-11: быстрый шаг через границу страницы помнит полосу', () async {
      final _GatedDocument document = _GatedDocument(
        pages: _texts(10),
        boxes: _boxes(10),
      );
      final Completer<void> gate = Completer<void>();
      document.gates[2] = gate;
      final ReaderController controller = await open(
        pages: 10,
        document: document,
      );
      await controller.setDisplayMode(PageDisplayMode.half);
      expect(await controller.nextFragment(), isTrue);
      expect(_screen(controller), '1:1');

      // Первый шаг ведёт на вторую страницу, второй — в её нижнюю
      // полосу, а не на третью страницу.
      final Future<bool> first = controller.nextFragment();
      final Future<bool> second = controller.nextFragment();
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(_screen(controller), '2:1');
      await controller.close();
      controller.dispose();
    });

    test('BUG-11: шаг назад во время перехода считается от цели', () async {
      final _GatedDocument document = _GatedDocument(pages: _texts(10));
      final Completer<void> gate = Completer<void>();
      document.gates[7] = gate;
      final ReaderController controller = await open(
        pages: 10,
        document: document,
      );

      final Future<bool> jump = controller.goToPage(7);
      final Future<bool> back = controller.previousFragment();
      gate.complete();
      expect(await jump, isFalse);
      expect(await back, isTrue);
      expect(controller.page, 6);
      await controller.close();
      controller.dispose();
    });
  });
}
