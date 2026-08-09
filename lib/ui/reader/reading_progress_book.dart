import 'package:flutter/material.dart';

import '../../domain/reading/progress_slot.dart';

/// Указатель места в книге — сама книга, вид сбоку.
///
/// Слева стопка прочитанного, справа — оставшегося; по мере чтения левая
/// растёт, правая тает. Толщина зависит от объёма файла, поэтому тонкая
/// брошюра и том в тысячу страниц выглядят по-разному. Это то самое
/// ощущение толщины, которого электронной книге не хватает больше всего.
///
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

  /// Наибольшая ширина рисунка книги.
  static const double maxBookWidth = 56;

  /// Высота рисунка книги.
  static const double bookHeight = 20;

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
    final Color ink = theme.colorScheme.onSurface;
    final double width = slot.width - 8 < maxBookWidth
        ? slot.width - 8
        : maxBookWidth;

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
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (width > 12)
                    SizedBox(
                      width: width,
                      height: bookHeight,
                      child: CustomPaint(
                        key: const Key('reader-progress-book'),
                        painter: _OpenBookPainter(
                          share: (page / pageCount).clamp(0.0, 1.0),
                          pageCount: pageCount,
                          read: theme.colorScheme.primary,
                          rest: ink.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '$page / $pageCount',
                    key: const Key('reader-progress-label'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.75),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Раскрытая книга сбоку: две стопки страниц, сходящиеся у корешка.
class _OpenBookPainter extends CustomPainter {
  const _OpenBookPainter({
    required this.share,
    required this.pageCount,
    required this.read,
    required this.rest,
  });

  /// Какая доля книги прочитана.
  final double share;

  /// Объём книги: от него зависит толщина стопки.
  final int pageCount;

  /// Цвет прочитанного.
  final Color read;

  /// Цвет оставшегося.
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 4 || size.height <= 4) {
      return;
    }
    final double base = size.height - 1;
    final double spine = size.width / 2;

    // Тонкая брошюра и том в тысячу страниц не должны выглядеть одинаково.
    final double fullness = pageCount >= 800 ? 1 : pageCount / 800;
    final double thickness = size.height * (0.35 + 0.6 * fullness);
    final double left = thickness * share;
    final double right = thickness * (1 - share);

    void stack(double from, double to, double height, Color color) {
      if (height <= 0.4) {
        return;
      }
      final Path path = Path()
        ..moveTo(from, base)
        ..lineTo(from, base - height)
        ..lineTo(to, base - 1.5)
        ..lineTo(to, base)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    stack(0, spine, left, read);
    stack(size.width, spine, right, rest);

    // Корешок: без него две стопки выглядят как две отдельные книги.
    canvas.drawLine(
      Offset(spine, base),
      Offset(spine, base - 2.5),
      Paint()
        ..color = rest
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_OpenBookPainter oldDelegate) =>
      oldDelegate.share != share ||
      oldDelegate.pageCount != pageCount ||
      oldDelegate.read != read ||
      oldDelegate.rest != rest;
}
