import 'package:flutter/material.dart';

import '../../domain/reading/progress_slot.dart';

/// Указатель места в книге в виде самой книги.
///
/// Стопка прочитанного растёт, стопка непрочитанного тает — то самое
/// ощущение толщины, которого электронной книге не хватает больше всего.
/// Указатель живёт в поле вокруг страницы и **не исчезает вместе с
/// панелями**: без него, спрятав интерфейс, читатель теряет всякое
/// представление о том, где он.
class ReadingProgressBook extends StatelessWidget {
  /// Создаёт указатель.
  const ReadingProgressBook({
    required this.slot,
    required this.page,
    required this.pageCount,
    super.key,
  });

  /// Место, отданное указателю.
  final ProgressSlot slot;

  /// Текущая страница, начиная с единицы.
  final int page;

  /// Всего страниц.
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    if (!slot.isVisible || pageCount < 1) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final double share = (page / pageCount).clamp(0.0, 1.0);
    final Color ink = theme.colorScheme.onSurface;

    final Widget label = Text(
      '$page / $pageCount',
      key: const Key('reader-progress-label'),
      style: theme.textTheme.labelSmall?.copyWith(
        color: ink.withValues(alpha: 0.7),
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );

    final Widget book = CustomPaint(
      key: const Key('reader-progress-book'),
      painter: _BookPainter(
        share: share,
        vertical: slot.isVertical,
        read: theme.colorScheme.primary,
        rest: ink.withValues(alpha: 0.28),
      ),
    );

    return Positioned(
      left: slot.left,
      top: slot.top,
      width: slot.width,
      height: slot.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Поверх страницы указателю нужна подложка, иначе он
            // потеряется в тексте; в свободном поле она лишняя.
            color: slot.overlaps
                ? theme.colorScheme.surface.withValues(alpha: 0.72)
                : Colors.transparent,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: slot.isVertical
                ? Column(
                    children: <Widget>[
                      Expanded(child: book),
                      const SizedBox(height: 4),
                      RotatedBox(quarterTurns: 1, child: label),
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: book),
                      const SizedBox(width: 8),
                      label,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Книга сбоку: слева прочитанное, справа оставшееся.
class _BookPainter extends CustomPainter {
  const _BookPainter({
    required this.share,
    required this.vertical,
    required this.read,
    required this.rest,
  });

  final double share;
  final bool vertical;
  final Color read;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    final double length = vertical ? size.height : size.width;
    final double thickness = vertical ? size.width : size.height;
    if (length <= 0 || thickness <= 0) {
      return;
    }
    final double bar = thickness < 6 ? thickness : 6;
    final double offset = (thickness - bar) / 2;
    final double edge = length * share;

    Rect along(double from, double to) {
      return vertical
          ? Rect.fromLTRB(offset, from, offset + bar, to)
          : Rect.fromLTRB(from, offset, to, offset + bar);
    }

    final Radius radius = Radius.circular(bar / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(along(0, length), radius),
      Paint()..color = rest,
    );
    if (edge > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(along(0, edge), radius),
        Paint()..color = read,
      );
    }

    // Насечки — срез страниц. Их немного и они бледные: указатель должен
    // читаться боковым зрением, а не притягивать взгляд от текста.
    final Paint notch = Paint()
      ..color = rest.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const int notches = 12;
    for (int i = 1; i < notches; i++) {
      final double at = length * i / notches;
      canvas.drawLine(
        vertical ? Offset(offset, at) : Offset(at, offset),
        vertical ? Offset(offset + bar, at) : Offset(at, offset + bar),
        notch,
      );
    }
  }

  @override
  bool shouldRepaint(_BookPainter oldDelegate) =>
      oldDelegate.share != share ||
      oldDelegate.vertical != vertical ||
      oldDelegate.read != read ||
      oldDelegate.rest != rest;
}
