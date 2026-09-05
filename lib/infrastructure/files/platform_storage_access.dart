import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/library/storage_access.dart';

/// Доступ ко всем файлам на Android — через канал в `MainActivity`.
///
/// Своего плагина ради этого не заводится по той же причине, что и для
/// закреплённых ссылок в S5.1: работы тут на три вызова системного API, а
/// плагин — это отдельный пакет со своей сборкой и своей жизнью.
class AndroidStorageAccess implements StorageAccess {
  /// Создаёт доступ.
  const AndroidStorageAccess([
    this._channel = const MethodChannel('memoria/storage_access'),
  ]);

  final MethodChannel _channel;

  @override
  Future<StorageAccessState> state() async {
    try {
      final bool granted =
          await _channel.invokeMethod<bool>('granted') ?? false;
      return granted ? StorageAccessState.granted : StorageAccessState.denied;
    } on PlatformException {
      return StorageAccessState.denied;
    } on MissingPluginException {
      // Канала нет — значит, мы не на Android. Спрашивать нечего.
      return StorageAccessState.notRequired;
    }
  }

  @override
  Future<void> request() async {
    try {
      await _channel.invokeMethod<bool>('request');
    } on PlatformException {
      // Системный экран не открылся. Читатель об этом узнает: состояние
      // при возвращении в приложение останется прежним.
    } on MissingPluginException {
      // Не Android.
    }
  }

  @override
  Future<List<String>> roots() async {
    try {
      final List<Object?>? roots = await _channel.invokeMethod<List<Object?>>(
        'roots',
      );
      return <String>[
        for (final Object? root in roots ?? const <Object?>[])
          if (root is String && root.isNotEmpty) root,
      ];
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }
}

/// Доступ к файлам на настольной системе.
///
/// Разрешения там нет вовсе: приложение и так читает файлы пользователя.
/// Обход начинается с домашней папки, а не с корня диска: книги лежат у
/// человека, а не в системных каталогах, и обходить `C:\Windows` значит
/// потратить минуты на заведомо пустое место.
class DesktopStorageAccess implements StorageAccess {
  /// Создаёт доступ.
  const DesktopStorageAccess();

  @override
  Future<StorageAccessState> state() async => StorageAccessState.notRequired;

  @override
  Future<void> request() async {
    // Спрашивать нечего.
  }

  @override
  Future<List<String>> roots() async {
    final Map<String, String> env = Platform.environment;
    final String? home = env['USERPROFILE'] ?? env['HOME'];
    if (home == null || home.isEmpty) {
      return const <String>[];
    }
    return <String>[home];
  }
}

/// Доступ к файлам для этой платформы.
StorageAccess platformStorageAccess() => Platform.isAndroid
    ? const AndroidStorageAccess()
    : const DesktopStorageAccess();
