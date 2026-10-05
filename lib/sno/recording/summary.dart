/// Итоги записи: отлучки участника и блоки тестирования
/// (SNO-F-REC-10, SNO-F-CFG-03).
///
/// То, что экспериментатор видит на экране завершения и что ложится в
/// сведения записи, — без разбора журнала. Чистый Dart.
library;

/// Сколько раз и надолго ли участник уходил из приложения.
class AwaySummary {
  /// Создаёт итог.
  const AwaySummary({
    this.count = 0,
    this.totalMs = 0,
    this.hiddenMs = 0,
    this.longestMs = 0,
  });

  /// Сколько было отлучек.
  final int count;

  /// Сколько они длились все вместе, в миллисекундах.
  final int totalMs;

  /// Сколько из этого приложения не было видно вовсе.
  final int hiddenMs;

  /// Самая длинная отлучка.
  final int longestMs;

  /// Итог с ещё одной отлучкой длиной [awayMs], из которых [hiddenMs]
  /// приложения не было видно.
  AwaySummary plus({required int awayMs, required int hiddenMs}) {
    final int away = awayMs < 0 ? 0 : awayMs;
    final int hidden = hiddenMs < 0 ? 0 : (hiddenMs > away ? away : hiddenMs);
    return AwaySummary(
      count: count + 1,
      totalMs: totalMs + away,
      hiddenMs: this.hiddenMs + hidden,
      longestMs: away > longestMs ? away : longestMs,
    );
  }

  /// Запись для сведений о записи и настроек.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'count': count,
      'total_ms': totalMs,
      'hidden_ms': hiddenMs,
      'longest_ms': longestMs,
    };
  }

  /// Читает запись; `null` — её нет или она не читается.
  static AwaySummary? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? count = raw['count'];
    final Object? total = raw['total_ms'];
    final Object? hidden = raw['hidden_ms'];
    final Object? longest = raw['longest_ms'];
    if (count is! int || total is! int) {
      return null;
    }
    return AwaySummary(
      count: count,
      totalMs: total,
      hiddenMs: hidden is int ? hidden : 0,
      longestMs: longest is int ? longest : 0,
    );
  }
}

/// Блок тестирования, отмеченный экспериментатором.
class BlockMark {
  /// Создаёт отметку.
  const BlockMark({
    required this.number,
    required this.startMs,
    required this.durationMs,
    required this.closedBy,
  });

  /// Номер блока.
  final int number;

  /// Когда блок начат, в миллисекундах от старта записи.
  final int startMs;

  /// Сколько блок длился.
  final int durationMs;

  /// Чем закрыт: `experimenter` — кнопкой, `stop` — остановкой записи.
  final String closedBy;

  /// Запись для сведений о записи и настроек.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'n': number,
      'start_ms': startMs,
      'duration_ms': durationMs,
      'closed_by': closedBy,
    };
  }

  /// Читает отметку; `null` — она не читается.
  static BlockMark? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? number = raw['n'];
    final Object? start = raw['start_ms'];
    final Object? duration = raw['duration_ms'];
    final Object? closedBy = raw['closed_by'];
    if (number is! int || start is! int || duration is! int) {
      return null;
    }
    return BlockMark(
      number: number,
      startMs: start,
      durationMs: duration,
      closedBy: closedBy is String ? closedBy : 'experimenter',
    );
  }

  /// Читает список отметок; нечитаемые пропускаются.
  static List<BlockMark> listFromJson(Object? raw) {
    if (raw is! List<Object?>) {
      return const <BlockMark>[];
    }
    final List<BlockMark> marks = <BlockMark>[];
    for (final Object? item in raw) {
      final BlockMark? mark = BlockMark.fromJson(item);
      if (mark != null) {
        marks.add(mark);
      }
    }
    return List<BlockMark>.unmodifiable(marks);
  }
}

String _clock(int milliseconds) {
  final int seconds = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${seconds ~/ 60}:${two(seconds % 60)}';
}

/// «раз» с числом: 1 раз, 2 раза, 5 раз, 21 раз, 22 раза.
String _times(int count) {
  final int tens = count % 100;
  final int ones = count % 10;
  final bool few = ones >= 2 && ones <= 4 && (tens < 12 || tens > 14);
  return '$count ${few ? 'раза' : 'раз'}';
}

/// Строка об отлучках для экрана завершения; `null` — участник не
/// уходил, и строки нет.
String? describeAway(AwaySummary? away) {
  if (away == null || away.count <= 0) {
    return null;
  }
  return 'Уходил из приложения: ${_times(away.count)}, '
      '${_clock(away.totalMs)}';
}

/// Строка о блоках для экрана завершения; `null` — блоков не отмечали.
String? describeBlocks(List<BlockMark> blocks) {
  if (blocks.isEmpty) {
    return null;
  }
  final String listed = blocks
      .map((BlockMark mark) => '${mark.number} — ${_clock(mark.durationMs)}')
      .join(' · ');
  return 'Блоки: $listed';
}
