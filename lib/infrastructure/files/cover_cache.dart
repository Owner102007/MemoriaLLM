import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../domain/library/cover.dart';

/// Обложки в отдельной папке приложения.
///
/// Это именно кэш: каждый файл здесь можно удалить, и приложение всего
/// лишь нарисует обложку заново. Поэтому папка отдельная — её видно в
/// настройках Android как «кэш», её можно очистить кнопкой, и потеря
/// содержимого ничего не значит.
class FileCoverStore implements CoverStore {
  /// Создаёт хранилище.
  ///
  /// [directory] задаётся в тестах: `path_provider` — плагин, и в
  /// `flutter test` его нет вовсе.
  FileCoverStore({Directory? directory}) : _fixed = directory;

  final Directory? _fixed;
  Future<Directory>? _resolved;

  @override
  Future<String?> read(String key) async {
    final File file = File(await _pathFor(key));
    if (await file.exists()) {
      // Пустой файл остаётся от прерванной записи: показывать его нельзя,
      // а вот перерисовать обложку — можно и нужно.
      if (await file.length() > 0) {
        return file.path;
      }
      await _quietly(file.delete);
    }
    return null;
  }

  @override
  Future<String> write(String key, Uint8List png) async {
    final String path = await _pathFor(key);
    // Пишем во временный файл и переименовываем: приложение закрыли
    // посреди записи — на полке останется книга без обложки, а не книга
    // с половиной картинки.
    final File temp = File('$path.part');
    await temp.writeAsBytes(png, flush: true);
    await temp.rename(path);
    return path;
  }

  @override
  Future<void> remove(String key) async {
    await _quietly(File(await _pathFor(key)).delete);
  }

  @override
  Future<int> clear() async {
    final Directory dir = await _directory();
    if (!await dir.exists()) {
      return 0;
    }
    int removed = 0;
    await for (final FileSystemEntity entry in dir.list()) {
      if (entry is File) {
        await _quietly(entry.delete);
        removed++;
      }
    }
    return removed;
  }

  Future<String> _pathFor(String key) async {
    final Directory dir = await _directory();
    return '${dir.path}${Platform.pathSeparator}$key.png';
  }

  Future<Directory> _directory() {
    return _resolved ??= _createDirectory();
  }

  Future<Directory> _createDirectory() async {
    final Directory base = _fixed ?? await _appCoverDirectory();
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }

  static Future<Directory> _appCoverDirectory() async {
    final Directory support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}covers');
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on FileSystemException {
      // Файла уже нет или он занят: для кэша обложек это не событие.
    }
  }
}
