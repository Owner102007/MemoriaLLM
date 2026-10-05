/// Часы записи (SNO-ALG-REC-01).
///
/// У записи двое часов. `t` — миллисекунды от старта по монотонным
/// часам: они не прыгают, когда переводят время, и по ним сводятся все
/// потоки записи. `wall` — настенное время: якорь старта плюс `t`.
///
/// Монотонные часы Android не идут во сне устройства, поэтому при
/// каждом возврате приложения на передний план часы сверяются
/// ([resync]): разошлись больше чем на полсекунды — у следующих
/// событий `wall` считается от нового якоря. Сам `t` не правится:
/// разбор применяет сдвиг сам.
///
/// Чистый Dart; источники времени подменяются в тестах.
library;

/// Расхождение настенных и монотонных часов, с которого якорь
/// переставляется, в миллисекундах.
const int kResyncThresholdMs = 500;

/// Часы одной записи.
class RecordingClock {
  /// Заводит часы: `t = 0` — сейчас.
  ///
  /// [now] — настенное время, [elapsedMs] — монотонный счёт от старта.
  RecordingClock({
    required DateTime Function() now,
    required int Function() elapsedMs,
  }) : _now = now,
       _elapsedMs = elapsedMs,
       anchor = now() {
    _base = anchor;
    _baseT = elapsedMs();
    _startT = _baseT;
  }

  final DateTime Function() _now;
  final int Function() _elapsedMs;

  /// Настенное время в миг `t = 0`.
  final DateTime anchor;

  late DateTime _base;
  late int _baseT;
  late final int _startT;

  /// Сколько раз якорь переставляли.
  int resyncs = 0;

  /// Миллисекунды от старта записи по монотонным часам.
  int get t => _elapsedMs() - _startT;

  /// Настенное время события в миг [t].
  DateTime wallAt(int t) {
    return _base.add(Duration(milliseconds: t - (_baseT - _startT)));
  }

  /// Сколько прошло от старта по настенным часам, в миллисекундах.
  ///
  /// Сорок минут записи считаются по ним: провал монотонных часов во
  /// сне устройства не должен растянуть сессию.
  int get wallElapsedMs => _now().difference(anchor).inMilliseconds;

  /// Сверяет часы; отвечает расхождением в миллисекундах.
  ///
  /// Положительное — настенные ушли вперёд: монотонные стояли. Якорь
  /// переставляется, только если расхождение больше
  /// [kResyncThresholdMs]; применён ли сдвиг, говорит [applied].
  ({int driftMs, bool applied}) resync() {
    final DateTime now = _now();
    final int t = this.t;
    final int drift = now.difference(wallAt(t)).inMilliseconds;
    if (drift.abs() <= kResyncThresholdMs) {
      return (driftMs: drift, applied: false);
    }
    _base = now;
    _baseT = t + _startT;
    resyncs++;
    return (driftMs: drift, applied: true);
  }
}
