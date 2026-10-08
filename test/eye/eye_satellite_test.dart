import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test(
    'SNO-ALG-EYE-03: hello, камеры, общие часы и выход за две секунды',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final EyeLink link = await EyeLink.start(launcher(), qpc: qpc);
      final EyeHello hello = await link.hello(build: 'ci', branch: 'I');
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
      expect(check.row('camera')?.value, isIn(<String>[
        'no_camera',
        'camera_busy',
        'camera_denied',
      ]));

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
      final EyeLink link = await EyeLink.start(
        launcher(extra: const <String>['--source', 'synthetic']),
        qpc: qpc,
      );
      final List<EyePreview> shots = <EyePreview>[];
      link.onProgress = (Map<String, Object?> message) {
        final EyePreview? shot = EyePreview.fromMessage(message);
        if (shot != null) {
          shots.add(shot);
        }
      };
      await link.hello();
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
    'SNO-F-EYE-04: второй экземпляр отказывается словами',
    () async {
      final QpcClock qpc = WindowsQpcClock.open()!;
      final EyeLink first = await EyeLink.start(launcher(), qpc: qpc);
      await first.hello();
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
