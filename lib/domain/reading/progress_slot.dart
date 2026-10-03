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

  /// Указателю некуда встать: рисовать нечего.
  static const ProgressSlot none = ProgressSlot(
    side: ProgressSlotSide.bottom,
    left: 0,
    top: 0,
    width: 0,
    height: 0,
    overlaps: false,
  );

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
/// широкое. Потом нижнее — в вертикальном чтении именно оно и остаётся.
/// Если ни одно поле не дотягивает до [thickness], указатель ложится
/// поверх нижнего края.
///
/// Толщина по умолчанию подобрана так, чтобы под рисунком книги
/// помещалась подпись «страница из скольких»: указатель без неё
/// показывает долю, но не отвечает на вопрос «а сколько осталось».
///
/// [overPage] — можно ли класть указатель поверх страницы, когда поля
/// нет. В чтении во весь экран нельзя (F-READ-35): там экран отдан
/// читаемой полосе целиком, и указатель остаётся только в свободном
/// поле.
///
/// [reservedRight] и [reservedBottom] — сколько поля у края листа занято
/// соседней страницей (F-READ-13): указатель встаёт за ней, а не поверх.
ProgressSlot progressSlotFor({
  required SheetPlacement placement,
  required double screenWidth,
  required double screenHeight,
  double thickness = 44,
  bool overPage = true,
  double reservedRight = 0,
  double reservedBottom = 0,
}) {
  final double takenRight = reservedRight.isFinite && reservedRight > 0
      ? reservedRight
      : 0;
  final double takenBottom = reservedBottom.isFinite && reservedBottom > 0
      ? reservedBottom
      : 0;
  final double rightField = placement.isVisible
      ? screenWidth - (placement.left + placement.sheetWidth) - takenRight
      : 0;
  final double bottomField = placement.isVisible
      ? screenHeight - (placement.top + placement.sheetHeight) - takenBottom
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
  if (!overPage) {
    return ProgressSlot.none;
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
