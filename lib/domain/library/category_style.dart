/// Узор и цвет категории, посчитанные из её названия.
///
/// Категории лежат на одной полке подряд, и различать их надо взглядом,
/// не читая подписи. Заводить для этого выбор цвета вручную — значит
/// заставить читателя оформлять библиотеку вместо того, чтобы читать.
/// Поэтому вид категории **выводится из названия**: «Учёба» всегда
/// выглядит одинаково, на телефоне и на ПК, сегодня и через год, и
/// одинаково же — на другом устройстве после синхронизации.
///
/// Слой `domain` не знает про Flutter, поэтому цвет здесь — обычное целое
/// `0xFFRRGGBB`, как в палитрах тем. Благодаря этому читаемость подписи на
/// подложке категории проверяется обычным юнит-тестом, тем же расчётом
/// контраста, что и темы.
library;

import 'dart:math' as math;

import '../theme/app_palette.dart';
import 'stable_hash.dart';

/// Рисунок подложки категории.
///
/// Шесть узоров, а не двадцать: узор — фактура под обложками, а не
/// картина. Чем он спокойнее, тем меньше спорит с обложками, ради которых
/// полка и существует.
enum ShelfPattern {
  /// Горизонтальные полосы — доски полки.
  planks,

  /// Диагональная штриховка.
  diagonal,

  /// Клетка.
  checker,

  /// Точки в шахматном порядке.
  dots,

  /// Ёлочка.
  herringbone,

  /// Плетение.
  weave,
}

/// Сколько разных оттенков различает полка.
///
/// Двенадцать — это шаг в 30° по цветовому кругу: соседние оттенки уже
/// различимы глазом, а более мелкий шаг давал бы категории, отличающиеся
/// только по названию.
const int kCategoryHues = 12;

/// Насколько оттенок подмешивается к поверхности темы.
///
/// Подложка обязана остаться цветом **этой** темы, слегка окрашенным, а не
/// самостоятельным пятном: пять тем и произвольные названия категорий
/// иначе дают сочетания, которых никто не проверял.
const double kCategoryTint = 0.20;

/// Насколько узор отличается от подложки.
///
/// Это фактура, а не рябь: слишком заметный узор соревнуется с обложками
/// и мешает читать подписи. Величина закреплена тестом — контраст узора
/// к подложке обязан остаться в узком коридоре.
const double kCategoryInk = 0.09;

/// Вид категории: узор, оттенок и сдвиг рисунка.
class CategoryStyle {
  /// Создаёт вид.
  const CategoryStyle({
    required this.seed,
    required this.pattern,
    required this.hueIndex,
    required this.phase,
  });

  /// Устойчивый хеш названия — из него выведено всё остальное.
  final int seed;

  /// Рисунок подложки.
  final ShelfPattern pattern;

  /// Номер оттенка, `0…kCategoryHues - 1`.
  final int hueIndex;

  /// Сдвиг рисунка, доля от 0 до 1.
  ///
  /// Две категории с одним узором и близким оттенком всё равно не
  /// выглядят копиями: рисунок у них начинается в разных местах.
  final double phase;

  /// Оттенок в градусах цветового круга.
  double get hue => hueIndex * 360.0 / kCategoryHues;

  /// Цвет подложки на заданной теме.
  int backgroundOn(AppPalette palette) {
    final int tint = _hslToArgb(
      hue,
      0.5,
      palette.isDark ? 0.34 : 0.62,
    );
    return _mix(palette.surface, tint, kCategoryTint);
  }

  /// Цвет узора на заданной теме.
  int inkOn(AppPalette palette) {
    return _mix(backgroundOn(palette), palette.text, kCategoryInk);
  }

  @override
  bool operator ==(Object other) =>
      other is CategoryStyle &&
      other.seed == seed &&
      other.pattern == pattern &&
      other.hueIndex == hueIndex &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(seed, pattern, hueIndex, phase);

  @override
  String toString() =>
      'CategoryStyle(${pattern.name}, оттенок $hueIndex, сдвиг '
      '${phase.toStringAsFixed(3)})';
}

/// Вид категории по её названию.
///
/// Название сначала приводится к общему виду: регистр и лишние пробелы не
/// должны менять вид полки, иначе переименование «учёба» в «Учёба»
/// перекрашивало бы её целиком.
CategoryStyle categoryStyleFor(String title) {
  final int seed = stableHash(_normalizeForSeed(title));
  // Три независимых числа из одного хеша: разные разряды берутся разными
  // сдвигами, иначе узор и оттенок менялись бы вместе и половина
  // сочетаний никогда бы не встретилась.
  final int pattern = (seed >> 3) % ShelfPattern.values.length;
  final int hue = (seed >> 9) % kCategoryHues;
  final int phase = (seed >> 17) % 1000;
  return CategoryStyle(
    seed: seed,
    pattern: ShelfPattern.values[pattern],
    hueIndex: hue,
    phase: phase / 1000.0,
  );
}

String _normalizeForSeed(String title) {
  return title.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

/// Смешивает два цвета: `0` — весь первый, `1` — весь второй.
int _mix(int a, int b, double amount) {
  final double t = amount.clamp(0.0, 1.0);
  int channel(int shift) {
    final int from = (a >> shift) & 0xFF;
    final int to = (b >> shift) & 0xFF;
    return (from + (to - from) * t).round().clamp(0, 255);
  }

  return 0xFF000000 |
      (channel(16) << 16) |
      (channel(8) << 8) |
      channel(0);
}

/// Цвет из тона, насыщенности и светлоты.
int _hslToArgb(double hue, double saturation, double lightness) {
  final double h = (hue % 360 + 360) % 360 / 60.0;
  final double c = (1 - (2 * lightness - 1).abs()) * saturation;
  final double x = c * (1 - ((h % 2) - 1).abs());
  final double m = lightness - c / 2;
  final double r;
  final double g;
  final double b;
  switch (h.floor()) {
    case 0:
      r = c;
      g = x;
      b = 0;
    case 1:
      r = x;
      g = c;
      b = 0;
    case 2:
      r = 0;
      g = c;
      b = x;
    case 3:
      r = 0;
      g = x;
      b = c;
    case 4:
      r = x;
      g = 0;
      b = c;
    default:
      r = c;
      g = 0;
      b = x;
  }
  int channel(double value) =>
      ((value + m) * 255).round().clamp(0, 255);
  return 0xFF000000 |
      (channel(r) << 16) |
      (channel(g) << 8) |
      channel(b);
}

/// Шаг узора в точках при заданной ширине блока.
///
/// Узор привязан к размеру книги, а не к экрану: на телефоне и на широком
/// окне ПК полка обязана выглядеть одной и той же полкой, просто крупнее.
double patternStepFor(double blockWidth) {
  return math.max(12.0, blockWidth / 6.0);
}
