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
  String toString() => 'EyeError($code${command == null ? '' : ' $command'}: '
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
  return <EyeCamera>[
    for (final Object? item in raw) ?EyeCamera.fromJson(item),
  ];
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
    return EyeCheck(
      verdict: verdictOf(all),
      rows: all,
      measures: measures,
    );
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
    final List<int> bytes;
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

  /// Кадр в JPEG.
  final List<int> jpeg;

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
