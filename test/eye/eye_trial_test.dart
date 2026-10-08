import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_tracker.dart';
import 'package:memoria/sno/eye/eye_trial.dart';
import 'package:memoria/sno/eye/eye_window.dart';
import 'package:memoria/sno/eye/live_layer.dart';
import 'package:memoria/sno/eye/trial_screen.dart';
import 'package:path/path.dart' as p;

import '../support/fake_eye.dart';
import '../support/recording_fakes.dart';

/// SNO-F-EYE-03, SNO-F-EYE-01, SNO-ALG-EYE-02: «Проверка айтрекера» —
/// калибровка, итог, живой взгляд поверх приложения.
///
/// Спутник, окно, часы и диск подставные; время идёт, только когда его
/// двигает тест (`pump`).
void main() {
  final EyePlace place = EyePlace(
    camera: const EyeCamera(index: 0, name: 'Integrated Camera'),
    monitor: r'\\.\DISPLAY1',
    monitorName: 'DELL P2419H',
    widthPx: 1920,
    heightPx: 1080,
    pxPerMm: 1920 / 527,
    sizeSource: ScreenSizeSource.card,
    distanceMm: 600,
    verdict: EyeVerdict.good,
    checkedAt: DateTime.utc(2026, 10, 8, 12),
    mode: const <int>[1920, 1080],
    fps: 29.9,
  );

  late MemorySettings settings;
  late FakeQpc qpc;
  late FakeEyeLauncher launcher;
  late FakeEyeWindow window;
  late MemoryEyeFiles files;
  late EyeTracker eye;
  late GlobalKey<NavigatorState> navigator;
  late List<String> opened;

  EyeTracker tracker() {
    return EyeTracker(
      settings: settings,
      launch: launcher.launch,
      qpc: qpc,
      window: window,
      dataFolder: () async => '/data',
      files: files,
      monotonicMs: () => 0,
      ticker: (Duration every, void Function() onTick) => () {},
      wait: (Duration pause) async {},
    );
  }

  setUp(() async {
    settings = MemorySettings();
    qpc = FakeQpc();
    launcher = FakeEyeLauncher(make: (int n) => FakeEyeProcess(clock: qpc));
    window = FakeEyeWindow();
    files = MemoryEyeFiles();
    navigator = GlobalKey<NavigatorState>();
    opened = <String>[];
    eye = tracker();
    await eye.savePlace(place);
  });

  tearDown(() async {
    eye.dispose();
    await window.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (BuildContext context, Widget? child) => EyeLiveLayer(
          eye: eye,
          navigator: navigator,
          openFolder: (String path) async {
            opened.add(path);
            return true;
          },
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open-trial'),
                onPressed: () =>
                    unawaited(openEyeTrial(Navigator.of(context), eye)),
                child: const Text('Полка'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-trial')));
    await tester.pump();
    await tester.pump();
  }

  /// Двигает время на [time] шагами по [step], с кадром на каждом.
  Future<void> runFor(
    WidgetTester tester,
    Duration time, {
    Duration step = const Duration(milliseconds: 250),
  }) async {
    Duration gone = Duration.zero;
    while (gone < time) {
      await tester.pump(step);
      gone += step;
    }
  }

  /// Даёт договорить связи и спутнику: отписки от потоков отвечают
  /// обещаниями корневой зоны, и продолжение кода ложится в очередь
  /// теста только на следующем кадре. Ждать их `await` в теле теста
  /// нельзя — тест повиснет.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    unawaited(eye.closeTrial());
    await settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  FakeEyeProcess sat() => launcher.last;

  /// Точка уходит спутнику сразу, без ожидания отрисовки кадра: так время
  /// точки — ровно её срок, и вехи калибровки предсказуемы. Ожидание
  /// кадра проверяет первый тест.
  void instantFrames() {
    eye.trial.value!.frameShown = () async => qpc.nowUs();
  }

  List<Map<String, Object?>> sent(String name) => <Map<String, Object?>>[
    for (final Map<String, Object?> c in sat().commands)
      if (c['cmd'] == name) c,
  ];

  testWidgets('SNO-F-EYE-03: быстро — 9 точек, живой взгляд поверх '
      'приложения, закрыть — спутник и окно отпущены', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(EyeTrialScreen), findsOneWidget);
    expect(find.byKey(const Key('eye-trial-place')), findsOneWidget);

    await tester.tap(find.byKey(const Key('eye-trial-quick')));
    await settle(tester);
    // Окно — на монитор места записи, спутник запущен, камера открыта
    // без файлов.
    expect(window.locks, <String>[r'\\.\DISPLAY1']);
    expect(sat().names.take(4), <Object?>[
      'hello',
      'selfcheck',
      'open',
      'calibrate',
    ]);
    // У быстрой проверки файлов нет — и самопроверки в папке тоже.
    final Map<String, Object?> check = sent('selfcheck').single;
    expect(check.containsKey('dir'), isFalse);
    final Map<String, Object?> open = sent('open').single;
    expect(open['write'], isFalse);
    expect(open.containsKey('dir'), isFalse);
    expect(open['distance_mm'], 600);
    final Map<String, Object?> screen = open['screen']! as Map<String, Object?>;
    expect(screen['w'], 1920);
    expect(screen['h'], 1080);
    expect((screen['w_mm']! as num).toDouble(), closeTo(527, 1e-6));
    expect(sent('calibrate').single['kind'], 'quick');

    // Подсказка, потом девять точек по две секунды.
    expect(
      find.text('Смотрите на точку. Нажимать ничего не нужно.'),
      findsOneWidget,
    );
    await runFor(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('eye-targets-point')), findsOneWidget);
    expect(
      find.text('Смотрите на точку. Нажимать ничего не нужно.'),
      findsNothing,
    );
    // Каждая точка уходит спутнику после отрисовки своего кадра — до
    // полусекунды сверх её срока.
    await runFor(tester, const Duration(seconds: 24));
    await tester.pump();
    await tester.pump();

    expect(sat().targetIds, hasLength(9));
    expect(
      sat().targetIds.every((Object? id) => (id! as String).startsWith('q')),
      isTrue,
    );
    for (final Map<String, Object?> t in sat().targets) {
      expect(t['qpc_us'], isA<int>());
      if (t['phase'] != 'off') {
        expect(t['phase'], 'calib');
        expect(t['x'], isA<double>());
      }
    }
    // Время точки — две секунды между появлениями (QPC подставной идёт
    // по чтениям, поэтому — порядок, а не числа).
    final List<int> times = <int>[
      for (final Map<String, Object?> t in sat().targets) t['qpc_us']! as int,
    ];
    expect(times, orderedEquals(List<int>.of(times)..sort()));
    expect(sat().names, contains('fit'));
    expect(sat().names, isNot(contains('validate')));
    expect(sat().liveOn, isTrue);

    // Экран ушёл: на месте — приложение и панель живого взгляда.
    expect(find.byType(EyeTrialScreen), findsNothing);
    expect(find.byKey(const Key('open-trial')), findsOneWidget);
    expect(find.byKey(const Key('eye-live-panel')), findsOneWidget);
    expect(find.byKey(const Key('eye-live-dot')), findsNothing);

    for (int i = 0; i < 30; i++) {
      sat().gaze(400, 300, t: 1000000 + i * 33000);
    }
    // Строки приходят после того, как кадр уже решён: второй кадр их
    // рисует.
    await tester.pump();
    await tester.pump();
    final Finder dot = find.byKey(const Key('eye-live-dot'));
    expect(dot, findsOneWidget);
    expect(tester.getCenter(dot), const Offset(400, 300));
    // Частота, доля кадров с лицом, точность быстрой калибровки.
    expect(find.text('30,0 к/с · лицо 100 % · 1,2°'), findsOneWidget);
    // Точка не забирает нажатий: под ней — приложение.
    expect(find.byKey(const Key('eye-live-again')), findsOneWidget);

    await tester.tap(find.byKey(const Key('eye-live-close')));
    await settle(tester);
    expect(find.byKey(const Key('eye-live-panel')), findsNothing);
    expect(sat().inputClosed, isTrue);
    expect(window.locked, isFalse);
    expect(eye.trial.value, isNull);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-03: «Ещё раз» из живого взгляда — новая быстрая '
      'калибровка', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('eye-trial-quick')));
    await runFor(tester, const Duration(seconds: 26));
    await tester.pump();
    expect(find.byKey(const Key('eye-live-panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('eye-live-again')));
    await settle(tester);
    expect(find.byType(EyeTrialScreen), findsOneWidget);
    expect(sat().liveOn, isFalse);
    expect(
      <Object?>[
        for (final Map<String, Object?> c in sent('calibrate')) c['attempt'],
      ],
      <Object?>[1, 2],
    );
    await runFor(tester, const Duration(seconds: 26));
    await tester.pump();
    expect(find.byType(EyeTrialScreen), findsNothing);
    expect(sat().liveOn, isTrue);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-01: пробная полная калибровка — 13 точек, '
      'слежение, 9 точек проверки, итог, две минуты просмотра, файлы стенда', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    instantFrames();
    await tester.tap(find.byKey(const Key('eye-trial-full')));
    await settle(tester);

    // Папка стенда создана, в ней — сведения о месте; самопроверка и
    // файлы камеры — туда же.
    expect(files.folders, hasLength(1));
    final String stand = files.folders.single;
    expect(p.dirname(stand), p.join('/data', 'Стенд'));
    final Map<String, Object?> placeJson = jsonDecode(
      files.written[p.join(stand, 'place.json')]!,
    ) as Map<String, Object?>;
    expect(placeJson['distance_mm'], 600);
    expect(sent('selfcheck').single['dir'], stand);
    final Map<String, Object?> open = sent('open').single;
    expect(open['write'], isTrue);
    expect(open['dir'], stand);
    expect(sent('calibrate').single['kind'], 'full');

    // 1,5 с подсказки и 13 точек по 2 с.
    await runFor(tester, const Duration(seconds: 28));
    expect(
      sat().targetIds.where((Object? id) => '$id'.startsWith('c')),
      hasLength(13),
    );
    expect(sat().names, contains('samples'));
    expect(find.text('Теперь следите глазами за точкой'), findsOneWidget);
    // Слежение — 20 с, путь уходит спутнику один раз.
    await runFor(tester, const Duration(seconds: 2));
    final Map<String, Object?> pursuit = sat().targets.firstWhere(
      (Map<String, Object?> t) => t['phase'] == 'pursuit',
    );
    final Map<String, Object?> path = pursuit['path']! as Map<String, Object?>;
    expect(path['tx_ms'], 16000);
    expect(path['ty_ms'], 10667);
    await runFor(tester, const Duration(seconds: 20));
    // Модель, затем 9 точек проверки по 1,5 с.
    await runFor(tester, const Duration(seconds: 15));
    await tester.pump();
    expect(
      sat().targetIds.where((Object? id) => '$id'.startsWith('v')),
      hasLength(9),
    );
    expect(sat().names, contains('validate'));

    expect(
      find.text(
        'Точность 2,2° (≈ 2,3 см) · худшая точка 4,1° · попытка 1 из 3',
      ),
      findsOneWidget,
    );
    expect(find.text('Принято.'), findsOneWidget);
    expect(find.text('Задержка камеры 70 мс'), findsOneWidget);

    await tester.tap(find.byKey(const Key('eye-trial-live')));
    await settle(tester);
    expect(find.byType(EyeTrialScreen), findsNothing);
    expect(find.byKey(const Key('eye-live-left')), findsOneWidget);
    expect(find.textContaining('Свободный просмотр 2:00'), findsOneWidget);
    await runFor(
      tester,
      const Duration(seconds: 30),
      step: const Duration(seconds: 1),
    );
    expect(find.textContaining('Свободный просмотр 1:30'), findsOneWidget);
    await runFor(
      tester,
      const Duration(seconds: 91),
      step: const Duration(seconds: 1),
    );
    await tester.pump();
    // Просмотр кончился: камера закрыта, файлы дописаны.
    expect(sat().names, contains('close'));
    expect(find.byKey(const Key('eye-live-finished')), findsOneWidget);
    expect(find.byKey(const Key('eye-live-dot')), findsNothing);
    await tester.tap(find.byKey(const Key('eye-live-folder')));
    await tester.pump();
    expect(opened, <String>[stand]);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-01: не принято — повтор до трёх попыток, потом '
      '«не принято» и живой взгляд по желанию', (WidgetTester tester) async {
    launcher = FakeEyeLauncher(
      make: (int n) => FakeEyeProcess(
        clock: qpc,
        validateReplies: <Map<String, Object?>>[
          kRejectedValidation,
          kRejectedValidation,
          kRejectedValidation,
        ],
      ),
    );
    eye.dispose();
    eye = tracker();
    await eye.savePlace(place);
    await pumpApp(tester);
    instantFrames();
    await tester.tap(find.byKey(const Key('eye-trial-full')));
    for (int attempt = 1; attempt <= 3; attempt++) {
      await runFor(tester, const Duration(seconds: 66));
      await tester.pump();
      expect(
        find.text(
          'Точность 3,1° (≈ 3,3 см) · худшая точка 4,6° · попытка $attempt '
          'из 3',
        ),
        findsOneWidget,
      );
      if (attempt < 3) {
        expect(
          find.text('Точность 3,1° (порог — 2,5°) — поправьте посадку и свет'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('eye-trial-retry')));
        await tester.pump();
      }
    }
    expect(find.byKey(const Key('eye-trial-retry')), findsNothing);
    expect(
      find.textContaining('Не принято и после 3 попыток.'),
      findsOneWidget,
    );
    expect(
      <Object?>[
        for (final Map<String, Object?> c in sent('calibrate')) c['attempt'],
      ],
      <Object?>[1, 2, 3],
    );
    expect(find.byKey(const Key('eye-trial-live-anyway')), findsOneWidget);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-ALG-EYE-02: точка без кадров повторяется в конце; лица '
      'нет — словами и без отсчёта попытки', (WidgetTester tester) async {
    launcher = FakeEyeLauncher(
      make: (int n) => FakeEyeProcess(
        clock: qpc,
        samplesReply: <String, Object?>{
          'phase': 'calib',
          'counts': <String, Object?>{'q3': 2},
          'short': <Object?>['q3'],
          'face': 1.0,
        },
      ),
    );
    eye.dispose();
    eye = tracker();
    await eye.savePlace(place);
    await pumpApp(tester);
    instantFrames();
    await tester.tap(find.byKey(const Key('eye-trial-quick')));
    await runFor(tester, const Duration(seconds: 24));
    await tester.pump();
    expect(sat().targetIds.where((Object? id) => id == 'q3'), hasLength(2));
    expect(sat().targetIds.last, 'q3');
    await unmount(tester);

    launcher = FakeEyeLauncher(
      make: (int n) => FakeEyeProcess(
        clock: qpc,
        samplesReply: <String, Object?>{
          'phase': 'calib',
          'counts': <String, Object?>{},
          'short': <Object?>[],
          'face': 0.2,
        },
      ),
    );
    eye.dispose();
    eye = tracker();
    await eye.savePlace(place);
    await pumpApp(tester);
    instantFrames();
    await tester.tap(find.byKey(const Key('eye-trial-full')));
    await runFor(tester, const Duration(seconds: 29));
    await tester.pump();
    expect(
      find.text('Камера не видит лица — сядьте напротив камеры и повторите'),
      findsOneWidget,
    );
    expect(sat().names, isNot(contains('fit')));
    await tester.tap(find.byKey(const Key('eye-trial-retry')));
    await settle(tester);
    expect(
      <Object?>[
        for (final Map<String, Object?> c in sent('calibrate')) c['attempt'],
      ],
      <Object?>[1, 1],
    );
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-01: окно сменилось посреди калибровки — камера '
      'заново и та же попытка; Esc закрывает проверку', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('eye-trial-quick')));
    await runFor(tester, const Duration(seconds: 5));
    window.change(
      const EyeWindowLock(
        monitor: r'\\.\DISPLAY1',
        name: 'DELL P2419H',
        found: true,
        widthPx: 1920,
        heightPx: 1080,
        dpr: 1,
      ),
    );
    await settle(tester);
    expect(sent('open'), hasLength(2));
    expect(
      <Object?>[
        for (final Map<String, Object?> c in sent('calibrate')) c['attempt'],
      ],
      <Object?>[1, 1],
    );
    expect(find.byType(EyeTrialScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(EyeTrialScreen), findsNothing);
    expect(window.locked, isFalse);
    expect(sat().inputClosed, isTrue);
    expect(eye.trial.value, isNull);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-03: самопроверка «не годится» — сказано, '
      'калибровки нет', (WidgetTester tester) async {
    launcher = FakeEyeLauncher(
      make: (int n) => FakeEyeProcess(
        clock: qpc,
        check: <String, Object?>{
          'verdict': 'fail',
          'checks': <Object?>[
            <String, Object?>{
              'id': 'camera',
              'verdict': 'fail',
              'value': 'camera_busy',
              'text':
                  'Камера занята другой программой — закройте Teams, Zoom, '
                  'браузер',
            },
          ],
          'measures': <String, Object?>{'camera': 'camera_busy'},
        },
      ),
    );
    eye.dispose();
    eye = tracker();
    await eye.savePlace(place);
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('eye-trial-quick')));
    await settle(tester);
    expect(find.text('Самопроверка: не годится'), findsOneWidget);
    expect(
      find.text(
        '• Камера занята другой программой — закройте Teams, Zoom, браузер',
      ),
      findsOneWidget,
    );
    expect(sat().names, isNot(contains('open')));
    await tester.tap(find.byKey(const Key('eye-trial-close')));
    await settle(tester);
    expect(find.byType(EyeTrialScreen), findsNothing);
    expect(window.locked, isFalse);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('SNO-F-EYE-03: без места записи проверки нет', () async {
    final EyeTracker fresh = EyeTracker(
      settings: MemorySettings(),
      launch: launcher.launch,
      qpc: qpc,
      window: window,
    );
    await fresh.loadPlace();
    expect(fresh.beginTrial(), isNull);
    fresh.dispose();
    final EyeTrial? trial = eye.beginTrial();
    expect(trial, isNotNull);
    expect(eye.beginTrial(), same(trial));
    expect(trial!.phase, EyeTrialPhase.choose);
    await trial.close();
    expect(eye.trial.value, isNull);
  });
}
