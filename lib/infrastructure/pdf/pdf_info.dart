import 'dart:typed_data';

import '../../domain/library/book_storage.dart';

/// Метаданные PDF: то, что автор файла написал о нём сам.
///
/// Вторая ступень поиска. Первая (имя файла) бесплатна и работает сразу,
/// третья (текст страниц) требует движка и времени, а метаданные лежат
/// в самом файле готовой строкой — и часто это единственное место, где
/// у скана с именем `doc_2019_scan0043.pdf` записано настоящее название.
class PdfInfo {
  /// Создаёт метаданные.
  const PdfInfo({this.title, this.author, this.subject, this.keywords});

  /// Пустые метаданные — их в файле не нашлось.
  static const PdfInfo none = PdfInfo();

  /// Заголовок.
  final String? title;

  /// Автор.
  final String? author;

  /// Тема.
  final String? subject;

  /// Ключевые слова.
  final String? keywords;

  /// Нечего класть в индекс.
  bool get isEmpty =>
      (title ?? '').trim().isEmpty &&
      (author ?? '').trim().isEmpty &&
      (subject ?? '').trim().isEmpty &&
      (keywords ?? '').trim().isEmpty;

  /// Всё, что стоит положить в индекс, одной строкой.
  String get searchable => <String>[
    title ?? '',
    author ?? '',
    subject ?? '',
    keywords ?? '',
  ].where((String part) => part.trim().isNotEmpty).join(' ');

  @override
  String toString() => 'PdfInfo(title: $title, author: $author)';
}

/// Сколько байт читается с начала и с конца файла.
///
/// Словарь `Info` лежит либо рядом с `trailer` в конце файла, либо среди
/// первых объектов — так его кладут почти все генераторы. Читать ради
/// заголовка книгу на триста мегабайт целиком нельзя: обход и так идёт по
/// тысяче файлов, и лишняя секунда на каждом превращается в двадцать
/// минут.
const int kInfoWindow = 512 * 1024;

/// Разбирает метаданные из куска файла.
///
/// [bytes] — начало и конец файла, склеенные подряд. Разрыв между ними
/// безвреден: разбор ищет объект целиком и не находит того, что разрезано
/// пополам, — а такой объект просто останется неразобранным.
///
/// Разбор намеренно **терпимый**. Полноценно прочитать PDF значит
/// разобрать таблицу перекрёстных ссылок, потоки объектов и шифрование —
/// то есть написать половину PDFium ради строки заголовка. Здесь другой
/// размен: находим что можем, а чего не можем — честно не находим, и
/// файл остаётся с именем вместо названия.
PdfInfo parsePdfInfo(Uint8List bytes) {
  final String text = String.fromCharCodes(bytes);
  final String? dictionary = _infoDictionary(text);
  if (dictionary == null) {
    return PdfInfo.none;
  }
  final PdfInfo info = PdfInfo(
    title: _entry(dictionary, 'Title'),
    author: _entry(dictionary, 'Author'),
    subject: _entry(dictionary, 'Subject'),
    keywords: _entry(dictionary, 'Keywords'),
  );
  return info;
}

/// Читает метаданные книги, не открывая её движком.
///
/// Работает через тот же [BookHandle], что и отпечаток: у документа
/// Android пути нет вовсе, а метаданные нужны ему ровно так же.
Future<PdfInfo> readPdfInfo(BookHandle book) async {
  final int size = book.length;
  if (size <= 0) {
    return PdfInfo.none;
  }
  final int headSize = size < kInfoWindow ? size : kInfoWindow;
  final Uint8List head = Uint8List(headSize);
  if (await book.read(head, 0, headSize) <= 0) {
    return PdfInfo.none;
  }
  if (size <= kInfoWindow) {
    return parsePdfInfo(head);
  }
  final int from = size - kInfoWindow;
  final Uint8List tail = Uint8List(size - from);
  if (await book.read(tail, from, tail.length) <= 0) {
    return parsePdfInfo(head);
  }
  final Uint8List both = Uint8List(head.length + tail.length)
    ..setRange(0, head.length, head)
    ..setRange(head.length, head.length + tail.length, tail);
  return parsePdfInfo(both);
}

/// Находит тело словаря `Info`.
///
/// Сначала ищется ссылка `/Info N G R` — она стоит и в обычном
/// `trailer`, и в словаре потока перекрёстных ссылок (сам словарь там
/// лежит открытым текстом, даже когда таблица сжата). Берётся **последняя**
/// ссылка: файл мог дописываться, и последняя запись главнее.
///
/// Если ссылки нет или объект по ней не нашёлся (например, он уехал в
/// сжатый поток объектов), пробуется прямой путь — словарь, в котором
/// просто есть `/Title`.
String? _infoDictionary(String text) {
  final RegExp reference = RegExp(r'/Info\s+(\d+)\s+(\d+)\s+R');
  final List<RegExpMatch> references = reference.allMatches(text).toList();
  for (final RegExpMatch match in references.reversed) {
    final String number = match.group(1)!;
    final RegExp object = RegExp(
      '(?:^|[^0-9])$number\\s+\\d+\\s+obj',
      multiLine: true,
    );
    for (final RegExpMatch found in object.allMatches(text)) {
      final String? body = _dictionaryAt(text, found.end);
      if (body != null && body.contains('/')) {
        return body;
      }
    }
  }

  final int direct = text.indexOf('/Title');
  if (direct < 0) {
    return null;
  }
  final int open = text.lastIndexOf('<<', direct);
  if (open < 0) {
    return null;
  }
  return _dictionaryAt(text, open);
}

/// Вырезает словарь `<< … >>`, начиная поиск с [from].
///
/// Вложенные словари считаются: у `Info` их не бывает, но у объекта,
/// который мы приняли за `Info`, — запросто, и остановка на первом `>>`
/// обрезала бы его на середине.
String? _dictionaryAt(String text, int from) {
  final int open = text.indexOf('<<', from);
  if (open < 0) {
    return null;
  }
  int depth = 0;
  int i = open;
  while (i < text.length - 1) {
    if (text.startsWith('<<', i)) {
      depth++;
      i += 2;
      continue;
    }
    if (text.startsWith('>>', i)) {
      depth--;
      i += 2;
      if (depth == 0) {
        return text.substring(open + 2, i - 2);
      }
      continue;
    }
    i++;
  }
  return null;
}

/// Достаёт значение одного ключа словаря.
String? _entry(String dictionary, String key) {
  final int at = dictionary.indexOf('/$key');
  if (at < 0) {
    return null;
  }
  int i = at + key.length + 1;
  while (i < dictionary.length && _isWhitespace(dictionary.codeUnitAt(i))) {
    i++;
  }
  if (i >= dictionary.length) {
    return null;
  }
  final int code = dictionary.codeUnitAt(i);
  if (code == 0x28) {
    return _decodeText(_literalString(dictionary, i));
  }
  if (code == 0x3c && !dictionary.startsWith('<<', i)) {
    return _decodeText(_hexString(dictionary, i));
  }
  return null;
}

/// Читает строку в скобках со всеми экранированиями PDF.
List<int> _literalString(String text, int open) {
  final List<int> out = <int>[];
  int depth = 0;
  int i = open;
  while (i < text.length) {
    final int code = text.codeUnitAt(i);
    if (code == 0x5c) {
      i++;
      if (i >= text.length) {
        break;
      }
      final int escaped = text.codeUnitAt(i);
      switch (escaped) {
        case 0x6e:
          out.add(0x0a);
        case 0x72:
          out.add(0x0d);
        case 0x74:
          out.add(0x09);
        case 0x62:
          out.add(0x08);
        case 0x66:
          out.add(0x0c);
        case 0x0a:
          // Перенос строки после обратной косой — склейка длинной
          // строки, в самой строке его нет.
          break;
        case 0x0d:
          if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0a) {
            i++;
          }
        default:
          if (escaped >= 0x30 && escaped <= 0x37) {
            int value = 0;
            int digits = 0;
            while (digits < 3 &&
                i < text.length &&
                text.codeUnitAt(i) >= 0x30 &&
                text.codeUnitAt(i) <= 0x37) {
              value = value * 8 + (text.codeUnitAt(i) - 0x30);
              i++;
              digits++;
            }
            i--;
            out.add(value & 0xff);
          } else {
            out.add(escaped);
          }
      }
      i++;
      continue;
    }
    if (code == 0x28) {
      depth++;
      if (depth > 1) {
        out.add(code);
      }
      i++;
      continue;
    }
    if (code == 0x29) {
      depth--;
      if (depth == 0) {
        return out;
      }
      out.add(code);
      i++;
      continue;
    }
    out.add(code);
    i++;
  }
  return out;
}

/// Читает строку в угловых скобках: шестнадцатеричные пары.
List<int> _hexString(String text, int open) {
  final List<int> out = <int>[];
  int value = 0;
  int digits = 0;
  for (int i = open + 1; i < text.length; i++) {
    final int code = text.codeUnitAt(i);
    if (code == 0x3e) {
      break;
    }
    final int digit = _hexDigit(code);
    if (digit < 0) {
      continue;
    }
    value = value * 16 + digit;
    digits++;
    if (digits == 2) {
      out.add(value);
      value = 0;
      digits = 0;
    }
  }
  if (digits == 1) {
    // Нечётное число цифр: последняя пара дополняется нулём — так велит
    // сам формат.
    out.add(value * 16);
  }
  return out;
}

/// Превращает байты строки PDF в текст.
///
/// Две кодировки: UTF-16BE, если в начале стоит метка `FE FF`, и
/// PDFDocEncoding во всех прочих случаях. Вторая в той части, которая нас
/// интересует, совпадает с Latin-1 — то есть с прямым переводом байта в
/// символ.
String? _decodeText(List<int> bytes) {
  if (bytes.isEmpty) {
    return null;
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    final StringBuffer out = StringBuffer();
    for (int i = 2; i + 1 < bytes.length; i += 2) {
      out.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return _clean(out.toString());
  }
  return _clean(String.fromCharCodes(bytes));
}

String? _clean(String raw) {
  final String text = raw
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x0a || code == 0x0d || code == 0x09;

int _hexDigit(int code) {
  if (code >= 0x30 && code <= 0x39) {
    return code - 0x30;
  }
  if (code >= 0x61 && code <= 0x66) {
    return code - 0x61 + 10;
  }
  if (code >= 0x41 && code <= 0x46) {
    return code - 0x41 + 10;
  }
  return -1;
}
