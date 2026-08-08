/// Геометрия текстового слоя страницы — чистая математика.
///
/// **Система координат.** Всё в этом файле и во всей читательской рамке
/// живёт в *долях отображаемой страницы*: начало в левом верхнем углу,
/// `x` вправо, `y` вниз, обе координаты от 0 до 1. Это то, что видит
/// читатель, а не то, что записано в файле: поворот страницы (`/Rotate`)
/// уже применён, точки PDF уже поделены на размер страницы.
///
/// Перевод из координат PDF (начало внизу слева, ось `y` вверх, единица —
/// 1/72 дюйма) делает `infrastructure/pdf`. Здесь про PDF не знают вовсе,
/// поэтому вся геометрия рамки проверяется обычными тестами на числах.
library;

/// Прямоугольник одного символа в долях страницы.
class TextBox {
  /// Создаёт прямоугольник.
  const TextBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Левая граница.
  final double left;

  /// Верхняя граница.
  final double top;

  /// Правая граница.
  final double right;

  /// Нижняя граница.
  final double bottom;

  /// Ширина.
  double get width => right - left;

  /// Высота.
  double get height => bottom - top;

  /// Середина по вертикали.
  double get centerY => (top + bottom) / 2;

  /// Середина по горизонтали.
  double get centerX => (left + right) / 2;

  /// Непустой ли прямоугольник и лежит ли он внутри страницы.
  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      right.isFinite &&
      bottom.isFinite &&
      width > 0 &&
      height > 0 &&
      left >= 0 &&
      top >= 0 &&
      right <= 1 &&
      bottom <= 1;

  @override
  bool operator ==(Object other) {
    return other is TextBox &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'TextBox($left, $top, $right, $bottom)';
}

/// Строка текста: объединяющий прямоугольник и число символов в ней.
class TextLine {
  /// Создаёт строку.
  const TextLine({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.boxCount,
  });

  /// Левая граница.
  final double left;

  /// Верхняя граница.
  final double top;

  /// Правая граница.
  final double right;

  /// Нижняя граница.
  final double bottom;

  /// Сколько символов вошло в строку.
  final int boxCount;

  /// Ширина.
  double get width => right - left;

  /// Высота.
  double get height => bottom - top;

  /// Середина по вертикали.
  double get centerY => (top + bottom) / 2;

  @override
  String toString() =>
      'TextLine($left, $top, $right, $bottom, symbols: $boxCount)';
}

/// Собирает символы в строки по вертикальному перекрытию.
///
/// Наивная группировка «по одинаковому `top`» рассыпается на первом же
/// шрифте с разными кеглями в строке: заглавная буква, цифра сноски и
/// строчная «а» стоят на одной строке, но их прямоугольники начинаются
/// в разных местах. Поэтому символ попадает в строку, если он
/// перекрывается с ней по вертикали хотя бы на [overlapShare] от своей
/// высоты.
///
/// Строки возвращаются сверху вниз. На двухколоночной странице левая и
/// правая колонки, стоящие на одной высоте, сольются в одну строку — для
/// обрезки полей это ровно то, что нужно; колонки ищет `columns.dart`
/// по самим символам.
List<TextLine> groupTextLines(
  List<TextBox> boxes, {
  double overlapShare = 0.4,
}) {
  final List<TextBox> usable = <TextBox>[
    for (final TextBox box in boxes)
      if (box.isValid) box,
  ];
  if (usable.isEmpty) {
    return const <TextLine>[];
  }
  usable.sort((TextBox a, TextBox b) => a.top.compareTo(b.top));

  final List<TextLine> lines = <TextLine>[];
  double left = usable.first.left;
  double top = usable.first.top;
  double right = usable.first.right;
  double bottom = usable.first.bottom;
  int count = 1;

  for (int i = 1; i < usable.length; i++) {
    final TextBox box = usable[i];
    final double overlap =
        (bottom < box.bottom ? bottom : box.bottom) -
        (top > box.top ? top : box.top);
    final double reference = box.height < (bottom - top)
        ? box.height
        : (bottom - top);
    if (overlap >= reference * overlapShare) {
      if (box.left < left) {
        left = box.left;
      }
      if (box.top < top) {
        top = box.top;
      }
      if (box.right > right) {
        right = box.right;
      }
      if (box.bottom > bottom) {
        bottom = box.bottom;
      }
      count++;
    } else {
      lines.add(
        TextLine(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
          boxCount: count,
        ),
      );
      left = box.left;
      top = box.top;
      right = box.right;
      bottom = box.bottom;
      count = 1;
    }
  }
  lines.add(
    TextLine(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      boxCount: count,
    ),
  );
  return lines;
}

/// Медиана списка. Пустой список даёт `0`.
double median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final int middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
