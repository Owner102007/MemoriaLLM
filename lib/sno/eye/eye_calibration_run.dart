/// Одна попытка калибровки (SNO-F-EYE-01, SNO-ALG-EYE-02): точки по
/// одной, повтор точек без кадров, фаза движения головы, слежение,
/// модель, точки проверки. И проверка точности без новой калибровки
/// (BUG-60, SNO-F-EYE-03) — девять точек той моделью, что есть.
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

/// Точки на экране — общая часть попытки калибровки и проверки
/// точности: подсказка, неподвижная точка или путь движущейся, таймеры и
/// отправка точки спутнику после отрисовки её кадра.
abstract class EyeTargetsRun extends ChangeNotifier {
  /// Создаёт показ точек в окне [screen].
  EyeTargetsRun({
    required EyeLink link,
    required QpcClock qpc,
    required this.screen,
    required EyeFrameShown frameShown,
  }) : _link = link,
       _qpc = qpc,
       _frameShown = frameShown;

  final EyeLink _link;
  final QpcClock _qpc;
  final EyeFrameShown _frameShown;

  /// Окно, в котором стоят точки.
  final EyeScreen screen;

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

  /// Прерван ли показ.
  bool get cancelled => _cancelled;

  /// Прерывает показ: таймеры сняты, `run` вернёт «прервано».
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
    // Прерванный показ экран больше не трогает: его место уже занял
    // следующий.
    if (_cancelled) {
      return;
    }
    this.hint = hint;
    this.point = point;
    this.pursuit = pursuit;
    shown++;
    notifyListeners();
  }

  /// Меняет только подсказку: точка стоит, и кольцо заново не сжимается.
  void _hint(String? text) {
    if (_cancelled) {
      return;
    }
    hint = text;
    notifyListeners();
  }

  Future<int> _onScreen() async {
    try {
      return await _frameShown().timeout(kFrameShownLimit);
    } on TimeoutException {
      return _qpc.nowUs();
    }
  }

  Future<void> _point(EyeTargetPoint p, Duration time, {String? hint}) async {
    if (_cancelled) {
      return;
    }
    _show(point: p, hint: hint);
    final int qpc = await _onScreen();
    if (_cancelled) {
      return;
    }
    final Offset at = p.at(screen.size);
    _link.target(phase: p.phase.wire, qpcUs: qpc, id: p.id, x: at.dx, y: at.dy);
    await _pause(time);
    done++;
  }

  void _off() {
    if (_cancelled) {
      return;
    }
    _link.target(phase: 'off', qpcUs: _qpc.nowUs());
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

/// Одна попытка калибровки.
class EyeCalibrationRun extends EyeTargetsRun {
  /// Создаёт попытку. [seed] — зерно порядка точек; [screen] —
  /// окно, на котором они рисуются.
  EyeCalibrationRun({
    required super.link,
    required super.qpc,
    required this.kind,
    required this.attempt,
    required this.seed,
    required super.screen,
    required this.distanceMm,
    required super.frameShown,
  });

  /// Какая калибровка.
  final EyeCalibrationKind kind;

  /// Номер попытки.
  final int attempt;

  /// Зерно порядка точек.
  final int seed;

  /// Расстояние до экрана, мм.
  final int distanceMm;

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

  /// Фаза движения головы (BUG-60): точка в середине, человек водит
  /// головой, глядя на неё, — по ней спутник учит поправку на голову.
  /// Лица мало — фаза повторяется один раз; мало и после повтора —
  /// калибровка идёт без неё, и поправка остаётся по геометрии.
  Future<void> _headPhase() async {
    for (int round = 0; round < 2; round++) {
      _show(hint: kHeadIntro);
      await _pause(kIntroTime);
      if (_cancelled) {
        return;
      }
      _show(hint: kHeadHintTurn, point: kHeadPoint);
      final int qpc = await _onScreen();
      if (_cancelled) {
        return;
      }
      final Offset at = kHeadPoint.at(screen.size);
      _link.target(
        phase: EyeTargetPhase.head.wire,
        qpcUs: qpc,
        id: kHeadPoint.id,
        x: at.dx,
        y: at.dy,
      );
      await _pause(kHeadTurnTime);
      _hint(kHeadHintNod);
      await _pause(kHeadPhaseTime - kHeadTurnTime);
      _off();
      if (_cancelled) {
        return;
      }
      final EyeSamples samples = await _link.samples(
        phase: EyeTargetPhase.head.wire,
      );
      final double? face = samples.face;
      if (face == null || face >= kFaceMinShare) {
        return;
      }
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
    await _headPhase();
    if (_cancelled) {
      return const EyeAttemptOutcome.cancelled();
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
}

/// Чем кончилась проверка точности без новой калибровки.
class EyeCheckOutcome {
  const EyeCheckOutcome._({this.accuracy, this.error, this.cancelled = false});

  /// Проверка прошла.
  const EyeCheckOutcome.done(EyeAccuracy accuracy) : this._(accuracy: accuracy);

  /// Спутник отказал.
  const EyeCheckOutcome.failed(EyeError error) : this._(error: error);

  /// Проверку прервали.
  const EyeCheckOutcome.cancelled() : this._(cancelled: true);

  /// Итог; `null` — до него не дошло.
  final EyeAccuracy? accuracy;

  /// Отказ спутника.
  final EyeError? error;

  /// Прервана.
  final bool cancelled;
}

/// Проверка точности без новой калибровки (BUG-60, SNO-F-EYE-03):
/// подсказка и девять точек по [kValidationPointTime] той моделью, что
/// есть. Итог — точность каждого способа поправки на голову и где была
/// голова против калибровки.
class EyeCheckRun extends EyeTargetsRun {
  /// Создаёт проверку номер [n]; [seed] — зерно порядка точек.
  EyeCheckRun({
    required super.link,
    required super.qpc,
    required super.screen,
    required super.frameShown,
    required this.n,
    required this.seed,
  });

  /// Номер проверки.
  final int n;

  /// Зерно порядка точек.
  final int seed;

  /// Ведёт проверку до конца.
  Future<EyeCheckOutcome> run() async {
    try {
      await _link.check(n);
      _show(hint: kCheckIntro);
      await _pause(kIntroTime);
      for (final EyeTargetPoint p in checkSequence(seed, n)) {
        await _point(p, kValidationPointTime);
      }
      _off();
      if (_cancelled) {
        return const EyeCheckOutcome.cancelled();
      }
      _show(hint: 'Считаю…');
      final EyeAccuracy accuracy = await _link.checked();
      _show();
      return _cancelled
          ? const EyeCheckOutcome.cancelled()
          : EyeCheckOutcome.done(accuracy);
    } on EyeError catch (e) {
      if (_cancelled) {
        return const EyeCheckOutcome.cancelled();
      }
      return EyeCheckOutcome.failed(e);
    }
  }
}

/// Окно спутника — размер в логических пикселях для точек.
extension EyeScreenSize on EyeScreen {
  /// Размер окна.
  Size get size => Size(width, height);
}
