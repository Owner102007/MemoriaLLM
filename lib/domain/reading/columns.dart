/// Поиск колонок на странице — чистая математика.
///
/// Двухколоночную статью нельзя делить пополам по горизонтали: получится
/// два обрубка обеих колонок сразу. Делить надо по колонкам, и порядок
/// чтения тогда «левая сверху вниз, потом правая».
///
/// Колонка ищется по вертикальному просвету: полосе, в которую не попал
/// ни один символ **ни одной** строки. В сплошном тексте такой полосы
/// посреди страницы не бывает — какая-нибудь строка обязательно её
/// перечеркнёт. Именно поэтому признак надёжен и почти не даёт ложных
/// срабатываний.
library;

import 'reading.dart';
import 'text_geometry.dart';

/// Вертикальная полоса страницы, занятая одной колонкой.
class ColumnBand {
  /// Создаёт полосу.
  const ColumnBand({required this.left, required this.right});

  /// Левая граница в долях страницы.
  final double left;

  /// Правая граница в долях страницы.
  final double right;

  /// Ширина.
  double get width => right - left;

  @override
  bool operator ==(Object other) {
    return other is ColumnBand && other.left == left && other.right == right;
  }

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'ColumnBand($left, $right)';
}

/// Настройки поиска колонок.
class ColumnOptions {
  /// Создаёт настройки.
  const ColumnOptions({
    this.bins = 240,
    this.minGutterShare = 0.025,
    this.minSideShare = 0.2,
    this.searchFrom = 0.3,
    this.searchTo = 0.7,
    this.minLines = 6,
  });

  /// Настройки по умолчанию.
  static const ColumnOptions standard = ColumnOptions();

  /// На сколько столбиков делится ширина содержимого.
  final int bins;

  /// Наименьшая ширина просвета в долях ширины содержимого.
  final double minGutterShare;

  /// Наименьшая доля символов, которая должна оказаться в каждой колонке.
  final double minSideShare;

  /// Слева от какой доли ширины просвет не ищется.
  final double searchFrom;

  /// Справа от какой доли ширины просвет не ищется.
  final double searchTo;

  /// Меньше скольких строк колонки не ищутся вовсе.
  final int minLines;
}

/// Колонки внутри рамки содержимого.
///
/// Всегда возвращает хотя бы одну полосу — саму рамку. Двухколоночная
/// вёрстка распознана, если полос две.
///
/// Три и больше колонок не ищутся намеренно: в книгах их практически не
/// бывает, а цена ошибки — разорванный посреди слова текст.
List<ColumnBand> detectColumns(
  List<TextBox> boxes,
  CropBox content, {
  ColumnOptions options = ColumnOptions.standard,
}) {
  final List<ColumnBand> single = <ColumnBand>[
    ColumnBand(left: content.left, right: content.right),
  ];
  if (content.width <= 0 || options.bins < 8) {
    return single;
  }

  final List<TextBox> inside = <TextBox>[
    for (final TextBox box in boxes)
      if (box.isValid &&
          box.right > content.left &&
          box.left < content.right &&
          box.bottom > content.top &&
          box.top < content.bottom)
        box,
  ];
  if (inside.length < 8) {
    return single;
  }
  if (groupTextLines(inside).length < options.minLines) {
    return single;
  }

  final List<int> ink = List<int>.filled(options.bins, 0);
  for (final TextBox box in inside) {
    final int from = _bin(box.left, content, options.bins);
    final int to = _bin(box.right, content, options.bins);
    for (int i = from; i <= to; i++) {
      ink[i]++;
    }
  }

  final int fromBin = (options.searchFrom * options.bins).floor();
  final int toBin = (options.searchTo * options.bins).ceil();
  int bestStart = -1;
  int bestEnd = -1;
  int start = -1;
  for (int i = 0; i < options.bins; i++) {
    if (ink[i] == 0) {
      if (start < 0) {
        start = i;
      }
      continue;
    }
    if (start >= 0) {
      _rememberRun(start, i - 1, fromBin, toBin, (int s, int e) {
        if (e - s > bestEnd - bestStart) {
          bestStart = s;
          bestEnd = e;
        }
      });
      start = -1;
    }
  }
  if (start >= 0) {
    _rememberRun(start, options.bins - 1, fromBin, toBin, (int s, int e) {
      if (e - s > bestEnd - bestStart) {
        bestStart = s;
        bestEnd = e;
      }
    });
  }
  if (bestStart < 0) {
    return single;
  }

  final double binWidth = content.width / options.bins;
  if ((bestEnd - bestStart + 1) * binWidth <
      content.width * options.minGutterShare) {
    return single;
  }

  final double gutterLeft = content.left + bestStart * binWidth;
  final double gutterRight = content.left + (bestEnd + 1) * binWidth;

  int leftCount = 0;
  int rightCount = 0;
  for (final TextBox box in inside) {
    if (box.centerX <= gutterLeft) {
      leftCount++;
    } else if (box.centerX >= gutterRight) {
      rightCount++;
    }
  }
  final double share = options.minSideShare * inside.length;
  if (leftCount < share || rightCount < share) {
    return single;
  }

  // Границы самих колонок берутся по символам, а не по краям просвета:
  // иначе в колонку попадёт половина межколоночного поля и весь выигрыш
  // в кегле пропадёт.
  double leftEnd = content.left;
  double rightStart = content.right;
  for (final TextBox box in inside) {
    if (box.centerX <= gutterLeft && box.right > leftEnd) {
      leftEnd = box.right;
    }
    if (box.centerX >= gutterRight && box.left < rightStart) {
      rightStart = box.left;
    }
  }
  if (leftEnd <= content.left || rightStart >= content.right) {
    return single;
  }

  return <ColumnBand>[
    ColumnBand(left: content.left, right: leftEnd),
    ColumnBand(left: rightStart, right: content.right),
  ];
}

void _rememberRun(
  int start,
  int end,
  int fromBin,
  int toBin,
  void Function(int start, int end) keep,
) {
  final int center = (start + end) ~/ 2;
  if (center < fromBin || center > toBin) {
    return;
  }
  keep(start, end);
}

int _bin(double x, CropBox content, int bins) {
  final double share = (x - content.left) / content.width;
  final int index = (share * bins).floor();
  if (index < 0) {
    return 0;
  }
  if (index > bins - 1) {
    return bins - 1;
  }
  return index;
}
