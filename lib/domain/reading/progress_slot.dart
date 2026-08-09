/// Где на экране разместить указатель места в книге — чистая математика.
///
/// Страница почти никогда не совпадает с экраном по пропорциям, и вокруг
/// неё остаются поля: в вертикальном чтении сверху и снизу, в
/// горизонтальном — слева и справа. Эти поля и так пустуют, а читателю
/// без панелей негде понять, где он в книге. Указатель занимает поле, а
/// не отнимает страницу.
///
/// Если поля нет вовсе (страница совпала с экраном), указатель ложится
/// поверх нижнего края — и об этом честно сообщает [ProgressSlot.overlaps],
/// чтобы интерфейс мог подложить фон.
library;

import 'sheet_placement.dart';

/// С какой стороны лежит поле, отданное указателю.
enum ProgressSlotSide {
  /// Поле справа от страницы: указатель вертикальный.
  right,

  /// Поле снизу: указатель горизонтальный.
  bottom,
}

/// Прямоугольник под указатель места.
class ProgressSlot {
  /// Создаёт место под указатель.
  const ProgressSlot({
    required this.side,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.overlaps,
  });

  /// С какой стороны стоит указатель.
  final ProgressSlotSide side;

  /// Отступ слева.
  final double left;

  /// Отступ сверху.
  final double top;

  /// Ширина.
  final double width;

  /// Высота.
  final double height;

  /// Лёг ли указатель поверх страницы, а не в свободное поле.
  final bool overlaps;

  /// Вертикальный ли указатель.
  bool get isVertical => side == ProgressSlotSide.right;

  /// Есть ли куда рисовать.
  bool get isVisible => width > 0 && height > 0;

  @override
  bool operator ==(Object other) {
    return other is ProgressSlot &&
        other.side == side &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height &&
        other.overlaps == overlaps;
  }

  @override
  int get hashCode => Object.hash(side, left, top, width, height, overlaps);

  @override
  String toString() =>
      'ProgressSlot($side, $left, $top, ${width}x$height, поверх: $overlaps)';
}

/// Подбирает поле под указатель места.
///
/// Сначала пробуется поле справа: в горизонтальном чтении оно самое
/// широкое, а вертикальная полоска там не мешает строке. Потом нижнее —
/// в вертикальном чтении именно оно и остаётся. Если ни одно поле не
/// дотягивает до [thickness], указатель ложится поверх нижнего края.
ProgressSlot progressSlotFor({
  required SheetPlacement placement,
  required double screenWidth,
  required double screenHeight,
  double thickness = 22,
}) {
  final double rightField = placement.isVisible
      ? screenWidth - (placement.left + placement.sheetWidth)
      : 0;
  final double bottomField = placement.isVisible
      ? screenHeight - (placement.top + placement.sheetHeight)
      : screenHeight;

  if (rightField >= thickness) {
    return ProgressSlot(
      side: ProgressSlotSide.right,
      left: screenWidth - rightField,
      top: 0,
      width: rightField,
      height: screenHeight,
      overlaps: false,
    );
  }
  if (bottomField >= thickness) {
    return ProgressSlot(
      side: ProgressSlotSide.bottom,
      left: 0,
      top: screenHeight - bottomField,
      width: screenWidth,
      height: bottomField,
      overlaps: false,
    );
  }
  return ProgressSlot(
    side: ProgressSlotSide.bottom,
    left: 0,
    top: screenHeight - thickness,
    width: screenWidth,
    height: thickness,
    overlaps: true,
  );
}
