import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/reader/key_bindings.dart';
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
const Key _reset = Key('turn-keys-reset');
const Key _addForward = Key('turn-key-add-forward');
const Key _addBack = Key('turn-key-add-back');
const Key _dialog = Key('key-capture-dialog');

/// Раздел настроек «Клавиши и громкость»: на телефоне — листание
/// кнопками громкости (F-READ-26), на ПК — таблица клавиш (F-READ-25).
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

  testWidgets('F-READ-26: на телефоне таблицы клавиш нет', (
    WidgetTester tester,
  ) async {
    // Тесты идут как на телефоне: у него кнопки громкости, а не клавиатура.
    await pumpScreen(tester, _MemorySettings());

    expect(find.byKey(_switch), findsOneWidget);
    expect(find.byKey(_reset), findsNothing);
    expect(find.byKey(_addForward), findsNothing);
  });

  group('F-READ-25: таблица клавиш на ПК', () {
    final TestVariant<TargetPlatform> desktop = TargetPlatformVariant.only(
      TargetPlatform.windows,
    );
    final int space = LogicalKeyboardKey.space.keyId;
    final int letter = LogicalKeyboardKey.keyJ.keyId;

    Finder chip(String turn, String code) => find.byKey(
      Key('turn-key-$turn-$code'),
    );

    /// Открывает окно «нажмите клавишу» у действия.
    Future<void> askKey(WidgetTester tester, Key add) async {
      await tester.tap(find.byKey(add));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsOneWidget);
    }

    testWidgets('раздел открывается из настроек и показывает таблицу', (
      WidgetTester tester,
    ) async {
      await pumpSettings(tester);

      final Finder tile = find.byKey(_tile);
      await tester.scrollUntilVisible(tile, 200);
      await tester.pump();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byKey(_reset), findsOneWidget);
      expect(find.byKey(_addForward), findsOneWidget);
      // Кнопок громкости у читалки на ПК нет.
      expect(find.byKey(_switch), findsNothing);
    }, variant: desktop);

    testWidgets('из коробки: вперёд — пробел, PgDn, → и ↓; назад — '
        'Shift+пробел, PgUp, ← и ↑', (WidgetTester tester) async {
      await pumpScreen(tester, _MemorySettings());

      for (final KeyStroke stroke in KeyBindings.standard.forward) {
        expect(chip('forward', stroke.encode()), findsOneWidget);
      }
      for (final KeyStroke stroke in KeyBindings.standard.back) {
        expect(chip('back', stroke.encode()), findsOneWidget);
      }
      for (final String label in <String>[
        'Пробел',
        'PgDn',
        '→',
        '↓',
        'Shift+Пробел',
        'PgUp',
        '←',
        '↑',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Возвращать нечего — и кнопка это показывает.
      expect(
        tester.widget<TextButton>(find.byKey(_reset)).onPressed,
        isNull,
      );
      expect(find.byKey(const Key('turn-keys-fixed')), findsOneWidget);
    }, variant: desktop);

    testWidgets('клавиша назначается нажатием и пишется в настройки', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await askKey(tester, _addForward);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsNothing);
      expect(chip('forward', '$letter'), findsOneWidget);
      expect(find.text('J'), findsOneWidget);
      final KeyBindings saved = KeyBindings.parse(
        settings.values[SettingsKeys.turnKeys],
      );
      expect(saved.turnFor(LogicalKeyboardKey.keyJ), TurnKey.forward);
      // Прежние клавиши при этом на месте.
      expect(saved.turnFor(LogicalKeyboardKey.space), TurnKey.forward);
      expect(
        tester.widget<TextButton>(find.byKey(_reset)).onPressed,
        isNotNull,
      );
    }, variant: desktop);

    testWidgets('Shift входит в клавишу', (WidgetTester tester) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await askKey(tester, _addBack);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      // Модификатор сам по себе окно не закрывает.
      expect(find.byKey(_dialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(chip('back', 's$letter'), findsOneWidget);
      expect(find.text('Shift+J'), findsOneWidget);
      final KeyBindings saved = KeyBindings.parse(
        settings.values[SettingsKeys.turnKeys],
      );
      expect(
        saved.turnFor(LogicalKeyboardKey.keyJ, shift: true),
        TurnKey.back,
      );
      expect(saved.turnFor(LogicalKeyboardKey.keyJ), isNull);
    }, variant: desktop);

    testWidgets('занятая клавиша переезжает, и об этом сказано', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await askKey(tester, _addBack);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(chip('back', '$space'), findsOneWidget);
      expect(chip('forward', '$space'), findsNothing);
      expect(find.byKey(const Key('turn-key-moved')), findsOneWidget);
      final KeyBindings saved = KeyBindings.parse(
        settings.values[SettingsKeys.turnKeys],
      );
      expect(saved.turnFor(LogicalKeyboardKey.space), TurnKey.back);
    }, variant: desktop);

    testWidgets('клавишу со своим делом назначить нельзя', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await askKey(tester, _addForward);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();

      // Окно объясняет отказ и ждёт другую клавишу.
      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.byKey(const Key('key-capture-refusal')), findsOneWidget);
      expect(settings.values.containsKey(SettingsKeys.turnKeys), isFalse);

      // Esc закрывает окно, ничего не назначив.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
      expect(settings.values.containsKey(SettingsKeys.turnKeys), isFalse);
    }, variant: desktop);

    testWidgets('сочетание с Ctrl назначить нельзя', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await askKey(tester, _addForward);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.byKey(const Key('key-capture-refusal')), findsOneWidget);
      expect(settings.values.containsKey(SettingsKeys.turnKeys), isFalse);

      await tester.tap(find.byKey(const Key('key-capture-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
    }, variant: desktop);

    testWidgets('клавиша убирается крестиком', (WidgetTester tester) async {
      final _MemorySettings settings = _MemorySettings();
      await pumpScreen(tester, settings);

      await tester.tap(
        find.descendant(
          of: chip('forward', '$space'),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(chip('forward', '$space'), findsNothing);
      final KeyBindings saved = KeyBindings.parse(
        settings.values[SettingsKeys.turnKeys],
      );
      expect(saved.turnFor(LogicalKeyboardKey.space), isNull);
      expect(saved.turnFor(LogicalKeyboardKey.pageDown), TurnKey.forward);
    }, variant: desktop);

    testWidgets('сохранённая таблица показана как есть', (
      WidgetTester tester,
    ) async {
      final KeyBindings custom = KeyBindings.standard
          .assign(TurnKey.forward, const KeyStroke(LogicalKeyboardKey.keyJ))
          .without(
            TurnKey.forward,
            const KeyStroke(LogicalKeyboardKey.space),
          );
      await pumpScreen(
        tester,
        _MemorySettings(<String, String>{
          SettingsKeys.turnKeys: custom.encode(),
        }),
      );

      expect(chip('forward', '$letter'), findsOneWidget);
      expect(chip('forward', '$space'), findsNothing);
    }, variant: desktop);

    testWidgets('«Вернуть как было» убирает настройку', (
      WidgetTester tester,
    ) async {
      final _MemorySettings settings = _MemorySettings(<String, String>{
        SettingsKeys.turnKeys: 'f:$letter;b:',
      });
      await pumpScreen(tester, settings);
      expect(chip('forward', '$letter'), findsOneWidget);
      expect(chip('forward', '$space'), findsNothing);

      await tester.tap(find.byKey(_reset));
      await tester.pumpAndSettle();

      expect(settings.values.containsKey(SettingsKeys.turnKeys), isFalse);
      expect(chip('forward', '$letter'), findsNothing);
      expect(chip('forward', '$space'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(_reset)).onPressed,
        isNull,
      );
    }, variant: desktop);
  });
}
