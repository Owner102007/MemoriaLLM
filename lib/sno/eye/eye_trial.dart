/// «Проверка айтрекера» — экспериментатор смотрит, как айтрекер видит
/// его самого, до прихода участника (SNO-F-EYE-03; калибровка —
/// SNO-F-EYE-01, SNO-ALG-EYE-02).
///
/// Два вида:
///
/// * **быстро** — самопроверка, девять точек и живой взгляд поверх
///   приложения; ничего не хранится;
/// * **пробная полная калибровка** — ровно то, что пройдёт участник:
///   самопроверка, 13 точек, слежение, 9 точек проверки, итог и приём;
///   потом живой взгляд и две минуты свободного просмотра. Файлы — в
///   папку стенда `Стенд/<дата-время>/` в папке данных приложения: по
///   ним меряются ворота Г2.
///
/// Окно на всё время проверки стоит на мониторе места записи под
/// замком: углы считаются по размеру этого монитора. В «Записи»
/// проверка не пишет ничего.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'eye_calibration.dart';
import 'eye_calibration_run.dart';
import 'eye_link.dart';
import 'eye_place.dart';
import 'eye_protocol.dart';
import 'eye_tracker.dart';
import 'eye_window.dart';

/// Длина свободного просмотра после пробной полной калибровки.
const Duration kFreeViewing = Duration(minutes: 2);

/// Длина замера самопроверки перед калибровкой, секунд (и прогрева).
const double kTrialCheckSeconds = 3;

/// Прогрев камеры перед замером самопроверки, секунд.
const double kTrialCheckWarmup = 1;

/// За какое время считается доля кадров с лицом в углу живой точки.
const Duration kFaceWindow = Duration(seconds: 10);

/// Где проверка сейчас.
enum EyeTrialPhase {
  /// Выбор вида.
  choose,

  /// Окно на монитор, запуск спутника, самопроверка, камера.
  starting,

  /// Проверка остановилась: сказано почему.
  failed,

  /// Идёт калибровка.
  calibrating,

  /// Итог попытки.
  result,

  /// Живой взгляд поверх приложения.
  live,

  /// Пробная полная калибровка закончена, файлы в папке стенда.
  finished,

  /// Проверка закрыта.
  closed,
}

/// Одна «Проверка айтрекера».
class EyeTrial extends ChangeNotifier {
  /// Создаёт проверку места [place]. [seed] — зерно порядка точек:
  /// кода участника нет, и оно случайное.
  EyeTrial({
    required this.tracker,
    required this.place,
    int? seed,
    DateTime Function()? now,
  }) : seed = seed ?? math.Random().nextInt(1 << 32),
       _now = now ?? DateTime.now;

  /// Айтрекер: спутник, окно, папки.
  final EyeTracker tracker;

  /// Место записи, на котором идёт проверка.
  final EyePlace place;

  /// Зерно порядка точек.
  final int seed;

  final DateTime Function() _now;

  EyeTrialPhase _phase = EyeTrialPhase.choose;
  EyeCalibrationKind? _kind;
  EyeLink? _link;
  StreamSubscription<EyeWindowLock>? _windowChanges;
  Timer? _freeTimer;

  /// Экран калибровки, который сейчас на экране: он сообщает, что кадр с
  /// точкой отрисован, и знает размер окна. Экран уходит — поле
  /// очищается, и точка уходит спутнику по QPC без ожидания кадра.
  EyeFrameShown? frameShown;

  /// Размер окна в логических пикселях — от экрана, который на экране.
  Size Function()? windowSize;

  /// Номер сегмента файлов стенда: камера, открытая заново после смены
  /// окна, пишет в следующий.
  int _segment = 0;

  /// Окно сменилось, пока калибровки не было (итог, живой взгляд):
  /// следующая попытка начинается с камеры, открытой заново.
  bool _stale = false;

  /// Камеру открывают заново; пока это так, новые смены окна только
  /// отмечаются — открытие повторится после текущего.
  Future<void>? _reopening;
  bool _reopenAgain = false;

  /// Проверка остановилась, когда экрана проверки уже не было (живой
  /// взгляд, свободный просмотр): об этом говорит панель над приложением.
  bool failedLive = false;
  double _dpr = 1;
  EyeScreen? _screen;

  /// Попытка, которая сейчас идёт или кончилась.
  EyeCalibrationRun? run;

  /// Номер попытки.
  int attempt = 0;

  /// Что идёт сейчас словами (пока запускается).
  String? stage;

  /// Почему проверка остановилась.
  String? failure;

  /// Самопроверка перед калибровкой.
  EyeCheck? check;

  /// Итог последней попытки.
  EyeAttemptOutcome? outcome;

  /// Папка стенда пробной полной калибровки; `null` — у быстрой её нет.
  String? standFolder;

  /// Последняя точка взгляда.
  EyeGaze? gaze;

  /// Сколько осталось свободного просмотра.
  Duration? freeLeft;

  /// Сводка спутника о записанных файлах.
  Map<String, Object?>? summary;

  final ListQueue<EyeGaze> _recent = ListQueue<EyeGaze>();

  /// Где проверка сейчас.
  EyeTrialPhase get phase => _phase;

  /// Какой вид выбран.
  EyeCalibrationKind? get kind => _kind;

  /// Видна ли проверка панелью над приложением, а не своим экраном:
  /// живой взгляд, конец свободного просмотра или отказ во время них.
  bool get overApp =>
      _phase == EyeTrialPhase.live ||
      _phase == EyeTrialPhase.finished ||
      (_phase == EyeTrialPhase.failed && failedLive);

  /// Окно, в котором стоят точки.
  EyeScreen? get screen => _screen;

  /// Сколько попыток ещё можно сделать у полной калибровки.
  bool get canRetry =>
      _kind == EyeCalibrationKind.quick ||
      (outcome?.noFace ?? false) ||
      attempt < kCalibrationAttempts;

  /// Кадров в секунду за последнюю секунду живой точки.
  double get fps {
    final EyeGaze? last = gaze;
    if (last == null) {
      return 0;
    }
    return _recent
        .where((EyeGaze g) => last.qpcUs - g.qpcUs < 1000000)
        .length
        .toDouble();
  }

  /// Доля годных кадров за последние [kFaceWindow].
  double? get faceShare {
    if (_recent.isEmpty) {
      return null;
    }
    return _recent.where((EyeGaze g) => g.ok).length / _recent.length;
  }

  /// Точность, которую показывают в углу: у полной — проверка, у быстрой
  /// — ошибка «без одной точки».
  double? get accuracyDeg =>
      outcome?.validation?.accuracyDeg ?? outcome?.fit?.cvDeg;

  void _set(EyeTrialPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// Начинает проверку вида [kind]; [dpr] — масштаб Windows, пока окно
  /// не встало на монитор.
  Future<void> start(EyeCalibrationKind kind, {double dpr = 1}) async {
    if (_phase != EyeTrialPhase.choose && _phase != EyeTrialPhase.failed) {
      return;
    }
    _kind = kind;
    _dpr = dpr;
    failure = null;
    check = null;
    outcome = null;
    attempt = 0;
    stage = 'Окно встаёт на монитор места записи…';
    _set(EyeTrialPhase.starting);
    try {
      await _begin(kind);
    } on EyeError catch (e) {
      await _fail(describeEyeError(e));
    } on FileSystemException catch (e) {
      await _fail('Папка стенда не создалась: ${e.message}');
    }
  }

  Future<void> _begin(EyeCalibrationKind kind) async {
    final EyeWindowLock? lock = await tracker.window.lock(place.monitor);
    if (_phase == EyeTrialPhase.closed) {
      // Проверку закрыли, пока окно вставало на монитор: замок снимается
      // здесь — `close` снимал ещё не поставленный.
      await tracker.window.unlock();
      return;
    }
    if (lock != null) {
      _dpr = lock.dpr;
    }
    _windowChanges ??= tracker.window.changes.listen(_windowChanged);
    stage = 'Запускаю айтрекер…';
    notifyListeners();
    final EyeLink link = await tracker.connect();
    if (_phase == EyeTrialPhase.closed) {
      await link.close();
      return;
    }
    _link = link
      ..onGaze = _onGaze
      ..onError = (EyeError e) {
        if (e.command == 'record') {
          unawaited(_fail(describeEyeError(e)));
        }
      };
    unawaited(
      link.exitCode.then((int code) {
        if (!link.closing && _phase != EyeTrialPhase.closed) {
          unawaited(_fail('Айтрекер закрылся (код $code)'));
        }
      }),
    );
    String? folder;
    if (kind == EyeCalibrationKind.full) {
      folder = await tracker.standFolder(_now());
      standFolder = folder;
      if (folder != null) {
        await tracker.files.writeText(
          p.join(folder, 'place.json'),
          const JsonEncoder.withIndent(' ').convert(place.toJson()),
        );
      }
    }
    // У быстрой проверки файлов нет: её самопроверка не ложится поверх
    // самопроверки места записи в `eye/` (место на диске меряется у
    // самого спутника).
    stage = 'Самопроверка…';
    notifyListeners();
    final EyeCheck checked = await link.selfcheck(
      camera: place.camera,
      seconds: kTrialCheckSeconds,
      warmup: kTrialCheckWarmup,
      dir: folder,
    );
    check = checked;
    if (_phase == EyeTrialPhase.closed) {
      return;
    }
    if (checked.verdict == EyeVerdict.fail) {
      await _fail('Самопроверка: не годится');
      return;
    }
    stage = 'Открываю камеру…';
    notifyListeners();
    final EyeScreen screen = _screenNow();
    _screen = screen;
    await link.open(
      screen: screen,
      distanceMm: place.distanceMm,
      camera: place.camera,
      dir: kind == EyeCalibrationKind.full ? folder : null,
      write: kind == EyeCalibrationKind.full && folder != null,
    );
    if (_phase == EyeTrialPhase.closed) {
      return;
    }
    await _calibrate(next: true);
  }

  /// Окно в логических пикселях и миллиметрах: размер монитора в
  /// пикселях — из места записи, миллиметры — по его пикселям на мм.
  EyeScreen _screenNow() {
    final Size size = windowSize?.call() ?? Size.zero;
    final double mmPerPx = 1 / place.pxPerMm;
    return EyeScreen(
      width: size.width,
      height: size.height,
      widthMm: size.width * _dpr * mmPerPx,
      heightMm: size.height * _dpr * mmPerPx,
    );
  }

  Future<void> _calibrate({required bool next}) async {
    final EyeLink? link = _link;
    final EyeScreen? screen = _screen;
    final EyeCalibrationKind? kind = _kind;
    if (link == null || screen == null || kind == null) {
      return;
    }
    if (next) {
      attempt++;
    }
    run?.dispose();
    final EyeCalibrationRun current = EyeCalibrationRun(
      link: link,
      qpc: tracker.qpc,
      kind: kind,
      attempt: attempt,
      seed: (seed + attempt) & 0xFFFFFFFF,
      screen: screen,
      distanceMm: place.distanceMm,
      frameShown: _shownOnScreen,
    );
    run = current;
    outcome = null;
    _set(EyeTrialPhase.calibrating);
    final EyeAttemptOutcome result = await current.run();
    if (!identical(run, current) || _phase == EyeTrialPhase.closed) {
      return;
    }
    if (result.cancelled) {
      return;
    }
    final EyeError? error = result.error;
    if (error != null) {
      await _fail(describeEyeError(error));
      return;
    }
    outcome = result;
    if (kind == EyeCalibrationKind.quick && !result.noFace) {
      await goLive();
      return;
    }
    _set(EyeTrialPhase.result);
  }

  /// Ещё одна попытка: после «не видно лица» — та же, иначе следующая.
  Future<void> retry() async {
    if (_phase != EyeTrialPhase.result || !canRetry) {
      return;
    }
    final bool sameAttempt = outcome?.noFace ?? false;
    if (_stale) {
      await _reopen(next: !sameAttempt);
      return;
    }
    await _calibrate(next: !sameAttempt);
  }

  /// Быстрая калибровка ещё раз — из живой точки.
  Future<void> again() async {
    final EyeLink? link = _link;
    if (link == null ||
        (_phase != EyeTrialPhase.live && _phase != EyeTrialPhase.result)) {
      return;
    }
    if (_phase == EyeTrialPhase.live) {
      try {
        await link.live(on: false);
      } on EyeError {
        // Живая точка не выключилась — калибровка выключит её сама.
      }
    }
    _recent.clear();
    gaze = null;
    if (_stale) {
      await _reopen(next: true);
      return;
    }
    await _calibrate(next: true);
  }

  /// Живой взгляд поверх приложения; у пробной полной — с отсчётом
  /// свободного просмотра.
  Future<void> goLive() async {
    final EyeLink? link = _link;
    if (link == null || outcome?.fit == null) {
      return;
    }
    try {
      await link.live(on: true);
    } on EyeError catch (e) {
      await _fail(describeEyeError(e));
      return;
    }
    _recent.clear();
    gaze = null;
    if (_kind == EyeCalibrationKind.full) {
      freeLeft = kFreeViewing;
      _freeTimer?.cancel();
      _freeTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        final Duration left =
            (freeLeft ?? Duration.zero) - const Duration(seconds: 1);
        freeLeft = left.isNegative ? Duration.zero : left;
        notifyListeners();
        if (left <= Duration.zero) {
          t.cancel();
          unawaited(_finish());
        }
      });
    }
    _set(EyeTrialPhase.live);
  }

  /// Свободный просмотр кончился: камера закрыта, файлы дописаны.
  Future<void> _finish() async {
    final EyeLink? link = _link;
    if (link == null || _phase != EyeTrialPhase.live) {
      return;
    }
    try {
      await link.live(on: false);
      summary = await link.closeCamera();
    } on EyeError catch (e) {
      await _fail(describeEyeError(e));
      return;
    }
    gaze = null;
    _set(EyeTrialPhase.finished);
  }

  Future<int> _shownOnScreen() {
    final EyeFrameShown? shown = frameShown;
    return shown == null ? Future<int>.value(tracker.qpc.nowUs()) : shown();
  }

  /// Заканчивает свободный просмотр раньше срока: файлы дописаны.
  Future<void> finishEarly() async {
    _freeTimer?.cancel();
    await _finish();
  }

  void _onGaze(EyeGaze g) {
    if (_phase != EyeTrialPhase.live) {
      return;
    }
    gaze = g;
    _recent.addLast(g);
    while (_recent.isNotEmpty &&
        g.qpcUs - _recent.first.qpcUs > kFaceWindow.inMicroseconds) {
      _recent.removeFirst();
    }
    notifyListeners();
  }

  void _windowChanged(EyeWindowLock lock) {
    // Окно сменило размер или монитор: точки стояли бы не там, а спутник
    // считает углы по окну из `open`. Посреди калибровки — попытка
    // заново и не в счёт (SNO-ALG-EYE-02, краевые случаи); на итоге и в
    // живом взгляде — следующая попытка начнётся с камеры, открытой
    // заново.
    _dpr = lock.dpr;
    if (_phase == EyeTrialPhase.calibrating) {
      run?.cancel();
      unawaited(_reopen(next: false));
    } else if (_phase == EyeTrialPhase.result || _phase == EyeTrialPhase.live) {
      _stale = true;
    }
  }

  /// Открывает камеру заново под новое окно и начинает попытку. Смены
  /// окна, пришедшие, пока камеру открывают, не открывают её второй
  /// раз параллельно, а повторяют открытие после текущего.
  Future<void> _reopen({required bool next}) async {
    if (_reopening != null) {
      _reopenAgain = true;
      return _reopening;
    }
    final Future<void> going = _reopenLoop(next: next);
    _reopening = going;
    try {
      await going;
    } finally {
      _reopening = null;
    }
  }

  Future<void> _reopenLoop({required bool next}) async {
    bool first = true;
    do {
      _reopenAgain = false;
      final EyeLink? link = _link;
      if (link == null || _phase == EyeTrialPhase.closed) {
        return;
      }
      final bool write =
          _kind == EyeCalibrationKind.full && standFolder != null;
      try {
        await link.closeCamera();
        // Размер окна — уже новый: пока закрывалась камера, кадр с новым
        // окном успел лечь.
        final EyeScreen screen = _screenNow();
        _screen = screen;
        await link.open(
          screen: screen,
          distanceMm: place.distanceMm,
          camera: place.camera,
          dir: write ? standFolder : null,
          write: write,
          seg: write ? ++_segment : null,
        );
      } on EyeError catch (e) {
        await _fail(describeEyeError(e));
        return;
      }
      _stale = false;
      if (!_reopenAgain) {
        unawaited(_calibrate(next: first && next));
        return;
      }
      first = false;
    } while (_phase != EyeTrialPhase.closed);
  }

  Future<void> _fail(String text) async {
    if (_phase == EyeTrialPhase.closed) {
      return;
    }
    run?.cancel();
    _freeTimer?.cancel();
    failedLive =
        _phase == EyeTrialPhase.live || _phase == EyeTrialPhase.finished;
    gaze = null;
    failure = text;
    final EyeLink? link = _link;
    _link = null;
    // Сначала — на экран: закрытие связи ждёт выхода спутника.
    _set(EyeTrialPhase.failed);
    if (link != null) {
      await link.close();
    }
  }

  /// Закрывает проверку: спутник закрыт (файлы стенда он дописывает
  /// сам), окно снова обычное.
  Future<void> close() async {
    if (_phase == EyeTrialPhase.closed) {
      return;
    }
    run?.cancel();
    _freeTimer?.cancel();
    _freeTimer = null;
    _phase = EyeTrialPhase.closed;
    notifyListeners();
    unawaited(_windowChanges?.cancel());
    _windowChanges = null;
    final EyeLink? link = _link;
    _link = null;
    // Окно — первым: его возвращают сразу, а спутник выходит до двух
    // секунд.
    final Future<void> unlocked = tracker.window.unlock();
    tracker.trialClosed(this);
    await Future.wait<void>(<Future<void>>[
      unlocked,
      if (link != null) link.close(),
    ]);
  }

  @override
  void dispose() {
    run?.dispose();
    _freeTimer?.cancel();
    super.dispose();
  }
}
