/// Часы, общие с спутником взгляда: QueryPerformanceCounter
/// (SNO-ALG-EYE-03, шаг 5).
///
/// Спутник штампует кадры `time.perf_counter_ns()`, а на Windows это
/// тот же счётчик QPC: у всех процессов машины одна частота и одно
/// начало. Приложение читает его напрямую — через `dart:ffi` к
/// `kernel32`, без плагина, — и пишет пары «QPC — `t` записи»; по ним
/// разбор переводит время спутника в время журнала.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Часы в микросекундах QPC.
abstract interface class QpcClock {
  /// Сейчас, мкс.
  int nowUs();
}

typedef _QpcNative = Int32 Function(Pointer<Int64> value);
typedef _QpcDart = int Function(Pointer<Int64> value);

/// Настоящий QPC Windows.
///
/// Ячейка под ответ заводится один раз и живёт, пока живёт приложение:
/// часы нужны всё время, пока открыт айтрекер, и заводятся на всё
/// приложение один раз.
class WindowsQpcClock implements QpcClock {
  WindowsQpcClock._(this._counter, this._frequency, this._cell);

  /// Часы; `null` — их нет (не Windows или `kernel32` не ответил).
  static WindowsQpcClock? open() {
    try {
      final DynamicLibrary kernel = DynamicLibrary.open('kernel32.dll');
      final _QpcDart counter = kernel.lookupFunction<_QpcNative, _QpcDart>(
        'QueryPerformanceCounter',
      );
      final _QpcDart frequency = kernel.lookupFunction<_QpcNative, _QpcDart>(
        'QueryPerformanceFrequency',
      );
      final Pointer<Int64> cell = calloc<Int64>();
      if (frequency(cell) == 0 || cell.value <= 0) {
        calloc.free(cell);
        return null;
      }
      return WindowsQpcClock._(counter, cell.value, cell);
    } on Object {
      return null;
    }
  }

  final _QpcDart _counter;
  final int _frequency;
  final Pointer<Int64> _cell;

  @override
  int nowUs() {
    _counter(_cell);
    return qpcTicksToUs(_cell.value, _frequency);
  }
}

/// Тики QPC в микросекунды — без переполнения на больших значениях и с
/// округлением к меньшему, как у `perf_counter_ns` Python.
int qpcTicksToUs(int ticks, int frequency) {
  return ticks ~/ frequency * 1000000 + (ticks % frequency) * 1000000 ~/ frequency;
}

/// Часы без QPC: монотонный счёт от запуска приложения. Для платформ без
/// айтрекера и для тестов: со временем спутника они не сравнимы, и
/// сверка часов по ним называет смещение как есть.
class StopwatchQpcClock implements QpcClock {
  /// Создаёт часы.
  StopwatchQpcClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int nowUs() => _watch.elapsedMicroseconds;
}
