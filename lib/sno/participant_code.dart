/// Код участника (SNO-ALG-CFG-03, SNO-F-CFG-05).
///
/// Каждому участнику исследования СНО2026 при начале записи нужен
/// уникальный код: он стоит в сведениях записи, участник вписывает его
/// **от руки** в бланк теста знаний, и по нему при разборе сходятся
/// запись, бланк и вторая запись того же человека. Сервера нет — код
/// рождается на устройстве; имён в данных нет.
///
/// Код — восемь цифр: семь из хеша и контрольная. Цифры, а не буквы:
/// от руки и с фотографии они читаются надёжнее («О» и «0», «З» и «3»
/// здесь не встречаются). Контрольная цифра — по алгоритму Дамма: он
/// ловит любую ошибку в одной цифре и любую перестановку двух соседних
/// — ровно то, чем ошибается почерк и переписывание.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Сколько знаков идентификатора устройства показывается.
///
/// Шести хватает, чтобы различить устройства одной серии тестов, и их
/// можно прочесть вслух; тот же код стоит в сведениях записи и в имени
/// её папки.
const int kDeviceCodeLength = 6;

/// Код устройства: первые знаки его идентификатора узла.
String deviceCodeOf(String nodeId) {
  return nodeId.length > kDeviceCodeLength
      ? nodeId.substring(0, kDeviceCodeLength)
      : nodeId;
}

/// Версия правила, по которому код выводится из входов.
///
/// Записывается рядом с кодом: код воспроизводим и проверяем.
const String kCodeGenerator = 'sno-code/1';

/// Сколько цифр в коде без контрольной.
const int kCodeBaseLength = 7;

/// Сколько цифр в коде вместе с контрольной.
const int kCodeLength = kCodeBaseLength + 1;

/// Таблица квазигруппы Дамма порядка 10.
///
/// Строка — промежуточная цифра, столбец — очередная цифра кода. Число
/// с верной контрольной цифрой приводит к нулю.
const List<List<int>> _damm = <List<int>>[
  <int>[0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
  <int>[7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
  <int>[4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
  <int>[1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
  <int>[6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
  <int>[3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
  <int>[5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
  <int>[8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
  <int>[9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
  <int>[2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
];

const int _zero = 0x30;

/// Только ли из цифр состоит [text].
bool _allDigits(String text) {
  for (final int unit in text.codeUnits) {
    if (unit < _zero || unit > _zero + 9) {
      return false;
    }
  }
  return true;
}

/// Контрольная цифра Дамма для строки цифр [digits].
///
/// Бросает [ArgumentError], если в строке есть не цифра: проверять
/// нецифровой ввод — дело [isValidParticipantCode].
int dammCheckDigit(String digits) {
  if (!_allDigits(digits)) {
    throw ArgumentError.value(digits, 'digits', 'ожидаются только цифры');
  }
  int interim = 0;
  for (final int unit in digits.codeUnits) {
    interim = _damm[interim][unit - _zero];
  }
  return interim;
}

/// Цифры кода из набранного: без дефиса, пробелов и прочего.
///
/// Код показывается группами `6795-4332`, и набирают его так же.
String normalizeParticipantCode(String input) {
  final StringBuffer digits = StringBuffer();
  for (final int unit in input.codeUnits) {
    if (unit >= _zero && unit <= _zero + 9) {
      digits.writeCharCode(unit);
    }
  }
  return digits.toString();
}

/// Верен ли код [code]: восемь цифр, первая не ноль, контрольная
/// сходится.
bool isValidParticipantCode(String code) {
  if (code.length != kCodeLength || !_allDigits(code)) {
    return false;
  }
  if (code.codeUnitAt(0) == _zero) {
    return false;
  }
  return dammCheckDigit(code) == 0;
}

/// Код группами для показа и бланка: `6795-4332`.
String formatParticipantCode(String code) {
  if (code.length != kCodeLength) {
    return code;
  }
  return '${code.substring(0, 4)}-${code.substring(4)}';
}

/// Код участника и то, откуда он взялся.
class ParticipantCode {
  /// Создаёт код.
  const ParticipantCode({
    required this.code,
    required this.generated,
    required this.generatedAt,
    this.attempt = 0,
  });

  /// Читает запись [toJson]; `null` — запись не читается.
  static ParticipantCode? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? code = raw['code'];
    final Object? generated = raw['generated'];
    final Object? at = raw['generated_at'];
    final Object? attempt = raw['attempt'];
    if (code is! String || generated is! bool || at is! String) {
      return null;
    }
    final DateTime? moment = DateTime.tryParse(at);
    if (moment == null || !isValidParticipantCode(code)) {
      return null;
    }
    return ParticipantCode(
      code: code,
      generated: generated,
      generatedAt: moment,
      attempt: attempt is int ? attempt : 0,
    );
  }

  /// Восемь цифр слитно: `67954332`.
  final String code;

  /// Выдан ли код этим устройством; `false` — его ввели: участник
  /// пришёл повторно или уже записывался на другом устройстве.
  final bool generated;

  /// Когда код выдан или введён.
  final DateTime generatedAt;

  /// С какой попытки код вышел неповторяющимся (у выданного).
  final int attempt;

  /// Семь цифр без контрольной — по ним код узнаётся среди выданных.
  String get base => code.substring(0, kCodeBaseLength);

  /// Код группами: `6795-4332`.
  String get display => formatParticipantCode(code);

  /// Запись для сведений записи и для хранения.
  ///
  /// Входы генератора лежат рядом с кодом: по ним код можно вывести
  /// заново и убедиться, что он не придуман.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'generated': generated,
    'generator': generated ? kCodeGenerator : null,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'attempt': attempt,
  };

  /// Время сравнивается мигом, а не записью: код, прочитанный из
  /// настроек, приходит со временем в UTC, выданный — с местным.
  @override
  bool operator ==(Object other) =>
      other is ParticipantCode &&
      other.code == code &&
      other.generated == generated &&
      other.generatedAt.isAtSameMomentAs(generatedAt) &&
      other.attempt == attempt;

  @override
  int get hashCode => Object.hash(
    code,
    generated,
    generatedAt.millisecondsSinceEpoch,
    attempt,
  );

  @override
  String toString() => 'ParticipantCode($display)';
}

/// Семь цифр кода из входов генератора.
///
/// `SHA-256("sno-code/1|узел|время_мс|попытка")`, первые восемь байт
/// как целое по модулю девяти миллионов плюс миллион: первая цифра не
/// бывает нулём — ведущий ноль от руки теряют.
String participantCodeBase({
  required String nodeId,
  required int timeMs,
  required int attempt,
}) {
  final List<int> hash = sha256
      .convert(utf8.encode('$kCodeGenerator|$nodeId|$timeMs|$attempt'))
      .bytes;
  // Остаток считается на ходу: восемь байт целиком в знаковое целое
  // Dart не помещаются.
  int rest = 0;
  for (int i = 0; i < 8; i++) {
    rest = (rest * 256 + hash[i]) % 9000000;
  }
  return (1000000 + rest).toString();
}

/// Выдаёт код участника (SNO-ALG-CFG-03).
///
/// [known] — семёрки цифр, уже встречавшиеся на этом устройстве: с
/// ними новый код не совпадёт, попытка растёт, пока не выйдет новая
/// семёрка. Время здесь — только источник разнообразия: сбитые часы
/// устройства на код не влияют.
ParticipantCode generateParticipantCode({
  required String nodeId,
  required DateTime now,
  Set<String> known = const <String>{},
}) {
  final int timeMs = now.millisecondsSinceEpoch;
  int attempt = 0;
  String base = participantCodeBase(
    nodeId: nodeId,
    timeMs: timeMs,
    attempt: attempt,
  );
  while (known.contains(base)) {
    attempt++;
    base = participantCodeBase(
      nodeId: nodeId,
      timeMs: timeMs,
      attempt: attempt,
    );
  }
  return ParticipantCode(
    code: '$base${dammCheckDigit(base)}',
    generated: true,
    generatedAt: now,
    attempt: attempt,
  );
}

/// Код, введённый вместо выданного; `null` — контрольная цифра не
/// сходится или цифр не восемь.
ParticipantCode? enteredParticipantCode(String input, DateTime now) {
  final String code = normalizeParticipantCode(input);
  if (!isValidParticipantCode(code)) {
    return null;
  }
  return ParticipantCode(code: code, generated: false, generatedAt: now);
}

/// Список выданных семёрок — одной строкой для хранения.
String encodeKnownCodes(Set<String> known) {
  final List<String> sorted = known.toList()..sort();
  return sorted.join(' ');
}

/// Читает список выданных семёрок; чужое в строке пропускается.
Set<String> decodeKnownCodes(String? stored) {
  if (stored == null || stored.isEmpty) {
    return <String>{};
  }
  return <String>{
    for (final String item in stored.split(' '))
      if (item.length == kCodeBaseLength && _allDigits(item)) item,
  };
}
