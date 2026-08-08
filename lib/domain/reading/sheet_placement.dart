/// Куда положить лист на экране — чистая математика.
///
/// **Никакого зума и панорамирования.** Читалка не «наводит объектив» на
/// кусок страницы, а раскладывает лист жёстко: нужный прямоугольник
/// вписывается в экран целиком, остальное обрезается краем экрана.
/// Масштаб не зависит ни от жестов, ни от истории — только от того, что
/// показывают и на чём.
///
/// Лист — это одна страница или две страницы разворота рядом. Фрагмент —
/// доля листа в тех же координатах, что и везде: начало в левом верхнем
/// углу, `x` вправо, `y` вниз, от 0 до 1.
library;

import 'reading.dart';

/// Готовая раскладка листа на экране.
class SheetPlacement {
  /// Создаёт раскладку.
  const SheetPlacement({
    required this.scale,
    required this.left,
    required this.top,
    required this.sheetWidth,
    required this.sheetHeight,
  });

  /// Пустая раскладка: показывать нечего.
  static const SheetPlacement none = SheetPlacement(
    scale: 0,
    left: 0,
    top: 0,
    sheetWidth: 0,
    sheetHeight: 0,
  );

  /// Во сколько раз точки листа превращаются в пиксели экрана.
  final double scale;

  /// Смещение левого края листа относительно левого края экрана.
  ///
  /// Отрицательное значение означает, что лист начинается левее экрана —
  /// именно так обрезается всё, что не входит во фрагмент.
  final double left;

  /// Смещение верхнего края листа относительно верхнего края экрана.
  final double top;

  /// Ширина всего листа на экране.
  final double sheetWidth;

  /// Высота всего листа на экране.
  final double sheetHeight;

  /// Есть ли что показывать.
  bool get isVisible => scale > 0 && sheetWidth > 0 && sheetHeight > 0;

  @override
  bool operator ==(Object other) {
    return other is SheetPlacement &&
        other.scale == scale &&
        other.left == left &&
        other.top == top &&
        other.sheetWidth == sheetWidth &&
        other.sheetHeight == sheetHeight;
  }

  @override
  int get hashCode => Object.hash(scale, left, top, sheetWidth, sheetHeight);

  @override
  String toString() =>
      'SheetPlacement(масштаб $scale, лист ${sheetWidth}x$sheetHeight, '
      'сдвиг $left, $top)';
}

/// Вписывает [fragment] листа в экран.
///
/// Масштаб берётся по той стороне, которой не хватает, поэтому фрагмент
/// целиком помещается на экране и ничего лишнего по его сторонам не
/// срезается: у страницы остаются её поля, а обрезается ровно та граница,
/// по которой лист поделён.
///
/// Если по одной из сторон остаётся запас, фрагмент центрируется: пустота
/// по краям выглядит куда спокойнее, чем прижатая к углу страница.
SheetPlacement placeFragment({
  required double sheetWidth,
  required double sheetHeight,
  required CropBox fragment,
  required double screenWidth,
  required double screenHeight,
}) {
  if (sheetWidth <= 0 ||
      sheetHeight <= 0 ||
      screenWidth <= 0 ||
      screenHeight <= 0 ||
      !fragment.isValid) {
    return SheetPlacement.none;
  }
  final double visibleWidth = sheetWidth * fragment.width;
  final double visibleHeight = sheetHeight * fragment.height;
  if (visibleWidth <= 0 || visibleHeight <= 0) {
    return SheetPlacement.none;
  }

  final double byWidth = screenWidth / visibleWidth;
  final double byHeight = screenHeight / visibleHeight;
  final double scale = byWidth < byHeight ? byWidth : byHeight;

  final double sheetOnScreenWidth = sheetWidth * scale;
  final double sheetOnScreenHeight = sheetHeight * scale;

  return SheetPlacement(
    scale: scale,
    left:
        (screenWidth - visibleWidth * scale) / 2 -
        fragment.left * sheetOnScreenWidth,
    top:
        (screenHeight - visibleHeight * scale) / 2 -
        fragment.top * sheetOnScreenHeight,
    sheetWidth: sheetOnScreenWidth,
    sheetHeight: sheetOnScreenHeight,
  );
}
