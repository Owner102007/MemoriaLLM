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
}
