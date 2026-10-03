import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/page_text.dart';
import '../support/test_services.dart';

/// Шаг 08: поиск по книге на экране чтения.
///
/// Сам лист с настоящим PDFium в widget-тестах не строится; здесь
/// проверяется то, что от него не зависит: куда ведёт переход к
/// найденному.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppData data;

  setUp(() async {
    data = await openTestData();
  });
  tearDown(() async => data.close());

  /// Снимает дерево виджетов и даёт базе прибраться (см.
  /// `reader_controls_test`).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Страница, где искомое слово стоит в нижней половине.
  final PageTextLayout lower = buildLayout(<TestLine>[
    const TestLine('первая строка страницы', top: 0.10),
    const TestLine('вторая строка страницы', top: 0.14),
    const TestLine('здесь внизу лежит тройка', top: 0.80),
    const TestLine('последняя строка страницы', top: 0.84),
  ]);

  Future<void> pumpReader(WidgetTester tester) async {
    await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
    final Book book = testBook();
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: testServices(
            data: data,
            document: FakeReaderDocument(
              pages: <String>['вступление', lower.text, 'окончание'],
              layouts: <int, PageTextLayout>{2: lower},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReaderScaffold scaffoldOf(WidgetTester tester) =>
      tester.widget<ReaderScaffold>(find.byType(ReaderScaffold));

  testWidgets('BUG-10: переход к найденному ведёт в полосу, где оно лежит', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    final ReaderController controller = scaffoldOf(tester).controller;
    await controller.setDisplayMode(PageDisplayMode.half);
    await tester.pumpAndSettle();
    expect(controller.fragmentCount, 2, reason: 'страница делится пополам');

    await scaffoldOf(tester).search.start('тройка');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
    // Прежде переход всегда вёл в первую полосу страницы, и найденное в
    // нижней половине оставалось в тени или за экраном.
    expect(controller.fragment, 1, reason: 'найденное — в нижней полосе');

    await unmount(tester);
  });

  testWidgets('BUG-10: читателя на той же странице к её началу не возвращает', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    final ReaderController controller = scaffoldOf(tester).controller;
    await controller.setDisplayMode(PageDisplayMode.half);
    await controller.goToPage(2, fragment: 1);
    await tester.pumpAndSettle();
    expect(controller.fragment, 1);

    await scaffoldOf(tester).search.start('тройка');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
    expect(controller.fragment, 1, reason: 'найденное уже на экране');

    await unmount(tester);
  });
}
