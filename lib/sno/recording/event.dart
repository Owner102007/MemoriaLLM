/// Событие журнала записи (SNO-ALG-REC-01, SNO-F-REC-02).
///
/// Одна форма строки для всего, что происходит во время записи сессии
/// исследования СНО2026: `events.jsonl`, одно событие — одна строка
/// JSON. Сквозной номер `seq` обнаруживает потери, `t` — миллисекунды
/// от старта записи по монотонным часам, `wall` — настенное время для
/// чтения глазами.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода.
library;

import 'dart:convert';

/// Виды событий — закрытый перечень.
///
/// Событие нельзя записать строкой с опечаткой: неизвестный вид — ошибка
/// сборки, а не строка журнала, которую разбор потом не узнает. Здесь
/// виды, которые пишет сама запись; действия участника добавляются
/// вместе со своими проводами (SNO-F-REC-02).
enum SnoEventType {
  /// Запись началась: `t = 0`.
  recordingStart('recording.start'),

  /// Запись остановлена: сама, экспериментатором или сбоем.
  recordingStop('recording.stop'),

  /// Приложение ушло с переднего плана.
  appBackground('app.background'),

  /// Приложение вернулось на передний план.
  appForeground('app.foreground'),

  /// Часы записи сверены с настенными.
  clockResync('clock.resync'),

  /// Запись жива: отличает «ничего не делал» от «приложение стояло».
  heartbeat('session.heartbeat'),

  /// Перед записью устройство сбрасывали к эталону.
  stateReset('state.reset'),

  /// Сессия завершена экспериментатором.
  sessionFinish('session.finish');

  const SnoEventType(this.wire);

  /// Имя вида в журнале.
  final String wire;
}

/// Где участник находится: подставляется в каждое событие.
///
/// Заполняет оболочка приложения; журнал читает то, что стоит здесь в
/// миг события. Книга, страница, полоса и режим появятся вместе с
/// событиями чтения — пока известен только экран.
class RecordingContext {
  /// Экран: `shelf`, `testing`, `settings`, `reader`.
  String screen = 'shelf';

  /// Отпечаток открытой книги; `null` — книга не открыта.
  String? book;

  /// Страница открытой книги, считая с единицы.
  int? page;

  /// Полоса страницы, считая с единицы.
  int? strip;

  /// Режим показа страницы.
  String? mode;
}

/// Сколько знаков текста попадает в событие целиком.
const int kJournalTextLimit = 4000;

/// Текст для события: длинный обрезан и помечен.
///
/// Выделение в двадцать тысяч знаков журналу не нужно целиком, но
/// знать, что оно было и какой длины, — нужно.
Map<String, Object?> journalText(String text) {
  if (text.length <= kJournalTextLimit) {
    return <String, Object?>{'text': text};
  }
  return <String, Object?>{
    'text': text.substring(0, kJournalTextLimit),
    'truncated': true,
    'length': text.length,
  };
}

/// Время со смещением пояса: `2026-11-03T14:02:11.482+03:00`.
///
/// `toIso8601String` у местного времени смещения не пишет, а без него
/// по строке не узнать, какой это был час у участника.
String isoWithOffset(DateTime moment) {
  final DateTime local = moment.toLocal();
  String pad(int value, [int width = 2]) {
    return value.toString().padLeft(width, '0');
  }

  final Duration offset = local.timeZoneOffset;
  final int minutes = offset.inMinutes.abs();
  final String sign = offset.isNegative ? '-' : '+';
  return '${pad(local.year, 4)}-${pad(local.month)}-${pad(local.day)}'
      'T${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}'
      '.${pad(local.millisecond, 3)}'
      '$sign${pad(minutes ~/ 60)}:${pad(minutes % 60)}';
}

/// Строка журнала: одно событие, JSON без переносов внутри.
///
/// Поля, которых нет, в строку не пишутся: «книга не открыта» — это
/// отсутствие поля `book`, а не `null`. [post] помечает то, что
/// случилось после остановки записи: в метрики чтения оно не входит.
String encodeEvent({
  required int seq,
  required int t,
  required DateTime wall,
  required SnoEventType type,
  required RecordingContext context,
  Map<String, Object?> data = const <String, Object?>{},
  bool post = false,
}) {
  final String? book = context.book;
  final int? page = context.page;
  final int? strip = context.strip;
  final String? mode = context.mode;
  return jsonEncode(<String, Object?>{
    'seq': seq,
    't': t,
    'wall': isoWithOffset(wall),
    'type': type.wire,
    if (post) 'phase': 'post',
    'screen': context.screen,
    if (book != null) 'book': book,
    if (page != null) 'page': page,
    if (strip != null) 'strip': strip,
    if (mode != null) 'mode': mode,
    if (data.isNotEmpty) 'data': data,
  });
}

/// Что читается из строки журнала при восстановлении.
class EventMarks {
  /// Создаёт отметки.
  const EventMarks({
    required this.seq,
    required this.t,
    required this.type,
    this.wall,
    this.data = const <String, Object?>{},
  });

  /// Сквозной номер события.
  final int seq;

  /// Миллисекунды от старта записи.
  final int t;

  /// Вид события, как он записан.
  final String type;

  /// Настенное время события; `null` — в строке его нет или оно не
  /// читается.
  final DateTime? wall;

  /// Данные события.
  final Map<String, Object?> data;
}

/// Отметки события в строке журнала; `null` — строка не читается.
///
/// Нужно восстановлению после сбоя: последняя целая строка говорит,
/// сколько событий записано, сколько длилась запись и не остановлена
/// ли она уже.
EventMarks? eventMarks(String line) {
  try {
    final Object? raw = jsonDecode(line);
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? seq = raw['seq'];
    final Object? t = raw['t'];
    final Object? type = raw['type'];
    final Object? wall = raw['wall'];
    final Object? data = raw['data'];
    if (seq is! int || t is! int || type is! String) {
      return null;
    }
    return EventMarks(
      seq: seq,
      t: t,
      type: type,
      wall: wall is String ? DateTime.tryParse(wall) : null,
      data: data is Map<String, Object?> ? data : const <String, Object?>{},
    );
  } on FormatException {
    return null;
  }
}

/// Последняя читаемая строка из [lines]; `null` — читаемых нет.
///
/// Последняя целая строка журнала может оказаться мусором — обрывком,
/// за которым успели дописать перевод строки. Тогда отметки берутся у
/// ближайшей читаемой перед ней.
EventMarks? lastEventMarks(List<String> lines) {
  for (int i = lines.length - 1; i >= 0; i--) {
    final EventMarks? marks = eventMarks(lines[i]);
    if (marks != null) {
      return marks;
    }
  }
  return null;
}
