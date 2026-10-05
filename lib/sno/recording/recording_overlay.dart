import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/navigation/sections.dart';
import '../../ui/claimed_pointers.dart';
import '../hold_button.dart';
import 'finish_screen.dart';
import 'session.dart';

/// Сколько держат точку записи, чтобы спросить об остановке.
const Duration kStopHold = Duration(seconds: 2);

/// Через сколько удержания точка забирает нажатие себе.
///
/// Раньше, чем экран под ней успеет принять то же нажатие за своё:
/// выделение слова на странице начинается через четверть секунды,
/// подсказка у кнопки — через полсекунды. Нажатие короче достаётся
/// экрану, как будто точки нет.
const Duration kDotRecognition = Duration(milliseconds: 200);

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
    if (state != AppLifecycleState.detached) {
      // SNO-F-REC-10: каждая смена — `resumed`, `inactive`, `hidden`,
      // `paused` — а не только уход и возвращение. Закрытие приложения
      // (`detached`) событием не пишется: запись закроется при
      // следующем запуске.
      widget.session.appState(state.name);
    }
  }

  /// Приложение просят закрыть: крестик окна на ПК, Alt+F4.
  ///
  /// Пока запись идёт, окно не закрывается — как «назад» на полке
  /// телефона: закрытое приложение оборвало бы запись участника.
  /// Сначала запись останавливают, потом закрывают окно. Остановке и
  /// завершению сессии дают дописать своё на диск: окно, закрытое
  /// раньше, оставило бы запись без строки остановки.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!widget.session.recording) {
      await widget.session.settled();
      return AppExitResponse.exit;
    }
    final BuildContext? host = widget.navigator.currentContext;
    if (host != null) {
      // Крестик нажали несколько раз — сообщение одно, а не очередь.
      ScaffoldMessenger.maybeOf(host)
        ?..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            key: Key('sno-exit-refused'),
            content: Text('Идёт запись: окно закроется после её остановки'),
            duration: Duration(seconds: 4),
          ),
        );
    }
    return AppExitResponse.cancel;
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
    // Состояние меняется сразу, диск догоняет: экран завершения
    // открывается, не дожидаясь его, — иначе под ним успела бы
    // мелькнуть плашка.
    final Future<void> stopping = widget.session.stop(StopReason.experimenter);
    _openFinish();
    await stopping;
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
    // Экранная клавиатура плашку не закрывает: та встаёт над ней.
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
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
                    bottom: keyboard > 0
                        ? keyboard + 12
                        : safe.bottom + (wide ? 24 : 96),
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
/// экрана — «назад» в левом углу, — и короткое нажатие достаётся ей,
/// как прежде.
///
/// Удержание — другое дело: через [kDotRecognition] точка забирает
/// нажатие себе, в общем споре жестов, как это делает любое долгое
/// нажатие. Экран под ней его уже не получит: слово на странице не
/// выделится, подсказка у кнопки не всплывёт, а отпущенный палец не
/// нажмёт «назад» и не закроет только что открытый вопрос об
/// остановке. Палец, который повёл по экрану, удержанием не
/// считается: прокрутка и протяжка идут как шли.
class RecordingDot extends StatefulWidget {
  /// Создаёт точку.
  const RecordingDot({required this.onHeld, this.hold = kStopHold, super.key});

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
    duration: _fillTime(widget.hold),
  )..addStatusListener(_statusChanged);

  /// Сколько растёт кольцо: всё удержание без времени распознавания.
  static Duration _fillTime(Duration hold) {
    return hold > kDotRecognition ? hold - kDotRecognition : Duration.zero;
  }

  @override
  void didUpdateWidget(RecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fill.duration = _fillTime(widget.hold);
  }

  @override
  void dispose() {
    final int? pointer = _claimed;
    if (pointer != null) {
      ClaimedPointers.release(pointer);
    }
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

  /// Нажатие, которое точка забрала себе; `null` — её не держат.
  int? _claimed;

  /// Удержание узнано: нажатие указателя [pointer] теперь точки.
  void _held(int? pointer) {
    // Страница книги узнаёт нажатие мимо спора жестов и о том, что
    // проиграла его, не знает: без этой отметки отпущенный палец
    // перелистнул бы страницу.
    if (pointer != null) {
      ClaimedPointers.claim(pointer);
      _claimed = pointer;
    }
    _fill.forward(from: 0);
  }

  void _release() {
    final int? pointer = _claimed;
    if (pointer != null) {
      ClaimedPointers.release(pointer);
      _claimed = null;
    }
    if (_fill.isAnimating) {
      _fill.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Идёт запись',
      child: RawGestureDetector(
        // Прозрачна для нажатий: кнопка под точкой получает их тоже.
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: kDotRecognition),
                (LongPressGestureRecognizer instance) {
                  instance
                    ..onLongPressStart = (LongPressStartDetails details) {
                      _held(instance.primaryPointer);
                    }
                    ..onLongPressEnd = (LongPressEndDetails details) {
                      _release();
                    }
                    ..onLongPressCancel = _release;
                },
              ),
        },
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
        -math.pi / 2,
        2 * math.pi * held,
        false,
        Paint()
          ..color = kRecordingDotRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  /// Картинка нажатий не ловит: иначе отрисовщик закрыл бы собой
  /// кнопку под точкой (как подсветка найденного в BUG-43). Удержание
  /// слушает распознаватель над ней.
  @override
  bool? hitTest(Offset position) => false;

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
    // Вопрос могли закрыть и мимо кнопок — нажатием вокруг него; тогда
    // закрывать уже нечего.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      return;
    }
    _closed = true;
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
