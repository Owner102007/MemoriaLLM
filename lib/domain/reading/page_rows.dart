/// Строки страницы по координатам символов — общая основа выделения,
/// контекста и подсветки.
///
/// Строка здесь — это не строка файла, а то, что читатель видит строкой:
/// подряд идущие символы, стоящие на одной высоте в одной колонке. Из
/// таких строк собирается абзац вокруг выделения, ими же рисуется
/// подсветка найденного, и они же переводят точку экрана в место в
/// тексте.
library;

import 'columns.dart';
import 'reader_document.dart';
import 'text_geometry.dart';

/// Строка страницы: где она лежит и какой кусок текста ей соответствует.
class TextRow {
  /// Создаёт строку.
  const TextRow({
    required this.start,
    required this.end,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.column,
  });

  /// Индекс первого символа строки в тексте страницы.
  final int start;

  /// Индекс за последним символом строки.
  final int end;

  /// Левая граница в долях страницы.
  final double left;

  /// Верхняя граница.
  final double top;

  /// Правая граница.
  final double right;

  /// Нижняя граница.
  final double bottom;

  /// Номер колонки, в которой стоит строка.
  final int column;

  /// Высота строки.
  double get height => bottom - top;

  /// Содержит ли строка место [index] в тексте.
  bool contains(int index) => index >= start && index < end;

  @override
  String toString() => 'TextRow($start..$end, колонка $column)';
}

/// Разбивает страницу на строки по координатам символов.
///
/// Строка обрывается там, где следующий символ не перекрывается с ней по
/// вертикали или уходит в другую колонку. Символы без своего места
/// (пробелы, переводы строк) в разбивке не участвуют, но остаются внутри
/// строки: текст строки берётся куском исходного текста от первого
/// символа до последнего, и пробелы внутри него сохраняются как есть.
List<TextRow> pageRows(
  PageTextLayout layout, {
  List<ColumnBand> columns = const <ColumnBand>[],
  double overlapShare = 0.4,
}) {
  if (!layout.hasGeometry) {
    return const <TextRow>[];
  }
  final List<TextRow> rows = <TextRow>[];
  int? start;
  int last = 0;
  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;
  int column = 0;

  for (int i = 0; i < layout.boxes.length; i++) {
    final TextBox? box = layout.boxAt(i);
    if (box == null) {
      continue;
    }
    final int boxColumn = _columnOf(box, columns);
    if (start == null) {
      start = i;
      last = i;
      left = box.left;
      top = box.top;
      right = box.right;
      bottom = box.bottom;
      column = boxColumn;
      continue;
    }
    final double overlap =
        (bottom < box.bottom ? bottom : box.bottom) -
        (top > box.top ? top : box.top);
    final double reference = box.height < (bottom - top)
        ? box.height
        : (bottom - top);
    final bool sameLine =
        boxColumn == column && overlap >= reference * overlapShare;
    if (sameLine) {
      last = i;
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
      continue;
    }
    rows.add(
      TextRow(
        start: start,
        end: last + 1,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        column: column,
      ),
    );
    start = i;
    last = i;
    left = box.left;
    top = box.top;
    right = box.right;
    bottom = box.bottom;
    column = boxColumn;
  }
  if (start != null) {
    rows.add(
      TextRow(
        start: start,
        end: last + 1,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        column: column,
      ),
    );
  }
  return rows;
}

int _columnOf(TextBox box, List<ColumnBand> columns) {
  if (columns.length < 2) {
    return 0;
  }
  final double center = box.centerX;
  for (int i = 0; i < columns.length; i++) {
    if (center >= columns[i].left && center <= columns[i].right) {
      return i;
    }
  }
  int nearest = 0;
  double best = double.infinity;
  for (int i = 0; i < columns.length; i++) {
    final double distance = center < columns[i].left
        ? columns[i].left - center
        : center - columns[i].right;
    if (distance < best) {
      best = distance;
      nearest = i;
    }
  }
  return nearest;
}
