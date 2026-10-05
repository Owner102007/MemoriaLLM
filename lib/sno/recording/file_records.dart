import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'archive.dart';
import 'event.dart';
import 'file_store.dart';
import 'record_outlet.dart';
import 'records.dart';
import 'store.dart';

/// Записи на диске устройства (SNO-F-REC-07, SNO-F-REC-06,
/// SNO-F-REC-05).
///
/// Список читается из самой папки `Записи/`, а не из базы: архив,
/// убранный руками, пропадает из списка, положенный — появляется.
/// Сведения о записи берутся из манифеста архива; архив, который не
/// читается или не сходится со своими суммами, помечен и всё равно
/// отправляется — что с ним делать, решит разбор.
///
/// Отметки «отправлена» и «копия есть» лежат рядом, в
/// `Записи/.state.json`: это единственное, чего в самих архивах нет.
/// Файл потерялся — все записи снова «не отправлены»: ошибка в
/// безопасную сторону, запись не удалят одним нажатием.
///
/// Всё, что меняет папку, идёт по очереди ([_locked]): упаковка при
/// запуске и упаковка только что завершённой записи не встречаются на
/// одной папке.
///
/// **Папку незавершённой сессии записи не трогают**, где бы она ни
/// лежала: обычно она среди незавершённых, но завершение, оборванное
/// на полпути, могло перенести её к остальным, не сняв отметки о
/// сессии. Такой папки нет ни в списке, ни в упаковке, ни в удалении.
class FileDeviceRecords extends ChangeNotifier implements DeviceRecords {
  /// Создаёт записи; [root] отдаёт папку `Записи/`.
  ///
  /// [activeFolder] называет папку незавершённой сессии: её нельзя ни
  /// подбирать, ни упаковывать. [now] подменяется в тестах.
  FileDeviceRecords({
    required Future<Directory> Function() root,
    RecordOutlet outlet = const NoRecordOutlet(),
    String? Function()? activeFolder,
    DateTime Function()? now,
  }) : _root = root,
       _outlet = outlet,
       _activeFolder = activeFolder,
       _now = now ?? DateTime.now;

  /// Имя файла отметок в папке записей.
  static const String stateName = '.state.json';

  /// Версия файла отметок.
  static const String stateSchema = 'sno2026-records/1';

  final Future<Directory> Function() _root;
  final RecordOutlet _outlet;
  final String? Function()? _activeFolder;
  final DateTime Function() _now;

  List<DeviceRecord> _entries = const <DeviceRecord>[];
  bool _loaded = false;
  bool _disposed = false;

  /// Отметки по именам записей: `shared_at`, `copied_at`, `copied_to`.
  final Map<String, Map<String, Object?>> _marks =
      <String, Map<String, Object?>>{};

  /// Папка, куда копию сохраняли в прошлый раз.
  String? _copyDir;

  bool _stateRead = false;

  /// Что известно об архивах, уже проверенных в этом запуске: суммы
  /// сверяются один раз, пока файл не изменился.
  final Map<String, _Known> _checked = <String, _Known>{};

  Future<void> _queue = Future<void>.value();

  @override
  bool get shares => _outlet.shares;

  @override
  bool get saves => _outlet.saves;

  @override
  bool get loaded => _loaded;

  @override
  List<DeviceRecord> get entries => _entries;

  /// Выполняет [body], когда кончилось всё начатое раньше.
  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await body());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  Future<Directory> _records() async {
    final Directory root = await _root();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Читает отметки с диска — один раз за запуск.
  ///
  /// Файла нет или в нём мусор — отметок нет. Файл есть, но диск его
  /// не отдал — чтение повторится в следующий раз: иначе первая же
  /// новая отметка записалась бы поверх всех прежних.
  Future<void> _readState(Directory records) async {
    if (_stateRead) {
      return;
    }
    final File file = File(p.join(records.path, stateName));
    Map<String, Object?>? raw;
    try {
      if (await file.exists()) {
        final Object? decoded = jsonDecode(await file.readAsString());
        raw = decoded is Map<String, Object?> ? decoded : null;
      }
    } on FormatException {
      raw = null;
    } on FileSystemException {
      return;
    }
    _stateRead = true;
    final Object? marks = raw?['records'];
    if (marks is Map<String, Object?>) {
      for (final MapEntry<String, Object?> mark in marks.entries) {
        final Object? value = mark.value;
        if (value is Map<String, Object?>) {
          _marks[mark.key] = <String, Object?>{...value};
        }
      }
    }
    final Object? copyDir = raw?['copy_dir'];
    _copyDir = copyDir is String && copyDir.isNotEmpty ? copyDir : null;
  }

  /// Отметки записи [name]; заводятся, если их ещё нет.
  Map<String, Object?> _mark(String name) {
    return _marks.putIfAbsent(name, () => <String, Object?>{});
  }

  /// Пишет отметки через временный файл: оборванная запись не оставит
  /// под именем отметок половину JSON.
  Future<void> _writeState(Directory records) async {
    final String text = const JsonEncoder.withIndent('  ')
        .convert(<String, Object?>{
          'schema': stateSchema,
          'copy_dir': _copyDir,
          'records': _marks,
        });
    try {
      final File part = File(p.join(records.path, '$stateName$kPartSuffix'));
      await part.writeAsString(text, flush: true);
      await part.rename(p.join(records.path, stateName));
    } on FileSystemException {
      // Отметка не легла на диск: до перезапуска она помнится, после —
      // запись снова «не отправлена».
    }
  }

  /// Перечитывает папку записей.
  ///
  /// Папка не прочиталась — список остаётся прежним: экран записей не
  /// должен падать оттого, что диск не ответил.
  Future<void> _scan() async {
    try {
      await _read();
    } on FileSystemException {
      _loaded = true;
    }
  }

  Future<void> _read() async {
    final Directory records = await _records();
    await _readState(records);
    final List<DeviceRecord> found = <DeviceRecord>[];
    final Set<String> seen = <String>{};
    await for (final FileSystemEntity entity in records.list(
      followLinks: false,
    )) {
      final String base = p.basename(entity.path);
      if (base.startsWith('.')) {
        continue;
      }
      try {
        if (entity is Directory && base == _activeFolder?.call()) {
          // Папка незавершённой сессии: её покажут, когда сессию
          // завершат.
          continue;
        }
        if (entity is File && base.endsWith(kArchiveExtension)) {
          final String name = base.substring(
            0,
            base.length - kArchiveExtension.length,
          );
          final FileStat stat = await entity.stat();
          final ArchiveCheck check = await _check(entity, stat);
          seen.add(entity.path);
          found.add(
            recordFrom(
              name: name,
              bytes: stat.size,
              packed: true,
              info: check.manifest,
              damaged: !check.intact,
              state: _marks[name] ?? const <String, Object?>{},
            ),
          );
        } else if (entity is Directory) {
          found.add(
            recordFrom(
              name: base,
              bytes: await _sizeOf(entity),
              packed: false,
              // Отметок у папки нет: «отправлена» и «копия есть»
              // говорят об архиве, а архива у неё ещё нет.
              info: await readJsonFile(
                File(p.join(entity.path, kRecordingFile)),
              ),
            ),
          );
        }
      } on FileSystemException {
        // Файл пропал, пока папку читали: в списке его нет.
      }
    }
    _checked.removeWhere((String path, _Known known) => !seen.contains(path));
    _entries = List<DeviceRecord>.unmodifiable(orderRecords(found));
    _loaded = true;
  }

  Future<ArchiveCheck> _check(File archive, FileStat stat) async {
    final _Known? known = _checked[archive.path];
    if (known != null &&
        known.size == stat.size &&
        known.modified == stat.modified) {
      return known.check;
    }
    final ArchiveCheck check = await checkArchive(archive);
    _checked[archive.path] = _Known(stat.size, stat.modified, check);
    return check;
  }

  Future<int> _sizeOf(Directory folder) async {
    int total = 0;
    await for (final FileSystemEntity entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Нет ли в папке ни одного непустого файла.
  Future<bool> _isEmpty(Directory folder) async {
    return await _sizeOf(folder) == 0;
  }

  @override
  Future<void> refresh() {
    return _locked(_scan).whenComplete(_notify);
  }

  @override
  Future<void> adoptOrphans() {
    return _locked(() async {
      final Directory records = await _records();
      final Directory current = Directory(
        p.join(records.path, FileRecordingStore.currentName),
      );
      if (!await current.exists()) {
        return;
      }
      final String? active = _activeFolder?.call();
      final List<Directory> orphans = <Directory>[];
      await for (final FileSystemEntity entity in current.list(
        followLinks: false,
      )) {
        if (entity is Directory && p.basename(entity.path) != active) {
          orphans.add(entity);
        }
      }
      for (final Directory orphan in orphans) {
        try {
          if (await _isEmpty(orphan)) {
            // Запись, которая так и не началась: ни одного события.
            await orphan.delete(recursive: true);
            continue;
          }
          final String base = p.basename(orphan.path);
          String name = base;
          for (
            int number = 2;
            await Directory(p.join(records.path, name)).exists();
            number++
          ) {
            name = '$base-$number';
          }
          await orphan.rename(p.join(records.path, name));
        } on FileSystemException {
          // Не переехала: останется среди незавершённых до следующего
          // запуска.
        }
      }
    });
  }

  @override
  Future<void> packPending() async {
    // Что упаковывать, читается один раз; каждая папка упаковывается
    // под своим замком — между ними проходят список записей и упаковка
    // только что завершённой сессии, которым иначе пришлось бы ждать
    // всех папок прежних сборок.
    final List<Directory> folders = await _locked(_pendingFolders);
    try {
      for (final Directory folder in folders) {
        await _locked(() async {
          if (p.basename(folder.path) != _activeFolder?.call()) {
            await _packFolder(folder);
          }
        });
      }
      await _locked(_scan);
    } finally {
      _notify();
    }
  }

  /// Папки записей, которые ждут упаковки, от старых к новым; заодно
  /// убирает то, что осталось от оборванных упаковок.
  Future<List<Directory>> _pendingFolders() async {
    final Directory records = await _records();
    final List<Directory> folders = <Directory>[];
    await for (final FileSystemEntity entity in records.list(
      followLinks: false,
    )) {
      final String base = p.basename(entity.path);
      try {
        if (entity is Directory && base.startsWith(kGonePrefix)) {
          // Папка упакованной записи, которую не успели убрать: её
          // архив уже лежит и сверен.
          await entity.delete(recursive: true);
        } else if (base.startsWith('.')) {
          continue;
        } else if (entity is File &&
            base.endsWith('$kArchiveExtension$kPartSuffix')) {
          // Обрывок архива: упаковку оборвало закрытие приложения.
          await entity.delete();
        } else if (entity is Directory) {
          folders.add(entity);
        }
      } on FileSystemException {
        // Останется: следующая упаковка запишет поверх, следующий
        // запуск уберёт.
      }
    }
    // От старых к новым: имя кончается временем старта.
    folders.sort((Directory a, Directory b) => a.path.compareTo(b.path));
    return folders;
  }

  /// Упаковывает папку; отвечает именем записи в списке или `null`,
  /// если папка осталась папкой.
  Future<String?> _packFolder(Directory folder) async {
    try {
      if (await _isEmpty(folder)) {
        await folder.delete(recursive: true);
        return null;
      }
      final File archive = await packRecording(folder, now: _now);
      final String base = p.basename(archive.path);
      return base.substring(0, base.length - kArchiveExtension.length);
    } on PackException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<DeviceRecord?> pack(String folder) {
    // Имя папки — одно слово: пустое или с разделителем увело бы
    // упаковку в саму папку записей или мимо неё.
    if (folder.isEmpty ||
        folder.startsWith('.') ||
        folder.contains('/') ||
        folder.contains(r'\')) {
      return Future<DeviceRecord?>.value();
    }
    return _locked(() async {
      if (_activeFolder?.call() == folder) {
        return null;
      }
      final Directory records = await _records();
      final Directory done = Directory(p.join(records.path, folder));
      final Directory open = Directory(
        p.join(records.path, FileRecordingStore.currentName, folder),
      );
      // Завершение сессии не сумело перенести папку: она переезжает
      // сейчас.
      if (!await done.exists() && await open.exists()) {
        try {
          await open.rename(done.path);
        } on FileSystemException {
          // Останется среди незавершённых до следующего запуска.
        }
      }
      String name = folder;
      if (await done.exists()) {
        name = await _packFolder(done) ?? folder;
      }
      await _scan();
      for (final DeviceRecord record in _entries) {
        if (record.name == name) {
          return record;
        }
      }
      return null;
    }).whenComplete(_notify);
  }

  @override
  Future<int> share(List<DeviceRecord> records) async {
    final Directory folder = await _records();
    final List<DeviceRecord> ready = <DeviceRecord>[];
    final List<String> paths = <String>[];
    for (final DeviceRecord record in records) {
      final File archive = File(p.join(folder.path, record.fileName));
      if (record.packed && await archive.exists()) {
        ready.add(record);
        paths.add(archive.path);
      }
    }
    if (ready.length != records.length) {
      // Архив убрали с диска, пока список был на экране.
      await refresh();
    }
    if (paths.isEmpty || !await _outlet.share(paths)) {
      return 0;
    }
    // Помечается факт вызова окна: дошёл ли архив, система не говорит.
    final String at = isoWithOffset(_now());
    return _locked(() async {
      for (final DeviceRecord record in ready) {
        _mark(record.name)['shared_at'] = at;
      }
      await _writeState(folder);
      await _scan();
      return ready.length;
    }).whenComplete(_notify);
  }

  @override
  Future<CopyOutcome> saveCopy(DeviceRecord record) async {
    final Directory folder = await _records();
    await _locked(() => _readState(folder));
    final String? remembered = _copyDir;
    final String? initial =
        remembered != null && await Directory(remembered).exists()
        ? remembered
        : null;
    final String? chosen = await _outlet.pickFolder(initial: initial);
    if (chosen == null || chosen.isEmpty) {
      return CopyOutcome.cancelled;
    }
    if (p.equals(chosen, folder.path) || p.isWithin(folder.path, chosen)) {
      return CopyOutcome.inside;
    }
    return _locked(() async {
      final File source = File(p.join(folder.path, record.fileName));
      File? part;
      try {
        final String sum = await fileSha256(source);
        File target = File(p.join(chosen, record.fileName));
        bool there = false;
        for (int number = 2; await target.exists(); number++) {
          // Папка записей под другим именем — ярлыком, сетевым путём,
          // подставным диском: «копия» оказалась бы самим архивом.
          if (await FileSystemEntity.identical(target.path, source.path)) {
            return CopyOutcome.inside;
          }
          if (await fileSha256(target) == sum) {
            // Та же копия уже лежит здесь: второй рядом не нужно.
            there = true;
            break;
          }
          target = File(
            p.join(chosen, '${record.name} ($number)$kArchiveExtension'),
          );
        }
        if (!there) {
          final File copy = File('${target.path}$kPartSuffix');
          part = copy;
          await source.copy(copy.path);
          // Копия сверяется с архивом: флешка, которую выдернули
          // посреди записи, не должна считаться копией.
          if (await fileSha256(copy) != sum) {
            await copy.delete();
            return CopyOutcome.failed;
          }
          await copy.rename(target.path);
          part = null;
        }
        _mark(record.name)
          ..['copied_at'] = isoWithOffset(_now())
          ..['copied_to'] = target.path;
        _copyDir = chosen;
        await _writeState(folder);
        await _scan();
        return CopyOutcome.done;
      } on FileSystemException {
        try {
          await part?.delete();
        } on FileSystemException {
          // Обрывок копии остался в чужой папке: убрать его нечем.
        }
        return CopyOutcome.failed;
      }
    }).whenComplete(_notify);
  }

  @override
  Future<bool> reveal([DeviceRecord? record]) async {
    final Directory folder = await _records();
    if (record != null && record.packed) {
      final File archive = File(p.join(folder.path, record.fileName));
      if (await archive.exists()) {
        return _outlet.reveal(archive.path, file: true);
      }
    }
    return _outlet.reveal(folder.path, file: false);
  }

  @override
  Future<bool> delete(DeviceRecord record) {
    return _locked(() async {
      if (!record.packed && _activeFolder?.call() == record.name) {
        return false;
      }
      final Directory folder = await _records();
      try {
        if (record.packed) {
          final File archive = File(p.join(folder.path, record.fileName));
          if (await archive.exists()) {
            await archive.delete();
          }
        } else {
          final Directory streams = Directory(p.join(folder.path, record.name));
          if (await streams.exists()) {
            await streams.delete(recursive: true);
          }
        }
      } on FileSystemException {
        await _scan();
        return false;
      }
      // Отметки — об архиве: с папкой, которая носила то же имя, они
      // не уходят.
      if (record.packed && _marks.remove(record.name) != null) {
        await _writeState(folder);
      }
      await _scan();
      return true;
    }).whenComplete(_notify);
  }
}

/// Проверенный архив: каким он был, когда его сверяли.
class _Known {
  _Known(this.size, this.modified, this.check);

  final int size;
  final DateTime modified;
  final ArchiveCheck check;
}
