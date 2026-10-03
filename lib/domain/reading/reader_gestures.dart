/// Жесты чтения: что означает нажатие и чем начинается выделение.
///
/// Вынесено в домен затем же, зачем и геометрия рамки: это правила, а не
/// виджеты, и проверять их надо числами. Экран чтения только исполняет
/// то, что здесь решено.
library;

import 'dart:ui' show Offset, PointerDeviceKind;

/// Что делает нажатие по странице.
enum ReaderTap {
  /// Предыдущий фрагмент.
  previousFragment,

  /// Следующий фрагмент.
  nextFragment,

  /// Снять выделение, никуда не уходя.
  dismissSelection,

  /// Показать или спрятать панели.
  toggleChrome,
}

/// Доля ширины экрана по краям, отданная переходу по фрагментам, — пока
/// читатель не выбрал свою (F-READ-23).
const double kReaderTapZone = 0.3;

/// Самая узкая зона листания: уже неё в край экрана не попасть.
const double kMinReaderTapZone = 0.1;

/// Самая широкая зона листания.
///
/// Не половина: между зонами обязана остаться середина, которая
/// показывает панели, — иначе до настроек было бы не добраться.
const double kMaxReaderTapZone = 0.45;

/// Шаг, которым зона меняется в настройках, в процентах ширины экрана.
const int kReaderTapZoneStep = 5;

/// Приводит ширину зоны листания к допустимой.
double clampReaderTapZone(double zone) {
  if (!zone.isFinite) {
    return kReaderTapZone;
  }
  if (zone < kMinReaderTapZone) {
    return kMinReaderTapZone;
  }
  return zone > kMaxReaderTapZone ? kMaxReaderTapZone : zone;
}

/// Ширина зоны листания из сохранённой настройки — целого числа
/// процентов. Нет настройки или она не читается — [kReaderTapZone].
double parseReaderTapZone(String? saved) {
  final int? percent = saved == null ? null : int.tryParse(saved.trim());
  if (percent == null) {
    return kReaderTapZone;
  }
  return clampReaderTapZone(percent / 100);
}

/// Ширина зоны листания целым числом процентов — для настроек и подписи.
int readerTapZonePercent(double zone) =>
    (clampReaderTapZone(zone) * 100).round();

/// Порог долгого нажатия, с которого начинается выделение пальцем.
///
/// Стандартные 500 мс на книге читаются как «приложение задумалось»:
/// владелец на проверке S6 назвал ожидание слишком долгим. 250 мс —
/// «почти моментально» и при этом заметно длиннее случайного касания,
/// которым листают.
const Duration kTouchSelectionDelay = Duration(milliseconds: 250);

/// Что означает нажатие в точке с долей [share] по ширине экрана.
///
/// F-READ-22, ALG-READ-04. **Пока текст выделен, нажатие не листает** —
/// оно снимает выделение, где бы ни пришлось (решение владельца
/// 03.10.2026; отменяет решение 06.09.2026 «зоны работают и при
/// выделенном тексте»). Читатель, который выделил слово и промахнулся
/// мимо панели, терял и выделение, и страницу разом. Стрелки панели,
/// клавиши и кнопки громкости листают и при выделении: они про книгу, а
/// не про место на экране.
///
/// [zone] — ширина зоны листания с каждой стороны, доля ширины экрана
/// (F-READ-23). Сама граница зоны принадлежит середине.
ReaderTap readerTapAt({
  required double share,
  required bool selecting,
  double zone = kReaderTapZone,
}) {
  if (selecting) {
    return ReaderTap.dismissSelection;
  }
  if (share < zone) {
    return ReaderTap.previousFragment;
  }
  if (share > 1 - zone) {
    return ReaderTap.nextFragment;
  }
  return ReaderTap.toggleChrome;
}

/// На сколько палец или перо могут сдвинуться, оставаясь нажатием, в
/// логических точках. То же число, что у распознавателя нажатий Flutter.
const double kTouchTapSlop = 18;

/// То же для мыши и трекпада: с двух точек сдвига у них начинается
/// протяжка — выделение текста или перенос страницы.
const double kPreciseTapSlop = 2;

/// Порог удержания мышью: с него просмотрщик выделяет слово под курсором.
const Duration kMouseHoldDelay = Duration(milliseconds: 500);

/// Сколько сообщение просмотрщика о нажатии может идти следом за самим
/// нажатием. Обычно это 300 мс ожидания двойного нажатия; запас — на
/// кадры, занятые отрисовкой новой страницы.
const Duration kViewerTapEcho = Duration(seconds: 1);

/// Во сколько раз дольше порога удержания надо держать указатель, чтобы
/// жест перестал быть нажатием и без слова распознавателя.
const int kHoldBackstop = 2;

/// На сколько указателю [kind] разрешено сдвинуться, оставаясь нажатием.
double tapSlopFor(PointerDeviceKind kind) =>
    selectionStartsOnDrag(kind) ? kPreciseTapSlop : kTouchTapSlop;

/// Порог удержания указателя [kind]: пальцем с него начинается
/// выделение, мышью просмотрщик выделяет слово.
///
/// Удержание узнаёт распознаватель жестов и сообщает о нём через
/// [TapWatch.spoil]. Метки времени — только страховка, см. [kHoldBackstop].
Duration tapHoldLimitFor(PointerDeviceKind kind) =>
    selectionStartsOnDrag(kind) ? kMouseHoldDelay : kTouchSelectionDelay;

/// Узнаёт одиночное нажатие по сырым событиям указателя (BUG-37).
///
/// Просмотрщик pdfrx 2.6.1 держит одиночное и двойное нажатие на одном
/// распознавателе, и одиночное объявляется, только когда истёк срок
/// ожидания второго — 300 мс. Двойное нажатие у нас при этом не делает
/// ничего, так что ждали его зря: каждое нажатие по краю экрана листало
/// на треть секунды позже стрелки панели.
///
/// Поэтому нажатие узнаётся здесь, в момент, когда указатель поднят:
/// один указатель, основная кнопка, без сдвига и без удержания.
/// Просмотрщик сообщит о том же нажатии следом — такое сообщение
/// опознаётся через [echoes] и второй раз не исполняется.
///
/// **Удержание узнаёт распознаватель жестов, а не метка времени**: он
/// живёт по таймеру и зовёт [spoil]. Сверять порог ещё и по меткам
/// времени события нельзя — на границе порога метки и таймер расходятся
/// на миллисекунды, и такое касание не стало бы ни нажатием, ни
/// выделением. По меткам отсекается только заведомое удержание — вдвое
/// дольше порога ([kHoldBackstop]): страховка на случай, если
/// распознавателя рядом не окажется.
///
/// Виджетов класс не знает: события ему подаёт слушатель указателя, а
/// проверяется он числами.
class TapWatch {
  /// Создаёт наблюдателя. [clock] — монотонные часы; в тестах свои.
  TapWatch({Duration Function()? clock}) : _clock = clock ?? _stopwatchClock();

  final Duration Function() _clock;

  /// Указатели, которые сейчас опущены.
  final Map<int, _Press> _presses = <int, _Press>{};

  /// Жест испорчен целиком: второй палец или начавшееся выделение.
  bool _spoiled = false;

  /// Когда по нашим часам был поднят последний указатель.
  Duration? _released;

  /// Последнее нажатие не исполнено, а оставлено просмотрщику.
  bool _left = false;

  static Duration Function() _stopwatchClock() {
    final Stopwatch watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Указатель опущен. [time] — метка времени самого события.
  ///
  /// [primary] — основная ли это кнопка: правая кнопка мыши и боковая
  /// кнопка пера нажатием не считаются.
  void down({
    required int pointer,
    required Offset position,
    required Duration time,
    required PointerDeviceKind kind,
    bool primary = true,
  }) {
    // Второй палец — это щипок, а не два нажатия.
    if (_presses.isNotEmpty) {
      _spoiled = true;
    }
    _presses[pointer] = _Press(
      start: position,
      time: time,
      kind: kind,
      primary: primary,
    );
  }

  /// Указатель сдвинулся.
  void move({required int pointer, required Offset position}) {
    final _Press? press = _presses[pointer];
    if (press != null && press.isFar(position)) {
      press.moved = true;
    }
  }

  /// Указатель поднят. Возвращает место нажатия или `null`, если это
  /// было не нажатие: удержание, протяжка, щипок, не та кнопка.
  Offset? up({
    required int pointer,
    required Offset position,
    required Duration time,
  }) {
    final _Press? press = _presses.remove(pointer);
    _released = _clock();
    final bool spoiled = _spoiled;
    if (_presses.isEmpty) {
      _spoiled = false;
    }
    if (press == null || spoiled || !press.primary || press.moved) {
      return null;
    }
    if (press.isFar(position)) {
      return null;
    }
    if (time - press.time >= tapHoldLimitFor(press.kind) * kHoldBackstop) {
      return null;
    }
    // Новое нажатие решается заново: что было оставлено прежде, забыто.
    _left = false;
    return position;
  }

  /// Система отобрала указатель: нажатия не было.
  void cancel({required int pointer}) {
    _presses.remove(pointer);
    _released = _clock();
    if (_presses.isEmpty) {
      _spoiled = false;
    }
  }

  /// Жест, который идёт сейчас, нажатием уже не станет: распознаватель
  /// удержания победил и началось выделение.
  ///
  /// Его слово — единственное на пороге удержания: иначе одно касание и
  /// выделило бы слово, и перелистнуло страницу.
  void spoil() {
    if (_presses.isNotEmpty) {
      _spoiled = true;
    }
  }

  /// Нажатие, только что отданное [up], исполнять не стали — пусть его
  /// исполнит тот, кто сообщит о нём следом.
  ///
  /// Так поступают, пока текст выделен: слушатель указателя видит и
  /// касания ручек выделения, а толчок ручки от нажатия по странице ему
  /// не отличить. Просмотрщик отличает — о ручках он не сообщает вовсе.
  /// Сообщение о таком нажатии — не эхо, и [echoes] ответит `false`
  /// ровно один раз.
  void leaveToViewer() => _left = true;

  /// Сообщил ли просмотрщик о нажатии, которое мы уже разобрали сами.
  ///
  /// Всякое нажатие указателем проходит через [up] — исполненное или
  /// отвергнутое, оно уже решено, и сообщение просмотрщика о нём только
  /// повторяет пройденное. Совпадение ищется по времени, а не счётчиком:
  /// о двойном нажатии просмотрщик одиночным не сообщает вовсе, и
  /// счётчик после двух быстрых нажатий проглотил бы чужое сообщение.
  ///
  /// Не эхо — нажатие, которому не предшествовал указатель: его присылают
  /// средства доступности. Такое исполняется как раньше. И не эхо —
  /// нажатие, оставленное просмотрщику через [leaveToViewer].
  bool echoes() {
    if (_left) {
      _left = false;
      return false;
    }
    final Duration? released = _released;
    if (released == null) {
      return false;
    }
    final Duration since = _clock() - released;
    return since >= Duration.zero && since <= kViewerTapEcho;
  }
}

/// Одно касание от опускания до подъёма.
class _Press {
  _Press({
    required this.start,
    required this.time,
    required this.kind,
    required this.primary,
  });

  final Offset start;
  final Duration time;
  final PointerDeviceKind kind;
  final bool primary;

  /// Уходил ли указатель дальше допуска — хотя бы раз.
  bool moved = false;

  bool isFar(Offset position) => (position - start).distance > tapSlopFor(kind);
}

/// Начинается ли выделение протяжкой указателя [kind].
///
/// Мышью текст выделяют, ведя курсор с зажатой кнопкой, и делают это
/// сразу — долгое нажатие мышью не настольная привычка, а задержка
/// непонятно за что. Пальцем наоборот: там протяжка принадлежит
/// прокрутке и листанию, и выделение начинается удержанием.
///
/// С S6.2 то же правило исполняет сам просмотрщик: по исходникам pdfrx,
/// `enableSelectionHandles`, оставленный по умолчанию, включает ручки для
/// пальца и протяжку для мыши. Здесь оно осталось затем, чтобы знать, у
/// каких указателей перехватывать удержание: порог у просмотрщика —
/// стандартные полсекунды, а нужно [kTouchSelectionDelay].
bool selectionStartsOnDrag(PointerDeviceKind kind) {
  return kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;
}
