import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';
import 'package:memoria/domain/reading/window_settle.dart';

DisplayArea _area(double width, double height) =>
    DisplayArea(width: width, height: height);

/// F-DESK-02, ALG-UI-27: живое окно без растяжения.
///
/// Две половины. Отсчёт: пока окно на ПК тянут за край, лист держит
/// прежний размер и перекладывается один раз — когда окно перестали
/// трогать. И сетка размеров окна: в какой бы форме окно ни оказалось,
/// режим деления не делает текст мельче, чем у страницы целиком.
///
/// Отсчёт проверяется в `testWidgets` не ради виджетов, а ради времени:
/// там оно подменено, и полтораста миллисекунд проходят по команде.
void main() {
  group('F-DESK-02: отсчёт', () {
    late int settled;
    late WindowSettle settle;

    setUp(() {
      settled = 0;
      settle = WindowSettle(onSettled: () => settled++);
    });
    tearDown(() => settle.dispose());

    /// Первый размер: окно только что открылось.
    void open() {
      expect(settle.offerArea(_area(1280, 800), hold: true), isTrue);
      expect(
        settle.offerBox(const Size(1280, 800), hold: true),
        const Size(1280, 800),
      );
    }

    /// Окно сменило размер, пока его держат.
    Size drag(double width, double height) {
      expect(settle.offerArea(_area(width, height), hold: true), isFalse);
      return settle.offerBox(Size(width, height), hold: true);
    }

    testWidgets('первый размер принимается сразу', (WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      open();

      expect(settle.area, _area(1280, 800));
      expect(settle.box, const Size(1280, 800));
      expect(settle.waiting, isFalse);
      expect(settled, 0);
    });

    testWidgets('серия изменений размера даёт одну перекладку', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      open();

      // Окно тянут за край: сорок размеров подряд, по кадру на каждый.
      for (int step = 1; step <= 40; step++) {
        expect(drag(1280 + step * 10, 800), const Size(1280, 800));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(settled, 0);
      expect(settle.waiting, isTrue);
      expect(settle.area, _area(1280, 800));
      expect(settle.box, const Size(1280, 800));

      // Окно отпустили.
      await tester.pump(kWindowSettle);
      expect(settled, 1);
      expect(settle.waiting, isFalse);
      expect(settle.area, _area(1680, 800));
      expect(settle.box, const Size(1680, 800));

      // И больше ничего не происходит.
      await tester.pump(kWindowSettle * 3);
      expect(settled, 1);
    });

    testWidgets('заминка руки короче отсчёта перекладки не даёт', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      open();

      drag(1400, 800);
      await tester.pump(kWindowSettle - const Duration(milliseconds: 20));
      drag(1500, 800);
      await tester.pump(kWindowSettle - const Duration(milliseconds: 20));
      expect(settled, 0);

      await tester.pump(const Duration(milliseconds: 40));
      expect(settled, 1);
      expect(settle.box, const Size(1500, 800));
    });

    testWidgets('повторное сообщение того же размера отсчёт не продлевает', (
      WidgetTester tester,
    ) async {
      // Экран перестраивается и без смены размера — от любого
      // уведомления книги. Это не движение окна.
      await tester.pumpWidget(const SizedBox());
      open();

      drag(1400, 800);
      await tester.pump(const Duration(milliseconds: 100));
      expect(drag(1400, 800), const Size(1280, 800));
      await tester.pump(const Duration(milliseconds: 60));

      expect(settled, 1);
      expect(settle.box, const Size(1400, 800));
    });

    testWidgets('окно вернули к прежнему размеру — перекладывать нечего', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      open();

      drag(1400, 900);
      drag(1280, 800);
      await tester.pump(kWindowSettle * 2);

      expect(settled, 0);
      expect(settle.waiting, isFalse);
      expect(settle.box, const Size(1280, 800));
    });

    testWidgets('форма окна и место под лист принимаются вместе', (
      WidgetTester tester,
    ) async {
      // Иначе режим успел бы пересчитаться под новое окно, пока лист ещё
      // лежит по-старому.
      await tester.pumpWidget(const SizedBox());
      open();

      expect(settle.offerArea(_area(1600, 900), hold: true), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        settle.offerBox(const Size(1600, 860), hold: true),
        const Size(1280, 800),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(settled, 0, reason: 'место под лист продлило отсчёт');

      await tester.pump(const Duration(milliseconds: 60));
      expect(settled, 1);
      expect(settle.area, _area(1600, 900));
      expect(settle.box, const Size(1600, 860));
    });

    testWidgets('на телефоне размер принимается сразу', (
      WidgetTester tester,
    ) async {
      // Поворот экрана — одно изменение, и ждать после него нечего.
      await tester.pumpWidget(const SizedBox());
      expect(settle.offerArea(_area(400, 800), hold: false), isTrue);
      expect(
        settle.offerBox(const Size(400, 800), hold: false),
        const Size(400, 800),
      );

      expect(settle.offerArea(_area(800, 400), hold: false), isTrue);
      expect(
        settle.offerBox(const Size(800, 400), hold: false),
        const Size(800, 400),
      );
      expect(settle.waiting, isFalse);
      expect(settled, 0);
    });

    testWidgets('разворот во весь экран принимается сразу', (
      WidgetTester tester,
    ) async {
      // F-READ-35: окно меняет размер по нашей же просьбе — это не
      // протяжка.
      await tester.pumpWidget(const SizedBox());
      open();

      expect(settle.offerArea(_area(1920, 1080), hold: false), isTrue);
      expect(
        settle.offerBox(const Size(1920, 1080), hold: false),
        const Size(1920, 1080),
      );
      expect(settle.waiting, isFalse);

      // А протяжка после него снова ждёт.
      expect(drag(1800, 1000), const Size(1920, 1080));
      expect(settle.waiting, isTrue);
      await tester.pump(kWindowSettle);
      expect(settle.box, const Size(1800, 1000));
    });

    testWidgets('после свёрнутого окна размер принимается сразу', (
      WidgetTester tester,
    ) async {
      // Свёрнутое окно раскладывается в ноль на ноль. Развернули —
      // держать нечего.
      await tester.pumpWidget(const SizedBox());
      open();

      drag(0, 0);
      await tester.pump(kWindowSettle);
      expect(settled, 1);
      expect(settle.box, Size.zero);
      expect(settle.area.isKnown, isFalse);

      expect(settle.offerArea(_area(1280, 800), hold: true), isTrue);
      expect(
        settle.offerBox(const Size(1280, 800), hold: true),
        const Size(1280, 800),
      );
      expect(settle.waiting, isFalse);
    });

    testWidgets('забытое место под лист принимается заново сразу', (
      WidgetTester tester,
    ) async {
      // Лист уходил с экрана — была лента. Окно за это время изменилось.
      await tester.pumpWidget(const SizedBox());
      open();

      settle.releaseBox();
      expect(settle.box, isNull);
      expect(
        settle.offerBox(const Size(900, 700), hold: true),
        const Size(900, 700),
      );
      expect(settle.waiting, isFalse);
    });

    testWidgets('закрытый экран отсчёт не дожидается', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      open();

      drag(1400, 800);
      settle.dispose();
      await tester.pump(kWindowSettle * 2);

      expect(settled, 0);
      expect(settle.waiting, isFalse);
    });
  });

  group('F-DESK-02: сетка размеров окна', () {
    // От 800×600 до 3840×2160, включая узкое высокое и низкое широкое.
    const List<Size> windows = <Size>[
      Size(800, 600),
      Size(1024, 768),
      Size(1280, 720),
      Size(1280, 800),
      Size(1366, 768),
      Size(1600, 900),
      Size(1920, 1080),
      Size(2560, 1440),
      Size(3840, 2160),
      Size(600, 1400),
      Size(480, 1000),
      Size(900, 1600),
      Size(1600, 480),
      Size(2560, 600),
    ];
    // Книжная страница, альбомная, квадратная и разворот.
    const List<Size> sheets = <Size>[
      Size(595, 842),
      Size(612, 792),
      Size(842, 595),
      Size(500, 500),
      Size(1190, 842),
    ];
    const List<CropBox> contents = <CropBox>[
      CropBox.full,
      CropBox(left: 0.1, top: 0.08, right: 0.9, bottom: 0.92),
      CropBox(left: 0.2, top: 0.05, right: 0.95, bottom: 0.6),
    ];
    const List<PageDisplayMode> modes = <PageDisplayMode>[
      PageDisplayMode.half,
      PageDisplayMode.third,
      PageDisplayMode.spreadHalf,
    ];
    const List<double> overlaps = <double>[
      0,
      kDefaultStripOverlap,
      kMaxStripOverlap,
    ];

    /// Масштаб страницы целиком в окне.
    double wholeScale(Size window, Size sheet, CropBox content) {
      return placeFragment(
        sheetWidth: sheet.width,
        sheetHeight: sheet.height,
        fragment: content,
        screenWidth: window.width,
        screenHeight: window.height,
      ).scale;
    }

    /// Масштаб самой мелкой полосы режима в окне — как её кладёт лист.
    double worstStripScale(
      Size window,
      Size sheet,
      CropBox content,
      PageDisplayMode mode,
      double overlap,
    ) {
      final int count = fragmentCountFor(mode: mode);
      double worst = double.infinity;
      for (final CropBox part in fragmentsFor(content: content, mode: mode)) {
        final double scale = placeFragment(
          sheetWidth: sheet.width,
          sheetHeight: sheet.height,
          fragment: part,
          screenWidth: window.width,
          screenHeight: window.height,
          overlap: stripOverlapFor(overlap: overlap, count: count),
          anchorTop: true,
        ).scale;
        if (scale < worst) {
          worst = scale;
        }
      }
      return worst;
    }

    test('режим не уменьшает кегль ни в каком окне', () {
      int checked = 0;
      for (final Size window in windows) {
        for (final Size sheet in sheets) {
          for (final CropBox content in contents) {
            final double whole = wholeScale(window, sheet, content);
            expect(whole, greaterThan(0));
            for (final PageDisplayMode mode in modes) {
              for (final double overlap in overlaps) {
                final double strip = worstStripScale(
                  window,
                  sheet,
                  content,
                  mode,
                  overlap,
                );
                expect(
                  strip,
                  greaterThanOrEqualTo(whole * (1 - 1e-9)),
                  reason:
                      'окно $window, лист $sheet, рамка $content, '
                      '$mode, нахлёст $overlap',
                );
                checked++;
              }
            }
          }
        }
      }
      expect(checked, greaterThan(1500));
    });

    test('кнопка-дробь обещает ровно то, что выйдет в этом окне', () {
      // Форма окна на ПК играет роль положения экрана: поворачивать
      // нечего, и выигрыш режима считается по окну как оно есть.
      for (final Size window in windows) {
        for (final Size sheet in sheets) {
          for (final CropBox content in contents) {
            for (final PageDisplayMode mode in modes) {
              for (final double overlap in overlaps) {
                final FragmentLayout layout = chooseFragmentLayout(
                  mode: mode,
                  content: content,
                  sheetWidth: sheet.width,
                  sheetHeight: sheet.height,
                  area: _area(window.width, window.height),
                  canTurn: false,
                  overlap: overlap,
                );
                final String reason =
                    'окно $window, лист $sheet, рамка $content, '
                    '$mode, нахлёст $overlap';
                final double whole = wholeScale(window, sheet, content);
                final double strip = worstStripScale(
                  window,
                  sheet,
                  content,
                  mode,
                  overlap,
                );

                expect(layout.area, _area(window.width, window.height));
                expect(
                  layout.wholeScale,
                  closeTo(whole, whole * 1e-9),
                  reason: reason,
                );
                expect(
                  layout.scale,
                  closeTo(strip, strip * 1e-9),
                  reason: reason,
                );
                expect(
                  layout.gain,
                  greaterThanOrEqualTo(1 - 1e-9),
                  reason: reason,
                );
              }
            }
          }
        }
      }
    });

    test('узкое высокое окно: деление без выигрыша не включается', () {
      // Страница вписана по ширине, и полоса той же ширины крупнее не
      // станет — режим честно называет себя бесполезным.
      final FragmentLayout layout = chooseFragmentLayout(
        mode: PageDisplayMode.half,
        content: CropBox.full,
        sheetWidth: 595,
        sheetHeight: 842,
        area: _area(600, 1400),
        canTurn: false,
        overlap: kDefaultStripOverlap,
      );

      expect(layout.gain, closeTo(1, 1e-9));
      expect(layout.isWorthwhile, isFalse);
    });

    test('широкое окно: деление увеличивает текст', () {
      final FragmentLayout layout = chooseFragmentLayout(
        mode: PageDisplayMode.half,
        content: CropBox.full,
        sheetWidth: 595,
        sheetHeight: 842,
        area: _area(1920, 1080),
        canTurn: false,
        overlap: kDefaultStripOverlap,
      );

      expect(layout.gain, greaterThan(1.5));
      expect(layout.isWorthwhile, isTrue);
    });
  });
}
