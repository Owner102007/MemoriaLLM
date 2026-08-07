import 'dart:math';

/// Метка гибридных логических часов (HLC) — версия строки для слияния.
///
/// Формат строки совпадает с форматом пакета `crdt`, поверх которого
/// работает `sqlite_crdt`: `<время ISO-8601 UTC>-<счётчик, 4 hex>-<узел>`.
/// Совместимость нужна потому, что движок слияния появится только в S10,
/// а метки проставляются с S2: переписывать уже накопленные данные никто
/// не станет.
///
/// Порядок меток тотальный: сначала время, при равенстве — счётчик, при
/// равенстве — идентификатор узла. Поэтому два изменения, сделанные на
/// разных устройствах в одну миллисекунду, всё равно сравнимы.
///
/// Идентификатор узла не должен содержать двоеточий: по последнему
/// двоеточию при разборе находится граница временной части.
class Hlc implements Comparable<Hlc> {
  /// Создаёт метку из компонентов.
  const Hlc(this.millis, this.counter, this.nodeId);

  /// Начальная метка узла — раньше любой настоящей.
  const Hlc.zero(String nodeId) : this(0, 0, nodeId);

  /// Разбирает каноническую строку.
  factory Hlc.parse(String value) {
    final int colon = value.lastIndexOf(':');
    final int dash = colon < 0 ? -1 : value.indexOf('-', colon);
    if (dash < 0 || value.length < dash + 6) {
      throw FormatException('Строка не похожа на метку HLC', value);
    }
    final DateTime time = DateTime.parse(value.substring(0, dash));
    final String hex = value.substring(dash + 1, dash + 5);
    return Hlc(
      time.millisecondsSinceEpoch,
      int.parse(hex, radix: 16),
      value.substring(dash + 6),
    );
  }

  /// Наибольший счётчик: в строке под него отведено четыре hex-знака.
  static const int maxCounter = 0xFFFF;

  /// Время метки в миллисекундах эпохи.
  final int millis;

  /// Счётчик событий внутри одной миллисекунды.
  final int counter;

  /// Идентификатор устройства, породившего метку.
  final String nodeId;

  /// Следующая метка этого узла для локального изменения.
  Hlc issue(int wallMillis) {
    if (wallMillis > millis) {
      return Hlc(wallMillis, 0, nodeId);
    }
    return Hlc(millis, _nextCounter(counter), nodeId);
  }

  /// Метка после приёма удалённого изменения: часы узла не должны
  /// отставать от того, что уже видели другие устройства.
  Hlc receive(Hlc remote, int wallMillis) {
    if (wallMillis > millis && wallMillis > remote.millis) {
      return Hlc(wallMillis, 0, nodeId);
    }
    if (millis == remote.millis) {
      final int highest = counter > remote.counter ? counter : remote.counter;
      return Hlc(millis, _nextCounter(highest), nodeId);
    }
    if (millis > remote.millis) {
      return Hlc(millis, _nextCounter(counter), nodeId);
    }
    return Hlc(remote.millis, _nextCounter(remote.counter), nodeId);
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) {
      return millis.compareTo(other.millis);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) {
    return other is Hlc &&
        other.millis == millis &&
        other.counter == counter &&
        other.nodeId == nodeId;
  }

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);

  @override
  String toString() {
    final DateTime time = _utc(millis);
    final String hex = counter.toRadixString(16).padLeft(4, '0');
    return '${time.toIso8601String()}-$hex-$nodeId';
  }
}

/// Часы узла: выдают монотонно растущие метки.
///
/// Часы не полагаются на системное время как на источник истины: если оно
/// отстало или прыгнуло назад, метка растёт за счёт счётчика.
class HlcClock {
  /// Создаёт часы. [last] — метка, на которой остановился прошлый запуск.
  HlcClock({
    required String nodeId,
    Hlc? last,
    DateTime Function()? now,
    void Function(Hlc stamp)? onIssued,
  }) {
    _last = last ?? Hlc.zero(nodeId);
    _now = now ?? DateTime.now;
    _onIssued = onIssued;
  }

  late final DateTime Function() _now;
  late final void Function(Hlc stamp)? _onIssued;
  late Hlc _last;

  /// Последняя выданная метка.
  Hlc get last => _last;

  /// Идентификатор этого устройства.
  String get nodeId => _last.nodeId;

  /// Выдаёт метку для локального изменения.
  Hlc issue() {
    _last = _last.issue(_wallMillis());
    _onIssued?.call(_last);
    return _last;
  }

  /// Учитывает метку, пришедшую с другого устройства.
  Hlc receive(Hlc remote) {
    _last = _last.receive(remote, _wallMillis());
    _onIssued?.call(_last);
    return _last;
  }

  int _wallMillis() => _now().toUtc().millisecondsSinceEpoch;
}

/// Генерирует идентификатор узла: 32 шестнадцатеричных знака.
///
/// Без дефисов и двоеточий — идентификатор попадает внутрь строки метки.
String generateNodeId([Random? random]) {
  final Random source = random ?? Random.secure();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 16; i++) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

DateTime _utc(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

int _nextCounter(int current) {
  if (current < Hlc.maxCounter) {
    return current + 1;
  }
  throw StateError('Счётчик HLC переполнен за одну миллисекунду');
}
