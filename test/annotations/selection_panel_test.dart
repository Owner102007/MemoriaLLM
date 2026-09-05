import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/ui/reader/prompt_preview_sheet.dart';
import 'package:memoria/ui/reader/selection_panel.dart';

/// Панель действий над выделением.
///
/// Проверяется главное обещание сессии: кнопки промптов подписаны так, как
/// их назвал читатель, и ни одна из них не молчит.
SelectionPrompt prompt(String id, String name) {
  return SelectionPrompt(
    id: id,
    name: name,
    body: 'Объясни {{выделение}}',
    position: 0,
    createdAt: DateTime.utc(2026, 9, 6),
    updatedAt: DateTime.utc(2026, 9, 6),
  );
}

Widget host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 800, child: Stack(children: <Widget>[child])),
    ),
  );
}

void main() {
  testWidgets('кнопки подписаны именами промптов читателя', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        SelectionPanel(
          anchor: const Rect.fromLTWH(50, 300, 200, 24),
          area: const Size(400, 800),
          prompts: PromptSet(
            prompts: <SelectionPrompt>[
              prompt('p1', 'Значение'),
              prompt('p2', 'Этимология'),
            ],
            fromBook: false,
          ),
          onPrompt: (_) {},
          onQuote: () {},
          onNote: () {},
          onCopy: () {},
        ),
      ),
    );

    expect(find.text('Значение'), findsOneWidget);
    expect(find.text('Этимология'), findsOneWidget);
    expect(find.byKey(const Key('selection-action-quote')), findsOneWidget);
    expect(find.byKey(const Key('selection-action-note')), findsOneWidget);
    expect(find.byKey(const Key('selection-action-copy')), findsOneWidget);
  });

  testWidgets('нажатия доходят до экрана чтения', (WidgetTester tester) async {
    String? pressed;
    int quotes = 0;
    int notes = 0;
    int copies = 0;
    await tester.pumpWidget(
      host(
        SelectionPanel(
          anchor: const Rect.fromLTWH(50, 300, 200, 24),
          area: const Size(400, 800),
          prompts: PromptSet(
            prompts: <SelectionPrompt>[prompt('p1', 'Значение')],
            fromBook: false,
          ),
          onPrompt: (SelectionPrompt value) => pressed = value.id,
          onQuote: () => quotes++,
          onNote: () => notes++,
          onCopy: () => copies++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('selection-prompt-p1')));
    await tester.tap(find.byKey(const Key('selection-action-quote')));
    await tester.tap(find.byKey(const Key('selection-action-note')));
    await tester.tap(find.byKey(const Key('selection-action-copy')));
    await tester.pump();

    expect(pressed, 'p1');
    expect(quotes, 1);
    expect(notes, 1);
    expect(copies, 1);
  });

  testWidgets('без промптов панель всё равно умеет цитаты и копирование', (
    WidgetTester tester,
  ) async {
    // Читатель вправе удалить все промпты — панель от этого не исчезает:
    // цитата и копирование к модели отношения не имеют.
    await tester.pumpWidget(
      host(
        SelectionPanel(
          anchor: const Rect.fromLTWH(50, 300, 200, 24),
          area: const Size(400, 800),
          prompts: PromptSet.empty,
          onPrompt: (_) {},
          onQuote: () {},
          onNote: () {},
          onCopy: () {},
        ),
      ),
    );
    expect(find.byKey(const Key('selection-panel')), findsOneWidget);
    expect(find.byKey(const Key('selection-action-copy')), findsOneWidget);
  });

  testWidgets('нажатие на промпт показывает готовый запрос, а не молчит', (
    WidgetTester tester,
  ) async {
    // Ответов модели в этой сессии нет, и кнопка обязана сказать об этом
    // прямо — вместе с тем, что именно уйдёт в модель.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptPreviewSheet(
            prompt: prompt('p1', 'Значение'),
            request: 'Объясни «ineffable» в отрывке: It was ineffable joy.',
          ),
        ),
      ),
    );
    expect(find.text('Значение'), findsOneWidget);
    expect(find.textContaining('появятся в следующей сессии'), findsOneWidget);
    expect(find.textContaining('ineffable'), findsOneWidget);
    expect(find.byKey(const Key('prompt-preview-copy')), findsOneWidget);
  });
}
