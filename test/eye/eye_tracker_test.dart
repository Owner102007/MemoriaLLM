import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_calibration.dart';
import 'package:memoria/sno/eye/eye_link.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_tracker.dart';
import 'package:memoria/sno/eye/eye_trial.dart';
import 'package:memoria/sno/eye/eye_window.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/fake_eye.dart';
import '../support/mini_schema.dart';
import '../support/recording_fakes.dart';

/// SNO-F-EYE-04, SNO-F-EYE-07, SNO-ALG-EYE-03: спутник во время записи.
///
/// Сессия записи — настоящая, на памяти и подменённом времени; спутник,
/// окно, часы QPC и таймеры айтрекера — подставные.
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

  /// Даёт обещаниям и потокам айтрекера договорить.
  Future<void> settle() async {
    for (int i = 0; i < 60; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  late SessionKit kit;
  late FakeQpc qpc;
  late FakeEyeLauncher launcher;
  late FakeEyeWindow window;
  late EyeTracker eye;
  late int ms;
  late Map<Duration, void Function()> tickers;
  late List<Duration> waits;

  EyeTracker tracker() {
    return EyeTracker(
      settings: kit.settings,
      launch: launcher.launch,
      qpc: qpc,
      window: window,
      build: 'test',
      branch: 'I',
      monotonicMs: () => ms,
      ticker: (Duration every, void Function() onTick) {
        tickers[every] = onTick;
        return () => tickers.remove(every);
      },
      wait: (Duration pause) async => waits.add(pause),
    )..attach(kit.session);
  }

  setUp(() async {
    kit = SessionKit();
    qpc = FakeQpc();
    launcher = FakeEyeLauncher(make: (int n) => FakeEyeProcess(clock: qpc));
    window = FakeEyeWindow();
    ms = 0;
    tickers = <Duration, void Function()>{};
    waits = <Duration>[];
    await kit.settings.write(SnoSettingsKeys.eyePlace, place.encode());
    eye = tracker();
  });

  tearDown(() async {
    eye.dispose();
    await window.dispose();
    kit.session.dispose();
  });

  /// События `eye.*` журнала записи: вид и данные.
  List<(String, Map<String, Object?>)> eyeEvents() {
    return <(String, Map<String, Object?>)>[
      for (final Map<String, Object?> event in kit.store.events(kit.folder))
        if ((event['type']! as String).startsWith('eye.'))
          (
            event['type']! as String,
            (event['data'] as Map<String, Object?>?) ??
                const <String, Object?>{},
          ),
    ];
  }

  List<String> eyeTypes() => <String>[
    for (final (String type, _) in eyeEvents()) type,
  ];

  /// Запись началась, спутник поднят, журнал на диске.
  Future<void> started() async {
    expect(await kit.session.start(code), isTrue);
    await settle();
    kit.run(1);
    await settle();
  }

  test('SNO-F-EYE-03: старт записи закрывает идущую проверку айтрекера — '
      'спутник у машины один', () async {
    await eye.loadPlace();
    final EyeTrial trial = eye.beginTrial()!
      ..windowSize = () => const Size(1920, 1080);
    unawaited(trial.start(EyeCalibrationKind.quick));
    await settle();
    expect(trial.phase, EyeTrialPhase.calibrating);
    final FakeEyeProcess first = launcher.last;
    expect(first.names, contains('calibrate'));

    await started();
    expect(trial.phase, EyeTrialPhase.closed);
    expect(first.inputClosed, isTrue);
    expect(eye.trial.value, isNull);
    // Запись подняла свой спутник и поставила окно под свой замок.
    expect(launcher.started, hasLength(2));
    expect(eye.running, isTrue);
    expect(window.locked, isTrue);
  });

  group('SNO-F-EYE-04: спутник на время записи', () {
    test(
      'SNO-F-EYE-07: старт — окно на монитор места, спутник, часы',
      () async {
        await started();

        expect(window.locks, <String>[r'\\.\DISPLAY1']);
        expect(window.locked, isTrue);
        expect(launcher.started, hasLength(1));
        expect(launcher.last.names.first, 'hello');
        expect(eye.running, isTrue);
        expect(eyeTypes(), <String>[
          'eye.window',
          'eye.ready',
          'eye.clock',
          'eye.sync',
        ]);
        final Map<String, Object?> lock = eyeEvents()[0].$2;
        expect(lock['locked'], isTrue);
        expect(lock['monitor'], r'\\.\DISPLAY1');
        expect(lock['w_px'], 1920);
        expect(lock['h_px'], 1080);
        expect(lock['dpr'], 1.0);
        expect(lock['found'], isTrue);
        final Map<String, Object?> ready = eyeEvents()[1].$2;
        expect(ready['version'], '0.2.0');
        expect(ready['model_sha256'], '64184e22');
        final Map<String, Object?> clock = eyeEvents()[2].$2;
        expect(clock['qpc0_us'], isA<int>());
        expect(clock['t0'], isA<int>());
        final Map<String, Object?> sync = eyeEvents()[3].$2;
        expect(sync['n'], 15);
        expect(sync['offset_us'], 0);
        expect(sync['rtt_us'], greaterThan(0));
        // Сверка раз в минуту и проверка молчания раз в секунду заведены.
        expect(tickers.keys.toSet(), <Duration>{
          const Duration(seconds: 1),
          const Duration(minutes: 1),
        });
      },
    );

    test('SNO-ALG-EYE-03: раз в минуту — пять обменов и eye.sync', () async {
      await started();
      tickers[const Duration(minutes: 1)]!();
      await settle();
      kit.run(1);
      await settle();
      expect(eyeTypes().where((String t) => t == 'eye.sync'), hasLength(2));
      expect(eyeEvents().last.$2['n'], 5);
    });

    test('SNO-F-EYE-04: остановка — спутник закрыт, окно вернулось', () async {
      await started();
      final FakeEyeProcess process = launcher.last;
      await kit.session.stop(StopReason.experimenter);
      await settle();

      expect(process.inputClosed, isTrue);
      expect(process.killed, isFalse);
      expect(window.locked, isFalse);
      expect(window.unlocks, 1);
      expect(eye.running, isFalse);
      expect(tickers, isEmpty);
      // Сведения записи — что знает айтрекер.
      final Map<String, Object?> info = kit.store.json(
        kit.folder,
        kRecordingFile,
      );
      final Map<String, Object?> block =
          info['eye_tracker']! as Map<String, Object?>;
      expect(block['present'], isFalse);
      expect(block['configured'], isTrue);
      expect(block['restarts'], 0);
      expect(block['gave_up'], isFalse);
      expect((block['satellite']! as Map<String, Object?>)['version'], '0.2.0');
      expect((block['place']! as Map<String, Object?>)['distance_mm'], 600);
    });

    test('SNO-F-EYE-04: спутник вышел — eye.lost и подъём заново', () async {
      await started();
      launcher.last.exit(1);
      await settle();
      kit.run(1);
      await settle();

      expect(launcher.started, hasLength(2));
      expect(eyeTypes().skip(4).toList(), <String>[
        'eye.lost',
        'eye.restart',
        'eye.sync',
      ]);
      expect(eyeEvents()[4].$2, <String, Object?>{'reason': 'exit', 'code': 1});
      expect(eyeEvents()[5].$2['n'], 1);
      expect(eyeEvents()[5].$2['seg'], 1);
      expect(eye.running, isTrue);
    });

    test('SNO-F-EYE-04: четвёртая потеря — eye.gaveup, запись идёт', () async {
      await started();
      for (int i = 0; i < 4; i++) {
        launcher.last.exit(1);
        await settle();
      }
      kit.run(1);
      await settle();

      expect(launcher.started, hasLength(4));
      final List<String> types = eyeTypes();
      expect(types.where((String t) => t == 'eye.lost'), hasLength(4));
      expect(types.where((String t) => t == 'eye.restart'), hasLength(3));
      expect(types.last, 'eye.gaveup');
      expect(eyeEvents().last.$2, <String, Object?>{'restarts': 3});
      expect(eye.running, isFalse);
      expect(kit.session.recording, isTrue);
      expect(tickers, isEmpty);
      // Окно стоит под замком до остановки записи.
      expect(window.locked, isTrue);
      await kit.session.stop(StopReason.experimenter);
      await settle();
      final Map<String, Object?> block =
          kit.store.json(kit.folder, kRecordingFile)['eye_tracker']!
              as Map<String, Object?>;
      expect(block['restarts'], 3);
      expect(block['gave_up'], isTrue);
    });

    test('SNO-ALG-EYE-03: молчит десять секунд — снят и поднят', () async {
      await started();
      final FakeEyeProcess first = launcher.last;
      for (int s = 1; s <= 10; s++) {
        ms = s * 1000;
        tickers[const Duration(seconds: 1)]!();
      }
      await settle();
      kit.run(1);
      await settle();

      expect(first.killed, isTrue);
      expect(launcher.started, hasLength(2));
      expect(eyeEvents()[4].$2, <String, Object?>{'reason': 'silent'});
      expect(eyeTypes()[5], 'eye.restart');
    });

    test('SNO-ALG-EYE-03: подвисло приложение — спутник не трогают', () async {
      await started();
      final FakeEyeProcess first = launcher.last;
      // Сердцебиения есть, но лежат непрочитанными, пока приложение
      // стоит: тики через раз в шесть секунд.
      for (int s = 1; s <= 5; s++) {
        ms = s * 6000;
        tickers[const Duration(seconds: 1)]!();
      }
      await settle();
      expect(first.killed, isFalse);
      // Сердцебиения приходят — молчания нет.
      for (int s = 31; s <= 45; s++) {
        ms = s * 1000;
        first.beat(s);
        await settle();
        tickers[const Duration(seconds: 1)]!();
      }
      await settle();
      expect(first.killed, isFalse);
      expect(launcher.started, hasLength(1));
    });

    test('SNO-ALG-EYE-03: три строки мусора подряд — снят и поднят', () async {
      await started();
      final FakeEyeProcess first = launcher.last;
      first
        ..garbage('Traceback (most recent call last):')
        ..garbage('  File "protocol.py"')
        ..garbage('RuntimeError');
      await settle();
      kit.run(1);
      await settle();
      expect(first.killed, isTrue);
      expect(eyeEvents()[4].$2, <String, Object?>{'reason': 'garbage'});
      expect(launcher.started, hasLength(2));
    });

    test('SNO-F-EYE-07: монитор сменился — eye.window с changed', () async {
      await started();
      window.change(
        const EyeWindowLock(
          monitor: r'\\.\DISPLAY1',
          name: 'DELL P2419H',
          found: true,
          widthPx: 1280,
          heightPx: 720,
          dpr: 1,
        ),
      );
      await settle();
      kit.run(1);
      await settle();
      final (String type, Map<String, Object?> data) = eyeEvents().last;
      expect(type, 'eye.window');
      expect(data['changed'], isTrue);
      expect(data['w_px'], 1280);
    });
  });

  group('SNO-F-EYE-04: спутник умер, пока поднимался', () {
    test(
      'SNO-F-EYE-04: упал на сверке часов — eye.lost и подъём заново',
      () async {
        launcher = FakeEyeLauncher(
          make: (int n) =>
              FakeEyeProcess(clock: qpc, exitOn: n == 0 ? 'sync' : null),
        );
        eye.dispose();
        eye = tracker();
        await started();
        expect(eyeTypes(), <String>[
          'eye.window',
          'eye.ready',
          'eye.clock',
          'eye.lost',
          'eye.restart',
          'eye.sync',
        ]);
        expect(eyeEvents()[3].$2, <String, Object?>{
          'reason': 'exit',
          'code': 1,
        });
        expect(launcher.started, hasLength(2));
        expect(eye.running, isTrue);
      },
    );

    test('SNO-F-EYE-04: сведения о спутнике переживают перезапуск '
        'приложения до завершения сессии', () async {
      await started();
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await settle();
      expect(kit.settings.values[SnoSettingsKeys.eyeRun], isNotNull);

      // «Перезапуск»: новая сессия и новый айтрекер на тех же
      // настройках и записях.
      final SessionKit again = SessionKit(
        settings: kit.settings,
        store: kit.store,
        time: kit.time,
      );
      final EyeTracker fresh = EyeTracker(
        settings: kit.settings,
        launch: launcher.launch,
        qpc: qpc,
        window: window,
      )..attach(again.session);
      await settle();
      await again.session.restore();
      await again.session.finish();
      await settle();

      final Map<String, Object?> block =
          kit.store.json(folder, kRecordingFile)['eye_tracker']!
              as Map<String, Object?>;
      expect(block['configured'], isTrue);
      expect((block['satellite']! as Map<String, Object?>)['version'], '0.2.0');
      fresh.dispose();
      again.session.dispose();
    });
  });

  group('SNO-F-EYE-04: без взгляда', () {
    test(
      'SNO-F-EYE-05: место не задано — eye.unavailable, окна не трогают',
      () async {
        await kit.settings.remove(SnoSettingsKeys.eyePlace);
        await started();
        expect(eyeTypes(), <String>['eye.unavailable']);
        expect(eyeEvents().single.$2, <String, Object?>{
          'reason': 'not_configured',
          'text': 'Айтрекер не настроен — запись идёт без взгляда',
        });
        expect(window.locks, isEmpty);
        expect(launcher.started, isEmpty);
        await kit.session.stop(StopReason.experimenter);
        await settle();
        final Map<String, Object?> block =
            kit.store.json(kit.folder, kRecordingFile)['eye_tracker']!
                as Map<String, Object?>;
        expect(block, <String, Object?>{
          'present': false,
          'configured': false,
          'unavailable': 'not_configured',
          'restarts': 0,
          'gave_up': false,
        });
      },
    );

    test(
      'SNO-F-EYE-04: папки eye/ нет — eye.unavailable, запись идёт',
      () async {
        launcher.failWith = const EyeError('no_satellite', 'нет eye');
        await started();
        expect(eyeTypes(), <String>['eye.window', 'eye.unavailable']);
        expect(eyeEvents().last.$2, <String, Object?>{
          'reason': 'no_satellite',
          'text': 'Айтрекер не запустился: рядом с приложением нет папки eye',
        });
        expect(kit.session.recording, isTrue);
        expect(tickers, isEmpty);
      },
    );

    test('SNO-F-EYE-04: спутник другой версии — eye.unavailable', () async {
      launcher = FakeEyeLauncher(
        make: (int n) => FakeEyeProcess(clock: qpc, protocol: 2),
      );
      eye.dispose();
      eye = tracker();
      await started();
      expect(eyeEvents().last.$2['reason'], 'version');
      expect(launcher.last.inputClosed, isTrue);
    });

    test(
      'SNO-F-EYE-04: прежний спутник ещё держит имя — ждём и ещё раз',
      () async {
        launcher = FakeEyeLauncher(
          make: (int n) => FakeEyeProcess(clock: qpc, alreadyRunning: n < 2),
        );
        eye.dispose();
        eye = tracker();
        await started();
        expect(launcher.started, hasLength(3));
        expect(waits, <Duration>[kAlreadyRunningPause, kAlreadyRunningPause]);
        expect(eyeTypes(), contains('eye.ready'));
      },
    );
  });

  group('SNO-F-EYE-05: место записи', () {
    test('SNO-F-EYE-05: место читается и сохраняется', () async {
      expect(await eye.loadPlace(), isNotNull);
      expect(eye.placeLoaded, isTrue);
      expect(eye.place!.monitor, r'\\.\DISPLAY1');
      await kit.settings.remove(SnoSettingsKeys.eyePlace);
      expect(await eye.loadPlace(), isNull);
      await eye.savePlace(place);
      expect(
        EyePlace.decode(await kit.settings.read(SnoSettingsKeys.eyePlace))!
            .distanceMm,
        600,
      );
    });

    test('SNO-F-EYE-05: связь для экрана — hello уже сказан', () async {
      final EyeLink link = await eye.connect();
      expect(launcher.last.names, <Object?>['hello']);
      await link.close();
      expect(launcher.last.inputClosed, isTrue);
    });
  });

  group('SNO-ALG-REC-03: блок eye_tracker манифеста', () {
    test('SNO-F-EYE-04: манифест берёт блок из сведений и проходит схему', () {
      final Map<String, Object?> schema = jsonDecode(
        File('tool/sno_manifest.schema.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> block = <String, Object?>{
        'present': false,
        'configured': true,
        'place': place.toJson(),
        'restarts': 1,
        'gave_up': false,
      };
      final Map<String, Object?> manifest = buildManifest(
        info: <String, Object?>{
          'schema': kRecordingSchema,
          'branch': 'I',
          'eye_tracker': block,
        },
        archiveName: 'sno2026_I_67954332_a91f3c_20261008-1200.zip',
        packedAt: DateTime.utc(2026, 10, 8),
        files: const <PackedFile>[],
      );
      expect(manifest['eye_tracker'], block);
      expect(schemaProblems(manifest, schema), isEmpty);
      // Без айтрекера — только то, что взгляда нет.
      final Map<String, Object?> phone = buildManifest(
        info: <String, Object?>{'schema': kRecordingSchema, 'branch': 'I'},
        archiveName: 'sno2026_I_67954332_a91f3c_20261008-1200.zip',
        packedAt: DateTime.utc(2026, 10, 8),
        files: const <PackedFile>[],
      );
      expect(phone['eye_tracker'], <String, Object?>{'present': false});
      expect(
        schemaProblems(<String, Object?>{
          ...manifest,
          'eye_tracker': <String, Object?>{'present': false, 'restarts': -1},
        }, schema),
        isNotEmpty,
      );
    });
  });
}
