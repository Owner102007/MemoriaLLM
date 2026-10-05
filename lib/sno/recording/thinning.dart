import 'dart:async';

/// Как часто пишется непрерывное событие: не чаще пяти раз в секунду.
const Duration kThinGap = Duration(milliseconds: 200);

/// Прореживание непрерывных событий (SNO-ALG-REC-01, шаг 4).
///
/// Прокрутка полки и масштаб во время жеста меняются десятки раз в
/// секунду, а журналу нужен ход жеста, а не каждый его кадр. Первое
/// значение пишется сразу, следующие — не чаще раза в [gap], и
/// **последнее значение пишется обязательно**: чем жест кончился,
/// журнал знает точно.
class Thinned<T> {
  /// Создаёт прореживатель; [emit] получает значения, которые пишутся.
  Thinned(this._emit, {this.gap = kThinGap});

  final void Function(T value) _emit;

  /// Наименьший промежуток между записанными значениями.
  final Duration gap;

  Timer? _timer;
  T? _pending;
  bool _waiting = false;
  bool _disposed = false;

  /// Новое значение. После [dispose] не делает ничего.
  void add(T value) {
    if (_disposed) {
      return;
    }
    if (_timer == null) {
      // Срок — раньше записи: значение, пришедшее из самой записи,
      // встаёт в очередь, а не пишется вторым подряд.
      _timer = Timer(gap, _fire);
      _emit(value);
      return;
    }
    _pending = value;
    _waiting = true;
  }

  void _fire() {
    _timer = null;
    if (!_waiting) {
      return;
    }
    final T value = _pending as T;
    _pending = null;
    _waiting = false;
    _emit(value);
    _timer = Timer(gap, _fire);
  }

  /// Пишет отложенное значение сразу — жест кончился.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_waiting) {
      final T value = _pending as T;
      _pending = null;
      _waiting = false;
      _emit(value);
    }
  }

  /// Бросает отложенное: писать больше некуда.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _waiting = false;
  }
}
