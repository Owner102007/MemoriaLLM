import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/ui/reader/selection_panel.dart';

/// Где на экране стоит панель над выделением (ALG-UI-18).
///
/// Панель обязана вставать там, где её ждёт глаз, — над самим
/// выделением. На широком окне ПК это особенно заметно: панель у левого
/// края оказывается в полуэкране от выделенного слова.
SelectionPrompt _prompt(String id, String name) {
  return SelectionPrompt(
    id: id,
    name: name,
    body: 'Объясни {{выделение}}',
    position: 0,
    createdAt: DateTime.utc(2026, 9, 6),
    updatedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  /// Ставит панель над [anchor] на экране размером [area] и возвращает
  /// место, которое она заняла.
  Future<Rect> panelAt(
    WidgetTester tester, {
    required Size area,
    required Rect anchor,
    PromptSet prompts = PromptSet.empty,
  }) async {
    tester.view.physicalSize = area;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: area.width,
            height: area.height,
            child: Stack(
              children: <Widget>[
                SelectionPanel(
                  anchor: anchor,
                  area: area,
                  prompts: prompts,
                  onPrompt: (_) {},
                  onQuote: () {},
                  onNote: () {},
                  onCopy: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tester.getRect(find.byKey(const Key('selection-panel')));
  }

  const Size desktop = Size(1400, 900);
  const Size phone = Size(400, 800);

  group('BUG-03: панель стоит над выделением', () {
    testWidgets('BUG-03: на широком окне панель по середине выделения', (
      WidgetTester tester,
    ) async {
      const Rect anchor = Rect.fromLTWH(900, 400, 200, 24);
      final Rect panel = await panelAt(tester, area: desktop, anchor: anchor);

      expect(
        panel.center.dx,
        closeTo(anchor.center.dx, 1),
        reason: 'панель $panel, выделение $anchor',
      );
      expect(panel.bottom, lessThanOrEqualTo(anchor.top));
    });

    testWidgets('BUG-03: на телефоне узкая панель тоже над выделением', (
      WidgetTester tester,
    ) async {
      const Rect anchor = Rect.fromLTWH(250, 300, 100, 20);
      final Rect panel = await panelAt(tester, area: phone, anchor: anchor);

      expect(panel.width, lessThan(phone.width / 2));
      expect(panel.center.dx, closeTo(anchor.center.dx, 1));
    });

    testWidgets('BUG-03: с кнопками промптов панель остаётся над словом', (
      WidgetTester tester,
    ) async {
      const Rect anchor = Rect.fromLTWH(700, 500, 80, 24);
      final Rect panel = await panelAt(
        tester,
        area: desktop,
        anchor: anchor,
        prompts: PromptSet(
          prompts: <SelectionPrompt>[
            _prompt('p1', 'Значение'),
            _prompt('p2', 'Перевод'),
          ],
          fromBook: false,
        ),
      );

      expect(panel.center.dx, closeTo(anchor.center.dx, 1));
    });

    testWidgets('BUG-03: у краёв панель прижата и не уходит за экран', (
      WidgetTester tester,
    ) async {
      final Rect right = await panelAt(
        tester,
        area: desktop,
        anchor: const Rect.fromLTWH(1385, 400, 15, 24),
      );
      expect(right.right, closeTo(desktop.width - 8, 0.5));

      final Rect left = await panelAt(
        tester,
        area: desktop,
        anchor: const Rect.fromLTWH(0, 400, 15, 24),
      );
      expect(left.left, closeTo(8, 0.5));
    });
  });
}
