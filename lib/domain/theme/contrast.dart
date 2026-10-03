/// Расчёт контраста по WCAG 2.1.
///
/// Слой `domain` не зависит от Flutter, поэтому цвет здесь — обычное целое
/// в формате ARGB (`0xFFRRGGBB`). Это позволяет проверять читаемость тем
/// обычными юнит-тестами, без поднятия виджет-окружения.
library;

import 'dart:math' as math;

/// Минимальный контраст для основного текста (WCAG AA, обычный кегль).
const double wcagAaNormalText = 4.5;

/// Минимальный контраст для крупного текста и границ элементов интерфейса.
const double wcagAaLargeText = 3.0;

/// Канал sRGB (0…255), приведённый к линейному пространству.
double _linearize(int channel) {
  final double c = channel / 255.0;
  if (c <= 0.04045) {
    return c / 12.92;
  }
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// Относительная яркость цвета по WCAG 2.1.
///
/// [argb] — цвет в формате `0xFFRRGGBB`; альфа игнорируется, темы
/// непрозрачные.
double relativeLuminance(int argb) {
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * _linearize(r) +
      0.7152 * _linearize(g) +
      0.0722 * _linearize(b);
}

/// Коэффициент контраста двух цветов: от 1.0 (одинаковые) до 21.0
/// (чёрный против белого). Порог WCAG AA для основного текста — 4.5.
double contrastRatio(int foreground, int background) {
  final double a = relativeLuminance(foreground);
  final double b = relativeLuminance(background);
  final double lighter = a > b ? a : b;
  final double darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Цвет, который видит глаз, когда полупрозрачный [top] лежит поверх
/// [under].
///
/// [alpha] — непрозрачность верхнего цвета, от 0 до 1; собственная альфа
/// чисел не учитывается. Нужен там, где текст стоит на полупрозрачной
/// панели: контраст считается против того, что получилось на экране, а
/// не против цвета самой панели (F-TEXT-11).
int blendOver(int top, double alpha, int under) {
  final double a = alpha < 0 ? 0 : (alpha > 1 ? 1 : alpha);
  int channel(int shift) {
    final int upper = (top >> shift) & 0xFF;
    final int lower = (under >> shift) & 0xFF;
    return (upper * a + lower * (1 - a)).round();
  }

  return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
}
