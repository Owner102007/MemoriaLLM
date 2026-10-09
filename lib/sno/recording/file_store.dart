import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'store.dart';

/// Записи сессий на диске (SNO-F-REC-01).
///
/// Папка `Записи/` лежит в папке данных приложения. Незавершённая
/// запись — в `Записи/.current/<имя>/`: по этой папке после сбоя
/// видно, что запись оборвалась. Завершённая переезжает в
/// `Записи/<имя>/`, и её упаковывают в архив `Записи/<имя>.zip`
/// (SNO-F-REC-05, `file_records.dart`).
class FileRecordingStore implements RecordingStore {
  /// Создаёт хранилище; [root] отдаёт папку `Записи/`.
  FileRecordingStore(this._root);

  /// Имя папки записей в папке данных приложения.
  static const String folderName = 'Записи';

  /// Имя папки незавершённых записей.
  static const String currentName = '.current';

  final Future<Directory> Function() _root;

  Future<Directory> _records() async {
    final Directory root = await _root();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Directory _current(Directory records) {
    return Directory(p.join(records.path, currentName));
  }

  /// Папка записи [folder]: среди незавершённых, а нет её там — среди
  /// завершённых.
  Future<Directory> _folder(String folder) async {
    final Directory records = await _records();
    final Directory open = Directory(p.join(_current(records).path, folder));
    if (await open.exists()) {
      return open;
    }
    return Directory(p.join(records.path, folder));
  }

  @override
  Future<String> location() async => (await _records()).path;

  @override
  Future<String> create(String wanted) async {
    final Directory records = await _records();
    final Directory current = _current(records);
    String name = wanted;
    int number = 1;
    // Две записи в одну минуту получили бы одно имя: вторая — с хвостом.
    // Занято имя и тогда, когда первая уже упакована в архив
    // (SNO-F-REC-05): архив называется так же, как папка.
    while (await Directory(p.join(current.path, name)).exists() ||
        await Directory(p.join(records.path, name)).exists() ||
        await File(p.join(records.path, '$name.zip')).exists()) {
      number++;
      name = '$wanted-$number';
    }
    await Directory(p.join(current.path, name)).create(recursive: true);
    return name;
  }

  @override
  Future<JournalFile> openJournal(
    String folder, {
    String name = kEventsFile,
  }) async {
    final Directory directory = await _folder(folder);
    final RandomAccessFile file = await File(p.join(directory.path, name))
        .open(mode: FileMode.writeOnlyAppend);
    return _DiskJournal(file);
  }

  @override
  Future<void> put(String folder, String name, String content) async {
    final Directory directory = await _folder(folder);
    // Через временный файл: оборванная запись не оставит под именем
    // сведений половину JSON.
    // Имя может называть подпапку (`clt/…`, SNO-F-CLT-03): она
    // заводится здесь же.
    final String path = p.joinAll(<String>[directory.path, ...name.split('/')]);
    final Directory parent = Directory(p.dirname(path));
    if (name.contains('/') && !await parent.exists()) {
      // Заводится только подпапка и только в записи, которая есть:
      // папку самой записи файл завести не вправе — запись уже могли
      // упаковать и убрать.
      if (!await directory.exists()) {
        throw FileSystemException('папки записи нет', directory.path);
      }
      await parent.create(recursive: true);
    }
    final File part = File('$path.part');
    await part.writeAsString(content, flush: true);
    await part.rename(path);
  }

  @override
  Future<Map<String, String>> texts(String folder, String subfolder) async {
    final Directory directory = Directory(
      p.join((await _folder(folder)).path, subfolder),
    );
    if (!await directory.exists()) {
      return const <String, String>{};
    }
    final Map<String, String> found = <String, String>{};
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      if (entity is! File || entity.path.endsWith('.part')) {
        continue;
      }
      try {
        found['$subfolder/${p.basename(entity.path)}'] = await entity
            .readAsString();
      } on FileSystemException {
        // Файл не прочитался: для записи его нет.
      } on FormatException {
        // Не текст: для записи его нет.
      }
    }
    return found;
  }

  @override
  Future<bool> has(String folder, String name) async {
    final Directory directory = await _folder(folder);
    return File(p.joinAll(<String>[directory.path, ...name.split('/')]))
        .exists();
  }

  @override
  Future<List<String>> lastLines(
    String folder, {
    int count = kTailLines,
  }) async {
    final Directory directory = await _folder(folder);
    final File file = File(p.join(directory.path, kEventsFile));
    if (!await file.exists()) {
      return const <String>[];
    }
    final List<int> bytes = await file.readAsBytes();
    const int newline = 0x0A;
    final int end = bytes.lastIndexOf(newline);
    if (end < 0) {
      // Ни одной целой строки: всё записанное — обрывок.
      if (bytes.isNotEmpty) {
        await _truncate(file, 0);
      }
      return const <String>[];
    }
    if (end != bytes.length - 1) {
      await _truncate(file, end + 1);
    }
    // Битый UTF-8 читается с заменой знаков: такую строку отвергнет
    // разбор JSON, а не чтение файла.
    final List<String> lines = <String>[
      for (final String line in const LineSplitter().convert(
        utf8.decode(bytes.sublist(0, end), allowMalformed: true),
      ))
        if (line.isNotEmpty) line,
    ];
    return lines.length > count ? lines.sublist(lines.length - count) : lines;
  }

  @override
  Future<List<int>?> journalBytes(
    String folder, {
    String name = kEventsFile,
  }) async {
    final Directory directory = await _folder(folder);
    final File file = File(p.join(directory.path, name));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> discard(String folder) async {
    final Directory records = await _records();
    final Directory open = Directory(p.join(_current(records).path, folder));
    if (await open.exists()) {
      await open.delete(recursive: true);
    }
  }

  Future<void> _truncate(File file, int length) async {
    final RandomAccessFile opened = await file.open(mode: FileMode.append);
    try {
      await opened.truncate(length);
      await opened.flush();
    } finally {
      await opened.close();
    }
  }

  @override
  Future<String> pathOf(String folder, String sub) async {
    return p.joinAll(<String>[(await _folder(folder)).path, ...sub.split('/')]);
  }

  @override
  Future<void> removeSub(String folder, String sub) async {
    final Directory target = Directory(await pathOf(folder, sub));
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
  }

  @override
  Future<void> finish(String folder) async {
    final Directory records = await _records();
    final Directory open = Directory(p.join(_current(records).path, folder));
    if (!await open.exists()) {
      return;
    }
    await open.rename(p.join(records.path, folder));
  }
}

/// Журнал на диске: дозапись и сброс.
class _DiskJournal implements JournalFile {
  _DiskJournal(this._file);

  final RandomAccessFile _file;

  @override
  Future<void> append(String text) async {
    await _file.writeString(text);
    await _file.flush();
  }

  @override
  Future<void> close() => _file.close();
}
