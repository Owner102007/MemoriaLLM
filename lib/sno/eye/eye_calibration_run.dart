/// Одна попытка калибровки (SNO-F-EYE-01, SNO-ALG-EYE-02): точки по
/// одной, повтор точек без кадров, слежение, модель, точки проверки.
///
/// Попытка ведёт спутник командами и держит то, что сейчас на экране:
/// подсказку, неподвижную точку или путь движущейся. Рисует экран
/// калибровки; он же сообщает, когда кадр с точкой отрисован
/// ([EyeFrameShown]) — в этот миг по QPC точка и уходит спутнику.
///
/// Время — таймеры: в widget-тестах его двигает тест.
library;

import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import 'eye_calibration.dart';
import 'eye_link.dart';
import 'eye_protocol.dart';
import 'qpc_clock.dart';

/// Ждёт, пока кадр с текущей точкой будет отрисован, и отвечает QPC
/// этого мига (SNO-ALG-EYE-03, шаг 9).
typedef EyeFrameShown = Future<int> Function();

/// Сколько ждать отрисовки кадра, прежде чем взять QPC без неё: экран
/// калибровки могли закрыть, а попытка не должна висеть.
const Duration kFrameShownLimit = Duration(milliseconds: 500);

/// Доля кадров с лицом, ниже которой калибровка прерывается словами
/// «Камера не видит лица» без отсчёта попытки.
const double kFaceMinShare = 0.5;

/// Чем кончилась попытка.
class EyeAttemptOutcome {
  const EyeAttemptOutcome._({
    this.fit,
    this.validation,
    this.noFace = false,
    this.error,
    this.cancelled = false,
  });

  /// Модель (и проверка у полной калибровки).
  const EyeAttemptOutcome.done(EyeFit fit, [EyeValidation? validation])
    : this._(fit: fit, validation: validation);

  /// Камера не видела лица: попытка не в счёт.
  const EyeAttemptOutcome.noFace() : this._(noFace: true);

  /// Спутник отказал.
  const EyeAttemptOutcome.failed(EyeError error) : this._(error: error);

  /// Попытку прервали.
  const EyeAttemptOutcome.cancelled() : this._(cancelled: true);

  /// Модель; `null` — до неё не дошло.
  final EyeFit? fit;

  /// Проверка; у быстрой калибровки её нет.
  final EyeValidation? validation;

  /// Камера не видела лица.
  final bool noFace;

  /// Отказ спутника.
  final EyeError? error;

  /// Прервана.
  final bool cancelled;
}

/// Одна попытка калибровки.
class EyeCalibrationRun extends ChangeNotifier {
  /// Создаёт попытку. [seed] — зерно порядка точек; [screen] —
  /// окно, на котором они рисуются.
  EyeCalibrationRun({
    required EyeLink link,
    required QpcClock qpc,
    required this.kind,
    required this.attempt,
    required this.seed,
    required this.screen,
    required this.distanceMm,
    required EyeFrameShown frameShown,
  }) : _link = link,
       _qpc = qpc,
       _frameShown = frameShown;

  final EyeLink _link;
  final QpcClock _qpc;
  final EyeFrameShown _frameShown;

  /// Какая калибровка.
  final EyeCalibrationKind kind;

  /// Номер попытки.
  final int attempt;

  /// Зерно порядка точек.
  final int seed;

  /// Окно, в котором стоят точки.
  final EyeScreen screen;

  /// Расстояние до экрана, мм.
  final int distanceMm;

  bool _cancelled = false;
  final Set<Completer<void>> _pauses = <Completer<void>>{};
  final Set<Timer> _timers = <Timer>{};

  /// Подсказка поверх экрана; `null` — нет.
  String? hint;

  /// Неподвижная точка на экране; `null` — нет.
  EyeTargetPoint? point;

  /// Путь движущейся точки; `null` — слежения сейчас нет.
  PursuitPath? pursuit;

  /// Номер показа: растёт с каждой новой точкой — кольцо сжимается
  /// заново.
  int shown = 0;

  /// Сколько точек уже отстояло своё.
  int done = 0;

  /// Прервана ли попытка.
  bool get cancelled => _cancelled;

  /// Прерывает попытку: таймеры сняты, `run` вернёт «прервано».
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final Timer timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    for (final Completer<void> pause in _pauses) {
      if (!pause.isCompleted) {
        pause.complete();
      }
    }
    _pauses.clear();
  }

  Future<void> _pause(Duration time) {
    if (_cancelled) {
      return Future<void>.value();
    }
    final Completer<void> gate = Completer<void>();
    _pauses.add(gate);
    late final Timer timer;
    timer = Timer(time, () {
      _timers.remove(timer);
      _pauses.remove(gate);
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
    _timers.add(timer);
    return gate.future;
  }

  void _show({String? hint, EyeTargetPoint? point, PursuitPath? pursuit}) {
    // Прерванная попытка экран больше не трогает: её место уже заняла
    // следующая.
    if (_cancelled) {
      return;
    }
    this.hint = hint;
    this.point = point;
    this.pursuit = pursuit;
    shown++;
    notifyListeners();
  }

  Future<int> _onScreen() async {
    try {
      return await _frameShown().timeout(kFrameShownLimit);
    } on TimeoutException {
      return _qpc.nowUs();
    }
  }

  Future<void> _point(EyeTargetPoint p, Duration time) async {
    if (_cancelled) {
      return;
    }
    _show(point: p);
    final int qpc = await _onScreen();
    if (_cancelled) {
      return;
    }
    final Offset at = p.at(screen.size);
    _link.target(
      phase: p.phase.wire,
      qpcUs: qpc,
      id: p.id,
      x: at.dx,
      y: at.dy,
    );
    await _pause(time);
    done++;
  }

  void _off() {
    if (_cancelled) {
      return;
    }
    _link.target(phase: 'off', qpcUs: _qpc.nowUs());
  }

  /// Ведёт попытку до конца.
  Future<EyeAttemptOutcome> run() async {
    try {
      return await _run();
    } on EyeError catch (e) {
      if (_cancelled) {
        return const EyeAttemptOutcome.cancelled();
      }
      if (e.code == 'no_face') {
        return const EyeAttemptOutcome.noFace();
      }
      return EyeAttemptOutcome.failed(e);
    }
  }

  Future<EyeAttemptOutcome> _run() async {
    await _link.calibrate(attempt: attempt, kind: kind.wire);
    _show(hint: 'Смотрите на точку. Нажимать ничего не нужно.');
    await _pause(kIntroTime);
    final List<EyeTargetPoint> points = calibrationSequence(kind, seed);
    for (final EyeTargetPoint p in points) {
      await _point(p, kCalibrationPointTime);
    }
    _off();
    if (_cancelled) {
      return const EyeAttemptOutcome.cancelled();
    }
    final EyeSamples samples = await _link.samples();
    final double? face = samples.face;
    if (face != null && face < kFaceMinShare) {
      return const EyeAttemptOutcome.noFace();
    }
    // Точка без кадров — моргнули, отвели глаза — повторяется в конце
    // один раз.
    final List<EyeTargetPoint> again = <EyeTargetPoint>[
      for (final EyeTargetPoint p in points)
        if (samples.short.contains(p.id)) p,
    ];
    for (final EyeTargetPoint p in again) {
      await _point(p, kCalibrationPointTime);
    }
    if (again.isNotEmpty) {
      _off();
    }
    if (kind == EyeCalibrationKind.full) {
      _show(hint: 'Теперь следите глазами за точкой');
      await _pause(kIntroTime);
      if (_cancelled) {
        return const EyeAttemptOutcome.cancelled();
      }
      final PursuitPath path = pursuitPathFor(screen, distanceMm);
      _show(pursuit: path);
      final int qpc = await _onScreen();
      if (_cancelled) {
        return const EyeAttemptOutcome.cancelled();
      }
      _link.target(
        phase: EyeTargetPhase.pursuit.wire,
        qpcUs: qpc,
        id: 'pursuit',
        x: path.cx,
        y: path.cy,
        path: path.toJson(),
      );
      await _pause(kPursuitTime);
      _off();
    }
    if (_cancelled) {
      return const EyeAttemptOutcome.cancelled();
    }
    _show(hint: 'Считаю…');
    final EyeFit fit = await _link.fit();
    if (_cancelled) {
      return const EyeAttemptOutcome.cancelled();
    }
    if (kind == EyeCalibrationKind.quick) {
      _show();
      return EyeAttemptOutcome.done(fit);
    }
    for (final EyeTargetPoint p in validationSequence(seed)) {
      await _point(p, kValidationPointTime);
    }
    _off();
    if (_cancelled) {
      return const EyeAttemptOutcome.cancelled();
    }
    _show(hint: 'Считаю…');
    final EyeValidation validation = await _link.validate();
    _show();
    return EyeAttemptOutcome.done(fit, validation);
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

/// Окно спутника — размер в логических пикселях для точек.
extension EyeScreenSize on EyeScreen {
  /// Размер окна.
  Size get size => Size(width, height);
}
