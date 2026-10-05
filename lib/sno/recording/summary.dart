/// Итоги записи: отлучки участника и блоки тестирования
/// (SNO-F-REC-10, SNO-F-CFG-03).
///
/// То, что экспериментатор видит на экране завершения и что ложится в
/// сведения записи, — без разбора журнала. Чистый Dart.
///
/// У записи, оборванной перезапуском приложения, итогов в памяти не
/// осталось: их собирает по журналу [summarizeJournal].
library;

import 'event.dart';

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

  /// Когда блок начат — временем `t` события `block.start`, тем же,
  /// что у строк журнала. Длительность считается иначе ([durationMs]),
  /// поэтому после сна устройства `startMs + durationMs` концом блока
  /// по `t` не будет: конец — у события `block.end`.
  final int startMs;

  /// Сколько блок длился — по счёту записи: сон устройства в блок
  /// входит, время после конца записи — нет.
  final int durationMs;

  /// Чем закрыт: `experimenter` — кнопкой, `stop` — остановкой записи,
  /// `crash` — запись оборвалась, блок закрыт по журналу.
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

/// Что о записи говорит её журнал: итоги, которых у оборванной записи
/// не осталось в памяти.
class JournalSummary {
  /// Создаёт итоги.
  const JournalSummary({
    this.away = const AwaySummary(),
    this.blocks = const <BlockMark>[],
    this.openBlock,
    this.inBackground = false,
  });

  /// Отлучки — вместе с той, что шла, когда журнал кончился.
  final AwaySummary away;

  /// Блоки, закрытые в журнале.
  final List<BlockMark> blocks;

  /// Блок, который в журнале начат и не закончен; длительность — до
  /// последней строки журнала.
  final BlockMark? openBlock;

  /// Кончился ли журнал, пока участника не было на переднем плане.
  final bool inBackground;
}

/// Большее из двух счётов времени между событиями, не меньше нуля:
/// монотонные часы стоят во сне устройства, настенные могут перевести.
int _between(EventMarks from, EventMarks to) {
  final DateTime? fromWall = from.wall;
  final DateTime? toWall = to.wall;
  final int byWall = fromWall == null || toWall == null
      ? 0
      : toWall.difference(fromWall).inMilliseconds;
  final int byT = to.t - from.t;
  final int span = byWall > byT ? byWall : byT;
  return span < 0 ? 0 : span;
}

/// Собирает итоги записи по её журналу [events] (SNO-F-REC-10,
/// SNO-F-CFG-03).
///
/// Нужно записи, оборванной перезапуском: что отмечено блоками и
/// сколько участник отсутствовал, знает только журнал. Отлучка и блок,
/// открытые в конце журнала, считаются до его последней строки — или
/// до строки остановки, если она уже записана.
///
/// Строки, дописанные после сбоя (`late`), несут время перезапуска, а
/// не записи: блок по такой строке закрывается, но концом журнала она
/// не считается. Время после конца записи (`late_ms` остановки) в
/// отлучку не входит — как у живой записи.
JournalSummary summarizeJournal(List<EventMarks> events) {
  if (events.isEmpty) {
    return const JournalSummary();
  }
  // Остановка — последняя в журнале; всё, что записано за ней, к записи
  // не относится.
  int last = events.length - 1;
  EventMarks? stop;
  for (int i = 0; i < events.length; i++) {
    if (events[i].type == SnoEventType.recordingStop.wire) {
      stop = events[i];
      last = i;
    }
  }
  // Конец журнала для счёта времени — последняя строка самой записи.
  EventMarks end = events[last];
  for (int i = last; i >= 0; i--) {
    if (events[i].data['late'] != true) {
      end = events[i];
      break;
    }
  }
  const Set<String> seen = <String>{'resumed', 'inactive'};
  final List<({int away, int hidden})> absences = <({int away, int hidden})>[];
  final List<BlockMark> blocks = <BlockMark>[];
  EventMarks? blockStart;
  EventMarks? left;
  EventMarks? hiddenSince;
  int hiddenMs = 0;
  for (int i = 0; i <= last; i++) {
    final EventMarks event = events[i];
    final String type = event.type;
    if (type == SnoEventType.blockStart.wire) {
      blockStart = event;
    } else if (type == SnoEventType.blockEnd.wire) {
      final Object? number = event.data['n'];
      final Object? duration = event.data['duration_ms'];
      final Object? by = event.data['by'];
      final EventMarks? start = blockStart;
      final int lasted = duration is int
          ? duration
          : (start == null ? 0 : _between(start, event));
      if (number is int) {
        blocks.add(
          BlockMark(
            number: number,
            startMs: start?.t ?? event.t - lasted,
            durationMs: lasted,
            closedBy: by is String ? by : 'experimenter',
          ),
        );
      }
      blockStart = null;
    } else if (type == SnoEventType.appBackground.wire) {
      if (left == null) {
        left = event;
        // Отлучка, начатая уже невидимым приложением (запись стартовала
        // при свёрнутом окне): смены состояния перед ней в журнале нет.
        if (hiddenSince == null && !seen.contains(event.data['state'])) {
          hiddenSince = event;
        }
      }
    } else if (type == SnoEventType.appState.wire) {
      final bool was = seen.contains(event.data['from']);
      final bool now = seen.contains(event.data['to']);
      final EventMarks? since = hiddenSince;
      if (was && !now) {
        hiddenSince = event;
      } else if (!was && now && since != null) {
        hiddenMs += _between(since, event);
        hiddenSince = null;
      }
    } else if (type == SnoEventType.appForeground.wire) {
      final Object? gone = event.data['away_ms'];
      final Object? hidden = event.data['hidden_ms'];
      if (gone is int) {
        absences.add((away: gone, hidden: hidden is int ? hidden : 0));
      }
      left = null;
      hiddenSince = null;
      hiddenMs = 0;
    }
  }
  final EventMarks? leftAt = left;
  if (leftAt != null) {
    final EventMarks? since = hiddenSince;
    absences.add((
      away: _between(leftAt, end),
      hidden: hiddenMs + (since == null ? 0 : _between(since, end)),
    ));
  }
  // Запись, кончившаяся в отсутствие участника: последняя отлучка идёт
  // в итог только до конца записи.
  final Object? late = stop?.data['late_ms'];
  final int past = late is int && late > 0 ? late : 0;
  final bool endedAway = leftAt != null || stop?.data['in_background'] == true;
  AwaySummary away = const AwaySummary();
  for (int i = 0; i < absences.length; i++) {
    final bool clipped = endedAway && i == absences.length - 1;
    away = away.plus(
      awayMs: absences[i].away - (clipped ? past : 0),
      hiddenMs: absences[i].hidden,
    );
  }
  final EventMarks? start = blockStart;
  final Object? number = start?.data['n'];
  return JournalSummary(
    away: away,
    blocks: List<BlockMark>.unmodifiable(blocks),
    openBlock: start == null || number is! int
        ? null
        : BlockMark(
            number: number,
            startMs: start.t,
            durationMs: _between(start, end),
            closedBy: 'crash',
          ),
    inBackground: leftAt != null,
  );
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
