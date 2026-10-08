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
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'eye_calibration.dart';
import 'eye_process.dart';
import 'eye_protocol.dart';
import 'eye_tracker.dart';
import 'eye_trial.dart';
import 'trial_screen.dart';

/// Поперечник точки живого взгляда.
const double kLiveDot = 28;

/// Слой живого взгляда над приложением.
class EyeLiveLayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EyeTrial?>(
      valueListenable: eye.trial,
      child: child,
      builder: (BuildContext context, EyeTrial? trial, Widget? child) {
        final Widget app = child ?? const SizedBox.shrink();
        if (trial == null) {
          return app;
        }
        return ListenableBuilder(
          listenable: trial,
          child: app,
          builder: (BuildContext context, Widget? app) {
            final EyeTrialPhase phase = trial.phase;
            if (phase != EyeTrialPhase.live &&
                phase != EyeTrialPhase.finished) {
              return app ?? const SizedBox.shrink();
            }
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ?app,
                if (phase == EyeTrialPhase.live) _dot(context, trial),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _EyeLivePanel(
                    trial: trial,
                    navigator: navigator,
                    openFolder: openFolder,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dot(BuildContext context, EyeTrial trial) {
    final EyeGaze? gaze = trial.gaze;
    final (double, double)? at = gaze?.smooth;
    if (gaze == null || !gaze.ok || at == null) {
      return const SizedBox.shrink();
    }
    final Color color = Theme.of(context).colorScheme.primary;
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
            color: color.withValues(alpha: 0.35),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool finished = trial.phase == EyeTrialPhase.finished;
    final bool full = trial.kind == EyeCalibrationKind.full;
    final Duration? left = trial.freeLeft;
    final String? folder = trial.standFolder;
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
                      finished ? 'Проверка айтрекера' : _numbers(),
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
              if (!finished && full && left != null)
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
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  if (!full)
                    TextButton(
                      key: const Key('eye-live-again'),
                      onPressed: _again,
                      child: const Text('Ещё раз'),
                    ),
                  if (full && !finished)
                    TextButton(
                      key: const Key('eye-live-finish'),
                      onPressed: () => unawaited(trial.finishEarly()),
                      child: const Text('Закончить'),
                    ),
                  if (finished && folder != null)
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
