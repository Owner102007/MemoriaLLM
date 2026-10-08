/// Экран «Проверки айтрекера» и калибровки (SNO-F-EYE-03, SNO-F-EYE-01;
/// кадры SNO-SCR-07.1, SNO-SCR-07.2).
///
/// Один экран на всю проверку: выбор вида, запуск, точки калибровки,
/// фаза движения головы и слежение, итог, точки проверки точности без
/// новой калибровки (BUG-60). Когда начинается живой взгляд, экран
/// уходит сам — точку взгляда поверх приложения рисует [EyeLiveLayer]
/// (`live_layer.dart`), чтобы экспериментатор смотрел на настоящую полку
/// и книгу.
///
/// Пока идут точки, экран забирает себе все нажатия и клавиши: ничего,
/// кроме точек, не открывается. `Esc` закрывает проверку.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'eye_calibration.dart';
import 'eye_calibration_run.dart';
import 'eye_protocol.dart';
import 'eye_tracker.dart';
import 'eye_trial.dart';

/// Открывает «Проверку айтрекера». Места записи нет — ничего не
/// открывается, `false`. Идёт живой взгляд идущей проверки — экран не
/// ставится: проверка уже на виду панелью над приложением.
Future<bool> openEyeTrial(NavigatorState navigator, EyeTracker eye) async {
  final EyeTrial? trial = eye.beginTrial();
  if (trial == null) {
    return false;
  }
  if (trial.overApp) {
    return true;
  }
  unawaited(showEyeTrialScreen(navigator, trial));
  return true;
}

/// Ставит экран проверки [trial] поверх приложения: и в начале, и из
/// живой точки по «Ещё раз».
Future<void> showEyeTrialScreen(NavigatorState navigator, EyeTrial trial) {
  return navigator.push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: kEyeTrialRoute),
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
      ) => EyeTrialScreen(trial: trial),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}

/// Имя маршрута экрана проверки.
const String kEyeTrialRoute = 'eye-trial';

/// Экран проверки.
class EyeTrialScreen extends StatefulWidget {
  /// Создаёт экран.
  const EyeTrialScreen({required this.trial, super.key});

  /// Проверка.
  final EyeTrial trial;

  @override
  State<EyeTrialScreen> createState() => _EyeTrialScreenState();
}

class _EyeTrialScreenState extends State<EyeTrialScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'eye-trial');
  bool _leaving = false;

  /// Фаза, которую экран видел последней: уходит он только при переходе
  /// в живой взгляд, а не оттого, что его открыли из живого взгляда.
  late EyeTrialPhase _seen;

  EyeTrial get _trial => widget.trial;

  @override
  void initState() {
    super.initState();
    _seen = _trial.phase;
    _trial.frameShown = _frameShown;
    _trial.windowSize = _windowSize;
    _trial.addListener(_changed);
  }

  Size _windowSize() {
    if (!mounted) {
      return Size.zero;
    }
    return MediaQuery.sizeOf(context);
  }

  /// QPC после того, как кадр с точкой отрисован: обратный вызов после
  /// кадра, в котором точка появилась, и ещё одного — тогда она уже на
  /// мониторе (SNO-ALG-EYE-03, шаг 9).
  Future<int> _frameShown() {
    final Completer<int> done = Completer<int>();
    final SchedulerBinding binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((Duration _) {
      binding.addPostFrameCallback((Duration _) {
        if (!done.isCompleted) {
          done.complete(_trial.tracker.qpc.nowUs());
        }
      });
      binding.scheduleFrame();
    });
    binding.scheduleFrame();
    return done.future;
  }

  void _changed() {
    if (!mounted || _leaving) {
      return;
    }
    final EyeTrialPhase was = _seen;
    final EyeTrialPhase phase = _trial.phase;
    _seen = phase;
    final bool away =
        phase == EyeTrialPhase.live || phase == EyeTrialPhase.finished;
    final bool wasAway =
        was == EyeTrialPhase.live || was == EyeTrialPhase.finished;
    if (phase == EyeTrialPhase.closed || (away && !wasAway)) {
      // Живой взгляд — поверх приложения, а не на этом экране.
      _leaving = true;
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _trial.removeListener(_changed);
    if (_trial.frameShown == _frameShown) {
      _trial.frameShown = null;
    }
    if (_trial.windowSize == _windowSize) {
      _trial.windowSize = null;
    }
    // Ушли с экрана не в живой взгляд («назад», `Esc`) — проверка
    // закрыта: спутник и окно отпущены. Закрывается она после кадра:
    // закрытие оповещает слушателей, а дерево виджетов сейчас под замком.
    if (!_trial.overApp) {
      final EyeTrial trial = _trial;
      unawaited(Future<void>.microtask(trial.close));
    }
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    unawaited(_trial.close());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    // Пока идут точки, клавиши не достаются никому: ни листание, ни
    // `F11`, ни поиск.
    return _trial.showingTargets ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget body = switch (_trial.phase) {
      EyeTrialPhase.choose => _choose(theme),
      EyeTrialPhase.starting => _starting(theme),
      EyeTrialPhase.failed => _failed(theme),
      EyeTrialPhase.calibrating => _targets(_trial.run),
      EyeTrialPhase.checking => _targets(_trial.checkRun),
      EyeTrialPhase.result => _result(theme),
      _ => const SizedBox.shrink(),
    };
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _page(ThemeData theme, List<Widget> children) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: children,
        ),
      ),
    );
  }

  Widget _closeButton() {
    return TextButton(
      key: const Key('eye-trial-close'),
      onPressed: _close,
      child: const Text('Закрыть'),
    );
  }

  Widget _choose(ThemeData theme) {
    return _page(theme, <Widget>[
      Text('Проверка айтрекера', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(_trial.place.summary, key: const Key('eye-trial-place')),
      const SizedBox(height: 24),
      FilledButton.tonal(
        key: const Key('eye-trial-quick'),
        onPressed: () => unawaited(_trial.start(EyeCalibrationKind.quick)),
        child: const Text('Быстро: 9 точек, движение головы и живой взгляд'),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('eye-trial-full'),
        onPressed: () => unawaited(_trial.start(EyeCalibrationKind.full)),
        child: const Text('Пробная полная калибровка'),
      ),
      const SizedBox(height: 8),
      Text(
        'Полная — то, что пройдёт участник: 13 точек, 12 секунд движения '
        'головы, слежение за точкой и 9 точек проверки, потом живой взгляд, '
        'две минуты свободного просмотра и проверка точности в конце. '
        'Из живого взгляда точность можно проверить в любой миг — посидите, '
        'откиньтесь, повернитесь и нажмите «Проверить точность». Файлы '
        'лягут в папку стенда.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerLeft, child: _closeButton()),
    ]);
  }

  Widget _starting(ThemeData theme) {
    return _page(theme, <Widget>[
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 16),
      Center(
        child: Text(
          _trial.stage ?? 'Запускаю…',
          key: const Key('eye-trial-stage'),
        ),
      ),
    ]);
  }

  Widget _failed(ThemeData theme) {
    final EyeCheck? check = _trial.check;
    return _page(theme, <Widget>[
      Text(
        _trial.failure ?? 'Проверка остановилась',
        key: const Key('eye-trial-failure'),
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      if (check != null) ...<Widget>[
        const SizedBox(height: 8),
        for (final EyeCheckRow row in check.rows)
          if (row.verdict != EyeVerdict.good)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${row.text}', key: Key('eye-trial-row-${row.id}')),
            ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        children: <Widget>[
          FilledButton(
            key: const Key('eye-trial-restart'),
            onPressed: _trial.kind == null
                ? null
                : () => unawaited(_trial.start(_trial.kind!)),
            child: const Text('Ещё раз'),
          ),
          _closeButton(),
        ],
      ),
    ]);
  }

  Widget _targets(EyeTargetsRun? run) {
    if (run == null) {
      return const SizedBox.shrink();
    }
    // Нажатия по экрану не достаются ничему под ним.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: EyeTargetsView(run: run),
    );
  }

  Widget _result(ThemeData theme) {
    final EyeAttemptOutcome? outcome = _trial.outcome;
    final EyeValidation? v = outcome?.validation;
    final bool noFace = outcome?.noFace ?? false;
    final bool accepted = v?.accepted ?? false;
    final bool canRetry = _trial.canRetry;
    return _page(theme, <Widget>[
      if (noFace)
        Text(
          'Камера не видит лица — сядьте напротив камеры и повторите',
          key: const Key('eye-trial-no-face'),
          style: theme.textTheme.titleMedium,
        )
      else if (v != null) ...<Widget>[
        Text(
          validationLine(v, attempt: _trial.attempt),
          key: const Key('eye-trial-line'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          accepted
              ? 'Принято.'
              : canRetry
              ? rejectAdvice(v)
              : 'Не принято и после ${_trial.attempt} попыток. '
                    '${rejectAdvice(v)}',
          key: const Key('eye-trial-verdict'),
          style: theme.textTheme.bodyLarge,
        ),
        if (outcome?.fit?.latencyMs case final double latency)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Задержка камеры ${latency.round()} мс',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (outcome?.fit case final EyeFit fit)
          if (headPhaseLine(fit) case final String head)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                head,
                key: const Key('eye-trial-head'),
                style: theme.textTheme.bodySmall,
              ),
            ),
      ],
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (accepted)
            FilledButton(
              key: const Key('eye-trial-live'),
              onPressed: () => unawaited(_trial.goLive()),
              child: const Text('Живой взгляд'),
            ),
          if (!accepted && canRetry)
            FilledButton(
              key: const Key('eye-trial-retry'),
              onPressed: () => unawaited(_trial.retry()),
              child: const Text('Повторить'),
            ),
          if (!accepted && !noFace && outcome?.fit != null)
            OutlinedButton(
              key: const Key('eye-trial-live-anyway'),
              onPressed: () => unawaited(_trial.goLive()),
              child: const Text('Живой взгляд всё равно'),
            ),
          _closeButton(),
        ],
      ),
    ]);
  }
}

/// Точки калибровки и проверки, движущаяся точка и подсказки (кадр
/// SNO-SCR-07.1): на фоне темы, без ничего лишнего.
class EyeTargetsView extends StatefulWidget {
  /// Создаёт вид.
  const EyeTargetsView({required this.run, super.key});

  /// Попытка калибровки или проверка точности, которую он показывает.
  final EyeTargetsRun run;

  @override
  State<EyeTargetsView> createState() => _EyeTargetsViewState();
}

class _EyeTargetsViewState extends State<EyeTargetsView>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: kRingTime,
  );
  late final Ticker _ticker = createTicker(_onTick);
  Duration _elapsed = Duration.zero;
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    widget.run.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(EyeTargetsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.run, widget.run)) {
      oldWidget.run.removeListener(_changed);
      widget.run.addListener(_changed);
      _changed();
    }
  }

  void _onTick(Duration elapsed) {
    setState(() => _elapsed = elapsed);
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final EyeTargetsRun run = widget.run;
    if (run.shown != _shown) {
      _shown = run.shown;
      if (run.point != null) {
        _ring.forward(from: 0);
      }
      if (_ticker.isActive) {
        _ticker.stop();
      }
      _elapsed = Duration.zero;
      if (run.pursuit != null) {
        _ticker.start();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.run.removeListener(_changed);
    _ring.dispose();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EyeTargetsRun run = widget.run;
    final Size size = MediaQuery.sizeOf(context);
    final EyeTargetPoint? point = run.point;
    final PursuitPath? path = run.pursuit;
    final String? hint = run.hint;
    Offset? at;
    if (point != null) {
      at = point.at(size);
    } else if (path != null) {
      at = path.at(_elapsed);
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (hint != null)
          Align(
            alignment: const Alignment(0, -0.6),
            child: Text(
              hint,
              key: const Key('eye-targets-hint'),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
        if (at != null)
          AnimatedBuilder(
            animation: _ring,
            builder: (BuildContext context, Widget? child) {
              final double ring = point == null
                  ? kTargetDot
                  : kTargetRing - (kTargetRing - kTargetDot) * _ring.value;
              return CustomPaint(
                key: const Key('eye-targets-point'),
                painter: _TargetPainter(
                  at: at!,
                  ring: ring,
                  color: theme.colorScheme.primary,
                  dot: theme.colorScheme.onSurface,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _TargetPainter extends CustomPainter {
  _TargetPainter({
    required this.at,
    required this.ring,
    required this.color,
    required this.dot,
  });

  final Offset at;
  final double ring;
  final Color color;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      at,
      ring / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    canvas.drawCircle(at, kTargetDot / 2, Paint()..color = color);
    canvas.drawCircle(at, 2, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_TargetPainter old) =>
      old.at != at || old.ring != ring || old.color != color || old.dot != dot;
}
