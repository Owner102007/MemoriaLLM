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
/// сборки, а не строка журнала, которую разбор потом не узнает. Сначала
/// стоят виды, которые пишет сама запись, за ними — действия участника
/// (SNO-F-REC-02): их пишут экраны через [ActionLog].
///
/// События второго мозга добавляются вместе со своими функциями;
/// события взгляда (`eye.*`, SNO-F-EYE-04) пишет только сборка ветви для
/// ПК; события карты и подготовки книг ветви II (SNO-F-MAP-01,
/// SNO-F-IDX-04) и теста нагрузки (SNO-F-CLT-01, SNO-F-CLT-03) стоят в
/// конце перечня.
enum SnoEventType {
  /// Запись началась: `t = 0`.
  recordingStart('recording.start'),

  /// Запись остановлена: сама, экспериментатором или сбоем.
  recordingStop('recording.stop'),

  /// Приложение сменило состояние: каждая смена, а не только первая
  /// (SNO-F-REC-10).
  appState('app.state'),

  /// Приложение ушло с переднего плана: начало отлучки.
  appBackground('app.background'),

  /// Приложение вернулось на передний план: конец отлучки.
  appForeground('app.foreground'),

  /// Часы записи сверены с настенными.
  clockResync('clock.resync'),

  /// Запись жива: отличает «ничего не делал» от «приложение стояло».
  heartbeat('session.heartbeat'),

  /// Защита записи от выгрузки в фоне: заведена ли служба переднего
  /// плана и видно ли её уведомление (SNO-F-REC-13).
  recordingGuard('recording.guard'),

  /// У устройства кончается заряд или место: журнал сброшен на диск
  /// сразу (SNO-F-REC-13).
  deviceLow('device.low'),

  /// Перед записью устройство сбрасывали к эталону.
  stateReset('state.reset'),

  /// Сессия завершена экспериментатором.
  sessionFinish('session.finish'),

  /// Экспериментатор начал блок тестирования.
  ///
  /// Только в записях прежних сборок: с шага 25 блоков нет, запись
  /// идёт в один этап (SNO-F-REC-15). Вид остаётся в перечне, чтобы
  /// журнал записи, начатой прежней сборкой, читался как раньше.
  blockStart('block.start'),

  /// Блок тестирования закончен. Только в записях прежних сборок
  /// (SNO-F-REC-15).
  blockEnd('block.end'),

  /// Участник перешёл с экрана на экран.
  navScreen('nav.screen'),

  /// Системное «назад», которое закрыло не экран, а что-то на нём.
  navBack('nav.back'),

  /// Открылась панель, шторка или окно поверх экрана.
  panelOpen('panel.open'),

  /// Панель, шторка или окно закрылись.
  panelClose('panel.close'),

  /// Полка показана: что на ней и где она стоит.
  shelfShown('shelf.shown'),

  /// Полку прокрутили (прореженно).
  shelfScroll('shelf.scroll'),

  /// Книга открылась.
  bookOpen('book.open'),

  /// Книгу закрыли.
  bookClose('book.close'),

  /// На экране другая страница или другая её полоса.
  pageShown('page.shown'),

  /// Сменился режим показа страницы.
  viewMode('view.mode'),

  /// Страницу приблизили или подвинули (прореженно).
  viewZoom('view.zoom'),

  /// Масштаб заперли или отперли.
  viewLock('view.lock'),

  /// Сменился светофильтр.
  viewFilter('view.filter'),

  /// Изменилась обрезка полей.
  viewCrop('view.crop'),

  /// Чтение повернули.
  viewOrientation('view.orientation'),

  /// Открыли оглавление.
  tocOpen('toc.open'),

  /// Перешли по оглавлению.
  tocJump('toc.jump'),

  /// Перешли ползунком страниц.
  sliderJump('slider.jump'),

  /// Запрос поиска — по книге или по полке.
  searchQuery('search.query'),

  /// Открыли найденное.
  searchResultOpen('search.result.open'),

  /// Поиск закрыли.
  searchClose('search.close'),

  /// Текст выделен: выделение устоялось.
  selectEnd('select.end'),

  /// Выделение снято без действия над ним.
  selectCancel('select.cancel'),

  /// Действие панели над выделением.
  selectionAction('selection.action'),

  /// Сохранена цитата.
  quoteCreate('quote.create'),

  /// Цитата удалена.
  quoteDelete('quote.delete'),

  /// Написана заметка.
  noteCreate('note.create'),

  /// Заметку исправили.
  noteEdit('note.edit'),

  /// Открыли «Цитаты и заметки».
  annotationsOpen('annotations.open'),

  /// Перешли из «Цитат и заметок» к месту в книге.
  annotationJump('annotation.jump'),

  /// Изменена настройка.
  settingsChange('settings.change'),

  /// Участнику показана ошибка.
  errorShown('error.shown'),

  /// Раздел «Галактика» показал карту: сколько на ней точек, какого
  /// они размера, где карта стоит на экране и куда смотрит
  /// (SNO-F-MAP-01).
  galaxyOpen('galaxy.open'),

  /// Карту подвинули или приблизили — чем жест кончился.
  galaxyView('galaxy.view'),

  /// Нажали на точку карты.
  galaxyStar('galaxy.star'),

  /// Открылась карточка книги на карте.
  galaxyCardOpen('galaxy.card.open'),

  /// Карточка книги на карте закрылась.
  galaxyCardClose('galaxy.card.close'),

  /// Вместо карты в разделе стоят слова: книги читаются, карта не
  /// посчитана, книг мало, карта не открылась.
  galaxyEmpty('galaxy.empty'),

  /// Ход подготовки книг ветви II: чтение текста и расчёт карты
  /// (SNO-F-IDX-04).
  indexProgress('index.progress'),

  /// Началась часть теста нагрузки (SNO-F-CLT-03).
  cltStart('clt.start'),

  /// Часть теста нагрузки пройдена до конца.
  cltFinish('clt.finish'),

  /// Попытка ввести пароль теста: удалась или нет — без самого ввода
  /// (SNO-F-CLT-01).
  cltPassword('clt.password.attempt'),

  /// Айтрекера в этой записи нет: место записи не задано, папки `eye/`
  /// нет, спутник не запустился (SNO-F-EYE-04). Запись идёт без
  /// взгляда. События `eye.*` пишет только сборка ветви для ПК.
  eyeUnavailable('eye.unavailable'),

  /// Спутник взгляда поднялся: его версия, версия MediaPipe и сумма
  /// модели лица.
  eyeReady('eye.ready'),

  /// Пара часов «QPC — `t` записи» при старте (SNO-ALG-EYE-03, шаг 5).
  eyeClock('eye.clock'),

  /// Сверка часов с спутником: пара «QPC — `t`» и итог рукопожатия.
  eyeSync('eye.sync'),

  /// Спутник потерян: вышел, замолчал или шлёт мусор.
  eyeLost('eye.lost'),

  /// Спутник поднят заново.
  eyeRestart('eye.restart'),

  /// Спутник терялся слишком часто: дальше запись идёт без него. В
  /// имени нет подчёркивания — виды событий называются одними буквами
  /// и точками.
  eyeGaveUp('eye.gaveup'),

  /// Окно записи на мониторе айтрекера: под замком, на каком мониторе,
  /// какого размера, или монитор сменился (SNO-F-EYE-07).
  eyeWindow('eye.window'),

  /// Самопроверка места перед калибровкой участника: годится, с
  /// оговоркой или нет, и что не так (SNO-F-EYE-01).
  eyeCheck('eye.check'),

  /// Началась попытка калибровки участника (SNO-F-EYE-01).
  eyeCalibrationStart('eye.calibration.start'),

  /// Точка калибровки или проверки на экране: где, какой фазы, QPC
  /// мига, когда кадр с ней отрисован (SNO-F-EYE-01, SNO-F-EYE-06).
  eyeTarget('eye.target'),

  /// Итог попытки калибровки: модель, точность, приняли ли.
  eyeCalibrationResult('eye.calibration.result'),

  /// Организатор выбрал после неудачной калибровки: писать взгляд с
  /// пометкой или без взгляда (SNO-F-EYE-01).
  eyeSkip('eye.skip'),

  /// Поток взгляда пошёл: сегмент файлов и номер первой строки
  /// `gaze.jsonl` (SNO-F-REC-04).
  eyeGaze('eye.gaze'),

  /// Лица нет в кадре дольше секунды (SNO-F-EYE-02).
  eyeFaceLost('eye.face.lost'),

  /// Лицо вернулось в кадр: сколько его не было.
  eyeFaceBack('eye.face.back'),

  /// После остановки записи началась проверка точности в конце
  /// (SNO-F-EYE-06).
  eyeEndcheckStart('eye.endcheck.start'),

  /// Итог проверки в конце: точность, дрейф от начала — или
  /// пропущена организатором.
  eyeEndcheckResult('eye.endcheck.result'),

  /// Спутник дописал файлы взгляда и закрылся: его итог.
  eyeClosed('eye.closed'),

  /// Изучение началось: сорок минут записи идут от этого мига
  /// (SNO-F-EYE-01). Пишется только записью, у которой перед изучением
  /// идёт калибровка взгляда (сборка ветви на ПК с айтрекером); без неё
  /// изучение начинается вместе с `recording.start`, и строки нет.
  studyStart('study.start');

  const SnoEventType(this.wire);

  /// Имя вида в журнале.
  final String wire;
}

/// Виды событий, которые пишет только сборка ветви II (SNO-F-REC-17).
///
/// Запись и тест в ветвях I и II одинаковы: одни события с одними
/// полями. Различаться журналы вправе только событиями экранов,
/// которых в ветви I нет, — карты и подготовки книг; позже сюда встанут
/// события «Палимпсеста». Список один на всё приложение: новое
/// различие между ветвями заводится решением владельца и записывается
/// здесь, а одинаковость остального держит автотест
/// (`test/sno/branch_parity_test.dart`).
const Set<SnoEventType> kSecondBranchEvents = <SnoEventType>{
  SnoEventType.galaxyOpen,
  SnoEventType.galaxyView,
  SnoEventType.galaxyStar,
  SnoEventType.galaxyCardOpen,
  SnoEventType.galaxyCardClose,
  SnoEventType.galaxyEmpty,
  SnoEventType.indexProgress,
};

/// Где участник находится: подставляется в каждое событие.
///
/// Экран называет оболочка приложения, книгу, страницу, полосу и режим
/// — экран чтения; журнал читает то, что стоит здесь в миг события.
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
/// [input] — номер строки потока сырого ввода, в ответ на которую
/// приложение это сделало (SNO-F-REC-11); касание, на которое не
/// сослалось ни одно событие, — пустое.
String encodeEvent({
  required int seq,
  required int t,
  required DateTime wall,
  required SnoEventType type,
  required RecordingContext context,
  Map<String, Object?> data = const <String, Object?>{},
  bool post = false,
  int? input,
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
    if (input != null) 'input': input,
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

/// Читаемые события из [lines], в порядке записи.
///
/// Целая строка журнала может оказаться мусором — обрывком, за которым
/// успели дописать перевод строки. Такие строки пропускаются: счёт и
/// время берутся у читаемых.
List<EventMarks> readableEvents(List<String> lines) {
  final List<EventMarks> events = <EventMarks>[];
  for (final String line in lines) {
    final EventMarks? marks = eventMarks(line);
    if (marks != null) {
      events.add(marks);
    }
  }
  return events;
}
