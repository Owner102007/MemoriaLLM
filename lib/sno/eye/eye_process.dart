/// Процесс спутника взгляда (SNO-F-EYE-04, SNO-ALG-EYE-03, шаг 1).
///
/// Приложение запускает `eye\python.exe -I -m sno_eye serve` из папки
/// `eye/` рядом с `memoria.exe` и говорит с ним строками через stdin и
/// stdout. Окна консоли при этом нет: `Process.start` запускает
/// дочерний процесс с `CREATE_NO_WINDOW`, когда у приложения своей
/// консоли нет. stderr спутника — его журнал: приложение складывает его
/// в файл, иначе канал переполнился бы, и спутник встал бы на записи
/// в stderr.
///
/// Договор [EyeProcess] позволяет проверять связь на подставном
/// процессе, без Python.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'eye_protocol.dart';

/// Запущенный спутник.
abstract interface class EyeProcess {
  /// Строки stdout спутника; поток один на процесс.
  Stream<String> get lines;

  /// Пишет строку в stdin спутника. Спутник уже вышел — строка
  /// теряется молча: о выходе скажет [exitCode].
  void write(String line);

  /// Закрывает stdin: спутник дописывает файлы и выходит за ≤ 2 с.
  Future<void> closeInput();

  /// Код выхода, когда процесс завершится.
  Future<int> get exitCode;

  /// Снимает процесс.
  void kill();
}

/// Заводит спутник; не завёлся — [EyeError] `no_satellite` или `start`.
typedef EyeLauncher = Future<EyeProcess> Function();

/// Папка `eye/` рядом с приложением.
Directory eyeFolderNextToApp() {
  return Directory(
    p.join(File(Platform.resolvedExecutable).parent.path, 'eye'),
  );
}

/// Сколько журнала спутника держится в файле: больше — прежний файл
/// уходит в `.old`, и журнал начинается заново.
const int kEyeLogLimit = 2 * 1024 * 1024;

/// Запуск настоящего спутника из папки [eye]. stderr уходит в файл
/// [log]: он дописывается, а перевалив за [kEyeLogLimit], начинается
/// заново. [extra] — добавочные ключи командной строки (тесты:
/// `--source synthetic`).
EyeLauncher satelliteLauncher(
  Directory eye, {
  Future<File?> Function()? log,
  List<String> extra = const <String>[],
}) {
  return () async {
    final String python = p.join(eye.path, 'python.exe');
    if (!File(python).existsSync()) {
      throw EyeError(
        'no_satellite',
        'нет ${p.join('eye', 'python.exe')} рядом с приложением',
      );
    }
    final Process process;
    try {
      process = await Process.start(
        python,
        <String>['-I', '-m', 'sno_eye', 'serve', ...extra],
        workingDirectory: eye.path,
        environment: <String, String>{
          'MPLBACKEND': 'Agg',
          'PYTHONIOENCODING': 'utf-8',
        },
      );
    } on ProcessException catch (e) {
      throw EyeError('start', e.message);
    }
    File? file;
    try {
      file = await log?.call();
    } on Object {
      file = null;
    }
    return _SatelliteProcess(process, await _openLog(file));
  };
}

Future<IOSink?> _openLog(File? log) async {
  if (log == null) {
    return null;
  }
  try {
    await log.parent.create(recursive: true);
    if (await log.exists() && await log.length() > kEyeLogLimit) {
      await log.rename('${log.path}.old');
    }
    return log.openWrite(mode: FileMode.append, encoding: utf8);
  } on Object {
    return null;
  }
}

class _SatelliteProcess implements EyeProcess {
  _SatelliteProcess(this._process, IOSink? log) {
    _process.stdin.encoding = utf8;
    // Запись в stdin вышедшего спутника кончается ошибкой «канал
    // закрыт» в будущем `done`: о выходе скажет код выхода, а не она.
    unawaited(_process.stdin.done.then((Object? _) {}, onError: (Object _) {}));
    _lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    _logging = _process.stderr
        .transform(utf8.decoder)
        .listen(
          (String text) {
            log?.write(text);
          },
          onDone: () {
            unawaited(_closeLog(log));
          },
          onError: (Object _) {},
          cancelOnError: false,
        );
  }

  final Process _process;
  late final Stream<String> _lines;
  // Подписка на stderr живёт столько же, сколько процесс: поток
  // кончается с выходом спутника, и подписка — вместе с ним.
  late final StreamSubscription<String> _logging;
  bool _inputClosed = false;

  static Future<void> _closeLog(IOSink? log) async {
    try {
      await log?.close();
    } on Object {
      // Журнал спутника не закрылся — терять из-за этого нечего.
    }
  }

  @override
  Stream<String> get lines => _lines;

  @override
  void write(String line) {
    if (_inputClosed) {
      return;
    }
    try {
      _process.stdin.add(utf8.encode('$line\n'));
    } on Object {
      // Спутник вышел: о выходе скажет код выхода.
    }
  }

  @override
  Future<void> closeInput() async {
    if (_inputClosed) {
      return;
    }
    _inputClosed = true;
    try {
      await _process.stdin.close();
    } on Object {
      // Канал уже закрыт: спутник вышел сам.
    }
  }

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() {
    _process.kill();
    unawaited(_logging.cancel().then((Object? _) {}, onError: (Object _) {}));
  }
}

/// Открывает страницу параметров Windows «Камера» — там классическим
/// приложениям разрешают доступ к камере (SNO-F-EYE-05).
Future<bool> openCameraSettings() async {
  try {
    await Process.start('explorer.exe', <String>['ms-settings:privacy-webcam']);
    return true;
  } on Object {
    return false;
  }
}
