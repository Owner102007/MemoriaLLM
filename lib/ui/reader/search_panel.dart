import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/reading/document_search.dart';
import '../../domain/reading/search_dock.dart';
import '../../domain/reading/text_search.dart';

/// Панель поиска по книге.
///
/// Результаты показываются по мере того, как поиск идёт по страницам:
/// на книге в тысячу страниц ждать конца, глядя на крутилку, невыносимо,
/// а нужное обычно находится в первой сотне.
///
/// **Панель — спутник страницы, а не окно поверх неё** (F-TEXT-11,
/// замечание владельца 03.10.2026). Выбор результата её не закрывает:
/// страница переходит к найденному, а список остаётся — не то, что
/// искал, следующий результат выбирается сразу. Закрывает поиск только
/// сам читатель: `✕`, `Esc` или системное «назад».
///
/// Где панель стоит и какого она размера, решает экран чтения
/// (`placeSearchPanel`, ALG-UI-31); здесь — только её содержимое. Видов
/// у него два:
///
/// * **ввод** — поле, счёт совпадений, список;
/// * **просмотр** ([browsing]) — результат выбран, и на узком экране
///   поля в полосе нет: в одной строке стоят `‹ 3 из 17 ›`, запрос
///   (нажатие по нему возвращает ко вводу) и `✕`.
///
/// **На узком экране панель — полупрозрачная полоса у нижнего края в
/// обоих видах** (F-TEXT-12, замечание владельца 04.10.2026): страница
/// видна над ней и сквозь неё и пока запрос набирают. Места в полосе
/// мало, поэтому поле в ней плотнее, а состояние поиска стоит в строке
/// счёта.
class SearchPanel extends StatefulWidget {
  /// Создаёт панель.
  const SearchPanel({
    required this.search,
    required this.onSelect,
    this.current = -1,
    this.browsing = false,
    this.translucent = false,
    this.edged = false,
    this.fieldFocus,
    this.onStep,
    this.onEdit,
    this.onClose,
    this.seed = 0,
    super.key,
  });

  /// Поиск по книге.
  final DocumentSearch search;

  /// Переход к найденному.
  final void Function(SearchHit hit) onSelect;

  /// Номер совпадения, на котором стоит читатель; меньше нуля — ни на
  /// каком.
  final int current;

  /// Вид «просмотр»: поля ввода нет, запрос показан текстом.
  final bool browsing;

  /// Лежит ли панель поверх страницы полупрозрачной полосой у нижнего
  /// края (узкий экран).
  final bool translucent;

  /// Стоит ли панель рядом со страницей: тогда их разделяет линия.
  final bool edged;

  /// Узел поля ввода: экран чтения ставит в него указатель, когда
  /// открывает поиск.
  final FocusNode? fieldFocus;

  /// Шаг по совпадениям: `1` — следующее, `-1` — предыдущее. Им же
  /// служит `Enter` по уже найденному запросу.
  final void Function(int step)? onStep;

  /// Вернуться ко вводу — нажатие по запросу в виде «просмотр».
  final VoidCallback? onEdit;

  /// Закрыть панель: `✕` и `Esc`.
  ///
  /// `Esc` разбирается здесь, а не в клавиатурном узле экрана: пока
  /// курсор стоит в поле, клавиши чтения не разбираются вовсе — иначе
  /// поле осталось бы без пробела и `Backspace`.
  final VoidCallback? onClose;

  /// Номер запроса, заданного не набором в поле (SNO-F-READ-01).
  ///
  /// «Найти в книге» над выделением запускает поиск сам. Панель, уже
  /// стоящая на экране, узнаёт об этом по сменившемуся номеру и ставит
  /// запрос в своё поле — иначе в поле остался бы прежний.
  final int seed;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late final TextEditingController _field = TextEditingController(
    text: widget.search.query,
  );
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  /// Высота строки списка в последнем построении.
  double _rowExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onChanged);
    _revealSoon();
  }

  @override
  void didUpdateWidget(SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.search, widget.search)) {
      oldWidget.search.removeListener(_onChanged);
      widget.search.addListener(_onChanged);
    }
    if (oldWidget.current != widget.current ||
        oldWidget.browsing != widget.browsing) {
      _revealSoon();
    }
    if (oldWidget.seed != widget.seed) {
      // Недобранный запрос не должен стартовать поверх заданного.
      _debounce?.cancel();
      _field.text = widget.search.query;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.search.removeListener(_onChanged);
    _scroll.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Докручивает список до текущего результата — после кадра, когда
  /// список уже разложен по новому месту.
  void _revealSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Текущий результат обязан быть виден в списке: шаг по совпадениям
  /// клавишей или кнопкой громкости иначе уводил бы отметку за край.
  void _reveal() {
    if (!mounted || !_scroll.hasClients || _rowExtent <= 0) {
      return;
    }
    final int current = widget.current;
    if (current < 0 || current >= widget.search.hits.length) {
      return;
    }
    final ScrollPosition position = _scroll.position;
    final double top = current * _rowExtent;
    final double bottom = top + _rowExtent;
    final double shown = position.pixels + position.viewportDimension;
    if (top >= position.pixels && bottom <= shown) {
      return;
    }
    // Выше видимого — к верхнему краю, ниже — к нижнему.
    final double target = top < position.pixels
        ? top
        : bottom - position.viewportDimension;
    final double low = position.minScrollExtent;
    final double high = position.maxScrollExtent;
    _scroll.jumpTo(target < low ? low : (target > high ? high : target));
  }

  /// `Esc` в поле поиска закрывает панель.
  ///
  /// Узел стоит вокруг поля, а не над экраном: событие доходит сюда
  /// раньше всех, и разбирается ровно одна клавиша — та, которой поле
  /// ввода всё равно не пользуется. Всё остальное уходит дальше, к
  /// правилам редактирования текста.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final VoidCallback? close = widget.onClose;
    if (close == null) {
      return KeyEventResult.ignored;
    }
    close();
    return KeyEventResult.handled;
  }

  void _onQueryChanged(String value) {
    // Пауза перед запуском: иначе каждый набранный символ запускает
    // проход по всей книге, и первые буквы съедают процессор впустую.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(widget.search.start(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DocumentSearch search = widget.search;
    final Color surface = theme.colorScheme.surface;
    final bool list = search.hits.isNotEmpty;
    // Своя область фокуса, как была у боковой шторки. Поле, потеряв
    // указатель ввода — по `Enter` или по нажатию мышью мимо него, —
    // отдаёт его своей области, а она лежит ниже узла клавиш чтения:
    // `Esc`, `F3` и стрелки продолжают до него доходить. Без области
    // указатель уходил бы к маршруту, выше узла, и клавиши чтения
    // замолкали до следующего нажатия по полю.
    return FocusScope(
      child: Material(
        key: const Key('search-panel'),
        // Поверх страницы панель полупрозрачна: сквозь неё видно, что
        // под ней. Рядом со страницей прозрачность ни к чему.
        color: widget.translucent
            ? surface.withValues(alpha: kSearchPanelOpacity)
            : surface,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: widget.edged
                ? Border(left: BorderSide(color: theme.dividerColor))
                : null,
          ),
          child: _content(context, theme, search, list: list),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ThemeData theme,
    DocumentSearch search, {
    required bool list,
  }) {
    final bool strip = widget.translucent;
    final bool typing = !widget.browsing;
    final bool counter = widget.browsing || search.hits.isNotEmpty;
    // F-TEXT-12: в полосе место дорого — над ней страница, под ней
    // клавиатура. Состояние поиска там встаёт в строку счёта, а не
    // отдельной строкой.
    final bool statusInCounter = strip && typing && counter;
    if (strip) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints limits) {
          // Телефон на боку с высокой клавиатурой: места меньше, чем
          // нужно полю и строке счёта. Остаётся одна строка, и за край
          // полосы ничего не вылезает.
          if (limits.maxHeight < kSearchCrampedExtent) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: typing
                    ? _input(context, theme, search)
                    : _counter(context, theme, search, status: false),
              ),
            );
          }
          return _column(
            context,
            theme,
            search,
            list: list,
            counter: counter,
            statusInCounter: statusInCounter,
          );
        },
      );
    }
    return _column(
      context,
      theme,
      search,
      list: list,
      counter: counter,
      statusInCounter: statusInCounter,
    );
  }

  /// Поле, счёт, состояние и список — сверху вниз.
  Widget _column(
    BuildContext context,
    ThemeData theme,
    DocumentSearch search, {
    required bool list,
    required bool counter,
    required bool statusInCounter,
  }) {
    final bool strip = widget.translucent;
    final bool typing = !widget.browsing;
    return SafeArea(
      // От вырезов экрана полоса отступает только там, где она его краёв
      // касается: нижней полосе верхний вырез не сосед.
      top: !strip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (typing) _input(context, theme, search),
          if (typing && search.isRunning)
            LinearProgressIndicator(
              key: const Key('search-progress'),
              value: search.progress,
            ),
          if (counter)
            _counter(context, theme, search, status: statusInCounter),
          if (typing && !statusInCounter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: _statusText(theme, search),
            ),
          if (list) const Divider(height: 1),
          if (list) Flexible(child: _results(context, theme, search.hits)),
        ],
      ),
    );
  }

  /// Состояние поиска одной строкой.
  ///
  /// На полупрозрачной полосе — основным цветом текста: вторичный над
  /// чужой страницей контраст не держит (`kSearchPanelOpacity`).
  Widget _statusText(
    ThemeData theme,
    DocumentSearch search, {
    bool brief = false,
  }) {
    final TextStyle? style = theme.textTheme.bodySmall;
    return Text(
      _status(search, brief: brief),
      key: const Key('search-status'),
      maxLines: widget.translucent ? 1 : null,
      overflow: widget.translucent ? TextOverflow.ellipsis : null,
      style: widget.translucent
          ? style?.copyWith(color: theme.colorScheme.onSurface)
          : style,
    );
  }

  /// Поле ввода и кнопка, закрывающая поиск.
  Widget _input(BuildContext context, ThemeData theme, DocumentSearch search) {
    final bool strip = widget.translucent;
    final Widget clear = IconButton(
      key: const Key('search-clear'),
      icon: const Icon(Icons.backspace_outlined),
      tooltip: 'Очистить',
      onPressed: () {
        _field.clear();
        search.clear();
      },
    );
    return Padding(
      padding: strip
          ? const EdgeInsets.fromLTRB(12, 8, 4, 4)
          : const EdgeInsets.fromLTRB(16, 16, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Focus(
              onKeyEvent: _onFieldKey,
              child: TextField(
                key: const Key('search-field'),
                controller: _field,
                // Указатель ввода в поле ставит экран чтения, когда
                // открывает поиск. Сам себе поле его не берёт: панель
                // переезжает между местами, и при повороте планшета или
                // расширении окна поле отбирало бы клавиши у страницы, а
                // на телефоне поднимало клавиатуру.
                focusNode: widget.fieldFocus,
                textInputAction: TextInputAction.search,
                // В полосе поле плотное и непрозрачное: набранное и
                // подсказка читаются на своём фоне, а не на чужой
                // странице под полосой (F-TEXT-12).
                decoration: strip
                    ? InputDecoration(
                        hintText: 'Поиск по книге',
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: const OutlineInputBorder(),
                        suffixIcon: clear,
                      )
                    : InputDecoration(
                        labelText: 'Поиск по книге',
                        border: const OutlineInputBorder(),
                        suffixIcon: clear,
                      ),
                onChanged: _onQueryChanged,
                // Enter по уже найденному запросу — это «следующее
                // совпадение», а не «искать то же самое заново»: искать
                // повторно то, что уже найдено, читателю незачем.
                onSubmitted: (String value) {
                  _debounce?.cancel();
                  if (value.trim() == search.query && search.hits.isNotEmpty) {
                    widget.onStep?.call(1);
                    return;
                  }
                  unawaited(search.start(value));
                },
              ),
            ),
          ),
          _closeButton(),
        ],
      ),
    );
  }

  Widget _closeButton() {
    return IconButton(
      key: const Key('search-close'),
      icon: const Icon(Icons.close),
      tooltip: 'Закрыть поиск (Esc)',
      visualDensity: VisualDensity.compact,
      onPressed: widget.onClose,
    );
  }

  /// Строка счёта: `‹ 3 из 17 ›`, а в виде «просмотр» — ещё запрос и
  /// `✕`. В полосе при вводе в ней же стоит состояние поиска ([status]).
  Widget _counter(
    BuildContext context,
    ThemeData theme,
    DocumentSearch search, {
    required bool status,
  }) {
    final int count = search.hits.length;
    final int current = widget.current;
    final bool placed = current >= 0 && current < count;
    final String label = count == 0
        ? 'нет'
        : (placed ? '${current + 1} из $count' : 'из $count');
    final void Function(int step)? step = count == 0 ? null : widget.onStep;
    return SizedBox(
      height: kSearchCounterExtent,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          IconButton(
            key: const Key('search-previous'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Предыдущее совпадение (Shift+F3)',
            visualDensity: VisualDensity.compact,
            onPressed: step == null ? null : () => step(-1),
          ),
          Text(
            label,
            key: const Key('search-count'),
            style: theme.textTheme.bodyMedium,
          ),
          IconButton(
            key: const Key('search-next'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Следующее совпадение (F3)',
            visualDensity: VisualDensity.compact,
            onPressed: step == null ? null : () => step(1),
          ),
          if (widget.browsing)
            Expanded(
              child: InkWell(
                key: const Key('search-query'),
                onTap: widget.onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Text(
                    search.query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            )
          else if (status)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _statusText(theme, search, brief: true),
                ),
              ),
            )
          else
            const Spacer(),
          if (widget.browsing) _closeButton(),
        ],
      ),
    );
  }

  /// Состояние поиска словами.
  ///
  /// [brief] — для строки счёта в полосе: число найденного там уже
  /// стоит, и повторять его незачем.
  ///
  /// Неполный поиск — честное состояние (F-TEXT-04): остаток назван
  /// числом и убывает. Книга без текстового слоя — тоже: «ничего не
  /// найдено» в скане было бы неправдой, искать там не в чем.
  String _status(DocumentSearch search, {bool brief = false}) {
    if (search.query.isEmpty) {
      return 'Введите хотя бы два символа.';
    }
    if (!isSearchableQuery(search.query)) {
      return 'Слишком короткий запрос: нужно хотя бы два символа.';
    }
    if (search.isRunning) {
      final int left = search.unscannedPages;
      if (brief) {
        return 'не просмотрено: $left';
      }
      return 'Не просмотрено страниц: $left. '
          'Найдено: ${search.hits.length}.';
    }
    if (search.bookHasNoText) {
      return 'В этой книге нет текста: это скан.';
    }
    if (search.hits.isEmpty) {
      return 'Ничего не найдено.';
    }
    if (brief) {
      return search.reachedLimit ? 'показаны первые' : '';
    }
    final String suffix = search.reachedLimit
        ? ' Показаны первые — уточните запрос.'
        : '';
    return 'Найдено совпадений: ${search.hits.length}.$suffix';
  }

  Widget _results(BuildContext context, ThemeData theme, List<SearchHit> hits) {
    final TextStyle style = theme.textTheme.bodySmall ?? const TextStyle();
    // Строки одной высоты: место любой из них в списке известно без
    // раскладки, и текущий результат докручивается в видимое счётом.
    // Две строки отрывка — столько помещается при любом кегле системы.
    final double line = MediaQuery.textScalerOf(context)
        .scale((style.fontSize ?? 12) * (style.height ?? 1.4));
    _rowExtent = line * 2 + 20;
    // На полупрозрачной панели пишут только основным цветом текста:
    // вторичный и акцентный над чужой страницей не держат контраст
    // (`kSearchPanelOpacity`).
    final Color ink = theme.colorScheme.onSurface;
    final Color accent = widget.translucent ? ink : theme.colorScheme.secondary;
    return ListView.builder(
      key: const Key('search-results'),
      controller: _scroll,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemExtent: _rowExtent,
      itemCount: hits.length,
      itemBuilder: (BuildContext context, int index) {
        final SearchHit hit = hits[index];
        final bool current = index == widget.current;
        return InkWell(
          key: Key('search-hit-$index'),
          onTap: () => widget.onSelect(hit),
          child: ColoredBox(
            color: current
                ? ink.withValues(alpha: 0.12)
                : const Color(0x00000000),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: <Widget>[
                  // Отметка текущего результата: по ней видно, какой из
                  // них сейчас на странице.
                  SizedBox(
                    width: 20,
                    child: current
                        ? Icon(
                            Icons.arrow_right,
                            key: const Key('search-current'),
                            size: 20,
                            color: ink,
                          )
                        : null,
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${hit.pageNumber}',
                      maxLines: 1,
                      style: style.copyWith(color: ink),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: hit.snippet.substring(
                              0,
                              hit.snippetMatchStart,
                            ),
                          ),
                          TextSpan(
                            text: hit.matchedText,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                          TextSpan(
                            text: hit.snippet.substring(hit.snippetMatchEnd),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
