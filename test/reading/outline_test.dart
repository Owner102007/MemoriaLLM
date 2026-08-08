import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/outline.dart';
import 'package:memoria/domain/reading/reader_document.dart';

/// Оглавление в три уровня — такое же, как в корпусном
/// `test/fixtures/outline_nested.pdf`.
const List<OutlineEntry> _nested = <OutlineEntry>[
  OutlineEntry(
    title: 'Часть I',
    pageNumber: 1,
    children: <OutlineEntry>[
      OutlineEntry(
        title: 'Глава 1',
        pageNumber: 2,
        children: <OutlineEntry>[
          OutlineEntry(title: 'Раздел 1.1', pageNumber: 3),
          OutlineEntry(title: 'Раздел 1.2', pageNumber: 4),
        ],
      ),
      OutlineEntry(title: 'Глава 2', pageNumber: 5),
    ],
  ),
  OutlineEntry(
    title: 'Часть II',
    pageNumber: 7,
    children: <OutlineEntry>[OutlineEntry(title: 'Глава 3', pageNumber: 8)],
  ),
];

void main() {
  group('flattenOutline', () {
    test('свёрнутое дерево показывает только верхний уровень', () {
      final List<FlatOutlineEntry> items = flattenOutline(_nested);
      expect(items.map((FlatOutlineEntry e) => e.title), <String>[
        'Часть I',
        'Часть II',
      ]);
      expect(items.every((FlatOutlineEntry e) => e.depth == 0), isTrue);
      expect(items.first.hasChildren, isTrue);
    });

    test('развёрнутый узел показывает своих детей и только их', () {
      final List<FlatOutlineEntry> items = flattenOutline(
        _nested,
        expanded: <String>{'0'},
      );
      expect(items.map((FlatOutlineEntry e) => e.title), <String>[
        'Часть I',
        'Глава 1',
        'Глава 2',
        'Часть II',
      ]);
      expect(items[1].depth, 1);
    });

    test('expandAll показывает всё дерево', () {
      final List<FlatOutlineEntry> items = flattenOutline(
        _nested,
        expandAll: true,
      );
      expect(items.length, outlineSize(_nested));
      final int deepest = items
          .map((FlatOutlineEntry e) => e.depth)
          .reduce((int a, int b) => a > b ? a : b);
      expect(deepest, 2);
    });

    test('идентификаторы — путь в дереве и они уникальны', () {
      final List<FlatOutlineEntry> items = flattenOutline(
        _nested,
        expandAll: true,
      );
      final List<String> ids = items.map((FlatOutlineEntry e) => e.id).toList();
      expect(ids, <String>['0', '0.0', '0.0.0', '0.0.1', '0.1', '1', '1.0']);
      expect(ids.toSet().length, ids.length);
    });

    test('пустой заголовок не оставляет пустую строку в списке', () {
      final List<FlatOutlineEntry> items = flattenOutline(const <OutlineEntry>[
        OutlineEntry(title: '   ', pageNumber: 1),
      ]);
      expect(items.single.title, 'Без названия');
    });

    test('пункт без страницы виден, но не нажимается', () {
      final List<FlatOutlineEntry> items = flattenOutline(const <OutlineEntry>[
        OutlineEntry(title: 'Приложение'),
      ]);
      expect(items.single.isNavigable, isFalse);
    });

    test('пустое оглавление даёт пустой список', () {
      expect(flattenOutline(const <OutlineEntry>[]), isEmpty);
    });
  });

  group('размеры дерева', () {
    test('глубина и число узлов', () {
      expect(outlineDepth(_nested), 3);
      expect(outlineSize(_nested), 7);
      expect(outlineDepth(const <OutlineEntry>[]), 0);
      expect(outlineSize(const <OutlineEntry>[]), 0);
    });
  });

  group('outlineIdsToDepth', () {
    test('по умолчанию раскрывает только верхний уровень', () {
      expect(outlineIdsToDepth(_nested), <String>{'0', '1'});
    });

    test('глубина два раскрывает и вторые уровни', () {
      expect(outlineIdsToDepth(_nested, depth: 2), <String>{'0', '1', '0.0'});
    });
  });

  group('currentOutlineId', () {
    test('подсвечивает раздел, в котором читатель находится', () {
      expect(currentOutlineId(_nested, 3), '0.0.0');
      expect(currentOutlineId(_nested, 6), '0.1');
      expect(currentOutlineId(_nested, 9), '1.0');
    });

    test('до первого пункта подсвечивать нечего', () {
      const List<OutlineEntry> startsLater = <OutlineEntry>[
        OutlineEntry(title: 'Глава', pageNumber: 5),
      ];
      expect(currentOutlineId(startsLater, 2), isNull);
    });

    test('оглавления нет — подсветки нет', () {
      expect(currentOutlineId(const <OutlineEntry>[], 3), isNull);
    });
  });

  group('outlineAncestors', () {
    test('путь к пункту', () {
      expect(outlineAncestors('0.2.1'), <String>{'0', '0.2'});
      expect(outlineAncestors('3'), isEmpty);
    });
  });
}
