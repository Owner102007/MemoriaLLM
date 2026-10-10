import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_calibration.dart';
import 'package:memoria/sno/eye/eye_link.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_process.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_recording.dart';
import 'package:memoria/sno/eye/eye_timing.dart';
import 'package:memoria/sno/eye/eye_tracker.dart';
import 'package:memoria/sno/eye/qpc_clock.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/file_store.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/fake_eye.dart';
import '../support/recording_fakes.dart';

/// SNO-ALG-EYE-03, SNO-F-EYE-04: связь приложения с настоящим спутником
/// на Windows.
///
/// Идёт только в CI — в работе сборки Windows ветви I, где папка
/// `eye/` собрана по замкам: её путь приходит переменной окружения
/// `SNO_EYE_DIR`. Проверяется то, чего подставной спутник не покажет:
/// запуск `python.exe` из приложения (без окна консоли и с кириллицей в
/// пути журнала), разбор настоящих ответов, общие часы QPC у двух
/// процессов и выход спутника за две секунды после закрытия stdin.
/// Камеры на раннере нет.
void main() {
  final String? folder = Platform.environment['SNO_EYE_DIR'];
  final Object skip = folder == null || !Platform.isWindows
      ? 'нужна папка eye/ Windows (SNO_EYE_DIR) — идёт в CI на Windows'
      : false;

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('айтрекер ');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Журнал спутника ещё держится: временную папку уберёт раннер.
    }
  });

  EyeLauncher launcher({List<String> extra = const <String>[]}) {
    return satelliteLauncher(
      Directory(folder!),
      log: () async => File('${temp.path}${Platform.pathSeparator}журнал.txt'),
      extra: extra,
    );
  }

  /// Запускает спутник и здоровается. На свежем раннере первый запуск
  /// бывает холодным — распаковка и первая загрузка колёс — и `hello` не
  /// успевает: такой спутник снимается (иначе он держит замок экземпляра,
  /// и следующие тесты отказывают «спутник уже запущен»), и запуск
  /// повторяется один раз (шаг 29; CI №316).
  Future<(EyeLink, EyeHello)> started(
    QpcClock qpc, {
    List<String> extra = const <String>[],
    String build = '',
    String branch = '',
  }) async {
    for (int round = 0; ; round++) {
      final EyeLink link = await EyeLink.start(
        launcher(extra: extra),
        qpc: qpc,
      );
      try {
        return (link, await link.hello(build: build, branch: branch));
      } on EyeError catch (e) {
        await link.kill();
        if (e.code != 'timeout' || round > 0) {
          rethrow;
        }
        stdout.writeln('ЗАМЕР SNO-F-EYE-04 | холодный запуск: hello не успел');
      }
    }
  }

  test(
    'SNO-ALG-EYE-03: hello, камеры, общие часы и выход за две секунды',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final (EyeLink link, EyeHello hello) = await started(
        qpc,
        build: 'ci',
        branch: 'I',
      );
      expect(hello.protocol, kEyeProtocol);
      expect(hello.mediapipe, isNotEmpty);
      expect(hello.modelSha256, hasLength(64));
      expect(await link.cameras(), isA<List<EyeCamera>>());

      final SyncResult sync = (await link.sync(kSyncRoundsOpen))!;
      stdout.writeln(
        'ЗАМЕР SNO-ALG-EYE-03 | сверка часов | смещение ${sync.offsetUs} мкс '
        '| ответ ${sync.rttUs} мкс | обменов ${sync.rounds}',
      );
      expect(sync.rounds, kSyncRoundsOpen);
      // Оба процесса читают один QPC: смещение — ноль с точностью до
      // половины ответа и микросекунды пересчёта.
      expect(sync.offsetUs.abs(), lessThanOrEqualTo(sync.errorUs + 2));

      // Камеры на раннере нет — самопроверка говорит это словами.
      final EyeCheck check = await link.selfcheck(
        camera: null,
        seconds: 0.5,
        warmup: 0,
      );
      expect(check.verdict, EyeVerdict.fail);
      expect(
        check.row('camera')?.value,
        isIn(<String>['no_camera', 'camera_busy', 'camera_denied']),
      );

      final Stopwatch watch = Stopwatch()..start();
      await link.close();
      expect(link.exited, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(2500));
      expect(await link.exitCode, 0);
      // Журнал спутника лёг в папку с кириллицей.
      expect(
        File('${temp.path}${Platform.pathSeparator}журнал.txt').existsSync(),
        isTrue,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SNO-F-EYE-05: самопроверка с кадрами камеры — на синтетике',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final (EyeLink link, _) = await started(
        qpc,
        extra: const <String>['--source', 'synthetic'],
      );
      final List<EyePreview> shots = <EyePreview>[];
      link.onProgress = (Map<String, Object?> message) {
        final EyePreview? shot = EyePreview.fromMessage(message);
        if (shot != null) {
          shots.add(shot);
        }
      };
      final EyeCheck check = await link.selfcheck(
        camera: const EyeCamera(index: 0, name: 'Синтетическая камера'),
        seconds: 1,
        warmup: 0.3,
        dir: temp.path,
        preview: true,
      );
      expect(check.verdict, isNot(EyeVerdict.fail));
      expect(shots, isNotEmpty);
      expect(shots.last.width, lessThanOrEqualTo(320));
      expect(shots.last.face, isNotNull);
      await link.close();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SNO-ALG-EYE-02, BUG-60: быстрая калибровка на синтетическом участнике — '
    'точки по QPC приложения, фаза движения головы, модель, проверка, '
    'проверка точности без новой калибровки, живая точка, файлы',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final (EyeLink link, _) = await started(
        qpc,
        extra: const <String>['--source', 'synthetic:follow'],
      );
      final List<EyeGaze> gaze = <EyeGaze>[];
      link.onGaze = gaze.add;
      final String folder = '${temp.path}${Platform.pathSeparator}стенд';
      final List<int>? frame = await link.open(
        screen: const EyeScreen(
          width: 1920,
          height: 1080,
          widthMm: 527,
          heightMm: 296,
        ),
        distanceMm: 600,
        dir: folder,
        strip: false,
      );
      expect(frame, isNotNull);
      await link.calibrate(attempt: 1, kind: 'quick');
      Future<void> show(String phase, String prefix) async {
        for (int i = 0; i < kValidationPoints.length; i++) {
          final (double fx, double fy) = kValidationPoints[i];
          link.target(
            phase: phase,
            qpcUs: qpc.nowUs(),
            id: '$prefix$i',
            x: fx * 1920,
            y: fy * 1080,
          );
          await Future<void>.delayed(const Duration(milliseconds: 1300));
        }
        link.target(phase: 'off', qpcUs: qpc.nowUs());
      }

      await show('calib', 'q');
      final EyeSamples samples = await link.samples();
      expect(samples.short, isEmpty);
      expect(samples.face, 1.0);
      // BUG-60: фаза движения головы — участник водит головой, глядя в
      // середину; BUG-61: спутник говорит, где голова.
      final List<EyeHeadPose> heads = <EyeHeadPose>[];
      link.onHead = heads.add;
      link.target(
        phase: 'head',
        qpcUs: qpc.nowUs(),
        id: 'head',
        x: 960,
        y: 540,
      );
      await Future<void>.delayed(const Duration(seconds: 9));
      link.target(phase: 'off', qpcUs: qpc.nowUs());
      final EyeSamples head = await link.samples(phase: 'head');
      expect(head.face, 1.0);
      link.onHead = null;
      expect(heads.length, greaterThan(100));
      final Iterable<double> turns = heads.map((EyeHeadPose p) => p.turnDeg);
      expect(turns.reduce(math.max), greaterThan(5));
      expect(turns.reduce(math.min), lessThan(-5));
      // Калибровка здесь — по точкам проверки (20–80 % окна): предел
      // наклона около ±8°, и кивки участника на ±7° с покачиванием
      // изредка его задевают.
      final int far = heads.where((EyeHeadPose p) => p.far).length;
      expect(far, lessThan(heads.length ~/ 10));
      final EyeFit fit = await link.fit();
      expect(fit.model, 'ridge');
      expect(fit.points, 9);
      // BUG-62: главный способ — геометрия.
      expect(fit.headModel, 'geometry');
      expect(fit.headPhase?.moved, isTrue);
      expect(fit.headPhase?.accepted, isNotNull);
      await show('validate', 'v');
      final EyeValidation v = await link.validate();
      await link.check(1);
      await show('check', 'k');
      final EyeAccuracy a = await link.checked();
      stdout.writeln(
        'ЗАМЕР SNO-ALG-EYE-02 | быстрая калибровка на синтетике | '
        'ошибка без одной точки ${fit.cvDeg}° | проверка ${v.accuracyDeg}° '
        '| прецизионность ${v.precisionDeg}° | проверка без калибровки '
        '${a.accuracyDeg}° | способы ${a.variants}',
      );
      expect(v.accuracyDeg, lessThan(3.0));
      expect(a.n, 1);
      expect(a.accuracyDeg, lessThan(3.0));
      expect(a.variants.keys, containsAll(<String>['learned', 'geometry']));
      await link.live(on: true);
      await Future<void>.delayed(const Duration(seconds: 1));
      await link.live(on: false);
      expect(gaze.where((EyeGaze g) => g.ok), hasLength(greaterThan(20)));
      final Map<String, Object?>? summary = await link.closeCamera();
      expect(summary, isNotNull);
      expect(
        File('$folder${Platform.pathSeparator}calibration.json').existsSync(),
        isTrue,
      );
      expect(
        File('$folder${Platform.pathSeparator}checks.json').existsSync(),
        isTrue,
      );
      await link.close();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SNO-F-REC-04, SNO-F-EYE-02: поток взгляда на синтетическом участнике — '
    'строки по часам записи, перезапуск той же моделью в следующий '
    'сегмент, итоги сегментов',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final String sep = Platform.pathSeparator;
      final String folder =
          '${temp.path}$sepЗаписи$sep.current$sepзапись${sep}eye';
      const EyeScreen screen = EyeScreen(
        width: 1920,
        height: 1080,
        widthMm: 527,
        heightMm: 296,
      );
      final int qpc0 = qpc.nowUs();
      final (EyeLink link, _) = await started(
        qpc,
        extra: const <String>['--source', 'synthetic:follow'],
      );
      await link.open(
        screen: screen,
        distanceMm: 600,
        dir: folder,
        seg: 0,
        qpc0Us: qpc0,
        t0: 0,
      );
      await link.calibrate(attempt: 1, kind: 'quick');
      for (int i = 0; i < kValidationPoints.length; i++) {
        final (double fx, double fy) = kValidationPoints[i];
        link.target(
          phase: 'calib',
          qpcUs: qpc.nowUs(),
          id: 'q$i',
          x: fx * 1920,
          y: fy * 1080,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1300));
      }
      link.target(phase: 'off', qpcUs: qpc.nowUs());
      await link.fit();
      final List<EyeFace> faces = <EyeFace>[];
      link.onFace = faces.add;
      expect(await link.gaze(on: true), 1);
      await Future<void>.delayed(const Duration(seconds: 3));
      final Map<String, Object?>? first = await link.closeCamera();
      await link.close();
      final Map<String, Object?> gaze1 =
          first!['gaze']! as Map<String, Object?>;
      final int lines1 = gaze1['lines']! as int;
      stdout.writeln(
        'ЗАМЕР SNO-F-REC-04 | поток взгляда | строк за 3 с: $lines1 | '
        'годных ${gaze1['valid_share']}',
      );
      expect(lines1, greaterThanOrEqualTo(60));

      // Спутник поднят заново: модель из файла, следующий сегмент.
      final (EyeLink again, _) = await started(
        qpc,
        extra: const <String>['--source', 'synthetic:follow'],
      );
      await again.open(
        screen: screen,
        distanceMm: 600,
        dir: folder,
        seg: 1,
        qpc0Us: qpc0,
        t0: 0,
        calibration: '$folder${sep}calibration.json',
      );
      expect(await again.gaze(on: true), lines1 + 1);
      await Future<void>.delayed(const Duration(seconds: 2));
      await again.closeCamera();
      await again.close();

      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        for (final String line in File(
          '$folder${sep}gaze.jsonl',
        ).readAsLinesSync())
          if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
      ];
      expect(
        rows.map((Map<String, Object?> r) => r['n']),
        List<int>.generate(rows.length, (int i) => i + 1),
      );
      expect(rows.map((Map<String, Object?> r) => r['seg']).toSet(), <int>{
        0,
        1,
      });
      final List<int> times = <int>[
        for (final Map<String, Object?> r in rows) r['t']! as int,
      ];
      expect(times, orderedEquals(List<int>.of(times)..sort()));
      for (final String name in <String>[
        'features.bin',
        'features.1.bin',
        'eyes.mp4',
        'eyes.1.mp4',
        'summary.json',
        'summary.1.json',
        'calibration.json',
      ]) {
        expect(File('$folder$sep$name').existsSync(), isTrue, reason: name);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'SNO-F-EYE-01, SNO-F-EYE-02, SNO-F-EYE-06: запись с настоящим '
    'спутником на синтетическом участнике — калибровка внутри записи, '
    'изучение со взглядом, проверка в конце, файлы eye/ в архиве',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final String sep = Platform.pathSeparator;
      final Directory records = Directory('${temp.path}$sepЗаписи');
      final MemorySettings settings = MemorySettings();
      final RecordingSession session = RecordingSession(
        settings: settings,
        store: FileRecordingStore(() async => records),
        nodeId: kTestNode,
        snapshot: () async => <String, Object?>{'schema': 'sno2026-snapshot/1'},
        branch: 'I',
        device: 'a91f3c',
      );
      await settings.write(
        SnoSettingsKeys.eyePlace,
        EyePlace(
          camera: const EyeCamera(index: 0, name: 'Синтетическая камера'),
          monitor: r'\\.\DISPLAY1',
          monitorName: 'CI',
          widthPx: 1920,
          heightPx: 1080,
          pxPerMm: 1920 / 527,
          sizeSource: ScreenSizeSource.card,
          distanceMm: 600,
          verdict: EyeVerdict.good,
          checkedAt: DateTime.utc(2026, 10, 9, 12),
          mode: const <int>[1280, 720],
          fps: 30,
        ).encode(),
      );
      final FakeEyeWindow window = FakeEyeWindow();
      final EyeTracker eye = EyeTracker(
        settings: settings,
        launch: launcher(extra: const <String>['--source', 'synthetic:follow']),
        qpc: qpc,
        window: window,
      )..attach(session);

      Future<void> waitFor(bool Function() done, Duration limit) async {
        final Stopwatch watch = Stopwatch()..start();
        while (!done() && watch.elapsed < limit) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(done(), isTrue, reason: 'не дождались за $limit');
      }

      final Stopwatch total = Stopwatch()..start();
      expect(
        await session.start(
          ParticipantCode(
            code: kTestCode,
            generated: true,
            generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
          ),
        ),
        isTrue,
      );
      await waitFor(
        () => eye.recording.value != null,
        const Duration(seconds: 60),
      );
      // Экрана в этом тесте нет: окно и миг показа точки называет тест.
      final EyeRecordingView view = eye.recording.value!;
      view.windowSize = () => const Size(1920, 1080);
      view.frameShown = () async => qpc.nowUs();
      await waitFor(
        () => view.phase == EyeRecordingPhase.result,
        const Duration(minutes: 3),
      );
      final int calibrationMs = total.elapsedMilliseconds;
      final double? accuracy = view.outcome?.validation?.accuracyDeg;
      stdout.writeln(
        'ЗАМЕР SNO-F-EYE-01 | калибровка внутри записи на синтетике | '
        '${calibrationMs ~/ 1000} с | точность $accuracy° | '
        'принята ${view.outcome?.validation?.accepted}',
      );
      if (view.outcome?.validation?.accepted ?? false) {
        await view.begin();
      } else {
        await view.choose(write: true);
      }
      await waitFor(() => !session.studyPending, const Duration(seconds: 20));
      expect(eye.info.present, isTrue);
      await Future<void>.delayed(const Duration(seconds: 3));
      await session.stop(StopReason.experimenter);
      await waitFor(
        () => eye.recording.value == null,
        const Duration(seconds: 90),
      );
      // Спутник пишет сырьё с открытия камеры до закрытия.
      final int writingMs = total.elapsedMilliseconds;
      final String folder = session.state!.folder;
      final String eyeDir = (await session.folderPath(kEyeFolder))!;
      final List<String> lines = File('$eyeDir${sep}gaze.jsonl')
          .readAsLinesSync();
      stdout.writeln(
        'ЗАМЕР SNO-F-EYE-02 | запись со взглядом на синтетике | строк '
        '${lines.length} | годных ${eye.info.validShare} | в конце '
        '${eye.info.endCheck?['accuracy_deg']}°',
      );
      expect(lines.length, greaterThanOrEqualTo(60));
      expect(eye.info.check?.intact, isTrue);
      expect(eye.info.endCheck?['accuracy_deg'], isA<double>());
      for (final String name in <String>[
        'features.bin',
        'eyes.mp4',
        'calibration.json',
        'selfcheck.json',
        'summary.json',
      ]) {
        expect(File('$eyeDir$sep$name').existsSync(), isTrue, reason: name);
      }
      expect(window.locked, isFalse);

      // Вес сырья взгляда за секунду работы спутника — прикидка на сорок
      // минут (критерий шага: не больше 300 МБ).
      int eyeBytes = 0;
      for (final FileSystemEntity f in Directory(eyeDir).listSync()) {
        if (f is File) {
          eyeBytes += f.lengthSync();
        }
      }
      final double perSecond = eyeBytes / (writingMs / 1000);
      await session.finish();
      final Stopwatch packing = Stopwatch()..start();
      final File archive = await packRecording(
        Directory('${records.path}$sep$folder'),
      );
      stdout.writeln(
        'ЗАМЕР SNO-F-REC-04 | архив записи со взглядом | '
        '${archive.lengthSync() ~/ 1024} КБ | упаковка '
        '${packing.elapsedMilliseconds} мс | eye/ ${eyeBytes ~/ 1024} КБ за '
        '$writingMs мс работы спутника | на 40 мин '
        '~${(perSecond * 2400 / 1e6).toStringAsFixed(0)} МБ',
      );
      final ArchiveCheck check = await checkArchive(archive);
      expect(check.intact, isTrue);
      final Map<String, Object?> manifest = check.manifest!;
      final Map<String, Object?> block =
          manifest['eye_tracker']! as Map<String, Object?>;
      expect(block['present'], isTrue);
      expect(block['file'], 'eye/gaze.jsonl');
      final Map<String, Object?> files =
          manifest['files']! as Map<String, Object?>;
      expect(
        files.keys,
        containsAll(<String>[
          'eye/gaze.jsonl',
          'eye/features.bin',
          'eye/eyes.mp4',
          'eye/calibration.json',
        ]),
      );
      expect(
        (files['eye/gaze.jsonl']! as Map<String, Object?>)['lines'],
        lines.length,
      );

      // SNO-F-RES-01: «Проверка записи» — тем же встраиваемым Python, что
      // у организатора, на архиве с настоящим потоком взгляда и путём с
      // кириллицей. Сборка в тесте проверочная — это оговорка, а не
      // порча.
      final ProcessResult checked = await Process.run(
        // Папка спутника; `folder` здесь — имя папки записи.
        '${Platform.environment['SNO_EYE_DIR']}${sep}python.exe',
        <String>[
          '-I',
          '-m',
          'sno_eye',
          'check',
          archive.path,
          '--json',
          '--no-csv',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final String out = '${checked.stdout}';
      expect(out.trimLeft(), startsWith('['), reason: '${checked.stderr}');
      final Map<String, Object?> report =
          (jsonDecode(out) as List<Object?>).single! as Map<String, Object?>;
      expect(report['problems'], isEmpty);
      expect(report['verdict'], isNot('bad'));
      expect(report['gaze'], isTrue);
      final Map<String, Object?> listed =
          report['files']! as Map<String, Object?>;
      expect(listed['intact'], listed['listed']);
      final Map<String, Object?> streams =
          report['streams']! as Map<String, Object?>;
      expect(
        (streams['eye/gaze.jsonl']! as Map<String, Object?>)['lines'],
        lines.length,
      );
      stdout.writeln(
        'ЗАМЕР SNO-F-RES-01 | «Проверка записи» на архиве со взглядом | '
        '${report['verdict_text']} | годных ${report['valid_share']} | '
        'кадров в секунду ${report['fps']} | точность '
        '${report['start_deg']}° / ${report['end_deg']}°',
      );

      // SNO-F-RES-03: «Разбор записи» — тем же встраиваемым Python, на
      // том же архиве. Архив лежит в папке «Записи», поэтому папка
      // разбора названа явно (без неё разбор ушёл бы в «Документы»).
      final Directory reportOut = Directory('${temp.path}$sepРазбор');
      final Stopwatch reporting = Stopwatch()..start();
      final ProcessResult reported = await Process.run(
        '${Platform.environment['SNO_EYE_DIR']}${sep}python.exe',
        <String>[
          '-I',
          '-m',
          'sno_eye',
          'report',
          archive.path,
          '--json',
          '--out',
          reportOut.path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final String reportText = '${reported.stdout}';
      expect(
        reportText.trimLeft(),
        startsWith('['),
        reason: '${reported.stderr}',
      );
      final Map<String, Object?> analysed =
          (jsonDecode(reportText) as List<Object?>).single!
              as Map<String, Object?>;
      expect(analysed['refused'], isNull, reason: '${analysed['refused']}');
      expect(analysed['gaze_used'], isTrue);
      final String base = archive.uri.pathSegments.last;
      final String folderName =
          '${base.substring(0, base.length - '.zip'.length)}_eye';
      for (final String name in <String>[
        'index.html',
        'fixations.csv',
        'visits.csv',
        'measures.csv',
        'quality.json',
      ]) {
        expect(
          File('${reportOut.path}$sep$folderName$sep$name').existsSync(),
          isTrue,
          reason: name,
        );
      }
      final Map<String, Object?> quality =
          analysed['quality']! as Map<String, Object?>;
      stdout.writeln(
        'ЗАМЕР SNO-F-RES-03 | «Разбор записи» на архиве со взглядом | '
        '${reporting.elapsedMilliseconds} мс | фиксаций '
        '${analysed['fixation_count']} | годных ${quality['valid_share']} '
        '| точность ${quality['start_deg']}° / ${quality['end_deg']}°',
      );
      eye.dispose();
      session.dispose();
      await window.dispose();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'SNO-F-EYE-04: второй экземпляр отказывается словами',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final (EyeLink first, _) = await started(qpc);
      final EyeLink second = await EyeLink.start(launcher(), qpc: qpc);
      await expectLater(
        second.hello(),
        throwsA(
          isA<EyeError>().having(
            (EyeError e) => e.code,
            'code',
            'already_running',
          ),
        ),
      );
      expect(await second.exitCode, 3);
      await second.close();
      await first.close();
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
