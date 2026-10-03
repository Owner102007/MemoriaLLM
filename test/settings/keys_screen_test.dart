import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/settings/keys_screen.dart';
import 'package:memoria/ui/settings/settings_screen.dart';

/// Настройки в памяти: ни базы, ни настоящего времени.
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

const Key _switch = Key('volume-keys-switch');
const Key _direction = Key('volume-down-direction');
const Key _tile = Key('keys-tile');

/// F-READ-26: раздел настроек «Клавиши и громкость».
void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    AppSettingsRepository settings,
  ) async {
    await tester.pumpWidget(MaterialApp(home: KeysScreen(settings: settings)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          themeController: ThemeController(),
          settings: _MemorySettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(_switch)).value;

  SegmentedButton<bool> direction(WidgetTester tester) =>
      tester.widget<SegmentedButton<bool>>(find.byKey(_direction));

  testWidgets('F-READ-26: без сохранённого — включено, «вниз» вперёд', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, _MemorySettings());

    expect(enabled(tester), isTrue);
    expect(direction(tester).selected, <bool>{true});
    expect(direction(tester).onSelectionChanged, isNotNull);
  });

  testWidgets('F-READ-26: сохранённые настройки показаны как есть', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      _MemorySettings(<String, String>{
        SettingsKeys.volumeKeys: 'false',
        SettingsKeys.volumeDownForward: 'false',
      }),
    );

    expect(enabled(tester), isFalse);
    expect(direction(tester).selected, <bool>{false});
  });

  testWidgets('F-READ-26: выключатель пишет настройку и гасит направление', (
    WidgetTester tester,
  ) async {
    final _MemorySettings settings = _MemorySettings();
    await pumpScreen(tester, settings);

    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();

    expect(settings.values[SettingsKeys.volumeKeys], 'false');
    expect(enabled(tester), isFalse);
    // Выбирать направление не у чего, и кнопки это показывают, а не
    // молча ничего не делают.
    expect(direction(tester).onSelectionChanged, isNull);
    expect(find.textContaining('только меняют громкость'), findsOneWidget);

    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.volumeKeys], 'true');
    expect(direction(tester).onSelectionChanged, isNotNull);
  });

  testWidgets('F-READ-26: направление пишется в настройки', (
    WidgetTester tester,
  ) async {
    final _MemorySettings settings = _MemorySettings();
    await pumpScreen(tester, settings);

    await tester.tap(find.byKey(const Key('volume-down-back')));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.volumeDownForward], 'false');
    expect(direction(tester).selected, <bool>{false});

    await tester.tap(find.byKey(const Key('volume-down-forward')));
    await tester.pumpAndSettle();
    expect(settings.values[SettingsKeys.volumeDownForward], 'true');
    expect(direction(tester).selected, <bool>{true});
  });

  testWidgets('F-READ-26: раздел открывается из настроек телефона', (
    WidgetTester tester,
  ) async {
    // Тесты идут как на телефоне.
    await pumpSettings(tester);

    final Finder tile = find.byKey(_tile);
    await tester.scrollUntilVisible(tile, 200);
    // Нажатие считает место по последнему кадру: без него оно ушло бы
    // туда, где плитка была до прокрутки.
    await tester.pump();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.byKey(_switch), findsOneWidget);
    expect(find.byKey(_direction), findsOneWidget);
  });

  testWidgets('F-READ-26: на ПК раздела нет', (WidgetTester tester) async {
    // Кнопок громкости у читалки на ПК нет, а таблица клавиш ещё не
    // сделана (F-READ-25): пустой раздел был бы обманом.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpSettings(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('build-label')),
        200,
      );
      expect(find.byKey(_tile), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
