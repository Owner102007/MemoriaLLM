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

/// С каким запасом по краям вписывать полосу.
///
/// В чтении во весь экран (F-READ-35) — вплотную, каким бы ни был запас
/// у книги: режим затем и включают, чтобы экран занимала именно
/// читаемая полоса. Запас книги при этом не теряется — он вернётся
/// вместе с окном.
double stripFitFor({required double stripFit, required bool fullScreen}) {
  return fullScreen ? 1 : clampStripFit(stripFit);
}

/// Нахлёст полосы в режиме с [count] полосами, в долях высоты экрана.
///
/// F-READ-12, ALG-PDF-19. Страница целиком нахлёста не имеет: соседних
/// полос у неё нет. В режиме трети действует половина заданного: полоса
/// там и так низкая, и полный нахлёст съел бы слишком много экрана.
double stripOverlapFor({required double overlap, required int count}) {
  if (count <= 1) {
    return 0;
  }
  final double safe = clampStripOverlap(overlap);
  return count >= 3 ? safe / 2 : safe;
}

/// Не трогал ли читатель масштаб страницы пальцами.
///
/// Пальцы почти никогда не оставляют ровную единицу, поэтому «не трогал»
/// — это узкая окрестность вокруг неё, а не точное равенство. Правило
/// нужно в одном месте: когда захлопывается замок. Страницу, которую
/// только сдвинули, не меняя масштаба, надо вернуть на место — сдвинутая
/// на палец страница выглядит поломкой, и при запертом замке вернуть её
/// было бы нечем. А настоящий масштаб, выставленный осознанно, замок
/// обязан сохранить: в этом весь его смысл.
bool isSheetZoomNeutral(double scale) {
  return scale.isFinite && scale > 0.995 && scale < 1.005;
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
/// По горизонтали фрагмент центрируется всегда. По вертикали —
/// по-разному. **Лист целиком стоит по центру**: пустота по краям
/// выглядит спокойнее, чем прижатая к углу страница. **Полоса прижата
/// кверху** ([anchorTop]; F-READ-11, решение владельца 05.09.2026):
/// полосы одной страницы разной высоты — граница ищет просвет между
/// строками, — и при центровке верх полосы гулял от экрана к экрану, а
/// глаз каждый раз искал, откуда читать. У прижатой полосы первая строка
/// стоит на одном месте, а весь вертикальный остаток уходит вниз.
///
/// [fit] меньше единицы оставляет запас по краям: полоса становится
/// мельче, зато её крайние строки уходят от границы экрана — у прижатой
/// полосы в том числе от верхней. Это ответ на закруглённые углы, вырезы
/// камеры и просто на желание видеть строку целиком, а не вплотную к
/// краю.
///
/// [overlap] — нахлёст, доля высоты экрана (F-READ-12): столько экрана
/// остаётся над полосой и под ней, и там видны соседние полосы. Полоса
/// вписывается в то, что осталось, поэтому сама она от нахлёста не
/// меняется — меняется только место под неё.
SheetPlacement placeFragment({
  required double sheetWidth,
  required double sheetHeight,
  required CropBox fragment,
  required double screenWidth,
  required double screenHeight,
  double fit = 1,
  double overlap = 0,
  bool anchorTop = false,
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

  // Нахлёст отнимает экран сверху и снизу поровну; полоса вписывается в
  // остаток.
  final double band = clampStripOverlap(overlap) * screenHeight;
  final double room = screenHeight - band * 2;
  final double safeFit = clampStripFit(fit);
  final double byWidth = screenWidth / visibleWidth;
  final double byHeight = room / visibleHeight;
  final double scale = (byWidth < byHeight ? byWidth : byHeight) * safeFit;

  final double sheetOnScreenWidth = sheetWidth * scale;
  final double sheetOnScreenHeight = sheetHeight * scale;

  // Верх прижатой полосы: под нахлёстом и под запасом по краям. Запас
  // берётся таким, каким он вышел бы у полосы, упёршейся в высоту, —
  // тогда у такой полосы он одинаков сверху и снизу, как и был. Лист
  // целиком стоит посередине того, что осталось.
  final double stripTop = anchorTop
      ? band + room * (1 - safeFit) / 2
      : band + (room - visibleHeight * scale) / 2;

  return SheetPlacement(
    scale: scale,
    left:
        (screenWidth - visibleWidth * scale) / 2 -
        fragment.left * sheetOnScreenWidth,
    top: stripTop - fragment.top * sheetOnScreenHeight,
    sheetWidth: sheetOnScreenWidth,
    sheetHeight: sheetOnScreenHeight,
  );
}

/// Окно фрагмента: где на экране лежит читаемая часть листа.
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

/// Где на экране лежит читаемая полоса.
///
/// Это светлое окно: всё остальное на листе гаснет. Границы намеренно
/// **не** подрезаются краем экрана — полоса и так в него вписана, а
/// подрезка сломала бы главное свойство затемнения: тень должна
/// оставаться на месте, когда читатель уменьшает страницу щипком и
/// затемнённые части листа въезжают в кадр из-за края.
SheetViewport fragmentBounds({
  required SheetPlacement placement,
  required CropBox fragment,
}) {
  if (!placement.isVisible || !fragment.isValid) {
    return SheetViewport.none;
  }
  final double width = fragment.width * placement.sheetWidth;
  final double height = fragment.height * placement.sheetHeight;
  if (width <= 0 || height <= 0) {
    return SheetViewport.none;
  }
  return SheetViewport(
    left: placement.left + fragment.left * placement.sheetWidth,
    top: placement.top + fragment.top * placement.sheetHeight,
    width: width,
    height: height,
  );
}
