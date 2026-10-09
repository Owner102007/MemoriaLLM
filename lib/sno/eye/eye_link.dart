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

/// Сколько ждать открытия камеры (`open`): модель, камера, файлы.
const Duration kOpenTimeout = Duration(seconds: 30);

/// Сколько ждать модели (`fit`): подбор двух моделей перекрёстной
/// проверкой на слабом ПК — секунды, с запасом.
const Duration kFitTimeout = Duration(seconds: 60);

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

  /// Живая точка взгляда — по строке на кадр, пока включена (`live`).
  void Function(EyeGaze gaze)? onGaze;

  /// Где голова — по строке на кадр, пока на экране точка фазы движения
  /// головы (BUG-61).
  void Function(EyeHeadPose pose)? onHead;

  /// Лица нет дольше секунды или оно вернулось — пока идёт поток взгляда
  /// записи (SNO-F-EYE-02).
  void Function(EyeFace face)? onFace;

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
    final EyeFace? face = EyeFace.fromMessage(message);
    if (face != null) {
      onFace?.call(face);
      return;
    }
    final EyeHeadPose? head = EyeHeadPose.fromMessage(message);
    if (head != null) {
      onHead?.call(head);
      return;
    }
    final EyeGaze? gaze = EyeGaze.fromMessage(message);
    if (gaze != null) {
      onGaze?.call(gaze);
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

  /// Открывает камеру (SNO-ALG-EYE-02, SNO-ALG-EYE-03): [write] —
  /// писать ли файлы в папку [dir]; [screen] и [distanceMm] — по ним
  /// спутник считает углы. Ответ — размер кадра камеры.
  Future<List<int>?> open({
    required EyeScreen screen,
    required int distanceMm,
    EyeCamera? camera,
    String? dir,
    bool write = true,
    bool strip = true,
    int? seg,
    int? qpc0Us,
    int? t0,
    String? calibration,
  }) async {
    final Map<String, Object?> reply = await request(
      'open',
      fields: <String, Object?>{
        'write': write,
        'dir': ?dir,
        if (camera != null) 'camera': camera.toJson(),
        'screen': screen.toJson(),
        'distance_mm': distanceMm,
        'strip': strip,
        'seg': ?seg,
        'qpc0_us': ?qpc0Us,
        't0': ?t0,
        // SNO-F-EYE-02: спутник поднят заново посреди записи — та же
        // модель из файла калибровки.
        'calibration': ?calibration,
      },
      timeout: kOpenTimeout,
    );
    final Object? frame = reply['frame'];
    return frame is List<Object?> &&
            frame.length == 2 &&
            frame.every((Object? v) => v is int)
        ? <int>[frame[0]! as int, frame[1]! as int]
        : null;
  }

  /// Новая попытка калибровки: [kind] — `full` (как у участника) или
  /// `quick` (девять точек без слежения).
  Future<void> calibrate({required int attempt, required String kind}) async {
    await request(
      'calibrate',
      fields: <String, Object?>{'attempt': attempt, 'kind': kind},
    );
  }

  /// Точка появилась на экране в миг [qpcUs] — без ответа. [phase] —
  /// `calib`, `pursuit`, `validate`, `head`, `check` или `off`; у
  /// `pursuit` — путь [path].
  void target({
    required String phase,
    required int qpcUs,
    String? id,
    double? x,
    double? y,
    Map<String, Object?>? path,
  }) {
    if (exited) {
      return;
    }
    _process.write(
      encodeEyeCommand('target', <String, Object?>{
        'phase': phase,
        'qpc_us': qpcUs,
        'id': ?id,
        'x': ?x,
        'y': ?y,
        'path': ?path,
      }),
    );
  }

  /// Сколько годных кадров набрали точки фазы [phase].
  Future<EyeSamples> samples({String phase = 'calib'}) async {
    return EyeSamples.fromMessage(
      await request('samples', fields: <String, Object?>{'phase': phase}),
    );
  }

  /// Модель попытки.
  Future<EyeFit> fit() async {
    return EyeFit.fromMessage(await request('fit', timeout: kFitTimeout));
  }

  /// Проверка точности и приём.
  Future<EyeValidation> validate() async {
    return EyeValidation.fromMessage(
      await request('validate', timeout: kFitTimeout),
    );
  }

  /// Начинает проверку точности [n] без новой калибровки (BUG-60): её
  /// точки — [target] с фазой `check`.
  Future<void> check(int n) async {
    await request('check', fields: <String, Object?>{'n': n});
  }

  /// Итог начатой проверки точности: точность каждого способа поправки
  /// на голову и где была голова.
  Future<EyeAccuracy> checked() async {
    return EyeAccuracy.fromMessage(
      await request('checked', timeout: kFitTimeout),
    );
  }

  /// Поток взгляда записи `gaze.jsonl` (SNO-F-REC-04): включить или
  /// выключить. Ответ — номер следующей строки файла.
  Future<int?> gaze({required bool on}) async {
    final Map<String, Object?> reply = await request(
      'gaze',
      fields: <String, Object?>{'on': on},
    );
    final Object? n = reply['n'];
    return n is int ? n : null;
  }

  /// Живая точка: включить или выключить поток [onGaze].
  Future<void> live({required bool on}) async {
    await request('live', fields: <String, Object?>{'on': on});
  }

  /// Закрывает камеру: файлы дописаны. Ответ — сводка спутника.
  Future<Map<String, Object?>?> closeCamera() async {
    final Map<String, Object?> reply = await request('close');
    final Object? summary = reply['summary'];
    return summary is Map<String, Object?> ? summary : null;
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
    // Ждать закрытия подписки незачем: строк больше не будет. А будущее
    // закрытия у вышедшего потока — общее, корневой зоны, и в поддельном
    // времени тестов не наступает.
    unawaited(_lines.cancel());
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
    unawaited(_lines.cancel());
  }
}
