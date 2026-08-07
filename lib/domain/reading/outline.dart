/// Оглавление в том виде, в котором его рисует список.
///
/// Дерево удобно движку PDF, но не списку на экране: `ListView` хочет
/// плоский массив, а отступ и «свёрнут/развёрнут» — это данные, а не
/// состояние виджета. Здесь дерево разворачивается в плоский список,
/// и всё это — чистые функции, которые тестируются без экрана.
library;

import 'reader_document.dart';

/// Пункт оглавления, готовый к отрисовке строкой списка.
class FlatOutlineEntry {
  /// Создаёт пункт.
  const FlatOutlineEntry({
    required this.id,
    required this.title,
    required this.depth,
    required this.hasChildren,
    this.pageNumber,
  });

  /// Устойчивый идентификатор пункта: путь в дереве вида `0.2.1`.
  ///
  /// Заголовки в оглавлениях повторяются («Введение» в каждой части),
  /// поэтому опознавать пункт по названию нельзя.
  final String id;

  /// Заголовок.
  final String title;

  /// Глубина вложенности, 0 — верхний уровень.
  final int depth;

  /// Есть ли вложенные пункты.
  final bool hasChildren;

  /// Страница назначения; `null` — пункт без разобранного назначения.
  final int? pageNumber;

  /// Можно ли по пункту перейти.
  bool get isNavigable => pageNumber != null;

  @override
  String toString() => 'FlatOutlineEntry($id, $title, depth: $depth)';
}

/// Разворачивает дерево оглавления в плоский список.
///
/// [expanded] — идентификаторы развёрнутых узлов. Узлы верхнего уровня
/// показываются всегда; дети показываются, только если родитель развёрнут.
/// Если [expandAll] истинно, [expanded] игнорируется и показывается всё
/// дерево — так удобно тестам и печати.
List<FlatOutlineEntry> flattenOutline(
  List<OutlineEntry> nodes, {
  Set<String> expanded = const <String>{},
  bool expandAll = false,
}) {
  final List<FlatOutlineEntry> result = <FlatOutlineEntry>[];
  void walk(List<OutlineEntry> level, int depth, String prefix) {
    for (int i = 0; i < level.length; i++) {
      final OutlineEntry node = level[i];
      final String id = prefix.isEmpty ? '$i' : '$prefix.$i';
      result.add(
        FlatOutlineEntry(
          id: id,
          title: node.title.trim().isEmpty ? 'Без названия' : node.title.trim(),
          depth: depth,
          hasChildren: node.children.isNotEmpty,
          pageNumber: node.pageNumber,
        ),
      );
      if (node.children.isEmpty) {
        continue;
      }
      if (expandAll || expanded.contains(id)) {
        walk(node.children, depth + 1, id);
      }
    }
  }

  walk(nodes, 0, '');
  return result;
}

/// Идентификаторы всех узлов, у которых есть дети, до глубины [depth].
///
/// Нужны для разумного состояния панели при открытии: полностью
/// свёрнутое оглавление бесполезно, полностью развёрнутое на большой
/// книге — простыня на тысячу строк.
Set<String> outlineIdsToDepth(List<OutlineEntry> nodes, {int depth = 1}) {
  final Set<String> ids = <String>{};
  void walk(List<OutlineEntry> level, int current, String prefix) {
    for (int i = 0; i < level.length; i++) {
      final OutlineEntry node = level[i];
      final String id = prefix.isEmpty ? '$i' : '$prefix.$i';
      if (node.children.isNotEmpty && current < depth) {
        ids.add(id);
        walk(node.children, current + 1, id);
      }
    }
  }

  walk(nodes, 0, '');
  return ids;
}

/// Глубина дерева: 0 — оглавления нет, 1 — плоский список.
int outlineDepth(List<OutlineEntry> nodes) {
  int deepest = 0;
  for (final OutlineEntry node in nodes) {
    final int depth = 1 + outlineDepth(node.children);
    if (depth > deepest) {
      deepest = depth;
    }
  }
  return deepest;
}

/// Сколько всего узлов в дереве.
int outlineSize(List<OutlineEntry> nodes) {
  int total = 0;
  for (final OutlineEntry node in nodes) {
    total += 1 + outlineSize(node.children);
  }
  return total;
}

/// Идентификатор пункта, в котором читатель сейчас находится.
///
/// Берётся последний по документу пункт, чья страница не больше текущей:
/// оглавление подсвечивает раздел, а не ближайшую строчку. Возвращает
/// `null`, если оглавления нет или все его пункты дальше текущей страницы.
String? currentOutlineId(List<OutlineEntry> nodes, int page) {
  String? best;
  int bestPage = 0;
  void walk(List<OutlineEntry> level, String prefix) {
    for (int i = 0; i < level.length; i++) {
      final OutlineEntry node = level[i];
      final String id = prefix.isEmpty ? '$i' : '$prefix.$i';
      final int? target = node.pageNumber;
      if (target != null && target <= page && target >= bestPage) {
        bestPage = target;
        best = id;
      }
      walk(node.children, id);
    }
  }

  walk(nodes, '');
  return best;
}

/// Идентификаторы всех предков пункта [id]: `0.2.1` → `{0, 0.2}`.
///
/// Нужны, чтобы раскрыть путь к подсвеченному пункту, а не показать
/// подсветку внутри свёрнутой ветки.
Set<String> outlineAncestors(String id) {
  final List<String> parts = id.split('.');
  final Set<String> result = <String>{};
  for (int i = 1; i < parts.length; i++) {
    result.add(parts.take(i).join('.'));
  }
  return result;
}
