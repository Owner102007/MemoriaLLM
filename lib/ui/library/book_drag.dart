import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/library/book.dart';

/// Книга, которую сейчас несут по полке.
///
/// В перетаскивание уезжает не только книга, но и категория, из которой
/// её взяли: без неё цель не знает, перестановка это внутри участка или
/// переезд в чужой, — а от этого зависит, какой список перенумеровывать.
@immutable
class DraggedBook {
  /// Создаёт груз.
  const DraggedBook({required this.book, required this.fromCategoryId});

  /// Сама книга.
  final Book book;

  /// Категория, из которой её взяли; `null` — «Без категории».
  final String? fromCategoryId;
}

/// Берётся ли книга сразу или после долгого нажатия.
///
/// На телефоне палец сначала прокручивает полку, и брать книгу по
/// касанию нельзя вовсе — прокрутка перестала бы работать. Мышь ничего
/// не прокручивает движением по экрану, поэтому на ПК книга берётся
/// сразу: ждать полсекунды, держа кнопку, там неоткуда взявшаяся
/// задержка (решение владельца, 24.08.2026).
bool dragStartsImmediately(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return false;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      return true;
  }
}

/// Обёртка, делающая блок полки перетаскиваемым.
///
/// Один виджет на обе платформы: разница — только в том, начинается
/// перетаскивание сразу или после удержания, и решает это
/// [dragStartsImmediately].
class BookDragHandle extends StatelessWidget {
  /// Создаёт обёртку.
  const BookDragHandle({
    required this.payload,
    required this.child,
    required this.feedbackSize,
    this.onDragStarted,
    this.onDragEnded,
    super.key,
  });

  /// Что несём.
  final DraggedBook payload;

  /// Сам блок.
  final Widget child;

  /// Размер карточки под пальцем.
  final Size feedbackSize;

  /// Книгу подняли.
  final VoidCallback? onDragStarted;

  /// Книгу отпустили — где угодно, в том числе мимо.
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    // Карточка держится **центром под пальцем**, а не тем углом, за
    // который её взяли. Причина не в красоте: цель определяет сторону
    // вставки по положению груза, а `DragTargetDetails.offset` — это
    // левый верхний угол карточки. Совместив его с пальцем, мы получаем
    // в цели настоящее положение пальца, а карточку возвращаем на место
    // сдвигом при отрисовке.
    final Widget feedback = FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: _Feedback(size: feedbackSize, child: child),
    );
    // Место, откуда книгу взяли, гаснет, но не схлопывается: сетка,
    // перестраивающаяся под рукой, уводит цель из-под пальца.
    final Widget hole = Opacity(opacity: 0.25, child: child);

    if (dragStartsImmediately(Theme.of(context).platform)) {
      return Draggable<DraggedBook>(
        data: payload,
        feedback: feedback,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: hole,
        onDragStarted: onDragStarted,
        onDragEnd: (DraggableDetails details) => onDragEnded?.call(),
        onDraggableCanceled: (Velocity v, Offset o) => onDragEnded?.call(),
        child: child,
      );
    }
    return LongPressDraggable<DraggedBook>(
      data: payload,
      feedback: feedback,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: hole,
      hapticFeedbackOnStart: true,
      onDragStarted: onDragStarted,
      onDragEnd: (DraggableDetails details) => onDragEnded?.call(),
      onDraggableCanceled: (Velocity v, Offset o) => onDragEnded?.call(),
      child: child,
    );
  }
}

/// Карточка под пальцем: приподнятая и чуть уменьшенная.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: SizedBox(
          width: size.width,
          height: size.height,
          // Чуть меньше своего места на полке: так видно, что книга
          // сейчас в руке, а не стоит.
          child: Transform.scale(
            scale: 0.94,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Место, куда встанет книга: полоска между блоками.
///
/// Показывается до отпускания — читатель обязан видеть, куда попадёт
/// книга, а не узнавать об этом после.
class DropSlot extends StatelessWidget {
  /// Создаёт полоску.
  const DropSlot({required this.active, super.key});

  /// Наведена ли книга прямо сейчас.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: active ? 4 : 0,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
