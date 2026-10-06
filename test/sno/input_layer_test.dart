import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/input_layer.dart';
import 'package:memoria/sno/recording/recording_overlay.dart';
import 'package:memoria/sno/recording/session.dart';

import '../support/recording_fakes.dart';

/// Шаг 23, SNO-F-REC-11: перехват сырого ввода на настоящем экране.
///
/// Слой записи стоит над экраном-заглушкой с кнопкой и областью,
/// которая, как страница книги, принимает долгое нажатие. Сессия — на
/// памяти и подменённом времени: время записи идёт, только когда его
/// двигает тест. Проверяется, что каждое касание, колесо и клавиша
/// ложатся строкой в поток — и что экран под слоем ведёт себя так же,
/// как без записи.
void main() {
  late SessionKit kit;
  int pressed = 0;
  int holds = 0;
  final List<LogicalKeyboardKey> keys = <LogicalKeyboardKey>[];

  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  setUp(() {
    kit = SessionKit();
    pressed = 0;
    holds = 0;
    keys.clear();
  });
  tearDown(() => kit.session.dispose());

  /// Экран под слоем: кнопка, которая что-то делает (и говорит об этом
  /// журналу), и область, которая принимает долгое нажатие.
  Widget screen() {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            keys.add(event.logicalKey);
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: <Widget>[
            TextButton(
              key: const Key('act'),
              onPressed: () {
                pressed++;
                kit.session.log(
                  SnoEventType.panelOpen,
                  data: const <String, Object?>{'panel': 'проба'},
                );
              },
              child: const Text('кнопка'),
            ),
            Expanded(
              child: GestureDetector(
                key: const Key('area'),
                behavior: HitTestBehavior.opaque,
                onLongPress: () => holds++,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pumpOverlay(WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (BuildContext context, Widget? page) {
          return RecordingOverlay(
            session: kit.session,
            navigator: navigator,
            child: page!,
          );
        },
        home: screen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Слой под идущей записью.
  Future<void> pumpRecording(WidgetTester tester) async {
    await pumpOverlay(tester);
    await kit.session.start(code);
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Строки потока ввода, как они лежат «на диске».
  Future<List<Map<String, Object?>>> inputLines(WidgetTester tester) async {
    kit.session.tick();
    await tester.pump();
    return kit.store.inputLines(kit.folder);
  }

  /// Время записи и время экрана идут вместе.
  Future<void> pass(WidgetTester tester, Duration by) async {
    kit.time.pass(by);
    await tester.pump(by);
  }

  group('SNO-F-REC-11: слушатели есть только во время записи', () {
    testWidgets('SNO-F-REC-11: записи нет — ни слушателей, ни строк', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);

      expect(InputLayer.listening, 0);
      await tester.tap(find.byKey(const Key('act')));
      await tester.tapAt(const Offset(400, 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(pressed, 1);
      expect(kit.store.inputs, isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: слушатели заводит старт записи и снимает '
        'её остановка', (WidgetTester tester) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();
      expect(InputLayer.listening, 1);

      await kit.session.stop(StopReason.experimenter);
      await tester.pump();
      expect(InputLayer.listening, 0);
      // Касание после остановки в поток не идёт.
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();
      expect(kit.store.inputLines(kit.folder), isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: слой сняли посреди записи — слушателей не '
        'осталось', (WidgetTester tester) async {
      await pumpRecording(tester);
      expect(InputLayer.listening, 1);

      await unmount(tester);

      expect(InputLayer.listening, 0);
    });
  });

  group('SNO-F-REC-11: каждое касание — строка', () {
    testWidgets('SNO-F-REC-11: нажатие по кнопке — кнопка нажата, как без '
        'записи; строка есть, и событие журнала на неё ссылается', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);
      final Offset at = tester.getCenter(find.byKey(const Key('act')));

      await tester.tap(find.byKey(const Key('act')));
      await tester.pump();

      expect(pressed, 1);
      final Map<String, Object?> line = (await inputLines(tester)).single;
      expect(line['n'], 1);
      expect(line['dev'], 'touch');
      expect(line['kind'], 'tap');
      expect(line['x'], closeTo(at.dx, 0.06));
      expect(line['y'], closeTo(at.dy, 0.06));
      expect(line['vw'], 800.0);
      expect(line['vh'], 600.0);
      expect(line['screen'], 'shelf');
      final Map<String, Object?> opened = kit.store
          .events(kit.folder)
          .singleWhere(
            (Map<String, Object?> event) => event['type'] == 'panel.open',
          );
      expect(opened['input'], 1);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: нажатие по пустому месту записано так же, '
        'и ни одно событие на него не ссылается', (WidgetTester tester) async {
      await pumpRecording(tester);

      await tester.tapAt(const Offset(400, 400));
      await tester.pump();

      final Map<String, Object?> line = (await inputLines(tester)).single;
      expect(line['kind'], 'tap');
      expect(line['x'], 400.0);
      expect(line['y'], 400.0);
      expect(
        kit.store
            .events(kit.folder)
            .where((Map<String, Object?> event) => event.containsKey('input')),
        isEmpty,
      );
      expect(pressed, 0);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: удержание — экран узнаёт его, как без '
        'записи, а в потоке оно long', (WidgetTester tester) async {
      await pumpRecording(tester);

      final TestGesture gesture = await tester.startGesture(
        const Offset(400, 400),
      );
      await pass(tester, const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();

      expect(holds, 1);
      final Map<String, Object?> line = (await inputLines(tester)).single;
      expect(line['kind'], 'long');
      expect(line['dt'], 700);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: протяжка несёт путь с последней точкой', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);

      final TestGesture gesture = await tester.startGesture(
        const Offset(100, 300),
      );
      for (int i = 0; i < 5; i++) {
        await pass(tester, const Duration(milliseconds: 60));
        await gesture.moveBy(const Offset(30, 0));
      }
      await gesture.up();
      await tester.pump();

      final Map<String, Object?> line = (await inputLines(tester)).single;
      expect(line['kind'], 'drag');
      expect(line['x'], 100.0);
      expect(line['x1'], 250.0);
      expect(line['path'], 150.0);
      expect(line['dt'], 300);
      final List<Object?> trail = line['trail']! as List<Object?>;
      expect(trail.length, greaterThanOrEqualTo(5));
      expect((trail.last! as List<Object?>)[1], 250.0);
      // Долгим нажатием экран протяжку не счёл.
      expect(holds, 0);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: два пальца — две строки одной группы', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);

      final TestGesture first = await tester.startGesture(
        const Offset(200, 300),
        pointer: 11,
      );
      final TestGesture second = await tester.startGesture(
        const Offset(500, 300),
        pointer: 12,
      );
      await pass(tester, const Duration(milliseconds: 100));
      await first.up();
      await second.up();
      await tester.pump();

      final List<Map<String, Object?>> lines = await inputLines(tester);
      expect(lines, hasLength(2));
      expect(lines[0]['kind'], 'multi');
      expect(lines[1]['kind'], 'multi');
      expect(lines[0]['group'], lines[1]['group']);
      expect(lines[0]['group'], isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: мышь — нажатие с кнопкой, колесо строкой '
        'прокрутки, путь без нажатия', (WidgetTester tester) async {
      await pumpRecording(tester);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(100, 300));
      await pass(tester, const Duration(milliseconds: 200));
      await mouse.moveTo(const Offset(300, 320));
      await mouse.down(const Offset(300, 320));
      await pass(tester, const Duration(milliseconds: 50));
      await mouse.up();
      final TestPointer wheel = TestPointer(7, PointerDeviceKind.mouse);
      wheel.hover(const Offset(300, 320));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await tester.pump();
      await mouse.removePointer();
      // Остановка дописывает начатое: путь мыши и прокрутку.
      await kit.session.stop(StopReason.experimenter);
      await tester.pump();

      final List<Map<String, Object?>> lines = kit.store.inputLines(
        kit.folder,
      );
      final Map<String, Object?> click = lines.singleWhere(
        (Map<String, Object?> line) => line['dev'] == 'mouse',
      );
      expect(click['button'], 'primary');
      expect(click['kind'], 'tap');
      expect(click['x'], 300.0);
      final Map<String, Object?> rolled = lines.singleWhere(
        (Map<String, Object?> line) => line['dev'] == 'wheel',
      );
      expect(rolled['dy'], 120.0);
      expect(rolled['x'], 300.0);
      final Map<String, Object?> path = lines.firstWhere(
        (Map<String, Object?> line) => line['dev'] == 'hover',
      );
      expect(path['trail'], isNotEmpty);
      // Все номера на месте: поток цел.
      expect(kit.session.inputCheck!.intact, isTrue);
      expect(kit.session.inputs, lines.length);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-11: клавиши', () {
    testWidgets('SNO-F-REC-11: управляющая клавиша — именем, печатная — '
        'без буквы; экран получает обе, как без записи', (
      WidgetTester tester,
    ) async {
      await pumpRecording(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(keys, <LogicalKeyboardKey>[
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.keyA,
      ]);
      final List<Map<String, Object?>> lines = await inputLines(tester);
      expect(lines, hasLength(2));
      expect(lines[0]['dev'], 'key');
      expect(lines[0]['key'], 'PageDown');
      expect(lines[1]['key'], 'char');
      expect(lines[1].keys.toSet(), <String>{
        'n',
        't',
        'dt',
        'dev',
        'key',
        'screen',
      });

      await unmount(tester);
    });

    test('SNO-ALG-REC-07: имя клавиши для потока', () {
      expect(inputKeyName(LogicalKeyboardKey.pageDown), 'PageDown');
      expect(inputKeyName(LogicalKeyboardKey.arrowLeft), 'ArrowLeft');
      expect(inputKeyName(LogicalKeyboardKey.escape), 'Escape');
      expect(inputKeyName(LogicalKeyboardKey.f3, shift: true), 'Shift+F3');
      expect(inputKeyName(LogicalKeyboardKey.audioVolumeDown), 'VolumeDown');
      // Печатные — без самой буквы, с Shift тоже.
      expect(inputKeyName(LogicalKeyboardKey.keyA), 'char');
      expect(inputKeyName(LogicalKeyboardKey.keyA, shift: true), 'char');
      expect(inputKeyName(LogicalKeyboardKey.digit7), 'char');
      expect(inputKeyName(LogicalKeyboardKey.comma), 'char');
      // Сочетание с Ctrl или Alt — управляющее: оно названо целиком.
      expect(inputKeyName(LogicalKeyboardKey.keyF, ctrl: true), 'Ctrl+F');
      expect(
        inputKeyName(LogicalKeyboardKey.keyC, ctrl: true, shift: true),
        'Ctrl+Shift+C',
      );
      expect(inputKeyName(LogicalKeyboardKey.f4, alt: true), 'Alt+F4');
      // Сама клавиша-модификатор.
      expect(inputKeyName(LogicalKeyboardKey.shiftLeft, shift: true), 'Shift');
      expect(
        inputKeyName(LogicalKeyboardKey.controlRight, ctrl: true),
        'Ctrl',
      );
    });

    test('SNO-ALG-REC-07: указатель и кнопка мыши словами', () {
      expect(inputDeviceName(PointerDeviceKind.touch), 'touch');
      expect(inputDeviceName(PointerDeviceKind.mouse), 'mouse');
      expect(inputDeviceName(PointerDeviceKind.stylus), 'stylus');
      expect(inputDeviceName(PointerDeviceKind.trackpad), 'trackpad');
      expect(inputButtonName(PointerDeviceKind.touch, 1), isNull);
      expect(
        inputButtonName(PointerDeviceKind.mouse, kPrimaryMouseButton),
        'primary',
      );
      expect(
        inputButtonName(PointerDeviceKind.mouse, kSecondaryMouseButton),
        'secondary',
      );
      expect(
        inputButtonName(PointerDeviceKind.mouse, kMiddleMouseButton),
        'middle',
      );
    });
  });

  group('SNO-F-REC-11: касания экспериментатора помечены', () {
    testWidgets('SNO-F-REC-11: удержание точки записи и нажатия в вопросе '
        'об остановке — не участник', (WidgetTester tester) async {
      await pumpRecording(tester);

      // Экспериментатор держит точку записи до вопроса об остановке.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('sno-recording-dot'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 1900));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);
      // И отвечает «Продолжить».
      await tester.tap(find.byKey(const Key('sno-stop-continue')));
      await tester.pumpAndSettle();
      expect(kit.session.recording, isTrue);
      // Дальше экрана касается участник.
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();

      final List<Map<String, Object?>> lines = await inputLines(tester);
      expect(
        lines.map((Map<String, Object?> line) => line['screen']),
        <String>[kInputDotScreen, kInputStopScreen, 'shelf'],
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-11: короткое нажатие в углу, где стоит точка, — '
        'нажатие участника', (WidgetTester tester) async {
      await pumpRecording(tester);

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('sno-recording-dot'))),
      );
      await tester.pump();

      expect((await inputLines(tester)).single['screen'], 'shelf');

      await unmount(tester);
    });
  });
}
