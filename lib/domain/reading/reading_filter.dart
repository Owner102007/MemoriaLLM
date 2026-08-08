/// Светофильтры чтения — математика, общая для шейдера и запасного пути.
///
/// Фильтр ложится **на страницу, а не на интерфейс** и ничего не меняет
/// в файле. Порядок преобразований выбран так, как ведёт себя бумага под
/// лампой, а не так, как удобнее считать:
///
/// 1. **гамма** — вытягивает бледный скан, не трогая чёрное и белое;
/// 2. **контраст** — разводит текст и фон вокруг середины;
/// 3. **сам фильтр** — красный монохром, тёплый, сепия, инверсия;
/// 4. **яркость** — гасит экран ниже системного минимума;
/// 5. обрезка в диапазон 0…1.
///
/// Тот же порядок повторён в `shaders/reading_filter.frag`. Код здесь —
/// источник истины: шейдер обязан ему соответствовать, и состав и порядок
/// uniform-переменных проверяются отдельным тестом.
///
/// Цвета — доли от 0 до 1 в sRGB, без предумножения на прозрачность.
library;

import 'dart:math' as math;

import 'reading.dart';

/// Коэффициенты яркости (Rec. 709) — те же, что в проверке контраста тем.
const double _wr = 0.2126;
const double _wg = 0.7152;
const double _wb = 0.0722;

/// Ниже какой насыщенности пиксель считается текстом, а не картинкой.
const double _imageSaturationLow = 0.10;

/// Выше какой насыщенности пиксель считается картинкой наверняка.
const double _imageSaturationHigh = 0.30;

const List<double> _identityMatrix = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];

const List<double> _zeroOffset = <double>[0, 0, 0];

const List<double> _nightRedMatrix = <double>[_wr, _wg, _wb, 0, 0, 0, 0, 0, 0];

const List<double> _warmMatrix = <double>[1, 0, 0, 0, 0.88, 0, 0, 0, 0.55];

const List<double> _invertMatrix = <double>[-1, 0, 0, 0, -1, 0, 0, 0, -1];

const List<double> _invertOffset = <double>[1, 1, 1];

const List<double> _sepiaMatrix = <double>[
  0.393,
  0.769,
  0.189,
  0.349,
  0.686,
  0.168,
  0.272,
  0.534,
  0.131,
];

/// Сила фильтра по умолчанию при его выборе.
///
/// Ноль в настройках означает «фильтр выключен», поэтому при выборе
/// фильтра сила выставляется сразу: иначе читатель включает ночной режим
/// и не видит никакой разницы.
double defaultFilterIntensity(ReadingFilter filter) {
  switch (filter) {
    case ReadingFilter.none:
      return 0;
    case ReadingFilter.nightRed:
      return 0.9;
    case ReadingFilter.warm:
      return 0.6;
    case ReadingFilter.sepia:
      return 0.8;
    case ReadingFilter.invert:
      // Инверсия наполовину — это серый кисель. Либо да, либо нет.
      return 1;
  }
}

/// Цвет в долях от 0 до 1.
class FilteredColor {
  /// Создаёт цвет.
  const FilteredColor(this.r, this.g, this.b);

  /// Красная составляющая.
  final double r;

  /// Зелёная составляющая.
  final double g;

  /// Синяя составляющая.
  final double b;

  @override
  bool operator ==(Object other) {
    return other is FilteredColor &&
        other.r == r &&
        other.g == g &&
        other.b == b;
  }

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() =>
      'FilteredColor(${r.toStringAsFixed(4)}, ${g.toStringAsFixed(4)}, '
      '${b.toStringAsFixed(4)})';
}

/// Настроенный светофильтр.
class ReadingFilterPipeline {
  /// Создаёт фильтр.
  const ReadingFilterPipeline({
    this.filter = ReadingFilter.none,
    this.intensity = 0,
    this.brightness = 1,
    this.contrast = 1,
    this.gamma = 1,
  });

  /// Фильтр из настроек чтения книги.
  factory ReadingFilterPipeline.fromSettings(BookReadingSettings settings) {
    return ReadingFilterPipeline(
      filter: settings.filter,
      intensity: settings.filterIntensity,
      brightness: settings.brightness,
      contrast: settings.contrast,
      gamma: settings.gamma,
    );
  }

  /// Имена float-uniform шейдера по порядку.
  ///
  /// Первая переменная обязана быть `vec2`, и её заполняет сам движок
  /// размером текстуры — таково требование `ImageFilter.shader`.
  static const List<String> uniformNames = <String>[
    'uSize',
    'uFilter',
    'uIntensity',
    'uBrightness',
    'uContrast',
    'uGamma',
  ];

  /// Имя сэмплера, в который движок кладёт саму страницу.
  static const String samplerName = 'uPage';

  /// Фильтр.
  final ReadingFilter filter;

  /// Сила фильтра, от 0 до 1.
  final double intensity;

  /// Яркость, 1 — как есть.
  final double brightness;

  /// Контраст, 1 — как есть.
  final double contrast;

  /// Гамма, 1 — как есть.
  final double gamma;

  /// Ничего не меняет — можно не тратить кадр на обработку вовсе.
  bool get isIdentity =>
      (filter == ReadingFilter.none || safeIntensity == 0) &&
      safeBrightness == 1 &&
      safeContrast == 1 &&
      safeGamma == 1;

  /// Нужен ли шейдер: без него потеряется больше, чем оттенок.
  ///
  /// Гамма нелинейна, а двойная инверсия картинок смотрит на насыщенность
  /// каждого пикселя — ни то, ни другое цветовой матрицей не выражается.
  bool get needsShader =>
      safeGamma != 1 ||
      (filter == ReadingFilter.invert && safeIntensity > 0);

  /// Сила фильтра, приведённая к допустимому диапазону.
  double get safeIntensity => _clamp(intensity, 0, 1);

  /// Яркость, приведённая к допустимому диапазону.
  ///
  /// Ниже 0.05 экран становится чёрным прямоугольником, из которого не
  /// выбраться: интерфейс тоже не виден, и вернуть яркость нечем.
  double get safeBrightness => _clamp(brightness, 0.05, 1);

  /// Контраст, приведённый к допустимому диапазону.
  double get safeContrast => _clamp(contrast, 0.2, 3);

  /// Гамма, приведённая к допустимому диапазону.
  double get safeGamma => _clamp(gamma, 0.2, 3);

  /// Значения float-uniform после `uSize`, в порядке [uniformNames].
  List<double> uniformValues() {
    return <double>[
      filter.index.toDouble(),
      safeIntensity,
      safeBrightness,
      safeContrast,
      safeGamma,
    ];
  }

  /// Эталонное преобразование одного цвета.
  ///
  /// По нему проверяются и шейдер (глазами владельца), и запасная
  /// цветовая матрица (тестом).
  FilteredColor apply(double red, double green, double blue) {
    final double g = safeGamma;
    double r = math.pow(_clamp(red, 0, 1), g).toDouble();
    double gr = math.pow(_clamp(green, 0, 1), g).toDouble();
    double b = math.pow(_clamp(blue, 0, 1), g).toDouble();

    final double k = safeContrast;
    r = (r - 0.5) * k + 0.5;
    gr = (gr - 0.5) * k + 0.5;
    b = (b - 0.5) * k + 0.5;

    final double t = safeIntensity;
    if (t > 0) {
      switch (filter) {
        case ReadingFilter.none:
          break;
        case ReadingFilter.nightRed:
          final double lum = _wr * r + _wg * gr + _wb * b;
          r = _mix(r, lum, t);
          gr = _mix(gr, 0, t);
          b = _mix(b, 0, t);
        case ReadingFilter.warm:
          gr = _mix(gr, gr * 0.88, t);
          b = _mix(b, b * 0.55, t);
        case ReadingFilter.sepia:
          final double sr = 0.393 * r + 0.769 * gr + 0.189 * b;
          final double sg = 0.349 * r + 0.686 * gr + 0.168 * b;
          final double sb = 0.272 * r + 0.534 * gr + 0.131 * b;
          r = _mix(r, sr, t);
          gr = _mix(gr, sg, t);
          b = _mix(b, sb, t);
        case ReadingFilter.invert:
          // Двойная инверсия картинок. Фотографию отличаем от текста по
          // насыщенности: буквы и бумага почти всегда серые, иллюстрации
          // цветные. Цветной пиксель инвертируется дважды, то есть
          // остаётся собой, и фотографии не превращаются в негативы.
          final double high = math.max(r, math.max(gr, b));
          final double low = math.min(r, math.min(gr, b));
          final double picture = _smoothstep(
            _imageSaturationLow,
            _imageSaturationHigh,
            high - low,
          );
          r = _mix(r, _mix(1 - r, r, picture), t);
          gr = _mix(gr, _mix(1 - gr, gr, picture), t);
          b = _mix(b, _mix(1 - b, b, picture), t);
      }
    }

    final double br = safeBrightness;
    return FilteredColor(
      _clamp(r * br, 0, 1),
      _clamp(gr * br, 0, 1),
      _clamp(b * br, 0, 1),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReadingFilterPipeline &&
        other.filter == filter &&
        other.intensity == intensity &&
        other.brightness == brightness &&
        other.contrast == contrast &&
        other.gamma == gamma;
  }

  @override
  int get hashCode =>
      Object.hash(filter, intensity, brightness, contrast, gamma);

  /// Запасная цветовая матрица 4×5 для случая, когда шейдеров нет.
  ///
  /// Порядок значений — как у `ColorFilter.matrix`: по строкам, пятое
  /// число каждой строки — слагаемое в шкале 0…255.
  ///
  /// Две вещи матрицей не выражаются, и обе теряются честно: гамма
  /// заменяется линейным приближением по методу наименьших квадратов
  /// (при гамме 1 приближение точное), а инверсия становится простой —
  /// картинки на странице станут негативами.
  List<double> colorMatrix() {
    _Linear total = _Linear.identity();
    total = _gammaApproximation(safeGamma).then(total);
    total = _contrastStep(safeContrast).then(total);
    total = _filterStep(filter, safeIntensity).then(total);
    total = _Linear.scale(safeBrightness).then(total);
    return total.toColorMatrix();
  }
}

/// Линейное преобразование цвета: матрица 3×3 и слагаемое.
class _Linear {
  const _Linear(this.m, this.o);

  factory _Linear.identity() => const _Linear(_identityMatrix, _zeroOffset);

  factory _Linear.scale(double value) {
    return _Linear(<double>[
      value,
      0,
      0,
      0,
      value,
      0,
      0,
      0,
      value,
    ], _zeroOffset);
  }

  final List<double> m;
  final List<double> o;

  /// Применить себя после [inner].
  _Linear then(_Linear inner) {
    final List<double> matrix = List<double>.filled(9, 0);
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        double sum = 0;
        for (int k = 0; k < 3; k++) {
          sum += m[row * 3 + k] * inner.m[k * 3 + col];
        }
        matrix[row * 3 + col] = sum;
      }
    }
    final List<double> offset = List<double>.filled(3, 0);
    for (int row = 0; row < 3; row++) {
      double sum = o[row];
      for (int k = 0; k < 3; k++) {
        sum += m[row * 3 + k] * inner.o[k];
      }
      offset[row] = sum;
    }
    return _Linear(matrix, offset);
  }

  List<double> toColorMatrix() {
    final List<double> result = List<double>.filled(20, 0);
    for (int row = 0; row < 3; row++) {
      result[row * 5] = m[row * 3];
      result[row * 5 + 1] = m[row * 3 + 1];
      result[row * 5 + 2] = m[row * 3 + 2];
      result[row * 5 + 4] = o[row] * 255;
    }
    result[18] = 1;
    return result;
  }
}

/// Линейное приближение `pow(c, gamma)` на отрезке 0…1.
///
/// Наименьшие квадраты: `a·c + b`, где коэффициенты получаются из двух
/// интегралов. При `gamma == 1` выходит ровно `a = 1, b = 0`, поэтому
/// нетронутая гамма не портит картинку даже в запасном пути.
_Linear _gammaApproximation(double gamma) {
  final double a = 12 * (1 / (gamma + 2) - 1 / (2 * (gamma + 1)));
  final double b = 1 / (gamma + 1) - a / 2;
  return _Linear(<double>[a, 0, 0, 0, a, 0, 0, 0, a], <double>[b, b, b]);
}

_Linear _contrastStep(double contrast) {
  final double shift = 0.5 - 0.5 * contrast;
  return _Linear(<double>[
    contrast,
    0,
    0,
    0,
    contrast,
    0,
    0,
    0,
    contrast,
  ], <double>[shift, shift, shift]);
}

_Linear _filterStep(ReadingFilter filter, double intensity) {
  if (intensity <= 0) {
    return _Linear.identity();
  }
  switch (filter) {
    case ReadingFilter.none:
      return _Linear.identity();
    case ReadingFilter.nightRed:
      return _mixWithIdentity(_nightRedMatrix, _zeroOffset, intensity);
    case ReadingFilter.warm:
      return _mixWithIdentity(_warmMatrix, _zeroOffset, intensity);
    case ReadingFilter.sepia:
      return _mixWithIdentity(_sepiaMatrix, _zeroOffset, intensity);
    case ReadingFilter.invert:
      return _mixWithIdentity(_invertMatrix, _invertOffset, intensity);
  }
}

_Linear _mixWithIdentity(List<double> target, List<double> offset, double t) {
  return _Linear(
    <double>[
      for (int i = 0; i < 9; i++) _identityMatrix[i] * (1 - t) + target[i] * t,
    ],
    <double>[for (int i = 0; i < 3; i++) offset[i] * t],
  );
}

double _mix(double from, double to, double t) => from + (to - from) * t;

double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) {
    return x < edge0 ? 0 : 1;
  }
  final double t = _clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

double _clamp(double value, double low, double high) {
  if (!value.isFinite) {
    return low;
  }
  if (value < low) {
    return low;
  }
  return value > high ? high : value;
}
