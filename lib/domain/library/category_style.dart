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
import '../theme/contrast.dart';
import 'stable_hash.dart';

/// Рисунок подложки категории.
///
/// Узоры намеренно абстрактные и «машинные» — сетки, трассы, потоки
/// данных, сбои развёртки (решение владельца, 28.08.2026). Полка стоит в
/// тёмной теме, и геометрия из мира схем и терминалов смотрится на ней
/// своей, а доски и плетёнки — чужой мебелью.
///
/// Шестнадцать узоров на восемнадцать оттенков дают 288 сочетаний: две
/// категории с одинаковым видом на живой полке встречаются не чаще, чем
/// два человека с одним днём рождения в маленькой компании.
enum ShelfPattern {
  /// Печатная плата: трассы с прямыми углами и контактные точки.
  circuit,

  /// Соты.
  hexGrid,

  /// Поток данных: вертикальные штрихи разной длины.
  dataStream,

  /// Строчная развёртка с редким сбоем.
  scanlines,

  /// Смещённые прямоугольные блоки — «глитч».
  glitchBlocks,

  /// Треугольная сетка.
  triangles,

  /// Изометрическая сетка: город, снятый сверху.
  isoGrid,

  /// Узлы, соединённые линиями, — карта сети.
  nodes,

  /// Штрихкод: вертикальные полосы разной ширины.
  barcode,

  /// Концентрические дуги — расходящийся сигнал.
  pulse,

  /// Перекрёстная диагональная штриховка.
  crosshatch,

  /// Ступенчатые горизонтали — рельеф на карте.
  contour,

  /// Короткие сегменты, сложенные в лабиринт.
  maze,

  /// Редкие квадратные пиксели, осыпающиеся вниз.
  pixelRain,

  /// Ломаная осциллограммы.
  waveform,

  /// Шевроны.
  chevron,
}

/// Сколько разных оттенков различает полка.
///
/// Восемнадцать — это шаг в 20° по цветовому кругу. Прежние двенадцать
/// давали полку, на которой половина категорий отличалась только
/// названием; двадцать четыре — соседей, различимых лишь рядом друг с
/// другом.
const int kCategoryHues = 18;

/// Насколько оттенок подмешивается к поверхности темы.
///
/// Подложка обязана остаться цветом **этой** темы, слегка окрашенным, а не
/// самостоятельным пятном: пять тем и произвольные названия категорий
/// иначе дают сочетания, которых никто не проверял. Верхняя граница
/// закреплена тестом — подложка не уходит от поверхности темы дальше чем
/// в 1.9 раза по контрасту.
const double kCategoryTint = 0.26;

/// Насколько спокойный узор отличается от подложки.
///
/// Это фактура, а не рябь: слишком заметный узор соревнуется с обложками
/// и мешает читать подписи. Величина закреплена тестом — контраст узора
/// к подложке обязан остаться в узком коридоре.
const double kCategoryInk = 0.09;

/// Каждая какая категория выходит кислотной.
///
/// Решение владельца (28.08.2026): яркие цвета встречаются **в малом
/// количестве**, основной стиль — тёмные оттенки. Одна из семи — это
/// примерно одна светящаяся категория на полке из десятка: она читается
/// как событие, а не как манера оформления.
const int kCategoryAcidEvery = 7;

/// Насыщенность неона у кислотной категории.
const double kCategoryAcidSaturation = 0.95;

/// Светлота неона у кислотной категории.
///
/// Вместе с насыщенностью даёт настоящие кислотные цвета — лайм, циан,
/// маджента, — а не притушенные их подобия.
const double kCategoryAcidLightness = 0.58;

/// Какую долю подложки закрашивает кислотный узор.
///
/// Здесь и живёт потолок «свечения», выбранный владельцем: неон светит в
/// полную силу, но светится его **мало**. Вес участка — средний цвет
/// подложки под узором ([CategoryStyle.weightOn]) — не уходит от подложки
/// дальше чем втрое по контрасту, и это закреплено тестом.
const double kCategoryAcidCoverage = 0.24;

/// Какую долю подложки закрашивает спокойный узор.
///
/// Спокойному узору тонкая линия не нужна вовсе: он и так покрашен почти
/// в цвет подложки, и щедрая линия делает фактуру ровнее, а не громче.
const double kCategoryCalmCoverage = 0.55;

/// Толщина линии кислотного узора — доля шага рисунка.
const double kCategoryAcidStroke = 1 / 22;

/// Толщина линии спокойного узора — доля шага рисунка.
const double kCategoryCalmStroke = 1 / 12;

/// Вид категории: узор, оттенок, сдвиг рисунка и признак кислоты.
class CategoryStyle {
  /// Создаёт вид.
  const CategoryStyle({
    required this.seed,
    required this.pattern,
    required this.hueIndex,
    required this.phase,
    required this.acid,
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

  /// Светится ли узор неоном.
  ///
  /// Признак самой категории, а не темы: на светлых темах кислота
  /// приглушается до обычной фактуры (см. [acidOn]) — неон на бумажном
  /// фоне читается как маркер, а не как свечение.
  final bool acid;

  /// Оттенок в градусах цветового круга.
  double get hue => hueIndex * 360.0 / kCategoryHues;

  /// Светится ли категория на этой теме.
  ///
  /// Решение владельца (28.08.2026): неон живёт только там, где ему есть
  /// на чём светиться.
  bool acidOn(AppPalette palette) => acid && palette.isDark;

  /// Цвет подложки на заданной теме.
  int backgroundOn(AppPalette palette) {
    final int tint = _hslToArgb(hue, 0.5, palette.isDark ? 0.34 : 0.62);
    return _mix(palette.surface, tint, kCategoryTint);
  }

  /// Цвет узора на заданной теме.
  int inkOn(AppPalette palette) {
    if (acidOn(palette)) {
      return _hslToArgb(
        hue,
        kCategoryAcidSaturation,
        kCategoryAcidLightness,
      );
    }
    return _mix(backgroundOn(palette), palette.text, kCategoryInk);
  }

  /// Какую долю подложки закрашивает узор на заданной теме.
  double coverageOn(AppPalette palette) =>
      acidOn(palette) ? kCategoryAcidCoverage : kCategoryCalmCoverage;

  /// Толщина линии узора при шаге рисунка [step].
  double strokeOn(AppPalette palette, double step) {
    final double factor = acidOn(palette)
        ? kCategoryAcidStroke
        : kCategoryCalmStroke;
    return math.max(1.0, step * factor);
  }

  /// Средний цвет участка: подложка, закрашенная узором на свою долю.
  ///
  /// Именно он отвечает за то, насколько громко категория заявляет о себе
  /// издали, и им же красится кружок у заголовка: категорию надо узнавать
  /// и тогда, когда полку прокрутили и подложки не видно.
  int weightOn(AppPalette palette) {
    return _mix(backgroundOn(palette), inkOn(palette), coverageOn(palette));
  }

  @override
  bool operator ==(Object other) =>
      other is CategoryStyle &&
      other.seed == seed &&
      other.pattern == pattern &&
      other.hueIndex == hueIndex &&
      other.phase == phase &&
      other.acid == acid;

  @override
  int get hashCode => Object.hash(seed, pattern, hueIndex, phase, acid);

  @override
  String toString() =>
      'CategoryStyle(${pattern.name}, оттенок $hueIndex, сдвиг '
      '${phase.toStringAsFixed(3)}${acid ? ', кислота' : ''})';
}

/// Вид категории по её названию.
///
/// Название сначала приводится к общему виду: регистр и лишние пробелы не
/// должны менять вид полки, иначе переименование «учёба» в «Учёба»
/// перекрашивало бы её целиком.
CategoryStyle categoryStyleFor(String title) {
  final int seed = stableHash(_normalizeForSeed(title));
  // Четыре независимых числа из одного хеша: разные разряды берутся
  // разными сдвигами, иначе узор и оттенок менялись бы вместе и половина
  // сочетаний никогда бы не встретилась.
  final int pattern = (seed >> 3) % ShelfPattern.values.length;
  final int hue = (seed >> 9) % kCategoryHues;
  final int phase = (seed >> 17) % 1000;
  // Кислота берётся из старших разрядов целиком, а не из пяти последних:
  // на пяти битах «каждая седьмая» превращается в каждую шестую с лишним,
  // потому что 32 на 7 не делится.
  final int acid = (seed >> 21) % kCategoryAcidEvery;
  return CategoryStyle(
    seed: seed,
    pattern: ShelfPattern.values[pattern],
    hueIndex: hue,
    phase: phase / 1000.0,
    acid: acid == 0,
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

  return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
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
  int channel(double value) => ((value + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | (channel(r) << 16) | (channel(g) << 8) | channel(b);
}

/// Шаг узора в точках при заданной ширине блока.
///
/// Узор привязан к размеру книги, а не к экрану: на телефоне и на широком
/// окне ПК полка обязана выглядеть одной и той же полкой, просто крупнее.
double patternStepFor(double blockWidth) {
  return math.max(12.0, blockWidth / 6.0);
}

/// Насколько громко категория заявляет о себе издали.
///
/// Отдельная функция, а не выражение в тесте: потолок громкости — решение
/// владельца, и жить он должен рядом с математикой, которая его держит.
double categoryWeightContrast(CategoryStyle style, AppPalette palette) {
  return contrastRatio(style.weightOn(palette), style.backgroundOn(palette));
}
