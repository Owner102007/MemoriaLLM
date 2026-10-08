import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_calibration.dart';
import 'package:memoria/sno/eye/eye_link.dart';
import 'package:memoria/sno/eye/eye_process.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_timing.dart';
import 'package:memoria/sno/eye/qpc_clock.dart';

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
      // середину.
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
      final EyeFit fit = await link.fit();
      expect(fit.model, 'ridge');
      expect(fit.points, 9);
      expect(fit.headModel, 'phase');
      expect(fit.headPhase?.moved, isTrue);
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
