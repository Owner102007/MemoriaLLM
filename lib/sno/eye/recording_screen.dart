/// Экран айтрекера внутри записи участника (SNO-F-EYE-01, SNO-F-EYE-06;
/// кадры SNO-SCR-07.1, SNO-SCR-07.2, SNO-SCR-07.4).
///
/// Встаёт поверх приложения сразу после «Код записан» на ПК с местом
/// записи: самопроверка, точки калибровки, фаза движения головы,
/// слежение, точки проверки и итог. Принято — «Начать», и экран уходит:
/// пошло изучение. Не принято — «Повторить»; после второй неудачи —
/// выбор организатора удержанием. После остановки записи он встаёт ещё
/// раз — над экраном завершения — точками проверки в конце; организатор
/// может её пропустить удержанием.
///
/// Уйти с экрана нельзя: ни «назад», ни `Esc`. Клавиши и нажатия не
/// достаются ничему под ним; точка записи — над ним, и удержание её по-
/// прежнему останавливает запись.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../hold_button.dart';
import '../recording/layout_frames.dart';
import '../recording/layout_probe.dart';
import 'eye_calibration.dart';
import 'eye_calibration_run.dart';
import 'eye_protocol.dart';
import 'eye_recording.dart';
import 'qpc_clock.dart';
import 'trial_screen.dart' show EyeTargetsView;

/// Имя маршрута экрана айтрекера записи.
const String kEyeRecordingRoute = 'eye-recording';

/// Ставит экран айтрекера записи [view] на навигатор: встаёт и уходит без
/// перехода.
Future<void> showEyeRecordingScreen(
  NavigatorState navigator,
  EyeRecordingView view,
  QpcClock qpc,
) {
  return navigator.push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: kEyeRecordingRoute),
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
      ) => EyeRecordingScreen(view: view, qpc: qpc),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}

/// Нужен ли экран айтрекера записи в этой фазе.
bool eyeRecordingWantsScreen(EyeRecordingPhase phase) {
  return switch (phase) {
    EyeRecordingPhase.starting ||
    EyeRecordingPhase.calibrating ||
    EyeRecordingPhase.result ||
    EyeRecordingPhase.endCheck => true,
    EyeRecordingPhase.studying || EyeRecordingPhase.done => false,
  };
}

/// Экран айтрекера записи.
class EyeRecordingScreen extends StatefulWidget {
  /// Создаёт экран.
  const EyeRecordingScreen({required this.view, required this.qpc, super.key});

  /// Айтрекер записи.
  final EyeRecordingView view;

  /// Часы QPC: миг, когда кадр с точкой отрисован.
  final QpcClock qpc;

  @override
  State<EyeRecordingScreen> createState() => _EyeRecordingScreenState();
}

class _EyeRecordingScreenState extends State<EyeRecordingScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'eye-recording');
  bool _leaving = false;

  EyeRecordingView get _view => widget.view;

  @override
  void initState() {
    super.initState();
    _view
      ..frameShown = _frameShown
      ..windowSize = _windowSize
      ..addListener(_changed);
    // Экран мог встать, когда показывать уже нечего.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _changed());
  }

  Size _windowSize() {
    if (!mounted) {
      return Size.zero;
    }
    return MediaQuery.sizeOf(context);
  }

  /// QPC после того, как кадр с точкой отрисован: после кадра, в котором
  /// точка появилась, и ещё одного (SNO-ALG-EYE-03, шаг 9).
  Future<int> _frameShown() {
    final Completer<int> done = Completer<int>();
    final SchedulerBinding binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((Duration _) {
      binding.addPostFrameCallback((Duration _) {
        if (!done.isCompleted) {
          done.complete(widget.qpc.nowUs());
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
    if (!eyeRecordingWantsScreen(_view.phase)) {
      _leaving = true;
      // Уходит именно этот экран, даже если над ним открыт вопрос об
      // остановке записи; «назад» он не слушает, поэтому — не `maybePop`.
      final NavigatorState navigator = Navigator.of(context);
      final ModalRoute<Object?>? route = ModalRoute.of(context);
      if (route == null) {
        return;
      }
      if (route.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        navigator.removeRoute(route);
      }
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _view.removeListener(_changed);
    if (_view.frameShown == _frameShown) {
      _view.frameShown = null;
    }
    if (_view.windowSize == _windowSize) {
      _view.windowSize = null;
    }
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget body = switch (_view.phase) {
      EyeRecordingPhase.starting => _starting(theme),
      EyeRecordingPhase.calibrating => _targets(_view.targets),
      EyeRecordingPhase.endCheck => _endCheck(theme),
      EyeRecordingPhase.result => _result(theme),
      _ => const SizedBox.shrink(),
    };
    // «Назад», `Esc`, листание и `F11` не делают ничего: с экрана
    // калибровки можно уйти только её итогом.
    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) => KeyEventResult.handled,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(child: body),
        ),
      ),
    );
  }

  Widget _page(ThemeData theme, List<Widget> children) {
    return LayoutProbe(
      kind: LayoutKind.screen,
      id: 'calibration_result',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _starting(ThemeData theme) {
    return _page(theme, <Widget>[
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 16),
      Center(
        child: Text(
          _view.stage ?? 'Запускаю…',
          key: const Key('eye-recording-stage'),
        ),
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

  /// Точки проверки в конце (кадр SNO-SCR-07.4) и в углу — пропуск для
  /// организатора.
  Widget _endCheck(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _targets(_view.targets),
        Positioned(
          right: 16,
          bottom: 16,
          child: SizedBox(
            width: 260,
            child: HoldToConfirmButton(
              key: const Key('eye-recording-skip'),
              label: 'Удерживайте — пропустить проверку',
              hold: kEyeChoiceHold,
              onConfirmed: _view.skipEndCheck,
            ),
          ),
        ),
      ],
    );
  }

  /// Итог попытки (кадр SNO-SCR-07.2).
  Widget _result(ThemeData theme) {
    final EyeAttemptOutcome? outcome = _view.outcome;
    final EyeValidation? v = outcome?.validation;
    final bool accepted = v?.accepted ?? false;
    final bool busy = _view.busy;
    final String? problem = _view.problem;
    return _page(theme, <Widget>[
      Text('Калибровка айтрекера', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 12),
      if (problem != null)
        Text(
          problem,
          key: const Key('eye-recording-problem'),
          style: theme.textTheme.titleMedium,
        )
      else if (v != null) ...<Widget>[
        Text(
          validationLine(
            v,
            attempt: _view.attempt,
            attempts: kRecordingAttempts,
          ),
          key: const Key('eye-recording-line'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          accepted
              ? 'Принято.'
              : _view.mustChoose
              ? 'Не принято и после ${_view.failures} попыток. '
                    '${rejectAdvice(v)}'
              : rejectAdvice(v),
          key: const Key('eye-recording-verdict'),
          style: theme.textTheme.bodyLarge,
        ),
      ],
      if (busy && !accepted)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Айтрекер готовится…', key: Key('eye-recording-busy')),
        ),
      const SizedBox(height: 20),
      if (accepted)
        FilledButton(
          key: const Key('eye-recording-begin'),
          onPressed: busy ? null : () => unawaited(_view.begin()),
          child: const Text('Начать'),
        )
      else if (_view.mustChoose) ...<Widget>[
        Text(
          'Решает организатор — удерживайте кнопку:',
          style: theme.textTheme.bodyMedium,
        ),
        // Модели нет (айтрекер перезапускался после итога) — писать
        // взгляд нечем.
        if (outcome?.fit != null) ...<Widget>[
          const SizedBox(height: 8),
          HoldToConfirmButton(
            key: const Key('eye-recording-write'),
            label: 'Писать с пометкой (по умолчанию)',
            hold: kEyeChoiceHold,
            onConfirmed: busy
                ? null
                : () => unawaited(_view.choose(write: true)),
          ),
        ],
        const SizedBox(height: 8),
        HoldToConfirmButton(
          key: const Key('eye-recording-without'),
          label: 'Без взгляда',
          hold: kEyeChoiceHold,
          onConfirmed: busy
              ? null
              : () => unawaited(_view.choose(write: false)),
        ),
      ] else
        FilledButton(
          key: const Key('eye-recording-retry'),
          onPressed: busy ? null : () => unawaited(_view.retry()),
          child: const Text('Повторить'),
        ),
    ]);
  }
}
