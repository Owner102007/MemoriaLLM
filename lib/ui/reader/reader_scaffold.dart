import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/reading/navigation.dart';
import 'outline_panel.dart';
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

  @override
  State<ReaderScaffold> createState() => ReaderScaffoldState();
}

/// Состояние [ReaderScaffold]. Открыто, чтобы экран чтения мог сам
/// показать панель — например, по кнопке «назад» на Android.
class ReaderScaffoldState extends State<ReaderScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _chromeVisible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final ReaderController controller = widget.controller;
    return Scaffold(
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
        onSelect: (int page) async {
          Navigator.of(context).pop();
          await _goTo(page);
          hideChrome();
        },
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
            onOutline: () {
              unawaited(controller.loadOutline());
              _scaffoldKey.currentState?.openDrawer();
            },
            onSearch: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          _BottomBar(
            visible: _chromeVisible,
            page: controller.page,
            pageCount: controller.pageCount,
            onPage: (int page) => unawaited(_goTo(page)),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.extraActions,
    required this.onBack,
    required this.onOutline,
    required this.onSearch,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final List<Widget> extraActions;
  final VoidCallback onBack;
  final VoidCallback onOutline;
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
                ...extraActions,
                IconButton(
                  key: const Key('reader-outline-button'),
                  icon: const Icon(Icons.list_alt_outlined),
                  tooltip: 'Оглавление',
                  onPressed: onOutline,
                ),
                IconButton(
                  key: const Key('reader-search-button'),
                  icon: const Icon(Icons.search),
                  tooltip: 'Поиск по книге',
                  onPressed: onSearch,
                ),
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
  });

  final bool visible;
  final int page;
  final int pageCount;
  final void Function(int page) onPage;

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
