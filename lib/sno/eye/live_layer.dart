/// Живой взгляд поверх приложения (SNO-F-EYE-03, кадр SNO-SCR-07.3).
///
/// После калибровки «Проверки айтрекера» экспериментатор смотрит на
/// настоящую полку и открывает настоящую книгу, а по экрану бегает
/// точка взгляда — сглаженная для глаза. В углу — частота, доля кадров
/// с лицом за последние десять секунд и точность калибровки; у пробной
/// полной — ещё и сколько осталось свободного просмотра.
///
/// Слой стоит выше навигатора, как слой записи: точка видна на любом
/// экране. Нажатия он не забирает — кроме кнопок своей панели.
///
/// «Проверить точность» (BUG-60) и проверка в конце свободного просмотра
/// идут на экране проверки: слой ставит его на навигатор, как только
/// проверка из живого взгляда начинает показывать точки.
///
/// Он же ставит экран айтрекера записи (шаг 32, SNO-F-EYE-01,
/// SNO-F-EYE-06): калибровку участника — сразу после «Код записан», и
/// проверку в конце — над экраном завершения, когда тот уже встал.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'eye_calibration.dart';
import 'eye_process.dart';
import '../recording/session.dart';
import 'eye_protocol.dart';
import 'eye_recording.dart';
import 'eye_tracker.dart';
import 'eye_trial.dart';
import 'recording_screen.dart';
import 'trial_screen.dart';

/// Поперечник точки живого взгляда.
const double kLiveDot = 28;

/// Слой живого взгляда над приложением.
///
/// Строение слоя не меняется, есть проверка или нет: приложение всегда
/// первый ребёнок одного и того же `Stack`, и его дерево — навигатор,
/// фокус клавиатуры — не пересоздаётся оттого, что проверка началась
/// или кончилась.
class EyeLiveLayer extends StatefulWidget {
  /// Создаёт слой. [openFolder] открывает папку стенда; подменяется в
  /// тестах.
  const EyeLiveLayer({
    required this.eye,
    required this.navigator,
    required this.child,
    this.openFolder = openFolderInExplorer,
    super.key,
  });

  /// Айтрекер.
  final EyeTracker eye;

  /// Навигатор приложения: «Ещё раз» ставит экран калибровки на него.
  final GlobalKey<NavigatorState> navigator;

  /// Приложение под слоем.
  final Widget child;

  /// Открывает папку в «Проводнике».
  final Future<bool> Function(String path) openFolder;

  @override
  State<EyeLiveLayer> createState() => _EyeLiveLayerState();
}

class _EyeLiveLayerState extends State<EyeLiveLayer> {
  EyeTrial? _trial;
  EyeTrialPhase? _phase;
  bool _screenUp = false;

  /// Айтрекер записи, за которым следит слой, и стоит ли его экран.
  EyeRecordingView? _recording;
  bool _recordingUp = false;
  bool _recordingSoon = false;

  /// Экран завершения сессии — над ним встаёт проверка в конце.
  RecordingSession? _session;

  @override
  void initState() {
    super.initState();
    widget.eye.trial.addListener(_trialChanged);
    widget.eye.recording.addListener(_recordingChanged);
    _session = widget.eye.session;
    _session?.finishOpen.addListener(_recordingScreen);
    _trialChanged();
    _recordingChanged();
  }

  @override
  void didUpdateWidget(EyeLiveLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.eye, widget.eye)) {
      oldWidget.eye.trial.removeListener(_trialChanged);
      widget.eye.trial.addListener(_trialChanged);
      oldWidget.eye.recording.removeListener(_recordingChanged);
      widget.eye.recording.addListener(_recordingChanged);
      _session?.finishOpen.removeListener(_recordingScreen);
      _session = widget.eye.session;
      _session?.finishOpen.addListener(_recordingScreen);
      _trialChanged();
      _recordingChanged();
    }
  }

  void _recordingChanged() {
    final EyeRecordingView? next = widget.eye.recording.value;
    if (!identical(next, _recording)) {
      _recording?.removeListener(_recordingScreen);
      _recording = next;
      next?.addListener(_recordingScreen);
    }
    _recordingScreen();
  }

  /// Ставит экран айтрекера записи, когда ему есть что показать: точки
  /// и итог калибровки — сразу, проверку в конце — когда под ней уже
  /// стоит экран завершения сессии (его ставит слой записи, снимая
  /// всё, что было открыто). Уходит экран сам.
  /// Нужен ли экран айтрекера записи [view] сейчас: калибровка — пока
  /// идёт запись, проверка в конце — после её остановки.
  bool _wants(EyeRecordingView? view) {
    if (view == null || !eyeRecordingWantsScreen(view.phase)) {
      return false;
    }
    final bool recording = _session?.recording ?? false;
    return view.phase == EyeRecordingPhase.endCheck ? !recording : recording;
  }

  void _recordingScreen() {
    final EyeRecordingView? view = _recording;
    if (view == null || !_wants(view)) {
      _recordingUp = false;
      return;
    }
    if (_recordingUp || _recordingSoon || !mounted) {
      return;
    }
    if (view.phase == EyeRecordingPhase.endCheck &&
        !(_session?.finishOpen.value ?? false)) {
      return;
    }
    // После кадра: слой записи мог в этот же миг снимать экраны.
    _recordingSoon = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _recordingSoon = false;
      final EyeRecordingView? now = _recording;
      final NavigatorState? nav = widget.navigator.currentState;
      if (!mounted || _recordingUp || nav == null || !_wants(now)) {
        return;
      }
      if (now!.phase == EyeRecordingPhase.endCheck &&
          !(_session?.finishOpen.value ?? false)) {
        return;
      }
      _recordingUp = true;
      unawaited(
        showEyeRecordingScreen(nav, now, widget.eye.qpc).whenComplete(() {
          _recordingUp = false;
          // Экран сняли (остановка записи сняла всё), а показывать ещё
          // есть что — например, проверку в конце.
          if (mounted) {
            _recordingScreen();
          }
        }),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _trialChanged() {
    final EyeTrial? next = widget.eye.trial.value;
    if (identical(next, _trial)) {
      return;
    }
    _trial?.removeListener(_changed);
    _trial = next;
    _phase = next?.phase;
    next?.addListener(_changed);
    _changed();
  }

  void _changed() {
    final EyeTrial? trial = _trial;
    final EyeTrialPhase? was = _phase;
    _phase = trial?.phase;
    // Из живого взгляда пошли точки — проверка точности (кнопкой или
    // концом свободного просмотра) или калибровка заново: они — на экране
    // проверки. «Ещё раз» ставит его сам.
    if (trial != null &&
        trial.showingTargets &&
        was == EyeTrialPhase.live &&
        !_screenUp) {
      final NavigatorState? nav = widget.navigator.currentState;
      if (nav != null && !_onTrialScreen(nav)) {
        _screenUp = true;
        unawaited(
          showEyeTrialScreen(nav, trial).whenComplete(() {
            _screenUp = false;
          }),
        );
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Стоит ли наверху навигатора экран проверки.
  bool _onTrialScreen(NavigatorState nav) {
    bool top = false;
    nav.popUntil((Route<dynamic> route) {
      top = route.settings.name == kEyeTrialRoute;
      return true;
    });
    return top;
  }

  @override
  void dispose() {
    widget.eye.trial.removeListener(_trialChanged);
    _trial?.removeListener(_changed);
    widget.eye.recording.removeListener(_recordingChanged);
    _recording?.removeListener(_recordingScreen);
    _session?.finishOpen.removeListener(_recordingScreen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EyeTrial? trial = _trial;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (trial != null && trial.overApp) ...<Widget>[
          if (trial.phase == EyeTrialPhase.live) _dot(context, trial),
          Positioned(
            top: 8,
            right: 8,
            child: _EyeLivePanel(
              trial: trial,
              navigator: widget.navigator,
              openFolder: widget.openFolder,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot(BuildContext context, EyeTrial trial) {
    final EyeGaze? gaze = trial.gaze;
    final (double, double)? at = gaze?.smooth;
    if (gaze == null || at == null) {
      return const SizedBox.shrink();
    }
    // Кадр без взгляда (моргание): спутник держит точку на месте до
    // полусекунды, и она не мигает, а бледнеет (BUG-59).
    final Color color = Theme.of(context).colorScheme.primary
        .withValues(alpha: gaze.ok ? 1 : 0.4);
    return Positioned(
      left: at.$1 - kLiveDot / 2,
      top: at.$2 - kLiveDot / 2,
      child: IgnorePointer(
        child: Container(
          key: const Key('eye-live-dot'),
          width: kLiveDot,
          height: kLiveDot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: color.a * 0.35),
            border: Border.all(color: color, width: 2),
          ),
        ),
      ),
    );
  }
}

class _EyeLivePanel extends StatelessWidget {
  const _EyeLivePanel({
    required this.trial,
    required this.navigator,
    required this.openFolder,
  });

  final EyeTrial trial;
  final GlobalKey<NavigatorState> navigator;
  final Future<bool> Function(String path) openFolder;

  /// Строка чисел в углу: «29,7 к/с · лицо 98 % · 2,7°».
  String _numbers() {
    final double? face = trial.faceShare;
    final double? acc = trial.accuracyDeg;
    return <String>[
      '${eyeNumber(trial.fps)} к/с',
      if (face != null) 'лицо ${(face * 100).round()} %',
      if (acc != null) '${eyeNumber(acc)}°',
    ].join(' · ');
  }

  String _left(Duration d) {
    final int s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _again() {
    final NavigatorState? nav = navigator.currentState;
    unawaited(trial.again());
    if (nav != null) {
      unawaited(showEyeTrialScreen(nav, trial));
    }
  }

  Widget _small(ThemeData theme, String text, String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, key: Key(key), style: theme.textTheme.bodySmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool finished = trial.phase == EyeTrialPhase.finished;
    final bool failed = trial.phase == EyeTrialPhase.failed;
    final bool full = trial.kind == EyeCalibrationKind.full;
    final Duration? left = trial.freeLeft;
    final String? folder = trial.standFolder;
    final EyeAccuracy? check = trial.lastCheck;
    final String? variants = check == null ? null : variantsLine(check);
    final EyeFit? fit = trial.outcome?.fit;
    final String? head = fit == null ? null : headPhaseLine(fit);
    return Material(
      key: const Key('eye-live-panel'),
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      finished || failed ? 'Проверка айтрекера' : _numbers(),
                      key: const Key('eye-live-numbers'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  // Без подсказки: слой стоит выше навигатора, и слоя
                  // всплывающих подсказок над ним нет.
                  IconButton(
                    key: const Key('eye-live-close'),
                    onPressed: () => unawaited(trial.close()),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (failed)
                Text(
                  trial.failure ?? 'Проверка остановилась',
                  key: const Key('eye-live-failure'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              if (!finished && !failed && full && left != null)
                Text(
                  'Свободный просмотр ${_left(left)} — смотрите на полку, '
                  'откройте книгу',
                  key: const Key('eye-live-left'),
                  style: theme.textTheme.bodySmall,
                ),
              if (finished)
                Text(
                  'Готово: файлы — в папке стенда',
                  key: const Key('eye-live-finished'),
                  style: theme.textTheme.bodyMedium,
                ),
              if (!failed && head != null && check == null)
                _small(theme, head, 'eye-live-head'),
              if (!failed && check != null)
                _small(
                  theme,
                  trial.endChecked ? endCheckLine(check) : checkLine(check),
                  'eye-live-check-line',
                ),
              if (!failed && variants != null)
                _small(theme, variants, 'eye-live-variants'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  if (!finished && !failed)
                    TextButton(
                      key: const Key('eye-live-check'),
                      onPressed: () => unawaited(trial.checkAccuracy()),
                      child: const Text('Проверить точность'),
                    ),
                  if (!full && !failed)
                    TextButton(
                      key: const Key('eye-live-again'),
                      onPressed: _again,
                      child: const Text('Ещё раз'),
                    ),
                  if (full && !finished && !failed)
                    TextButton(
                      key: const Key('eye-live-finish'),
                      onPressed: () => unawaited(trial.finishEarly()),
                      child: const Text('Закончить'),
                    ),
                  if ((finished || !full) && folder != null)
                    TextButton(
                      key: const Key('eye-live-folder'),
                      onPressed: () => unawaited(openFolder(folder)),
                      child: const Text('Открыть папку стенда'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
