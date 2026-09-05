/// Правила обхода файловой системы устройства.
///
/// Обход телефона — не «найти всё, что можно», а «не показать читателю
/// чужого мусора». На среднем телефоне лежат тысячи PDF, и подавляющее
/// большинство — не книги: чеки из банка, кэш мессенджера, служебные
/// файлы приложений, выгрузки, которые кто-то забыл. Поэтому правила
/// отбора живут отдельно от самого обхода — здесь их видно все сразу и
/// проверять их можно на дереве, собранном в тесте, без телефона.
library;

/// Найденный файл: всё, что об этом знает обход.
///
/// Отпечатка здесь нет намеренно: он требует чтения файла, а обход должен
/// оставаться дешёвым. Отпечатки считаются потом и только тем файлам,
/// которые этого стоят.
class ScannedFile {
  /// Создаёт запись о файле.
  const ScannedFile({
    required this.path,
    required this.size,
    required this.modifiedAt,
  });

  /// Полный путь на устройстве.
  final String path;

  /// Размер в байтах.
  final int size;

  /// Когда файл изменяли в последний раз.
  final DateTime modifiedAt;

  /// Имя файла без папок.
  String get name {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Папка, в которой лежит файл, без пути к ней.
  ///
  /// Читатель помнит книгу не только по имени, но и по месту: «та, что в
  /// „Учебники“». Поэтому имя папки идёт в индекс наравне с именем файла.
  String get folder {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    if (slash <= 0) {
      return '';
    }
    final String head = path.substring(0, slash);
    final int parent = head.lastIndexOf(RegExp(r'[\\/]'));
    return parent < 0 ? head : head.substring(parent + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is ScannedFile &&
      other.path == path &&
      other.size == size &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(path, size, modifiedAt);

  @override
  String toString() => 'ScannedFile($path, $size)';
}

/// Папки, в которые обход не заходит никогда.
///
/// `Android/data` и `Android/obb` — служебные каталоги приложений: с
/// Android 11 в них не пускают даже с полным доступом, а те, что открыты,
/// содержат кэш, а не книги. Остальное — известные кэши мессенджеров и
/// браузеров: там лежат сотни присланных документов, из которых читателю
/// не нужен ни один, а полка от них становится помойкой.
const Set<String> kSkippedDirectoryNames = <String>{
  'cache',
  'caches',
  '.cache',
  '.thumbnails',
  '.trash',
  '.trashed',
  'lost.dir',
  'lost+found',
  'tmp',
  'temp',
  'thumbnails',
  'code_cache',
  'no_media',
};

/// Куски пути, которые целиком выводят ветку из обхода.
///
/// Проверяется вхождение в путь с разделителями по краям, поэтому папка
/// `mydata` не попадает под правило `data`.
const List<String> kSkippedPathParts = <String>[
  'android/data',
  'android/obb',
  'android/media/com.whatsapp',
  'telegram/telegram documents/cache',
];

/// Расширение, по которому файл вообще попадает в поле зрения.
const String kPdfExtension = '.pdf';

/// Первые байты настоящего PDF.
///
/// По расширению судить нельзя: `.pdf` носят и картинки, и html-страницы,
/// и обрубленные закачки. По одной сигнатуре — тоже: файл книги может
/// называться `конспект.dat`, но открывать все файлы устройства подряд
/// ради проверки — это часы работы и разряженная батарея. Поэтому правило
/// двойное: расширение отбирает кандидатов, сигнатура их подтверждает.
const List<int> kPdfSignature = <int>[0x25, 0x50, 0x44, 0x46, 0x2d];

/// Сколько байт достаточно прочитать для проверки сигнатуры.
///
/// Сигнатура обязана стоять в начале файла, но встречаются книги с
/// мусором перед ней — так их сохраняют некоторые генераторы. PDF-читалки
/// такие файлы открывают, поэтому и мы ищем сигнатуру в первой тысяче
/// байт, а не строго в нулевом смещении.
const int kSignatureProbe = 1024;

/// Похоже ли имя на PDF.
bool looksLikePdfName(String name) =>
    name.toLowerCase().endsWith(kPdfExtension);

/// Скрытое ли имя (файл или папка, начинающиеся с точки).
///
/// Точка в начале — общая договорённость всех систем о том, что
/// содержимое служебное. Читательских книг там не бывает.
bool isHiddenName(String name) => name.startsWith('.') && name != '.';

/// Заходить ли обходу в эту папку.
///
/// [path] — полный путь к папке, [name] — её собственное имя. Проверяются
/// три вещи: скрытая ли папка, не в списке ли служебных имён и не входит
/// ли путь в заведомо ненужную ветку.
bool shouldSkipDirectory({required String path, required String name}) {
  if (isHiddenName(name)) {
    return true;
  }
  if (kSkippedDirectoryNames.contains(name.toLowerCase())) {
    return true;
  }
  final String normal = '/${path.replaceAll(r'\', '/').toLowerCase()}/';
  for (final String part in kSkippedPathParts) {
    if (normal.contains('/$part/')) {
      return true;
    }
  }
  return false;
}

/// Есть ли в начале файла сигнатура PDF.
bool hasPdfSignature(List<int> head) {
  if (head.length < kPdfSignature.length) {
    return false;
  }
  final int limit = head.length - kPdfSignature.length;
  for (int start = 0; start <= limit; start++) {
    bool match = true;
    for (int i = 0; i < kPdfSignature.length; i++) {
      if (head[start + i] != kPdfSignature[i]) {
        match = false;
        break;
      }
    }
    if (match) {
      return true;
    }
  }
  return false;
}

/// Как идут дела у обхода.
///
/// Растущий список с числами — не украшение: полный обход телефона идёт
/// десятки секунд, и пустой экран с крутилкой всё это время читателю
/// сказать нечего. Он должен видеть, что книги уже находятся.
class ScanProgress {
  /// Создаёт состояние обхода.
  const ScanProgress({
    required this.found,
    required this.visitedDirectories,
    this.currentDirectory = '',
    this.done = false,
  });

  /// Сколько PDF найдено.
  final int found;

  /// Сколько папок обойдено.
  final int visitedDirectories;

  /// В какой папке обход сейчас.
  final String currentDirectory;

  /// Обход закончен.
  final bool done;

  @override
  String toString() =>
      'ScanProgress(found: $found, dirs: $visitedDirectories, done: $done)';
}
