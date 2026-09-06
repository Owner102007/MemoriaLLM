import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/text_search.dart';
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

  @override
  State<ReaderScaffold> createState() => ReaderScaffoldState();
}

/// Состояние [ReaderScaffold]. Открыто, чтобы экран чтения мог сам
/// показать панель — например, по кнопке «назад» на Android.
class ReaderScaffoldState extends State<ReaderScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _chromeVisible = false;

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
    widget.controller.addListener(_onControllerChanged);
    widget.search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.search.removeListener(_onSearchChanged);
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
      _hit = -1;
      return;
    }
    if (_hit >= widget.search.hits.length) {
      _hit = -1;
    }
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

  void _openSearch() {
    final ScaffoldState? scaffold = _scaffoldKey.currentState;
    if (scaffold != null && !scaffold.isEndDrawerOpen) {
      scaffold.openEndDrawer();
    }
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
  /// он или сломалась клавиша, — худший из исходов. Панель поиска при
  /// этом не закрывается: `F3` для того и нужен, чтобы пройти совпадения
  /// подряд, не трогая список.
  Future<void> _stepHit(int step) async {
    final List<SearchHit> hits = widget.search.hits;
    if (hits.isEmpty) {
      return;
    }
    final int next = (_hit + step) % hits.length;
    _hit = next < 0 ? next + hits.length : next;
    await _goToHit(hits[_hit]);
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
    final bool searching = scaffold?.isEndDrawerOpen ?? false;
    final ReaderKeyAction? action = readerKeyAction(
      key: event.logicalKey,
      control: keyboard.isControlPressed || keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      searching: searching,
      hasHits: widget.search.hits.isNotEmpty,
      typing: isTypingInField(),
    );
    if (action == null) {
      return KeyEventResult.ignored;
    }
    switch (action) {
      case ReaderKeyAction.previous:
        widget.onPreviousFragment?.call();
      case ReaderKeyAction.next:
        widget.onNextFragment?.call();
      case ReaderKeyAction.openSearch:
        _openSearch();
      case ReaderKeyAction.nextHit:
        unawaited(_stepHit(1));
      case ReaderKeyAction.previousHit:
        unawaited(_stepHit(-1));
      case ReaderKeyAction.dismiss:
        if (searching) {
          scaffold?.closeEndDrawer();
        } else if (scaffold?.isDrawerOpen ?? false) {
          scaffold?.closeDrawer();
        } else {
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
    // части, поэтому узел стоит **над** `Scaffold`: панель поиска — не
    // ребёнок тела экрана, и `Esc`, нажатый в её поле, иначе до нас не
    // дошёл бы вовсе. Поле при этом ничего не теряет: свои клавиши оно
    // разбирает первым, а сюда доходит только то, чего оно не взяло.
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        key: _scaffoldKey,
        // Панели открываются кнопками, а не свайпом от края: свайп на
        // экране чтения принадлежит странице.
        drawerEnableOpenDragGesture: false,
        endDrawerEnableOpenDragGesture: false,
        drawer: OutlinePanel(
          controller: controller,
          onSelect: (int page) async {
            Navigator.of(context).pop();
            await _goTo(page);
            hideChrome();
          },
        ),
        endDrawer: SearchPanel(
          search: widget.search,
          onSelect: (SearchHit hit) async {
            Navigator.of(context).pop();
            _hit = widget.search.hits.indexOf(hit);
            await _goToHit(hit);
            hideChrome();
          },
          onNextHit: () => unawaited(_stepHit(1)),
          // `Esc` закрывает поиск, но разбирает его сама панель: пока
          // курсор стоит в поле, клавиши чтения молчат вовсе, и до нас
          // событие не дошло бы.
          onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
        ),
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: widget.viewerBuilder(context, toggleChrome)),
            _TopBar(
              visible: _chromeVisible,
              title: controller.book.title,
              subtitle: controller.label,
              extraActions: widget.extraActions,
              onBack: () => Navigator.of(context).maybePop(),
              onSearch: _openSearch,
            ),
            _BottomBar(
              visible: _chromeVisible,
              page: controller.page,
              pageCount: controller.pageCount,
              onPage: (int page) => unawaited(_goTo(page)),
              onOutline: () {
                unawaited(controller.loadOutline());
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
          ],
        ),
      ),
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
    required this.onPage,
    required this.onOutline,
  });

  final bool visible;
  final int page;
  final int pageCount;
  final void Function(int page) onPage;
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
                    onPressed: page > 1
                        ? () => onPage(previousPage(page, pageCount))
                        : null,
                  ),
                  Expanded(
                    // Ползунок нужен только там, где есть куда его тянуть:
                    // на книге в одну страницу Slider с min == max падает.
                    child: pageCount > 1
                        ? Slider(
                            key: const Key('reader-progress-slider'),
                            min: 1,
                            max: pageCount.toDouble(),
                            divisions: pageCount - 1,
                            value: clampPage(page, pageCount).toDouble(),
                            label: '$page',
                            onChanged: (double value) => onPage(value.round()),
                          )
                        : const SizedBox(height: 48),
                  ),
                  IconButton(
                    key: const Key('reader-next-page'),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Следующая страница',
                    visualDensity: VisualDensity.compact,
                    onPressed: page < pageCount
                        ? () => onPage(nextPage(page, pageCount))
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${progressPercent(progressForPage(page, pageCount))}%',
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
