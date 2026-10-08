/// Обмен приложения со спутником взгляда — сторона приложения, чистая
/// часть (SNO-ALG-EYE-03, SNO-F-EYE-04).
///
/// Спутник — программа на Python рядом с приложением (`eye/`); с ним
/// приложение говорит строками JSON через stdin и stdout. Здесь — что в
/// этих строках: разбор ответов, виды ошибок и слова для них. Ни
/// процессов, ни часов, ни виджетов: правило проверяется на строках,
/// написанных руками, и на тех, что отвечает настоящий спутник.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Версия обмена. Меняется только вместе со спутником
/// (`eye/sno_eye/__init__.py`, `PROTOCOL`): в ответе `hello` чужая
/// версия — отказ.
const int kEyeProtocol = 1;

/// Строка команды спутнику: JSON без переводов строк, с версией обмена.
String encodeEyeCommand(String name, [Map<String, Object?>? fields]) {
  return jsonEncode(<String, Object?>{
    'cmd': name,
    'v': kEyeProtocol,
    ...?fields,
  });
}

/// Строка спутника, разобранная: объект JSON или `null`, если это не он.
///
/// Не-JSON — мусор в канале: спутник пишет в stdout только JSON, а
/// всё остальное у него идёт в stderr. Три строки мусора подряд — повод
/// перезапустить спутник (SNO-ALG-EYE-03, краевые случаи).
Map<String, Object?>? decodeEyeLine(String line) {
  final String text = line.trim();
  if (text.isEmpty) {
    return null;
  }
  try {
    final Object? raw = jsonDecode(text);
    return raw is Map<String, Object?> ? raw : null;
  } on FormatException {
    return null;
  }
}

/// Какой команде отвечает строка; `null` — это не ответ.
///
/// Ответ на `close` называется `closed`: так его назвал спутник.
String? replyOf(Map<String, Object?> message) {
  final Object? reply = message['reply'];
  if (reply is! String) {
    return null;
  }
  return reply == 'closed' ? 'close' : reply;
}

/// Ошибка спутника или связи с ним.
///
/// [code] — из закрытого перечня спутника (`camera_denied`,
/// `camera_busy`, `camera_lost`, `no_camera`, `no_face`,
/// `model_missing`, `disk`, `bad_command`, `already_running`) или
/// приложения: `timeout` — ответа не дождались, `exit` — спутник
/// вышел, `version` — спутник другой версии, `start` — спутник не
/// запустился, `no_satellite` — папки `eye/` нет.
class EyeError implements Exception {
  /// Создаёт ошибку.
  const EyeError(this.code, this.text, {this.command});

  /// Ошибка из строки спутника `{error, text, cmd}`.
  factory EyeError.fromMessage(Map<String, Object?> message) {
    final Object? code = message['error'];
    final Object? text = message['text'];
    final Object? command = message['cmd'];
    return EyeError(
      code is String ? code : 'bad_command',
      text is String ? text : '',
      command: command is String ? command : null,
    );
  }

  /// Вид ошибки.
  final String code;

  /// Что сказал спутник словами; может быть пустым.
  final String text;

  /// На какую команду ответ; `null` — ошибка не о команде.
  final String? command;

  @override
  String toString() =>
      'EyeError($code${command == null ? '' : ' $command'}: '
      '$text)';
}

/// Почему айтрекера нет — словами для экспериментатора.
///
/// Слова о камере — те же, что у самопроверки спутника
/// (`eye/sno_eye/selfcheck.py`, `CAMERA_TEXT`): экспериментатор не
/// должен видеть одну причину двумя разными фразами.
String describeEyeError(EyeError error) {
  final String said = error.text.trim();
  return switch (error.code) {
    'no_satellite' =>
      'Айтрекер не запустился: рядом с приложением нет папки eye',
    'start' => 'Айтрекер не запустился${said.isEmpty ? '' : ': $said'}',
    'version' => 'Айтрекер не запустился: спутник другой версии',
    'model_missing' =>
      'Айтрекер не запустился: модель лица не загрузилась'
          '${said.isEmpty ? '' : ' ($said)'}',
    'already_running' =>
      'Айтрекер занят: его держит другое окно проверки камеры',
    'timeout' => 'Айтрекер не ответил вовремя',
    'exit' => 'Айтрекер закрылся',
    'camera_denied' =>
      'Камера запрещена в параметрах Windows — разрешите классическим '
          'приложениям доступ к камере',
    'camera_busy' =>
      'Камера занята другой программой — закройте Teams, Zoom, браузер',
    'no_camera' => 'Камера не найдена',
    'camera_lost' => 'Камера отключилась',
    'disk' => 'Не хватает места на диске для взгляда',
    _ => said.isEmpty ? 'Айтрекер ответил ошибкой «${error.code}»' : said,
  };
}

/// Ответ `hello`: кто на том конце.
class EyeHello {
  /// Создаёт ответ.
  const EyeHello({
    required this.protocol,
    required this.version,
    required this.mediapipe,
    required this.modelSha256,
  });

  /// Ответ из строки спутника; чужая версия обмена — [EyeError]
  /// `version`.
  factory EyeHello.fromMessage(Map<String, Object?> message) {
    final Object? v = message['v'];
    if (v != kEyeProtocol) {
      throw EyeError(
        'version',
        'Спутник говорит на версии обмена $v, приложение — на '
            '$kEyeProtocol',
        command: 'hello',
      );
    }
    String text(String key) {
      final Object? value = message[key];
      return value is String ? value : '';
    }

    return EyeHello(
      protocol: kEyeProtocol,
      version: text('version'),
      mediapipe: text('mediapipe'),
      modelSha256: text('model_sha256'),
    );
  }

  /// Версия обмена.
  final int protocol;

  /// Версия спутника.
  final String version;

  /// Версия MediaPipe.
  final String mediapipe;

  /// Сумма модели лица.
  final String modelSha256;

  /// Для журнала и сведений записи.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': protocol,
    'version': version,
    'mediapipe': mediapipe,
    'model_sha256': modelSha256,
  };
}

/// Камера, как её назвал спутник.
class EyeCamera {
  /// Создаёт камеру.
  const EyeCamera({required this.index, required this.name, this.path});

  /// Камера из объекта спутника; `null` — объект не о камере.
  static EyeCamera? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? index = raw['index'];
    final Object? name = raw['name'];
    final Object? path = raw['path'];
    if (index is! int) {
      return null;
    }
    return EyeCamera(
      index: index,
      name: name is String && name.isNotEmpty ? name : 'Камера ${index + 1}',
      path: path is String && path.isNotEmpty ? path : null,
    );
  }

  /// Номер камеры в системе.
  final int index;

  /// Имя камеры.
  final String name;

  /// Путь устройства: по нему камера узнаётся, даже если номера
  /// поменялись после того, как камеру переткнули.
  final String? path;

  /// Как камера называется в команде спутнику и в месте записи.
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'name': name,
    if (path != null) 'path': path,
  };

  @override
  bool operator ==(Object other) {
    return other is EyeCamera &&
        other.index == index &&
        other.name == name &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(index, name, path);
}

/// Список камер из ответа `cameras`.
List<EyeCamera> camerasOf(Map<String, Object?> message) {
  final Object? raw = message['cameras'];
  if (raw is! List<Object?>) {
    return const <EyeCamera>[];
  }
  return <EyeCamera>[for (final Object? item in raw) ?EyeCamera.fromJson(item)];
}

/// Итог проверки: годится, с оговоркой, не годится.
enum EyeVerdict {
  /// Годится.
  good('good', 'годится'),

  /// Годится с оговоркой.
  warn('warn', 'годится с оговоркой'),

  /// Не годится.
  fail('fail', 'не годится');

  const EyeVerdict(this.wire, this.words);

  /// Как итог назван в обмене.
  final String wire;

  /// Итог словами.
  final String words;

  /// Итог по имени; незнакомое имя — «не годится».
  static EyeVerdict named(Object? wire) {
    for (final EyeVerdict verdict in values) {
      if (verdict.wire == wire) {
        return verdict;
      }
    }
    return fail;
  }

  /// Худший из двух итогов.
  EyeVerdict worse(EyeVerdict other) => index >= other.index ? this : other;
}

/// Строка самопроверки: что проверено, итог, значение и слова.
class EyeCheckRow {
  /// Создаёт строку.
  const EyeCheckRow({
    required this.id,
    required this.verdict,
    required this.text,
    this.value,
  });

  /// Строка из объекта спутника; `null` — объект не о проверке.
  static EyeCheckRow? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? text = raw['text'];
    if (id is! String) {
      return null;
    }
    return EyeCheckRow(
      id: id,
      verdict: EyeVerdict.named(raw['verdict']),
      text: text is String ? text : id,
      value: raw['value'],
    );
  }

  /// Что проверено: `camera`, `fps`, `face`, `iris`, `light`, …,
  /// `window` — окно приложения (его проверяет приложение, а не
  /// спутник).
  final String id;

  /// Итог строки.
  final EyeVerdict verdict;

  /// Строка словами.
  final String text;

  /// Измеренное значение — как его прислал спутник.
  final Object? value;

  /// Как строка записана в месте записи.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'verdict': verdict.wire,
    'text': text,
    'value': value,
  };
}

/// Проверки, без которых взгляда не будет: «не годится» в любой из них
/// — общий итог «не годится» (как `CRITICAL` в `selfcheck.py`; строка
/// «окно» — приложения).
const Set<String> kCriticalChecks = <String>{
  'satellite',
  'camera',
  'mode',
  'fps',
  'face',
  'iris',
  'window',
};

/// Итог самопроверки места (SNO-ALG-EYE-04).
class EyeCheck {
  /// Создаёт итог.
  const EyeCheck({
    required this.verdict,
    required this.rows,
    this.measures = const <String, Object?>{},
  });

  /// Итог из ответа `selfcheck`.
  factory EyeCheck.fromMessage(Map<String, Object?> message) {
    final Object? rows = message['checks'];
    final Object? measures = message['measures'];
    return EyeCheck(
      verdict: EyeVerdict.named(message['verdict']),
      rows: <EyeCheckRow>[
        if (rows is List<Object?>)
          for (final Object? row in rows) ?EyeCheckRow.fromJson(row),
      ],
      measures: measures is Map<String, Object?>
          ? measures
          : const <String, Object?>{},
    );
  }

  /// Самопроверка, которой не было: спутник не запустился.
  factory EyeCheck.unavailable(String text) {
    return EyeCheck(
      verdict: EyeVerdict.fail,
      rows: <EyeCheckRow>[
        EyeCheckRow(id: 'satellite', verdict: EyeVerdict.fail, text: text),
      ],
    );
  }

  /// Общий итог.
  final EyeVerdict verdict;

  /// Строки по порядку.
  final List<EyeCheckRow> rows;

  /// Сырые замеры спутника: режим камеры, частота и прочее.
  final Map<String, Object?> measures;

  /// Тот же итог со строкой [row] в конце — и общий итог пересчитан
  /// тем же правилом, что у спутника.
  EyeCheck withRow(EyeCheckRow row) {
    final List<EyeCheckRow> all = <EyeCheckRow>[
      for (final EyeCheckRow r in rows)
        if (r.id != row.id) r,
      row,
    ];
    return EyeCheck(verdict: verdictOf(all), rows: all, measures: measures);
  }

  /// Общий итог строк [rows]: «не годится» в важной строке — «не
  /// годится»; что-то не «годится» — «с оговоркой»; иначе «годится».
  static EyeVerdict verdictOf(List<EyeCheckRow> rows) {
    if (rows.any(
      (EyeCheckRow r) =>
          r.verdict == EyeVerdict.fail && kCriticalChecks.contains(r.id),
    )) {
      return EyeVerdict.fail;
    }
    if (rows.any((EyeCheckRow r) => r.verdict != EyeVerdict.good)) {
      return EyeVerdict.warn;
    }
    return EyeVerdict.good;
  }

  /// Строка с идентификатором [id]; `null` — её нет.
  EyeCheckRow? row(String id) {
    for (final EyeCheckRow r in rows) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  /// Режим камеры, на котором шёл замер: `[ширина, высота]`; `null` —
  /// камера не открылась.
  List<int>? get mode {
    final Object? w = measures['width'];
    final Object? h = measures['height'];
    return w is int && h is int && w > 0 && h > 0 ? <int>[w, h] : null;
  }

  /// Частота кадров с распознаванием; `null` — не намерили.
  double? get fps {
    final Object? value = measures['fps'];
    return value is num ? value.toDouble() : null;
  }
}

/// Маленький кадр камеры с рамкой лица — для экрана «Место записи».
class EyePreview {
  /// Создаёт кадр.
  const EyePreview({
    required this.jpeg,
    required this.width,
    required this.height,
    this.face,
  });

  /// Кадр из строки `{progress: preview, jpeg, w, h, face}`; `null` —
  /// строка не о кадре или кадр не читается.
  static EyePreview? fromMessage(Map<String, Object?> message) {
    if (message['progress'] != 'preview') {
      return null;
    }
    final Object? jpeg = message['jpeg'];
    final Object? w = message['w'];
    final Object? h = message['h'];
    final Object? face = message['face'];
    if (jpeg is! String || w is! int || h is! int || w <= 0 || h <= 0) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(jpeg);
    } on FormatException {
      return null;
    }
    List<double>? box;
    if (face is List<Object?> && face.length == 4) {
      final List<double> numbers = <double>[
        for (final Object? v in face)
          if (v is num) v.toDouble(),
      ];
      if (numbers.length == 4) {
        box = numbers;
      }
    }
    return EyePreview(jpeg: bytes, width: w, height: h, face: box);
  }

  /// Кадр в JPEG — один и тот же список байт на все перерисовки, чтобы
  /// картинка не распаковывалась заново при каждой.
  final Uint8List jpeg;

  /// Ширина кадра в точках.
  final int width;

  /// Высота кадра в точках.
  final int height;

  /// Рамка лица `[x0, y0, x1, y1]` в долях кадра; `null` — лица нет.
  final List<double>? face;
}

/// Сердцебиение спутника: раз в секунду.
class EyeHeartbeat {
  /// Создаёт сердцебиение.
  const EyeHeartbeat({required this.n, this.cpu, this.memoryMb});

  /// Сердцебиение из строки `{hb, …}`; `null` — строка не о нём.
  static EyeHeartbeat? fromMessage(Map<String, Object?> message) {
    final Object? n = message['hb'];
    if (n is! int) {
      return null;
    }
    final Object? cpu = message['cpu'];
    final Object? mem = message['mem'];
    return EyeHeartbeat(
      n: n,
      cpu: cpu is num ? cpu.toDouble() : null,
      memoryMb: mem is num ? mem.toDouble() : null,
    );
  }

  /// Номер сердцебиения с запуска спутника.
  final int n;

  /// Загрузка процессора спутником, процентов.
  final double? cpu;

  /// Память спутника, МБ.
  final double? memoryMb;
}

// --- калибровка (шаг 28, SNO-ALG-EYE-02) ---------------------------------

double? _num(Object? value) => value is num ? value.toDouble() : null;

List<String> _ids(Object? raw) => <String>[
  if (raw is List<Object?>)
    for (final Object? v in raw)
      if (v is String) v,
];

/// Окно приложения для спутника: размер в логических пикселях и в
/// миллиметрах. По нему спутник переводит точки в градусы.
class EyeScreen {
  /// Создаёт окно.
  const EyeScreen({
    required this.width,
    required this.height,
    required this.widthMm,
    required this.heightMm,
  });

  /// Ширина окна, логических пикселей.
  final double width;

  /// Высота окна, логических пикселей.
  final double height;

  /// Ширина окна, мм.
  final double widthMm;

  /// Высота окна, мм.
  final double heightMm;

  /// Поле `screen` команды `open`.
  Map<String, Object?> toJson() => <String, Object?>{
    'w': width,
    'h': height,
    'w_mm': widthMm,
    'h_mm': heightMm,
  };
}

/// Ответ `samples`: сколько годных кадров у каждой точки калибровки.
class EyeSamples {
  /// Создаёт ответ.
  const EyeSamples({required this.counts, required this.short, this.face});

  /// Ответ из строки спутника.
  factory EyeSamples.fromMessage(Map<String, Object?> message) {
    final Object? counts = message['counts'];
    return EyeSamples(
      counts: <String, int>{
        if (counts is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in counts.entries)
            if (e.value is int) e.key: e.value! as int,
      },
      short: _ids(message['short']),
      face: _num(message['face']),
    );
  }

  /// Годных кадров по точкам.
  final Map<String, int> counts;

  /// Точки, которым не хватило кадров: их показывают ещё раз в конце.
  final List<String> short;

  /// Доля кадров с лицом; `null` — кадров не было.
  final double? face;
}

/// Ответ `fit`: модель попытки.
class EyeFit {
  /// Создаёт ответ.
  const EyeFit({
    required this.model,
    required this.cvDeg,
    required this.points,
    this.cvCm,
    this.latencyMs,
    this.excluded = const <String>[],
    this.headModel,
    this.headPhase,
    this.raw = const <String, Object?>{},
  });

  /// Ответ из строки спутника.
  factory EyeFit.fromMessage(Map<String, Object?> message) {
    final Object? points = message['points'];
    final Object? head = message['head'];
    final Object? model = message['head_model'];
    return EyeFit(
      model: message['model'] is String ? message['model']! as String : '',
      cvDeg: _num(message['cv_deg']) ?? double.nan,
      cvCm: _num(message['cv_cm']),
      latencyMs: _num(message['latency_ms']),
      points: points is int ? points : 0,
      excluded: _ids(message['excluded']),
      headModel: model is String ? model : null,
      headPhase: head is Map<String, Object?> ? EyeHeadPhase.fromJson(head) : null,
      raw: message,
    );
  }

  /// Какая модель выбрана: `ridge` или `krr`.
  final String model;

  /// Ошибка «без одной точки», градусов.
  final double cvDeg;

  /// Та же ошибка в сантиметрах на экране.
  final double? cvCm;

  /// Задержка камеры, мс; `null` — слежения не было.
  final double? latencyMs;

  /// Сколько точек вошло в модель.
  final int points;

  /// Точки, исключённые за нехваткой кадров.
  final List<String> excluded;

  /// Каким способом поправки на голову идут живая точка и итог
  /// (BUG-60): `learned`, `geometry` или `phase`; `null` — спутник
  /// прежней версии.
  final String? headModel;

  /// Как прошла фаза движения головы; `null` — спутник прежней версии.
  final EyeHeadPhase? headPhase;

  /// Ответ как есть — для файлов и журнала.
  final Map<String, Object?> raw;
}

/// Фаза движения головы в итоге `fit` (BUG-60): сколько кадров, на
/// сколько ходила голова и выучен ли по ней остаток поправки.
class EyeHeadPhase {
  /// Создаёт сведения.
  const EyeHeadPhase({
    required this.frames,
    required this.moved,
    this.turnDeg,
    this.tiltDeg,
  });

  /// Сведения из поля `head`.
  factory EyeHeadPhase.fromJson(Map<String, Object?> json) {
    final Object? frames = json['frames'];
    return EyeHeadPhase(
      frames: frames is int ? frames : 0,
      moved: json['moved'] == true,
      turnDeg: _num(json['turn_deg']),
      tiltDeg: _num(json['tilt_deg']),
    );
  }

  /// Кадров с лицом в фазе.
  final int frames;

  /// Ходила ли голова настолько, чтобы выучить остаток.
  final bool moved;

  /// Размах поворота влево-вправо, градусов; `null` — кадров не было.
  final double? turnDeg;

  /// Размах наклона вверх-вниз, градусов.
  final double? tiltDeg;
}

/// Где была голова на проверке против калибровки (BUG-60).
class EyeHeadMove {
  /// Создаёт сведения.
  const EyeHeadMove({
    this.turnDeg = 0,
    this.tiltDeg = 0,
    this.rollDeg = 0,
    this.dxMm = 0,
    this.dyMm = 0,
    this.dzPct = 0,
  });

  /// Сведения из поля `head`.
  factory EyeHeadMove.fromJson(Map<String, Object?> json) => EyeHeadMove(
    turnDeg: _num(json['turn_deg']) ?? 0,
    tiltDeg: _num(json['tilt_deg']) ?? 0,
    rollDeg: _num(json['roll_deg']) ?? 0,
    dxMm: _num(json['dx_mm']) ?? 0,
    dyMm: _num(json['dy_mm']) ?? 0,
    dzPct: _num(json['dz_pct']) ?? 0,
  );

  /// Поворот к правому краю экрана, градусов.
  final double turnDeg;

  /// Наклон вниз, градусов.
  final double tiltDeg;

  /// Наклон к правому плечу, градусов.
  final double rollDeg;

  /// Сдвиг вправо, мм.
  final double dxMm;

  /// Сдвиг вниз, мм.
  final double dyMm;

  /// Расстояние до экрана, проценты: минус — ближе.
  final double dzPct;
}

/// Итог проверки точности без новой калибровки — ответ `checked`
/// (BUG-60, SNO-F-EYE-03).
class EyeAccuracy {
  /// Создаёт итог.
  const EyeAccuracy({
    required this.n,
    this.accuracyDeg,
    this.accuracyCm,
    this.worstDeg,
    this.startDeg,
    this.headModel,
    this.variants = const <String, double?>{},
    this.head,
    this.raw = const <String, Object?>{},
  });

  /// Итог из строки спутника.
  factory EyeAccuracy.fromMessage(Map<String, Object?> message) {
    final Object? n = message['n'];
    final Object? variants = message['variants'];
    final Object? head = message['head'];
    final Object? model = message['head_model'];
    return EyeAccuracy(
      n: n is int ? n : 0,
      accuracyDeg: _num(message['accuracy_deg']),
      accuracyCm: _num(message['accuracy_cm']),
      worstDeg: _num(message['worst_deg']),
      startDeg: _num(message['start_deg']),
      headModel: model is String ? model : null,
      variants: <String, double?>{
        if (variants is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in variants.entries)
            if (e.value is Map<String, Object?>)
              e.key: _num((e.value! as Map<String, Object?>)['accuracy_deg']),
      },
      head: head is Map<String, Object?> ? EyeHeadMove.fromJson(head) : null,
      raw: message,
    );
  }

  /// Номер проверки.
  final int n;

  /// Точность главным способом, градусов; `null` — годных точек нет.
  final double? accuracyDeg;

  /// Она же в сантиметрах на экране.
  final double? accuracyCm;

  /// Худшая точка, градусов.
  final double? worstDeg;

  /// Точность проверки сразу после калибровки; `null` — её не было.
  final double? startDeg;

  /// Главный способ поправки на голову.
  final String? headModel;

  /// Точность каждого способа: `learned`, `geometry`, `phase`.
  final Map<String, double?> variants;

  /// Где была голова против калибровки.
  final EyeHeadMove? head;

  /// Ответ как есть — для файлов.
  final Map<String, Object?> raw;
}

/// Почему калибровка не принята.
enum EyeRejectReason {
  /// Средняя точность хуже порога.
  accuracy('accuracy'),

  /// Одна из точек хуже порога худшей.
  worst('worst'),

  /// Годных точек проверки слишком мало.
  fewPoints('few_points');

  const EyeRejectReason(this.wire);

  /// Имя в обмене.
  final String wire;

  /// Причина по имени; `null` — принято или имя незнакомо.
  static EyeRejectReason? named(Object? wire) {
    for (final EyeRejectReason r in values) {
      if (r.wire == wire) {
        return r;
      }
    }
    return null;
  }
}

/// Ответ `validate`: проверка точности и приём.
class EyeValidation {
  /// Создаёт ответ.
  const EyeValidation({
    required this.accepted,
    this.accuracyDeg,
    this.accuracyCm,
    this.precisionDeg,
    this.worstDeg,
    this.worstId,
    this.reason,
    this.acceptDeg = 2.5,
    this.worstMaxDeg = 5,
    this.excluded = const <String>[],
    this.raw = const <String, Object?>{},
  });

  /// Ответ из строки спутника.
  factory EyeValidation.fromMessage(Map<String, Object?> message) {
    final Object? t = message['thresholds'];
    final Map<String, Object?> thresholds = t is Map<String, Object?>
        ? t
        : const <String, Object?>{};
    final Object? worstId = message['worst_id'];
    return EyeValidation(
      accepted: message['accepted'] == true,
      accuracyDeg: _num(message['accuracy_deg']),
      accuracyCm: _num(message['accuracy_cm']),
      precisionDeg: _num(message['precision_deg']),
      worstDeg: _num(message['worst_deg']),
      worstId: worstId is String ? worstId : null,
      reason: EyeRejectReason.named(message['reason']),
      acceptDeg: _num(thresholds['accept_deg']) ?? 2.5,
      worstMaxDeg: _num(thresholds['worst_deg']) ?? 5,
      excluded: _ids(message['excluded']),
      raw: message,
    );
  }

  /// Принята ли калибровка.
  final bool accepted;

  /// Точность — средний угол, градусов; `null` — годных точек нет.
  final double? accuracyDeg;

  /// Точность в сантиметрах на экране.
  final double? accuracyCm;

  /// Прецизионность — RMS угла между соседними выборками, градусов.
  final double? precisionDeg;

  /// Худшая точка, градусов.
  final double? worstDeg;

  /// Какая точка худшая.
  final String? worstId;

  /// Почему не принята; `null` — принята.
  final EyeRejectReason? reason;

  /// Порог приёма, градусов.
  final double acceptDeg;

  /// Порог худшей точки, градусов.
  final double worstMaxDeg;

  /// Точки проверки без годных кадров.
  final List<String> excluded;

  /// Ответ как есть — для файлов и журнала.
  final Map<String, Object?> raw;
}

/// Строка живой точки `{g, s, ok, t}`: оценка взгляда на кадре.
class EyeGaze {
  /// Создаёт точку.
  const EyeGaze({required this.ok, required this.qpcUs, this.raw, this.smooth});

  /// Точка из строки спутника; `null` — строка не о ней.
  static EyeGaze? fromMessage(Map<String, Object?> message) {
    if (!message.containsKey('g') || message['t'] is! int) {
      return null;
    }
    (double, double)? pair(Object? v) {
      if (v is List<Object?> && v.length == 2 && v[0] is num && v[1] is num) {
        return ((v[0]! as num).toDouble(), (v[1]! as num).toDouble());
      }
      return null;
    }

    final (double, double)? g = pair(message['g']);
    return EyeGaze(
      ok: message['ok'] == true && g != null,
      qpcUs: message['t']! as int,
      raw: g,
      smooth: pair(message['s']) ?? g,
    );
  }

  /// Годен ли кадр: лицо есть, голова не отвёрнута, не моргание.
  final bool ok;

  /// QPC кадра, мкс.
  final int qpcUs;

  /// Оценка взгляда в логических пикселях окна; `null` — кадр негоден.
  final (double, double)? raw;

  /// Она же, сглаженная для глаза.
  final (double, double)? smooth;
}
