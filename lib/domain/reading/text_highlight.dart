/// Прямоугольники подсветки: из куска текста — в то, что видно на странице.
///
/// Одна и та же математика обслуживает двоих. Выделение показывает, где
/// стоит выделенный текст, и по этим же прямоугольникам панель действий
/// понимает, куда ей встать. Поиск подсвечивает найденное — долг, честно
/// отложенный в S3 именно до этой сессии, потому что до координат
/// символов подсвечивать было нечем.
///
/// Прямоугольник строится **на строку**, а не на символ: подсветка из
/// сотни отдельных клеток выглядит рябью, а строка — маркером.
library;

import 'columns.dart';
import 'page_rows.dart';
import 'reader_document.dart';
import 'text_geometry.dart';

/// Прямоугольники подсветки для куска текста [start]..[end).
///
/// Координаты — доли отображаемой страницы, как и везде в читательской
/// рамке. Пустой список означает, что показывать нечего: у страницы нет
/// геометрии или кусок пуст.
List<TextBox> highlightRects({
  required PageTextLayout layout,
  required int start,
  required int end,
  List<ColumnBand> columns = const <ColumnBand>[],
  List<TextRow>? rows,
}) {
  if (!layout.hasGeometry || start >= end) {
    return const <TextBox>[];
  }
  final int from = start < 0 ? 0 : start;
  final int to = end > layout.text.length ? layout.text.length : end;
  if (from >= to) {
    return const <TextBox>[];
  }
  final List<TextRow> lines = rows ?? pageRows(layout, columns: columns);
  final List<TextBox> rects = <TextBox>[];
  for (final TextRow row in lines) {
    if (row.end <= from || row.start >= to) {
      continue;
    }
    final int left = row.start > from ? row.start : from;
    final int right = row.end < to ? row.end : to;
    TextBox? union;
    for (int i = left; i < right; i++) {
      final TextBox? box = layout.boxAt(i);
      if (box == null) {
        continue;
      }
      union = union == null ? box : _union(union, box);
    }
    if (union != null) {
      // Прямоугольник тянется на всю высоту строки, а не на высоту
      // попавших в него букв: подсветка, скачущая по вертикали от «а» к
      // «б», читается как дрожь, а не как маркер.
      rects.add(
        TextBox(
          left: union.left,
          top: row.top,
          right: union.right,
          bottom: row.bottom,
        ),
      );
    }
  }
  return rects;
}

/// Место в тексте, ближайшее к точке страницы.
///
/// Точка — в долях страницы. Нужна выделению: палец попадает не в символ,
/// а куда придётся, и промах по вертикали (между строк) стоит дороже
/// промаха по горизонтали — поэтому сначала выбирается строка, и только
/// потом место внутри неё.
int? indexAtPoint({
  required PageTextLayout layout,
  required double x,
  required double y,
  List<ColumnBand> columns = const <ColumnBand>[],
  List<TextRow>? rows,
}) {
  if (!layout.hasGeometry) {
    return null;
  }
  final List<TextRow> lines = rows ?? pageRows(layout, columns: columns);
  if (lines.isEmpty) {
    return null;
  }
  TextRow? best;
  double bestDistance = double.infinity;
  for (final TextRow row in lines) {
    final double distance = y < row.top
        ? row.top - y
        : (y > row.bottom ? y - row.bottom : 0);
    // При равном расстоянии выигрывает строка, в которую точка попала по
    // горизонтали: на двухколоночной странице соседняя колонка стоит на
    // той же высоте, и без этого палец уезжал бы в чужой текст.
    final double penalty = x < row.left
        ? row.left - x
        : (x > row.right ? x - row.right : 0);
    final double score = distance * 4 + penalty;
    if (score < bestDistance) {
      bestDistance = score;
      best = row;
    }
  }
  if (best == null) {
    return null;
  }
  int nearest = best.start;
  double nearestDistance = double.infinity;
  for (int i = best.start; i < best.end; i++) {
    final TextBox? box = layout.boxAt(i);
    if (box == null) {
      continue;
    }
    final double distance = (box.centerX - x).abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearest = i;
    }
  }
  return nearest;
}

/// Место символа среди прямоугольников движка по месту [index] в тексте.
///
/// Наш слой текста считает места **кодовыми единицами** строки Dart, а
/// движок отдаёт по прямоугольнику на **кодовую точку**. Пока в тексте
/// нет ничего за пределами основной плоскости Юникода, это одно и то же;
/// как только встретится эмодзи или редкий иероглиф, счёт разъедется — и
/// выделение, отданное просмотрщику, поедет на соседние буквы. Поэтому
/// перевод делается явно и только тогда, когда длины не сошлись.
///
/// Возвращает `null`, если переводить не во что.
int? charRectIndex(String text, int index, int rectCount) {
  if (index < 0 || rectCount <= 0) {
    return null;
  }
  if (text.length == rectCount) {
    return index >= rectCount ? rectCount - 1 : index;
  }
  int at = 0;
  int unit = 0;
  while (unit < index && unit < text.length) {
    final int code = text.codeUnitAt(unit);
    // Суррогатная пара — одна кодовая точка и один прямоугольник.
    final bool pair =
        code >= 0xD800 &&
        code <= 0xDBFF &&
        unit + 1 < text.length &&
        text.codeUnitAt(unit + 1) >= 0xDC00 &&
        text.codeUnitAt(unit + 1) <= 0xDFFF;
    unit += pair ? 2 : 1;
    at++;
  }
  return at >= rectCount ? rectCount - 1 : at;
}

/// Границы слова вокруг места [index].
///
/// Выделение начинается со слова, а не с буквы: попасть пальцем в букву
/// нельзя, а в слово — можно.
({int start, int end})? wordAround(String text, int index) {
  if (text.isEmpty) {
    return null;
  }
  int at = index;
  if (at >= text.length) {
    at = text.length - 1;
  }
  if (at < 0) {
    at = 0;
  }
  if (!_isWordChar(text.codeUnitAt(at))) {
    // Палец попал в пробел или знак препинания — берётся ближайшее слово
    // слева, а если его нет, то справа.
    int left = at;
    while (left > 0 && !_isWordChar(text.codeUnitAt(left - 1))) {
      left--;
    }
    if (left > 0) {
      at = left - 1;
    } else {
      int right = at;
      while (right < text.length && !_isWordChar(text.codeUnitAt(right))) {
        right++;
      }
      if (right >= text.length) {
        return null;
      }
      at = right;
    }
  }
  int start = at;
  while (start > 0 && _isWordChar(text.codeUnitAt(start - 1))) {
    start--;
  }
  int end = at + 1;
  while (end < text.length && _isWordChar(text.codeUnitAt(end))) {
    end++;
  }
  return (start: start, end: end);
}

TextBox _union(TextBox a, TextBox b) {
  return TextBox(
    left: a.left < b.left ? a.left : b.left,
    top: a.top < b.top ? a.top : b.top,
    right: a.right > b.right ? a.right : b.right,
    bottom: a.bottom > b.bottom ? a.bottom : b.bottom,
  );
}

/// Считается ли символ частью слова.
///
/// Дефис внутри слова — часть слова («по-моему»), а тире между словами —
/// нет; различить их по одному символу нельзя, поэтому дефис засчитан:
/// лишняя половина слова в выделении лучше, чем разрезанное надвое
/// «по-» и «моему».
bool _isWordChar(int code) {
  if (code >= 0x30 && code <= 0x39) {
    return true; // цифры
  }
  if (code >= 0x41 && code <= 0x5A) {
    return true; // A–Z
  }
  if (code >= 0x61 && code <= 0x7A) {
    return true; // a–z
  }
  if (code == 0x2D || code == 0x27 || code == 0x2019) {
    return true; // дефис и апострофы
  }
  if (code >= 0x0400 && code <= 0x04FF) {
    return true; // кириллица
  }
  if (code >= 0x00C0 && code <= 0x024F) {
    return true; // латиница с диакритикой
  }
  if (code >= 0x0370 && code <= 0x03FF) {
    return true; // греческий
  }
  // Всё, что за пределами известных алфавитов, но не пробел и не знак
  // препинания, считается словом: китайский, японский и корейский текст
  // иначе не выделился бы вовсе.
  return code > 0x2E80;
}
