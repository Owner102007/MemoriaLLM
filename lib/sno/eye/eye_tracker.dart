/// Айтрекер в приложении ветви для ПК: место записи и спутник во время
/// записи (SNO-F-EYE-04, SNO-F-EYE-05, SNO-F-EYE-07, SNO-ALG-EYE-03).
///
/// Что делает этот класс:
///
/// * держит место записи (`sno.eye_place`) — камеру, монитор, размер
///   экрана, расстояние и итог самопроверки;
/// * даёт экрану «Место записи» связь со спутником;
/// * пока идёт запись — ставит окно на весь монитор места записи под
///   замок, поднимает спутник, сверяет часы при старте и раз в минуту,
///   поднимает спутник заново, если он вышел, замолчал или шлёт мусор
///   (до трёх раз за запись), и пишет всё это в журнал событиями `eye.*`.
///
/// С шага 32 (ET-06) айтрекер — часть записи участника (SNO-F-EYE-01,
/// SNO-F-EYE-02, SNO-F-EYE-06, SNO-F-REC-04): после «Код записан» —
/// самопроверка, калибровка и итог, и только по «Начать» (или выбору
/// организатора после второй неудачи) идут сорок минут изучения; всё
/// изучение спутник пишет в подпапку `eye/` папки записи поток взгляда,
/// признаки кадров и полосу глаз; поднятый заново — той же моделью и в
/// следующий сегмент; запись остановилась — проверка точности в конце,
/// и спутник закрывается до завершения сессии. Что видно на экране —
/// `eye_recording.dart` и `recording_screen.dart`.
///
/// Время, таймеры и ожидание подменяются в тестах.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../domain/settings/app_settings.dart';
import '../clt/scenario.dart' show cltSeedOf;
import '../recording/event.dart';
import '../recording/journal_check.dart';
import '../recording/session.dart';
import '../settings_keys.dart';
import 'eye_calibration.dart';
import 'eye_calibration_run.dart';
import 'eye_link.dart';
import 'eye_place.dart';
import 'eye_process.dart';
import 'eye_protocol.dart';
import 'eye_recording.dart';
import 'eye_timing.dart';
import 'eye_trial.dart';
import 'eye_window.dart';
import 'qpc_clock.dart';

/// Таймер: зовёт [onTick] каждые [every]; возвращает, чем его снять.
typedef EyeTicker = void Function() Function(
  Duration every,
  void Function() onTick,
);

void Function() _timerTicker(Duration every, void Function() onTick) {
  final Timer timer = Timer.periodic(every, (Timer _) => onTick());
  return timer.cancel;
}

int Function() _stopwatchMs() {
  final Stopwatch watch = Stopwatch()..start();
  return () => watch.elapsedMilliseconds;
}

/// Файлы айтрекера на диске: папка стенда и сведения о месте в ней
/// (SNO-F-EYE-03). Договор — чтобы проверка шла в тестах без диска.
abstract interface class EyeFiles {
  /// Создаёт папку [path] со всеми недостающими.
  Future<void> createFolder(String path);

  /// Пишет текст [text] в файл [path].
  Future<void> writeText(String path, String text);
}

/// Файлы айтрекера на настоящем диске.
class EyeDiskFiles implements EyeFiles {
  /// Создаёт доступ.
  const EyeDiskFiles();

  @override
  Future<void> createFolder(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> writeText(String path, String text) async {
    await File(path).writeAsString(text);
  }
}

/// Сколько раз пробовать запуск, если прежний спутник ещё держит имя
/// экземпляра (`already_running`): он выходит за две секунды после
/// закрытия «Места записи».
const int kAlreadyRunningTries = 5;

/// Сколько ждать между такими попытками.
const Duration kAlreadyRunningPause = Duration(milliseconds: 700);

/// Имя подпапки взгляда в папке записи (SNO-F-REC-04).
const String kEyeFolder = 'eye';

/// Поток взгляда в папке записи.
const String kGazeFile = '$kEyeFolder/gaze.jsonl';

/// Самопроверка места перед калибровкой участника: длина замера и
/// прогрев камеры, секунд (SNO-F-EYE-01).
const double kRecordingCheckSeconds = 3;

/// Прогрев камеры перед замером.
const double kRecordingCheckWarmup = 1;

/// Что известно о спутнике идущей записи — для сведений записи.
class EyeRunInfo {
  /// Запись, о которой эти сведения; `null` — записи не было.
  String? recording;

  /// Место записи настроено.
  bool configured = false;

  /// Почему взгляда нет; `null` — спутник поднялся.
  String? unavailable;

  /// Что ответил спутник на `hello`.
  EyeHello? hello;

  /// Окно под замком.
  EyeWindowLock? window;

  /// Сколько раз спутник поднимали заново.
  int restarts = 0;

  /// Сдались ли.
  bool gaveUp = false;

  /// Пишется ли взгляд в этой записи (SNO-F-REC-04): изучение пошло с
  /// потоком взгляда.
  bool present = false;

  /// `ok` — калибровка принята; `low` — организатор выбрал «Писать с
  /// пометкой» после неудачи.
  String? quality;

  /// Почему взгляда в записи нет: `not_configured`, `unavailable`,
  /// `selfcheck_failed`, `open_failed`, `skipped`, `stopped`,
  /// `gave_up`, `limit`.
  String? reason;

  /// Итог калибровки: попытки, модель, точность, задержка камеры.
  Map<String, Object?>? calibration;

  /// Итог проверки в конце (SNO-F-EYE-06).
  Map<String, Object?>? endCheck;

  /// Сколько сегментов файлов взгляда.
  int segments = 0;

  /// Доля годных строк потока взгляда.
  double? validShare;

  /// Самопроверка потока взгляда после закрытия спутника.
  JournalCheck? check;

  /// Итог спутника последнего сегмента — как он его закрыл.
  Map<String, Object?>? summary;

  /// Новая запись [id] — сведения с чистого листа.
  void reset(String? id) {
    recording = id;
    configured = false;
    unavailable = null;
    hello = null;
    window = null;
    restarts = 0;
    gaveUp = false;
    present = false;
    quality = null;
    reason = null;
    calibration = null;
    endCheck = null;
    segments = 0;
    validShare = null;
    check = null;
    summary = null;
  }

  /// Как запись спутника выглядит в `recording.json` и манифесте: блок
  /// `eye_tracker` (SNO-F-REC-04).
  Map<String, Object?> toJson(EyePlace? place) => <String, Object?>{
    'present': present,
    if (quality != null) 'quality': quality,
    if (!present && reason != null) 'reason': reason,
    'source': 'webcam',
    'configured': configured,
    if (place != null) 'place': place.toJson(),
    if (unavailable != null) 'unavailable': unavailable,
    if (hello != null) 'satellite': hello!.toJson(),
    if (window != null) 'window': window!.toJson(),
    'restarts': restarts,
    'gave_up': gaveUp,
    if (calibration != null) 'calibration': calibration,
    if (endCheck != null) 'end_check': endCheck,
    if (present) 'file': kGazeFile,
    if (present) 'segments': segments,
    if (validShare != null) 'valid_share': validShare,
    if (check != null) 'check': check!.toJson(),
    if (summary != null) 'summary': summary,
  };
}

/// Чем кончился подъём спутника.
enum _Raised {
  /// Спутник поднят и жив.
  up,

  /// Взгляда в этой записи не будет: спутника нет или он не тот.
  unavailable,

  /// Не поднялся или умер, пока поднимался: можно пробовать ещё раз.
  failed,
}

/// Айтрекер приложения.
class EyeTracker extends ChangeNotifier {
  /// Создаёт айтрекер.
  EyeTracker({
    required AppSettingsRepository settings,
    required EyeLauncher launch,
    required QpcClock qpc,
    required this.window,
    this.dataFolder,
    this.files = const EyeDiskFiles(),
    this.build = '',
    this.branch = '',
    int Function()? monotonicMs,
    EyeTicker? ticker,
    Future<void> Function(Duration pause)? wait,
  }) : _settings = settings,
       _launch = launch,
       _qpc = qpc,
       _monotonicMs = monotonicMs ?? _stopwatchMs(),
       _ticker = ticker ?? _timerTicker,
       _wait = wait ?? Future<void>.delayed;

  final AppSettingsRepository _settings;
  final EyeLauncher _launch;
  final QpcClock _qpc;
  final int Function() _monotonicMs;
  final EyeTicker _ticker;
  final Future<void> Function(Duration pause) _wait;

  /// Окно приложения: мониторы и замок.
  final EyeWindow window;

  /// Папка данных приложения. В её подпапке `eye/` лежат журнал спутника
  /// и самопроверка места записи (BUG-58: не в `Записи/` — это не
  /// запись), в `Стенд/` — файлы пробной полной калибровки
  /// (SNO-F-EYE-03).
  final Future<String?> Function()? dataFolder;

  /// Файлы на диске: папка стенда и сведения о месте в ней.
  final EyeFiles files;

  /// Версия сборки — для `hello`.
  final String build;

  /// Ветвь — для `hello`.
  final String branch;

  EyePlace? _place;
  bool _placeLoaded = false;
  RecordingSession? _session;
  RecordingPhase _phase = RecordingPhase.idle;
  _EyeRun? _run;
  final EyeRunInfo _info = EyeRunInfo();

  /// Сведения о спутнике записи, сохранённые прежним запуском
  /// приложения: `{recording, block}`.
  Map<String, Object?>? _stored;
  bool _disposed = false;

  /// Место записи; `null` — не задано или ещё не прочитано.
  EyePlace? get place => _place;

  /// Прочитано ли место записи.
  bool get placeLoaded => _placeLoaded;

  /// Сведения о спутнике последней записи.
  EyeRunInfo get info => _info;

  /// Часы QPC приложения.
  QpcClock get qpc => _qpc;

  /// Идущая «Проверка айтрекера»; `null` — её нет (SNO-F-EYE-03).
  final ValueNotifier<EyeTrial?> trial = ValueNotifier<EyeTrial?>(null);

  /// Айтрекер идущей записи на экране (SNO-F-EYE-01, SNO-F-EYE-06):
  /// калибровка, итог, проверка в конце; `null` — экрана айтрекера записи
  /// нет. Ставит его на навигатор слой живого взгляда.
  final ValueNotifier<EyeRecordingView?> recording =
      ValueNotifier<EyeRecordingView?>(null);

  /// Запись, к которой айтрекер подключён.
  RecordingSession? get session => _session;

  void _show(_EyeRun run) {
    if (!_disposed && identical(_run, run)) {
      recording.value = run;
    }
  }

  /// Папка `eye/` в папке данных: по ней самопроверка меряет место на
  /// диске и в неё кладёт `selfcheck.json`; `null` — папки данных нет.
  Future<String?> eyeFolder() async {
    final String? root = await dataFolder?.call();
    return root == null ? null : p.join(root, 'eye');
  }

  /// Новая папка стенда `Стенд/<дата-время>/` для пробной полной
  /// калибровки; создана. `null` — папки данных нет.
  Future<String?> standFolder(DateTime at) async {
    final String? root = await dataFolder?.call();
    if (root == null) {
      return null;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    final String name =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    final String folder = p.join(root, kStandFolder, name);
    await files.createFolder(folder);
    return folder;
  }

  /// Начинает «Проверку айтрекера» на месте записи; идущая — та же.
  /// `null` — места записи нет.
  EyeTrial? beginTrial({int? seed}) {
    final EyeTrial? current = trial.value;
    if (current != null && current.phase != EyeTrialPhase.closed) {
      return current;
    }
    final EyePlace? place = _place;
    if (place == null) {
      return null;
    }
    final EyeTrial created = EyeTrial(tracker: this, place: place, seed: seed);
    trial.value = created;
    return created;
  }

  /// Проверка закрылась сама.
  void trialClosed(EyeTrial closed) {
    if (!_disposed && identical(trial.value, closed)) {
      trial.value = null;
    }
  }

  /// Закрывает идущую проверку: место записи открывают заново или
  /// начинается запись — спутник у машины один.
  Future<void> closeTrial() async {
    final EyeTrial? current = trial.value;
    if (current != null) {
      await current.close();
    }
  }

  /// Читает место записи из настроек.
  Future<EyePlace?> loadPlace() async {
    try {
      _place = EyePlace.decode(await _settings.read(SnoSettingsKeys.eyePlace));
    } on Object {
      _place = null;
    }
    _placeLoaded = true;
    _notify();
    return _place;
  }

  /// Сохраняет место записи.
  Future<void> savePlace(EyePlace place) async {
    await _settings.write(SnoSettingsKeys.eyePlace, place.encode());
    _place = place;
    _placeLoaded = true;
    _notify();
  }

  /// Поднимает спутник и здоровается с ним: связь для «Места записи».
  /// Закрывает её тот, кто открыл. Не поднялся — [EyeError].
  Future<EyeLink> connect() async => (await _open()).$1;

  /// Запуск спутника и `hello`. Прежний спутник ещё держит имя
  /// экземпляра (`already_running`: «Место записи» закрыли только что) —
  /// ещё раз через [kAlreadyRunningPause], до [kAlreadyRunningTries]
  /// раз. Любой другой отказ — [EyeError] сразу. [stopped] — запись,
  /// ради которой поднимали, уже кончилась: спутник закрывается.
  Future<(EyeLink, EyeHello)> _open({bool Function()? stopped}) async {
    bool gone() => stopped?.call() ?? false;
    EyeError? last;
    for (int attempt = 0; attempt < kAlreadyRunningTries; attempt++) {
      if (attempt > 0) {
        await _wait(kAlreadyRunningPause);
      }
      if (gone()) {
        throw const EyeError('stopped', 'запись остановлена');
      }
      final EyeLink link;
      try {
        link = await EyeLink.start(_launch, qpc: _qpc);
      } on EyeError {
        rethrow;
      } on Object catch (e) {
        throw EyeError('start', '$e');
      }
      final EyeHello hello;
      try {
        hello = await link.hello(build: build, branch: branch);
      } on EyeError catch (e) {
        await link.close();
        if (e.code != 'already_running') {
          rethrow;
        }
        last = e;
        continue;
      } on Object catch (e) {
        await link.close();
        throw EyeError('start', '$e');
      }
      if (gone()) {
        await link.close();
        throw const EyeError('stopped', 'запись остановлена');
      }
      return (link, hello);
    }
    throw last ?? const EyeError('already_running', 'Спутник уже запущен');
  }

  /// Подключает айтрекер к записи: старт записи поднимает спутник,
  /// остановка — опускает. Сведения о спутнике идут в `recording.json`
  /// той записи, о которой они: сведения, сохранённые до перезапуска
  /// приложения, — тоже.
  void attach(RecordingSession session) {
    _session?.removeListener(_sessionChanged);
    _session = session;
    _phase = session.phase;
    session.addListener(_sessionChanged);
    session.addInfoPart('eye_tracker', () => _infoFor(session.state?.id));
    // SNO-F-EYE-01: сорок минут — от начала изучения, после калибровки.
    session.holdStudy = true;
    // SNO-F-EYE-06: завершение сессии ждёт, пока спутник допишет файлы.
    session.addFinishHook(_settled);
    unawaited(_loadStored());
  }

  /// Ждёт, пока спутник записи закроется после проверки в конце.
  Future<void> _settled() async {
    final Future<void>? stopping = _stopping;
    if (stopping != null) {
      await stopping;
    }
  }

  /// Сведения о спутнике записи, поднятой после перезапуска приложения
  /// (SNO-F-EYE-06, SNO-F-REC-04): проверка в конце, которую застал
  /// сбой, названа незавершённой, а поток взгляда сверен с диска.
  Future<void> _repairStored(RecordingSession session) async {
    await _loadStored();
    final String? id = session.state?.id;
    final Map<String, Object?>? stored = _stored;
    final Object? block = stored?['block'];
    if (id == null ||
        stored?['recording'] != id ||
        block is! Map<String, Object?> ||
        _info.recording == id) {
      return;
    }
    final Map<String, Object?> fixed = <String, Object?>{...block};
    bool changed = false;
    final Object? end = fixed['end_check'];
    if (end is Map<String, Object?> && end['started'] == true) {
      fixed['end_check'] = <String, Object?>{'done': false, 'error': 'crash'};
      changed = true;
    }
    if (fixed['present'] == true && fixed['check'] == null) {
      final List<int>? bytes = await session.streamBytes(kGazeFile);
      if (bytes != null) {
        fixed['check'] = checkJournal(bytes, key: 'n', late: true).toJson();
        fixed['valid_share'] = gazeValidShare(bytes);
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    final Map<String, Object?> next = <String, Object?>{
      'recording': id,
      'block': fixed,
    };
    _stored = next;
    try {
      await _settings.write(SnoSettingsKeys.eyeRun, jsonEncode(next));
    } on Object {
      // Не легло — сведения останутся в памяти до конца запуска.
    }
    session.infoChanged();
  }

  /// Блок `eye_tracker` для записи [id]; `null` — о ней айтрекер ничего
  /// не знает (запись оборвалась вместе с приложением).
  Map<String, Object?>? _infoFor(String? id) {
    if (id == null) {
      return null;
    }
    if (_info.recording == id) {
      return _info.toJson(_place);
    }
    final Map<String, Object?>? stored = _stored;
    final Object? block = stored?['block'];
    if (stored?['recording'] == id && block is Map<String, Object?>) {
      return block;
    }
    return null;
  }

  Future<void> _loadStored() async {
    try {
      final String? text = await _settings.read(SnoSettingsKeys.eyeRun);
      final Object? raw = text == null ? null : jsonDecode(text);
      if (raw is Map<String, Object?> && _stored == null) {
        _stored = raw;
      }
    } on Object {
      // Нечитаемые сведения — то же, что их нет.
    }
  }

  /// Сохраняет сведения о спутнике идущей записи: они переживут
  /// перезапуск приложения между остановкой записи и завершением сессии.
  Future<void> _store() async {
    final String? id = _info.recording;
    if (id == null) {
      return;
    }
    final Map<String, Object?> stored = <String, Object?>{
      'recording': id,
      'block': _info.toJson(_place),
    };
    _stored = stored;
    try {
      await _settings.write(SnoSettingsKeys.eyeRun, jsonEncode(stored));
    } on Object {
      // Не легло — сведения останутся в памяти до конца запуска.
    }
  }

  void _sessionChanged() {
    final RecordingSession? session = _session;
    if (session == null) {
      return;
    }
    final RecordingPhase now = session.phase;
    final RecordingPhase was = _phase;
    _phase = now;
    if (now == RecordingPhase.recording && was != RecordingPhase.recording) {
      // Сведения прежней записи не должны попасть в сведения новой:
      // запись пишет их раньше, чем спутник успеет подняться.
      _info.reset(session.state?.id);
      unawaited(_startRun(session));
    } else if (now != RecordingPhase.recording &&
        was == RecordingPhase.recording) {
      unawaited(_stopRun());
    } else if (now == RecordingPhase.stopped &&
        was == RecordingPhase.idle &&
        _run == null) {
      // Сессию подняли остановленной — приложение перезапускали.
      unawaited(_repairStored(session));
    } else if (now == RecordingPhase.recording && !session.studyPending) {
      // SNO-F-EYE-01: изучение началось само — калибровка ждала дольше
      // положенного.
      final _EyeRun? run = _run;
      if (run != null &&
          (run.phase == EyeRecordingPhase.starting ||
              run.phase == EyeRecordingPhase.calibrating ||
              run.phase == EyeRecordingPhase.result)) {
        unawaited(run.studyStartedAside());
      }
    }
  }

  Future<void> _startRun(RecordingSession session) async {
    // Проверка айтрекера держит спутник и окно: запись важнее.
    await closeTrial();
    final _EyeRun? previous = _run;
    if (previous != null) {
      await previous.stop();
      _drop(previous);
    }
    final _EyeRun run = _EyeRun(this, session);
    _run = run;
    run.addListener(() => _runChanged(run));
    await run.start();
  }

  /// Экран айтрекера записи уходит, когда показывать нечего.
  void _runChanged(_EyeRun run) {
    if (_disposed) {
      return;
    }
    if (run.phase == EyeRecordingPhase.done &&
        identical(recording.value, run)) {
      recording.value = null;
    } else if (run.phase == EyeRecordingPhase.endCheck &&
        identical(_run, run)) {
      recording.value = run;
    }
  }

  void _drop(_EyeRun run) {
    if (identical(_run, run)) {
      _run = null;
    }
    if (!_disposed && identical(recording.value, run)) {
      recording.value = null;
    }
  }

  /// Остановка записи: проверка в конце и закрытие спутника идут один
  /// раз, и завершение сессии их ждёт.
  Future<void>? _stopping;

  Future<void> _stopRun() {
    return _stopping ??= _stopRunOnce().whenComplete(() => _stopping = null);
  }

  Future<void> _stopRunOnce() async {
    final _EyeRun? run = _run;
    if (run == null) {
      return;
    }
    // SNO-F-EYE-06: изучение шло со взглядом — проверка точности в конце,
    // потом спутник дописывает файлы.
    await run.finish();
    _drop(run);
    await _store();
  }

  /// Идёт ли сейчас спутник записи.
  @visibleForTesting
  bool get running => _run?.alive ?? false;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _session?.removeListener(_sessionChanged);
    unawaited(closeTrial());
    final _EyeRun? run = _run;
    _run = null;
    if (run != null) {
      // Приложение уходит: без проверки в конце, спутник закрывается.
      unawaited(run.stop());
    }
    trial.dispose();
    recording.dispose();
    super.dispose();
  }
}

/// Папка стенда в папке данных приложения (SNO-F-EYE-03).
const String kStandFolder = 'Стенд';

/// Спутник одной записи: от старта записи до закрытия после проверки в
/// конце (SNO-F-EYE-01, SNO-F-EYE-02, SNO-F-EYE-04, SNO-F-EYE-06).
///
/// Он же — то, что видит экран айтрекера записи ([EyeRecordingView]):
/// самопроверка, точки калибровки, итог попытки, точки проверки в конце.
class _EyeRun extends ChangeNotifier implements EyeRecordingView {
  _EyeRun(this.tracker, this.session);

  final EyeTracker tracker;
  final RecordingSession session;
  EyeLink? _link;
  SilenceWatch? _watch;
  void Function()? _stopTick;
  void Function()? _stopSync;
  StreamSubscription<EyeWindowLock>? _windowChanges;
  bool _stopped = false;

  /// Идёт ли подъём спутника: сигналы о потере его ждут конца подъёма —
  /// подъём сам узнаёт, жив ли поднятый.
  bool _raising = false;
  bool _syncing = false;

  /// Номер подъёма спутника: запоздавшие сигналы прежнего — не в счёт.
  int _generation = 0;

  /// Номер сегмента файлов взгляда: растёт с каждым подъёмом спутника
  /// заново (SNO-F-REC-04).
  int _segment = 0;

  // --- калибровка, изучение и проверка в конце (шаг 32) -----------------

  EyePlace? _place;
  EyeRecordingPhase _phase = EyeRecordingPhase.starting;
  String? _stage;
  EyeCalibrationRun? _run;
  EyeCheckRun? _checkRun;
  EyeAttemptOutcome? _outcome;
  int _attempt = 0;
  int _failures = 0;
  String? _problem;

  /// Идёт выбор или начало изучения: второе нажатие не в счёт.
  bool _acting = false;

  /// Папка `eye/` записи на диске.
  String? _eyeDir;

  /// Камера открыта на запись файлов взгляда.
  bool _cameraOpen = false;

  /// Окно сменилось, пока камера открыта: следующая попытка — с камерой,
  /// открытой заново под новое окно.
  bool _stale = false;

  /// Пишется ли поток взгляда: изучение идёт с ним.
  bool _gazeOn = false;

  /// Пара часов «QPC — t записи» для файлов взгляда.
  int? _qpc0;
  int? _t0;

  double _dpr = 1;
  EyeScreen? _screen;

  /// Экран айтрекера записи встал: калибровке есть где рисовать точки и
  /// откуда взять размер окна.
  final Completer<void> _screenUp = Completer<void>();

  /// Конец проверки в конце, если организатор пропустил её.
  bool _skipped = false;

  EyeFrameShown? _frameShown;
  Size Function()? _windowSize;

  @override
  EyeFrameShown? get frameShown => _frameShown;

  @override
  set frameShown(EyeFrameShown? value) {
    _frameShown = value;
    _screenAttached();
  }

  @override
  Size Function()? get windowSize => _windowSize;

  @override
  set windowSize(Size Function()? value) {
    _windowSize = value;
    _screenAttached();
  }

  /// Запись кончилась, а экран так и не встал: подготовка калибровки
  /// больше никого не ждёт.
  void _release() {
    if (!_screenUp.isCompleted) {
      _screenUp.complete();
    }
  }

  void _screenAttached() {
    if (_frameShown != null &&
        _windowSize != null &&
        !_screenUp.isCompleted) {
      _screenUp.complete();
    }
  }

  @override
  EyeRecordingPhase get phase => _phase;

  @override
  String? get stage => _stage;

  @override
  EyeTargetsRun? get targets => switch (_phase) {
    EyeRecordingPhase.calibrating => _run,
    EyeRecordingPhase.endCheck => _checkRun,
    _ => null,
  };

  @override
  EyeAttemptOutcome? get outcome => _outcome;

  @override
  int get attempt => _attempt;

  @override
  int get failures => _failures;

  @override
  bool get mustChoose => _failures >= kRecordingAttempts;

  @override
  bool get busy => _acting || _raising || _link == null;

  @override
  String? get problem => _problem;

  bool get alive => !_stopped && _link != null && !_link!.exited;

  EyeRunInfo get info => tracker._info;

  /// Зерно порядка точек — по коду участника, как у теста нагрузки: один
  /// код даёт один порядок на любом ПК (SNO-F-EYE-01).
  int get _seed => cltSeedOf(session.participant?.code ?? '');

  void _log(SnoEventType type, Map<String, Object?> data) {
    if (!_stopped) {
      session.log(type, data: data);
    }
  }

  void _set(EyeRecordingPhase phase, {String? stage}) {
    _phase = phase;
    _stage = stage;
    if (!_quiet) {
      notifyListeners();
    }
  }

  void _changed() {
    if (!_quiet) {
      notifyListeners();
    }
  }

  /// Слушателей больше нет: оповещать некого.
  bool _quiet = false;

  Future<void> start() async {
    final EyePlace? place = await tracker.loadPlace();
    if (_stopped) {
      return;
    }
    if (place == null) {
      info.unavailable = 'not_configured';
      info.reason = 'not_configured';
      _log(SnoEventType.eyeUnavailable, <String, Object?>{
        'reason': 'not_configured',
        'text': 'Айтрекер не настроен — запись идёт без взгляда',
      });
      _beginWithout();
      unawaited(tracker._store());
      return;
    }
    _place = place;
    info.configured = true;
    // SNO-F-EYE-01: экран айтрекера записи встаёт сразу — участник не
    // видит полки до калибровки.
    tracker._show(this);
    _set(
      EyeRecordingPhase.starting,
      stage: 'Окно встаёт на монитор места записи…',
    );
    // SNO-F-EYE-07: окно — на весь монитор места записи, сразу.
    final EyeWindowLock? lock = await tracker.window.lock(place.monitor);
    if (_stopped) {
      await tracker.window.unlock();
      return;
    }
    info.window = lock;
    if (lock != null) {
      _dpr = lock.dpr;
    }
    _log(SnoEventType.eyeWindow, <String, Object?>{
      'locked': lock != null,
      if (lock != null) ...lock.toJson(),
      'wanted': place.monitor,
    });
    _windowChanges = tracker.window.changes.listen(_windowChanged);
    _set(EyeRecordingPhase.starting, stage: 'Запускаю айтрекер…');
    final _Raised raised = await _raise(first: true);
    if (_stopped) {
      return;
    }
    if (raised == _Raised.unavailable) {
      info.reason = 'unavailable';
      _beginWithout();
      unawaited(tracker._store());
      return;
    }
    if (raised == _Raised.failed) {
      await _restart();
      if (_stopped || _link == null) {
        return;
      }
    }
    unawaited(tracker._store());
    await _prepare();
  }

  /// Самопроверка места и камера перед калибровкой (SNO-F-EYE-01): ждёт,
  /// пока встанет экран, — по нему считается окно.
  Future<void> _prepare() async {
    await _screenUp.future;
    final EyeLink? link = _link;
    final EyePlace? place = _place;
    if (_stopped || link == null || place == null) {
      return;
    }
    _set(EyeRecordingPhase.starting, stage: 'Самопроверка…');
    _eyeDir = await session.folderPath(kEyeFolder);
    final EyeCheck checked;
    try {
      checked = await link.selfcheck(
        camera: place.camera,
        seconds: kRecordingCheckSeconds,
        warmup: kRecordingCheckWarmup,
        dir: _eyeDir,
      );
    } on EyeError catch (e) {
      if (_stopped || !identical(link, _link)) {
        return;
      }
      _log(SnoEventType.eyeCheck, <String, Object?>{
        'verdict': 'fail',
        'error': e.code,
        'text': describeEyeError(e),
      });
      await _without('selfcheck_failed', drop: true);
      return;
    }
    if (_stopped) {
      return;
    }
    _log(SnoEventType.eyeCheck, <String, Object?>{
      'verdict': checked.verdict.wire,
      'checks': <Object?>[
        for (final EyeCheckRow row in checked.rows)
          <String, Object?>{'id': row.id, 'verdict': row.verdict.wire},
      ],
    });
    if (checked.verdict == EyeVerdict.fail) {
      await _without('selfcheck_failed', drop: true);
      return;
    }
    if (!await _openCamera(first: true)) {
      return;
    }
    await _calibrate(next: true);
  }

  /// Окно в логических пикселях и миллиметрах: размер — от экрана,
  /// миллиметры — по пикселям монитора на мм из места записи.
  EyeScreen _screenNow() {
    final EyePlace place = _place!;
    Size size = windowSize?.call() ?? Size.zero;
    final EyeWindowLock? lock = info.window;
    if ((size.width <= 0 || size.height <= 0) && lock != null) {
      size = Size(lock.widthPx / lock.dpr, lock.heightPx / lock.dpr);
    }
    final double mmPerPx = 1 / place.pxPerMm;
    return EyeScreen(
      width: size.width,
      height: size.height,
      widthMm: size.width * _dpr * mmPerPx,
      heightMm: size.height * _dpr * mmPerPx,
    );
  }

  /// Открывает камеру на запись файлов взгляда в папку записи. [first] —
  /// первый раз за запись: у поднятого заново спутника — следующий
  /// сегмент и, если изучение уже идёт, модель из файла калибровки.
  /// Не открылась — запись идёт без взгляда (до изучения) или спутник
  /// считается потерянным (во время него); отвечает, открылась ли.
  Future<bool> _openCamera({required bool first, bool restore = false}) async {
    final EyeLink? link = _link;
    final EyePlace? place = _place;
    if (link == null || place == null || _stopped) {
      return false;
    }
    final EyeScreen screen = _screen != null && restore
        ? _screen!
        : _screenNow();
    _screen = screen;
    _qpc0 ??= tracker._qpc.nowUs();
    _t0 ??= session.eyeNow;
    final String? dir = _eyeDir;
    try {
      await link.open(
        screen: screen,
        distanceMm: place.distanceMm,
        camera: place.camera,
        dir: dir,
        write: dir != null,
        strip: true,
        seg: _segment,
        qpc0Us: _qpc0,
        t0: _t0,
        calibration: restore && dir != null
            ? p.join(dir, 'calibration.json')
            : null,
      );
    } on EyeError catch (e) {
      if (_stopped || !identical(link, _link)) {
        return false;
      }
      if (first) {
        _log(SnoEventType.eyeUnavailable, <String, Object?>{
          'reason': 'open_failed',
          'error': e.code,
          'text': describeEyeError(e),
        });
        await _without('open_failed', drop: true);
      }
      return false;
    }
    _cameraOpen = true;
    _stale = false;
    info.segments = _segment + 1;
    return true;
  }

  Future<void> _calibrate({required bool next}) async {
    final EyeLink? link = _link;
    final EyePlace? place = _place;
    if (link == null || place == null || _stopped) {
      return;
    }
    if (_stale) {
      try {
        await link.closeCamera();
      } on EyeError {
        // Не закрылась — откроется всё равно: спутник сам закроет прежнюю.
      }
      _cameraOpen = false;
      _segment++;
      if (!await _openCamera(first: false)) {
        _problem = 'Камера не открылась заново — повторите';
        _set(EyeRecordingPhase.result);
        return;
      }
    }
    if (next) {
      _attempt++;
    }
    _problem = null;
    _outcome = null;
    _run?.dispose();
    final EyeCalibrationRun current = EyeCalibrationRun(
      link: link,
      qpc: tracker._qpc,
      kind: EyeCalibrationKind.full,
      attempt: _attempt,
      seed: (_seed + _attempt) & 0xFFFFFFFF,
      screen: _screen ?? _screenNow(),
      distanceMm: place.distanceMm,
      frameShown: _shown,
    )..onTarget = _targetSent;
    _run = current;
    _log(SnoEventType.eyeCalibrationStart, <String, Object?>{
      'attempt': _attempt,
      'kind': 'full',
      'seed': (_seed + _attempt) & 0xFFFFFFFF,
    });
    _set(EyeRecordingPhase.calibrating);
    final EyeAttemptOutcome result = await current.run();
    if (!identical(_run, current) || _stopped) {
      return;
    }
    _outcome = result;
    final EyeValidation? v = result.validation;
    final EyeFit? fit = result.fit;
    if (result.cancelled) {
      _problem ??= 'Калибровка прервана — повторите';
    } else if (result.error != null) {
      _problem = 'Айтрекер отказал: ${describeEyeError(result.error!)}';
    } else if (result.noFace) {
      _problem = 'Камера не видит лица — сядьте напротив камеры и повторите';
    } else if (v != null && !v.accepted) {
      _failures++;
    }
    _log(SnoEventType.eyeCalibrationResult, <String, Object?>{
      'attempt': _attempt,
      if (v != null) 'accepted': v.accepted,
      if (v != null) 'reason': v.reason?.wire,
      if (v != null) 'accuracy_deg': v.accuracyDeg,
      if (v != null) 'accuracy_cm': v.accuracyCm,
      if (v != null) 'precision_deg': v.precisionDeg,
      if (v != null) 'worst_deg': v.worstDeg,
      if (fit != null) 'model': fit.model,
      if (fit != null && !fit.cvDeg.isNaN) 'cv_deg': fit.cvDeg,
      if (fit != null) 'latency_ms': fit.latencyMs,
      if (fit != null) 'head_model': fit.headModel,
      if (result.noFace) 'no_face': true,
      if (result.error != null) 'error': result.error!.code,
      if (result.cancelled) 'cancelled': true,
      'failures': _failures,
    });
    if (fit != null && v != null) {
      info.calibration = <String, Object?>{
        'attempts': _attempt,
        'accepted': v.accepted,
        'model': fit.model,
        'head_model': fit.headModel,
        'accuracy_deg': v.accuracyDeg,
        'accuracy_cm': v.accuracyCm,
        'precision_deg': v.precisionDeg,
        'worst_deg': v.worstDeg,
        'latency_ms': fit.latencyMs,
        'seed': (_seed + _attempt) & 0xFFFFFFFF,
      };
    }
    _set(EyeRecordingPhase.result);
  }

  void _targetSent({
    required String phase,
    required int qpcUs,
    String? id,
    double? x,
    double? y,
    Map<String, Object?>? path,
  }) {
    final Map<String, Object?> data = <String, Object?>{
      'phase': phase,
      'id': ?id,
      'x': ?x,
      'y': ?y,
      'qpc_us': qpcUs,
      'path': ?path,
    };
    if (_phase == EyeRecordingPhase.endCheck) {
      unawaited(session.logAfter(SnoEventType.eyeTarget, data: data));
    } else {
      _log(SnoEventType.eyeTarget, data);
    }
  }

  Future<int> _shown() {
    final EyeFrameShown? shown = frameShown;
    return shown == null ? Future<int>.value(tracker._qpc.nowUs()) : shown();
  }

  @override
  Future<void> begin() async {
    final EyeAttemptOutcome? outcome = _outcome;
    if (_phase != EyeRecordingPhase.result ||
        _acting ||
        outcome?.validation?.accepted != true) {
      return;
    }
    await _study('ok');
  }

  @override
  Future<void> retry() async {
    if (_phase != EyeRecordingPhase.result || _acting || mustChoose) {
      return;
    }
    final EyeAttemptOutcome? outcome = _outcome;
    // Не видно лица, сбой спутника, прерванная попытка — та же попытка,
    // не в счёт; не принята — следующая.
    final bool counted = outcome?.validation != null;
    await _calibrate(next: counted);
  }

  @override
  Future<void> choose({required bool write}) async {
    if (_phase != EyeRecordingPhase.result || _acting) {
      return;
    }
    _log(SnoEventType.eyeSkip, <String, Object?>{
      'by': 'experimenter',
      'write': write,
      'failures': _failures,
    });
    if (write && _outcome?.fit != null) {
      await _study('low');
      return;
    }
    await _without('skipped', drop: true);
  }

  /// Изучение с потоком взгляда (SNO-F-EYE-02): поток пошёл — сорок
  /// минут пошли.
  Future<void> _study(String quality) async {
    final EyeLink? link = _link;
    if (link == null) {
      return;
    }
    _acting = true;
    _changed();
    int? n;
    try {
      n = await link.gaze(on: true);
    } on EyeError catch (e) {
      _acting = false;
      if (_stopped) {
        return;
      }
      _problem = 'Поток взгляда не пошёл: ${describeEyeError(e)}';
      _changed();
      return;
    }
    _acting = false;
    if (_stopped) {
      return;
    }
    _gazeOn = true;
    info
      ..present = true
      ..quality = quality
      ..reason = null;
    _log(SnoEventType.eyeGaze, <String, Object?>{
      'seg': _segment,
      'n': n,
      'quality': quality,
    });
    // Сначала своё состояние, потом изучение: запись оповестит
    // айтрекер, и он не должен принять начало изучения за чужое.
    _set(EyeRecordingPhase.studying);
    session.beginStudy(<String, Object?>{'gaze': true, 'quality': quality});
    unawaited(tracker._store());
  }

  /// Изучение без взгляда: [reason] — почему; [drop] — убрать подпапку
  /// `eye/`, в архиве её не будет (SNO-F-EYE-01). Спутник закрыт, окно
  /// остаётся под замком до конца записи.
  Future<void> _without(String reason, {bool drop = false}) async {
    info.reason = reason;
    _run?.cancel();
    _gazeOn = false;
    final EyeLink? link = _link;
    _link = null;
    _watch = null;
    _generation++;
    _stopTimers();
    if (link != null) {
      await link.close();
    }
    _cameraOpen = false;
    if (drop) {
      await session.dropFolder(kEyeFolder);
    }
    _beginWithout();
    unawaited(tracker._store());
  }

  /// Изучение начинается без взгляда — экрана айтрекера больше нет.
  void _beginWithout() {
    _set(EyeRecordingPhase.done);
    session.beginStudy(const <String, Object?>{'gaze': false});
  }

  @override
  void skipEndCheck() {
    if (_phase != EyeRecordingPhase.endCheck || _skipped) {
      return;
    }
    _skipped = true;
    _checkRun?.cancel();
  }

  void _windowChanged(EyeWindowLock changed) {
    info.window = changed;
    _dpr = changed.dpr;
    _log(SnoEventType.eyeWindow, <String, Object?>{
      'changed': true,
      ...changed.toJson(),
    });
    if (!_cameraOpen) {
      return;
    }
    if (_phase == EyeRecordingPhase.calibrating) {
      // Точки стояли бы не там, а спутник считает углы по окну из
      // `open`: попытка прервана и не в счёт, камера откроется заново.
      _stale = true;
      _problem = 'Окно сменилось — повторите калибровку';
      _run?.cancel();
    } else if (_phase == EyeRecordingPhase.result ||
        _phase == EyeRecordingPhase.starting) {
      _stale = true;
    }
  }

  Future<_Raised> _raise({required bool first}) async {
    _raising = true;
    _changed();
    try {
      return await _raiseOnce(first: first);
    } finally {
      _raising = false;
      _changed();
    }
  }

  /// Поднимает спутник: запуск, `hello`, сверка часов, таймеры; у
  /// поднятого заново — камера и поток взгляда, если они были.
  Future<_Raised> _raiseOnce({required bool first}) async {
    final int generation = ++_generation;
    final int startedMs = tracker._monotonicMs();
    final (EyeLink, EyeHello) opened;
    try {
      opened = await tracker._open(stopped: () => _stopped);
    } on EyeError catch (e) {
      if (_stopped) {
        return _Raised.failed;
      }
      if (first) {
        info.unavailable = e.code;
        _log(SnoEventType.eyeUnavailable, <String, Object?>{
          'reason': e.code,
          'text': describeEyeError(e),
        });
        return _Raised.unavailable;
      }
      _log(SnoEventType.eyeLost, <String, Object?>{
        'reason': 'start',
        'error': e.code,
        'text': describeEyeError(e),
      });
      return _Raised.failed;
    }
    final EyeLink link = opened.$1;
    final EyeHello hello = opened.$2;
    if (_stopped) {
      await link.close();
      return _Raised.failed;
    }
    _link = link;
    info.hello = hello;
    link
      ..onHeartbeat = (EyeHeartbeat beat) {
        if (generation == _generation) {
          _watch?.beat(tracker._monotonicMs());
        }
      }
      ..onGarbage = (int inRow) {
        if (generation == _generation && inRow >= kEyeGarbageInRow) {
          unawaited(_lost('garbage', kill: true));
        }
      }
      ..onFace = (EyeFace face) {
        if (generation == _generation) {
          _faceSaid(face);
        }
      }
      ..onError = (EyeError error) {
        // Камера пропала, диск отказал посреди записи взгляда.
        if (generation == _generation && _gazeOn) {
          _log(SnoEventType.eyeLost, <String, Object?>{
            'reason': error.code == 'camera_lost' ? 'camera' : error.code,
            'text': describeEyeError(error),
          });
        }
      };
    unawaited(
      link.exitCode.then((int code) {
        if (generation == _generation && !link.closing && !_stopped) {
          unawaited(_lost('exit', code: code));
        }
      }),
    );
    if (first) {
      _log(SnoEventType.eyeReady, <String, Object?>{
        ...hello.toJson(),
        'start_ms': tracker._monotonicMs() - startedMs,
      });
      // Пара часов «QPC — t записи»: от неё разбор переводит время
      // спутника в время журнала (SNO-ALG-EYE-03, шаг 5).
      final int qpc = tracker._qpc.nowUs();
      final int t = session.eyeNow;
      _qpc0 = qpc;
      _t0 = t;
      _log(SnoEventType.eyeClock, <String, Object?>{'qpc0_us': qpc, 't0': t});
    } else {
      _log(SnoEventType.eyeRestart, <String, Object?>{
        'n': info.restarts,
        'seg': ++_segment,
        'start_ms': tracker._monotonicMs() - startedMs,
      });
    }
    await _sync(kSyncRoundsOpen, force: true);
    if (_stopped || generation != _generation) {
      return _Raised.failed;
    }
    if (link.exited || link.garbageInRow >= kEyeGarbageInRow) {
      // Спутник умер или сломался, пока поднимался: сигнал о потере
      // пришёл во время подъёма и ждал его конца.
      _link = null;
      _generation++;
      final bool died = link.exited;
      _log(SnoEventType.eyeLost, <String, Object?>{
        'reason': died ? 'exit' : 'garbage',
        if (died) 'code': await link.exitCode,
      });
      if (!died) {
        await link.kill();
      }
      return _Raised.failed;
    }
    if (!first && _cameraOpen) {
      // SNO-F-EYE-02: поднятый заново спутник пишет дальше той же
      // моделью — в следующий сегмент файлов.
      _cameraOpen = false;
      final bool again = await _openCamera(first: false, restore: _gazeOn);
      if (_stopped || generation != _generation) {
        return _Raised.failed;
      }
      if (!again) {
        _link = null;
        _generation++;
        _log(SnoEventType.eyeLost, <String, Object?>{'reason': 'open'});
        await link.close();
        return _Raised.failed;
      }
      if (_gazeOn) {
        try {
          final int? n = await link.gaze(on: true);
          _log(SnoEventType.eyeGaze, <String, Object?>{
            'seg': _segment,
            'n': n,
            'restart': true,
          });
        } on EyeError catch (e) {
          if (_stopped || generation != _generation) {
            return _Raised.failed;
          }
          _link = null;
          _generation++;
          _log(SnoEventType.eyeLost, <String, Object?>{
            'reason': 'gaze',
            'error': e.code,
          });
          await link.close();
          return _Raised.failed;
        }
      } else if (_phase == EyeRecordingPhase.calibrating ||
          _phase == EyeRecordingPhase.result) {
        // Калибровка шла на прежнем спутнике: у нового модели нет —
        // попытка прервана, та же и не в счёт.
        _problem = 'Айтрекер перезапустился — повторите калибровку';
        _outcome = null;
      }
    }
    _watch = SilenceWatch(tracker._monotonicMs());
    _stopTick ??= tracker._ticker(kEyeTick, _tick);
    _stopSync ??= tracker._ticker(kSyncEvery, () {
      unawaited(_sync(kSyncRoundsMinute));
    });
    return _Raised.up;
  }

  /// Лица нет дольше секунды или оно вернулось (SNO-F-EYE-02).
  void _faceSaid(EyeFace face) {
    if (!_gazeOn) {
      return;
    }
    if (face.lost) {
      _log(SnoEventType.eyeFaceLost, <String, Object?>{
        'qpc_us': face.qpcUs,
        'since_qpc_us': ?face.sinceUs,
      });
    } else {
      _log(SnoEventType.eyeFaceBack, <String, Object?>{
        'qpc_us': face.qpcUs,
        'ms': ?face.ms,
      });
    }
  }

  void _tick() {
    final SilenceWatch? watch = _watch;
    if (watch == null || _stopped || _raising) {
      return;
    }
    if (watch.tick(tracker._monotonicMs())) {
      unawaited(_lost('silent', kill: true));
    }
  }

  /// Сверка часов: [rounds] обменов и событие `eye.sync`. Сверка раз в
  /// минуту во время подъёма не идёт; сверка самого подъёма — [force].
  Future<void> _sync(int rounds, {bool force = false}) async {
    final EyeLink? link = _link;
    if (link == null || _stopped || _syncing || (_raising && !force)) {
      return;
    }
    _syncing = true;
    try {
      final SyncResult? result = await link.sync(rounds);
      if (result == null || _stopped || !identical(link, _link)) {
        return;
      }
      final int qpc = tracker._qpc.nowUs();
      final int t = session.eyeNow;
      _log(SnoEventType.eyeSync, <String, Object?>{
        'qpc_us': qpc,
        't': t,
        'offset_us': result.offsetUs,
        'rtt_us': result.rttUs,
        'n': result.rounds,
      });
    } on EyeError {
      // Сверка не прошла: о спутнике скажет его выход или молчание.
    } finally {
      _syncing = false;
    }
  }

  /// Спутник потерян: `eye.lost` и подъём заново. Во время подъёма
  /// сигнал не в счёт: подъём сам проверит, жив ли поднятый.
  Future<void> _lost(String reason, {int? code, bool kill = false}) async {
    if (_stopped || _raising) {
      return;
    }
    final EyeLink? link = _link;
    if (link == null) {
      return;
    }
    _link = null;
    _watch = null;
    _generation++;
    if (!session.recording) {
      // Запись уже остановлена (проверка в конце): поднимать некого —
      // проверка кончится отказом, и спутник закроется.
      if (kill) {
        await link.kill();
      }
      return;
    }
    // Калибровка шла на нём: попытка прервана, экран скажет почему.
    _run?.cancel();
    _log(SnoEventType.eyeLost, <String, Object?>{
      'reason': reason,
      'code': ?code,
    });
    if (kill) {
      await link.kill();
    }
    await _restart();
  }

  /// Поднимает спутник заново, пока он не поднимется или не кончатся
  /// попытки: после [kEyeRestarts] — `eye.gaveup`, и запись идёт без
  /// взгляда.
  Future<void> _restart() async {
    while (!_stopped) {
      if (info.restarts >= kEyeRestarts) {
        info.gaveUp = true;
        _log(SnoEventType.eyeGaveUp, <String, Object?>{
          'restarts': info.restarts,
        });
        _stopTimers();
        _run?.cancel();
        if (!_gazeOn &&
            _phase != EyeRecordingPhase.studying &&
            _phase != EyeRecordingPhase.done) {
          // Калибровка не кончилась — изучение без взгляда.
          info.reason = 'gave_up';
          _beginWithout();
        }
        unawaited(tracker._store());
        return;
      }
      info.restarts++;
      if (await _raise(first: false) == _Raised.up) {
        unawaited(tracker._store());
        if (_phase == EyeRecordingPhase.calibrating) {
          // Попытка шла на прежнем спутнике — её итог «прервана».
          _changed();
        }
        return;
      }
    }
  }

  void _stopTimers() {
    _stopTick?.call();
    _stopTick = null;
    _stopSync?.call();
    _stopSync = null;
  }

  /// Изучение началось без айтрекера (ждало дольше
  /// [kStudyHoldLimit]): калибровка закрывается без взгляда.
  Future<void> studyStartedAside() async {
    if (_phase == EyeRecordingPhase.studying ||
        _phase == EyeRecordingPhase.done ||
        _stopped) {
      return;
    }
    _log(SnoEventType.eyeSkip, <String, Object?>{
      'by': 'limit',
      'write': false,
    });
    info.reason = 'limit';
    _run?.cancel();
    final EyeLink? link = _link;
    _link = null;
    _generation++;
    _stopTimers();
    if (link != null) {
      await link.close();
    }
    _set(EyeRecordingPhase.done);
    unawaited(tracker._store());
  }

  /// Запись остановлена (SNO-F-EYE-06): шло изучение со взглядом — точки
  /// проверки в конце, потом спутник дописывает файлы и закрывается, и
  /// окно возвращается. Иначе — сразу закрытие.
  Future<void> finish() async {
    if (_stopped) {
      return;
    }
    // Калибровка, которую застала остановка, — прервана.
    _run?.cancel();
    final EyeLink? link = _link;
    final EyeScreen? screen = _screen;
    if (_gazeOn && link != null && !link.exited && screen != null) {
      await _endCheck(link, screen);
    } else if (!_gazeOn && info.reason == null) {
      // Остановлена до начала изучения — взгляда в записи нет.
      info.reason = 'stopped';
    }
    await _close();
  }

  Future<void> _endCheck(EyeLink link, EyeScreen screen) async {
    const int n = 1;
    _checkRun?.dispose();
    final EyeCheckRun current = EyeCheckRun(
      link: link,
      qpc: tracker._qpc,
      screen: screen,
      frameShown: _shown,
      n: n,
      seed: _seed,
      intro: kEndCheckIntro,
    )..onTarget = _targetSent;
    _checkRun = current;
    info.endCheck = <String, Object?>{'started': true, 'done': false};
    unawaited(tracker._store());
    await session.logAfter(
      SnoEventType.eyeEndcheckStart,
      data: <String, Object?>{'n': n, 'seed': _seed},
    );
    _set(EyeRecordingPhase.endCheck);
    final EyeCheckOutcome result = await current.run();
    final EyeAccuracy? accuracy = result.accuracy;
    final Object? start = info.calibration?['accuracy_deg'];
    final double? startDeg = start is num ? start.toDouble() : null;
    final Map<String, Object?> data;
    if (_skipped) {
      data = <String, Object?>{'skipped': true};
    } else if (accuracy != null) {
      final double? acc = accuracy.accuracyDeg;
      data = <String, Object?>{
        'accuracy_deg': acc,
        'accuracy_cm': accuracy.accuracyCm,
        'worst_deg': accuracy.worstDeg,
        'start_deg': startDeg,
        if (acc != null && startDeg != null)
          'drift_deg': double.parse((acc - startDeg).toStringAsFixed(3)),
        'variants': accuracy.variants,
      };
    } else {
      data = <String, Object?>{
        'done': false,
        'error': result.error?.code ?? 'cancelled',
      };
    }
    info.endCheck = data;
    await session.logAfter(SnoEventType.eyeEndcheckResult, data: data);
  }

  /// Спутник дописывает файлы и закрывается, окно возвращается; поток
  /// взгляда перечитан с диска и сверен сам с собой.
  Future<void> _close() async {
    if (_stopped) {
      return;
    }
    final EyeLink? link = _link;
    final bool hadGaze = _gazeOn;
    Map<String, Object?>? summary;
    if (link != null && !link.exited && _cameraOpen) {
      try {
        summary = await link.closeCamera();
      } on EyeError {
        summary = null;
      }
    }
    _stopped = true;
    _generation++;
    _release();
    _stopTimers();
    _run?.cancel();
    _checkRun?.cancel();
    await _windowChanges?.cancel();
    _windowChanges = null;
    _link = null;
    await Future.wait<void>(<Future<void>>[
      if (link != null) link.close(),
      tracker.window.unlock(),
    ]);
    if (hadGaze) {
      info.summary = _brief(summary);
      final List<int>? bytes = await session.streamBytes(kGazeFile);
      if (bytes != null) {
        info.check = checkJournal(bytes, key: 'n');
        info.validShare = gazeValidShare(bytes);
      }
      final Map<String, Object?> closed = <String, Object?>{
        if (summary != null) 'summary': info.summary,
        'segments': info.segments,
        'valid_share': info.validShare,
        if (info.check != null) 'check': info.check!.toJson(),
      };
      await session.logAfter(SnoEventType.eyeClosed, data: closed);
    }
    _gazeOn = false;
    _set(EyeRecordingPhase.done);
    session.infoChanged();
  }

  /// Итог спутника коротко — для сведений записи.
  static Map<String, Object?>? _brief(Map<String, Object?>? summary) {
    if (summary == null) {
      return null;
    }
    final Object? gaze = summary['gaze'];
    return <String, Object?>{
      for (final String key in const <String>[
        'frames',
        'ok',
        'face',
        'dropped',
        'lost',
        'seg',
        'satellite',
      ])
        if (summary.containsKey(key)) key: summary[key],
      if (gaze is Map<String, Object?>) 'gaze': gaze,
    };
  }

  /// Снимает всё сразу, без проверки в конце: айтрекер закрывают, новая
  /// запись или приложение уходит.
  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _generation++;
    _release();
    _stopTimers();
    _run?.cancel();
    _checkRun?.cancel();
    await _windowChanges?.cancel();
    _windowChanges = null;
    final EyeLink? link = _link;
    _link = null;
    await Future.wait<void>(<Future<void>>[
      if (link != null) link.close(),
      tracker.window.unlock(),
    ]);
    _set(EyeRecordingPhase.done);
  }

  @override
  void dispose() {
    _quiet = true;
    _run?.dispose();
    _checkRun?.dispose();
    super.dispose();
  }
}

/// Доля годных строк потока взгляда [bytes] (SNO-F-EYE-02): строки, где
/// спутник написал `"ok":true`. Пустой поток — `null`.
double? gazeValidShare(List<int> bytes) {
  const int newline = 0x0A;
  final int end = bytes.lastIndexOf(newline);
  if (end < 0) {
    return null;
  }
  int lines = 0;
  int ok = 0;
  for (final String line in const LineSplitter().convert(
    utf8.decode(bytes.sublist(0, end), allowMalformed: true),
  )) {
    if (line.trim().isEmpty) {
      continue;
    }
    lines++;
    if (line.contains('"ok":true')) {
      ok++;
    }
  }
  return lines == 0 ? null : double.parse((ok / lines).toStringAsFixed(4));
}
