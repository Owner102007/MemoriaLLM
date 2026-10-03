import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/full_screen.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/window_settle.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/reader/key_bindings.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// Шаг 07: как читатель управляет страницей на экране чтения.
///
/// Правила — ширина зон, таблица клавиш, отсчёт окна — проверены числами
/// в `reader_gestures_test`, `key_bindings_test` и `window_settle_test`.
/// Здесь — то, чего числами не проверить: что экран чтения берёт их из
/// настроек устройства, показывает подсказку один раз, прячет в ленте
/// недействующие кнопки и держит лист, пока окно меняют.
///
/// Сам лист с настоящим PDFium в widget-тестах не строится: на его месте
/// стоит пустое место того же размера, и этого хватает, чтобы увидеть,
/// какой размер ему отвели.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppData data;
  late FakeFullScreenWindow window;

  setUp(() async {
    data = await openTestData();
    window = FakeFullScreenWindow();
  });
  tearDown(() async => data.close());

  /// Снимает дерево виджетов и даёт базе прибраться: живые запросы drift
  /// при отписке планируют уборку обычным таймером, а в widget-тестах
  /// время подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpReader(
    WidgetTester tester, {
    Map<String, String> settings = const <String, String>{},
    bool hasWindow = false,
  }) async {
    for (final MapEntry<String, String> entry in settings.entries) {
      await data.settings.write(entry.key, entry.value);
    }
    final Book book = testBook();
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: testServices(
            data: data,
            document: FakeReaderDocument(
              pages: List<String>.generate(6, (int i) => 'страница ${i + 1}'),
            ),
            window: hasWindow ? window : const NoFullScreenWindow(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showChrome(WidgetTester tester) async {
    tester
        .state<ReaderScaffoldState>(find.byType(ReaderScaffold))
        .toggleChrome();
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('reader-page-label'))).data!;

  final Finder hint = find.byKey(const Key('tap-zone-hint'));

  Future<String?> hintSeen() =>
      data.settings.read(SettingsKeys.tapZoneHintSeen);

  group('F-READ-23: подсказка о зонах листания', () {
    testWidgets('показывается при первой открытой книге', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester);

      expect(hint, findsOneWidget);
      expect(find.text('‹ Назад'), findsOneWidget);
      expect(find.text('Панели'), findsOneWidget);
      expect(find.text('Вперёд ›'), findsOneWidget);
      // Отметка о показе записана сразу, а не по нажатию.
      expect(await hintSeen(), 'true');

      await unmount(tester);
    });

    testWidgets('нажатие убирает подсказку и не листает', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester);
      expect(label(tester), '1 / 6');

      // Нажатие в правую зону: без подсказки оно листало бы вперёд.
      await tester.tapAt(const Offset(760, 300));
      await tester.pumpAndSettle();

      expect(hint, findsNothing);
      expect(label(tester), '1 / 6');

      await unmount(tester);
    });

    testWidgets('не появляется второй раз', (WidgetTester tester) async {
      await pumpReader(tester);
      expect(hint, findsOneWidget);
      // Книгу закрыли, так и не нажав на подсказку.
      await unmount(tester);

      await pumpReader(tester);
      expect(hint, findsNothing);

      await unmount(tester);
    });

    testWidgets('уже показанная подсказка не показывается', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        settings: <String, String>{SettingsKeys.tapZoneHintSeen: 'true'},
      );

      expect(hint, findsNothing);

      await unmount(tester);
    });

    testWidgets('листание клавишей убирает подсказку', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester);
      expect(hint, findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(hint, findsNothing);
      expect(label(tester), '2 / 6');

      await unmount(tester);
    });

    testWidgets('в ленте подсказки нет, и показанной она не считается', (
      WidgetTester tester,
    ) async {
      // В ленте зон нет: подсказка дождётся листания по страницам.
      await pumpReader(
        tester,
        settings: <String, String>{
          SettingsKeys.pageFlow: PageFlow.continuous.name,
        },
      );

      expect(hint, findsNothing);
      expect(await hintSeen(), isNull);

      await unmount(tester);
    });

    testWidgets('зоны подсказки — той ширины, что в настройках', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        settings: <String, String>{SettingsKeys.tapZone: '15'},
      );

      final double screen = tester.getSize(hint).width;
      final double back = tester
          .getSize(find.byKey(const Key('tap-zone-hint-back')))
          .width;
      final double forward = tester
          .getSize(find.byKey(const Key('tap-zone-hint-forward')))
          .width;
      expect(back, closeTo(screen * 0.15, 0.5));
      expect(forward, closeTo(screen * 0.15, 0.5));

      await unmount(tester);
    });
  });

  group('F-READ-25: таблица клавиш в книге', () {
    testWidgets('листают клавиши, назначенные читателем', (
      WidgetTester tester,
    ) async {
      final KeyBindings bindings = KeyBindings.standard
          .assign(TurnKey.forward, const KeyStroke(LogicalKeyboardKey.keyJ))
          .without(
            TurnKey.forward,
            const KeyStroke(LogicalKeyboardKey.space),
          );
      await pumpReader(
        tester,
        settings: <String, String>{
          SettingsKeys.turnKeys: bindings.encode(),
          SettingsKeys.tapZoneHintSeen: 'true',
        },
      );
      expect(label(tester), '1 / 6');

      await press(tester, LogicalKeyboardKey.keyJ);
      expect(label(tester), '2 / 6');

      // Пробел у листания отобран.
      await press(tester, LogicalKeyboardKey.space);
      expect(label(tester), '2 / 6');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(label(tester), '1 / 6');

      await unmount(tester);
    });

    testWidgets('без настройки листают клавиши из коробки', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        settings: <String, String>{SettingsKeys.tapZoneHintSeen: 'true'},
      );

      await press(tester, LogicalKeyboardKey.space);
      expect(label(tester), '2 / 6');
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(label(tester), '2 / 6');

      await unmount(tester);
    });
  });

  group('BUG-15: в ленте нет кнопок, которые на неё не действуют', () {
    final Finder half = find.byKey(const Key('reader-mode-half-button'));
    final Finder third = find.byKey(const Key('reader-mode-third-button'));
    final Finder lock = find.byKey(const Key('reader-zoom-lock-button'));

    testWidgets('при листании по страницам дроби и замок на месте', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        settings: <String, String>{SettingsKeys.tapZoneHintSeen: 'true'},
      );
      await showChrome(tester);

      expect(half, findsOneWidget);
      expect(third, findsOneWidget);
      expect(lock, findsOneWidget);

      await unmount(tester);
    });

    testWidgets('в ленте дробей и замка в панели нет', (
      WidgetTester tester,
    ) async {
      await pumpReader(
        tester,
        settings: <String, String>{
          SettingsKeys.pageFlow: PageFlow.continuous.name,
        },
      );
      await showChrome(tester);

      expect(half, findsNothing);
      expect(third, findsNothing);
      expect(lock, findsNothing);
      // Шторка, в которой можно вернуться к листанию по страницам, и
      // остальные кнопки панели остаются.
      expect(find.byKey(const Key('reader-settings-button')), findsOneWidget);
      expect(find.byKey(const Key('reader-search-button')), findsOneWidget);

      await unmount(tester);
    });
  });

  group('F-DESK-02: живое окно без растяжения', () {
    /// Место, которое отведено листу.
    Size sheetSize(WidgetTester tester) => tester.getSize(
      find.descendant(
        of: find.byKey(const Key('reader-sheet-box')),
        matching: find.byType(SizedBox),
      ),
    );

    /// Меняет размер окна: и область показа, и то, что знает о ней
    /// система.
    void resize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
    }

    testWidgets('пока окно тянут, лист стоит в прежнем размере', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      await pumpReader(tester, hasWindow: true);
      final Size before = sheetSize(tester);
      expect(before, const Size(800, 600));

      // Окно тянут за угол: размер меняется каждый кадр.
      for (int step = 1; step <= 10; step++) {
        resize(tester, Size(800 + step * 20, 600 + step * 10));
        await tester.pump(const Duration(milliseconds: 16));
        expect(sheetSize(tester), before, reason: 'кадр $step');
      }

      // Окно отпустили: лист перекладывается один раз, под новый размер.
      await tester.pump(kWindowSettle);
      await tester.pump();
      expect(sheetSize(tester), const Size(1000, 700));

      await unmount(tester);
    });

    testWidgets('окно сжимают — лист не сжимается, пока его не отпустят', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      await pumpReader(tester, hasWindow: true);

      resize(tester, const Size(500, 400));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sheetSize(tester), const Size(800, 600));

      await tester.pump(kWindowSettle);
      await tester.pump();
      expect(sheetSize(tester), const Size(500, 400));

      await unmount(tester);
    });

    testWidgets('на телефоне новый размер принимается сразу', (
      WidgetTester tester,
    ) async {
      // Поворот экрана — одно изменение, и ждать после него нечего.
      addTearDown(tester.view.resetPhysicalSize);
      await pumpReader(tester);
      expect(sheetSize(tester), const Size(800, 600));

      resize(tester, const Size(600, 800));
      await tester.pump();
      expect(sheetSize(tester), const Size(600, 800));

      await unmount(tester);
    });

    testWidgets('разворот во весь экран перекладывает лист сразу', (
      WidgetTester tester,
    ) async {
      // F-READ-35: окно меняет размер по нашей же просьбе — это не
      // протяжка, и отсчёта нет.
      addTearDown(tester.view.resetPhysicalSize);
      await pumpReader(tester, hasWindow: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(window.full, isTrue);
      resize(tester, const Size(1920, 1080));
      await tester.pump();
      expect(sheetSize(tester), const Size(1920, 1080));

      // Когда разворот позади, протяжка окна снова ждёт.
      await tester.pump(kWindowJump * 2);
      resize(tester, const Size(1600, 900));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sheetSize(tester), const Size(1920, 1080));
      await tester.pump(kWindowSettle);
      await tester.pump();
      expect(sheetSize(tester), const Size(1600, 900));

      await unmount(tester);
    });
  });
}
