/// Раскладка архива с книгами: какая запись — какая книга и в какую
/// категорию она встаёт (SNO-ALG-LIT-01, SNO-F-LIT-01).
///
/// Архив собирают руками, «Проводником» или 7-Zip, без инструментов и
/// без манифеста: папка — категория, порядок — по именам. Тот же формат
/// сможет писать отправка полки (F-LIB-19), когда до неё дойдёт.
///
/// Здесь только правило над списком имён — ни файлов, ни архива: оно
/// проверяется обычными тестами на придуманных списках.
library;

import 'book.dart';
import 'book_category.dart';

/// Книга, которую архив кладёт на полку.
class ArchiveBook {
  /// Создаёт описание книги.
  const ArchiveBook({
    required this.entry,
    required this.path,
    required this.title,
    required this.category,
  });

  /// Номер записи в списке, переданном раскладке.
  final int entry;

  /// Путь записи в архиве, как он там записан.
  final String path;

  /// Название книги — из имени файла, без цифр порядка в начале.
  final String title;

  /// Название категории; `null` — «Без категории».
  final String? category;

  /// Имя файла без папок — так книгу называют в сообщении об отказе.
  String get fileName => path.substring(path.lastIndexOf('/') + 1);

  @override
  String toString() => 'ArchiveBook($category, $title)';
}

/// Что архив кладёт на полку.
class ArchiveLayout {
  /// Создаёт раскладку.
  const ArchiveLayout({
    required this.books,
    required this.categories,
    required this.skipped,
  });

  /// Книги в том порядке, в каком они встают на полку: сначала «Без
  /// категории», затем категории по порядку имён папок, внутри — по
  /// именам файлов.
  final List<ArchiveBook> books;

  /// Названия категорий в порядке полки.
  final List<String> categories;

  /// Сколько файлов пропущено, потому что это не PDF. Служебные файлы
  /// систем сюда не входят: о них экспериментатору знать незачем.
  final int skipped;
}

/// Архив ли это, судя по имени файла.
bool isArchiveName(String name) => name.toLowerCase().endsWith('.zip');

/// Раскладывает записи архива по полке.
///
/// [names] — имена записей с путями, папки разделены `/`.
///
/// - Папка верхнего уровня — категория; файлы в корне встают в «Без
///   категории». Папки глубже первой категорий не заводят: их книги
///   ложатся в категорию верхней папки.
/// - Порядок — по именам, числа сравниваются как числа: «2» раньше «10».
///   Цифры в начале имени («01 Анатомия») задают порядок и в название не
///   попадают.
/// - Общая папка-обёртка снимается: если все файлы лежат в одной верхней
///   папке и в ней есть подпапки, категориями становятся подпапки — так
///   выглядит архив, в который упаковали папку целиком.
/// - Не-PDF пропускаются и сосчитаны; служебное (`__MACOSX`, `.DS_Store`,
///   `Thumbs.db`, `desktop.ini`) пропускается молча.
ArchiveLayout layoutShelfArchive(List<String> names) {
  final List<_Item> files = <_Item>[];
  for (int i = 0; i < names.length; i++) {
    final String name = names[i].replaceAll(r'\', '/');
    if (name.endsWith('/')) {
      continue;
    }
    final List<String> parts = <String>[
      for (final String part in name.split('/'))
        if (part.isNotEmpty && part != '.') part,
    ];
    if (parts.isEmpty || parts.any(_isService)) {
      continue;
    }
    files.add(_Item(i, names[i], parts));
  }

  final bool wrapped = _isWrapped(files);
  int skipped = 0;
  final List<_Item> books = <_Item>[];
  for (final _Item file in files) {
    final List<String> parts = wrapped ? file.parts.sublist(1) : file.parts;
    if (!parts.last.toLowerCase().endsWith('.pdf')) {
      skipped++;
      continue;
    }
    books.add(_Item(file.entry, file.path, parts));
  }
  books.sort(_compareItems);

  final List<String> categories = <String>[];
  final Set<String> seen = <String>{};
  final List<ArchiveBook> result = <ArchiveBook>[];
  for (final _Item book in books) {
    final String? category = book.folder == null
        ? null
        : normalizeCategoryTitle(stripOrderPrefix(book.folder!));
    if (category != null && seen.add(category.toLowerCase())) {
      categories.add(category);
    }
    final String file = book.parts.last;
    result.add(
      ArchiveBook(
        entry: book.entry,
        path: book.path,
        // Расширение снимается до цифр порядка: у «1984.pdf» цифры —
        // название, а не порядок.
        title: titleFromFileName(
          stripOrderPrefix(file.substring(0, file.length - 4)),
        ),
        category: category,
      ),
    );
  }
  return ArchiveLayout(books: result, categories: categories, skipped: skipped);
}

/// Убирает из начала имени цифры порядка: «01 Анатомия» → «Анатомия».
///
/// Цифрами порядка считаются цифры, за которыми идёт разделитель —
/// пробел, точка, скобка, подчёркивание, тире с пробелом. «1984» и
/// «3D-атлас» остаются как есть: там цифры — часть названия. Имя, от
/// которого ничего бы не осталось, тоже не трогается.
String stripOrderPrefix(String name) {
  final String rest = name.replaceFirst(_orderPrefix, '').trim();
  return rest.isEmpty ? name.trim() : rest;
}

final RegExp _orderPrefix = RegExp(r'^\s*\d+(?:[.)_]\s*|\s*[-–—]\s+|\s+)');

/// Сравнивает имена так, как их ставит по порядку «Проводник»: без
/// регистра, а числа — как числа.
int compareNatural(String a, String b) {
  final String left = a.toLowerCase();
  final String right = b.toLowerCase();
  int i = 0;
  int j = 0;
  while (i < left.length && j < right.length) {
    if (_isDigit(left.codeUnitAt(i)) && _isDigit(right.codeUnitAt(j))) {
      final int fromLeft = i;
      final int fromRight = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      final String x = _withoutZeros(left.substring(fromLeft, i));
      final String y = _withoutZeros(right.substring(fromRight, j));
      // Числа любой длины: сначала по числу цифр, потом по самим цифрам.
      final int byNumber = x.length != y.length
          ? x.length.compareTo(y.length)
          : x.compareTo(y);
      if (byNumber != 0) {
        return byNumber;
      }
      continue;
    }
    final int byLetter = left.codeUnitAt(i).compareTo(right.codeUnitAt(j));
    if (byLetter != 0) {
      return byLetter;
    }
    i++;
    j++;
  }
  final int byRest = (left.length - i).compareTo(right.length - j);
  // Запасная ступень — сами строки: порядок обязан быть одним и тем же
  // при каждом добавлении архива.
  return byRest != 0 ? byRest : a.compareTo(b);
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

String _withoutZeros(String digits) {
  int from = 0;
  while (from < digits.length - 1 && digits.codeUnitAt(from) == 0x30) {
    from++;
  }
  return digits.substring(from);
}

/// Файл или папка, которые система положила в архив сама.
bool _isService(String part) {
  final String name = part.toLowerCase();
  return name == '__macosx' ||
      name == 'thumbs.db' ||
      name == 'desktop.ini' ||
      name.startsWith('.');
}

/// Лежит ли всё в одной папке-обёртке, внутри которой есть подпапки.
bool _isWrapped(List<_Item> files) {
  if (files.isEmpty) {
    return false;
  }
  final String top = files.first.parts.first;
  bool nested = false;
  for (final _Item file in files) {
    if (file.parts.length < 2 || file.parts.first != top) {
      return false;
    }
    nested = nested || file.parts.length >= 3;
  }
  return nested;
}

/// Сначала книги без папки, затем папки по именам, внутри — по пути.
int _compareItems(_Item a, _Item b) {
  final String? left = a.folder;
  final String? right = b.folder;
  if (left == null || right == null) {
    if (left != null) {
      return 1;
    }
    if (right != null) {
      return -1;
    }
  } else {
    final int byFolder = compareNatural(left, right);
    if (byFolder != 0) {
      return byFolder;
    }
  }
  final int byPath = compareNatural(a.inner, b.inner);
  return byPath != 0 ? byPath : a.entry.compareTo(b.entry);
}

class _Item {
  const _Item(this.entry, this.path, this.parts);

  final int entry;
  final String path;
  final List<String> parts;

  /// Папка верхнего уровня; `null` — файл лежит в корне.
  String? get folder => parts.length >= 2 ? parts.first : null;

  /// Путь внутри папки верхнего уровня.
  String get inner => parts.skip(folder == null ? 0 : 1).join('/');
}
