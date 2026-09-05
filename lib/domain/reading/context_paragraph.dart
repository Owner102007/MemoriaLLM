/// Абзац вокруг выделения — чистая математика над текстом и координатами.
///
/// Модели нужен не абзац ради абзаца, а ответ на вопрос «в каком смысле
/// это слово стоит здесь». Поэтому контекст берётся **в порядке чтения**:
/// на двухколоночной странице продолжение левой колонки лежит вверху
/// правой, а вовсе не справа на той же высоте — и абзац, собранный по
/// горизонтали, склеил бы два разных текста в один.
///
/// Границы абзаца ищутся по тому же, по чему их видит глаз: пустой
/// промежуток между строками, недописанная до края последняя строка,
/// красная строка следующего абзаца. Ни одна из этих примет не
/// безошибочна поодиночке, поэтому засчитывается любая.
library;

import 'columns.dart';
import 'page_rows.dart';
import 'reader_document.dart';
import 'text_geometry.dart';

/// Абзац вокруг выделения.
class ParagraphContext {
  /// Создаёт контекст.
  const ParagraphContext({
    required this.text,
    required this.selectionStart,
    required this.selectionEnd,
  });

  /// Текст абзаца, склеенный по строкам.
  final String text;

  /// Где внутри [text] начинается выделение.
  final int selectionStart;

  /// Где внутри [text] кончается выделение.
  final int selectionEnd;

  /// Выделенный кусок так, как он выглядит внутри абзаца.
  String get selection => text.substring(selectionStart, selectionEnd);

  @override
  String toString() => 'ParagraphContext(${text.length} символов)';
}

/// Собирает абзац вокруг выделения.
///
/// Возвращает `null`, если контекст взять неоткуда: пустая страница или
/// выделение за её пределами. Страница без геометрии (испорченный
/// текстовый слой) не остаётся без ответа вовсе — абзац берётся окном по
/// тексту, потому что половина контекста лучше, чем ничего.
ParagraphContext? paragraphAround({
  required PageTextLayout layout,
  required int selectionStart,
  required int selectionEnd,
  List<ColumnBand> columns = const <ColumnBand>[],
  int maxChars = 1200,
}) {
  final String text = layout.text;
  if (text.isEmpty || selectionStart < 0 || selectionEnd > text.length) {
    return null;
  }
  final int from = selectionStart < selectionEnd ? selectionStart : selectionEnd;
  final int to = selectionStart < selectionEnd ? selectionEnd : selectionStart;
  if (from == to) {
    return null;
  }
  if (!layout.hasGeometry) {
    return _windowAround(text, from, to, maxChars);
  }

  final List<TextRow> rows = pageRows(layout, columns: columns);
  if (rows.isEmpty) {
    return _windowAround(text, from, to, maxChars);
  }
  final int first = _rowAt(rows, from);
  final int lastRow = _rowAt(rows, to - 1);
  if (first < 0 || lastRow < 0) {
    return _windowAround(text, from, to, maxChars);
  }

  final _Shape shape = _Shape.of(rows, columns);
  int top = first;
  while (top > 0 && !_breaksBetween(rows, top - 1, text, shape)) {
    top--;
  }
  int bottom = lastRow;
  while (bottom + 1 < rows.length &&
      !_breaksBetween(rows, bottom, text, shape)) {
    bottom++;
  }

  return _assemble(
    rows: rows,
    text: text,
    fromRow: top,
    toRow: bottom,
    selectionStart: from,
    selectionEnd: to,
    maxChars: maxChars,
  );
}

/// Признаки абзаца, посчитанные один раз на страницу.
class _Shape {
  const _Shape({
    required this.lineHeight,
    required this.gap,
    required this.columnLeft,
    required this.columnRight,
  });

  factory _Shape.of(List<TextRow> rows, List<ColumnBand> columns) {
    final double height = median(<double>[
      for (final TextRow row in rows) row.height,
    ]);
    final List<double> gaps = <double>[];
    for (int i = 1; i < rows.length; i++) {
      if (rows[i].column == rows[i - 1].column) {
        final double gap = rows[i].top - rows[i - 1].bottom;
        if (gap >= 0) {
          gaps.add(gap);
        }
      }
    }
    final Map<int, double> lefts = <int, double>{};
    final Map<int, double> rights = <int, double>{};
    for (final TextRow row in rows) {
      final double? left = lefts[row.column];
      if (left == null || row.left < left) {
        lefts[row.column] = row.left;
      }
      final double? right = rights[row.column];
      if (right == null || row.right > right) {
        rights[row.column] = row.right;
      }
    }
    return _Shape(
      lineHeight: height,
      gap: median(gaps),
      columnLeft: lefts,
      columnRight: rights,
    );
  }

  /// Медианная высота строки.
  final double lineHeight;

  /// Медианный просвет между строками.
  final double gap;

  /// Левый край текста в каждой колонке.
  final Map<int, double> columnLeft;

  /// Правый край текста в каждой колонке.
  final Map<int, double> columnRight;

  /// Ширина колонки по её крайним строкам.
  double widthOf(int column) {
    final double left = columnLeft[column] ?? 0;
    final double right = columnRight[column] ?? 1;
    final double width = right - left;
    return width > 0 ? width : 1;
  }
}

/// Кончается ли абзац между строкой [index] и следующей.
bool _breaksBetween(
  List<TextRow> rows,
  int index,
  String text,
  _Shape shape,
) {
  final TextRow current = rows[index];
  final TextRow next = rows[index + 1];

  if (current.column != next.column) {
    // Колонка сменилась. Это либо продолжение чтения — низ левой колонки
    // и верх правой, — либо прыжок куда попало, если строки в файле лежат
    // не по порядку чтения. Продолжением считается только движение
    // вправо и вверх: ровно так выглядит переход через межколоночное поле.
    final bool wraps = next.column > current.column && next.top < current.top;
    if (!wraps) {
      return true;
    }
  } else if (shape.gap > 0 && next.top - current.bottom > shape.gap * 1.8) {
    // Между абзацами всегда больше пустоты, чем между строками одного.
    return true;
  } else if (shape.gap <= 0 &&
      shape.lineHeight > 0 &&
      next.top - current.bottom > shape.lineHeight * 0.9) {
    return true;
  }

  final double width = shape.widthOf(current.column);
  final double right = shape.columnRight[current.column] ?? current.right;
  // Последняя строка абзаца не дописана до правого края. Порог намеренно
  // великоват: у выключки по левому краю строки и внутри абзаца кончаются
  // где придётся, и цена ошибки здесь — лишний абзац в запросе, а не
  // потерянный.
  final bool short = right - current.right > width * 0.16;

  final double left = shape.columnLeft[next.column] ?? next.left;
  // Красная строка следующего абзаца.
  final bool indented = next.left - left > width * 0.02;

  if (short && indented) {
    return true;
  }
  if (short && _endsSentence(text.substring(current.start, current.end))) {
    return true;
  }
  return indented && _endsSentence(text.substring(current.start, current.end));
}

/// Кончается ли строка концом предложения.
bool _endsSentence(String line) {
  final String trimmed = line.trimRight();
  if (trimmed.isEmpty) {
    return false;
  }
  const String enders = '.!?…»"”\')';
  return enders.contains(trimmed[trimmed.length - 1]);
}

ParagraphContext _assemble({
  required List<TextRow> rows,
  required String text,
  required int fromRow,
  required int toRow,
  required int selectionStart,
  required int selectionEnd,
  required int maxChars,
}) {
  final StringBuffer buffer = StringBuffer();
  final List<_Placed> placed = <_Placed>[];

  for (int i = fromRow; i <= toRow; i++) {
    final TextRow row = rows[i];
    final String raw = text.substring(row.start, row.end);
    final String line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    // Сколько пробелов съедено слева: на столько же сдвигаются места
    // выделения внутри этой строки.
    final int shift = raw.length - raw.trimLeft().length;

    final String previous = buffer.toString();
    final bool glue =
        previous.isNotEmpty &&
        _isHyphen(previous[previous.length - 1]) &&
        _continuesWord(line);
    if (glue) {
      // Перенос через дефис: слово разрезано концом строки, и в запрос
      // модели оно обязано попасть целым. Иначе «пре-» и «красный»
      // приедут двумя обрубками.
      buffer.clear();
      buffer.write(previous.substring(0, previous.length - 1));
    } else if (previous.isNotEmpty) {
      buffer.write(' ');
    }

    placed.add(
      _Placed(
        sourceStart: row.start + shift,
        sourceEnd: row.start + shift + line.length,
        offset: buffer.length,
        length: line.length,
      ),
    );
    buffer.write(line);
  }

  final String paragraph = buffer.toString();
  final int start = _mapIndex(placed, selectionStart, paragraph.length);
  final int mappedEnd = _mapIndex(placed, selectionEnd, paragraph.length);
  final int end = mappedEnd > start ? mappedEnd : paragraph.length;
  return _shorten(
    ParagraphContext(
      text: paragraph,
      selectionStart: start,
      selectionEnd: end > paragraph.length ? paragraph.length : end,
    ),
    maxChars,
  );
}

/// Строка, уже уложенная в абзац.
class _Placed {
  const _Placed({
    required this.sourceStart,
    required this.sourceEnd,
    required this.offset,
    required this.length,
  });

  /// Начало строки в тексте страницы (после снятия пробелов слева).
  final int sourceStart;

  /// Конец строки в тексте страницы.
  final int sourceEnd;

  /// Куда строка легла в абзаце.
  final int offset;

  /// Длина строки в абзаце.
  final int length;
}

/// Переводит место в тексте страницы в место в собранном абзаце.
///
/// Место между строками (перенос, лишние пробелы) прижимается к
/// ближайшему краю строки: показать выделение на символ левее — не беда,
/// а промахнуться мимо абзаца целиком — беда.
int _mapIndex(List<_Placed> placed, int index, int fallback) {
  if (placed.isEmpty) {
    return 0;
  }
  for (final _Placed line in placed) {
    if (index < line.sourceStart) {
      return line.offset;
    }
    if (index <= line.sourceEnd) {
      return line.offset + (index - line.sourceStart);
    }
  }
  return fallback;
}

bool _isHyphen(String char) {
  return char == '-' || char == '‐' || char == '‑' || char == '­';
}

/// Продолжает ли строка разрезанное слово.
///
/// Заглавная буква после дефиса — это не перенос, а начало нового слова
/// («Санкт-» и «Петербург» так и должны склеиться, а вот «Иванов-» и
/// «Петров» на границе строк почти всегда список, а не одно слово).
bool _continuesWord(String line) {
  if (line.isEmpty) {
    return false;
  }
  final String first = line[0];
  return first.toLowerCase() == first && first.toUpperCase() != first;
}

/// Обрезает слишком длинный абзац вокруг выделения.
///
/// Целые страницы сплошного текста без единого просвета встречаются чаще,
/// чем хотелось бы: у модели есть предел входа, а у читателя — терпение.
/// Режется по словам и симметрично относительно выделения.
ParagraphContext _shorten(ParagraphContext context, int maxChars) {
  if (maxChars <= 0 || context.text.length <= maxChars) {
    return context;
  }
  final int selectionLength = context.selectionEnd - context.selectionStart;
  if (selectionLength >= maxChars) {
    return ParagraphContext(
      text: context.selection,
      selectionStart: 0,
      selectionEnd: selectionLength,
    );
  }
  final int room = maxChars - selectionLength;
  int left = context.selectionStart - room ~/ 2;
  int right = context.selectionEnd + room ~/ 2;
  if (left < 0) {
    right += -left;
    left = 0;
  }
  if (right > context.text.length) {
    left -= right - context.text.length;
    right = context.text.length;
  }
  if (left < 0) {
    left = 0;
  }
  left = _wordBoundary(context.text, left, forward: true);
  right = _wordBoundary(context.text, right, forward: false);
  if (left > context.selectionStart) {
    left = context.selectionStart;
  }
  if (right < context.selectionEnd) {
    right = context.selectionEnd;
  }
  final String cut = context.text.substring(left, right);
  return ParagraphContext(
    text: cut,
    selectionStart: context.selectionStart - left,
    selectionEnd: context.selectionEnd - left,
  );
}

int _wordBoundary(String text, int at, {required bool forward}) {
  int index = at;
  if (forward) {
    while (index > 0 && index < text.length && text[index - 1] != ' ') {
      index++;
    }
    return index > text.length ? text.length : index;
  }
  while (index > 0 && index < text.length && text[index] != ' ') {
    index--;
  }
  return index < 0 ? 0 : index;
}

/// Контекст без геометрии: окно по тексту вокруг выделения.
ParagraphContext _windowAround(String text, int from, int to, int maxChars) {
  final ParagraphContext whole = ParagraphContext(
    text: text,
    selectionStart: from,
    selectionEnd: to,
  );
  return _shorten(whole, maxChars);
}

int _rowAt(List<TextRow> rows, int index) {
  for (int i = 0; i < rows.length; i++) {
    if (rows[i].contains(index)) {
      return i;
    }
    if (rows[i].start > index) {
      // Индекс попал в пробел между строками — берётся ближайшая.
      return i == 0 ? 0 : i - 1;
    }
  }
  return rows.isEmpty ? -1 : rows.length - 1;
}
