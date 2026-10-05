import 'dart:io';

import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/services.dart';

import 'records.dart';

/// Как запись уходит с устройства (SNO-F-REC-06, SNO-ALG-REC-04).
///
/// Сетевого кода у записей нет: приложение не знает адресов и не
/// хранит ключей. Архив уходит руками экспериментатора — системным
/// окном «Поделиться» на телефоне или копией в выбранную папку на ПК.
/// Здесь только то, что зависит от платформы; что помечать отправленным
/// и как сверять копию, решает `file_records.dart` под тестами.
abstract interface class RecordOutlet {
  /// Есть ли системное окно «Поделиться».
  bool get shares;

  /// Есть ли папки, куда сохраняют копию, и «Проводник».
  bool get saves;

  /// Отдаёт файлы [paths] системному окну «Поделиться» и ждёт, чем
  /// оно кончится (SNO-F-REC-14): выбрано ли в нём приложение. Дошёл
  /// ли файл до адресата, система не говорит.
  Future<ShareOutcome> share(List<String> paths);

  /// Есть ли у устройства общая папка, куда можно положить вторую
  /// копию архива без спроса (SNO-F-REC-13): «Загрузки» на Android 10
  /// и новее.
  Future<bool> canBackup();

  /// Кладёт копию файла [path] в папку [folder] общих «Загрузок» и
  /// сверяет её с суммой [sha256]. Отвечает, лежит ли там теперь
  /// сверенная копия — новая или положенная раньше; `null` — узнать
  /// не удалось: общая папка не ответила, и копию не подтвердили, но
  /// и не опровергли.
  Future<bool?> backup(
    String path, {
    required String sha256,
    required String folder,
  });

  /// Открывает папку [path]; [file] — это файл, и открыть надо папку,
  /// где он лежит, выделив его.
  Future<bool> reveal(String path, {required bool file});

  /// Спрашивает папку для копии; [initial] — с какой начать. `null` —
  /// папку не выбрали.
  Future<String?> pickFolder({String? initial});
}

/// Устройство, с которого запись никуда не отдать: тесты и платформы,
/// для которых выхода не написано.
class NoRecordOutlet implements RecordOutlet {
  /// Создаёт заглушку.
  const NoRecordOutlet();

  @override
  bool get shares => false;

  @override
  bool get saves => false;

  @override
  Future<ShareOutcome> share(List<String> paths) async {
    return ShareOutcome.failed;
  }

  @override
  Future<bool> canBackup() async => false;

  @override
  Future<bool?> backup(
    String path, {
    required String sha256,
    required String folder,
  }) async {
    return false;
  }

  @override
  Future<bool> reveal(String path, {required bool file}) async => false;

  @override
  Future<String?> pickFolder({String? initial}) async => null;
}

/// Чем кончилось окно «Поделиться» по слову канала.
///
/// Незнакомое слово — «система не сообщила»: запись останется
/// неотправленной.
ShareOutcome shareOutcomeOf(Object? told) {
  return switch (told) {
    'chosen' => ShareOutcome.chosen,
    'dismissed' => ShareOutcome.dismissed,
    'failed' || false || null => ShareOutcome.failed,
    _ => ShareOutcome.untold,
  };
}

/// Телефон: системное окно «Поделиться» и общая папка «Загрузки» через
/// канал `memoria/records` в `MainActivity`.
///
/// Своего плагина ради одного намерения не заводится — та же причина,
/// что у канала `memoria/device`. Договор канала: `share` со списком
/// путей `paths` → чем кончилось окно: `chosen` — в нём выбрано
/// приложение, `dismissed` — закрыто без выбора, `untold` — система не
/// сообщила, `failed` — не открылось (SNO-F-REC-14); `canBackup` → есть
/// ли общая папка; `backup` с `path`, `sha256` и `folder` → лежит ли в
/// ней сверенная копия, или `null`, если хранилище загрузок не
/// ответило (SNO-F-REC-13). Архивы отдаются окну ссылками
/// `content://` через поставщика файлов сборки ветви: чужое приложение
/// получает право прочитать только эти файлы.
class AndroidRecordOutlet implements RecordOutlet {
  /// Создаёт доступ к каналу.
  const AndroidRecordOutlet([
    this._channel = const MethodChannel('memoria/records'),
  ]);

  final MethodChannel _channel;

  @override
  bool get shares => true;

  @override
  bool get saves => false;

  @override
  Future<ShareOutcome> share(List<String> paths) async {
    if (paths.isEmpty) {
      return ShareOutcome.failed;
    }
    try {
      return shareOutcomeOf(
        await _channel.invokeMethod<Object?>('share', <String, Object?>{
          'paths': paths,
        }),
      );
    } on PlatformException {
      return ShareOutcome.failed;
    } on MissingPluginException {
      return ShareOutcome.failed;
    }
  }

  @override
  Future<bool> canBackup() async {
    try {
      return await _channel.invokeMethod<bool>('canBackup') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool?> backup(
    String path, {
    required String sha256,
    required String folder,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('backup', <String, Object?>{
        'path': path,
        'sha256': sha256,
        'folder': folder,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> reveal(String path, {required bool file}) async => false;

  @override
  Future<String?> pickFolder({String? initial}) async => null;
}

/// ПК: «Проводник» и системный диалог выбора папки.
///
/// Системного окна «Поделиться» на Windows нет намеренно
/// (SNO-ALG-REC-04): из Flutter оно ненадёжно, а архив на компьютере
/// экспериментатора и так под рукой — его сохраняют на флешку, в
/// сетевую папку или в «Загрузки».
class WindowsRecordOutlet implements RecordOutlet {
  /// Создаёт выход.
  const WindowsRecordOutlet();

  @override
  bool get shares => false;

  @override
  bool get saves => true;

  @override
  Future<ShareOutcome> share(List<String> paths) async {
    return ShareOutcome.failed;
  }

  // На ПК второй копии сама сборка не кладёт (SNO-F-REC-13): папка
  // записей в данных приложения переживает и обновление, и удаление
  // портативной сборки, а копию ставит «Сохранить архив как…».
  @override
  Future<bool> canBackup() async => false;

  @override
  Future<bool?> backup(
    String path, {
    required String sha256,
    required String folder,
  }) async {
    return false;
  }

  @override
  Future<bool> reveal(String path, {required bool file}) async {
    try {
      // «Проводник» отвечает кодом 1 и тогда, когда открылся: ждать его
      // и читать ответ незачем.
      await Process.start(
        'explorer.exe',
        file ? <String>['/select,', path] : <String>[path],
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<String?> pickFolder({String? initial}) async {
    try {
      return await getDirectoryPath(
        initialDirectory: initial,
        confirmButtonText: 'Сохранить сюда',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Выход записей для платформы, на которой запущено приложение.
RecordOutlet platformRecordOutlet() {
  if (Platform.isAndroid) {
    return const AndroidRecordOutlet();
  }
  if (Platform.isWindows) {
    return const WindowsRecordOutlet();
  }
  return const NoRecordOutlet();
}
