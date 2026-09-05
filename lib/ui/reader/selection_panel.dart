import 'package:flutter/material.dart';

import '../../domain/prompts/selection_prompt.dart';

/// Панель действий над выделением.
///
/// Кнопки промптов идут первыми и подписаны так, как их назвал читатель:
/// приложение не знает, что такое «Значение» или «Этимология», оно знает
/// только имя записи. Ответов модели в этой сессии ещё нет — нажатие на
/// промпт честно показывает, что именно уйдёт в модель, и говорит, когда
/// она появится. **Молчащая кнопка хуже отсутствующей.**
///
/// Панель встаёт над выделением, а если сверху места нет — под ним. Ни
/// то, ни другое не должно накрывать сам выделенный текст: читатель
/// смотрит на него, пока выбирает, что с ним сделать.
class SelectionPanel extends StatelessWidget {
  /// Создаёт панель.
  const SelectionPanel({
    required this.anchor,
    required this.area,
    required this.prompts,
    required this.onPrompt,
    required this.onQuote,
    required this.onNote,
    required this.onCopy,
    super.key,
  });

  /// Сколько места панель занимает по высоте вместе с отступами.
  static const double height = 108;

  /// Отступ панели от выделения.
  static const double gap = 10;

  /// Прямоугольник выделения на экране.
  final Rect anchor;

  /// Размер области, в которой стоит панель.
  final Size area;

  /// Промпты читателя.
  final PromptSet prompts;

  /// Нажали промпт.
  final void Function(SelectionPrompt prompt) onPrompt;

  /// Сохранить цитату.
  final VoidCallback onQuote;

  /// Написать заметку.
  final VoidCallback onNote;

  /// Скопировать выделенное.
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Offset at = panelOffset(anchor: anchor, area: area);
    return Stack(
      children: <Widget>[
        Positioned(
          left: at.dx,
          top: at.dy,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: area.width - 16 < 240 ? 240 : area.width - 16,
            ),
            child: Material(
              key: const Key('selection-panel'),
              color: theme.colorScheme.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (prompts.prompts.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final SelectionPrompt prompt
                                in prompts.prompts)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: TextButton(
                                  key: Key('selection-prompt-${prompt.id}'),
                                  onPressed: () => onPrompt(prompt),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: prompt.isPrimary
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                  child: Text(prompt.name),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Action(
                          id: 'quote',
                          icon: Icons.format_quote,
                          label: 'В цитаты',
                          onPressed: onQuote,
                        ),
                        _Action(
                          id: 'note',
                          icon: Icons.edit_note,
                          label: 'Заметка',
                          onPressed: onNote,
                        ),
                        _Action(
                          id: 'copy',
                          icon: Icons.copy_all_outlined,
                          label: 'Копировать',
                          onPressed: onCopy,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: Key('selection-action-$id'),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

/// Куда встать панели над выделением — чистая математика.
///
/// Сверху, если там есть место; иначе снизу. Если места нет нигде — а так
/// бывает, когда выделен весь экран, — панель прижимается к нижнему краю:
/// она нужнее, чем вид на последнюю строку выделения.
Offset panelOffset({
  required Rect anchor,
  required Size area,
  double height = SelectionPanel.height,
  double gap = SelectionPanel.gap,
}) {
  final double above = anchor.top - gap - height;
  final double below = anchor.bottom + gap;
  double top;
  if (above >= 0) {
    top = above;
  } else if (below + height <= area.height) {
    top = below;
  } else {
    top = area.height - height;
  }
  if (top < 0) {
    top = 0;
  }
  // По горизонтали панель встаёт по середине выделения и не вылезает за
  // края: у выделения в углу страницы середина у самого края экрана.
  const double margin = 8;
  final double width = area.width - margin * 2;
  double left = anchor.center.dx - width / 2;
  if (left < margin) {
    left = margin;
  }
  final double limit = area.width - margin - width;
  if (left > limit) {
    left = limit < margin ? margin : limit;
  }
  return Offset(left, top);
}
