import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../domain/reading/reader_gestures.dart';

/// Слушает сырые события указателя над [child] и сообщает о нажатии в
/// тот миг, когда указатель поднят (BUG-37).
///
/// Ничего не отбирает: в арене жестов слушатель не участвует, и всё, что
/// умеет [child] — выделение, протяжка, щипок, — работает как работало.
/// Правило «что считать нажатием» живёт в [TapWatch]; его держит тот,
/// кто строит этот виджет, — ему же приходит сообщение просмотрщика о
/// том же нажатии, и только он может сверить одно с другим.
class QuickTap extends StatelessWidget {
  /// Создаёт слушателя.
  const QuickTap({
    required this.watch,
    required this.onTap,
    required this.child,
    super.key,
  });

  /// Правило нажатия и его память.
  final TapWatch watch;

  /// Нажатие в точке — в координатах этого виджета.
  final ValueChanged<Offset> onTap;

  /// То, по чему нажимают.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) => watch.down(
        pointer: event.pointer,
        position: event.localPosition,
        time: event.timeStamp,
        kind: event.kind,
        // Кнопки спрашиваются только у мыши: палец и перо приходят с
        // разными признаками на разных платформах, а правой кнопки у них
        // нет.
        primary:
            event.kind != PointerDeviceKind.mouse ||
            event.buttons == kPrimaryButton,
      ),
      onPointerMove: (PointerMoveEvent event) =>
          watch.move(pointer: event.pointer, position: event.localPosition),
      onPointerUp: (PointerUpEvent event) {
        final Offset? at = watch.up(
          pointer: event.pointer,
          position: event.localPosition,
          time: event.timeStamp,
        );
        if (at != null) {
          onTap(at);
        }
      },
      onPointerCancel: (PointerCancelEvent event) =>
          watch.cancel(pointer: event.pointer),
      child: child,
    );
  }
}
