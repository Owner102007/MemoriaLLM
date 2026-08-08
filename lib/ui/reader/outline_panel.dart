import 'package:flutter/material.dart';

import '../../application/reading/reader_controller.dart';
import '../../domain/reading/outline.dart';
import '../../domain/reading/reader_document.dart';

/// Панель оглавления.
///
/// Дерево разворачивается в плоский список в `domain/reading/outline.dart`,
/// здесь остаётся только рисование. Раздел, в котором читатель сейчас
/// находится, подсвечен, и путь к нему раскрыт: подсветка внутри
/// свёрнутой ветки не помогает никому.
class OutlinePanel extends StatefulWidget {
  /// Создаёт панель.
  const OutlinePanel({
    required this.controller,
    required this.onSelect,
    super.key,
  });

  /// Состояние книги.
  final ReaderController controller;

  /// Переход по выбранному пункту.
  final void Function(int page) onSelect;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  Set<String>? _expanded;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Set<String> _expandedFor(List<OutlineEntry> nodes, int page) {
    // Первое открытие: раскрыт верхний уровень плюс путь к текущему
    // разделу. Дальше состояние принадлежит человеку, и трогать его
    // при каждой перерисовке нельзя.
    final Set<String>? chosen = _expanded;
    if (chosen != null) {
      return chosen;
    }
    final Set<String> initial = outlineIdsToDepth(nodes);
    final String? current = currentOutlineId(nodes, page);
    if (current != null) {
      initial.addAll(outlineAncestors(current));
    }
    return _expanded = initial;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReaderController controller = widget.controller;
    final List<OutlineEntry>? nodes = controller.outline;

    return Drawer(
      key: const Key('outline-panel'),
      width: 340,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Оглавление', style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(child: _body(context, nodes)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<OutlineEntry>? nodes) {
    final ThemeData theme = Theme.of(context);
    if (nodes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'В этой книге нет оглавления. Так бывает у сканов и у книг, '
          'собранных из отдельных страниц: содержание есть на бумаге, '
          'но в файл его не положили.',
          key: const Key('outline-empty'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final int page = widget.controller.page;
    final Set<String> expanded = _expandedFor(nodes, page);
    final List<FlatOutlineEntry> items = flattenOutline(
      nodes,
      expanded: expanded,
    );
    final String? currentId = currentOutlineId(nodes, page);

    return ListView.builder(
      key: const Key('outline-list'),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final FlatOutlineEntry item = items[index];
        final bool isCurrent = item.id == currentId;
        return ListTile(
          key: Key('outline-item-${item.id}'),
          dense: true,
          selected: isCurrent,
          contentPadding: EdgeInsets.only(left: 16 + item.depth * 16, right: 8),
          leading: item.hasChildren
              ? IconButton(
                  key: Key('outline-toggle-${item.id}'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    expanded.contains(item.id)
                        ? Icons.expand_more
                        : Icons.chevron_right,
                  ),
                  onPressed: () => setState(() {
                    if (!expanded.remove(item.id)) {
                      expanded.add(item.id);
                    }
                  }),
                )
              : null,
          title: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          trailing: item.pageNumber == null
              ? null
              : Text('${item.pageNumber}', style: theme.textTheme.bodySmall),
          onTap: item.isNavigable
              ? () => widget.onSelect(item.pageNumber!)
              : null,
        );
      },
    );
  }
}
