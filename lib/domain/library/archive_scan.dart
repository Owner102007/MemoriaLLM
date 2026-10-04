/// Архивы с книгами, найденные на устройстве (SNO-F-LIT-03,
/// SNO-ALG-LIT-02).
///
/// Литература исследования СНО2026 приходит тестировщику одним
/// ZIP-архивом, и искать его в системном диалоге выбора на телефоне
/// оказалось трудно (проверка шага 13). Поэтому сборка ветви находит
/// архивы сама: обходит устройство тем же обходом, что ищет книги в
/// основном приложении, но отбирает только ZIP-архивы, в которых лежат
/// PDF.
///
/// Здесь — то, что не трогает диск: что такое найденный архив, в каком
/// порядке архивы стоят в списке и какими словами о них сказано. Сам
/// обход — `infrastructure/files/archive_scanner.dart`.
library;

/// Архив с книгами, найденный обходом.
class FoundArchive {
  /// Создаёт запись об архиве.
  const FoundArchive({
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.books,
  });

  /// Полный путь на устройстве.
  final String path;

  /// Размер в байтах.
  final int size;

  /// Когда файл изменяли в последний раз.
  final DateTime modifiedAt;

  /// Сколько книг архив положит на полку: PDF по правилу раскладки
  /// (`layoutShelfArchive`), без служебных файлов.
  final int books;

  /// Имя файла без папок.
  String get name {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is FoundArchive &&
      other.path == path &&
      other.size == size &&
      other.modifiedAt == modifiedAt &&
      other.books == books;

  @override
  int get hashCode => Object.hash(path, size, modifiedAt, books);

  @override
  String toString() => 'FoundArchive($path, $books)';
}

/// Поиск архивов с книгами: корни обхода → поток находок.
///
/// Поток закрывается сам, когда обход закончен; оборванный обход
/// закрывает его ошибкой `ScanFailure`. Настоящий поиск идёт в изоляте
/// (`findArchivesInIsolate`); widget-тесты подставляют свой — изолят с
/// подменённым временем они не дождутся.
typedef ArchiveSearch = Stream<FoundArchive> Function(List<String> roots);

/// Поиск, который ничего не ищет: основное приложение архивов не знает.
Stream<FoundArchive> noArchiveSearch(List<String> roots) {
  return const Stream<FoundArchive>.empty();
}

/// Папки корня, с которых обход архивов начинает.
///
/// Архив, который прислали или скачали, почти всегда лежит в одной из
/// них. Полный обход телефона идёт десятки секунд; с этим порядком
/// нужный архив появляется в списке в первые секунды. Имена — как на
/// диске, без регистра: на Android «Загрузки» называются `Download`, на
/// Windows — `Downloads`, каким бы ни был язык системы.
const List<String> kArchiveFirstFolders = <String>[
  'download',
  'downloads',
  'desktop',
  'documents',
  'telegram',
  'telegram desktop',
  'onedrive',
];

/// Очерёдность папки корня при поиске архивов: меньше — раньше.
int archiveRootOrder(String name) {
  final int at = kArchiveFirstFolders.indexOf(name.toLowerCase());
  return at < 0 ? kArchiveFirstFolders.length : at;
}

/// Порядок архивов в списке: новые сверху, при равенстве — по имени.
///
/// Экспериментатор ищет архив, который только что получил, — он и
/// должен стоять первым.
int compareFoundArchives(FoundArchive left, FoundArchive right) {
  final int byTime = right.modifiedAt.compareTo(left.modifiedAt);
  if (byTime != 0) {
    return byTime;
  }
  final int byName = left.name.toLowerCase().compareTo(
    right.name.toLowerCase(),
  );
  return byName != 0 ? byName : left.path.compareTo(right.path);
}

/// Где лежит архив — папкой относительно корня обхода.
///
/// «Download/Telegram», а не `/storage/emulated/0/Download/Telegram`:
/// начало пути у всех архивов одно и ничего не говорит. Архив в самом
/// корне назван «в корне памяти»; архив вне корней — полной папкой.
String archivePlace(String path, List<String> roots) {
  final String normal = path.replaceAll(r'\', '/');
  final int slash = normal.lastIndexOf('/');
  final String folder = slash < 0 ? '' : normal.substring(0, slash);
  String? best;
  for (final String root in roots) {
    String base = root.replaceAll(r'\', '/');
    while (base.length > 1 && base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final bool inside = folder == base || folder.startsWith('$base/');
    if (inside && (best == null || base.length > best.length)) {
      best = base;
    }
  }
  if (best == null) {
    return folder;
  }
  if (folder.length == best.length) {
    return 'в корне памяти';
  }
  return folder.substring(best.length + 1);
}

/// «1 книга», «2 книги», «5 книг».
String describeBookCount(int count) {
  final int tail = count % 100;
  final int last = count % 10;
  final String word;
  if (tail >= 11 && tail <= 14) {
    word = 'книг';
  } else if (last == 1) {
    word = 'книга';
  } else if (last >= 2 && last <= 4) {
    word = 'книги';
  } else {
    word = 'книг';
  }
  return '$count $word';
}

/// Размер файла словами: «2,1 ГБ», «340 МБ», «12 КБ».
///
/// До сотни единиц — с одним знаком после запятой, дальше — целым
/// числом: «2,1 ГБ» от «2,9 ГБ» отличить важно, «340,2 МБ» от «340 МБ» —
/// нет.
String describeFileSize(int bytes) {
  const int step = 1024;
  if (bytes < step) {
    return '$bytes Б';
  }
  const List<String> units = <String>['КБ', 'МБ', 'ГБ', 'ТБ'];
  double value = bytes / step;
  int unit = 0;
  // Полшага запаса: 1023,6 КБ — это «1,0 МБ», а не «1024 КБ».
  while (value >= step - 0.5 && unit < units.length - 1) {
    value /= step;
    unit++;
  }
  // 99,96 округлилось бы до «100,0»: такое число пишется уже целым.
  final String number = value < 99.95
      ? value.toStringAsFixed(1).replaceAll('.', ',')
      : value.toStringAsFixed(0);
  return '$number ${units[unit]}';
}

/// Строка под именем архива в списке: «34 книги · 2,1 ГБ · Download».
String describeFoundArchive(FoundArchive archive, List<String> roots) {
  return <String>[
    describeBookCount(archive.books),
    describeFileSize(archive.size),
    archivePlace(archive.path, roots),
  ].join(' · ');
}
