/// Подставной спутник взгляда, его запуск, часы и окно (SNO-F-EYE-04,
/// SNO-F-EYE-05, SNO-F-EYE-07).
///
/// Отвечает на команды так же, как настоящий `eye/sno_eye/protocol.py`,
/// и делает то, что ему велит тест: молчит, шлёт мусор, выходит,
/// отказывается вторым экземпляром.
library;

import 'dart:async';
import 'dart:convert';

import 'package:memoria/sno/eye/eye_process.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_window.dart';
import 'package:memoria/sno/eye/qpc_clock.dart';

/// Часы QPC в руках теста: каждое чтение сдвигает их на [step] мкс.
class FakeQpc implements QpcClock {
  /// Создаёт часы.
  FakeQpc({this.now = 1000000000, this.step = 40});

  /// Сейчас, мкс.
  int now;

  /// На сколько сдвигается каждое чтение.
  int step;

  @override
  int nowUs() {
    now += step;
    return now;
  }
}

/// Подставной спутник.
class FakeEyeProcess implements EyeProcess {
  /// Создаёт спутник. [clock] — его часы: на `sync` он отвечает их
  /// временем со сдвигом [offsetUs].
  FakeEyeProcess({
    required this.clock,
    this.offsetUs = 0,
    this.protocol = kEyeProtocol,
    this.alreadyRunning = false,
    this.helloError,
    this.check,
    this.cameraList,
    this.exitOn,
  });

  /// Часы спутника.
  final FakeQpc clock;

  /// Сдвиг часов спутника, мкс.
  final int offsetUs;

  /// Версия обмена в ответе `hello`.
  final int protocol;

  /// Отказаться вторым экземпляром.
  final bool alreadyRunning;

  /// Ошибка на `hello` (например, `model_missing`); `null` — ответить.
  final String? helloError;

  /// Ответ на `selfcheck`; `null` — «годится».
  final Map<String, Object?>? check;

  /// Камеры; `null` — одна встроенная.
  final List<Map<String, Object?>>? cameraList;

  /// Команда, на которой спутник падает с кодом 1 вместо ответа.
  final String? exitOn;

  final StreamController<String> _out = StreamController<String>();
  final Completer<int> _exit = Completer<int>();

  /// Команды, которые получил спутник, по порядку.
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];

  /// Не отвечать ни на что.
  bool mute = false;

  /// Закрыли ли stdin.
  bool inputClosed = false;

  /// Сняли ли процесс.
  bool killed = false;

  /// Имена команд по порядку.
  List<Object?> get names => <Object?>[
    for (final Map<String, Object?> c in commands) c['cmd'],
  ];

  /// Вышел ли спутник.
  bool get exited => _exit.isCompleted;

  @override
  Stream<String> get lines => _out.stream;

  @override
  Future<int> get exitCode => _exit.future;

  /// Строка от спутника.
  void emit(Map<String, Object?> message) {
    if (!exited) {
      _out.add(jsonEncode(<String, Object?>{'v': kEyeProtocol, ...message}));
    }
  }

  /// Строка мусора.
  void garbage(String line) {
    if (!exited) {
      _out.add(line);
    }
  }

  /// Сердцебиение.
  void beat(int n) => emit(<String, Object?>{'hb': n, 'cpu': 3.5, 'mem': 210});

  /// Спутник выходит сам с кодом [code].
  void exit(int code) {
    if (exited) {
      return;
    }
    _exit.complete(code);
    unawaited(_out.close());
  }

  @override
  void write(String line) {
    if (exited) {
      return;
    }
    final Map<String, Object?> command =
        jsonDecode(line) as Map<String, Object?>;
    commands.add(command);
    if (!mute) {
      scheduleMicrotask(() => _answer(command));
    }
  }

  void _answer(Map<String, Object?> command) {
    final Object? name = command['cmd'];
    if (exitOn != null && name == exitOn) {
      exit(1);
      return;
    }
    if (alreadyRunning) {
      emit(<String, Object?>{
        'error': 'already_running',
        'text': 'Спутник уже запущен',
      });
      exit(3);
      return;
    }
    switch (name) {
      case 'hello':
        final String? error = helloError;
        if (error != null) {
          emit(<String, Object?>{
            'error': error,
            'text': 'Модель лица: нет файла модели',
            'cmd': 'hello',
          });
          return;
        }
        _out.add(
          jsonEncode(<String, Object?>{
            'v': protocol,
            'reply': 'hello',
            'version': '0.1.0',
            'mediapipe': '1.1.0',
            'model_sha256': '64184e22',
          }),
        );
      case 'cameras':
        emit(<String, Object?>{
          'reply': 'cameras',
          'cameras':
              cameraList ??
              <Map<String, Object?>>[
                <String, Object?>{
                  'index': 0,
                  'name': 'Integrated Camera',
                  'path': r'\\?\usb#vid_0001',
                },
              ],
        });
      case 'selfcheck':
        emit(<String, Object?>{'progress': 'selfcheck', 'stage': 'warmup'});
        emit(<String, Object?>{'progress': 'selfcheck', 'stage': 'measure'});
        emit(<String, Object?>{
          'reply': 'selfcheck',
          ...(check ??
              <String, Object?>{
                'verdict': 'good',
                'checks': <Object?>[
                  <String, Object?>{
                    'id': 'camera',
                    'verdict': 'good',
                    'value': 'ok',
                    'text': 'Камера открылась',
                  },
                  <String, Object?>{
                    'id': 'fps',
                    'verdict': 'good',
                    'value': 29.9,
                    'text': 'Частота 29.9 к/с',
                  },
                ],
                'measures': <String, Object?>{
                  'camera': 'ok',
                  'width': 1920,
                  'height': 1080,
                  'fps': 29.9,
                },
              }),
        });
      case 'sync':
        emit(<String, Object?>{
          'reply': 'sync',
          'app_qpc_us': command['app_qpc_us'],
          'eye_qpc_us': clock.nowUs() + offsetUs,
        });
      default:
        emit(<String, Object?>{
          'error': 'bad_command',
          'text': 'неизвестная команда',
          'cmd': name,
        });
    }
  }

  @override
  Future<void> closeInput() async {
    inputClosed = true;
    exit(0);
  }

  @override
  void kill() {
    killed = true;
    exit(-1);
  }
}

/// Запуск подставных спутников: каждый запуск — новый процесс из
/// [make]; [failWith] — запуск не удаётся вовсе.
class FakeEyeLauncher {
  /// Создаёт запуск.
  FakeEyeLauncher({required this.make});

  /// Новый процесс для очередного запуска; номер — с нуля.
  final FakeEyeProcess Function(int n) make;

  /// Ошибка запуска; `null` — запуск удаётся.
  EyeError? failWith;

  /// Запущенные процессы по порядку.
  final List<FakeEyeProcess> started = <FakeEyeProcess>[];

  /// Последний запущенный.
  FakeEyeProcess get last => started.last;

  /// Запуск.
  Future<EyeProcess> launch() async {
    final EyeError? error = failWith;
    if (error != null) {
      throw error;
    }
    final FakeEyeProcess process = make(started.length);
    started.add(process);
    return process;
  }
}

/// Подставное окно: мониторы, замок и его смены.
class FakeEyeWindow implements EyeWindow {
  /// Создаёт окно с мониторами [list].
  FakeEyeWindow({List<EyeMonitor>? list})
    : list =
          list ??
          const <EyeMonitor>[
            EyeMonitor(
              id: r'\\.\DISPLAY1',
              name: 'DELL P2419H',
              widthPx: 1920,
              heightPx: 1080,
              widthMm: 527,
              heightMm: 296,
              primary: true,
              current: true,
            ),
            EyeMonitor(
              id: r'\\.\DISPLAY2',
              name: '',
              widthPx: 2560,
              heightPx: 1440,
            ),
          ];

  /// Мониторы.
  final List<EyeMonitor> list;

  /// Отказать в замке.
  bool refuse = false;

  /// На какие мониторы ставили окно, по порядку.
  final List<String> locks = <String>[];

  /// Сколько раз замок снимали.
  int unlocks = 0;

  bool _locked = false;
  final StreamController<EyeWindowLock> _changes =
      StreamController<EyeWindowLock>.broadcast();

  @override
  bool get locked => _locked;

  @override
  Stream<EyeWindowLock> get changes => _changes.stream;

  /// Монитор замка сменился.
  void change(EyeWindowLock lock) => _changes.add(lock);

  @override
  Future<List<EyeMonitor>> monitors() async => list;

  @override
  Future<EyeWindowLock?> lock(String monitor) async {
    locks.add(monitor);
    if (refuse) {
      return null;
    }
    _locked = true;
    EyeMonitor? target;
    for (final EyeMonitor m in list) {
      if (m.id == monitor) {
        target = m;
      }
    }
    final EyeMonitor shown = target ?? list.first;
    return EyeWindowLock(
      monitor: shown.id,
      name: shown.name,
      found: target != null,
      widthPx: shown.widthPx,
      heightPx: shown.heightPx,
      dpr: 1,
    );
  }

  @override
  Future<void> unlock() async {
    if (_locked) {
      unlocks++;
    }
    _locked = false;
  }

  /// Закрывает поток смен.
  Future<void> dispose() => _changes.close();
}
