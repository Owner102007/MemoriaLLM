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
///   перезапускает спутник, если он вышел или замолчал (до трёх раз за
///   запись), и пишет всё это в журнал событиями `eye.*`.
///
/// В этом шаге (ET-02) спутник во время записи файлов взгляда не пишет:
/// команда `open`, папка `eye/` в архиве и короткая самопроверка перед
/// записью придут с ET-06, вместе с калибровкой. Поэтому `present` в
/// сведениях записи — `false`.
///
/// Время, таймеры и ожидание подменяются в тестах.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/settings/app_settings.dart';
import '../recording/event.dart';
import '../recording/session.dart';
import '../settings_keys.dart';
import 'eye_link.dart';
import 'eye_place.dart';
import 'eye_process.dart';
import 'eye_protocol.dart';
import 'eye_timing.dart';
import 'eye_window.dart';
import 'qpc_clock.dart';

/// Таймер: зовёт [onTick] каждые [every]; возвращает, чем его снять.
typedef EyeTicker =
    void Function() Function(Duration every, void Function() onTick);

void Function() _timerTicker(Duration every, void Function() onTick) {
  final Timer timer = Timer.periodic(every, (Timer _) => onTick());
  return timer.cancel;
}

int Function() _stopwatchMs() {
  final Stopwatch watch = Stopwatch()..start();
  return () => watch.elapsedMilliseconds;
}

/// Сколько раз пробовать запуск, если прежний спутник ещё держит имя
/// экземпляра (`already_running`): он выходит за две секунды после
/// закрытия «Места записи».
const int kAlreadyRunningTries = 5;

/// Сколько ждать между такими попытками.
const Duration kAlreadyRunningPause = Duration(milliseconds: 700);

/// Что известно о спутнике идущей записи — для сведений записи.
class EyeRunInfo {
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

  /// Новая запись — сведения с чистого листа.
  void reset() {
    configured = false;
    unavailable = null;
    hello = null;
    window = null;
    restarts = 0;
    gaveUp = false;
  }

  /// Как запись спутника выглядит в `recording.json`.
  Map<String, Object?> toJson(EyePlace? place) => <String, Object?>{
    // Файлов взгляда в записи нет до ET-06: спутник жив, но не пишет.
    'present': false,
    'configured': configured,
    if (place != null) 'place': place.toJson(),
    if (unavailable != null) 'unavailable': unavailable,
    if (hello != null) 'satellite': hello!.toJson(),
    if (window != null) 'window': window!.toJson(),
    'restarts': restarts,
    'gave_up': gaveUp,
  };
}

/// Айтрекер приложения.
class EyeTracker extends ChangeNotifier {
  /// Создаёт айтрекер.
  EyeTracker({
    required AppSettingsRepository settings,
    required EyeLauncher launch,
    required QpcClock qpc,
    required this.window,
    this.recordsFolder,
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

  /// Папка записей: по ней самопроверка меряет место на диске.
  final Future<String?> Function()? recordsFolder;

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
  bool _disposed = false;

  /// Место записи; `null` — не задано или ещё не прочитано.
  EyePlace? get place => _place;

  /// Прочитано ли место записи.
  bool get placeLoaded => _placeLoaded;

  /// Сведения о спутнике последней записи.
  EyeRunInfo get info => _info;

  /// Часы QPC — для экрана, который сверяет их сам.
  QpcClock get qpc => _qpc;

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
  /// раз. Любой другой отказ — [EyeError] сразу.
  Future<(EyeLink, EyeHello)> _open() async {
    EyeError? last;
    for (int attempt = 0; attempt < kAlreadyRunningTries; attempt++) {
      if (attempt > 0) {
        await _wait(kAlreadyRunningPause);
      }
      final EyeLink link;
      try {
        link = await EyeLink.start(_launch, qpc: _qpc);
      } on EyeError {
        rethrow;
      } on Object catch (e) {
        throw EyeError('start', '$e');
      }
      try {
        final EyeHello hello = await link.hello(build: build, branch: branch);
        return (link, hello);
      } on EyeError catch (e) {
        await link.close();
        if (e.code != 'already_running') {
          rethrow;
        }
        last = e;
      } on Object catch (e) {
        await link.close();
        throw EyeError('start', '$e');
      }
    }
    throw last ?? const EyeError('already_running', 'Спутник уже запущен');
  }

  /// Подключает айтрекер к записи: старт записи поднимает спутник,
  /// остановка — опускает.
  void attach(RecordingSession session) {
    _session?.removeListener(_sessionChanged);
    _session = session;
    _phase = session.phase;
    session.addListener(_sessionChanged);
    session.addInfoPart('eye_tracker', () => _info.toJson(_place));
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
      _info.reset();
      unawaited(_startRun(session));
    } else if (now != RecordingPhase.recording &&
        was == RecordingPhase.recording) {
      unawaited(_stopRun());
    }
  }

  Future<void> _startRun(RecordingSession session) async {
    await _run?.stop();
    final _EyeRun run = _EyeRun(this, session);
    _run = run;
    await run.start();
  }

  Future<void> _stopRun() async {
    final _EyeRun? run = _run;
    _run = null;
    await run?.stop();
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
    unawaited(_stopRun());
    super.dispose();
  }
}

/// Спутник одной записи: от старта записи до её остановки.
class _EyeRun {
  _EyeRun(this.tracker, this.session);

  final EyeTracker tracker;
  final RecordingSession session;
  EyeLink? _link;
  SilenceWatch? _watch;
  void Function()? _stopTick;
  void Function()? _stopSync;
  StreamSubscription<EyeWindowLock>? _windowChanges;
  bool _stopped = false;
  bool _restarting = false;
  bool _syncing = false;

  /// Номер подъёма спутника: запоздавшие сигналы прежнего — не в счёт.
  int _generation = 0;

  bool get alive => !_stopped && _link != null && !_link!.exited;

  EyeRunInfo get info => tracker._info;

  void _log(SnoEventType type, Map<String, Object?> data) {
    if (!_stopped) {
      session.log(type, data: data);
    }
  }

  Future<void> start() async {
    final EyeRunInfo info = tracker._info;
    final EyePlace? place = await tracker.loadPlace();
    if (_stopped) {
      return;
    }
    if (place == null) {
      info.unavailable = 'not_configured';
      _log(SnoEventType.eyeUnavailable, <String, Object?>{
        'reason': 'not_configured',
        'text': 'Айтрекер не настроен — запись идёт без взгляда',
      });
      return;
    }
    info.configured = true;
    // SNO-F-EYE-07: окно — на весь монитор места записи, сразу.
    final EyeWindowLock? lock = await tracker.window.lock(place.monitor);
    if (_stopped) {
      await tracker.window.unlock();
      return;
    }
    info.window = lock;
    _log(SnoEventType.eyeWindow, <String, Object?>{
      'locked': lock != null,
      if (lock != null) ...lock.toJson(),
      'wanted': place.monitor,
    });
    _windowChanges = tracker.window.changes.listen((EyeWindowLock changed) {
      info.window = changed;
      _log(SnoEventType.eyeWindow, <String, Object?>{
        'changed': true,
        ...changed.toJson(),
      });
    });
    await _raise(first: true);
  }

  /// Поднимает спутник: запуск, `hello`, сверка часов, таймеры.
  Future<void> _raise({required bool first}) async {
    final int generation = ++_generation;
    final int startedMs = tracker._monotonicMs();
    final (EyeLink, EyeHello) opened;
    try {
      opened = await tracker._open();
    } on EyeError catch (e) {
      if (_stopped) {
        return;
      }
      if (first) {
        info.unavailable = e.code;
        _log(SnoEventType.eyeUnavailable, <String, Object?>{
          'reason': e.code,
          'text': describeEyeError(e),
        });
        return;
      }
      _log(SnoEventType.eyeLost, <String, Object?>{
        'reason': 'start',
        'error': e.code,
        'text': describeEyeError(e),
      });
      await _restart();
      return;
    }
    final EyeLink link = opened.$1;
    final EyeHello hello = opened.$2;
    if (_stopped) {
      await link.close();
      return;
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
      _log(SnoEventType.eyeClock, <String, Object?>{'qpc0_us': qpc, 't0': t});
    } else {
      _log(SnoEventType.eyeRestart, <String, Object?>{
        'n': info.restarts,
        'seg': info.restarts,
        'start_ms': tracker._monotonicMs() - startedMs,
      });
    }
    await _sync(kSyncRoundsOpen);
    if (_stopped || generation != _generation) {
      return;
    }
    _watch = SilenceWatch(tracker._monotonicMs());
    _stopTick ??= tracker._ticker(const Duration(seconds: 1), _tick);
    _stopSync ??= tracker._ticker(kSyncEvery, () {
      unawaited(_sync(kSyncRoundsMinute));
    });
  }

  void _tick() {
    final SilenceWatch? watch = _watch;
    if (watch == null || _stopped || _restarting) {
      return;
    }
    if (watch.tick(tracker._monotonicMs())) {
      unawaited(_lost('silent', kill: true));
    }
  }

  /// Сверка часов: [rounds] обменов и событие `eye.sync`.
  Future<void> _sync(int rounds) async {
    final EyeLink? link = _link;
    if (link == null || _stopped || _syncing || _restarting) {
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

  /// Спутник потерян: `eye.lost` и подъём заново.
  Future<void> _lost(String reason, {int? code, bool kill = false}) async {
    if (_stopped || _restarting) {
      return;
    }
    final EyeLink? link = _link;
    _link = null;
    _watch = null;
    _generation++;
    _log(SnoEventType.eyeLost, <String, Object?>{
      'reason': reason,
      if (code != null) 'code': code,
    });
    if (link != null && kill) {
      await link.kill();
    }
    await _restart();
  }

  Future<void> _restart() async {
    if (_stopped) {
      return;
    }
    if (info.restarts >= kEyeRestarts) {
      info.gaveUp = true;
      _log(SnoEventType.eyeGaveUp, <String, Object?>{
        'restarts': info.restarts,
      });
      _stopTimers();
      return;
    }
    _restarting = true;
    info.restarts++;
    try {
      await _raise(first: false);
    } finally {
      _restarting = false;
    }
  }

  void _stopTimers() {
    _stopTick?.call();
    _stopTick = null;
    _stopSync?.call();
    _stopSync = null;
  }

  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _generation++;
    _stopTimers();
    await _windowChanges?.cancel();
    _windowChanges = null;
    final EyeLink? link = _link;
    _link = null;
    await Future.wait<void>(<Future<void>>[
      if (link != null) link.close(),
      tracker.window.unlock(),
    ]);
  }
}
