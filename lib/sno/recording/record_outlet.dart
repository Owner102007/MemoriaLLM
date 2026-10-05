import 'dart:io';

import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/services.dart';

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

  /// Отдаёт файлы [paths] системному окну «Поделиться». Отвечает,
  /// открылось ли окно: дошёл ли файл до адресата, система не говорит.
  Future<bool> share(List<String> paths);

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
  Future<bool> share(List<String> paths) async => false;

  @override
  Future<bool> reveal(String path, {required bool file}) async => false;

  @override
  Future<String?> pickFolder({String? initial}) async => null;
}

/// Телефон: системное окно «Поделиться» через канал `memoria/records`
/// в `MainActivity`.
///
/// Своего плагина ради одного намерения не заводится — та же причина,
/// что у канала `memoria/device`. Договор канала: `share` со списком
/// путей `paths` → открылось ли окно. Архивы отдаются ссылками
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
  Future<bool> share(List<String> paths) async {
    if (paths.isEmpty) {
      return false;
    }
    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'share',
        <String, Object?>{'paths': paths},
      );
      return opened ?? false;
    } on PlatformException {
      return false;
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
  Future<bool> share(List<String> paths) async => false;

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
