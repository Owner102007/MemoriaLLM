/// Что читатель добавил к раскладке листа сам — и где после этого лежат
/// лист и читаемая полоса на экране.
///
/// Раскладка (`sheet_placement.dart`) отвечает на вопрос «куда положить
/// лист», и её математика неизменна. Здесь — второй слой: отперев замок,
/// читатель двигает и масштабирует страницу, и всё, что рисуется поверх
/// неё (маска, подсветка, панель над выделением), обязано ехать вместе с
/// ней. Преобразование при этом всегда остаётся сдвигом и масштабом —
/// поворотов у страницы нет, — поэтому оно и записано тремя числами, а не
/// матрицей: домен не должен знать ни про Matrix4, ни про просмотрщик.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'reading.dart';
import 'sheet_placement.dart';

/// Наибольшее увеличение щипком, в разах от раскладки.
const double kSheetMaxZoom = 5;

/// Наименьшее уменьшение щипком, в разах от раскладки.
///
/// Полоса вписана в экран, поэтому лист в режиме трети втрое выше экрана:
/// чтобы увидеть страницу целиком, уменьшать надо не меньше чем втрое.
/// Предел взят с запасом — иначе страница упиралась бы в него ровно в тот
/// момент, когда читатель хочет оглядеть её всю.
const double kSheetMinZoom = 0.2;

/// Сколько листа обязано остаться на экране при любом сдвиге.
///
/// Просмотрщик, которому вернули пан, умеет увезти страницу куда угодно.
/// Пустой экран с чёрным фоном читается как поломка, а вернуть страницу
/// читателю нечем: кнопки «на место» у нас нет. Полоска в четыре десятка
/// точек — это и «страница не потерялась», и «двигать можно свободно».
const double kSheetKeepOnScreen = 48;

/// Сдвиг и масштаб, которые читатель добавил к раскладке.
///
/// Единичное преобразование означает «читатель страницу не трогал»: ровно
/// так лист и лежит, пока замок заперт.
class SheetTransform {
  /// Создаёт преобразование.
  const SheetTransform({this.scale = 1, this.dx = 0, this.dy = 0});

  /// Читатель ничего не менял.
  static const SheetTransform none = SheetTransform();

  /// Во сколько раз читатель увеличил страницу против раскладки.
  final double scale;

  /// Сдвиг по горизонтали, в точках экрана.
  final double dx;

  /// Сдвиг по вертикали, в точках экрана.
  final double dy;

  /// Годится ли преобразование к применению.
  bool get isValid => scale.isFinite && scale > 0 && dx.isFinite && dy.isFinite;

  /// Не трогал ли читатель страницу вовсе.
  ///
  /// Пальцы почти никогда не оставляют ровную единицу, поэтому «не трогал»
  /// — это узкая окрестность вокруг неё, а не точное равенство.
  bool get isNeutral =>
      isSheetZoomNeutral(scale) && dx.abs() < 0.5 && dy.abs() < 0.5;

  /// Переводит точку раскладки в точку экрана.
  Offset apply(Offset point) =>
      Offset(point.dx * scale + dx, point.dy * scale + dy);

  /// Переводит прямоугольник раскладки в прямоугольник экрана.
  Rect applyTo(Rect rect) => Rect.fromLTWH(
    rect.left * scale + dx,
    rect.top * scale + dy,
    rect.width * scale,
    rect.height * scale,
  );

  @override
  bool operator ==(Object other) {
    return other is SheetTransform &&
        other.scale == scale &&
        other.dx == dx &&
        other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(scale, dx, dy);

  @override
  String toString() => 'SheetTransform(×$scale, сдвиг $dx, $dy)';
}

/// Где лежит весь лист на экране.
Rect sheetRectOnScreen({
  required SheetPlacement placement,
  SheetTransform transform = SheetTransform.none,
}) {
  if (!placement.isVisible || !transform.isValid) {
    return Rect.zero;
  }
  return transform.applyTo(
    Rect.fromLTWH(
      placement.left,
      placement.top,
      placement.sheetWidth,
      placement.sheetHeight,
    ),
  );
}

/// Где лежит читаемая полоса на экране.
///
/// Это светлое окно: за его пределами лист гаснет, а за пределами листа
/// закрашивается фоном.
Rect stripRectOnScreen({
  required SheetPlacement placement,
  required CropBox fragment,
  SheetTransform transform = SheetTransform.none,
}) {
  final SheetViewport window = fragmentBounds(
    placement: placement,
    fragment: fragment,
  );
  if (!window.isVisible || !transform.isValid) {
    return Rect.zero;
  }
  return transform.applyTo(
    Rect.fromLTWH(window.left, window.top, window.width, window.height),
  );
}

/// Приводит преобразование читателя к допустимому.
///
/// Две границы, и обе про то, чтобы страницу нельзя было потерять.
/// Масштаб держится между [kSheetMinZoom] и [kSheetMaxZoom]; упёршись в
/// предел, страница не прыгает — точка под серединой экрана остаётся на
/// месте. Сдвиг держится так, чтобы от листа на экране оставалась хотя бы
/// полоска в [kSheetKeepOnScreen] точек.
SheetTransform clampSheetTransform({
  required SheetTransform transform,
  required SheetPlacement placement,
  required Size screen,
  double minZoom = kSheetMinZoom,
  double maxZoom = kSheetMaxZoom,
  double keep = kSheetKeepOnScreen,
}) {
  if (!placement.isVisible ||
      screen.width <= 0 ||
      screen.height <= 0 ||
      !transform.isValid) {
    return SheetTransform.none;
  }
  final double scale = transform.scale < minZoom
      ? minZoom
      : (transform.scale > maxZoom ? maxZoom : transform.scale);
  double dx = transform.dx;
  double dy = transform.dy;
  if (scale != transform.scale) {
    // Масштаб упёрся в предел. Пересчитываем сдвиг так, чтобы точка под
    // серединой экрана осталась под ней же: иначе страница дёргалась бы в
    // сторону ровно на границе разрешённого.
    final double k = scale / transform.scale;
    dx = screen.width / 2 - (screen.width / 2 - dx) * k;
    dy = screen.height / 2 - (screen.height / 2 - dy) * k;
  }

  final double width = placement.sheetWidth * scale;
  final double height = placement.sheetHeight * scale;
  dx = _keepOnScreen(
    start: placement.left * scale + dx,
    size: width,
    screen: screen.width,
    keep: keep,
  );
  dy = _keepOnScreen(
    start: placement.top * scale + dy,
    size: height,
    screen: screen.height,
    keep: keep,
  );
  return SheetTransform(
    scale: scale,
    dx: dx - placement.left * scale,
    dy: dy - placement.top * scale,
  );
}

/// Двигает край листа так, чтобы от него осталось видно хотя бы [keep].
double _keepOnScreen({
  required double start,
  required double size,
  required double screen,
  required double keep,
}) {
  // Лист короче полоски — тогда «видно хотя бы полоску» означает «виден
  // весь лист», и оба предела считаются по его собственному размеру.
  final double margin = size < keep ? size : keep;
  final double lowest = margin - size;
  final double highest = screen - margin;
  if (start < lowest) {
    return lowest;
  }
  return start > highest ? highest : start;
}
