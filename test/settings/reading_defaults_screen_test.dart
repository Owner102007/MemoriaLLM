import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/settings/reading_defaults_screen.dart';
import 'package:memoria/ui/settings/settings_screen.dart';

/// Настройки в памяти: ни базы, ни настоящего времени.
///
/// Widget-тесты живут в подменённом времени, а база — в настоящем;
/// экрану из двух выключателей хватает словаря.
class _MemorySettings implements AppSettingsRepository {
  _MemorySettings([Map<String, String>? values])
    : values = values ?? <String, String>{};

  /// Что лежит в «базе».
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Stream<String?> watch(String key) => Stream<String?>.value(values[key]);
}

const Key _switch = Key('page-preview-switch');
const Key _reserve = Key('page-reserve');

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AppSettingsRepository settings,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingDefaultsScreen(settings: settings)),
    );
    await tester.pumpAndSettle();
  }

  bool previewOn(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(_switch)).value;

  SegmentedButton<int> reserve(WidgetTester tester) =>
      tester.widget<SegmentedButton<int>>(find.byKey(_reserve));

  testWidgets('F-READ-02: без сохранённого — сразу, запас одна страница', (
    WidgetTester tester,
  ) async {
    // Тесты идут как на телефоне: там запас по умолчанию — страница.
    await pumpScreen(tester, _MemorySettings());

    expect(previewOn(tester), isTrue);
    expect(reserve(tester).selected, <int>{1});
    expect(reserve(tester).onSelectionChanged, isNotNull);
  });

  testWidgets('F-READ-02: сохранённые настройки показаны как есть', (
    WidgetTester tester,
  ) async {
    final _MemorySettings settings = _MemorySettings(<String, String>{
      SettingsKeys.pagePreview: 'false',
      SettingsKeys.pageReserve: '0',
    });
    await pumpScreen(tester, settings);

    expect(previewOn(tester), isFalse);
    expect(reserve(tester).selected, <int>{0});
  });

  testWidgets('F-READ-02: выключатель пишет настройку и гасит запас', (
    WidgetTester tester,
  ) async {
    final _MemorySettings settings = _MemorySettings();
    await pumpScreen(tester, settings);

    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();

    expect(settings.values[SettingsKeys.pagePreview], 'false');
    expect(previewOn(tester), isFalse);
    // Наготове держатся грубые картинки: без них запас выбирать не из
    // чего, и кнопки это показывают, а не молча ничего не делают.
    expect(reserve(tester).onSelectionChanged, isNull);
    expect(find.textContaining('держать нечего'), findsOneWidget);

    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.pagePreview], 'true');
    expect(reserve(tester).onSelectionChanged, isNotNull);
  });

  testWidgets('F-READ-02: запас соседних страниц пишется в настройки', (
    WidgetTester tester,
  ) async {
    final _MemorySettings settings = _MemorySettings();
    await pumpScreen(tester, settings);

    await tester.tap(find.byKey(const Key('page-reserve-2')));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.pageReserve], '2');
    expect(reserve(tester).selected, <int>{2});

    await tester.tap(find.byKey(const Key('page-reserve-0')));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.pageReserve], '0');
    expect(reserve(tester).selected, <int>{0});
  });

  testWidgets('F-READ-02: раздел открывается из настроек', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          themeController: ThemeController(),
          settings: _MemorySettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder tile = find.byKey(const Key('reading-defaults-tile'));
    await tester.scrollUntilVisible(tile, 200);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byKey(_switch), findsOneWidget);
    expect(find.byKey(_reserve), findsOneWidget);
  });
}
