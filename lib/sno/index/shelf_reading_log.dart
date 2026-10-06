/// Ход подготовки книг — в журнал записи (SNO-F-IDX-04).
///
/// Подготовка книг ветви II идёт сама по себе: читает текст книг полки
/// и считает карту. Если она идёт во время записи, разбору нужно это
/// знать — приложение в эти минуты занято, а раздел «Галактика» вместо
/// карты показывает слова. Здесь её ход становится событиями
/// `index.progress`: смена того, что делается, каждая прочитанная книга
/// и итог с отпечатком карты.
library;

import '../recording/action_log.dart';
import '../recording/event.dart';
import 'shelf_reading.dart';

/// Что о ходе подготовки пишется в журнал.
Map<String, Object?> shelfReadingFacts(
  ShelfReadingProgress progress,
  ShelfIndexSummary? summary,
) {
  final MapSummary? map = summary?.map;
  final bool done = progress.phase == ShelfReadingPhase.done;
  return <String, Object?>{
    'phase': progress.phase.name,
    'books_done': progress.booksDone,
    'books_total': progress.booksTotal,
    if (progress.phase == ShelfReadingPhase.mapping) ...<String, Object?>{
      'map_done': progress.mapDone,
      'map_total': progress.mapTotal,
    },
    'elapsed_ms': progress.elapsedMs,
    if (done && summary != null) ...<String, Object?>{
      'pages': summary.pages,
      'scans': summary.scans,
      'unread': summary.unread.length,
    },
    if (done && map != null) 'map': map.toJson(),
  };
}

/// Пишет ход подготовки [reading] в журнал [log], пока идёт запись.
///
/// Строка пишется, когда сменилось то, что делается, или прочитана ещё
/// одна книга, — а не на каждую страницу. Отвечает тем, как перестать
/// слушать.
void Function() logShelfReading(ShelfReading reading, ActionLog log) {
  String? said;
  // Сказано ли журналу, что подготовка идёт: только тогда ему нужен и
  // её конец.
  bool active = false;
  void changed() {
    if (!log.recording) {
      // Запись не идёт: следующая начнётся с чистого листа и первым
      // же сдвигом подготовки узнает, где та стоит.
      said = null;
      active = false;
      return;
    }
    final ShelfReadingProgress progress = reading.progress;
    final bool counting = progress.phase == ShelfReadingPhase.mapping;
    final String mark =
        '${progress.phase.name}/${progress.booksDone}/'
        '${progress.booksTotal}/'
        '${counting && progress.mapDone >= progress.mapTotal}';
    if (mark == said) {
      return;
    }
    said = mark;
    if (!progress.busy && !active) {
      // Подготовке нечего было делать: всё прочитано и посчитано
      // заранее — писать не о чем.
      return;
    }
    active = progress.busy;
    log.log(
      SnoEventType.indexProgress,
      data: shelfReadingFacts(progress, reading.summary),
    );
  }

  reading.addListener(changed);
  return () => reading.removeListener(changed);
}
