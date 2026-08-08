import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/ui/reader/crop_editor_screen.dart';

import '../support/fake_reading.dart';

/// Экран правки рамки проверяется без ожидания превью: страница
/// подгружается сама по себе, а рамка двигается независимо от неё.
/// Ждать превью через `pumpAndSettle` нельзя — крутилка загрузки крутится
/// вечно, и тест повис бы на ней.
void main() {
  late FakeReaderDocument document;
  CropBox? result;

  setUp(() {
    document = FakeReaderDocument(pages: const <String>['страница']);
    result = null;
  });

  Future<void> open(
    WidgetTester tester, {
    CropBox initial = CropBox.full,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<CropBox>(
                      MaterialPageRoute<CropBox>(
                        builder: (BuildContext context) => CropEditorScreen(
                          document: document,
                          pageNumber: 1,
                          initial: initial,
                        ),
                      ),
                    );
                  },
                  child: const Text('править рамку'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('править рамку'));
    // Переход на экран: одного кадра мало, а `pumpAndSettle` упрётся
    // в крутилку загрузки превью.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('crop-apply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('рамка возвращается той же, если её не трогали', (
    WidgetTester tester,
  ) async {
    const CropBox initial = CropBox(
      left: 0.1,
      top: 0.2,
      right: 0.9,
      bottom: 0.8,
    );
    await open(tester, initial: initial);
    await apply(tester);
    expect(result, initial);
  });

  testWidgets('левый край двигается вправо и рамка сужается', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.drag(find.byKey(const Key('crop-left')), const Offset(60, 0));
    await tester.pump();
    await apply(tester);

    expect(result, isNotNull);
    expect(result!.left, greaterThan(0));
    expect(result!.right, 1);
    expect(result!.isValid, isTrue);
  });

  testWidgets('верхний край двигается вниз', (WidgetTester tester) async {
    await open(tester);
    await tester.drag(find.byKey(const Key('crop-top')), const Offset(0, 40));
    await tester.pump();
    await apply(tester);

    expect(result!.top, greaterThan(0));
    expect(result!.bottom, 1);
  });

  testWidgets('рамку нельзя вывернуть наизнанку', (
    WidgetTester tester,
  ) async {
    await open(tester);
    // Тянем левый край далеко за правый: рамка обязана остаться рамкой.
    await tester.drag(
      find.byKey(const Key('crop-left')),
      const Offset(4000, 0),
    );
    await tester.pump();
    await apply(tester);

    expect(result!.isValid, isTrue);
    expect(result!.width, greaterThanOrEqualTo(0.1));
  });

  testWidgets('сброс возвращает страницу целиком', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      initial: const CropBox(left: 0.3, top: 0.3, right: 0.7, bottom: 0.7),
    );
    await tester.tap(find.byKey(const Key('crop-reset')));
    await tester.pump();
    await apply(tester);

    expect(result, CropBox.full);
  });

  testWidgets('сказано, что рамка ляжет на всю книгу', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('crop-hint')), findsOneWidget);
  });
}
