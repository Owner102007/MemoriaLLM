import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/search_dock.dart';
import '../../domain/reading/text_search.dart';
import 'key_bindings.dart';
import 'outline_panel.dart';
import 'reader_keys.dart';
import 'search_panel.dart';

/// Обвязка экрана чтения: страница во весь экран, панели поверх неё.
///
/// Виджет намеренно ничего не знает про PDFium: сама страница приходит
/// снаружи через [viewerBuilder]. Благодаря этому весь интерфейс чтения —
/// панель, оглавление, поиск, ползунок — проверяется widget-тестами без
/// движка PDF и без настоящего файла.
///
/// Главное правило экрана: **по умолчанию не видно ничего, кроме
/// страницы**. Панели появляются по нажатию в середину и уходят сами,
/// как только читатель переходит к делу.
///
/// **Поиск — спутник страницы** (F-TEXT-11, ALG-UI-31): выбор результата
/// панель не закрывает. На широком окне она стоит справа, а страница —
/// в оставшейся ширине; на узком экране после выбора результата она
/// сжимается в полупрозрачную полосу у того края, где найденного нет.
/// Закрывает поиск только читатель: `✕`, `Esc`, системное «назад».
class ReaderScaffold extends StatefulWidget {
  /// Создаёт обвязку.
  const ReaderScaffold({
    required this.controller,
    required this.search,
    required this.viewerBuilder,
    required this.onGoToPage,
    this.onGoToHit,
    this.onPreviousFragment,
    this.onNextFragment,
    this.onDismiss,
    this.onPanelsChanged,
    this.onSearchOpen,
    this.onSearchDock,
    this.found,
    this.selecting,
    this.fullScreen = false,
    this.onFullScreen,
    this.keyBindings = KeyBindings.standard,
    this.extraActions = const <Widget>[],
    super.key,
  });

  /// Состояние книги.
  final ReaderController controller;

  /// Поиск по книге.
  final DocumentSearch search;

  /// Дополнительные кнопки в верхней панели — например, переключатель
  /// способа листания. Их владелец — экран чтения, а не обвязка.
  final List<Widget> extraActions;

  /// Строит саму страницу. [onTap] надо вызвать по нажатию в середину:
  /// это переключает видимость панелей.
  final Widget Function(BuildContext context, VoidCallback onTap) viewerBuilder;

  /// Переход на страницу. Возвращает управление, когда переход выполнен.
  final Future<void> Function(int page) onGoToPage;

  /// Переход к найденному. Отличается от [onGoToPage] тем, что несёт само
  /// совпадение: подсветить его на странице по одному номеру страницы
  /// нельзя — нужны координаты в тексте.
  final Future<void> Function(SearchHit hit)? onGoToHit;

  /// Предыдущий фрагмент — клавишами. Зоны листания живут на самой
  /// странице, а клавиатура принадлежит экрану целиком.
  final VoidCallback? onPreviousFragment;

  /// Следующий фрагмент — клавишами.
  final VoidCallback? onNextFragment;

  /// `Esc`, когда закрывать нечего: снять выделение, спрятать панели.
  final VoidCallback? onDismiss;

  /// Страницу закрыла панель — оглавление или поиск во время ввода на
  /// узком экране — или снова открыла.
  ///
  /// `true`, пока страница закрыта. Экрану чтения это нужно затем,
  /// чтобы не листать кнопками громкости книгу, которую не видно
  /// (F-READ-26): панель — не маршрут, и навигатор о ней не знает.
  /// Поиск, который стоит рядом со страницей или лежит на ней полосой,
  /// страницу не закрывает (F-TEXT-11).
  final ValueChanged<bool>? onPanelsChanged;

  /// Поиск открыли или закрыли. Пока он открыт, экран чтения подсвечивает
  /// на странице все совпадения запроса, а не одно (F-TEXT-11).
  final ValueChanged<bool>? onSearchOpen;

  /// Сколько ширины панель поиска отняла у страницы: на широком окне она
  /// стоит рядом с ней. Ноль — страница снова во всю ширину.
  ///
  /// Когда поиск открывают или закрывают, сообщается до кадра, в
  /// котором место под страницу меняется: экран чтения перекладывает
  /// лист один раз и сразу, не принимая это за протяжку окна
  /// (F-DESK-02). Когда окно при открытом поиске перешло границу
  /// «широкого» — после кадра: посреди построения дерева нельзя.
  final ValueChanged<double>? onSearchDock;

  /// Где на экране лежит текущее совпадение, в координатах страницы;
  /// `null` — его не видно. По нему панель поиска на узком экране
  /// выбирает край, у которого она найденного не закроет (ALG-UI-31).
  final ValueListenable<Rect?>? found;

  /// Выделен ли текст на странице. Нужно `Esc`: выделение он снимает
  /// раньше, чем выводит из чтения во весь экран. Спрашивается в миг
  /// нажатия, а не при построении: о выделении просмотрщик узнаёт
  /// раньше, чем экран успевает перестроиться.
  final ValueGetter<bool>? selecting;

  /// Развёрнуто ли чтение во весь экран (F-READ-35).
  final bool fullScreen;

  /// Развернуть чтение во весь экран или вернуть окно — клавишей `F11`
  /// и `Esc`. `null` — платформа окно не разворачивает, и клавиши не
  /// значат ничего.
  final ValueChanged<bool>? onFullScreen;

  /// Какие клавиши листают вперёд и назад (F-READ-25). Настройка
  /// устройства; без неё — таблица из коробки.
  final KeyBindings keyBindings;

  @override
  State<ReaderScaffold> createState() => ReaderScaffoldState();
}

/// Состояние [ReaderScaffold]. Открыто, чтобы экран чтения мог сам
/// показать панель — например, по кнопке «назад» на Android.
class ReaderScaffoldState extends State<ReaderScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Панель поиска переезжает между местами — рядом со страницей, во
  /// весь экран, полосой у края, — и обязана переезжать со своим
  /// состоянием: набранным запросом и местом в списке.
  final GlobalKey _searchKey = GlobalKey(debugLabel: 'search-panel');

  /// Узел клавиш чтения. Свой, а не безымянный: выбрав результат,
  /// читатель смотрит на страницу, и клавиши обязаны вернуться к ней из
  /// поля поиска (F-TEXT-11).
  final FocusNode _keys = FocusNode(debugLabel: 'reader-keys');

  /// Узел поля поиска: открывая поиск, ставим указатель в поле сами.
  final FocusNode _searchField = FocusNode(debugLabel: 'search-field');

  bool _chromeVisible = false;

  /// Открыты ли оглавление и поиск.
  bool _outlineOpen = false;
  bool _searchOpen = false;

  /// Выбран ли результат: поиск открыт, а читатель смотрит на страницу.
  /// На узком экране панель в это время — полоса у края.
  bool _browsing = false;

  /// Широкое ли окно: панель поиска стоит рядом со страницей.
  bool _wide = false;

  /// У какого края полоса поиска стояла в прошлый раз: без нужды она не
  /// переезжает.
  SearchDockSide? _dockSide;

  /// Что экрану чтения сказано в последний раз.
  bool _saidCovered = false;
  bool _saidOpen = false;
  double _saidDock = 0;

  /// На каком совпадении читатель стоит сейчас.
  ///
  /// Нужно `F3`: «следующее» имеет смысл только относительно текущего.
  /// Минус единица — ни на каком, и следующее равно первому.
  int _hit = -1;

  /// Запрос, по которому идёт счёт совпадений.
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Поиск мог начаться раньше экрана: его запрос — уже наш, и первое
    // же сообщение о нём счёт совпадений не сбрасывает.
    _query = widget.search.query;
    widget.controller.addListener(_onControllerChanged);
    widget.search.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool wide = isSearchWide(MediaQuery.sizeOf(context));
    if (wide == _wide) {
      return;
    }
    _wide = wide;
    if (_searchOpen) {
      // Окно перешло границу «широкого» при открытом поиске: панель
      // встаёт рядом со страницей или уходит с неё. Экрану чтения об
      // этом говорится после кадра — посреди построения дерева нельзя.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _report();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.search.removeListener(_onSearchChanged);
    _keys.dispose();
    _searchField.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Новый запрос — счёт совпадений начинается заново.
  ///
  /// Иначе `F3` по новому запросу продолжал бы с того места, где читатель
  /// бросил прошлый, и первое совпадение оказалось бы пропущено.
  void _onSearchChanged() {
    if (!mounted) {
      return;
    }
    if (widget.search.query != _query) {
      _query = widget.search.query;
      // Отметка текущего результата в списке уходит вместе со счётом.
      setState(() => _hit = -1);
      return;
    }
    if (_hit >= widget.search.hits.length) {
      setState(() => _hit = -1);
    }
  }

  /// Открыт ли поиск.
  bool get searchOpen => _searchOpen;

  /// Закрывает ли поиск страницу: на узком экране, пока читатель
  /// набирает запрос, панель занимает экран целиком.
  bool get _searchCovers => _searchOpen && !_wide && !_browsing;

  /// Ведут ли кнопки громкости по совпадениям вместо листания.
  ///
  /// F-TEXT-11, решение владельца 03.10.2026 (Ж1): пока панель поиска
  /// открыта, а страница видна, «тише» и «громче» перебирают найденное —
  /// одной рукой, не отрывая глаз от страницы. Без найденного
  /// перебирать нечего, и кнопки листают, как всегда.
  bool get searchSteps =>
      _searchOpen && !_searchCovers && widget.search.hits.isNotEmpty;

  /// Говорит экрану чтения, что изменилось: закрыта ли страница, открыт
  /// ли поиск и сколько ширины он отнял у страницы.
  ///
  /// Зовётся из обработчиков событий и после кадра — и никогда из
  /// построения дерева: экран чтения в ответ перестраивается сам.
  void _report() {
    final bool covered = _outlineOpen || _searchCovers;
    if (covered != _saidCovered) {
      _saidCovered = covered;
      widget.onPanelsChanged?.call(covered);
    }
    final double dock = _searchOpen && _wide ? kSearchPanelWidth : 0;
    if (dock != _saidDock) {
      _saidDock = dock;
      widget.onSearchDock?.call(dock);
    }
    if (_searchOpen != _saidOpen) {
      _saidOpen = _searchOpen;
      widget.onSearchOpen?.call(_searchOpen);
    }
  }

  void _onOutline(bool open) {
    _outlineOpen = open;
    _report();
  }

  /// Показать или спрятать панели.
  void toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  /// Спрятать панели.
  void hideChrome() {
    if (mounted && _chromeVisible) {
      setState(() => _chromeVisible = false);
    }
  }

  Future<void> _goTo(int page) async {
    await widget.onGoToPage(page);
  }

  /// Стрелка нижней панели: соседний лист.
  ///
  /// Лист, а не страница (BUG-01): в развороте стрелка, шагавшая на
  /// страницу, каждый второй раз оставляла экран прежним. Цель читается
  /// в момент нажатия, а не при построении панели: контроллер считает её
  /// от ещё не законченного перехода, и два быстрых нажатия дают два
  /// шага (BUG-11).
  void _stepSheet({required bool forward}) {
    final ReaderController controller = widget.controller;
    final int? target = forward
        ? controller.nextSheetStart
        : controller.previousSheetStart;
    if (target != null) {
      unawaited(_goTo(target));
    }
  }

  /// Открывает поиск — или возвращает уже открытый ко вводу запроса.
  void openSearch() {
    if (!mounted) {
      return;
    }
    setState(() {
      _searchOpen = true;
      _browsing = false;
    });
    _report();
    // Указатель — в поле: открывший поиск собирается набирать. Поле в
    // этом кадре может ещё не стоять на экране, поэтому после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen && !_browsing) {
        _searchField.requestFocus();
      }
    });
  }

  /// Закрывает поиск. Запрос и место в списке остаются: откроют снова —
  /// найденное на месте.
  void closeSearch() {
    if (!mounted || !_searchOpen) {
      return;
    }
    setState(() {
      _searchOpen = false;
      _browsing = false;
      _dockSide = null;
    });
    _report();
    _keys.requestFocus();
  }

  /// Читатель нажал по странице: клавиши возвращаются к ней.
  ///
  /// На широком окне страница рядом с поиском живая, и после нажатия по
  /// ней стрелки и пробел обязаны листать, а не уходить в поле запроса
  /// (F-TEXT-11).
  ///
  /// Спрашивать, стоит ли указатель в поле, нельзя: на ПК поле теряет
  /// его уже по нажатию кнопки мыши мимо себя — раньше, чем нажатие
  /// дойдёт сюда.
  void focusPage() {
    if (mounted && _searchOpen) {
      _keys.requestFocus();
    }
  }

  /// Результат выбран: читатель смотрит на страницу, а панель остаётся.
  ///
  /// Клавиши возвращаются к странице — рядом с открытой панелью она
  /// листается, как обычно, — а на телефоне заодно уходит клавиатура.
  void _browse(int index) {
    setState(() {
      _hit = index;
      _browsing = true;
    });
    _report();
    _keys.requestFocus();
  }

  Future<void> _selectHit(SearchHit hit) async {
    _browse(widget.search.hits.indexOf(hit));
    await _goToHit(hit);
    hideChrome();
  }

  Future<void> _goToHit(SearchHit hit) async {
    final Future<void> Function(SearchHit hit)? goToHit = widget.onGoToHit;
    if (goToHit != null) {
      await goToHit(hit);
    } else {
      await _goTo(hit.pageNumber);
    }
  }

  /// Следующее или предыдущее совпадение по кругу.
  ///
  /// По кругу потому, что упереться в конец списка и не понять, кончился
  /// он или сломалась клавиша, — худший из исходов. Куда ведёт шаг,
  /// решает [stepSearchHit] (BUG-08). Открытый поиск при этом переходит
  /// к просмотру: шаг — это выбор результата (F-TEXT-11). Закрытый не
  /// открывается: `F3` идёт по совпадениям и без панели.
  Future<void> stepHit(int step) async {
    final List<SearchHit> hits = widget.search.hits;
    if (hits.isEmpty) {
      return;
    }
    final int next = stepSearchHit(
      current: _hit,
      step: step,
      count: hits.length,
    );
    if (_searchOpen) {
      _browse(next);
    } else {
      _hit = next;
    }
    await _goToHit(hits[next]);
  }

  /// Клавиши чтения.
  ///
  /// Работают **всегда**: выделен текст или нет, открыт поиск или нет.
  /// Своей навигации по клавишам у просмотрщика нет — она выключена
  /// намеренно, чтобы его страница не уехала от нашей.
  ///
  /// Единственное исключение — набор текста. Узел стоит над `Scaffold`, и
  /// событие из поля поиска проходит через него **раньше**, чем через
  /// правила редактирования текста, которые живут выше, в `WidgetsApp`.
  /// Ответить «разобрано» здесь значит съесть у поля пробел и
  /// `Backspace` — ровно это и случилось в S6.1.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    final ScaffoldState? scaffold = _scaffoldKey.currentState;
    final bool searching = _searchOpen;
    final ReaderKeyAction? action = readerKeyAction(
      key: event.logicalKey,
      control: keyboard.isControlPressed || keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      searching: searching,
      hasHits: widget.search.hits.isNotEmpty,
      typing: isTypingInField(),
      canFullScreen: widget.onFullScreen != null,
      bindings: widget.keyBindings,
    );
    if (action == null) {
      return KeyEventResult.ignored;
    }
    // Страницу, которую панель поиска закрыла целиком, клавиши не
    // листают: читатель её не видит.
    final bool turning =
        action == ReaderKeyAction.previous || action == ReaderKeyAction.next;
    if (turning && _searchCovers) {
      return KeyEventResult.ignored;
    }
    switch (action) {
      case ReaderKeyAction.previous:
        widget.onPreviousFragment?.call();
      case ReaderKeyAction.next:
        widget.onNextFragment?.call();
      case ReaderKeyAction.openSearch:
        openSearch();
      case ReaderKeyAction.nextHit:
        unawaited(stepHit(1));
      case ReaderKeyAction.previousHit:
        unawaited(stepHit(-1));
      case ReaderKeyAction.fullScreen:
        // Только по нажатию: удержанная клавиша иначе гоняла бы окно
        // туда-сюда с частотой автоповтора.
        if (event is KeyDownEvent) {
          widget.onFullScreen?.call(!widget.fullScreen);
        }
      case ReaderKeyAction.dismiss:
        final bool selecting = widget.selecting?.call() ?? false;
        final EscapeTarget target = escapeTarget(
          // Поиск теперь стоит рядом со страницей подолгу, и закрывать
          // его раньше, чем снято выделение на видимой странице, значило
          // бы отбирать у `Esc` привычное дело (F-TEXT-11). Пока панель
          // закрывает страницу, выделять на ней нечем, и порядок прежний.
          searching: searching && (_searchCovers || !selecting),
          outline: scaffold?.isDrawerOpen ?? false,
          selecting: selecting,
          panels: _chromeVisible,
          fullScreen: widget.fullScreen && widget.onFullScreen != null,
        );
        switch (target) {
          case EscapeTarget.search:
            closeSearch();
          case EscapeTarget.outline:
            scaffold?.closeDrawer();
          case EscapeTarget.fullScreen:
            widget.onFullScreen?.call(false);
          case EscapeTarget.page:
            widget.onDismiss?.call();
            hideChrome();
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ReaderController controller = widget.controller;
    // Клавиатура принадлежит всему экрану чтения, а не какой-то его
    // части, поэтому узел стоит **над** `Scaffold`: оглавление — не
    // ребёнок тела экрана, и клавиша, нажатая в нём, иначе до нас не
    // дошла бы вовсе. Поле поиска при этом ничего не теряет: свои
    // клавиши оно разбирает первым, а сюда доходит только то, чего оно
    // не взяло.
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      // Системное «назад» при открытом поиске закрывает поиск, а не
      // книгу (F-TEXT-11).
      child: PopScope<Object?>(
        canPop: !_searchOpen,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) {
            closeSearch();
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          // Оглавление открывается кнопкой, а не свайпом от края: свайп
          // на экране чтения принадлежит странице.
          drawerEnableOpenDragGesture: false,
          onDrawerChanged: _onOutline,
          drawer: OutlinePanel(
            controller: controller,
            onSelect: (int page) async {
              Navigator.of(context).pop();
              await _goTo(page);
              hideChrome();
            },
          ),
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints limits) {
              return _buildBody(
                context,
                Size(limits.maxWidth, limits.maxHeight),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Страница с панелями чтения и панель поиска — рядом с ней или
  /// поверх неё.
  ///
  /// Страница стоит в дереве на одном и том же месте, с поиском и без
  /// него: меняется только её правый край. Иначе просмотрщик под ней
  /// пересоздавался бы на каждое открытие поиска.
  ///
  /// **Полоса поиска лежит под панелями чтения**, а не над ними: читатель
  /// вызывает их сам, нажатием в середину, и кнопки в них — стрелки
  /// листания, ползунок, оглавление — обязаны оставаться под рукой и
  /// при открытом поиске. Панель во весь экран и панель рядом со
  /// страницей с ними не спорят и лежат выше всего.
  Widget _buildBody(BuildContext context, Size area) {
    final ReaderController controller = widget.controller;
    final bool strip = _searchOpen && !_wide && _browsing;
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          // На широком окне панель поиска стоит рядом со страницей, и
          // лист раскладывается в оставшейся ширине: найденное под
          // панелью оказаться не может.
          right: _searchOpen && _wide ? kSearchPanelWidth : 0,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: widget.viewerBuilder(context, toggleChrome),
              ),
              if (strip) _buildStrip(context, area),
              _TopBar(
                visible: _chromeVisible,
                title: controller.book.title,
                subtitle: controller.label,
                extraActions: widget.extraActions,
                onBack: () => Navigator.of(context).maybePop(),
                onSearch: openSearch,
              ),
              _BottomBar(
                visible: _chromeVisible,
                page: controller.page,
                pageCount: controller.pageCount,
                canGoBack: controller.previousSheetStart != null,
                canGoForward: controller.nextSheetStart != null,
                progress: controller.progress,
                onStep: _stepSheet,
                onPage: _goTo,
                onOutline: () {
                  unawaited(controller.loadOutline());
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
            ],
          ),
        ),
        // Рядом со страницей: места хватает и полю, и списку, и вид у
        // панели один — что при вводе, что при просмотре.
        if (_searchOpen && _wide)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: kSearchPanelWidth,
            child: _searchPanel(edged: true),
          ),
        // Узкий экран, ввод: клавиатура и так закрывает половину экрана
        // — панель занимает его целиком.
        if (_searchOpen && !_wide && !_browsing)
          Positioned.fill(child: _searchPanel()),
      ],
    );
  }

  /// Узкий экран, просмотр: полупрозрачная полоса у того края, где
  /// найденного нет (ALG-UI-31).
  Widget _buildStrip(BuildContext context, Size area) {
    final ValueListenable<Rect?>? found = widget.found;
    if (found == null) {
      return _placeStrip(context, area, null);
    }
    return ValueListenableBuilder<Rect?>(
      valueListenable: found,
      builder: (BuildContext context, Rect? rect, Widget? child) {
        return _placeStrip(context, area, rect);
      },
    );
  }

  Widget _placeStrip(BuildContext context, Size area, Rect? found) {
    final SearchDock dock = placeSearchPanel(
      screen: MediaQuery.sizeOf(context),
      area: area,
      found: found,
      current: _dockSide,
    );
    // Запоминаем край: в следующий раз панель останется у него, если
    // найденное не окажется под ней.
    _dockSide = dock.side;
    final Widget panel = _searchPanel(
      browsing: true,
      compact: dock.compact,
      translucent: true,
      side: dock.side,
    );
    // Одна строка счёта — это её высота плюс вырез экрана у этого края:
    // иначе строка в отведённое место не поместилась бы.
    final EdgeInsets inset = MediaQuery.paddingOf(context);
    switch (dock.side) {
      case SearchDockSide.bottom:
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: dock.extent + (dock.compact ? inset.bottom : 0),
            ),
            child: panel,
          ),
        );
      case SearchDockSide.top:
        return Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: dock.extent + (dock.compact ? inset.top : 0),
            ),
            child: panel,
          ),
        );
      case SearchDockSide.right:
        return Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: dock.extent,
          child: panel,
        );
      case SearchDockSide.left:
        return Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: dock.extent,
          child: panel,
        );
    }
  }

  Widget _searchPanel({
    bool browsing = false,
    bool compact = false,
    bool translucent = false,
    bool edged = false,
    SearchDockSide? side,
  }) {
    return SearchPanel(
      key: _searchKey,
      search: widget.search,
      current: _hit,
      browsing: browsing,
      compact: compact,
      translucent: translucent,
      edged: edged,
      side: side,
      fieldFocus: _searchField,
      onSelect: (SearchHit hit) => unawaited(_selectHit(hit)),
      onStep: (int step) => unawaited(stepHit(step)),
      onEdit: openSearch,
      // `Esc` закрывает поиск, но в поле его разбирает сама панель: пока
      // курсор стоит в поле, клавиши чтения молчат вовсе, и до нас
      // событие не дошло бы.
      onClose: closeSearch,
    );
  }
}

/// Верхняя панель: чем управляют, глядя на страницу.
///
/// Здесь живёт всё, что меняет вид страницы прямо сейчас, — деление,
/// поворот, замок, рамка и фильтр, — и здесь же **поиск**. Наверх он
/// вернулся по проверке S6: владелец искал его тут и не нашёл, а поиск,
/// до которого не добрался читатель, всё равно что отсутствует.
///
/// Оглавление осталось внизу, у шкалы прогресса, и это не забывчивость, а
/// ширина телефона: кнопок наверху уже семь, восьмая не помещается в
/// портрет (368 точек против 360 у обычного экрана) и съела бы название
/// книги целиком. Поиском пользуются чаще оглавления — наверх уехал он.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.extraActions,
    required this.onBack,
    required this.onSearch,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final List<Widget> extraActions;
  final VoidCallback onBack;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _ChromeSlide(
        visible: visible,
        fromTop: true,
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const Key('reader-back'),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Закрыть книгу',
                  onPressed: onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        key: const Key('reader-page-label'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('reader-search-button'),
                  icon: const Icon(Icons.search),
                  tooltip: 'Поиск по книге (Ctrl+F)',
                  visualDensity: VisualDensity.compact,
                  onPressed: onSearch,
                ),
                ...extraActions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.visible,
    required this.page,
    required this.pageCount,
    required this.canGoBack,
    required this.canGoForward,
    required this.progress,
    required this.onStep,
    required this.onPage,
    required this.onOutline,
  });

  final bool visible;
  final int page;
  final int pageCount;

  /// Есть ли лист перед этим и за этим: на краю книги стрелка гаснет.
  final bool canGoBack;
  final bool canGoForward;

  /// Доля прочитанного — та же, что у контроллера и на полке.
  final double progress;

  /// Шаг стрелкой на соседний лист.
  final void Function({required bool forward}) onStep;

  /// Переход ползунком; будущее завершается, когда переход закончен.
  final Future<void> Function(int page) onPage;
  final VoidCallback onOutline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _ChromeSlide(
        visible: visible,
        fromTop: false,
        child: Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: const Key('reader-prev-page'),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Предыдущая страница',
                    visualDensity: VisualDensity.compact,
                    onPressed: canGoBack ? () => onStep(forward: false) : null,
                  ),
                  Expanded(
                    // Ползунок нужен только там, где есть куда его тянуть:
                    // на книге в одну страницу Slider с min == max падает.
                    child: pageCount > 1
                        ? _PageSlider(
                            page: page,
                            pageCount: pageCount,
                            onPage: onPage,
                          )
                        : const SizedBox(height: 48),
                  ),
                  IconButton(
                    key: const Key('reader-next-page'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Следующая страница',
                    visualDensity: VisualDensity.compact,
                    onPressed: canGoForward
                        ? () => onStep(forward: true)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${progressPercent(progress)}%',
                    key: const Key('reader-progress-percent'),
                    style: theme.textTheme.bodySmall,
                  ),
                  // Оглавление живёт рядом со шкалой прогресса: оба
                  // отвечают на вопрос «где я в книге». Поиск уехал
                  // отсюда наверх — его там искали и не нашли.
                  IconButton(
                    key: const Key('reader-outline-button'),
                    icon: const Icon(Icons.list_alt_outlined),
                    tooltip: 'Оглавление',
                    visualDensity: VisualDensity.compact,
                    onPressed: onOutline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ползунок страниц нижней панели.
///
/// BUG-39, F-READ-28: пока бегунок тянут, книга стоит, а меняется только
/// подпись над ним. Переход один — туда, где бегунок простоял
/// [kSliderRest] или был отпущен; страницы по пути не открываются.
/// Нужен ли переход, решает [SliderDrag]; здесь — срок и сам ползунок.
class _PageSlider extends StatefulWidget {
  const _PageSlider({
    required this.page,
    required this.pageCount,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final Future<void> Function(int page) onPage;

  @override
  State<_PageSlider> createState() => _PageSliderState();
}

class _PageSliderState extends State<_PageSlider> {
  final SliderDrag _drag = SliderDrag();

  /// Срок, который бегунок обязан простоять.
  Timer? _rest;

  /// Держит ли читатель бегунок прямо сейчас.
  bool _touching = false;

  /// Сколько отправленных переходов ещё не закончено.
  int _going = 0;

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }

  void _onChanged(double value) {
    setState(() => _drag.move(value.round()));
    // Срок идёт заново с каждым движением: переход — только когда
    // бегунок остановился. Он же закрывает случай, когда бегунок двигают
    // без пальца — клавишами или средствами доступности: отпускания там
    // не бывает вовсе.
    _rest?.cancel();
    _rest = Timer(kSliderRest, _settle);
  }

  void _onChangeEnd(double value) {
    _touching = false;
    _rest?.cancel();
    _rest = null;
    _drag.move(value.round());
    _settle();
  }

  /// Бегунок остановился или отпущен.
  void _settle() {
    _rest = null;
    if (!mounted) {
      return;
    }
    final int? page = _drag.rest(current: widget.page);
    if (page != null) {
      unawaited(_go(page));
      return;
    }
    _follow();
  }

  Future<void> _go(int page) async {
    _going++;
    try {
      await widget.onPage(page);
    } finally {
      _going--;
      _follow();
    }
  }

  /// Возвращает бегунок книге, когда держать его больше нечем.
  ///
  /// До конца перехода бегунок стоит там, где его оставили: страница
  /// меняется не в тот же миг, и без этого он на мгновение отскакивал бы
  /// на прежнее место.
  void _follow() {
    if (!mounted || _touching || _going > 0 || _rest != null) {
      return;
    }
    if (_drag.held != null) {
      setState(_drag.release);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int shown = clampPage(_drag.held ?? widget.page, widget.pageCount);
    return Slider(
      key: const Key('reader-progress-slider'),
      min: 1,
      max: widget.pageCount.toDouble(),
      divisions: widget.pageCount - 1,
      value: shown.toDouble(),
      label: '$shown',
      onChangeStart: (double value) => _touching = true,
      onChanged: _onChanged,
      onChangeEnd: _onChangeEnd,
    );
  }
}

/// Панель, уезжающая за край экрана.
///
/// Скрытая панель убирается из дерева не сразу, а после анимации, и
/// поэтому не перехватывает нажатия по странице.
class _ChromeSlide extends StatelessWidget {
  const _ChromeSlide({
    required this.visible,
    required this.fromTop,
    required this.child,
  });

  final bool visible;
  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    );
  }
}
