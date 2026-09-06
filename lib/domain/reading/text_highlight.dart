/// Прямоугольники подсветки: из куска текста — в то, что видно на странице.
///
/// Одна и та же математика обслуживает двоих. Выделение показывает, где
/// стоит выделенный текст, и по этим же прямоугольникам панель действий
/// понимает, куда ей встать. Поиск подсвечивает найденное — долг, честно
/// отложенный в S3 именно до этой сессии, потому что до координат
/// символов подсвечивать было нечем.
///
/// Обратного хода — «точка на странице → место в тексте» — здесь больше
/// нет. Он был нужен, пока мы вели диапазон выделения сами, отдавая его
/// просмотрщику готовым; с S6.2 диапазон ведёт сам просмотрщик, потому
/// что страницу рисует он же.
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
