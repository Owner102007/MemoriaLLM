/// Автообрезка белых полей — чистая математика.
///
/// Смысл всей затеи: страница должна занимать весь экран. Поля печатной
/// книги нужны пальцам, а не глазам, и на телефоне они съедают до трети
/// экрана. Здесь считается прямоугольник содержимого страницы; чем именно
/// его показать — забота интерфейса.
///
/// Два пути. Быстрый — по координатам символов текстового слоя: точный,
/// без рисования, работает на любой странице с текстом. Медленный — по
/// пикселям низкого рендера: единственный возможный для сканов, где
/// текстового слоя нет вовсе.
///
/// Координаты — доли отображаемой страницы, начало в левом верхнем углу
/// (см. `text_geometry.dart`).
library;

import 'reader_document.dart';
import 'reading.dart';
import 'text_geometry.dart';

/// Настройки автообрезки.
///
/// Значения по умолчанию подобраны так, чтобы ошибаться в сторону
/// «обрезать меньше»: недорезанное поле — мелочь, срезанная строка —
/// испорченная книга.
class CropOptions {
  /// Создаёт настройки.
  const CropOptions({
    this.ignoreRunningHeads = true,
    this.padding = 0.01,
    this.minSize = 0.2,
    this.grid = 0.005,
  });

  /// Настройки по умолчанию.
  static const CropOptions standard = CropOptions();

  /// Не считать колонтитулы содержимым.
  final bool ignoreRunningHeads;

  /// Запас вокруг содержимого в долях страницы.
  ///
  /// Нужен не для красоты: у выносных элементов, диакритики и подчёркиваний
  /// прямоугольники символов часто чуть меньше того, что реально нарисовано.
  final double padding;

  /// Наименьшая допустимая сторона рамки в долях страницы.
  ///
  /// Страница с одним словом посреди листа даёт крошечный прямоугольник;
  /// растянуть его на весь экран — не чтение, а лупа.
  final double minSize;

  /// Шаг сетки, к которой округляется рамка (наружу).
  ///
  /// Соседние страницы книги отличаются полями на доли процента. Без
  /// округления кегль слегка менялся бы от страницы к странице, и это
  /// заметно глазу сильнее, чем сами поля.
  final double grid;
}

/// Прямоугольник содержимого по координатам символов.
///
/// Пустой список символов — это не ошибка, а страница без текстового слоя:
/// возвращается страница целиком, а решать, идти ли пиксельным путём,
/// будет вызывающий.
CropBox contentBoxFromTextBoxes(
  List<TextBox> boxes, {
  CropOptions options = CropOptions.standard,
}) {
  final List<TextLine> lines = groupTextLines(boxes);
  if (lines.isEmpty) {
    return CropBox.full;
  }
  final List<TextLine> body = options.ignoreRunningHeads
      ? dropRunningHeads(lines)
      : lines;
  if (body.isEmpty) {
    return CropBox.full;
  }

  double left = body.first.left;
  double top = body.first.top;
  double right = body.first.right;
  double bottom = body.first.bottom;
  for (final TextLine line in body) {
    if (line.left < left) {
      left = line.left;
    }
    if (line.top < top) {
      top = line.top;
    }
    if (line.right > right) {
      right = line.right;
    }
    if (line.bottom > bottom) {
      bottom = line.bottom;
    }
  }

  return normalizeCrop(
    CropBox(left: left, top: top, right: right, bottom: bottom),
    options: options,
  );
}

/// Убирает колонтитулы: одиночные строки, оторванные от основного блока.
///
/// Признак колонтитула — не место на странице, а **разрыв**: между номером
/// страницы и телом текста пустоты втрое больше, чем между строками тела.
/// Проверяется отдельно сверху и снизу и не больше одной строки с каждой
/// стороны: страница, начинающаяся с заголовка в две строки, не должна
/// осыпаться целиком.
///
/// На короткой странице (меньше [minLines] строк) не делается ничего:
/// там любая строка выглядит оторванной, а ошибиться — значит срезать
/// половину содержимого.
List<TextLine> dropRunningHeads(
  List<TextLine> lines, {
  int minLines = 4,
  double gapFactor = 2.2,
}) {
  if (lines.length < minLines) {
    return lines;
  }
  final List<double> gaps = <double>[
    for (int i = 1; i < lines.length; i++) lines[i].top - lines[i - 1].top,
  ];
  final double typical = median(gaps);
  if (typical <= 0) {
    return lines;
  }
  final double heights = median(<double>[
    for (final TextLine line in lines) line.height,
  ]);

  int start = 0;
  int end = lines.length;
  // Верхний колонтитул: оторван от следующей строки и не выше обычной
  // строки. Второе условие бережёт крупный заголовок главы.
  if (gaps.first > typical * gapFactor && lines.first.height <= heights * 1.6) {
    start = 1;
  }
  // Нижний колонтитул: оторван от предыдущей строки.
  if (gaps.last > typical * gapFactor && lines.last.height <= heights * 1.6) {
    end = lines.length - 1;
  }
  if (end - start < 1) {
    return lines;
  }
  return lines.sublist(start, end);
}

/// Прямоугольник содержимого по пикселям рендера.
///
/// Единственный путь для сканов. Работает по фону: уровень фона берётся
/// с краёв страницы, «чернилами» считается всё, что отличается от него
/// больше чем на [inkThreshold]. Разница берётся по модулю, поэтому
/// светлый текст на тёмном фоне обрезается так же, как чёрный на белом.
///
/// Строка или столбец считаются содержимым, только если чернил в них
/// набралось хотя бы [minInkShare]: у сканов края в крапинку от пыли на
/// стекле, и без этого порога рамка всегда получалась бы во всю страницу.
CropBox contentBoxFromRaster(
  PageRaster raster, {
  double inkThreshold = 0.12,
  double minInkShare = 0.02,
  CropOptions options = CropOptions.standard,
}) {
  if (!raster.isConsistent) {
    return CropBox.full;
  }
  final int width = raster.width;
  final int height = raster.height;

  final List<double> luminance = List<double>.filled(width * height, 0);
  for (int i = 0; i < width * height; i++) {
    final int base = i * 4;
    // Пиксели приходят в порядке BGRA.
    final double b = raster.pixels[base] / 255;
    final double g = raster.pixels[base + 1] / 255;
    final double r = raster.pixels[base + 2] / 255;
    luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  final List<double> edge = <double>[];
  for (int x = 0; x < width; x++) {
    edge.add(luminance[x]);
    edge.add(luminance[(height - 1) * width + x]);
  }
  for (int y = 0; y < height; y++) {
    edge.add(luminance[y * width]);
    edge.add(luminance[y * width + width - 1]);
  }
  final double background = median(edge);

  final int rowThreshold = _atLeastOne(width * minInkShare);
  final int columnThreshold = _atLeastOne(height * minInkShare);
  final List<int> rowInk = List<int>.filled(height, 0);
  final List<int> columnInk = List<int>.filled(width, 0);
  for (int y = 0; y < height; y++) {
    final int row = y * width;
    for (int x = 0; x < width; x++) {
      if ((luminance[row + x] - background).abs() > inkThreshold) {
        rowInk[y]++;
        columnInk[x]++;
      }
    }
  }

  final int top = _firstAbove(rowInk, rowThreshold);
  final int bottom = _lastAbove(rowInk, rowThreshold);
  final int left = _firstAbove(columnInk, columnThreshold);
  final int right = _lastAbove(columnInk, columnThreshold);
  if (top < 0 || bottom < 0 || left < 0 || right < 0) {
    return CropBox.full;
  }

  return normalizeCrop(
    CropBox(
      left: left / width,
      top: top / height,
      right: (right + 1) / width,
      bottom: (bottom + 1) / height,
    ),
    options: options,
  );
}

/// Приводит рамку к пригодному виду: запас, минимальный размер, сетка.
///
/// Возвращает [CropBox.full] для всего, что не похоже на прямоугольник:
/// пустая или вывернутая наизнанку рамка — это чёрный экран вместо книги,
/// и лучше не обрезать вовсе.
CropBox normalizeCrop(
  CropBox box, {
  CropOptions options = CropOptions.standard,
}) {
  if (!box.left.isFinite ||
      !box.top.isFinite ||
      !box.right.isFinite ||
      !box.bottom.isFinite) {
    return CropBox.full;
  }
  // Вывернутую рамку нельзя «починить» растяжением до минимального
  // размера: получился бы прямоугольник посреди страницы, к содержимому
  // отношения не имеющий.
  if (box.right <= box.left || box.bottom <= box.top) {
    return CropBox.full;
  }
  double left = box.left - options.padding;
  double top = box.top - options.padding;
  double right = box.right + options.padding;
  double bottom = box.bottom + options.padding;

  if (options.grid > 0) {
    left = (left / options.grid).floor() * options.grid;
    top = (top / options.grid).floor() * options.grid;
    right = (right / options.grid).ceil() * options.grid;
    bottom = (bottom / options.grid).ceil() * options.grid;
  }

  left = left.clamp(0.0, 1.0);
  top = top.clamp(0.0, 1.0);
  right = right.clamp(0.0, 1.0);
  bottom = bottom.clamp(0.0, 1.0);

  final List<double> horizontal = _grow(left, right, options.minSize);
  final List<double> vertical = _grow(top, bottom, options.minSize);

  final CropBox result = CropBox(
    left: horizontal[0],
    top: vertical[0],
    right: horizontal[1],
    bottom: vertical[1],
  );
  return result.isValid ? result : CropBox.full;
}

/// Какую рамку показывать при этих настройках чтения.
///
/// Ручная рамка главнее автообрезки: если читатель поправил её сам, значит
/// автомат ошибся именно на этой книге, и спорить с человеком незачем.
CropBox effectiveCrop({
  required BookReadingSettings settings,
  required CropBox automatic,
}) {
  final CropBox? manual = settings.manualCrop;
  if (manual != null && manual.isValid) {
    return manual;
  }
  if (!settings.autoCrop) {
    return CropBox.full;
  }
  return automatic.isValid ? automatic : CropBox.full;
}

List<double> _grow(double from, double to, double minSize) {
  double low = from;
  double high = to;
  if (high - low >= minSize) {
    return <double>[low, high];
  }
  final double lack = minSize - (high - low);
  low -= lack / 2;
  high += lack / 2;
  if (low < 0) {
    high -= low;
    low = 0;
  }
  if (high > 1) {
    low -= high - 1;
    high = 1;
  }
  return <double>[low < 0 ? 0 : low, high > 1 ? 1 : high];
}

int _atLeastOne(double value) {
  final int rounded = value.round();
  return rounded < 1 ? 1 : rounded;
}

int _firstAbove(List<int> values, int threshold) {
  for (int i = 0; i < values.length; i++) {
    if (values[i] >= threshold) {
      return i;
    }
  }
  return -1;
}

int _lastAbove(List<int> values, int threshold) {
  for (int i = values.length - 1; i >= 0; i--) {
    if (values[i] >= threshold) {
      return i;
    }
  }
  return -1;
}
