import 'dart:async';

import 'package:flutter/material.dart';

import '../hold_button.dart';
import 'session.dart';

/// Чем кончилась запись — заголовком экрана завершения и плашки.
String describeStop(StopReason? by) {
  return switch (by) {
    StopReason.auto => 'Запись завершена',
    StopReason.crash => 'Запись прервана',
    StopReason.experimenter || null => 'Запись остановлена',
  };
}

/// Открывает экран завершения сессии поверх всего.
///
/// Экран один: пока он открыт, второй не открывается, а плашка,
/// ведущая на него, не показывается ([RecordingSession.finishOpen]).
Future<void> openSessionFinish(
  NavigatorState navigator,
  RecordingSession session,
) async {
  if (session.finishOpen.value || session.phase != RecordingPhase.stopped) {
    return;
  }
  session.setFinishOpen(true);
  try {
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return SessionFinishScreen(session: session);
        },
      ),
    );
  } finally {
    session.setFinishOpen(false);
  }
}

/// Завершение сессии (SNO-SCR-08, SNO-F-REC-01, SNO-F-CFG-05).
///
/// Всё, что происходит между остановкой записи и снятым замком полки.
/// Экран ведёт экспериментатор: код участника стоит крупно — его
/// сверяют с бланком, — а сессия завершается удержанием кнопки. Тест
/// нагрузки, фото бланка и упаковка в архив встанут сюда же вместе со
/// своими функциями.
class SessionFinishScreen extends StatefulWidget {
  /// Создаёт экран.
  const SessionFinishScreen({required this.session, super.key});

  /// Сессия записи.
  final RecordingSession session;

  @override
  State<SessionFinishScreen> createState() => _SessionFinishScreenState();
}

class _SessionFinishScreenState extends State<SessionFinishScreen> {
  /// Идёт ли завершение.
  bool _closing = false;

  /// Что показано на экране. Запоминается, пока сессия есть: когда её
  /// завершили, экран ещё уходит с глаз и обязан показывать то же, а не
  /// пустой код и нули.
  String _title = '';
  String _code = '';
  int _events = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    _remember();
  }

  void _remember() {
    final RecordingSession session = widget.session;
    final SessionState? state = session.state;
    if (state == null) {
      return;
    }
    _title =
        '${describeStop(state.stoppedBy)} · '
        '${describeRecordingTime(session.elapsedMs)}';
    _code = state.participant.display;
    _events = session.events;
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(_remember);
    }
  }

  Future<void> _finish() async {
    if (_closing) {
      return;
    }
    setState(() => _closing = true);
    try {
      await widget.session.finish();
    } on Object {
      // Завершить не удалось: экран остаётся, кнопка снова доступна.
    }
    if (!mounted) {
      return;
    }
    setState(() => _closing = false);
    if (widget.session.phase == RecordingPhase.idle) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final RecordingSession session = widget.session;
    final bool open = session.phase == RecordingPhase.stopped;
    return Scaffold(
      appBar: AppBar(title: const Text('Завершение сессии')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: <Widget>[
              Text(
                _title,
                key: const Key('sno-finish-title'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              Text('Код участника', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _code,
                  key: const Key('sno-finish-code'),
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Впишите код в бланк'),
              const SizedBox(height: 28),
              Text(
                'Записано событий: $_events',
                key: const Key('sno-finish-events'),
              ),
              if (session.writeFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Часть журнала не записалась на диск: проверьте '
                    'свободное место.',
                    key: const Key('sno-finish-failed'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 28),
              HoldToConfirmButton(
                key: const Key('sno-finish-hold'),
                label: _closing
                    ? 'Завершаю…'
                    : 'Удерживайте, чтобы завершить сессию',
                onConfirmed: _closing || !open
                    ? null
                    : () => unawaited(_finish()),
              ),
              const SizedBox(height: 8),
              Text(
                'После завершения полка открывается, а код участника '
                'забывается: следующая запись получит новый.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
