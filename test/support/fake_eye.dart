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
import 'package:memoria/sno/eye/eye_tracker.dart';
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
    this.preview = false,
    this.stages = const <String>['warmup', 'measure'],
    this.samplesReply,
    this.fitError,
    List<Map<String, Object?>>? validateReplies,
  }) : validateReplies = validateReplies ?? <Map<String, Object?>>[];

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

  /// Присылать ли кадр камеры во время самопроверки.
  final bool preview;

  /// Этапы хода самопроверки, которые спутник пришлёт перед итогом.
  final List<String> stages;

  /// Ответ на `samples`; `null` — у всех точек кадров хватает.
  Map<String, Object?>? samplesReply;

  /// Ошибка на `fit` (например, `no_face`); `null` — модель есть.
  String? fitError;

  /// Ответы на `validate` по порядку попыток; кончились — «принято».
  final List<Map<String, Object?>> validateReplies;

  /// Включена ли живая точка.
  bool liveOn = false;

  /// Открыта ли камера (`open` … `close`).
  bool cameraOpen = false;

  /// Есть ли у открытой камеры размеры экрана: без них, как настоящий
  /// спутник, калибровку он не начинает.
  bool _screenKnown = false;

  /// Есть ли модель: живая точка, как у настоящего спутника, — только
  /// после `fit`.
  bool _fitted = false;

  /// Номер текущей попытки калибровки.
  Object? _attempt;

  /// Команды `target` по порядку.
  List<Map<String, Object?>> get targets => <Map<String, Object?>>[
    for (final Map<String, Object?> c in commands)
      if (c['cmd'] == 'target') c,
  ];

  /// Имена точек по порядку показа (без `off`).
  List<Object?> get targetIds => <Object?>[
    for (final Map<String, Object?> t in targets)
      if (t['phase'] != 'off') t['id'],
  ];

  /// Строка живой точки: взгляд в точке (x, y) окна. Кадр без взгляда
  /// ([ok] — `false`) несёт точку, которую спутник держит, если [held].
  void gaze(double x, double y, {int? t, bool ok = true, bool held = false}) {
    emit(<String, Object?>{
      'g': ok ? <double>[x, y] : null,
      if (ok || held) 's': <double>[x, y],
      'ok': ok,
      't': t ?? clock.nowUs(),
    });
  }

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
            'version': '0.2.0',
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
        for (final String stage in stages) {
          emit(<String, Object?>{'progress': 'selfcheck', 'stage': stage});
        }
        if (preview) {
          emit(<String, Object?>{
            'progress': 'preview',
            // Не JPEG: картинка не распакуется, и экран покажет чёрный
            // кадр — для проверки подписи этого хватает.
            'jpeg': 'AAECAw==',
            'w': 320,
            'h': 180,
            'face': <double>[0.3, 0.2, 0.7, 0.8],
          });
        }
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
      case 'open':
        if (cameraOpen) {
          emit(<String, Object?>{
            'error': 'bad_command',
            'text': 'Запись уже идёт',
            'cmd': 'open',
          });
          return;
        }
        cameraOpen = true;
        final Object? screen = command['screen'];
        _screenKnown =
            screen is Map<String, Object?> &&
            <String>[
              'w',
              'h',
              'w_mm',
              'h_mm',
            ].every((String k) => screen[k] is num && (screen[k]! as num) > 0);
        _fitted = false;
        emit(<String, Object?>{
          'reply': 'open',
          'frame': <int>[1920, 1080],
        });
      case 'close':
        cameraOpen = false;
        liveOn = false;
        _fitted = false;
        emit(<String, Object?>{
          'reply': 'closed',
          'summary': <String, Object?>{'frames': 1800},
        });
      case 'calibrate':
        if (!cameraOpen || !_screenKnown) {
          emit(<String, Object?>{
            'error': 'bad_command',
            'text': cameraOpen
                ? 'Нет размеров экрана: их называет команда open'
                : 'Калибровке нужна открытая камера: сначала open',
            'cmd': 'calibrate',
          });
          return;
        }
        _attempt = command['attempt'];
        emit(<String, Object?>{
          'reply': 'calibrate',
          'attempt': command['attempt'],
          'kind': command['kind'],
        });
      case 'target':
        break;
      case 'samples':
        emit(<String, Object?>{
          'reply': 'samples',
          ...(samplesReply ??
              <String, Object?>{
                'phase': 'calib',
                'counts': <String, Object?>{},
                'short': <Object?>[],
                'face': 1.0,
              }),
        });
      case 'fit':
        final String? error = fitError;
        if (error != null) {
          emit(<String, Object?>{
            'error': error,
            'text': 'Камера не видит лица',
            'cmd': 'fit',
          });
          return;
        }
        _fitted = true;
        emit(<String, Object?>{
          'reply': 'fit',
          'attempt': _attempt,
          'model': 'ridge',
          'cv_deg': 1.2,
          'cv_cm': 1.3,
          'latency_ms': 70.0,
          'points': 13,
          'excluded': <Object?>[],
        });
      case 'validate':
        emit(<String, Object?>{
          'reply': 'validate',
          'attempt': _attempt,
          ...(validateReplies.isEmpty
              ? kAcceptedValidation
              : validateReplies.removeAt(0)),
        });
      case 'live':
        if (command['on'] == true && !_fitted) {
          emit(<String, Object?>{
            'error': 'bad_command',
            'text': 'Живой точке нужна модель: сначала fit',
            'cmd': 'live',
          });
          return;
        }
        liveOn = command['on'] == true;
        emit(<String, Object?>{'reply': 'live', 'on': liveOn});
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

/// Проверка, которую подставной спутник отвечает по умолчанию: принято.
const Map<String, Object?> kAcceptedValidation = <String, Object?>{
  'accuracy_deg': 2.2,
  'accuracy_cm': 2.3,
  'precision_deg': 0.5,
  'worst_deg': 4.1,
  'worst_id': 'v4',
  'accepted': true,
  'reason': null,
  'points': <Object?>[],
  'excluded': <Object?>[],
  'thresholds': <String, Object?>{
    'accept_deg': 2.5,
    'worst_deg': 5.0,
    'min_points': 6,
  },
};

/// Проверка «не принято»: точность 3,1°.
const Map<String, Object?> kRejectedValidation = <String, Object?>{
  'accuracy_deg': 3.1,
  'accuracy_cm': 3.3,
  'precision_deg': 0.6,
  'worst_deg': 4.6,
  'worst_id': 'v2',
  'accepted': false,
  'reason': 'accuracy',
  'points': <Object?>[],
  'excluded': <Object?>[],
  'thresholds': <String, Object?>{
    'accept_deg': 2.5,
    'worst_deg': 5.0,
    'min_points': 6,
  },
};

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

/// Файлы айтрекера в памяти: какие папки создавали и что писали.
class MemoryEyeFiles implements EyeFiles {
  /// Созданные папки по порядку.
  final List<String> folders = <String>[];

  /// Записанные файлы: путь → текст.
  final Map<String, String> written = <String, String>{};

  @override
  Future<void> createFolder(String path) async {
    folders.add(path);
  }

  @override
  Future<void> writeText(String path, String text) async {
    written[path] = text;
  }
}
