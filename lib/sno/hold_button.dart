import 'package:flutter/material.dart';

/// Сколько держат кнопку сброса, чтобы она сработала.
///
/// Две секунды — заметно дольше случайного касания и короче терпения:
/// экспериментатор сбрасывает устройство перед каждым тестировщиком.
const Duration kResetHold = Duration(seconds: 2);

/// Кнопка, которая срабатывает, только если её удерживать
/// (SNO-F-CFG-04).
///
/// Подтверждение удержанием, а не вторым окном: действие необратимо, и
/// случайное нажатие не должно его начать, а вопрос «вы уверены?»
/// закрывают не читая. Пока палец на кнопке, она заполняется слева
/// направо; отпустили раньше — ничего не произошло. Палец, который
/// повёл список, удержанием не считается.
class HoldToConfirmButton extends StatefulWidget {
  /// Создаёт кнопку.
  const HoldToConfirmButton({
    required this.label,
    required this.onConfirmed,
    this.hold = kResetHold,
    super.key,
  });

  /// Подпись.
  final String label;

  /// Что сделать, когда кнопку додержали; `null` — кнопка выключена.
  final VoidCallback? onConfirmed;

  /// Сколько её держать.
  final Duration hold;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.hold,
  )..addStatusListener(_statusChanged);

  @override
  void didUpdateWidget(HoldToConfirmButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fill.duration = widget.hold;
    // Кнопку выключили, пока её держали, — удержание не засчитывается.
    if (widget.onConfirmed == null) {
      _fill.reset();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    final VoidCallback? confirmed = widget.onConfirmed;
    _fill.reset();
    confirmed?.call();
  }

  void _press() {
    if (widget.onConfirmed != null) {
      _fill.forward(from: 0);
    }
  }

  void _release() {
    if (_fill.isAnimating) {
      _fill.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = widget.onConfirmed != null;
    final Color ink = enabled
        ? theme.colorScheme.onSurface
        : theme.disabledColor;
    final Color edge = enabled ? theme.colorScheme.error : theme.disabledColor;
    final BorderRadius radius = BorderRadius.circular(8);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails details) => _press(),
        onTapUp: (TapUpDetails details) => _release(),
        onTapCancel: _release,
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: edge),
              borderRadius: radius,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _fill,
                    builder: (BuildContext context, Widget? child) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _fill.value,
                        child: ColoredBox(color: edge.withValues(alpha: 0.35)),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(color: ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
