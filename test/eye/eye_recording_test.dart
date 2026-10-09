import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/scenario.dart' show cltSeedOf;
import 'package:memoria/sno/eye/eye_calibration.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_recording.dart';
import 'package:memoria/sno/eye/eye_tracker.dart';
import 'package:memoria/sno/eye/live_layer.dart';
import 'package:memoria/sno/eye/recording_screen.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/gaze_line.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/fake_eye.dart';
import '../support/recording_fakes.dart';

/// Шаг 32 (ET-06): айтрекер внутри записи участника — калибровка перед
/// изучением (SNO-F-EYE-01), взгляд всю запись (SNO-F-EYE-02), проверка
/// в конце (SNO-F-EYE-06), поток взгляда в записи (SNO-F-REC-04).
///
/// Запись — настоящая, на памяти и подменённом времени; спутник, окно и
/// часы QPC подставные; время калибровки идёт, только когда его двигает
/// тест (`pump`).
void main() {
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

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

  late SessionKit kit;
  late FakeQpc qpc;
  late FakeEyeLauncher launcher;
  late FakeEyeWindow window;
  late EyeTracker eye;
  late GlobalKey<NavigatorState> navigator;

  /// Что ответит спутник на `validate` по попыткам и на самопроверку.
  late List<Map<String, Object?>> validations;
  Map<String, Object?>? checkReply;

  setUp(() async {
    kit = SessionKit();
    qpc = FakeQpc();
    validations = <Map<String, Object?>>[];
    checkReply = null;
    launcher = FakeEyeLauncher(
      make: (int n) => FakeEyeProcess(
        clock: qpc,
        check: checkReply,
        validateReplies: List<Map<String, Object?>>.of(validations),
      ),
    );
    window = FakeEyeWindow();
    navigator = GlobalKey<NavigatorState>();
    await kit.settings.write(SnoSettingsKeys.eyePlace, place.encode());
    eye = EyeTracker(
      settings: kit.settings,
      launch: launcher.launch,
      qpc: qpc,
      window: window,
      monotonicMs: () => 0,
      ticker: (Duration every, void Function() onTick) => () {},
      wait: (Duration pause) async {},
    )..attach(kit.session);
  });

  tearDown(() async {
    eye.dispose();
    await window.dispose();
    kit.session.dispose();
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
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(body: Center(child: Text('Полка'))),
      ),
    );
  }

  /// Даёт договорить связи и спутнику.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Двигает время шагами, пока не выполнится [done], но не дольше
  /// [limit].
  Future<void> runUntil(
    WidgetTester tester,
    bool Function() done, {
    Duration limit = const Duration(minutes: 3),
    Duration step = const Duration(milliseconds: 250),
  }) async {
    Duration gone = Duration.zero;
    while (!done() && gone < limit) {
      await tester.pump(step);
      gone += step;
    }
    expect(done(), isTrue, reason: 'не дождались за $limit');
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  FakeEyeProcess sat() => launcher.last;

  EyeRecordingView? view() => eye.recording.value;

  List<Map<String, Object?>> sent(String name) => <Map<String, Object?>>[
    for (final Map<String, Object?> c in sat().commands)
      if (c['cmd'] == name) c,
  ];

  /// Журнал записи, сброшенный на диск.
  Future<List<Map<String, Object?>>> journal(WidgetTester tester) async {
    kit.session.tick();
    await settle(tester);
    return kit.store.events(kit.folder);
  }

  List<String> typesOf(List<Map<String, Object?>> events) => <String>[
    for (final Map<String, Object?> e in events) e['type']! as String,
  ];

  Map<String, Object?> dataOf(Map<String, Object?> event) =>
      (event['data'] as Map<String, Object?>?) ?? const <String, Object?>{};

  Map<String, Object?> one(List<Map<String, Object?>> events, String type) {
    return dataOf(events.singleWhere((Map<String, Object?> e) => e['type'] == type));
  }

  Future<void> holdOn(WidgetTester tester, String key) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key(key))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(kEyeChoiceHold + const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);
  }

  /// Запись началась, экран айтрекера встал; точки уходят спутнику сразу
  /// после показа.
  Future<void> started(WidgetTester tester) async {
    await pumpApp(tester);
    expect(await kit.session.start(code), isTrue);
    await settle(tester);
    await runUntil(
      tester,
      () => find.byType(EyeRecordingScreen).evaluate().isNotEmpty,
      limit: const Duration(seconds: 5),
    );
    view()!.frameShown = () async => qpc.nowUs();
  }

  Future<void> calibrated(WidgetTester tester) async {
    await runUntil(tester, () => view()?.phase == EyeRecordingPhase.result);
    await settle(tester);
  }

  testWidgets('SNO-F-EYE-01: «Код записан» — самопроверка, калибровка в '
      'порядке по коду участника, итог и «Начать»: сорок минут идут от '
      'study.start, взгляд пишется', (WidgetTester tester) async {
    await started(tester);
    // Участник полки не видит: на экране — калибровка, изучение ждёт.
    expect(find.text('Полка'), findsNothing);
    expect(kit.session.studyPending, isTrue);
    expect(window.locks, <String>[r'\\.\DISPLAY1']);

    await calibrated(tester);
    final List<Object?> names = sat().names.where((Object? n) => n != 'sync').toList();
    expect(names.take(4), <Object?>['hello', 'selfcheck', 'open', 'calibrate']);
    final Map<String, Object?> check = sent('selfcheck').single;
    expect(check['dir'], '/records/.current/${kit.folder}/eye');
    final Map<String, Object?> open = sent('open').single;
    expect(open['dir'], '/records/.current/${kit.folder}/eye');
    expect(open['write'], isTrue);
    expect(open['strip'], isTrue);
    expect(open['seg'], 0);
    expect(open['qpc0_us'], isA<int>());
    expect(open['t0'], isA<int>());
    expect(open.containsKey('calibration'), isFalse);
    expect(sent('calibrate').single['kind'], 'full');
    // Порядок точек — по коду участника, как у теста нагрузки.
    final int seed = (cltSeedOf(kTestCode) + 1) & 0xFFFFFFFF;
    final List<String> order = <String>[
      for (final EyeTargetPoint p in calibrationSequence(
        EyeCalibrationKind.full,
        seed,
      ))
        p.id,
    ];
    expect(sat().targetIds.take(order.length).toList(), order);

    expect(find.byKey(const Key('eye-recording-line')), findsOneWidget);
    expect(find.text('Принято.'), findsOneWidget);
    expect(kit.session.studyPending, isTrue);
    expect(kit.session.elapsedMs, 0);

    kit.time.pass(const Duration(seconds: 90));
    await tester.tap(find.byKey(const Key('eye-recording-begin')));
    await settle(tester);
    expect(sat().gazeOn, isTrue);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    expect(find.text('Полка'), findsOneWidget);
    expect(kit.session.studyPending, isFalse);

    final List<Map<String, Object?>> events = await journal(tester);
    final List<String> types = typesOf(events);
    expect(types, containsAllInOrder(<String>[
      'recording.start',
      'eye.window',
      'eye.ready',
      'eye.clock',
      'eye.sync',
      'eye.check',
      'eye.calibration.start',
      'eye.target',
      'eye.calibration.result',
      'eye.gaze',
      'study.start',
    ]));
    expect(one(events, 'eye.check')['verdict'], 'good');
    expect(one(events, 'eye.calibration.start'), <String, Object?>{
      'attempt': 1,
      'kind': 'full',
      'seed': seed,
    });
    final Map<String, Object?> result = one(events, 'eye.calibration.result');
    expect(result['accepted'], isTrue);
    expect(result['accuracy_deg'], 2.2);
    expect(result['failures'], 0);
    final List<Map<String, Object?>> targets = <Map<String, Object?>>[
      for (final Map<String, Object?> e in events)
        if (e['type'] == 'eye.target') dataOf(e),
    ];
    // 13 точек, фаза головы, слежение и 9 точек проверки.
    expect(targets.where((Map<String, Object?> t) => t['phase'] == 'calib'), hasLength(13));
    expect(targets.where((Map<String, Object?> t) => t['phase'] == 'validate'), hasLength(9));
    expect(targets.where((Map<String, Object?> t) => t['phase'] == 'pursuit'), hasLength(1));
    expect(targets.first['qpc_us'], isA<int>());
    expect(one(events, 'eye.gaze'), <String, Object?>{
      'seg': 0,
      'n': 1,
      'quality': 'ok',
    });
    final Map<String, Object?> study = events.singleWhere(
      (Map<String, Object?> e) => e['type'] == 'study.start',
    );
    expect(dataOf(study), <String, Object?>{'gaze': true, 'quality': 'ok'});
    expect(study['t'], 90000);
    expect(kit.session.state!.studyT, 90000);

    // Сорок минут — от начала изучения.
    kit.time.pass(const Duration(minutes: 10));
    expect(kit.session.elapsedMs, 10 * 60 * 1000);
    expect(eye.info.present, isTrue);
    expect(eye.info.quality, 'ok');
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-01: две неудачи — организатор удержанием выбирает '
      '«Писать с пометкой»', (WidgetTester tester) async {
    validations = <Map<String, Object?>>[
      kRejectedValidation,
      kRejectedValidation,
    ];
    await started(tester);
    await calibrated(tester);
    expect(find.byKey(const Key('eye-recording-retry')), findsOneWidget);
    expect(find.byKey(const Key('eye-recording-write')), findsNothing);
    await tester.tap(find.byKey(const Key('eye-recording-retry')));
    await settle(tester);
    expect(view()!.phase, EyeRecordingPhase.calibrating);
    await calibrated(tester);
    expect(view()!.failures, 2);
    expect(view()!.mustChoose, isTrue);
    expect(find.byKey(const Key('eye-recording-retry')), findsNothing);
    expect(find.byType(HoldToConfirmButton), findsNWidgets(2));
    expect(sent('calibrate').map((Map<String, Object?> c) => c['attempt']), <Object?>[1, 2]);

    await holdOn(tester, 'eye-recording-write');
    expect(sat().gazeOn, isTrue);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    final List<Map<String, Object?>> events = await journal(tester);
    expect(one(events, 'eye.skip'), <String, Object?>{
      'by': 'experimenter',
      'write': true,
      'failures': 2,
    });
    expect(
      dataOf(events.singleWhere((Map<String, Object?> e) => e['type'] == 'study.start')),
      <String, Object?>{'gaze': true, 'quality': 'low'},
    );
    expect(eye.info.quality, 'low');
    expect(eye.info.calibration!['attempts'], 2);
    expect(eye.info.calibration!['accepted'], isFalse);
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('SNO-F-EYE-01: «Без взгляда» — спутник закрыт, подпапки eye/ '
      'нет, изучение идёт', (WidgetTester tester) async {
    validations = <Map<String, Object?>>[
      kRejectedValidation,
      kRejectedValidation,
    ];
    await started(tester);
    await calibrated(tester);
    await tester.tap(find.byKey(const Key('eye-recording-retry')));
    await settle(tester);
    await calibrated(tester);
    await holdOn(tester, 'eye-recording-without');
    expect(sat().inputClosed, isTrue);
    expect(kit.store.removed[kit.folder], <String>['eye']);
    expect(kit.session.studyPending, isFalse);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    final List<Map<String, Object?>> events = await journal(tester);
    expect(one(events, 'eye.skip')['write'], isFalse);
    expect(
      dataOf(events.singleWhere((Map<String, Object?> e) => e['type'] == 'study.start')),
      <String, Object?>{'gaze': false},
    );
    // Окно остаётся под замком до конца записи.
    expect(window.locked, isTrue);
    await kit.session.stop(StopReason.experimenter);
    await settle(tester);
    expect(window.locked, isFalse);
    final Map<String, Object?> block =
        kit.store.json(kit.folder, kRecordingFile)['eye_tracker']!
            as Map<String, Object?>;
    expect(block['present'], isFalse);
    expect(block['reason'], 'skipped');
    expect(describeGaze(block), 'Взгляд не записан: организатор выбрал «Без взгляда»');
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('SNO-F-EYE-01: самопроверка «не годится» — запись без взгляда '
      'сразу', (WidgetTester tester) async {
    checkReply = <String, Object?>{
      'verdict': 'fail',
      'checks': <Object?>[
        <String, Object?>{
          'id': 'camera',
          'verdict': 'fail',
          'value': 'camera_busy',
          'text': 'Камера занята',
        },
      ],
      'measures': <String, Object?>{'camera': 'camera_busy'},
    };
    await started(tester);
    await settle(tester);
    expect(sent('open'), isEmpty);
    expect(kit.session.studyPending, isFalse);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    expect(kit.store.removed[kit.folder], <String>['eye']);
    final List<Map<String, Object?>> events = await journal(tester);
    final Map<String, Object?> check = one(events, 'eye.check');
    expect(check['verdict'], 'fail');
    expect(check['checks'], <Object?>[
      <String, Object?>{'id': 'camera', 'verdict': 'fail'},
    ]);
    expect(eye.info.reason, 'selfcheck_failed');
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('SNO-F-EYE-02, SNO-F-EYE-06: изучение — лицо потерялось и '
      'вернулось, спутник поднят заново той же моделью; остановка — '
      'проверка в конце над экраном завершения, итог, спутник закрыт', (
    WidgetTester tester,
  ) async {
    await started(tester);
    await calibrated(tester);
    await tester.tap(find.byKey(const Key('eye-recording-begin')));
    await settle(tester);
    final FakeEyeProcess first = sat();

    // SNO-F-EYE-02: лица нет дольше секунды — и вернулось.
    first.face(lost: true);
    await settle(tester);
    first.face(lost: false, ms: 2300);
    await settle(tester);

    // Спутник упал — поднят заново: следующий сегмент, модель из файла.
    first.exit(1);
    await settle(tester);
    expect(launcher.started, hasLength(2));
    final Map<String, Object?> again = sent('open').single;
    expect(again['seg'], 1);
    expect(
      again['calibration'],
      '/records/.current/${kit.folder}/eye/calibration.json',
    );
    expect(sat().gazeOn, isTrue);
    // Поток взгляда на диске: строки спутника (их пишет спутник сам).
    kit.store.files[kit.folder]![kGazeFile] = <String>[
      for (int i = 1; i <= 10; i++)
        jsonEncode(<String, Object?>{'n': i, 'ok': i != 3, 'seg': i > 6 ? 1 : 0}),
      '',
    ].join('\n');

    final List<Map<String, Object?>> during = await journal(tester);
    expect(one(during, 'eye.face.lost')['qpc_us'], isA<int>());
    expect(one(during, 'eye.face.back')['ms'], 2300);
    expect(one(during, 'eye.lost'), <String, Object?>{'reason': 'exit', 'code': 1});
    expect(one(during, 'eye.restart')['seg'], 1);
    final List<Map<String, Object?>> gazes = <Map<String, Object?>>[
      for (final Map<String, Object?> e in during)
        if (e['type'] == 'eye.gaze') dataOf(e),
    ];
    expect(gazes.last, <String, Object?>{'seg': 1, 'n': 1, 'restart': true});

    // SNO-F-EYE-06: остановка — проверка в конце; экран встаёт над
    // экраном завершения, когда тот открыт.
    kit.time.pass(const Duration(minutes: 5));
    unawaited(kit.session.stop(StopReason.experimenter));
    await settle(tester);
    expect(view()!.phase, EyeRecordingPhase.endCheck);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    kit.session.setFinishOpen(true);
    await settle(tester);
    expect(find.byType(EyeRecordingScreen), findsOneWidget);
    expect(find.text(kEndCheckIntro), findsOneWidget);
    expect(find.byKey(const Key('eye-recording-skip')), findsOneWidget);
    view()!.frameShown = () async => qpc.nowUs();
    await runUntil(
      tester,
      () => view() == null,
      limit: const Duration(seconds: 40),
    );
    await settle(tester);
    expect(find.byType(EyeRecordingScreen), findsNothing);
    expect(sent('check').single['n'], 1);
    expect(sat().names, containsAllInOrder(<Object?>['check', 'checked', 'close']));
    expect(sat().inputClosed, isTrue);
    expect(window.locked, isFalse);

    final List<Map<String, Object?>> events = kit.store.events(kit.folder);
    final List<String> types = typesOf(events);
    final int stop = types.indexOf('recording.stop');
    expect(stop, greaterThan(0));
    expect(types.sublist(stop + 1), containsAllInOrder(<String>[
      'eye.endcheck.start',
      'eye.target',
      'eye.endcheck.result',
      'eye.closed',
    ]));
    for (final Map<String, Object?> e in events.sublist(stop + 1)) {
      expect(e['phase'], 'post', reason: '${e['type']}');
    }
    expect(
      types.sublist(stop + 1).where((String t) => t == 'eye.target'),
      hasLength(9),
    );
    final Map<String, Object?> end = one(events, 'eye.endcheck.result');
    expect(end['accuracy_deg'], 1.9);
    expect(end['start_deg'], 2.2);
    expect(end['drift_deg'], closeTo(-0.3, 1e-9));
    final Map<String, Object?> closed = one(events, 'eye.closed');
    expect(closed['valid_share'], 0.9);
    expect(closed['segments'], 2);
    expect((closed['check']! as Map<String, Object?>)['lines'], 10);
    expect((closed['check']! as Map<String, Object?>)['gaps'], 0);

    // Сведения записи — блок eye_tracker; строка экрана завершения.
    final String folder = kit.folder;
    await kit.session.finish();
    await settle(tester);
    final Map<String, Object?> block =
        kit.store.json(folder, kRecordingFile)['eye_tracker']!
            as Map<String, Object?>;
    expect(block['present'], isTrue);
    expect(block['quality'], 'ok');
    expect(block['file'], 'eye/gaze.jsonl');
    expect(block['segments'], 2);
    expect(block['restarts'], 1);
    expect(block['valid_share'], 0.9);
    expect((block['end_check']! as Map<String, Object?>)['accuracy_deg'], 1.9);
    expect((block['calibration']! as Map<String, Object?>)['accuracy_deg'], 2.2);
    expect(
      describeGaze(block),
      'Взгляд: 90 % времени, точность в начале 2,2°, в конце 1,9°',
    );
    final Map<String, Object?> recording =
        kit.store.json(folder, kRecordingFile)['recording']!
            as Map<String, Object?>;
    expect(recording['study_t'], isA<int>());
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('SNO-F-EYE-06: организатор пропускает проверку в конце '
      'удержанием', (WidgetTester tester) async {
    await started(tester);
    await calibrated(tester);
    await tester.tap(find.byKey(const Key('eye-recording-begin')));
    await settle(tester);
    unawaited(kit.session.stop(StopReason.experimenter));
    await settle(tester);
    kit.session.setFinishOpen(true);
    await settle(tester);
    expect(find.byKey(const Key('eye-recording-skip')), findsOneWidget);
    await holdOn(tester, 'eye-recording-skip');
    await runUntil(tester, () => view() == null, limit: const Duration(seconds: 10));
    final Map<String, Object?> end = one(
      kit.store.events(kit.folder),
      'eye.endcheck.result',
    );
    expect(end, <String, Object?>{'skipped': true});
    expect(sat().inputClosed, isTrue);
    expect(eye.info.endCheck, <String, Object?>{'skipped': true});
    await unmount(tester);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('SNO-F-EYE-06: строка «Взгляд: …» экрана завершения', () {
    expect(describeGaze(null), isNull);
    expect(describeGaze(<String, Object?>{'present': false}), isNull);
    expect(
      describeGaze(<String, Object?>{
        'present': true,
        'configured': true,
        'quality': 'low',
        'valid_share': 0.937,
        'calibration': <String, Object?>{'accuracy_deg': 3.14},
        'end_check': <String, Object?>{'skipped': true},
      }),
      'Взгляд: 94 % времени, точность в начале 3,1°, в конце — пропущена, '
      'с пометкой',
    );
    expect(
      describeGaze(<String, Object?>{
        'present': true,
        'configured': true,
        'end_check': <String, Object?>{'done': false, 'error': 'crash'},
      }),
      'Взгляд записан, в конце — не завершена',
    );
    expect(
      describeGaze(<String, Object?>{
        'present': false,
        'configured': true,
        'reason': 'stopped',
      }),
      'Взгляд не записан: запись остановлена до начала изучения',
    );
  });

  test('SNO-F-EYE-02: доля годного времени — по строкам потока', () {
    List<int> lines(List<bool> ok) => utf8.encode(<String>[
      for (int i = 0; i < ok.length; i++)
        jsonEncode(<String, Object?>{'n': i + 1, 'ok': ok[i]}).replaceAll(' ', ''),
      '',
    ].join('\n'));
    expect(gazeValidShare(lines(<bool>[true, true, false, true])), 0.75);
    expect(gazeValidShare(const <int>[]), isNull);
    // Оборванная строка в счёт не идёт.
    expect(
      gazeValidShare(<int>[...lines(<bool>[true]), ...utf8.encode('{"n":2,"ok":fa')]),
      1.0,
    );
  });
}
