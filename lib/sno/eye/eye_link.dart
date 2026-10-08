/// Связь приложения со спутником взгляда (SNO-ALG-EYE-03, SNO-F-EYE-04).
///
/// Одна связь — один запущенный спутник: команды строками в stdin,
/// ответы строками из stdout. Спутник исполняет команды по одной и по
/// порядку, поэтому ответ на команду — первый ответ с её именем
/// (`reply`) или ошибка с её именем (`cmd`). Сердцебиение и ход
/// самопроверки приходят сами, без команды.
///
/// Связь не перезапускает спутник и не судит о его молчании — это дело
/// того, кто ею пользуется (`eye_tracker.dart`): здесь только обмен.
library;

import 'dart:async';

import 'eye_process.dart';
import 'eye_protocol.dart';
import 'eye_timing.dart';
import 'qpc_clock.dart';

/// Сколько ждать ответа на `hello`: спутник при первом слове грузит
/// MediaPipe и модель лица, а на слабом ПК в первый раз это долго.
const Duration kHelloTimeout = Duration(seconds: 40);

/// Сколько ждать ответа на обычную команду.
const Duration kReplyTimeout = Duration(seconds: 10);

/// Сколько ждать итога самопроверки: прогрев и замер, а если 1080p не
/// держит частоту — ещё раз в 720p.
const Duration kSelfcheckTimeout = Duration(seconds: 60);

/// Сколько ждать выхода спутника после закрытия stdin, прежде чем снять
/// его: сам он обязан уйти за две секунды.
const Duration kExitGrace = Duration(milliseconds: 2500);

class _Waiting {
  _Waiting(this.done);

  final Completer<Map<String, Object?>> done;
}

/// Связь с запущенным спутником.
class EyeLink {
  EyeLink._(this._process, this._qpc) {
    _lines = _process.lines.listen(
      _onLine,
      onError: (Object _) {},
      onDone: _onClosed,
    );
    unawaited(
      _process.exitCode.then(_onExit, onError: (Object _) => _onExit(-1)),
    );
  }

  /// Запускает спутник через [launch]. Не запустился — [EyeError].
  static Future<EyeLink> start(
    EyeLauncher launch, {
    required QpcClock qpc,
  }) async {
    return EyeLink._(await launch(), qpc);
  }

  final EyeProcess _process;
  final QpcClock _qpc;
  late final StreamSubscription<String> _lines;
  final Map<String, List<_Waiting>> _waiting = <String, List<_Waiting>>{};
  final Completer<int> _exited = Completer<int>();
  bool _closing = false;

  /// Сколько строк мусора пришло подряд.
  int garbageInRow = 0;

  /// Сердцебиение спутника.
  void Function(EyeHeartbeat beat)? onHeartbeat;

  /// Ход самопроверки и кадры камеры (`{progress: …}`).
  void Function(Map<String, Object?> message)? onProgress;

  /// Ошибка не о команде: например, о записи (`cmd: record`).
  void Function(EyeError error)? onError;

  /// Пришла строка мусора; число — сколько их подряд.
  void Function(int inRow)? onGarbage;

  /// Код выхода спутника, когда он вышел.
  Future<int> get exitCode => _exited.future;

  /// Вышел ли спутник.
  bool get exited => _exited.isCompleted;

  /// Закрывается ли связь по слову приложения: выход спутника тогда —
  /// не сбой.
  bool get closing => _closing;

  void _onLine(String line) {
    // Миг прихода — до разбора: по нему считается время ответа `sync`.
    final int arrivedUs = _qpc.nowUs();
    final Map<String, Object?>? message = decodeEyeLine(line);
    if (message == null) {
      if (line.trim().isEmpty) {
        return;
      }
      garbageInRow++;
      onGarbage?.call(garbageInRow);
      return;
    }
    garbageInRow = 0;
    final String? reply = replyOf(message);
    if (reply != null) {
      _complete(reply, <String, Object?>{
        ...message,
        if (reply == 'sync') '_arrived_us': arrivedUs,
      });
      return;
    }
    if (message.containsKey('error')) {
      final EyeError error = EyeError.fromMessage(message);
      final String? command = error.command;
      if (command != null && _fail(command, error)) {
        return;
      }
      if (error.code == 'already_running') {
        // Второй экземпляр отказался и выходит: ждать от него нечего.
        _failAll(error);
        return;
      }
      onError?.call(error);
      return;
    }
    final EyeHeartbeat? beat = EyeHeartbeat.fromMessage(message);
    if (beat != null) {
      onHeartbeat?.call(beat);
      return;
    }
    if (message.containsKey('progress')) {
      onProgress?.call(message);
    }
  }

  bool _complete(String name, Map<String, Object?> message) {
    final List<_Waiting>? queue = _waiting[name];
    if (queue == null || queue.isEmpty) {
      return false;
    }
    queue.removeAt(0).done.complete(message);
    return true;
  }

  bool _fail(String name, EyeError error) {
    final List<_Waiting>? queue = _waiting[name];
    if (queue == null || queue.isEmpty) {
      return false;
    }
    queue.removeAt(0).done.completeError(error);
    return true;
  }

  void _failAll(EyeError error) {
    final List<_Waiting> all = <_Waiting>[
      for (final List<_Waiting> queue in _waiting.values) ...queue,
    ];
    _waiting.clear();
    for (final _Waiting waiting in all) {
      waiting.done.completeError(error);
    }
  }

  void _onClosed() {
    // stdout кончился: дальше ответов не будет.
    _failAll(const EyeError('exit', 'спутник закрыл вывод'));
  }

  void _onExit(int code) {
    if (!_exited.isCompleted) {
      _exited.complete(code);
    }
    _failAll(EyeError('exit', 'спутник вышел с кодом $code'));
  }

  /// Отправляет команду и ждёт ответа на неё.
  ///
  /// Не дождались за [timeout] — [EyeError] `timeout`, и связь считать
  /// живой нельзя: запоздавший ответ достался бы следующей команде.
  /// Поэтому после такого отказа связь закрывают.
  Future<Map<String, Object?>> request(
    String name, {
    Map<String, Object?>? fields,
    Duration timeout = kReplyTimeout,
  }) {
    if (exited) {
      return Future<Map<String, Object?>>.error(
        const EyeError('exit', 'спутник уже вышел'),
      );
    }
    final _Waiting waiting = _Waiting(Completer<Map<String, Object?>>());
    (_waiting[name] ??= <_Waiting>[]).add(waiting);
    _process.write(encodeEyeCommand(name, fields));
    return waiting.done.future.timeout(
      timeout,
      onTimeout: () {
        _waiting[name]?.remove(waiting);
        throw EyeError('timeout', 'нет ответа на «$name»', command: name);
      },
    );
  }

  /// `hello`: кто на том конце. Чужая версия обмена — [EyeError]
  /// `version`.
  Future<EyeHello> hello({String build = '', String branch = ''}) async {
    final Map<String, Object?> reply = await request(
      'hello',
      fields: <String, Object?>{'build': build, 'branch': branch},
      timeout: kHelloTimeout,
    );
    return EyeHello.fromMessage(reply);
  }

  /// Камеры системы.
  Future<List<EyeCamera>> cameras() async {
    return camerasOf(await request('cameras'));
  }

  /// Самопроверка места на камере [camera]. [seconds] — длина замера;
  /// [dir] — папка, по которой меряется место на диске; [preview] —
  /// присылать ли маленькие кадры камеры ([onProgress]).
  Future<EyeCheck> selfcheck({
    required EyeCamera? camera,
    double? seconds,
    double? warmup,
    String? dir,
    bool preview = false,
  }) async {
    final Map<String, Object?> reply = await request(
      'selfcheck',
      fields: <String, Object?>{
        if (camera != null) 'camera': camera.toJson(),
        if (seconds != null) 'seconds': seconds,
        if (warmup != null) 'warmup': warmup,
        if (dir != null) 'dir': dir,
        if (preview) 'preview': true,
      },
      timeout: kSelfcheckTimeout,
    );
    return EyeCheck.fromMessage(reply);
  }

  /// Рукопожатие `sync`: [rounds] обменов по одному, итог — по обмену с
  /// наименьшим временем ответа (SNO-ALG-EYE-03, шаг 7).
  Future<SyncResult?> sync(int rounds) async {
    final List<SyncRound> done = <SyncRound>[];
    for (int i = 0; i < rounds; i++) {
      final int sent = _qpc.nowUs();
      final Map<String, Object?> reply = await request(
        'sync',
        fields: <String, Object?>{'app_qpc_us': sent},
      );
      final Object? echo = reply['app_qpc_us'];
      final Object? eye = reply['eye_qpc_us'];
      final Object? arrived = reply['_arrived_us'];
      if (echo != sent || eye is! int || arrived is! int) {
        // Ответ не на этот обмен: в счёт не идёт.
        continue;
      }
      done.add(SyncRound(sentUs: sent, eyeUs: eye, receivedUs: arrived));
    }
    return SyncResult.best(done);
  }

  /// Закрывает связь: stdin закрыт, спутник дописывает файлы и выходит;
  /// не вышел за [kExitGrace] — снят.
  Future<void> close() async {
    _closing = true;
    if (!exited) {
      await _process.closeInput();
      try {
        await exitCode.timeout(kExitGrace);
      } on TimeoutException {
        _process.kill();
      }
    }
    await _lines.cancel();
  }

  /// Снимает спутник сразу: он молчит или шлёт мусор.
  Future<void> kill() async {
    _closing = true;
    _process.kill();
    try {
      await exitCode.timeout(kExitGrace);
    } on TimeoutException {
      // Процесс не отозвался и на снятие — дальше его не ждём.
    }
    await _lines.cancel();
  }
}
