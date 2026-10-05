import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../application/reading/book_selection.dart';
import '../../application/reading/book_text.dart';
import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../application/reading/selection_actions.dart';
import '../../domain/annotations/annotations.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/prompts/selection_prompt.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/page_turning.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reader_gestures.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/selection_query.dart';
import '../../domain/reading/selection_text.dart';
import '../../domain/reading/sheet_arrangement.dart';
import '../../domain/reading/sheet_placement.dart';
import '../../domain/reading/sheet_transform.dart';
import '../../domain/reading/text_geometry.dart';
import '../../domain/reading/text_search.dart';
import '../../domain/reading/volume_keys.dart';
import '../../domain/reading/window_settle.dart';
import '../../domain/settings/app_settings.dart';
import '../../sno/recording/action_log.dart';
import '../../sno/recording/event.dart';
import '../../sno/recording/thinning.dart';
import '../annotations/annotations_screen.dart';
import 'crop_editor_screen.dart';
import 'display_mode_buttons.dart';
import 'held_box.dart';
import 'highlight_layer.dart';
import 'key_bindings.dart';
import 'note_dialog.dart';
import 'prompt_preview_sheet.dart';
import 'quick_tap.dart';
import 'reader_scaffold.dart';
import 'reader_settings_sheet.dart';
import 'reader_sheet.dart';
import 'reading_filter_layer.dart';
import 'selection_panel.dart';
import 'tap_zone_hint.dart';
import 'viewer_selection.dart';

/// Экран чтения.
///
/// Единственное место, где встречаются `pdfrx` и всё остальное:
/// просмотрщик рисует страницу, а состояние книги — где читатель, какая
/// у страницы рамка, какой фильтр — живёт в [ReaderController] и ничего
/// про виджеты не знает.
///
/// **Рамка работает в постраничном листании.** Там читатель ходит по
/// фрагментам, и каждый фрагмент занимает весь экран. Непрерывная лента
/// оставлена как есть: это другой способ читать, и навязывать ему рамку
/// значит сломать оба.
class ReaderScreen extends StatefulWidget {
  /// Создаёт экран чтения.
  const ReaderScreen({
    required this.book,
    required this.services,
    this.canRelink = true,
    this.models = true,
    this.openedVia = 'shelf',
    super.key,
  });

  /// Книга.
  final Book book;

  /// Каким путём книгу открыли: `shelf` — с полки, `shelf_search` — из
  /// найденного по названию. Пишется в журнал записи сборок ветвей
  /// СНО2026 (SNO-F-REC-02): по нему видно, когда участник перестаёт
  /// искать источник и открывает его по памяти.
  final String openedVia;

  /// Службы приложения.
  final AppServices services;

  /// Можно ли показать файл книги заново, если он пропал.
  ///
  /// В сборках ветвей СНО2026 — нет (BUG-46, решение владельца П3 от
  /// 04.10.2026): свои PDF там не добавляются, книги приходят только
  /// архивом с литературой. «Выбрать файл заново» было последним путём,
  /// которым под именем книги из литературы на полку вставал любой PDF.
  /// Пропавшую копию возвращает повторное добавление архива.
  final bool canRelink;

  /// Есть ли в сборке модель.
  ///
  /// В сборках ветвей СНО2026 — нет (SNO-F-READ-01, SNO-DIV-09): сети и
  /// модели в тестах нет, и кнопка промпта вела бы к запросу, который
  /// некому задать. Над выделением тогда четыре действия — «В цитаты»,
  /// «Заметка», «Копировать», «Найти в книге» — и ни одного промпта.
  final bool models;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  /// Просмотрщик непрерывной ленты. Постраничное чтение рисует лист сам.
  final PdfViewerController _viewer = PdfViewerController();

  /// Рычаги к листу: снять выделение, не трогая страницу.
  final ReaderSheetController _sheet = ReaderSheetController();

  /// Обвязка экрана: у неё спрашиваем, ведут ли кнопки громкости по
  /// совпадениям поиска, и ей возвращаем клавиши после нажатия по
  /// странице (F-TEXT-11).
  final GlobalKey<ReaderScaffoldState> _scaffold =
      GlobalKey<ReaderScaffoldState>();

  /// Книга может смениться прямо на этом экране: если файл переехал,
  /// читатель выбирает его заново, и у книги становится новый источник.
  /// Идентификатор при этом прежний — место чтения и цитаты не теряются.
  late Book _book = widget.book;
  ReaderController? _controller;
  DocumentSearch? _search;

  /// Текст страниц книги: кэш устройства и движок за ним (F-TEXT-04).
  /// По нему ищет [_search], и его же наполняет фоновый проход.
  BookTextCache? _texts;
  Timer? _textPassTimer;
  DocumentOpenException? _failure;
  bool _loading = true;

  /// Как листается книга. Живое значение: его слушает шторка настроек,
  /// которая открыта поверх экрана и сама не перестраивается (BUG-36).
  final ValueNotifier<PageFlow> _flowNow = ValueNotifier<PageFlow>(
    PageFlow.paged,
  );
  AppLifecycleListener? _lifecycle;
  ScreenOrientation _rotation = ScreenOrientation.portrait;
  bool _zoomLocked = true;

  /// Форма окна и место под лист (F-DESK-02, ALG-UI-27).
  ///
  /// На ПК окно меняют протяжкой, и новый размер принимается не сразу,
  /// а когда окно перестали тянуть: до того лист стоит в прежнем размере
  /// и не перекладывается. На телефоне размер меняется один раз —
  /// поворотом — и принимается сразу.
  late final WindowSettle _window = WindowSettle(onSettled: _onWindowSettled);

  /// Окно меняет размер по нашей же просьбе — разворот во весь экран.
  /// Это не протяжка: новый размер принимается сразу.
  bool _windowJump = false;
  Timer? _jumpTimer;

  /// Ширина зоны листания с каждой стороны, доля ширины экрана
  /// (F-READ-23). Настройка устройства.
  double _tapZone = kReaderTapZone;

  /// Показана ли уже подсказка о зонах; `null` — настройка ещё не
  /// прочитана, и решать рано.
  bool? _zoneHintSeen;

  /// Лежит ли подсказка о зонах поверх страницы прямо сейчас.
  bool _zoneHintOn = false;

  /// Какие клавиши листают (F-READ-25). Настройка устройства.
  KeyBindings _keys = KeyBindings.standard;

  /// Нажатие в ленте узнаём сами, как и на листе (BUG-38).
  final TapWatch _ribbonTaps = TapWatch();

  /// Развёрнуто ли чтение во весь экран (F-READ-35): окно занимает весь
  /// монитор, а читаемая полоса вписана в него вплотную. Есть только
  /// там, где у приложения есть окно.
  bool _fullScreen = false;

  /// Выбрал ли читатель чтение во весь экран — настройка устройства.
  ///
  /// Отличается от [_fullScreen] тем, что книга может быть ещё не
  /// открыта или не открыться вовсе: разворачивать во весь монитор экран
  /// загрузки или сообщение об ошибке незачем.
  bool _fullScreenWanted = false;

  /// Идёт ли прямо сейчас разворот окна: второе нажатие, пришедшее
  /// раньше ответа платформы, не должно запросить то же самое ещё раз.
  bool _switchingWindow = false;

  /// Как показывать страницу при листании: сразу ли и с каким запасом
  /// соседних страниц (F-READ-02). Настройка устройства.
  PageTurnSettings _turning = PageTurnSettings.parse(
    preview: null,
    reserve: null,
    desktop: !_canTurn,
  );

  /// Листание кнопками громкости (F-READ-26): настройка устройства и
  /// правило «короткое нажатие листает, удержание меняет громкость».
  ///
  /// Пока настройка не прочитана, перехвата нет: книга открывается
  /// раньше, чем дочитываются настройки устройства, и читатель,
  /// выключивший листание, на миг получал бы его обратно.
  VolumeKeySettings _volume = const VolumeKeySettings(enabled: false);
  final VolumeKeyTurner _volumeTurner = VolumeKeyTurner();
  late final VolumeKeyHandler _volumeHandler = _onVolumeKey;

  /// На экране ли страница: поверх нет ни шторки, ни диалога, ни другого
  /// экрана ([_onTop]), и её не закрыло оглавление ([_panelOpen]). Поиск
  /// страницу не закрывает (F-TEXT-12).
  bool _onTop = true;
  bool _panelOpen = false;

  /// Включён ли экранный диктор.
  bool _screenReader = false;

  /// Что о перехвате кнопок сказано платформе в последний раз.
  bool? _volumeSent;

  /// Что выделено сейчас.
  BookSelection? _selection;

  /// Промпты читателя: набор книги, если он есть, иначе мастерский.
  PromptSet _prompts = PromptSet.empty;
  StreamSubscription<PromptSet>? _promptsWatch;

  /// Что подсвечено на странице: найденное поиском или открытая цитата.
  _PageMark? _mark;
  List<TextBox> _markRects = const <TextBox>[];

  /// Счёт переходов к отмеченному месту: пока искались его
  /// прямоугольники, читатель мог попросить другой переход — тогда этот
  /// устарел и ничего не меняет.
  int _markRun = 0;

  /// Запрос, по которому отмечено найденное; `null` — отмечена цитата
  /// или не отмечено ничего. Запрос сменился — отметка прежнего уходит.
  String? _markQuery;

  /// Открыта ли панель поиска. Пока она открыта, на странице подсвечены
  /// все совпадения запроса, а текущее — ярче (F-TEXT-11).
  bool _searchShown = false;

  /// Совпадения запроса на страницах листа и то, для чего они посчитаны.
  List<_HitRects> _hitRects = const <_HitRects>[];
  String _hitRectsFor = '';
  int _hitRectsRun = 0;

  /// Сколько ширины у страницы отняла панель поиска: на широком окне
  /// она стоит рядом со страницей (F-TEXT-11).
  double _dock = 0;

  /// Размер окна целиком — как о нём сообщила система.
  Size _screen = Size.zero;

  /// Язык, на который читатель просит переводить. Подставляется в
  /// `{{мой_язык}}`; настоящий выбор языка появится в S8 вместе с
  /// редактором промптов.
  String _myLanguage = 'русский';

  /// Журнал действий участника; `null` — в этой сборке записи нет
  /// (SNO-F-REC-02).
  ///
  /// Экран, который уже закрывают, в журнал не пишет: полка записала
  /// `book.close` в миг, когда участник ушёл, а экран живёт ещё треть
  /// секунды, пока уезжает, — книга, досчитавшаяся за это время,
  /// открылась бы в журнале после собственного закрытия.
  ActionLog? get _log {
    return _route?.isActive == false ? null : widget.services.recording;
  }

  /// Маршрут этого экрана: по нему видно, что экран уже закрывают.
  ModalRoute<Object?>? _route;

  /// Действия над выделенным: что уходит из книги и что пишется в
  /// журнал (BUG-51, SNO-F-REC-02).
  SelectionActions? _actions;

  /// Чем вызван следующий показ страницы и когда это сказано: причина,
  /// за которой показа так и не случилось, к чужому показу не идёт.
  String _cause = 'open';
  DateTime _causeAt = DateTime.now();
  int _causeRun = 0;

  /// Сколько причина ждёт своего показа.
  static const Duration _causeLife = Duration(seconds: 3);

  /// Что на экране по последнему слову журналу: страница, полоса, режим.
  ({int page, int strip, String mode})? _placeSaid;

  /// Настройки книги, какими их видел журнал.
  BookReadingSettings? _settingsSaid;

  /// Настройки-ползунки, которые ещё не записаны: пока ползунок тянут,
  /// журналу нужен не каждый его шаг, а то, на чём он остановился.
  final Map<String, Object?> _slid = <String, Object?>{};
  Timer? _slidTimer;

  /// Сколько ползунок обязан простоять, чтобы его значение записалось.
  static const Duration _slidRest = Duration(milliseconds: 400);

  /// Масштаб и сдвиг страницы для журнала — прореженно.
  late final Thinned<SheetTransform> _moved = Thinned<SheetTransform>(
    _logMoved,
  );

  /// Записана ли книга открытой: повторное открытие того же экрана —
  /// после пароля, после выбора файла — вторым обращением не считается.
  bool _openSaid = false;

  /// Сколько выделение обязано простоять, чтобы журнал счёл его
  /// выделением: пока ручку тянут, оно меняется на каждом знаке.
  static const Duration _selectRest = Duration(milliseconds: 600);
  Timer? _selectTimer;

  /// Записано ли нынешнее выделение и было ли над ним действие: снятое
  /// без действия пишется отдельным событием.
  bool _selectSaid = false;
  bool _selectActed = false;

  /// Шёл ли поиск по книге, по какому запросу и с какого мига — для
  /// события запроса.
  bool _searchRan = false;
  String _searchFor = '';
  final Stopwatch _searchTime = Stopwatch();

  /// Говорит, чем вызван следующий показ страницы (SNO-F-REC-02).
  ///
  /// Отвечает номером причины — по нему её снимают ([_dropCause]),
  /// когда действие кончилось.
  int _because(String cause) {
    _cause = cause;
    _causeAt = DateTime.now();
    return ++_causeRun;
  }

  /// Действие с причиной номер [run] кончилось: если показа за ним не
  /// случилось — последняя страница, режим без выигрыша, пометка на
  /// этой же странице, — причина чужому показу не достаётся. Причину,
  /// названную позже, не трогает.
  void _dropCause(int run) {
    if (run == _causeRun) {
      _causeAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Режим показа для журнала: в ленте режимов нет.
  String _modeName(ReaderController controller) {
    return _flow == PageFlow.continuous
        ? 'ribbon'
        : controller.settings.displayMode.name;
  }

  /// Сверяет место чтения с тем, что знает журнал: сменилась страница,
  /// полоса или режим — пишется `page.shown` (SNO-F-REC-02).
  ///
  /// Показ берётся здесь, у контроллера, а не из записи позиции: та
  /// прорежена, а журналу нужен каждый показ — по ним считается время
  /// на странице.
  void _notePlace(ReaderController controller) {
    final ActionLog? log = _log;
    if (log == null) {
      return;
    }
    final bool paged = _flow == PageFlow.paged;
    final ({int page, int strip, String mode}) place = (
      page: controller.page,
      strip: paged ? controller.fragment + 1 : 1,
      mode: _modeName(controller),
    );
    final ({int page, int strip, String mode})? was = _placeSaid;
    if (place == was) {
      return;
    }
    _placeSaid = place;
    log.place(page: place.page, strip: place.strip, mode: place.mode);
    if (!log.recording) {
      return;
    }
    final bool fresh = DateTime.now().difference(_causeAt) <= _causeLife;
    final String cause = fresh ? _cause : (paged ? 'other' : 'scroll');
    _cause = paged ? 'other' : 'scroll';
    final List<int> pages = controller.sheetPages;
    log.log(
      SnoEventType.pageShown,
      data: <String, Object?>{
        'cause': cause,
        if (paged) 'strips': controller.fragmentCount,
        if (pages.length > 1) 'pages': pages,
        'of': controller.pageCount,
        if (was != null)
          'from': <String, Object?>{'page': was.page, 'strip': was.strip},
      },
    );
  }

  /// Сверяет настройки книги с тем, что знает журнал (SNO-F-REC-02).
  ///
  /// Режим, светофильтр и обрезка пишутся сразу — это одно нажатие.
  /// Ползунки пишутся, когда остановились.
  void _noteSettings(ReaderController controller) {
    final BookReadingSettings now = controller.settings;
    final BookReadingSettings? was = _settingsSaid;
    _settingsSaid = now;
    final ActionLog? log = _log;
    if (log == null || was == null || !log.recording) {
      return;
    }
    if (was.displayMode != now.displayMode) {
      log.log(
        SnoEventType.viewMode,
        data: <String, Object?>{
          'mode': now.displayMode.name,
          'from': was.displayMode.name,
        },
      );
    }
    if (was.filter != now.filter) {
      log.log(
        SnoEventType.viewFilter,
        data: <String, Object?>{
          'filter': now.filter.name,
          'from': was.filter.name,
        },
      );
    }
    if (was.autoCrop != now.autoCrop ||
        was.ignoreRunningHeads != now.ignoreRunningHeads ||
        was.manualCrop != now.manualCrop) {
      log.log(
        SnoEventType.viewCrop,
        data: <String, Object?>{
          'auto': now.autoCrop,
          'running_heads': now.ignoreRunningHeads,
          'manual': now.manualCrop != null,
        },
      );
    }
    void slid(String key, double before, double after) {
      if (before != after) {
        _slid[key] = (after * 1000).round() / 1000;
      }
    }

    slid('filter_intensity', was.filterIntensity, now.filterIntensity);
    slid('brightness', was.brightness, now.brightness);
    slid('contrast', was.contrast, now.contrast);
    slid('gamma', was.gamma, now.gamma);
    slid('strip_fit', was.stripFit, now.stripFit);
    slid('dim_outside', was.dimOutside, now.dimOutside);
    slid('strip_overlap', was.stripOverlap, now.stripOverlap);
    slid('neighbour_share', was.neighbourShare, now.neighbourShare);
    if (_slid.isNotEmpty) {
      _slidTimer?.cancel();
      _slidTimer = Timer(_slidRest, _logSlid);
    }
  }

  /// Ползунки остановились: их значения — в журнал одним событием.
  void _logSlid() {
    _slidTimer?.cancel();
    _slidTimer = null;
    if (_slid.isEmpty) {
      return;
    }
    final Map<String, Object?> changed = Map<String, Object?>.of(_slid);
    _slid.clear();
    _log?.log(
      SnoEventType.settingsChange,
      data: <String, Object?>{'scope': 'book', 'changed': changed},
    );
  }

  /// Настройка устройства, которую меняют прямо в чтении.
  void _logDeviceSetting(String key, Object? value) {
    _log?.log(
      SnoEventType.settingsChange,
      data: <String, Object?>{'scope': 'device', 'key': key, 'value': value},
    );
  }

  /// Страницу приблизили или подвинули при отпертом замке.
  void _logMoved(SheetTransform transform) {
    _log?.log(
      SnoEventType.viewZoom,
      data: <String, Object?>{
        'scale': (transform.scale * 100).round() / 100,
        'dx': transform.dx.round(),
        'dy': transform.dy.round(),
      },
    );
  }

  /// Поиск по книге начался или кончился: законченный пишется запросом
  /// с числом найденного и временем (SNO-F-REC-02).
  ///
  /// Запрос, который сменили раньше, чем он досчитался, не пишется:
  /// запросом считается то, что досчиталось.
  void _noteSearch() {
    final DocumentSearch? search = _search;
    final ActionLog? log = _log;
    if (search == null || log == null) {
      return;
    }
    if (search.isRunning) {
      // Запрос сменили, не дождавшись прежнего: время считается от
      // нового, а не от первого из сменённых.
      if (!_searchRan || _searchFor != search.query) {
        _searchRan = true;
        _searchFor = search.query;
        _searchTime
          ..reset()
          ..start();
      }
      return;
    }
    if (!_searchRan) {
      return;
    }
    _searchRan = false;
    _searchTime.stop();
    // Запрос, по которому не искали — стёрли до одной буквы, пока шёл
    // прежний, — запросом не считается.
    if (!log.recording || !isSearchableQuery(search.query)) {
      return;
    }
    log.log(
      SnoEventType.searchQuery,
      data: <String, Object?>{
        'scope': 'book',
        ...journalText(search.query),
        'hits': search.hits.length,
        if (search.reachedLimit) 'limit': true,
        'ms': _searchTime.elapsedMilliseconds,
      },
    );
  }

  /// Выделение появилось или изменилось: в журнал оно попадёт, когда
  /// устоится.
  void _noteSelection(BookSelection selection) {
    _selectTimer?.cancel();
    _selectTimer = null;
    _selectActed = false;
    if (!(_log?.recording ?? false)) {
      return;
    }
    _selectTimer = Timer(_selectRest, () {
      _selectTimer = null;
      // Экран за это время могли закрыть: о выделении в книге, которая
      // в журнале уже закрыта, не пишут.
      if (!(_log?.recording ?? false)) {
        return;
      }
      _selectSaid = true;
      unawaited(_actions?.settled(selection));
    });
  }

  /// Перед действием над выделением: недождавшееся выделение пишется
  /// сейчас — событие о нём обязано стоять раньше события действия.
  Future<void> _settleSelection(BookSelection selection) async {
    if (_selectTimer == null) {
      return;
    }
    _selectTimer?.cancel();
    _selectTimer = null;
    _selectSaid = true;
    await _actions?.settled(selection);
  }

  /// Выделения больше нет: снятое без действия пишется в журнал.
  void _noteSelectionGone() {
    _selectTimer?.cancel();
    _selectTimer = null;
    if (_selectSaid && !_selectActed) {
      unawaited(_actions?.cancelled());
    }
    _selectSaid = false;
    _selectActed = false;
  }

  /// Действие панели над выделением — в журнал.
  Future<void> _logAction(
    String action,
    BookSelection selection, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    await _settleSelection(selection);
    _selectActed = true;
    await _actions?.acted(action, selection, extra: extra);
  }

  /// Можно ли попросить систему повернуть экран.
  ///
  /// На ПК — нельзя: `setPreferredOrientations` там не делает ничего, а
  /// форму окна выбирает человек. Поэтому и кнопки поворота на ПК нет:
  /// кнопка, которая заведомо ничего не сделает, хуже её отсутствия.
  static final bool _canTurn =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  PageFlow get _flow => _flowNow.value;

  /// Действующая форма окна: по ней выбирается режим.
  DisplayArea get _area => _window.area;

  /// Держать ли прежний размер, пока окно меняют: только там, где у
  /// приложения есть окно, и только если меняем его не мы сами.
  bool get _holdsWindow => widget.services.window.available && !_windowJump;

  @override
  void initState() {
    super.initState();
    // Чтение во весь экран: системные панели уходят и возвращаются по
    // жесту от края. Страница — это вся поверхность, а не окно в ней.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    // Свернули приложение — записываем место немедленно: система вправе
    // убить процесс сразу после этого, и переспросить будет некого.
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_controller?.flush()),
      onDetach: () => unawaited(_controller?.flush()),
      // F-TEXT-04: свёрнутое приложение книгу в фоне не читает — батарея
      // дороже; вернулись — проход продолжается с того, что осталось.
      onHide: _stopTextPass,
      onShow: _scheduleTextPass,
    );
    unawaited(_restoreDeviceSettings());
    // Набор промптов слушается живьём: правка мастер-набора в настройках
    // обязана менять подписи на кнопках, не закрывая книгу.
    _promptsWatch = widget.services.data.prompts
        .watchPromptsFor(widget.book.id)
        .listen((PromptSet set) {
          if (mounted) {
            setState(() => _prompts = set);
          }
        });
    unawaited(_open());
  }

  /// Форма области показа приходит из системы и меняется сама: поворот
  /// телефона, изменение размера окна на ПК. Геометрия деления страницы
  /// работает с этими числами, а не с признаком «портрет или альбом», —
  /// иначе на ПК, где ориентации нет вовсе, ей нечего было бы сказать.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _screen = MediaQuery.sizeOf(context);
    _offerArea();
    // Маршрут сообщает сюда же, когда поверх него что-то открыли или
    // закрыли: шторку, диалог, другой экран. Кнопки громкости листают,
    // только пока читатель смотрит на страницу (F-READ-26).
    _screenReader = MediaQuery.accessibleNavigationOf(context);
    _refreshOnTop();
  }

  /// Сообщает форму области показа: окно за вычетом панели поиска,
  /// если та стоит рядом со страницей.
  ///
  /// F-DESK-02: на ПК форма окна принимается, когда его перестали
  /// тянуть, — вместе с местом под лист. F-TEXT-11: режим выбирается по
  /// тому месту, которое странице в самом деле досталось, — иначе
  /// кнопка-дробь обещала бы выигрыш для окна целиком.
  void _offerArea() {
    final double width = _screen.width - _dock;
    final bool changed = _window.offerArea(
      DisplayArea(width: width > 0 ? width : 0, height: _screen.height),
      hold: _holdsWindow,
    );
    if (changed) {
      _controller?.setDisplayArea(_area, canTurn: _canTurn);
    }
  }

  /// Панель поиска встала рядом со страницей или ушла (F-TEXT-11).
  ///
  /// Место под лист меняется один раз и известно зачем — это не
  /// протяжка окна, и новый размер принимается сразу, как при развороте
  /// во весь экран: лист перекладывается один раз при открытии панели и
  /// один раз при закрытии.
  void _onSearchDock(double width) {
    if (!mounted || width == _dock) {
      return;
    }
    _beginWindowJump();
    setState(() => _dock = width);
    _offerArea();
    _endWindowJump();
  }

  /// Панель поиска открыли или закрыли.
  void _onSearchOpen(bool open) {
    _searchShown = open;
    _refreshHitRects();
  }

  /// Окно перестали менять: лист перекладывается под новый размер.
  ///
  /// F-DESK-02, ALG-UI-27. Один раз на всю серию изменений — и вместе с
  /// формой окна, по которой выбирается режим. Место чтения при этом не
  /// меняется: страница и полоса те же, меняется только раскладка.
  void _onWindowSettled() {
    if (!mounted) {
      return;
    }
    setState(() {
      _controller?.setDisplayArea(_area, canTurn: _canTurn);
    });
  }

  /// Окно сейчас сменит размер по нашей просьбе (F-READ-35).
  void _beginWindowJump() {
    _jumpTimer?.cancel();
    _jumpTimer = null;
    _windowJump = true;
  }

  /// Платформа ответила: ещё [kWindowJump] новый размер принимается
  /// сразу — сообщение о нём может прийти следом за ответом.
  void _endWindowJump() {
    _jumpTimer?.cancel();
    _jumpTimer = null;
    if (!mounted) {
      _windowJump = false;
      return;
    }
    _jumpTimer = Timer(kWindowJump, () {
      _jumpTimer = null;
      _windowJump = false;
    });
  }

  /// Перечитывает, лежит ли что-нибудь поверх экрана чтения.
  ///
  /// Зовётся и по сообщению маршрута, и после каждого окна, которое
  /// экран открывал сам, и перед разбором события кнопки: пропустить
  /// смену нельзя — кнопки громкости листали бы книгу из-под шторки.
  void _refreshOnTop() {
    if (!mounted) {
      return;
    }
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    _syncVolumeKeys();
  }

  /// Листают ли кнопки громкости прямо сейчас.
  bool get _volumeKeysActive => volumeKeysActive(
    settings: _volume,
    bookOpen: _controller != null && !_loading && _failure == null,
    onTop: _onTop && !_panelOpen,
    screenReader: _screenReader,
  );

  /// Говорит платформе, перехватывать ли кнопки громкости.
  ///
  /// Пока перехват выключен, `MainActivity` кнопки не трогает вовсе, и
  /// громкость меняет система своим путём — в шторке, в оглавлении, на
  /// экране цитат и везде, где читатель не смотрит на страницу. Поиск,
  /// который страницу не закрывает, перехвату не мешает: там кнопки
  /// ведут по совпадениям (F-TEXT-11).
  void _syncVolumeKeys() {
    final bool active = _volumeKeysActive;
    if (active == _volumeSent) {
      return;
    }
    _volumeSent = active;
    if (active) {
      // Получатель у платформы один. Подключаемся каждый раз, когда
      // страница снова на экране: пока поверх лежала другая книга, им
      // была она.
      widget.services.volumeKeys.attach(_volumeHandler);
    } else {
      _volumeTurner.reset();
    }
    unawaited(widget.services.volumeKeys.setActive(active));
  }

  /// Кнопка громкости: листнуть или сказать платформе поменять громкость.
  ///
  /// F-READ-26, ALG-READ-06. Листается так же, как клавишами: в
  /// постраничном чтении — на полосу, в ленте — на страницу; выделение
  /// при этом снимается.
  VolumeKeyOutcome _onVolumeKey(VolumeKeyEvent event) {
    _refreshOnTop();
    final VolumeKeyOutcome outcome = _volumeTurner.handle(
      event,
      active: mounted && _volumeKeysActive,
      downIsForward: _volume.downIsForward,
    );
    if (outcome == VolumeKeyOutcome.forward ||
        outcome == VolumeKeyOutcome.back) {
      final bool forward = outcome == VolumeKeyOutcome.forward;
      final ReaderScaffoldState? scaffold = _scaffold.currentState;
      if (scaffold != null && scaffold.searchSteps) {
        // F-TEXT-11, решение владельца 03.10.2026: пока панель поиска
        // открыта, а страница видна, кнопки ведут по совпадениям —
        // найденное перебирается одной рукой.
        unawaited(scaffold.stepHit(forward ? 1 : -1));
      } else {
        _stepFragment(forward: forward, cause: 'volume');
      }
    }
    return outcome;
  }

  void _onPanels(bool open) {
    _panelOpen = open;
    _syncVolumeKeys();
  }

  /// Положение экрана и способ листания — настройки устройства, а не
  /// книги: держать телефон боком читатель привыкает один раз.
  Future<void> _restoreDeviceSettings() async {
    final AppSettingsRepository settings = widget.services.data.settings;
    final String? rotation = await settings.read(SettingsKeys.readingRotation);
    final String? flow = await settings.read(SettingsKeys.pageFlow);
    final String? locked = await settings.read(SettingsKeys.zoomLock);
    final String? language = await settings.read(SettingsKeys.targetLanguage);
    final String? preview = await settings.read(SettingsKeys.pagePreview);
    final String? reserve = await settings.read(SettingsKeys.pageReserve);
    final String? volume = await settings.read(SettingsKeys.volumeKeys);
    final String? volumeDown = await settings.read(
      SettingsKeys.volumeDownForward,
    );
    final String? fullScreen = await settings.read(
      SettingsKeys.readingFullScreen,
    );
    final String? tapZone = await settings.read(SettingsKeys.tapZone);
    final String? hintSeen = await settings.read(SettingsKeys.tapZoneHintSeen);
    final String? turnKeys = await settings.read(SettingsKeys.turnKeys);
    if (!mounted) {
      return;
    }
    _myLanguage = language ?? _myLanguage;
    _volume = VolumeKeySettings.parse(
      enabled: volume,
      downIsForward: volumeDown,
    );
    setState(() {
      _turning = PageTurnSettings.parse(
        preview: preview,
        reserve: reserve,
        desktop: !_canTurn,
      );
      _rotation = rotation == ScreenOrientation.landscape.name
          ? ScreenOrientation.landscape
          : ScreenOrientation.portrait;
      _flowNow.value = flow == PageFlow.continuous.name
          ? PageFlow.continuous
          : PageFlow.paged;
      _controller?.setSheetModes(enabled: _flow == PageFlow.paged);
      // Заперто по умолчанию: обычное чтение — это листание, и страница,
      // уехавшая от случайного движения двумя пальцами, читателю ничего
      // не даёт, а вернуть её он не догадается.
      _zoomLocked = locked != 'false';
      _tapZone = parseReaderTapZone(tapZone);
      _keys = KeyBindings.parse(turnKeys);
    });
    _syncVolumeKeys();
    _zoneHintSeen = hintSeen == 'true';
    _offerZoneHint();
    // Читали во весь экран — так и открываем: режим выбирают один раз,
    // а не при каждой книге.
    _fullScreenWanted = fullScreen == 'true';
    _applyWantedFullScreen();
    await _applyRotation();
  }

  /// Показана ли книга: открыта и не в ошибке.
  bool get _bookShown => _controller != null && !_loading && _failure == null;

  /// Кладёт подсказку о зонах листания поверх страницы — один раз за
  /// жизнь установки (F-READ-23).
  ///
  /// Зовётся трижды — когда прочитаны настройки, когда открылась книга и
  /// когда читатель вернулся из ленты к листам: что случится раньше,
  /// заранее неизвестно. В ленте зон нет, и подсказки там нет тоже.
  ///
  /// «Показана» записывается в тот же миг, а не по нажатию: подсказка,
  /// которую читатель не закрыл, а закрыл вместе с книгой, второй раз
  /// появиться не должна.
  void _offerZoneHint() {
    if (_zoneHintOn ||
        _zoneHintSeen != false ||
        !_bookShown ||
        _flow != PageFlow.paged) {
      return;
    }
    _zoneHintSeen = true;
    setState(() => _zoneHintOn = true);
    unawaited(
      widget.services.data.settings.write(SettingsKeys.tapZoneHintSeen, 'true'),
    );
  }

  /// Убирает подсказку о зонах: по нажатию, по `Esc` и по первому же
  /// листанию.
  void _dismissZoneHint() {
    if (_zoneHintOn && mounted) {
      setState(() => _zoneHintOn = false);
    }
  }

  /// Разворачивает окно, если читатель выбрал чтение во весь экран и
  /// книга уже на экране (F-READ-35).
  ///
  /// Зовётся дважды — когда прочитаны настройки и когда открылась книга:
  /// что из двух случится раньше, заранее неизвестно.
  void _applyWantedFullScreen() {
    if (_fullScreenWanted && _bookShown) {
      unawaited(_setFullScreen(true, remember: false));
    }
  }

  /// Разворачивает чтение во весь экран и возвращает окно.
  ///
  /// F-READ-35. Во весь экран открывается именно область чтения: окно
  /// занимает монитор целиком — без заголовка и панели задач, — а полоса
  /// вписывается в него вплотную, каким бы ни был запас по краям у
  /// книги. Режим включён, только если окно в самом деле развернулось:
  /// полоса вплотную в обычном окне — это уже другая настройка.
  ///
  /// Полоса перекладывается сразу, не дожидаясь ответа платформы: окно
  /// меняет размер раньше, чем приходит ответ, и иначе читатель успевал
  /// бы увидеть страницу в новом окне с прежним запасом по краям. Если
  /// платформа отказала, раскладка возвращается.
  Future<void> _setFullScreen(bool value, {bool remember = true}) async {
    if (!widget.services.window.available ||
        _switchingWindow ||
        value == _fullScreen) {
      return;
    }
    _switchingWindow = true;
    // F-DESK-02: разворот — не протяжка окна, его размер принимается
    // сразу, без отсчёта.
    _beginWindowJump();
    setState(() => _fullScreen = value);
    bool done = false;
    try {
      done = await widget.services.window.setFullScreen(value);
    } finally {
      _switchingWindow = false;
      _endWindowJump();
      // Платформа отказала или вызов сорвался — раскладка возвращается.
      if (!done && mounted) {
        setState(() => _fullScreen = !value);
      }
    }
    if (!mounted) {
      // Книгу закрыли раньше, чем окно развернулось: оставлять его во
      // весь экран на полке некому.
      if (done && value) {
        unawaited(widget.services.window.setFullScreen(false));
      }
      return;
    }
    if (!done) {
      return;
    }
    if (remember) {
      _fullScreenWanted = value;
      _logDeviceSetting('full_screen', value);
      await widget.services.data.settings.write(
        SettingsKeys.readingFullScreen,
        value.toString(),
      );
    }
  }

  /// Поворачивает экран сам, не спрашивая систему.
  ///
  /// Автоповорот у многих выключен насовсем, а без поворота деление
  /// страницы на полосы не даёт ровным счётом ничего: полоса той же
  /// ширины вписывается в вертикальный экран тем же масштабом, что и
  /// целая страница. Принудительная ориентация сильнее пользовательской
  /// блокировки — именно так поступают видеоплееры.
  Future<void> _applyRotation() async {
    if (!_canTurn) {
      return;
    }
    await SystemChrome.setPreferredOrientations(
      _rotation == ScreenOrientation.landscape
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  Future<void> _setRotation(ScreenOrientation rotation) async {
    if (rotation == _rotation) {
      return;
    }
    setState(() => _rotation = rotation);
    _log?.log(
      SnoEventType.viewOrientation,
      data: <String, Object?>{'orientation': rotation.name},
    );
    await widget.services.data.settings.write(
      SettingsKeys.readingRotation,
      rotation.name,
    );
    await _applyRotation();
  }

  /// Запирает и отпирает масштаб.
  ///
  /// Настройка устройства, а не книги: привычка держать страницу
  /// запертой не меняется от книги к книге.
  Future<void> _setZoomLocked(bool value) async {
    if (value == _zoomLocked) {
      return;
    }
    setState(() => _zoomLocked = value);
    _log?.log(SnoEventType.viewLock, data: <String, Object?>{'locked': value});
    await widget.services.data.settings.write(
      SettingsKeys.zoomLock,
      value.toString(),
    );
  }

  Future<void> _setFlow(PageFlow flow) async {
    if (flow == _flow) {
      return;
    }
    // В ленте разворота нет: лист там — одна страница, и подпись со
    // стрелками обязаны считать так же (F-READ-06).
    _controller?.setSheetModes(enabled: flow == PageFlow.paged);
    // Место под лист в ленте не меряется: к возвращению оно устарело.
    _window.releaseBox();
    setState(() => _flowNow.value = flow);
    // SNO-F-REC-02: способ листания — настройка устройства; место
    // чтения после смены называется журналу заново.
    _logDeviceSetting('page_flow', flow.name);
    final ReaderController? shown = _controller;
    if (shown != null) {
      final int run = _because('flow');
      _notePlace(shown);
      _dropCause(run);
    }
    // В ленте слоя подсветки нет: совпадений там не показать.
    _refreshHitRects();
    _offerZoneHint();
    // Вернулись к листам в развороте — рамка соседней страницы могла
    // остаться непосчитанной, пока шла лента.
    unawaited(_controller?.loadFrame());
    await widget.services.data.settings.write(SettingsKeys.pageFlow, flow.name);
  }

  /// Смена режима отображения заодно поворачивает чтение.
  ///
  /// Положение экрана выбирает геометрия, а не название режима: полоса
  /// страницы шире и ниже её самой, и крупнее всего она на лежащем
  /// экране. Страница режется поперёк в любой книге, на колонки деление
  /// не смотрит (BUG-13: прежде здесь было написано обратное). Режим, у
  /// которого выигрыша нет вовсе, не включается — но и не молчит:
  /// читателю говорится, почему страница осталась целой.
  Future<void> _setDisplayMode(PageDisplayMode mode) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final int run = _because('mode');
    final DisplayModeOutcome outcome = await controller.setDisplayMode(mode);
    _dropCause(run);
    if (outcome == DisplayModeOutcome.noGain) {
      _explainNoGain(mode);
      return;
    }
    // Пока область показа не измерена, поворачивать экран не по чему:
    // поворот вслепую — это ровно та ошибка, от которой уходим.
    final FragmentLayout layout = controller.layout;
    if (layout.isKnown) {
      await _setRotation(layout.orientation);
    }
  }

  /// Говорит, почему деление не включилось.
  void _explainNoGain(PageDisplayMode mode) {
    if (!mounted) {
      return;
    }
    final String fraction = mode == PageDisplayMode.third ? '⅓' : '½';
    _log?.log(
      SnoEventType.errorShown,
      data: <String, Object?>{'what': 'mode_no_gain', 'mode': mode.name},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reader-mode-no-gain'),
        duration: const Duration(seconds: 3),
        content: Text(
          'На этой странице $fraction не увеличит текст — страница '
          'осталась целой.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    // Книга закрыта — кнопки громкости снова только про громкость.
    widget.services.volumeKeys.detach(_volumeHandler);
    // И окно снова обычное: во весь экран разворачивается чтение, а не
    // полка (F-READ-35). Сама настройка при этом остаётся.
    if (_fullScreen) {
      unawaited(widget.services.window.setFullScreen(false));
    }
    _jumpTimer?.cancel();
    _selectTimer?.cancel();
    _slidTimer?.cancel();
    _moved.dispose();
    _window.dispose();
    _flowNow.dispose();
    _lifecycle?.dispose();
    unawaited(_promptsWatch?.cancel());
    _textPassTimer?.cancel();
    _texts?.close();
    _search?.dispose();
    final ReaderController? controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.close().then((_) => controller.dispose()));
    }
    super.dispose();
  }

  Future<void> _open({String? password}) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    _syncVolumeKeys();
    try {
      final ReaderController controller = await ReaderController.open(
        book: _book,
        opener: widget.services.opener,
        reading: widget.services.data.reading,
        password: password,
      );
      // BUG-09: открытие засчитывается здесь и только здесь — когда
      // книга действительно открылась. Полка его не считает: иначе одно
      // открытие считалось дважды, а книга, которая не открылась,
      // поднималась в «Сначала недавние».
      await widget.services.data.library.markOpened(_book.id, DateTime.now());
      controller.setDisplayArea(_area, canTurn: _canTurn);
      controller.setSheetModes(enabled: _flow == PageFlow.paged);
      // F-READ-02: первый кадр лучше показать уже по рамке — иначе
      // страница встаёт целиком и тут же подрезается на глазах. Но и
      // держать ради рамки пустой экран нельзя: на скане это рендер с
      // разбором. Поэтому рамку ждут недолго, а не до победного. Ленте
      // рамка не нужна вовсе — там её не ждут.
      if (_flow == PageFlow.paged) {
        await controller.settleFrame();
      } else {
        unawaited(controller.loadFrame());
      }
      if (!mounted) {
        await controller.close();
        controller.dispose();
        return;
      }
      controller.addListener(_onControllerChanged);
      // F-TEXT-04: текст страниц берётся из кэша устройства, а чего в
      // нём нет — читается движком и по дороге запоминается. Поиск от
      // этого не перечитывает книгу на каждый запрос.
      final BookTextCache texts = BookTextCache(
        document: controller.document,
        store: widget.services.data.pageTexts,
        bookId: _book.id,
        fingerprint: _book.fileHash,
        onBookRead: _bookRead,
      );
      // Найденное приходит по мере поиска: совпадения на открытой
      // странице подсвечиваются, как только до неё дошла очередь.
      final DocumentSearch search =
          DocumentSearch(document: controller.document, cache: texts)
            ..addListener(_refreshHitRects)
            // SNO-F-REC-02: законченный поиск — в журнал записи.
            ..addListener(_noteSearch);
      _texts?.close();
      _searchRan = false;
      setState(() {
        _controller = controller;
        _texts = texts;
        _search = search;
        _loading = false;
      });
      // BUG-51: всё, что уходит из выделения, идёт через одни руки.
      _actions = SelectionActions(
        controller: controller,
        annotations: widget.services.data.annotations,
        bookId: _book.id,
        texts: texts,
        log: _log,
      );
      _sayOpened(controller);
      _scheduleTextPass();
      _syncVolumeKeys();
      _applyWantedFullScreen();
      _offerZoneHint();
    } on DocumentOpenException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failure = error;
        _loading = false;
      });
      // SNO-F-REC-02: участнику показана ошибка вместо книги.
      _log?.log(
        SnoEventType.errorShown,
        data: <String, Object?>{
          'what': 'book_open',
          'problem': error.problem.name,
          'book': _book.fileHash,
        },
      );
      _syncVolumeKeys();
      // Книга не открылась: сообщение об этом во весь монитор ни к чему,
      // а выйти из режима оттуда было бы нечем — клавиши чтения живут на
      // странице. Выбор читателя при этом остаётся в силе.
      if (_fullScreen) {
        unawaited(_setFullScreen(false, remember: false));
      }
    }
  }

  /// Книга открылась: журнал записи узнаёт, какая, каким путём и на
  /// какой странице (SNO-F-REC-02).
  void _sayOpened(ReaderController controller) {
    _settingsSaid = controller.settings;
    final ActionLog? log = _log;
    if (log == null) {
      return;
    }
    if (!_openSaid) {
      _openSaid = true;
      log.bookOpened(
        _book.fileHash,
        via: widget.openedVia,
        data: <String, Object?>{
          'title': _book.title,
          'pages': controller.pageCount,
          'page': controller.page,
        },
      );
    }
    _placeSaid = null;
    final int run = _because('open');
    _notePlace(controller);
    _dropCause(run);
  }

  /// Начинает фоновый проход по тексту книги — не сразу, а дав книге
  /// открыться (F-TEXT-04, ALG-TXT-09).
  ///
  /// Первые секунды движок занят первой страницей и рамкой книги, и
  /// проход им не соперник. Идёт он от места чтения вперёд; что уже
  /// запомнено — пропускает, так что повторное открытие книги
  /// продолжает с того, на чём остановилось прошлое.
  void _scheduleTextPass() {
    _textPassTimer?.cancel();
    if (!mounted || _texts == null) {
      return;
    }
    _textPassTimer = Timer(kTextPassDelay, () {
      _textPassTimer = null;
      final ReaderController? controller = _controller;
      if (mounted && controller != null) {
        _texts?.startPass(from: controller.page);
      }
    });
  }

  /// Книга прочитана проходом целиком — признак скана сверяется с тем,
  /// что в ней нашлось на самом деле (F-DEV-13).
  ///
  /// При импорте на текст смотрят первые страницы: книгу с картинками в
  /// начале и текстом дальше он назвал бы сканом, а книгу, которую не
  /// смог прочесть, не назвал бы никак. Теперь ответ точный, и метка на
  /// обложке ему следует.
  void _bookRead(bool hasText) {
    if (!mounted || _book.hasTextLayer == hasText) {
      return;
    }
    _book = _book.copyWith(hasTextLayer: hasText);
    unawaited(widget.services.data.library.setTextLayer(_book.id, hasText));
  }

  /// Останавливает фоновый проход: приложение свернули.
  void _stopTextPass() {
    _textPassTimer?.cancel();
    _textPassTimer = null;
    _texts?.stopPass();
  }

  /// Привязывает книгу к заново выбранному файлу.
  ///
  /// Файл переименовали, унесли карту памяти, отозвали разрешение на
  /// ссылку — книга при этом никуда не делась: место чтения, цитаты и
  /// заметки принадлежат ей, а не файлу. Поэтому «файл недоступен» — это
  /// не тупик с кнопкой «назад», а предложение показать файл заново.
  ///
  /// BUG-19: файл при этом обязан быть тем же. Если отпечаток не совпал,
  /// читатель спрошен ([_confirmOtherFile]); отказался — книга остаётся
  /// как была, и экран возвращается к прежнему сообщению.
  Future<void> _relink() async {
    final PickedFile? file = await widget.services.picker.pickPdf();
    if (file == null || !mounted) {
      return;
    }
    final DocumentOpenException? before = _failure;
    // Ждём — колесо; не ждём — прежнее сообщение о том, что случилось.
    void waiting(bool on) {
      if (mounted) {
        setState(() {
          _loading = on;
          _failure = on ? null : before;
        });
      }
    }

    waiting(true);
    final BookImporter importer = BookImporter(
      library: widget.services.data.library,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
    try {
      _book = await importer.relink(
        _book,
        file,
        onMismatch: (RelinkMismatch mismatch) async {
          // Пока читатель думает, ждать нечего: под вопросом стоит
          // прежний экран, а не колесо, которое ничего не делает.
          waiting(false);
          final bool agreed = await _confirmOtherFile(mismatch);
          if (agreed) {
            waiting(true);
          }
          return agreed;
        },
      );
    } on RelinkRefused {
      waiting(false);
      return;
    } on DocumentOpenException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _loading = false;
        });
      }
      return;
    } on Object {
      // Файл не приняли или не записали — что угодно, кроме «не
      // открылся». Колесо не должно остаться навсегда: возвращается
      // прежний экран, и сказано, что случилось.
      waiting(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Этот файл не удалось прочесть')),
        );
      }
      return;
    }
    if (mounted) {
      await _open();
    }
  }

  /// Спрашивает, привязать ли книгу к файлу с другим отпечатком (BUG-19).
  ///
  /// Ответа «да» по умолчанию нет: закрытый мимо кнопок вопрос — отказ.
  Future<bool> _confirmOtherFile(RelinkMismatch mismatch) async {
    if (!mounted) {
      return false;
    }
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('relink-mismatch'),
        title: const Text('Это другой файл'),
        content: SingleChildScrollView(
          child: Text(describeRelinkMismatch(mismatch)),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('relink-pick-other'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Выбрать другой'),
          ),
          FilledButton(
            key: const Key('relink-force'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Привязать всё равно'),
          ),
        ],
      ),
    );
    return agreed ?? false;
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    // SNO-F-REC-02: показ страницы и настройки книги — в журнал записи.
    final ReaderController? current = _controller;
    if (current != null) {
      _notePlace(current);
      _noteSettings(current);
    }
    // Читатель ушёл со страницы — подсветке нечего показывать: текста, к
    // которому она относилась, на экране больше нет.
    final _PageMark? mark = _mark;
    if (mark != null && mark.pageNumber != _controller?.page) {
      _mark = null;
      _markRects = const <TextBox>[];
    }
    setState(() {});
    _refreshHitRects();
  }

  /// Пересчитывает, где на страницах листа лежат совпадения запроса.
  ///
  /// F-TEXT-11: пока поиск открыт, на странице подсвечены все совпадения,
  /// а не одно — читатель оценивает найденное, не перебирая его по
  /// одному. Зовётся на каждое сообщение поиска и контроллера, поэтому
  /// сначала проверяет, изменилось ли что-нибудь: запрос, лист или число
  /// совпадений на нём.
  void _refreshHitRects() {
    final ReaderController? controller = _controller;
    final DocumentSearch? search = _search;
    if (!mounted || controller == null || search == null) {
      return;
    }
    // Запрос сменился — отметка найденного по прежнему запросу уходит:
    // яркая подсветка слова, которое уже не ищут, только путала бы.
    final String? marked = _markQuery;
    if (marked != null && marked != search.query) {
      _markQuery = null;
      setState(() {
        _mark = null;
        _markRects = const <TextBox>[];
      });
    }
    final List<int> pages = controller.sheetPages;
    final bool shown = _searchShown && _flow == PageFlow.paged;
    final List<SearchHit> hits = <SearchHit>[
      if (shown)
        for (final SearchHit hit in search.hits)
          if (pages.contains(hit.pageNumber)) hit,
    ];
    final String wanted = '${search.query}\n${pages.join(',')}\n${hits.length}';
    if (wanted == _hitRectsFor) {
      return;
    }
    _hitRectsFor = wanted;
    final int run = ++_hitRectsRun;
    if (hits.isEmpty) {
      if (_hitRects.isNotEmpty) {
        setState(() => _hitRects = const <_HitRects>[]);
      }
      return;
    }
    unawaited(_loadHitRects(controller, run, hits));
  }

  Future<void> _loadHitRects(
    ReaderController controller,
    int run,
    List<SearchHit> hits,
  ) async {
    final List<_HitRects> found = <_HitRects>[];
    // Страница, на которой слово встречается сотню раз, сотни подсветок
    // не требует: за потолком найденное всё равно видно в списке.
    for (final SearchHit hit in hits.take(_maxHitRects)) {
      final List<TextBox> boxes;
      try {
        boxes = await controller.highlightFor(
          pageNumber: hit.pageNumber,
          start: hit.sourceStart,
          end: hit.sourceEnd,
        );
      } on Object {
        // Книгу закрыли или страницу не удалось разобрать: подсветка —
        // не то, ради чего стоит ронять чтение.
        return;
      }
      if (!mounted || run != _hitRectsRun) {
        return;
      }
      if (boxes.isNotEmpty) {
        found.add(
          _HitRects(
            pageNumber: hit.pageNumber,
            start: hit.sourceStart,
            boxes: boxes,
          ),
        );
      }
    }
    setState(() => _hitRects = found);
  }

  /// Сколько совпадений одного листа подсвечивается, не больше.
  static const int _maxHitRects = 80;

  /// Снять выделение вместе с панелью.
  ///
  /// Выделение живёт внутри просмотрщика — он же его и рисует, — поэтому
  /// снимается оно там, а панель уходит вместе с ним.
  void _dismissSelection() {
    _sheet.clearSelection();
    if (_selection == null) {
      return;
    }
    _noteSelectionGone();
    setState(() => _selection = null);
  }

  /// `Esc`, когда закрывать больше нечего: уходит подсказка о зонах и
  /// снимается выделение.
  void _onDismissKey() {
    _dismissZoneHint();
    _dismissSelection();
  }

  Future<void> _onSelectionRanges(List<PdfPageTextRange> ranges) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (ranges.isEmpty) {
      if (mounted && _selection != null) {
        _noteSelectionGone();
        setState(() => _selection = null);
      }
      return;
    }
    // Берётся первый кусок: на листе видна одна страница или разворот, и
    // выделение через границу страниц — редкость, ради которой не стоит
    // усложнять панель. Текст при этом склеивается весь.
    final PdfPageTextRange range = ranges.first;
    final String text = ranges
        .map((PdfPageTextRange part) => part.text)
        .join(' ')
        .trim();
    // BUG-25: прямоугольники выделения берутся и у самого просмотрщика.
    // Когда наш слой текста с его разбором не сошёлся, панель встаёт по
    // ним — прежде она в этом случае не появлялась вовсе.
    final Object? engine = controller.document.engineDocument;
    final int pageNumber = range.pageNumber;
    final List<TextBox> viewerRects =
        engine is PdfDocument &&
            pageNumber >= 1 &&
            pageNumber <= engine.pages.length
        ? viewerSelectionBoxes(ranges, engine.pages[pageNumber - 1])
        : const <TextBox>[];
    final BookSelection selection = await controller.selectionFrom(
      pageNumber: pageNumber,
      start: range.start,
      end: range.end,
      located: range.text,
      text: text,
      viewerRects: viewerRects,
    );
    if (!mounted) {
      return;
    }
    final BookSelection? next = selection.isEmpty ? null : selection;
    // SNO-F-REC-02: журнал записи узнаёт о выделении, когда оно
    // устоялось, и о том, что его сняли.
    if (next == null) {
      if (_selection != null) {
        _noteSelectionGone();
      }
    } else if (next != _selection) {
      _noteSelection(next);
    }
    setState(() => _selection = next);
  }

  /// Нажали на промпт читателя.
  ///
  /// Модели ещё нет — она появится в S8. Кнопка при этом не молчит:
  /// показывается готовый запрос со всеми подстановками. Заодно это
  /// единственный способ увидеть глазами, тот ли абзац достался
  /// контекстом.
  /// Идёт ли действие над выделением: текст выделения с переносом
  /// считается по книге, и второе нажатие той же кнопки, пришедшее за
  /// это время, вторым действием не становится — две цитаты, два окна
  /// заметки.
  bool _acting = false;

  Future<void> _once(Future<void> Function() action) async {
    if (_acting) {
      return;
    }
    _acting = true;
    try {
      await action();
    } finally {
      _acting = false;
    }
  }

  Future<void> _onPrompt(SelectionPrompt prompt) {
    return _once(() => _prompt(prompt));
  }

  Future<void> _prompt(SelectionPrompt prompt) async {
    final BookSelection? selection = _selection;
    final SelectionActions? actions = _actions;
    if (selection == null || actions == null) {
      return;
    }
    await _logAction(
      'prompt',
      selection,
      extra: <String, Object?>{'prompt': prompt.name},
    );
    // BUG-51: выделенное и абзац уходят в запрос без знака переноса.
    final String request = await actions.request(
      selection,
      prompt,
      bookLanguage: _book.language,
      myLanguage: _myLanguage,
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) =>
          PromptPreviewSheet(prompt: prompt, request: request),
    );
    _refreshOnTop();
  }

  /// Сохраняет выделенное цитатой (BUG-51: без знака переноса — текст
  /// и абзац вокруг него берутся у [SelectionActions]).
  Future<void> _onQuote() => _once(_quote);

  Future<void> _quote() async {
    final BookSelection? selection = _selection;
    final SelectionActions? actions = _actions;
    if (selection == null || actions == null) {
      return;
    }
    await _logAction('quote', selection);
    await actions.saveQuote(selection);
    if (!mounted) {
      return;
    }
    _dismissSelection();
    _say('Цитата сохранена');
  }

  /// Заметка пишется к месту, а не в пустоту.
  ///
  /// Поэтому вместе с ней сохраняется и сама цитата: заметка «здесь автор
  /// себе противоречит» без того, чему она противоречит, через месяц не
  /// значит ничего. Цитата заводится **после** того, как читатель написал
  /// заметку: отменённое окно не должно оставлять за собой следов.
  Future<void> _onNote() => _once(_note);

  Future<void> _note() async {
    final BookSelection? selection = _selection;
    final SelectionActions? actions = _actions;
    if (selection == null || actions == null) {
      return;
    }
    await _logAction('note', selection);
    // BUG-51: в окне заметки цитата показана такой, какой сохранится.
    final String quoted = await actions.textOf(selection);
    if (!mounted) {
      return;
    }
    final String? body = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => NoteDialog(quote: quoted),
    );
    _refreshOnTop();
    if (body == null || !mounted) {
      return;
    }
    await actions.saveNote(selection, body, text: quoted);
    if (!mounted) {
      return;
    }
    _dismissSelection();
    _say('Заметка сохранена');
  }

  Future<void> _onCopy() => _once(_copy);

  Future<void> _copy() async {
    final BookSelection? selection = _selection;
    final SelectionActions? actions = _actions;
    if (selection == null || actions == null) {
      return;
    }
    await _logAction('copy', selection);
    // BUG-51: в буфер обмена текст уходит без знака переноса.
    final String text = await actions.textOf(selection);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _dismissSelection();
    _say('Скопировано');
  }

  /// «Найти в книге»: выделенное становится запросом поиска по книге.
  ///
  /// SNO-F-READ-01. Запросы собирает [selectionSearchQueries]; поиск
  /// открывает обвязка экрана — сразу со списком найденного, а текущим
  /// делает совпадение на месте выделения.
  Future<void> _onFind() async {
    final BookSelection? selection = _selection;
    final ReaderScaffoldState? scaffold = _scaffold.currentState;
    if (selection == null || scaffold == null) {
      return;
    }
    final List<String> queries = selectionSearchQueries(selection.text);
    if (queries.isEmpty || !isSearchableQuery(queries.first)) {
      _say('Для поиска выделите хотя бы два знака');
      return;
    }
    await _logAction('find', selection);
    if (!mounted) {
      return;
    }
    _dismissSelection();
    await scaffold.findInBook(
      queries,
      pageNumber: selection.pageNumber,
      start: selection.start,
      end: selection.end,
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Переход к найденному с подсветкой самого совпадения.
  ///
  /// Долг S3: список результатов был, а подсветки на странице не было —
  /// координаты символов появились только в S4, а перевод «место в тексте
  /// → прямоугольник» написан в S6.
  Future<void> _goToHit(SearchHit hit) async {
    await _showMark(
      page: hit.pageNumber,
      start: hit.sourceStart,
      end: hit.sourceEnd,
      query: _search?.query,
    );
  }

  /// Прямоугольники отмеченного места; пусто, если их нет или страницу
  /// не удалось разобрать. Не бросает: подсветка — не то, ради чего
  /// стоит срывать переход.
  Future<List<TextBox>> _markRectsOf(
    ReaderController controller,
    _PageMark mark,
  ) async {
    try {
      return await controller.highlightFor(
        pageNumber: mark.pageNumber,
        start: mark.start,
        end: mark.end,
      );
    } on Object {
      return const <TextBox>[];
    }
  }

  /// Открывает страницу и подсвечивает на ней кусок текста.
  ///
  /// Подсветка **держится**, пока читатель на этой странице: она отвечает
  /// на вопрос «где здесь то, что я искал», и первое же касание экрана
  /// этого ответа не отменяет (правка по проверке S6: прежде подсветка
  /// пропадала от любого нажатия, и найти её снова было нечем).
  ///
  /// Без координат — просто переход на страницу. Так открываются старые
  /// цитаты, сохранённые до схемы 8: подсвечивать у них нечего, и делать
  /// вид, что есть, нечестно.
  ///
  /// [query] — запрос, по которому место найдено; у цитаты его нет.
  Future<void> _showMark({
    required int page,
    required int? start,
    required int? end,
    String? query,
  }) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final int run = ++_markRun;
    final int? from = start;
    final int? to = end;
    final _PageMark? mark = from == null || to == null || to <= from
        ? null
        : _PageMark(pageNumber: page, start: from, end: to);
    // BUG-10: прямоугольники отмеченного нужны до перехода — по первому
    // из них выбирается полоса, в которой оно лежит. Прежде переход
    // всегда вёл в первую полосу страницы: в ½ и ⅓ найденное оставалось
    // в тени или за экраном, а читателя, уже стоявшего на этой странице,
    // возвращало к её началу.
    //
    // Ждут их недолго ([_revealWait]): разбор тяжёлой страницы не должен
    // держать читателя на прежней (BUG-23). Не успели — переход идёт в
    // начало страницы, а полоса и подсветка встают, когда досчитаются.
    // Читателя, который уже на этой странице, держать не на чем и
    // возвращать к её началу нельзя: тут прямоугольники ждут до конца.
    final Future<List<TextBox>> loading = mark == null
        ? Future<List<TextBox>>.value(const <TextBox>[])
        : _markRectsOf(controller, mark);
    List<TextBox> rects = controller.page == page
        ? await loading
        : await loading.timeout(
            _revealWait,
            onTimeout: () => const <TextBox>[],
          );
    if (!mounted || run != _markRun) {
      return;
    }
    // Переход обогнали — читатель уже ушёл дальше, и отмечать на
    // странице, которой нет на экране, нечего (BUG-11).
    final bool arrived = await _goToPage(
      page,
      reveal: rects.isEmpty ? null : rects.first,
    );
    if (!arrived || !mounted || run != _markRun) {
      return;
    }
    if (rects.isEmpty) {
      rects = await loading;
      if (!mounted || run != _markRun || controller.page != page) {
        return;
      }
      // Досчитались уже после перехода: полоса выбирается теперь.
      if (rects.isNotEmpty) {
        final bool shown = await _goToPage(page, reveal: rects.first);
        if (!shown || !mounted || run != _markRun) {
          return;
        }
      }
    }
    setState(() {
      _mark = mark;
      _markRects = rects;
      _markQuery = mark == null ? null : query;
    });
  }

  /// Сколько переход к найденному ждёт его прямоугольники, прежде чем
  /// открыть страницу без них. Четверть секунды читатель не замечает, а
  /// страница с текстом за это время разбирается почти всегда.
  static const Duration _revealWait = Duration(milliseconds: 250);

  /// Экран «Цитаты и заметки» и возвращение из него в книгу.
  ///
  /// Карточка отвечает на вопрос «а где это было»: экран закрывается,
  /// книга открывается на своей странице, сама цитата подсвечена.
  Future<void> _openAnnotations() async {
    _log?.log(SnoEventType.annotationsOpen);
    final AnnotationTarget? target = await Navigator.of(context)
        .push<AnnotationTarget>(
          MaterialPageRoute<AnnotationTarget>(
            builder: (BuildContext context) => AnnotationsScreen(
              book: _book,
              annotations: widget.services.data.annotations,
              log: _log,
            ),
          ),
        );
    _refreshOnTop();
    _log?.log(
      SnoEventType.panelClose,
      data: const <String, Object?>{'panel': 'annotations'},
    );
    if (target == null || !mounted) {
      return;
    }
    _dismissSelection();
    _log?.log(
      SnoEventType.annotationJump,
      data: <String, Object?>{'page': target.page},
    );
    final int run = _because('annotation');
    await _showMark(
      page: target.page,
      start: target.textStart,
      end: target.textEnd,
    );
    _dropCause(run);
  }

  /// Переход на страницу; `false` — его обогнал следующий (BUG-11).
  ///
  /// Ленту довозим только до страницы, на которую переход состоялся:
  /// иначе устаревший переход увёз бы её туда, откуда читатель уже ушёл.
  ///
  /// [reveal] — место на странице, которое надо показать: переход ведёт
  /// в ту полосу, где оно лежит (BUG-10).
  Future<bool> _goToPage(int page, {TextBox? reveal}) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return false;
    }
    if (!await controller.goToPage(page, reveal: reveal)) {
      return false;
    }
    if (_flow == PageFlow.continuous && _viewer.isReady) {
      await _viewer.goToPage(pageNumber: page);
    }
    return true;
  }

  /// Нажатие по странице: переход к соседнему фрагменту или панели.
  ///
  /// Зоны всегда слева и справа, в любом режиме и в любом положении
  /// экрана. Пробовали привязать их к направлению деления — читатель
  /// каждый раз вспоминал, куда нажимать в этом режиме. Привычка «вправо
  /// значит дальше» сильнее любой логики раскладки.
  ///
  /// **Пока текст выделен, нажатие не листает**, а снимает выделение —
  /// где бы ни пришлось (F-READ-22, решение владельца 03.10.2026;
  /// отменяет решение 06.09.2026). Выделено ли что-нибудь, спрашивается
  /// и у просмотрщика ([selecting]), и у себя: просмотрщик узнаёт о
  /// выделении раньше, чем экран успевает его разобрать. Стрелки панели,
  /// клавиши и кнопки громкости листают и при выделении.
  void _onTap(
    Offset position,
    Size size,
    VoidCallback toggleChrome, {
    required bool selecting,
  }) {
    // F-TEXT-11: нажали по странице — клавиши возвращаются к ней из поля
    // поиска.
    _scaffold.currentState?.focusPage();
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged || size.width <= 0) {
      toggleChrome();
      return;
    }
    final ReaderTap action = readerTapAt(
      share: position.dx / size.width,
      selecting: selecting || _selection != null,
      // F-READ-23: ширину зоны выбирает читатель.
      zone: _tapZone,
    );
    switch (action) {
      case ReaderTap.previousFragment:
        _dismissSelection();
        _turn('tap_zone', controller.previousFragment);
      case ReaderTap.nextFragment:
        _dismissSelection();
        _turn('tap_zone', controller.nextFragment);
      case ReaderTap.dismissSelection:
        _dismissSelection();
      case ReaderTap.toggleChrome:
        toggleChrome();
    }
  }

  /// Листание клавишами: то же самое, что зонами.
  ///
  /// В ленте фрагментов нет, там шаг — страница, и просмотрщик обязан
  /// доехать до неё сам: иначе номер страницы уехал бы, а лента осталась
  /// на месте.
  ///
  /// [cause] — чем листают: клавишей или кнопкой громкости; это пишет
  /// журнал записи (SNO-F-REC-02).
  void _stepFragment({required bool forward, String cause = 'key'}) {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    // Читатель листает клавишей или кнопкой — подсказка о зонах ему уже
    // не нужна (F-READ-23).
    _dismissZoneHint();
    _dismissSelection();
    if (_flow == PageFlow.continuous) {
      // Цель считает контроллер: он знает, куда ведёт ещё не законченный
      // переход, и два быстрых нажатия дают два шага (BUG-11).
      final int? target = forward
          ? controller.nextSheetStart
          : controller.previousSheetStart;
      if (target != null) {
        _turn(cause, () => _goToPage(target));
      }
      return;
    }
    _turn(
      cause,
      forward ? controller.nextFragment : controller.previousFragment,
    );
  }

  /// Листает действием [step] и называет журналу причину [cause]
  /// (SNO-F-REC-02). Листать некуда — причина снимается.
  void _turn(String cause, Future<bool> Function() step) {
    final int run = _because(cause);
    unawaited(step().whenComplete(() => _dropCause(run)));
  }

  Future<void> _openSettings() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    _log?.log(
      SnoEventType.panelOpen,
      data: const <String, Object?>{'panel': 'reader_settings'},
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ReaderSettingsSheet(
          controller: controller,
          flow: _flowNow,
          onFlow: (PageFlow value) => unawaited(_setFlow(value)),
          onDisplayMode: (PageDisplayMode mode) =>
              unawaited(_setDisplayMode(mode)),
          onEditCrop: () {
            Navigator.of(context).pop();
            unawaited(_editCrop());
          },
        );
      },
    );
    _refreshOnTop();
    // SNO-F-REC-02: ползунки шторки — в журнал до события о её закрытии.
    _logSlid();
    _log?.log(
      SnoEventType.panelClose,
      data: const <String, Object?>{'panel': 'reader_settings'},
    );
    // Шторку могли смахнуть, не отпустив ползунок: его значение уже на
    // странице, а в базу ещё не записано (BUG-12).
    await controller.persistSettings();
  }

  Future<void> _editCrop() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    _log?.log(
      SnoEventType.panelOpen,
      data: const <String, Object?>{'panel': 'crop_editor'},
    );
    final CropBox? box = await Navigator.of(context).push<CropBox>(
      MaterialPageRoute<CropBox>(
        builder: (BuildContext context) => CropEditorScreen(
          document: controller.document,
          pageNumber: controller.page,
          // Рамка страницы, а не листа: редактор показывает одну
          // страницу, а в развороте рамка листа записана в его долях.
          initial: controller.pageContentBox,
        ),
      ),
    );
    _refreshOnTop();
    _log?.log(
      SnoEventType.panelClose,
      data: <String, Object?>{'panel': 'crop_editor', 'saved': box != null},
    );
    if (box != null) {
      await controller.setManualCrop(box);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('reader-loading')),
        ),
      );
    }
    final DocumentOpenException? failure = _failure;
    if (failure != null) {
      return _FailureScreen(
        failure: failure,
        onPassword: (String password) => unawaited(_open(password: password)),
        // BUG-46: в сборке ветви выбора файла нет вовсе.
        onRelink: widget.canRelink ? () => unawaited(_relink()) : null,
      );
    }

    final ReaderController controller = _controller!;
    return ReaderScaffold(
      key: _scaffold,
      controller: controller,
      search: _search!,
      onGoToPage: _goToPage,
      onGoToHit: _goToHit,
      onPreviousFragment: () => _stepFragment(forward: false),
      onNextFragment: () => _stepFragment(forward: true),
      onDismiss: _onDismissKey,
      onPanelsChanged: _onPanels,
      onSearchOpen: _onSearchOpen,
      onSearchDock: _onSearchDock,
      // SNO-F-REC-02: обвязка пишет в журнал записи своё — оглавление,
      // ползунок, поиск, панели — и говорит, чем вызван переход.
      log: _log,
      onTurnCause: _because,
      selecting: () => _selection != null || _sheet.selecting,
      fullScreen: _fullScreen,
      onFullScreen: widget.services.window.available
          ? (bool value) => unawaited(_setFullScreen(value))
          : null,
      keyBindings: _keys,
      extraActions: <Widget>[
        IconButton(
          key: const Key('reader-annotations-button'),
          icon: const Icon(Icons.format_quote),
          tooltip: 'Цитаты и заметки',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_openAnnotations()),
        ),
        // BUG-15: деление страницы и замок действуют только на листе. В
        // ленте их нет вовсе: кнопка, которая ничего не делает, обманывает,
        // а дробь там ещё и поворачивала телефон.
        if (_flow == PageFlow.paged) ...<Widget>[
          // Деление страницы стоит там, где им пользуются, — на странице,
          // а не в панели настроек: это способ читать, а не настройка.
          DisplayModeButtons(
            mode: controller.settings.displayMode,
            onMode: (PageDisplayMode mode) => unawaited(_setDisplayMode(mode)),
            // Дробь, которая на этой книге не увеличит текст, показана
            // погасшей: обещать увеличение и не дать его — хуже, чем
            // честно сказать заранее.
            gainless: <PageDisplayMode>{
              for (final PageDisplayMode mode in <PageDisplayMode>[
                PageDisplayMode.half,
                PageDisplayMode.third,
              ])
                if (!controller.layoutFor(mode).isWorthwhile) mode,
            },
          ),
          IconButton(
            key: const Key('reader-zoom-lock-button'),
            icon: Icon(_zoomLocked ? Icons.lock_outline : Icons.lock_open),
            tooltip: _zoomLocked
                ? 'Разрешить двигать и масштабировать страницу'
                : 'Запереть масштаб',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(_setZoomLocked(!_zoomLocked)),
          ),
        ],
        // Поворот есть только там, где он что-то делает. На ПК форму окна
        // выбирает человек, а `setPreferredOrientations` не делает ничего:
        // кнопка-обманка хуже её отсутствия.
        if (_canTurn)
          IconButton(
            key: const Key('reader-rotation-button'),
            icon: Icon(
              _rotation == ScreenOrientation.landscape
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
            ),
            tooltip: _rotation == ScreenOrientation.landscape
                ? 'Читать вертикально'
                : 'Читать горизонтально',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(
              _setRotation(
                _rotation == ScreenOrientation.landscape
                    ? ScreenOrientation.portrait
                    : ScreenOrientation.landscape,
              ),
            ),
          ),
        // Во весь экран — только там, где у приложения есть окно: на
        // телефоне страница и так занимает экран целиком (F-READ-35).
        if (widget.services.window.available)
          IconButton(
            key: const Key('reader-full-screen-button'),
            icon: Icon(_fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: _fullScreen ? 'Вернуть окно (F11)' : 'Во весь экран (F11)',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(_setFullScreen(!_fullScreen)),
          ),
        IconButton(
          key: const Key('reader-settings-button'),
          icon: const Icon(Icons.tune),
          tooltip: 'Рамка и светофильтр',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_openSettings()),
        ),
      ],
      viewerBuilder: (BuildContext context, VoidCallback onTap) {
        final Widget page = AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, Widget? child) {
            // BUG-04: в постраничном чтении фильтр кладёт на страницу сам
            // лист — под маской, подсветкой и панелями. Оборачивать его
            // здесь целиком значило бы красить фильтром и их.
            if (child == null) {
              return _buildSheet(context, controller, onTap);
            }
            return ReadingFilterLayer(
              filter: controller.filter,
              // Лента строится один раз и передаётся мимо перестроений:
              // пересоздавать просмотрщик на каждое уведомление значило бы
              // терять место прокрутки под руками у читателя.
              child: child,
            );
          },
          child: _flow == PageFlow.continuous
              ? _buildRibbon(context, controller, onTap)
              : null,
        );
        // F-READ-23: подсказка о зонах лежит поверх страницы, но под
        // панелями. Страница при этом стоит в дереве на одном и том же
        // месте, с подсказкой и без неё.
        return Stack(
          children: <Widget>[
            Positioned.fill(child: page),
            if (_zoneHintOn && _flow == PageFlow.paged)
              Positioned.fill(
                child: TapZoneHint(
                  zone: _tapZone,
                  keyboard: widget.services.window.available,
                  onDismiss: _dismissZoneHint,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Чтение по страницам: жёсткая раскладка, страница целиком.
  ///
  /// Лист кладётся так, что читаемая часть занимает экран, а остальная
  /// страница гаснет вокруг неё. Масштаб один и тот же на каждой странице
  /// книги — пока замок заперт. Отперев его, читатель двигает и
  /// масштабирует страницу как в обычном просмотрщике, и она остаётся в
  /// том виде, в каком он её оставил.
  ///
  /// Жестов здесь больше нет: страницу рисует просмотрщик, он же
  /// разводит выделение с перемещением и отдаёт выделенный диапазон.
  /// Нажатие лист узнаёт сам, не дожидаясь просмотрщика (BUG-37).
  Widget _buildSheet(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    final Color background = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limits) {
        // F-DESK-02: пока окно на ПК тянут, лист раскладывается по
        // прежнему размеру, а по новому — один раз, когда окно отпустили.
        final Size size = _window.offerBox(
          Size(limits.maxWidth, limits.maxHeight),
          hold: _holdsWindow,
        );
        // Рисуем тем же документом, который уже открыл контроллер:
        // второе открытие той же книги стоило вдвое больше памяти, а на
        // большой книге отдавало страницы не сразу — и вместо содержимого
        // читатель видел пустой экран.
        final Object? engine = controller.document.engineDocument;
        final PdfDocument? document = engine is PdfDocument ? engine : null;
        final List<int> pages = controller.sheetPages;
        return ColoredBox(
          color: background,
          child: HeldBox(
            key: const Key('reader-sheet-box'),
            size: size,
            child: document == null
                ? const SizedBox.expand()
                : _sheetOf(controller, document, pages, size, onTap),
          ),
        );
      },
    );
  }

  /// Сам лист — в размере, который держит [HeldBox].
  Widget _sheetOf(
    ReaderController controller,
    PdfDocument document,
    List<int> pages,
    Size size,
    VoidCallback onTap,
  ) {
    final BookReadingSettings settings = controller.settings;
    final PageDisplayMode mode = settings.displayMode;
    return ReaderSheet(
      document: document,
      pages: pages,
      fragment: controller.fragmentBox,
      background: Theme.of(context).colorScheme.surface,
      // BUG-04: фильтр — только на картинку страницы.
      filter: controller.filter,
      // F-READ-12: в режимах с полосами листы лежат в столбик, и под
      // последней полосой страницы виден верх следующей.
      arrangement: arrangementFor(mode),
      spread: isSpreadMode(mode),
      overlap: stripOverlapFor(
        overlap: settings.stripOverlap,
        count: fragmentCountFor(mode: mode),
      ),
      // F-READ-13: соседняя страница видна полоской заданной ширины.
      neighbourShare: settings.neighbourShare,
      // Указатель места считает по правой странице разворота: она тоже
      // открыта, и процент в панели считается так же.
      page: controller.lastShownPage,
      pageCount: controller.pageCount,
      locked: _zoomLocked,
      // F-READ-35: во весь экран полоса вписана вплотную, и указатель
      // места поверх страницы не ложится.
      stripFit: stripFitFor(
        stripFit: settings.stripFit,
        fullScreen: _fullScreen,
      ),
      progressOverPage: !_fullScreen,
      dim: settings.dimOutside,
      preview: _turning.preview,
      reserve: _turning.effectiveReserve,
      sheetController: _sheet,
      onSelection: (List<PdfPageTextRange> ranges) =>
          unawaited(_onSelectionRanges(ranges)),
      onTap: (Offset at, {required bool selecting}) =>
          _onTap(at, size, onTap, selecting: selecting),
      // SNO-F-REC-02: масштаб и сдвиг страницы — в журнал записи.
      onMoved: _log == null ? null : _moved.add,
      overlay: (BuildContext context, SheetView view) =>
          _buildOverlay(context, view, document, pages, size),
    );
  }

  /// Что лежит поверх листа: подсветка найденного и панель действий.
  ///
  /// И то, и другое живёт в координатах страницы, а рисуется на экране,
  /// поэтому обоим нужен [SheetView] — раскладка листа плюс щипок
  /// читателя. Считать это в самом листе нельзя: он не знает ни про
  /// поиск, ни про промпты.
  Widget _buildOverlay(
    BuildContext context,
    SheetView view,
    PdfDocument document,
    List<int> pages,
    Size size,
  ) {
    final ThemeData theme = Theme.of(context);
    final BookSelection? selection = _selection;
    final _PageMark? mark = _mark;
    final List<Rect> found = mark == null || !pages.contains(mark.pageNumber)
        ? const <Rect>[]
        : _screenRects(view, document, pages, mark.pageNumber, _markRects);
    // F-TEXT-11: остальные совпадения запроса — бледнее текущего.
    final List<Rect> others = <Rect>[
      for (final _HitRects hit in _hitRects)
        if (pages.contains(hit.pageNumber) && !hit.isAt(mark))
          ..._screenRects(view, document, pages, hit.pageNumber, hit.boxes),
    ];
    final List<Rect> selected = selection == null
        ? const <Rect>[]
        : _screenRects(
            view,
            document,
            pages,
            selection.pageNumber,
            selection.rects,
          );
    return Stack(
      children: <Widget>[
        if (others.isNotEmpty)
          Positioned.fill(
            child: HighlightLayer(
              rects: others,
              color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
              others: true,
            ),
          ),
        if (found.isNotEmpty)
          Positioned.fill(
            child: HighlightLayer(
              rects: found,
              color: theme.colorScheme.tertiary.withValues(alpha: 0.35),
            ),
          ),
        // BUG-25: выделение на этом листе есть — панель есть. Нет
        // прямоугольников — она встаёт посередине листа, а не пропадает.
        if (selection != null && pages.contains(selection.pageNumber))
          // SNO-F-READ-01: без модели промптов над выделением нет, а
          // четвёртым действием стоит «Найти в книге».
          SelectionPanel.forReader(
            anchor: panelAnchor(rects: selected, area: size),
            models: widget.models,
            prompts: _prompts,
            onPrompt: (SelectionPrompt prompt) => unawaited(_onPrompt(prompt)),
            onQuote: () => unawaited(_onQuote()),
            onNote: () => unawaited(_onNote()),
            onCopy: () => unawaited(_onCopy()),
            onFind: () => unawaited(_onFind()),
          ),
      ],
    );
  }

  /// Переводит прямоугольники страницы в прямоугольники экрана.
  ///
  /// Страница лежит внутри листа: в развороте вторая страница начинается
  /// там, где кончилась первая. Поэтому смещение считается по ширинам
  /// страниц листа, а не по номеру страницы в книге.
  List<Rect> _screenRects(
    SheetView view,
    PdfDocument document,
    List<int> pages,
    int pageNumber,
    List<TextBox> boxes,
  ) {
    if (boxes.isEmpty) {
      return const <Rect>[];
    }
    double left = 0;
    PdfPage? target;
    for (final int number in pages) {
      if (number < 1 || number > document.pages.length) {
        continue;
      }
      final PdfPage page = document.pages[number - 1];
      if (number == pageNumber) {
        target = page;
        break;
      }
      left += page.width;
    }
    if (target == null) {
      return const <Rect>[];
    }
    final double width = target.width;
    final double height = target.height;
    return <Rect>[
      for (final TextBox box in boxes)
        Rect.fromPoints(
          view.toScreen(left + box.left * width, box.top * height),
          view.toScreen(left + box.right * width, box.bottom * height),
        ),
    ];
  }

  /// Непрерывная лента: свободное чтение с зумом и прокруткой.
  ///
  /// Здесь читатель сам решает, что и как разглядывать, поэтому режимы
  /// отображения в ленте не действуют — это другой способ читать.
  Widget _buildRibbon(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    // Тем же документом, который уже открыл контроллер. Прежде лента
    // открывала книгу по пути во второй раз — но у документа Android
    // пути нет вовсе, а второе открытие большой книги и без того стоило
    // вдвое больше памяти. `autoDispose: false` потому, что закрывает
    // документ контроллер: он его и открыл.
    final Object? engine = controller.document.engineDocument;
    final PdfDocument? document = engine is PdfDocument ? engine : null;
    if (document == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: const SizedBox.expand(),
      );
    }
    // BUG-38: нажатие узнаём сами, в миг, когда указатель поднят, — как
    // на листе (BUG-37). Слушатель только смотрит на указатель и ничего
    // у просмотрщика не отбирает: прокрутка, щипок и выделение живут
    // как жили.
    return QuickTap(
      watch: _ribbonTaps,
      onTap: (Offset at) => _onRibbonTap(onTap),
      child: _buildRibbonViewer(context, controller, document, onTap),
    );
  }

  /// Нажатие в ленте, которое мы узнали сами: показать или спрятать
  /// панели.
  ///
  /// Кроме одного случая: **пока текст выделен, нажатие разбирает
  /// просмотрщик** — только он знает, пришлось ли оно на выделенный
  /// текст, на ручку выделения или мимо, а слушателю указателя этого не
  /// отличить. По выделенному тексту он снимает выделение сам, ручку
  /// двигает молча, а о нажатии мимо сообщает нам — и панели тогда
  /// переключаются по его сообщению, через 300 мс, как и до BUG-38.
  void _onRibbonTap(VoidCallback toggleChrome) {
    _scaffold.currentState?.focusPage();
    if (_viewer.isReady && _viewer.textSelectionDelegate.hasSelectedText) {
      _ribbonTaps.leaveToViewer();
      return;
    }
    toggleChrome();
  }

  /// Меню просмотрщика в ленте: «Копировать» и «Выделить всё».
  ///
  /// То же меню, что pdfrx 2.6.1 строит сам (`pdf_viewer.dart`,
  /// `_buildContextMenu`), — в ленте это единственный способ унести
  /// текст. Отличие одно: нажатие по кнопке меню — не нажатие по
  /// странице (BUG-38). Меню лежит внутри просмотрщика, и слушатель
  /// поверх него видит его нажатия тоже; свой слушатель у меню
  /// срабатывает раньше и говорит, что этот жест нажатием по странице не
  /// станет. Иначе «Выделить всё» заодно показывало бы панели.
  ///
  /// Поднимая версию pdfrx, меню сверяют с его собственным.
  Widget? _buildRibbonMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final PdfTextSelectionDelegate text = params.textSelectionDelegate;
    final bool selectable = params.isTextSelectionEnabled;
    final List<ContextMenuButtonItem> items = <ContextMenuButtonItem>[
      if (selectable && text.isCopyAllowed && text.hasSelectedText)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => unawaited(_copyRibbonSelection(text, clear: true)),
        ),
      if (selectable && !text.isSelectingAllText)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () => unawaited(text.selectAllText()),
        ),
    ];
    if (items.isEmpty) {
      return null;
    }
    return Listener(
      onPointerUp: (PointerUpEvent event) => _ribbonTaps.spoil(),
      child: Align(
        alignment: Alignment.topLeft,
        child: AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(
            primaryAnchor: params.anchorA,
            secondaryAnchor: params.anchorB,
          ),
          buttonItems: items,
        ),
      ),
    );
  }

  /// «Копировать» в ленте (BUG-51).
  ///
  /// Сам просмотрщик кладёт в буфер текст страницы как есть — со
  /// знаком, которым движок отмечает перенос слова. Поэтому текст
  /// берётся у него, чистится тем же правилом, что цитата и заметка, и
  /// в буфер его кладём мы. Выделение после кнопки меню снимается, а
  /// после `Ctrl+C` остаётся ([clear]) — как у просмотрщика.
  Future<void> _copyRibbonSelection(
    PdfTextSelectionDelegate text, {
    required bool clear,
  }) async {
    if (!text.isCopyAllowed) {
      return;
    }
    final String raw = await text.getSelectedText();
    final SelectionActions? actions = _actions;
    final String clean = actions == null
        ? leavingText(raw)
        : await actions.leaving(raw);
    if (clean.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: clean));
    // SNO-F-REC-02: места в тексте страницы у выделения ленты нет —
    // действие пишется с текстом и пометкой ленты.
    unawaited(actions?.copiedLoose(clean));
    if (clear) {
      await text.clearTextSelection();
    }
  }

  /// `Ctrl+C` в ленте: просмотрщик скопировал бы сам, мимо правила
  /// (BUG-51). Остальные клавиши остаются ему.
  bool? _onRibbonKey(
    PdfViewerKeyHandlerParams params,
    LogicalKeyboardKey key,
    bool isRealKeyPress,
  ) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (key != LogicalKeyboardKey.keyC ||
        !(keyboard.isControlPressed || keyboard.isMetaPressed)) {
      return null;
    }
    if (_viewer.isReady) {
      final PdfTextSelectionDelegate text = _viewer.textSelectionDelegate;
      if (text.hasSelectedText) {
        unawaited(_copyRibbonSelection(text, clear: false));
      }
    }
    return true;
  }

  Widget _buildRibbonViewer(
    BuildContext context,
    ReaderController controller,
    PdfDocument document,
    VoidCallback onTap,
  ) {
    return PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _viewer,
      initialPageNumber: controller.initialPage,
      params: PdfViewerParams(
        // Фон под страницей — цвет темы, а не белый: белые поля вокруг
        // страницы ночью бьют в глаза сильнее самой страницы.
        backgroundColor: Theme.of(context).colorScheme.surface,
        margin: 6,
        pageDropShadow: null,
        enableKeyboardNavigation: true,
        // F-READ-02: книга открыта, не измеряя все свои страницы, и лента
        // меряет их по мере прокрутки, а не обходит всю книгу в фоне: в
        // pdfrx 2.6.1 такой обход отнимает движок у отрисовки.
        behaviorControlParams: const PdfViewerBehaviorControlParams(
          loadPageDimensionsOnDemand: true,
        ),
        onPageChanged: (int? page) {
          if (page != null) {
            controller.onPageChanged(page);
          }
        },
        buildContextMenu: _buildRibbonMenu,
        onKey: _onRibbonKey,
        onGeneralTap:
            (
              BuildContext context,
              PdfViewerController viewerController,
              PdfViewerGeneralTapHandlerDetails details,
            ) {
              // Панели переключает только простое нажатие; долгое — это
              // выделение текста, и отбирать его у просмотрщика нельзя:
              // жест, которым оно сделано, нажатием уже не станет.
              if (details.type == PdfViewerGeneralTapType.longPress) {
                _ribbonTaps.spoil();
              }
              if (details.type != PdfViewerGeneralTapType.tap) {
                return false;
              }
              // BUG-38: двойное нажатие в pdfrx 2.6.1 не делает ничего,
              // но одиночное из-за него приходит сюда на 300 мс позже.
              // Мы его уже исполнили — в миг, когда указатель был поднят,
              // — и сюда оно доходит эхом. Не эхо — нажатие без указателя
              // (средства доступности) и нажатие, оставленное
              // просмотрщику, потому что текст был выделен.
              final bool echo = _ribbonTaps.echoes();
              if (details.tapOn == PdfViewerPart.selectedText) {
                return false;
              }
              if (!echo) {
                onTap();
              }
              return true;
            },
      ),
    );
  }
}

/// Кусок текста, подсвеченный на странице.
///
/// Один и тот же для найденного поиском и для открытой из списка цитаты:
/// и то, и другое — ответ на вопрос «где здесь то, что я ищу».
class _PageMark {
  const _PageMark({
    required this.pageNumber,
    required this.start,
    required this.end,
  });

  final int pageNumber;
  final int start;
  final int end;
}

/// Совпадение запроса на странице листа: где оно в тексте и на странице.
class _HitRects {
  const _HitRects({
    required this.pageNumber,
    required this.start,
    required this.boxes,
  });

  final int pageNumber;
  final int start;
  final List<TextBox> boxes;

  /// То ли это место, что отмечено текущим: его рисует своя подсветка,
  /// ярче остальных.
  bool isAt(_PageMark? mark) =>
      mark != null && mark.pageNumber == pageNumber && mark.start == start;
}

/// Экран «книга не открылась».
///
/// Причина названа своими словами, а не кодом ошибки: человеку надо
/// понять, что делать дальше, а не что сломалось внутри.
class _FailureScreen extends StatefulWidget {
  const _FailureScreen({
    required this.failure,
    required this.onPassword,
    required this.onRelink,
  });

  final DocumentOpenException failure;
  final void Function(String password) onPassword;

  /// Показать файл заново; `null` — в этой сборке файл не выбирают
  /// (BUG-46), и вместо кнопки сказано, откуда книга возвращается.
  final VoidCallback? onRelink;

  @override
  State<_FailureScreen> createState() => _FailureScreenState();
}

class _FailureScreenState extends State<_FailureScreen> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DocumentProblem problem = widget.failure.problem;
    final bool needsPassword =
        problem == DocumentProblem.passwordRequired ||
        problem == DocumentProblem.wrongPassword;
    // Файл потерялся — значит, его можно показать заново. Всё остальное
    // (повреждён, пустой) перевыбором того же файла не лечится.
    final bool missing = problem == DocumentProblem.missing;
    final VoidCallback? onRelink = widget.onRelink;

    return Scaffold(
      appBar: AppBar(title: const Text('Книга не открылась')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(
              needsPassword ? Icons.lock_outline : Icons.report_gmailerrorred,
              size: 56,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              describeDocumentProblem(problem),
              key: const Key('reader-failure-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (needsPassword) ...<Widget>[
              const SizedBox(height: 24),
              TextField(
                key: const Key('reader-password-field'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: widget.onPassword,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('reader-password-submit'),
                onPressed: () => widget.onPassword(_password.text),
                child: const Text('Открыть'),
              ),
            ],
            if (missing && onRelink != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('reader-relink'),
                onPressed: onRelink,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Выбрать файл заново'),
              ),
              const SizedBox(height: 12),
              Text(
                'Место чтения, цитаты и заметки останутся на месте: они '
                'принадлежат книге, а не файлу.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (missing && onRelink == null) ...<Widget>[
              const SizedBox(height: 24),
              Text(
                'Добавьте архив с литературой ещё раз: «Тестирование» → '
                '«Для экспериментатора». Книга вернётся на своё место.',
                key: const Key('reader-readd-archive'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
