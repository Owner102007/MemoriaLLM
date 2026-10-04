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
///
/// По горизонтали панель стоит **по середине выделения** и шириной по
/// своим кнопкам (BUG-03): место ей назначается после того, как она
/// измерена, — заранее её ширины не знает никто, она зависит от имён
/// промптов читателя.
class SelectionPanel extends StatelessWidget {
  /// Создаёт панель.
  const SelectionPanel({
    required this.anchor,
    required this.prompts,
    required this.onPrompt,
    required this.onQuote,
    required this.onNote,
    required this.onCopy,
    this.onFind,
    super.key,
  });

  /// Панель экрана чтения: с моделью или без неё (SNO-F-READ-01).
  ///
  /// С моделью ([models]) — промпты читателя и три действия, как было.
  /// Без неё — в сборках ветвей СНО2026 — промптов нет, какими бы ни
  /// были [prompts], а четвёртым действием стоит «Найти в книге»
  /// ([onFind]). Решение живёт здесь, а не в экране чтения: лист с
  /// выделением в тестах не строится, а панель проверяется.
  const SelectionPanel.forReader({
    required this.anchor,
    required bool models,
    required PromptSet prompts,
    required this.onPrompt,
    required this.onQuote,
    required this.onNote,
    required this.onCopy,
    required VoidCallback onFind,
    super.key,
  }) : prompts = models ? prompts : PromptSet.empty,
       onFind = models ? null : onFind;

  /// Сколько места панель занимает по высоте вместе с отступами, когда
  /// в ней два ряда — промпты и действия.
  ///
  /// На экране высота берётся настоящая, измеренная; это число — для
  /// расчётов, которым измерить панель негде.
  static const double height = 108;

  /// Отступ панели от краёв области.
  static const double margin = 8;

  /// Ниже этой ширины панель не сжимается и на самом узком экране.
  static const double minWidth = 240;

  /// Отступ панели от выделения.
  static const double gap = 10;

  /// Прямоугольник выделения — в координатах области, которую панель
  /// занимает: размер области она узнаёт сама, при раскладке.
  final Rect anchor;

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

  /// Найти выделенное в книге.
  ///
  /// `null` — действия нет. Оно есть в сборках ветвей СНО2026
  /// (SNO-F-READ-01): там нет модели, ряд промптов пуст, и панель — это
  /// один ряд из четырёх значков.
  final VoidCallback? onFind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // BUG-03: место панели считается по её настоящему размеру. Прежде
    // она считалась шириной во весь экран и потому всегда стояла у
    // левого края — на широком окне ПК в полуэкране от выделенного.
    return CustomSingleChildLayout(
      delegate: _PanelPlace(anchor: anchor),
      child: Material(
        key: const Key('selection-panel'),
        color: theme.colorScheme.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                      for (final SelectionPrompt prompt in prompts.prompts)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
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
              // Три подписи в ряд не помещаются в телефон в портрете:
              // «Копировать» уезжало за край экрана, и до него
              // приходилось бы доскроллить. Подписей у действий поэтому
              // нет — только значки и всплывающие подсказки. Имена
              // остаются там, где они и есть смысл: на кнопках промптов,
              // которые читатель назвал сам.
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
                  // Прежние три стоят как стояли; новое — последним.
                  if (onFind case final VoidCallback find)
                    _Action(
                      id: 'find',
                      icon: Icons.manage_search,
                      label: 'Найти в книге',
                      onPressed: find,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ставит панель на место, когда её размер уже известен (BUG-03).
///
/// Слой занимает всю область над страницей, но нажатия ловит только
/// сама панель: мимо неё они проходят к странице, как и прежде.
class _PanelPlace extends SingleChildLayoutDelegate {
  const _PanelPlace({required this.anchor});

  /// Прямоугольник выделения на экране.
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Панель не шире области без полей — длинный ряд промптов тогда
    // прокручивается внутри неё, — но и не уже своего минимума.
    final double room = constraints.maxWidth - SelectionPanel.margin * 2;
    return BoxConstraints(
      maxWidth: room < SelectionPanel.minWidth ? SelectionPanel.minWidth : room,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return panelOffset(
      anchor: anchor,
      area: size,
      width: childSize.width,
      height: childSize.height,
    );
  }

  @override
  bool shouldRelayout(_PanelPlace oldDelegate) {
    return oldDelegate.anchor != anchor;
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
    return IconButton(
      key: Key('selection-action-$id'),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: label,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Куда встать панели над выделением — чистая математика.
///
/// Сверху, если там есть место; иначе снизу. Если места нет нигде — а так
/// бывает, когда выделен весь экран, — панель прижимается к нижнему краю:
/// она нужнее, чем вид на последнюю строку выделения.
///
/// По горизонтали — по середине выделения (ALG-UI-18, BUG-03): [width] —
/// настоящая ширина панели, а не ширина экрана. У края страницы панель
/// прижимается к нему с отступом [SelectionPanel.margin] и за экран не
/// выходит.
Offset panelOffset({
  required Rect anchor,
  required Size area,
  required double width,
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
  const double margin = SelectionPanel.margin;
  double left = anchor.center.dx - width / 2;
  // Правый край проверяется первым, левый — последним: панель шире
  // области обязана начинаться у левого поля, а не уезжать влево.
  final double limit = area.width - margin - width;
  if (left > limit) {
    left = limit;
  }
  if (left < margin) {
    left = margin;
  }
  return Offset(left, top);
}

/// К чему привязать панель: прямоугольник всего выделения (BUG-25).
///
/// Обычно это объединение прямоугольников выделения по строкам. Если их
/// нет вовсе — ни наших, ни от просмотрщика, — панель всё равно
/// показывается: привязка уходит в середину области. Выделено, а сделать
/// с выделенным ничего нельзя — хуже, чем панель не на своём месте.
///
/// Именно в середину, а не к краю: у верхнего и у нижнего края поверх
/// листа ложатся панели чтения и полоса поиска, и панель под ними была
/// бы видна, но недоступна нажатию.
Rect panelAnchor({required List<Rect> rects, required Size area}) {
  if (rects.isEmpty) {
    return Rect.fromLTWH(area.width / 2, area.height / 2, 0, 0);
  }
  return rects.reduce((Rect a, Rect b) => a.expandToInclude(b));
}
