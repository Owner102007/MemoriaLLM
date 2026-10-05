import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/navigation/sections.dart';
import '../hold_button.dart';
import 'finish_screen.dart';
import 'session.dart';

/// Сколько держат точку записи, чтобы спросить об остановке.
const Duration kStopHold = Duration(seconds: 2);

/// Цвет точки записи.
///
/// Не из темы: точка обязана выглядеть одинаково на любой теме и под
/// любым светофильтром — по ней экспериментатор с одного взгляда
/// видит, что запись идёт.
const Color kRecordingDotColor = Color(0xFFE5484D);

/// Ободок точки: на тёмно-красной теме красная точка без него теряется.
const Color kRecordingDotRing = Color(0xFFF5E9E6);

/// Слой записи поверх всего приложения (SNO-SCR-02, SNO-F-REC-01).
///
/// Стоит выше навигатора, поэтому виден на каждом экране — на полке, в
/// книге, в «Тестировании» — и лежит выше светофильтра: фильтр
/// накрывает только картинку страницы. Пока запись идёт, в углу горит
/// точка без цифр; удержание точки спрашивает об остановке. Когда
/// запись остановилась сама, чтение не прерывается: внизу появляется
/// плашка, ведущая на завершение сессии.
///
/// Здесь же запись узнаёт, что приложение ушло с переднего плана и
/// вернулось.
class RecordingOverlay extends StatefulWidget {
  /// Создаёт слой.
  const RecordingOverlay({
    required this.session,
    required this.navigator,
    required this.child,
    super.key,
  });

  /// Сессия записи.
  final RecordingSession session;

  /// Навигатор приложения: диалог остановки и экран завершения
  /// открываются в нём.
  final GlobalKey<NavigatorState> navigator;

  /// Приложение под слоем.
  final Widget child;

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with WidgetsBindingObserver {
  /// Открыт ли вопрос об остановке.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_changed);
  }

  @override
  void didUpdateWidget(RecordingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      widget.session.appReturned();
    } else if (state != AppLifecycleState.detached) {
      // `inactive`, `hidden`, `paused`. Закрытие приложения (`detached`)
      // событием не пишется: запись закроется при следующем запуске.
      widget.session.appLeft(state.name);
    }
  }

  /// Спрашивает экспериментатора, остановить ли запись.
  Future<void> _askStop() async {
    final BuildContext? host = widget.navigator.currentContext;
    if (_asking || host == null || !widget.session.recording) {
      return;
    }
    _asking = true;
    final bool? stop;
    try {
      stop = await showDialog<bool>(
        context: host,
        builder: (BuildContext context) {
          return StopRecordingDialog(session: widget.session);
        },
      );
    } finally {
      _asking = false;
    }
    if (stop != true || !mounted) {
      return;
    }
    await widget.session.stop(StopReason.experimenter);
    _openFinish();
  }

  void _openFinish() {
    final NavigatorState? navigator = widget.navigator.currentState;
    if (navigator == null) {
      return;
    }
    unawaited(openSessionFinish(navigator, widget.session));
  }

  @override
  Widget build(BuildContext context) {
    final RecordingSession session = widget.session;
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final bool wide =
        navPlacementFor(MediaQuery.sizeOf(context).width) == NavPlacement.top;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (session.recording)
          Positioned(
            top: safe.top,
            // Телефон — левый верхний угол, окно ПК — правый: там точка
            // не ложится на разделы навигации.
            left: wide ? null : safe.left,
            right: wide ? safe.right : null,
            child: RecordingDot(
              key: const Key('sno-recording-dot'),
              onHeld: () => unawaited(_askStop()),
            ),
          ),
        if (session.phase == RecordingPhase.stopped)
          ValueListenableBuilder<bool>(
            valueListenable: session.finishOpen,
            builder: (BuildContext context, bool open, Widget? child) {
              if (open) {
                return const SizedBox.shrink();
              }
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  // Выше нижней навигации телефона: плашка не должна
                  // закрывать разделы.
                  padding: EdgeInsets.only(
                    bottom: safe.bottom + (wide ? 24 : 96),
                  ),
                  child: _EndedPlaque(
                    label: describeStop(session.state?.stoppedBy),
                    onTap: _openFinish,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Плашка «Запись завершена»: ведёт на завершение сессии.
class _EndedPlaque extends StatelessWidget {
  const _EndedPlaque({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      key: const Key('sno-recording-ended'),
      color: theme.colorScheme.surface,
      elevation: 6,
      shape: StadiumBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Точка записи: горит, пока запись идёт (SNO-SCR-02.1).
///
/// Удержание точки [hold] зовёт [onHeld]; короткое нажатие не делает
/// ничего. Нажатия точка не отбирает: под ней может стоять кнопка
/// экрана, и та работает как прежде.
class RecordingDot extends StatefulWidget {
  /// Создаёт точку.
  const RecordingDot({
    required this.onHeld,
    this.hold = kStopHold,
    super.key,
  });

  /// Что сделать, когда точку додержали.
  final VoidCallback onHeld;

  /// Сколько её держать.
  final Duration hold;

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.hold,
  )..addStatusListener(_statusChanged);

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    _fill.reset();
    widget.onHeld();
  }

  void _release() {
    if (_fill.isAnimating) {
      _fill.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Идёт запись',
      child: Listener(
        // Прозрачна для нажатий: кнопка под точкой получает их тоже.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent event) => _fill.forward(from: 0),
        onPointerUp: (PointerUpEvent event) => _release(),
        onPointerCancel: (PointerCancelEvent event) => _release(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: AnimatedBuilder(
            animation: _fill,
            builder: (BuildContext context, Widget? child) {
              return CustomPaint(painter: _DotPainter(_fill.value));
            },
          ),
        ),
      ),
    );
  }
}

/// Рисует точку с ободком и, пока её держат, растущее кольцо.
class _DotPainter extends CustomPainter {
  const _DotPainter(this.held);

  /// Какая доля удержания прошла: от нуля до единицы.
  final double held;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    canvas
      ..drawCircle(centre, 6.5, Paint()..color = kRecordingDotRing)
      ..drawCircle(centre, 5, Paint()..color = kRecordingDotColor);
    if (held > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: 11),
        -1.5707963267948966,
        6.283185307179586 * held,
        false,
        Paint()
          ..color = kRecordingDotRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter oldDelegate) => oldDelegate.held != held;
}

/// Вопрос об остановке записи (SNO-SCR-02.2).
///
/// Остановка — тоже удержанием: случайное нажатие не должно оборвать
/// запись участника. Если запись за это время кончилась сама, вопрос
/// закрывается.
class StopRecordingDialog extends StatefulWidget {
  /// Создаёт вопрос.
  const StopRecordingDialog({required this.session, super.key});

  /// Сессия записи.
  final RecordingSession session;

  @override
  State<StopRecordingDialog> createState() => _StopRecordingDialogState();
}

class _StopRecordingDialogState extends State<StopRecordingDialog> {
  /// Закрыт ли вопрос: закрывается он один раз.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // Запись кончилась сама, пока вопрос был открыт.
    if (!widget.session.recording) {
      _close(false);
    }
  }

  /// Закрывает вопрос ответом [stop].
  ///
  /// Один раз: пока окно уходит с экрана, оно ещё в дереве, и второе
  /// закрытие сняло бы экран под ним.
  void _close(bool stop) {
    if (_closed || !mounted) {
      return;
    }
    _closed = true;
    // Вопрос могли закрыть и мимо кнопок — нажатием вокруг него.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      return;
    }
    Navigator.of(context).pop(stop);
  }

  @override
  Widget build(BuildContext context) {
    final RecordingSession session = widget.session;
    final String planned = describeRecordingTime(
      session.planned.inMilliseconds,
    );
    return AlertDialog(
      key: const Key('sno-stop-dialog'),
      title: const Text('Остановить запись?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: session.ticks,
            builder: (BuildContext context, int tick, Widget? child) {
              final String passed = describeRecordingTime(session.elapsedMs);
              return Text(
                'Прошло $passed из $planned',
                key: const Key('sno-stop-passed'),
              );
            },
          ),
          const SizedBox(height: 16),
          HoldToConfirmButton(
            key: const Key('sno-stop-hold'),
            label: 'Удерживайте, чтобы остановить',
            onConfirmed: () => _close(true),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('sno-stop-continue'),
          onPressed: () => _close(false),
          child: const Text('Продолжить'),
        ),
      ],
    );
  }
}
