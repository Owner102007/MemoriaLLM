import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/ui/app.dart';

import 'data/test_data.dart';
import 'support/fake_reading.dart';

void main() {
  late AppData data;
  late AppServices services;

  setUp(() async {
    data = await openTestData();
    services = AppServices(
      data: data,
      opener: FakeDocumentOpener(FakeReaderDocument(pages: <String>['текст'])),
      picker: FakeBookFilePicker(null),
    );
  });
  tearDown(() async => data.close());

  Future<void> pumpApp(WidgetTester tester, ThemeController controller) async {
    await tester.pumpWidget(
      MemoriaApp(themeController: controller, services: services),
    );
    await tester.pumpAndSettle();
  }

  /// Снимает дерево виджетов и даёт базе прибраться.
  ///
  /// Живые запросы drift при отписке планируют отложенную уборку обычным
  /// таймером. В widget-тестах время подменено, и такой таймер, оставшийся
  /// после теста, валит его сообщением «A Timer is still pending». Поэтому
  /// экран снимается явно и прокручивается ещё один кадр — уборка
  /// случается внутри теста, а не после него.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('приложение запускается на экране библиотеки', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, ThemeController());

    expect(find.text('Memoria LLM HB'), findsOneWidget);
    expect(find.byKey(const Key('nav-library')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsOneWidget);
    expect(find.byKey(const Key('library-open-file')), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('по умолчанию включена тёмно-красная тема', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, ThemeController());

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final AppPalette expected = appPalettes[AppThemeId.darkRed]!;
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      Color(expected.background),
    );

    await unmount(tester);
  });

  testWidgets('смена темы в настройках перекрашивает приложение', (
    WidgetTester tester,
  ) async {
    final ThemeController controller = ThemeController();
    await pumpApp(tester, controller);

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-sepia')));
    await tester.pumpAndSettle();

    expect(controller.value, AppThemeId.sepia);

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final AppPalette sepia = appPalettes[AppThemeId.sepia]!;
    expect(Theme.of(context).scaffoldBackgroundColor, Color(sepia.background));

    await unmount(tester);
  });

  testWidgets('на пустой полке предложено открыть файл', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, ThemeController());

    expect(find.byKey(const Key('library-open-file-empty')), findsOneWidget);
    expect(find.byKey(const Key('library-list')), findsNothing);

    // Человек закрыл диалог, ничего не выбрав: приложение не должно
    // ни падать, ни заводить пустую книгу.
    await tester.tap(find.byKey(const Key('library-open-file-empty')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-list')), findsNothing);

    await unmount(tester);
  });
}
