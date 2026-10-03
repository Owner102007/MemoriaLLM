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

  group('F-READ-23: зоны листания', () {
    const Key slider = Key('tap-zone-slider');
    const Key value = Key('tap-zone-value');
    const Key again = Key('tap-zone-hint-reset');

    String shown(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(value)).data!;

    /// Экран длиннее тестового окна: до нижних настроек надо домотать.
    Future<void> reach(WidgetTester tester, Key key) async {
      await tester.scrollUntilVisible(find.byKey(key), 200);
      await tester.pump();
    }

    testWidgets('без сохранённого зона — тридцать процентов', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, _MemorySettings());
      await reach(tester, slider);

      expect(shown(tester), '30 %');
      expect(tester.widget<Slider>(find.byKey(slider)).value, 30);
      expect(find.byKey(const Key('tap-zone-preview')), findsOneWidget);
    });

    testWidgets('сохранённая ширина показана как есть', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        _MemorySettings(<String, String>{SettingsKeys.tapZone: '15'}),
      );
      await reach(tester, slider);

      expect(shown(tester), '15 %');
      expect(tester.widget<Slider>(find.byKey(slider)).value, 15);
    });

    testWidgets('ползунок пишет ширину зоны в настройки', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);
      await reach(tester, slider);

      await tester.drag(find.byKey(slider), const Offset(800, 0));
      await tester.pumpAndSettle();
      // Шире нельзя: между зонами обязана остаться середина.
      expect(settings.values[SettingsKeys.tapZone], '45');
      expect(shown(tester), '45 %');

      await tester.drag(find.byKey(slider), const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(settings.values[SettingsKeys.tapZone], '10');
      expect(shown(tester), '10 %');
    });

    testWidgets('пока ползунок тянут, в настройки не пишется', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);
      await reach(tester, slider);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(slider)),
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(400, 0));
      await tester.pump();
      // Образец уже показывает новую ширину, а запись — по отпусканию.
      expect(shown(tester), '45 %');
      expect(settings.values.containsKey(SettingsKeys.tapZone), isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.values[SettingsKeys.tapZone], '45');
    });

    testWidgets('«Показать подсказку ещё раз» снимает отметку о показе', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings(<String, String>{
        SettingsKeys.tapZoneHintSeen: 'true',
      });
      await pumpScreen(tester, settings);
      await reach(tester, again);

      await tester.tap(find.byKey(again));
      await tester.pumpAndSettle();

      expect(
        settings.values.containsKey(SettingsKeys.tapZoneHintSeen),
        isFalse,
      );
      expect(find.byKey(const Key('tap-zone-hint-again')), findsOneWidget);
    });
  });
}
