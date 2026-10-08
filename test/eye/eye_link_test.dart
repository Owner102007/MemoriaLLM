import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_link.dart';
import 'package:memoria/sno/eye/eye_process.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_timing.dart';

import '../support/fake_eye.dart';

/// SNO-ALG-EYE-03, SNO-F-EYE-04: связь со спутником на подставном
/// процессе.
void main() {
  late FakeQpc qpc;

  setUp(() => qpc = FakeQpc());

  Future<(EyeLink, FakeEyeProcess)> open([
    FakeEyeProcess Function()? make,
  ]) async {
    final FakeEyeProcess process = make?.call() ?? FakeEyeProcess(clock: qpc);
    final EyeLink link = await EyeLink.start(
      () async => process,
      qpc: qpc,
    );
    return (link, process);
  }

  test('SNO-F-EYE-04: hello — версии; камеры — списком', () async {
    final (EyeLink link, FakeEyeProcess process) = await open();
    final EyeHello hello = await link.hello(build: '0.33.0', branch: 'I');
    expect(hello.version, '0.1.0');
    expect(hello.mediapipe, '1.1.0');
    expect(process.commands.first, <String, Object?>{
      'cmd': 'hello',
      'v': 1,
      'build': '0.33.0',
      'branch': 'I',
    });
    expect((await link.cameras()).single.name, 'Integrated Camera');
    await link.close();
    expect(process.inputClosed, isTrue);
    expect(process.killed, isFalse);
  });

  test('SNO-F-EYE-04: спутник другой версии — отказ', () async {
    final (EyeLink link, _) = await open(
      () => FakeEyeProcess(clock: qpc, protocol: 2),
    );
    await expectLater(
      link.hello(),
      throwsA(isA<EyeError>().having((EyeError e) => e.code, 'code', 'version')),
    );
    await link.close();
  });

  test('SNO-F-EYE-04: ошибка на команду приходит ей, а не другой', () async {
    final (EyeLink link, _) = await open(
      () => FakeEyeProcess(clock: qpc, helloError: 'model_missing'),
    );
    await expectLater(
      link.hello(),
      throwsA(
        isA<EyeError>()
            .having((EyeError e) => e.code, 'code', 'model_missing')
            .having((EyeError e) => e.command, 'cmd', 'hello'),
      ),
    );
    // Связь жива: следующая команда получает свой ответ.
    expect(await link.cameras(), hasLength(1));
    await link.close();
  });

  test('SNO-F-EYE-04: второй экземпляр — already_running', () async {
    final (EyeLink link, FakeEyeProcess process) = await open(
      () => FakeEyeProcess(clock: qpc, alreadyRunning: true),
    );
    await expectLater(
      link.hello(),
      throwsA(
        isA<EyeError>().having((EyeError e) => e.code, 'code', 'already_running'),
      ),
    );
    expect(await link.exitCode, 3);
    expect(process.exited, isTrue);
    await link.close();
  });

  test('SNO-ALG-EYE-03: спутник вышел — ожидающие узнают сразу', () async {
    final (EyeLink link, FakeEyeProcess process) = await open();
    process.mute = true;
    final Future<EyeHello> hello = link.hello();
    process.exit(1);
    await expectLater(
      hello,
      throwsA(isA<EyeError>().having((EyeError e) => e.code, 'code', 'exit')),
    );
    expect(await link.exitCode, 1);
    expect(link.exited, isTrue);
    await expectLater(
      link.cameras(),
      throwsA(isA<EyeError>().having((EyeError e) => e.code, 'code', 'exit')),
    );
    await link.close();
  });

  test('SNO-ALG-EYE-03: ответа нет — timeout, а запоздавший не чужой', () async {
    final (EyeLink link, FakeEyeProcess process) = await open();
    process.mute = true;
    await expectLater(
      link.request('cameras', timeout: const Duration(milliseconds: 20)),
      throwsA(isA<EyeError>().having((EyeError e) => e.code, 'code', 'timeout')),
    );
    // Запоздавший ответ на снятую команду никому не достаётся.
    process.emit(<String, Object?>{'reply': 'cameras', 'cameras': <Object?>[]});
    await Future<void>.delayed(Duration.zero);
    await link.kill();
    expect(process.killed, isTrue);
  });

  test('SNO-ALG-EYE-03: сердцебиение, ход и мусор — своим слушателям', () async {
    final (EyeLink link, FakeEyeProcess process) = await open();
    final List<int> beats = <int>[];
    final List<Object?> stages = <Object?>[];
    final List<int> garbage = <int>[];
    final List<EyeError> errors = <EyeError>[];
    link
      ..onHeartbeat = (EyeHeartbeat beat) => beats.add(beat.n)
      ..onProgress = (Map<String, Object?> m) => stages.add(m['stage'])
      ..onGarbage = garbage.add
      ..onError = errors.add;
    process
      ..beat(1)
      ..garbage('Traceback (most recent call last):')
      ..garbage('  File "x.py"')
      ..beat(2)
      ..garbage('мусор')
      ..emit(<String, Object?>{'progress': 'selfcheck', 'stage': 'warmup'})
      ..emit(<String, Object?>{
        'error': 'camera_lost',
        'text': 'Камера пропала',
        'cmd': 'record',
      });
    await Future<void>.delayed(Duration.zero);
    expect(beats, <int>[1, 2]);
    // Счёт мусора — подряд: сердцебиение его обнуляет.
    expect(garbage, <int>[1, 2, 1]);
    expect(link.garbageInRow, 0);
    expect(stages, <Object?>['warmup']);
    expect(errors.single.code, 'camera_lost');
    await link.close();
  });

  test('SNO-ALG-EYE-04: самопроверка — камера, кадры и итог', () async {
    final (EyeLink link, FakeEyeProcess process) = await open();
    final List<Object?> stages = <Object?>[];
    link.onProgress = (Map<String, Object?> m) => stages.add(m['stage']);
    final EyeCheck check = await link.selfcheck(
      camera: const EyeCamera(index: 0, name: 'Integrated Camera'),
      seconds: 5,
      dir: r'C:\Записи',
      preview: true,
    );
    expect(check.verdict, EyeVerdict.good);
    expect(check.mode, <int>[1920, 1080]);
    expect(stages, <Object?>['warmup', 'measure']);
    expect(process.commands.last, <String, Object?>{
      'cmd': 'selfcheck',
      'v': 1,
      'camera': <String, Object?>{'index': 0, 'name': 'Integrated Camera'},
      'seconds': 5.0,
      'dir': r'C:\Записи',
      'preview': true,
    });
    await link.close();
  });

  test('SNO-ALG-EYE-03: рукопожатие находит сдвиг часов спутника', () async {
    final (EyeLink link, FakeEyeProcess process) = await open(
      () => FakeEyeProcess(clock: qpc, offsetUs: 7345),
    );
    final SyncResult result = (await link.sync(kSyncRoundsOpen))!;
    expect(result.rounds, kSyncRoundsOpen);
    expect(process.names.where((Object? n) => n == 'sync'), hasLength(15));
    // Часы делают шаг на каждое чтение: погрешность — полвремени ответа.
    expect((result.offsetUs - 7345).abs(), lessThanOrEqualTo(result.errorUs));
    expect(result.rttUs, greaterThan(0));
    await link.close();
  });

  test('SNO-F-EYE-04: не запустился — EyeError от запуска', () async {
    await expectLater(
      EyeLink.start(
        () async => throw const EyeError('no_satellite', 'нет eye'),
        qpc: qpc,
      ),
      throwsA(
        isA<EyeError>().having((EyeError e) => e.code, 'code', 'no_satellite'),
      ),
    );
  });

  test('SNO-F-EYE-04: спутник не закрылся сам — снят', () async {
    final _Stubborn stubborn = _Stubborn();
    final EyeLink link = await EyeLink.start(() async => stubborn, qpc: qpc);
    await link.close();
    expect(stubborn.inputClosed, isTrue);
    expect(stubborn.killed, isTrue);
  }, timeout: const Timeout(Duration(seconds: 10)));
}

/// Спутник, который на закрытие stdin не выходит.
class _Stubborn implements EyeProcess {
  final StreamController<String> _out = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  bool inputClosed = false;
  bool killed = false;

  @override
  Stream<String> get lines => _out.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(String line) {}

  @override
  Future<void> closeInput() async => inputClosed = true;

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) {
      _exit.complete(-1);
    }
    unawaited(_out.close());
  }
}
