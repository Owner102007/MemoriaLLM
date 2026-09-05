import 'device_scan.dart';
import 'search_text.dart';

/// Докуда дошла разборка файла.
///
/// Три ступени поиска (имя → метаданные → текст) идут не подряд по одному
/// файлу, а слоями по всей библиотеке: имена есть у всех сразу, метаданные
/// подъезжают через секунды, текст — через минуту. Ступень записана у
/// файла, чтобы повторный запуск приложения продолжил с того места, где
/// его закрыли, а не начал заново.
enum IndexStage {
  /// Только то, что видно из имени и пути.
  name,

  /// Прочитаны `Title` / `Author` / `Subject` / `Keywords` из самого PDF.
  meta,

  /// Прочитан текст первых непустых страниц.
  text;

  /// Ступень выше этой или она сама, если выше некуда.
  IndexStage get next => switch (this) {
    IndexStage.name => IndexStage.meta,
    IndexStage.meta => IndexStage.text,
    IndexStage.text => IndexStage.text,
  };

  /// Дошла ли разборка хотя бы до [stage].
  bool reached(IndexStage stage) => index >= stage.index;
}

/// Файл устройства в том виде, в каком его помнит база.
///
/// Это не книга: книга появляется, только когда читатель поставил её на
/// полку. Здесь — список того, что нашлось на диске, со всем, что успели
/// про это узнать.
class DeviceFileRecord {
  /// Создаёт запись.
  const DeviceFileRecord({
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.seenAt,
    this.fingerprint,
    this.title,
    this.author,
    this.stage = IndexStage.name,
    this.hasTextLayer,
    this.missing = false,
  });

  /// Заводит запись по свежему результату обхода.
  factory DeviceFileRecord.found(ScannedFile file, {required DateTime seenAt}) {
    return DeviceFileRecord(
      path: file.path,
      size: file.size,
      modifiedAt: file.modifiedAt,
      seenAt: seenAt,
    );
  }

  /// Путь к файлу — он же ключ записи.
  final String path;

  /// Размер в байтах.
  final int size;

  /// Время последнего изменения файла.
  final DateTime modifiedAt;

  /// Когда файл последний раз попадался обходу.
  final DateTime seenAt;

  /// Отпечаток содержимого; `null` — ещё не считали.
  final String? fingerprint;

  /// Заголовок из метаданных PDF.
  final String? title;

  /// Автор из метаданных PDF.
  final String? author;

  /// Докуда дошла разборка.
  final IndexStage stage;

  /// Есть ли текстовый слой; `null` — ещё не смотрели.
  ///
  /// `false` — скан. Такая книга честно помечается «текст не распознан»:
  /// распознавать его мы не беремся (OCR — далеко за MVP), и делать вид,
  /// что поиск по ней работает, нельзя.
  final bool? hasTextLayer;

  /// Файла не было на месте при последнем обходе.
  ///
  /// Запись не удаляется: карту памяти вынимают и вставляют обратно, а
  /// вместе с записью пропали бы и отпечаток, и разобранные метаданные —
  /// то есть минуты работы ради файла, который никуда не девался.
  final bool missing;

  /// Имя файла с расширением.
  String get name {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// Имя папки, в которой лежит файл.
  String get folder {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    if (slash <= 0) {
      return '';
    }
    final String head = path.substring(0, slash);
    final int parent = head.lastIndexOf(RegExp(r'[\\/]'));
    return parent < 0 ? head : head.substring(parent + 1);
  }

  /// Копия с изменёнными полями.
  ///
  /// [fingerprint], [title], [author] и [hasTextLayer] обнуляются явно —
  /// через [reset]: разборку приходится сбрасывать каждый раз, когда файл
  /// изменился, и делать это «пропущенным аргументом» нельзя.
  DeviceFileRecord copyWith({
    int? size,
    DateTime? modifiedAt,
    DateTime? seenAt,
    String? fingerprint,
    String? title,
    String? author,
    IndexStage? stage,
    bool? hasTextLayer,
    bool? missing,
  }) {
    return DeviceFileRecord(
      path: path,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      seenAt: seenAt ?? this.seenAt,
      fingerprint: fingerprint ?? this.fingerprint,
      title: title ?? this.title,
      author: author ?? this.author,
      stage: stage ?? this.stage,
      hasTextLayer: hasTextLayer ?? this.hasTextLayer,
      missing: missing ?? this.missing,
    );
  }

  /// Та же запись с новыми размером и временем и сброшенной разборкой.
  DeviceFileRecord reset(ScannedFile file, {required DateTime seenAt}) {
    return DeviceFileRecord(
      path: path,
      size: file.size,
      modifiedAt: file.modifiedAt,
      seenAt: seenAt,
    );
  }

  @override
  String toString() => 'DeviceFileRecord($path, $stage)';
}

/// Что делать с файлом после обхода.
enum ScanVerdict {
  /// Файла раньше не было.
  added,

  /// Файл изменился: размер или время другие — всё разобранное недействительно.
  changed,

  /// Файл прежний: открывать его заново незачем.
  unchanged,

  /// Файла больше нет на месте.
  gone,
}

/// Одно решение по одному файлу.
class ScanDecision {
  /// Создаёт решение.
  const ScanDecision(this.verdict, this.record);

  /// Что случилось с файлом.
  final ScanVerdict verdict;

  /// Запись в том виде, в каком её надо записать в базу.
  final DeviceFileRecord record;

  @override
  String toString() => 'ScanDecision($verdict, ${record.path})';
}

/// Сверяет свежий обход с тем, что уже лежит в базе.
///
/// Здесь и живёт обещание «повторный обход открывает только
/// изменившееся». Признак изменения — размер **и** время правки: хеш
/// каждого файла при каждом обходе стоил бы чтения всей библиотеки, а
/// пара «размер + время» меняется у отредактированного файла всегда.
/// Ошибиться она может только в одну сторону — счесть изменённый файл
/// прежним, — и для этого файл должен сохранить и размер до байта, и
/// время до секунды.
List<ScanDecision> reconcileScan({
  required List<DeviceFileRecord> known,
  required List<ScannedFile> found,
  required DateTime seenAt,
}) {
  final Map<String, DeviceFileRecord> byPath = <String, DeviceFileRecord>{
    for (final DeviceFileRecord record in known) record.path: record,
  };
  final List<ScanDecision> decisions = <ScanDecision>[];
  final Set<String> visited = <String>{};

  for (final ScannedFile file in found) {
    visited.add(file.path);
    final DeviceFileRecord? previous = byPath[file.path];
    if (previous == null) {
      decisions.add(
        ScanDecision(
          ScanVerdict.added,
          DeviceFileRecord.found(file, seenAt: seenAt),
        ),
      );
      continue;
    }
    final bool same =
        previous.size == file.size &&
        previous.modifiedAt.isAtSameMomentAs(file.modifiedAt);
    if (same) {
      decisions.add(
        ScanDecision(
          ScanVerdict.unchanged,
          previous.copyWith(seenAt: seenAt, missing: false),
        ),
      );
    } else {
      decisions.add(
        ScanDecision(ScanVerdict.changed, previous.reset(file, seenAt: seenAt)),
      );
    }
  }

  for (final DeviceFileRecord record in known) {
    if (!visited.contains(record.path) && !record.missing) {
      decisions.add(
        ScanDecision(ScanVerdict.gone, record.copyWith(missing: true)),
      );
    }
  }
  return decisions;
}

/// Одна карточка на экране «Книги на устройстве».
///
/// Это не файл, а **книга**: один и тот же PDF лежит на телефоне в трёх
/// местах — в загрузках, в папке мессенджера и там, куда его положил
/// читатель, — и три одинаковые обложки подряд выглядят как ошибка
/// приложения, а не как правда о диске.
class DeviceBookEntry {
  /// Создаёт карточку.
  const DeviceBookEntry({
    required this.primary,
    this.duplicates = const <DeviceFileRecord>[],
  });

  /// Файл, который показывается и открывается.
  final DeviceFileRecord primary;

  /// Прочие копии того же файла — мелкой строкой под названием.
  final List<DeviceFileRecord> duplicates;

  /// Отпечаток книги, если он посчитан.
  String? get fingerprint => primary.fingerprint;

  /// Сколько всего копий на устройстве.
  int get copies => duplicates.length + 1;

  /// Название книги: из метаданных, иначе из имени файла.
  ///
  /// Имя файла — не запасной вариант, а равноправный: в метаданных PDF
  /// сплошь и рядом лежит «Microsoft Word - Document1», и показывать это
  /// вместо честного имени файла было бы издевательством. Поэтому
  /// заголовок из метаданных берётся, только если он не выглядит
  /// служебным.
  String get title {
    final String? meta = primary.title?.trim();
    if (meta != null && meta.isNotEmpty && !looksLikeJunkTitle(meta)) {
      return meta;
    }
    return primary.name;
  }

  /// Строка про остальные копии или пустая строка, если копия одна.
  String get duplicatesLabel {
    if (duplicates.isEmpty) {
      return '';
    }
    if (duplicates.length == 1) {
      return 'ещё в одном месте';
    }
    return 'ещё в ${duplicates.length} местах';
  }
}

/// Похож ли заголовок на служебный мусор из генератора PDF.
bool looksLikeJunkTitle(String title) {
  final String folded = foldSearchText(title.trim());
  if (folded.isEmpty) {
    return true;
  }
  const List<String> junk = <String>[
    'microsoft word',
    'microsoft powerpoint',
    'untitled',
    'document1',
    'no title',
    'print',
    'adobe acrobat',
  ];
  for (final String mark in junk) {
    if (folded.contains(foldSearchText(mark))) {
      return true;
    }
  }
  // Голое имя файла в заголовке ничего не добавляет, но и не мешает —
  // отсеивать его незачем: карточка всё равно покажет то же самое.
  return false;
}

/// Склеивает файлы в карточки по отпечатку.
///
/// Файлы без отпечатка (его ещё не посчитали) склеивать не по чему,
/// поэтому каждый из них остаётся сам по себе: показать читателю файл
/// сразу важнее, чем дождаться, пока станет ясно, что это дубликат.
/// Главным путём становится самый короткий: он почти всегда и есть тот,
/// куда книгу положил человек, — кэши и папки загрузок лежат глубже.
List<DeviceBookEntry> groupDeviceFiles(List<DeviceFileRecord> records) {
  final Map<String, List<DeviceFileRecord>> byHash =
      <String, List<DeviceFileRecord>>{};
  final List<DeviceBookEntry> single = <DeviceBookEntry>[];

  for (final DeviceFileRecord record in records) {
    if (record.missing) {
      continue;
    }
    final String? hash = record.fingerprint;
    if (hash == null || hash.isEmpty) {
      single.add(DeviceBookEntry(primary: record));
      continue;
    }
    byHash.putIfAbsent(hash, () => <DeviceFileRecord>[]).add(record);
  }

  final List<DeviceBookEntry> grouped = <DeviceBookEntry>[];
  for (final List<DeviceFileRecord> group in byHash.values) {
    final List<DeviceFileRecord> sorted = <DeviceFileRecord>[...group]
      ..sort(_byShortestPath);
    grouped.add(
      DeviceBookEntry(primary: sorted.first, duplicates: sorted.sublist(1)),
    );
  }

  return <DeviceBookEntry>[...grouped, ...single];
}

int _byShortestPath(DeviceFileRecord a, DeviceFileRecord b) {
  final int byLength = a.path.length.compareTo(b.path.length);
  return byLength != 0 ? byLength : a.path.compareTo(b.path);
}

/// Хранилище списка файлов устройства и индекса поиска.
///
/// Живёт **только на этом устройстве**: ни список файлов, ни индекс не
/// уезжают в облако. В appDataFolder читателя уходит то, что он создал
/// сам, — цитаты, заметки и расстановка полки, — а перечень содержимого
/// его диска не создавал никто.
abstract interface class DeviceFileRepository {
  /// Все известные файлы.
  Future<List<DeviceFileRecord>> files();

  /// Живой список файлов: обновляется по мере того, как идёт обход.
  Stream<List<DeviceFileRecord>> watchFiles();

  /// Записывает результаты обхода одной транзакцией.
  Future<void> applyScan(List<ScanDecision> decisions);

  /// Обновляет одну запись и её строку в индексе.
  Future<void> saveFile(DeviceFileRecord record, {String? body});

  /// Файлы, которым разборка нужнее всего: сначала не разобранные вовсе.
  Future<List<DeviceFileRecord>> pendingIndex({
    required IndexStage upTo,
    int limit = 32,
  });

  /// Ищет по индексу. Возвращает пути в порядке убывания веса.
  Future<List<String>> search(String query, {int limit = 200});

  /// Забывает всё: список файлов и индекс.
  ///
  /// Нужно ровно в одном случае — читатель отозвал разрешение. Держать
  /// перечень чужих файлов после того, как доступ к ним отобрали, было бы
  /// именно тем, чего мы обещали не делать.
  Future<void> forgetEverything();
}
