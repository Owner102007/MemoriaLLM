import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/progress_slot.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';

/// Указатель места должен занимать поле вокруг страницы, а не отнимать
/// у неё пространство. Поэтому проверяется главное: он попадает именно
/// в пустоту и не залезает на лист.
void main() {
  test('в вертикальном чтении указатель ложится под страницу', () {
    // Страница А4 в вертикальном экране упирается в ширину, и пустота
    // остаётся сверху и снизу.
    final SheetPlacement placement = placeFragment(
      sheetWidth: 595,
      sheetHeight: 842,
      fragment: CropBox.full,
      screenWidth: 360,
      screenHeight: 800,
    );
    final ProgressSlot slot = progressSlotFor(
      placement: placement,
      screenWidth: 360,
      screenHeight: 800,
    );

    expect(slot.side, ProgressSlotSide.bottom);
    expect(slot.overlaps, isFalse);
    expect(slot.isVertical, isFalse);
    expect(
      slot.top,
      greaterThanOrEqualTo(placement.top + placement.sheetHeight - 1e-9),
      reason: 'указатель начинается там, где кончилась страница',
    );
  });

  test('в горизонтальном чтении указатель встаёт сбоку', () {
    final SheetPlacement placement = placeFragment(
      sheetWidth: 595,
      sheetHeight: 842,
      fragment: CropBox.full,
      screenWidth: 800,
      screenHeight: 360,
    );
    final ProgressSlot slot = progressSlotFor(
      placement: placement,
      screenWidth: 800,
      screenHeight: 360,
    );

    expect(slot.side, ProgressSlotSide.right);
    expect(slot.isVertical, isTrue);
    expect(slot.overlaps, isFalse);
    expect(
      slot.left,
      greaterThanOrEqualTo(placement.left + placement.sheetWidth - 1e-9),
      reason: 'указатель правее страницы',
    );
  });

  test('когда поля нет, указатель честно признаётся, что лёг поверх', () {
    // Страница ровно по экрану: пустоты не осталось вовсе.
    final SheetPlacement placement = placeFragment(
      sheetWidth: 100,
      sheetHeight: 200,
      fragment: CropBox.full,
      screenWidth: 100,
      screenHeight: 200,
    );
    final ProgressSlot slot = progressSlotFor(
      placement: placement,
      screenWidth: 100,
      screenHeight: 200,
    );

    expect(slot.overlaps, isTrue);
    expect(slot.side, ProgressSlotSide.bottom);
    expect(slot.height, greaterThan(0));
    expect(slot.top + slot.height, closeTo(200, 1e-9));
  });

  test('узкая щель указателю не годится', () {
    // Поле в пару точек — это не место под указатель, а щель округления.
    final SheetPlacement placement = placeFragment(
      sheetWidth: 100,
      sheetHeight: 199,
      fragment: CropBox.full,
      screenWidth: 100,
      screenHeight: 200,
    );
    final ProgressSlot slot = progressSlotFor(
      placement: placement,
      screenWidth: 100,
      screenHeight: 200,
    );
    expect(slot.overlaps, isTrue);
  });

  test('указатель всегда внутри экрана', () {
    for (final List<double> screen in <List<double>>[
      <double>[360, 800],
      <double>[800, 360],
      <double>[1000, 1000],
    ]) {
      final SheetPlacement placement = placeFragment(
        sheetWidth: 595,
        sheetHeight: 842,
        fragment: CropBox.full,
        screenWidth: screen[0],
        screenHeight: screen[1],
      );
      final ProgressSlot slot = progressSlotFor(
        placement: placement,
        screenWidth: screen[0],
        screenHeight: screen[1],
      );
      expect(slot.isVisible, isTrue, reason: '$screen');
      expect(slot.left, greaterThanOrEqualTo(-1e-9), reason: '$screen');
      expect(slot.top, greaterThanOrEqualTo(-1e-9), reason: '$screen');
      expect(
        slot.left + slot.width,
        lessThanOrEqualTo(screen[0] + 1e-9),
        reason: '$screen',
      );
      expect(
        slot.top + slot.height,
        lessThanOrEqualTo(screen[1] + 1e-9),
        reason: '$screen',
      );
    }
  });

  group('F-READ-35: указатель места в чтении во весь экран', () {
    // Страница совпала с экраном: свободного поля нет ни сбоку, ни снизу.
    final SheetPlacement tight = placeFragment(
      sheetWidth: 360,
      sheetHeight: 800,
      fragment: CropBox.full,
      screenWidth: 360,
      screenHeight: 800,
    );

    test('F-READ-35: в окне указатель ложится поверх страницы', () {
      final ProgressSlot slot = progressSlotFor(
        placement: tight,
        screenWidth: 360,
        screenHeight: 800,
      );
      expect(slot.overlaps, isTrue);
      expect(slot.isVisible, isTrue);
    });

    test('F-READ-35: во весь экран поверх страницы он не ложится', () {
      final ProgressSlot slot = progressSlotFor(
        placement: tight,
        screenWidth: 360,
        screenHeight: 800,
        overPage: false,
      );
      expect(slot, ProgressSlot.none);
      expect(slot.isVisible, isFalse);
    });

    test('F-READ-35: свободное поле указатель занимает и во весь экран', () {
      final SheetPlacement placement = placeFragment(
        sheetWidth: 595,
        sheetHeight: 842,
        fragment: CropBox.full,
        screenWidth: 360,
        screenHeight: 800,
      );
      final ProgressSlot slot = progressSlotFor(
        placement: placement,
        screenWidth: 360,
        screenHeight: 800,
        overPage: false,
      );
      expect(slot.isVisible, isTrue);
      expect(slot.overlaps, isFalse);
    });
  });

  group('F-READ-13: указатель места и полоска соседней страницы', () {
    // Страница на широком окне ПК: справа от неё поле в 300 точек.
    const SheetPlacement wide = SheetPlacement(
      scale: 1,
      left: 300,
      top: 0,
      sheetWidth: 400,
      sheetHeight: 600,
    );

    test('F-READ-13: указатель встаёт за полоской, а не поверх неё', () {
      final ProgressSlot slot = progressSlotFor(
        placement: wide,
        screenWidth: 1000,
        screenHeight: 600,
        reservedRight: 50,
      );
      expect(slot.side, ProgressSlotSide.right);
      expect(slot.left, closeTo(750, 1e-9));
      expect(slot.width, closeTo(250, 1e-9));
      expect(slot.overlaps, isFalse);
    });

    test('F-READ-13: без полоски указатель стоит у самой страницы', () {
      final ProgressSlot slot = progressSlotFor(
        placement: wide,
        screenWidth: 1000,
        screenHeight: 600,
      );
      expect(slot.left, closeTo(700, 1e-9));
      expect(slot.width, closeTo(300, 1e-9));
    });

    test('F-READ-13: полоска съела поле — указатель уходит вниз', () {
      // Справа после полоски осталось меньше, чем нужно указателю, а под
      // страницей поле есть.
      const SheetPlacement placement = SheetPlacement(
        scale: 1,
        left: 0,
        top: 0,
        sheetWidth: 300,
        sheetHeight: 400,
      );
      final ProgressSlot slot = progressSlotFor(
        placement: placement,
        screenWidth: 360,
        screenHeight: 600,
        reservedRight: 40,
      );
      expect(slot.side, ProgressSlotSide.bottom);
      expect(slot.overlaps, isFalse);
      expect(slot.top, closeTo(400, 1e-9));
    });

    test('F-READ-12: под листом указатель встаёт ниже соседней страницы', () {
      // Последняя полоса страницы: под листом виден верх следующей — на
      // высоту нахлёста. Указатель ложится под ним.
      const SheetPlacement placement = SheetPlacement(
        scale: 1,
        left: 0,
        top: -200,
        sheetWidth: 800,
        sheetHeight: 400,
      );
      final ProgressSlot slot = progressSlotFor(
        placement: placement,
        screenWidth: 800,
        screenHeight: 360,
        reservedBottom: 30,
      );
      expect(slot.side, ProgressSlotSide.bottom);
      expect(slot.top, closeTo(230, 1e-9));
      expect(slot.height, closeTo(130, 1e-9));
      expect(slot.overlaps, isFalse);
    });

    test('F-READ-13: мусор в занятом поле не двигает указатель', () {
      final ProgressSlot plain = progressSlotFor(
        placement: wide,
        screenWidth: 1000,
        screenHeight: 600,
      );
      for (final double junk in <double>[-40, double.nan, double.infinity]) {
        expect(
          progressSlotFor(
            placement: wide,
            screenWidth: 1000,
            screenHeight: 600,
            reservedRight: junk,
          ),
          plain,
          reason: '$junk',
        );
      }
    });
  });
}
