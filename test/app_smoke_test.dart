import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/ui/app.dart';

void main() {
  testWidgets('приложение запускается на экране библиотеки', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MemoriaApp(themeController: ThemeController()));
    await tester.pumpAndSettle();

    expect(find.text('Memoria LLM HB'), findsOneWidget);
    expect(find.byKey(const Key('nav-library')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsOneWidget);
  });

  testWidgets('по умолчанию включена тёмно-красная тема', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MemoriaApp(themeController: ThemeController()));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final AppPalette expected = appPalettes[AppThemeId.darkRed]!;
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      Color(expected.background),
    );
  });

  testWidgets('смена темы в настройках перекрашивает приложение', (
    WidgetTester tester,
  ) async {
    final ThemeController controller = ThemeController();
    await tester.pumpWidget(MemoriaApp(themeController: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-sepia')));
    await tester.pumpAndSettle();

    expect(controller.value, AppThemeId.sepia);

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final AppPalette sepia = appPalettes[AppThemeId.sepia]!;
    expect(Theme.of(context).scaffoldBackgroundColor, Color(sepia.background));
  });
}
