import 'package:flutter/material.dart';

import '../../domain/reading/reader_gestures.dart';

/// Подсказка о зонах листания поверх страницы (F-READ-23).
///
/// Показывается один раз — при первой открытой книге: слева «Назад»,
/// справа «Вперёд», посередине «Панели». Зоны нарисованы той ширины,
/// какая действует на самом деле, поэтому подсказка заодно показывает,
/// что изменила настройка ширины.
///
/// Первое нажатие — в любое место — убирает подсказку и больше ничего не
/// делает: читатель, который тянется прочитать подпись, не должен при
/// этом перелистнуть страницу.
class TapZoneHint extends StatelessWidget {
  /// Создаёт подсказку.
  const TapZoneHint({
    required this.zone,
    required this.onDismiss,
    this.keyboard = false,
    super.key,
  });

  /// Ширина зоны листания с каждой стороны, доля ширины экрана.
  final double zone;

  /// Подсказку убрали.
  final VoidCallback onDismiss;

  /// Есть ли у устройства клавиатура: на ПК подсказка говорит и о ней.
  final bool keyboard;

  static const String _captionTouch =
      'Нажатие по краю листает, в середину — показывает панели. '
      'Ширина зон — в настройках. Нажмите, чтобы начать читать.';

  static const String _captionKeyboard =
      'Нажатие по краю листает, в середину — показывает панели. '
      'Клавиши листания и ширина зон — в настройках. Нажмите, чтобы '
      'начать читать.';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int side = readerTapZonePercent(zone);
    final int middle = 100 - side * 2;
    final Color veil = colors.surface.withValues(alpha: 0.86);
    final Color edge = colors.primary.withValues(alpha: 0.28);
    final TextStyle? label = theme.textTheme.titleMedium?.copyWith(
      color: colors.onSurface,
    );
    return GestureDetector(
      key: const Key('tap-zone-hint'),
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  key: const Key('tap-zone-hint-back'),
                  flex: side,
                  child: _Zone(
                    color: Color.alphaBlend(edge, veil),
                    line: colors.primary,
                    lineOnRight: true,
                    child: Text('‹ Назад', style: label),
                  ),
                ),
                Expanded(
                  key: const Key('tap-zone-hint-middle'),
                  flex: middle,
                  child: _Zone(
                    color: veil,
                    child: Text('Панели', style: label),
                  ),
                ),
                Expanded(
                  key: const Key('tap-zone-hint-forward'),
                  flex: side,
                  child: _Zone(
                    color: Color.alphaBlend(edge, veil),
                    line: colors.primary,
                    lineOnRight: false,
                    child: Text('Вперёд ›', style: label),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(
              top: false,
              child: Text(
                keyboard ? _captionKeyboard : _captionTouch,
                key: const Key('tap-zone-hint-caption'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Одна зона подсказки: подложка, подпись и черта у границы с серединой.
class _Zone extends StatelessWidget {
  const _Zone({
    required this.color,
    required this.child,
    this.line,
    this.lineOnRight = false,
  });

  final Color color;
  final Widget child;

  /// Цвет черты; `null` — зона без черты.
  final Color? line;

  /// С какой стороны зоны черта.
  final bool lineOnRight;

  @override
  Widget build(BuildContext context) {
    final Color? stroke = line;
    final BorderSide side = stroke == null
        ? BorderSide.none
        : BorderSide(color: stroke, width: 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: lineOnRight ? BorderSide.none : side,
          right: lineOnRight ? side : BorderSide.none,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }
}
