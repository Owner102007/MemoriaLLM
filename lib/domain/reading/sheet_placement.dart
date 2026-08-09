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

/// Насколько сильно читателю позволено уменьшить полосу.
///
/// Полоса вписывается в экран вплотную, и её крайняя строка приходится
/// ровно на границу экрана: закруглённый угол, вырез камеры или просто
/// неудачно вставшая граница полосы съедают её у самого края. Щипок
/// внутрь даёт запас — небольшой, потому что каждый процент запаса
/// отнимается у кегля, ради которого режимы и затевались.
const double kMinStripFit = 0.7;

/// Приводит уменьшение полосы к допустимому диапазону.
double clampStripFit(double value) {
  if (!value.isFinite || value >= 1) {
    return 1;
  }
  return value < kMinStripFit ? kMinStripFit : value;
}

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
///
/// [fit] меньше единицы оставляет запас по всем краям: полоса становится
/// мельче, зато её крайние строки уходят от границы экрана. Это ответ на
/// закруглённые углы, вырезы камеры и просто на желание видеть строку
/// целиком, а не вплотную к краю.
SheetPlacement placeFragment({
  required double sheetWidth,
  required double sheetHeight,
  required CropBox fragment,
  required double screenWidth,
  required double screenHeight,
  double fit = 1,
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
  final double scale =
      (byWidth < byHeight ? byWidth : byHeight) * clampStripFit(fit);

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

/// Окно фрагмента: куда именно на экране попал показываемый кусок листа.
class SheetViewport {
  /// Создаёт окно.
  const SheetViewport({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Пустое окно.
  static const SheetViewport none = SheetViewport(
    left: 0,
    top: 0,
    width: 0,
    height: 0,
  );

  /// Отступ слева.
  final double left;

  /// Отступ сверху.
  final double top;

  /// Ширина.
  final double width;

  /// Высота.
  final double height;

  /// Есть ли что показывать.
  bool get isVisible => width > 0 && height > 0;

  @override
  bool operator ==(Object other) {
    return other is SheetViewport &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SheetViewport($left, $top, ${width}x$height)';
}

/// Границы фрагмента на экране — то, что позволено видеть.
///
/// Нужно там, где полоса уменьшена: при запасе по краям вокруг фрагмента
/// освобождается место, и в него заглядывают соседние полосы. Половина
/// строки, торчащая из-за края, хуже, чем её отсутствие: глаз цепляется
/// за неё и теряет строку, которую читал. Поэтому лист обрезается ровно
/// по фрагменту, а вокруг остаётся фон.
///
/// Окно всегда лежит внутри экрана: наружу фрагмент не выходит никогда,
/// он в него вписан.
SheetViewport fragmentViewport({
  required SheetPlacement placement,
  required CropBox fragment,
  required double screenWidth,
  required double screenHeight,
}) {
  if (!placement.isVisible ||
      !fragment.isValid ||
      screenWidth <= 0 ||
      screenHeight <= 0) {
    return SheetViewport.none;
  }
  final double left = placement.left + fragment.left * placement.sheetWidth;
  final double top = placement.top + fragment.top * placement.sheetHeight;
  final double right = left + fragment.width * placement.sheetWidth;
  final double bottom = top + fragment.height * placement.sheetHeight;

  final double clampedLeft = left < 0 ? 0 : left;
  final double clampedTop = top < 0 ? 0 : top;
  final double clampedRight = right > screenWidth ? screenWidth : right;
  final double clampedBottom = bottom > screenHeight ? screenHeight : bottom;
  if (clampedRight <= clampedLeft || clampedBottom <= clampedTop) {
    return SheetViewport.none;
  }
  return SheetViewport(
    left: clampedLeft,
    top: clampedTop,
    width: clampedRight - clampedLeft,
    height: clampedBottom - clampedTop,
  );
}
