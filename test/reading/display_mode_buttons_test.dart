import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/ui/reader/display_mode_buttons.dart';

/// Кнопки-дроби в верхней панели чтения.
void main() {
  late List<PageDisplayMode> picked;

  Future<void> pump(WidgetTester tester, PageDisplayMode mode) async {
    picked = <PageDisplayMode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DisplayModeButtons(
            mode: mode,
            onMode: (PageDisplayMode value) => picked.add(value),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('обе дроби есть прямо в чтении', (WidgetTester tester) async {
    await pump(tester, PageDisplayMode.full);
    expect(find.byKey(const Key('reader-mode-half-button')), findsOneWidget);
    expect(find.byKey(const Key('reader-mode-third-button')), findsOneWidget);
    // Дробь нарисована цифрами, а не символом `½`: в системном шрифте
    // его может не быть, и кнопка осталась бы пустым прямоугольником.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('дробь включает свой режим', (WidgetTester tester) async {
    await pump(tester, PageDisplayMode.full);

    await tester.tap(find.byKey(const Key('reader-mode-half-button')));
    expect(picked, <PageDisplayMode>[PageDisplayMode.half]);

    await tester.tap(find.byKey(const Key('reader-mode-third-button')));
    expect(picked.last, PageDisplayMode.third);
  });

  testWidgets('повторное нажатие возвращает страницу целиком', (
    WidgetTester tester,
  ) async {
    // Кнопка включает режим и она же его выключает: искать выход из
    // половины в панели настроек читателю не придётся.
    await pump(tester, PageDisplayMode.half);
    await tester.tap(find.byKey(const Key('reader-mode-half-button')));
    expect(picked, <PageDisplayMode>[PageDisplayMode.full]);
  });

  testWidgets('чужая дробь переключает режим, а не выключает его', (
    WidgetTester tester,
  ) async {
    await pump(tester, PageDisplayMode.half);
    await tester.tap(find.byKey(const Key('reader-mode-third-button')));
    expect(picked, <PageDisplayMode>[PageDisplayMode.third]);
  });

  testWidgets('включённый режим видно по кнопке', (WidgetTester tester) async {
    await pump(tester, PageDisplayMode.third);
    final IconButton third = tester.widget<IconButton>(
      find.byKey(const Key('reader-mode-third-button')),
    );
    final IconButton half = tester.widget<IconButton>(
      find.byKey(const Key('reader-mode-half-button')),
    );
    expect(third.tooltip, 'Вернуть страницу целиком');
    expect(half.tooltip, 'Половина страницы');
  });

  testWidgets('разворот не гасит кнопки: из него тоже делят страницу', (
    WidgetTester tester,
  ) async {
    await pump(tester, PageDisplayMode.spread);
    await tester.tap(find.byKey(const Key('reader-mode-half-button')));
    expect(picked, <PageDisplayMode>[PageDisplayMode.half]);
  });
}
