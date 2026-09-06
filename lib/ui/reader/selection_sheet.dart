import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/columns.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/sheet_placement.dart';
import '../../domain/reading/text_geometry.dart';
import '../../domain/reading/text_highlight.dart';

/// Насколько видим слой, пока им не пользуются.
///
/// Не ноль, и это не придирка к числу. `Opacity(0)` в Flutter **не
/// рисует ребёнка вовсе** (`RenderOpacity` при нулевой альфе выходит из
/// `paint` сразу), а `PdfViewer` просит растр страницы именно из
/// отрисовки — значит, слой с нулевой прозрачностью так и остался бы
/// пустым до первого жеста, и моргание, ради которого всё затевалось,
/// никуда бы не делось. Альфа, округляющаяся до единицы из 255, глазом
/// неотличима от нуля, а отрисовку включает.
const double kSelectionLayerWarmOpacity = 0.004;

/// Место символа, которого на странице нет: пробел, перевод строки.
///
/// Место в списке за ним сохраняется, чтобы индексы не поехали, а
/// рисовать там нечего.
const TextBox _noBox = TextBox(left: 0, top: 0, right: 0, bottom: 0);

/// Слой выделения снаружи: чем экран чтения им управляет.
///
/// Отдельный объект, а не поля виджета, по простой причине: протяжка
/// мышью идёт десятками событий в секунду, и перестраивать на каждое
/// дерево листа вместе с растром страницы значило бы дёргать чтение.
/// Экран говорит слою, что делать, а перестраивается только тогда, когда
/// меняется видимость.
class SelectionLayerController extends ChangeNotifier {
  _SelectionSheetState? _sheet;
  bool _active = false;

  /// Виден ли слой и ловит ли он указатель.
  bool get active => _active;

  /// Читатель начал выделять в точке [at] экрана.
  ///
  /// [word] — выделить слово под пальцем (долгое нажатие) или начать
  /// диапазон с этого места (протяжка мышью).
  void start(Offset at, {required bool word}) {
    final bool was = _active;
    _active = true;
    if (!was) {
      notifyListeners();
    }
    _sheet?.beginAt(at, word: word);
  }

  /// Читатель ведёт выделение к точке [at].
  void extendTo(Offset at) {
    if (_active) {
      _sheet?.extendTo(at);
    }
  }

  /// Выделение снято.
  void dismiss() {
    _sheet?.clear();
    if (!_active) {
      return;
    }
    _active = false;
    notifyListeners();
  }

  void _attach(_SelectionSheetState sheet) => _sheet = sheet;

  void _detach(_SelectionSheetState sheet) {
    if (identical(_sheet, sheet)) {
      _sheet = null;
    }
  }
}

/// Слой выделения поверх листа.
///
/// **Почему он вообще есть.** Постраничное чтение с S4.2 рисует страницы
/// собственным виджетом (`ReaderSheet` через `PdfPageView`), а вся работа
/// с выделением в pdfrx заперта внутри `PdfViewer`: ручки, лупа над
/// ручкой, слово по нажатию, правка выделения после отпускания.
/// `PdfPageView` не умеет из этого ничего.
///
/// Решение владельца от 06.09.2026: **чтение остаётся жёсткой раскладкой,
/// а `PdfViewer` поднимается над листом** — в той же раскладке и в том же
/// масштабе. Ради этого его матрица приколочена (`normalizeMatrix`
/// возвращает нашу, а не свою), панорама и зум выключены, поля убраны, а
/// страницы разложены нашей собственной функцией.
///
/// **Слой стоит на месте заранее, а не создаётся жестом** (правка S6.1 по
/// проверке 06.09.2026). Виджет, поднятый в момент касания, рисует свою
/// копию страницы с нуля, и первый его кадр приходит не сразу — на ПК это
/// читалось как отчётливое моргание. Теперь слой смонтирован всё время,
/// пока читатель на странице: он уже нарисован, а жест только делает его
/// видимым и отдаёт ему указатель. Рисовать в этот момент нечего, поэтому
/// и моргать нечему.
///
/// Цена — страница живёт в памяти в двух растрах. Она ограничена
/// намеренно: запас кэша сведён к нулю, чтобы просмотрщик не рисовал
/// соседние страницы, которых в нашей раскладке всё равно не видно, а
/// потолок кэша опущен со ста мегабайт до восьми — больше одной страницы
/// сюда и не должно помещаться.
class SelectionSheet extends StatefulWidget {
  /// Создаёт слой выделения.
  const SelectionSheet({
    required this.document,
    required this.pages,
    required this.placement,
    required this.transform,
    required this.selection,
    required this.onSelection,
    this.columnsOf,
    this.onTap,
    super.key,
  });

  /// Потолок кэша растров слоя.
  ///
  /// У pdfrx по умолчанию сто мегабайт: он рассчитан на ленту, где
  /// страницы прокручивают. У нас на экране всегда одна страница или
  /// разворот, и всё, что сверх них, — забытая память.
  static const int imageCacheBytes = 8 * 1024 * 1024;

  /// Открытый документ — тот же, которым рисует лист.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Раскладка листа: масштаб и место на экране.
  final SheetPlacement placement;

  /// Преобразование, которое читатель добавил щипком. Единичное, когда
  /// замок заперт.
  final Matrix4 transform;

  /// Управление слоем со стороны экрана чтения.
  final SelectionLayerController selection;

  /// Колонки страницы: без них точка в конце левой колонки уехала бы в
  /// текст, стоящий справа на той же высоте.
  final Future<List<ColumnBand>> Function(int pageNumber)? columnsOf;

  /// Выделение изменилось. Пустой список означает, что выделения нет.
  final void Function(List<PdfPageTextRange> ranges) onSelection;

  /// Нажатие мимо выделения: экран чтения решает, листать или снять
  /// выделение. Зоны листания обязаны работать и поверх слоя.
  final void Function(Offset localPosition)? onTap;

  @override
  State<SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<SelectionSheet> {
  final PdfViewerController _viewer = PdfViewerController();

  /// Слои текста страниц в счёте самого просмотрщика.
  ///
  /// Нарочно **не** те, что у контроллера чтения. У pdfrx два разных
  /// текста страницы: сырой (`loadText`) и разобранный на строки и слова
  /// (`loadStructuredText`), и они отличаются — лишние пробелы склеены,
  /// переводы строк добавлены. Места выделения просмотрщик считает по
  /// второму, поэтому и мы здесь считаем по нему: иначе диапазон,
  /// отданный ему по нашим числам, лёг бы на соседние буквы.
  final Map<int, PageTextLayout> _layouts = <int, PageTextLayout>{};
  final Map<int, PdfPageText> _texts = <int, PdfPageText>{};

  PdfTextSelectionPoint? _anchor;
  bool _ready = false;
  bool _extending = false;
  Offset? _queued;
  Offset? _pendingStart;
  bool _pendingWord = true;

  @override
  void initState() {
    super.initState();
    widget.selection._attach(this);
  }

  @override
  void didUpdateWidget(SelectionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection._detach(this);
      widget.selection._attach(this);
    }
    // Читатель перелистнул или сменил режим — слой обязан переехать
    // следом, и **сразу**, а не в момент следующего жеста. В этом весь
    // смысл: к тому времени, когда читатель начнёт выделять, страница у
    // слоя уже нарисована. Сам он этого не заметит: своей матрицей он не
    // распоряжается, она приколочена к раскладке листа.
    final bool moved =
        !_samePages(oldWidget.pages, widget.pages) ||
        oldWidget.placement != widget.placement ||
        oldWidget.transform != widget.transform;
    if (!moved) {
      return;
    }
    _anchor = null;
    _queued = null;
    _forgetPagesOutsideSheet();
    if (_ready) {
      unawaited(
        _viewer.goTo(
          sheetMatrix(
            placement: widget.placement,
            documentLeft: _documentLeft(),
            transform: widget.transform,
          ),
          duration: Duration.zero,
        ),
      );
    }
  }

  bool _samePages(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Разобранные страницы держатся только для листа на экране.
  ///
  /// Иначе за долгое чтение здесь скопился бы текст всей книги с
  /// прямоугольником на каждый символ — а нужен он ровно там, где сейчас
  /// водят пальцем.
  void _forgetPagesOutsideSheet() {
    _layouts.removeWhere(
      (int page, PageTextLayout layout) => !widget.pages.contains(page),
    );
    _texts.removeWhere(
      (int page, PdfPageText text) => !widget.pages.contains(page),
    );
  }

  @override
  void dispose() {
    widget.selection._detach(this);
    super.dispose();
  }

  /// Читатель начал выделять в точке экрана.
  ///
  /// **Первый жест не пропадает.** Слой стоит невидимым и указателя не
  /// ловит вовсе — иначе он забрал бы себе зоны листания, — поэтому
  /// касания, которым выделение началось, он не видел. Намерение
  /// читателя повторяется здесь программно: слово под пальцем или начало
  /// диапазона под курсором.
  void beginAt(Offset screen, {required bool word}) {
    _anchor = null;
    _queued = null;
    if (!_ready) {
      // Жест пришёл раньше, чем просмотрщик встал на место: так бывает на
      // первой же странице книги. Точка запоминается и отрабатывает по
      // готовности — молча потерянный жест хуже задержки.
      _pendingStart = screen;
      _pendingWord = word;
      return;
    }
    unawaited(_startAt(screen, word: word));
  }

  /// Читатель ведёт выделение.
  void extendTo(Offset screen) {
    _queued = screen;
    if (_extending) {
      return;
    }
    unawaited(_drain());
  }

  /// Выделение снято.
  void clear() {
    _anchor = null;
    _queued = null;
    _pendingStart = null;
    if (_ready) {
      unawaited(_viewer.textSelectionDelegate.clearTextSelection());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Цвет выделения просмотрщик берёт из темы, а не из своих настроек:
    // `textSelectionTheme` задаётся один раз на приложение, и выделение
    // в книге красится тем же, чем выделение в любом поле ввода.
    return PdfViewer(
      // Тот же открытый документ, что и у листа: второе открытие книги
      // стоило бы вдвое больше памяти и отдавало бы страницы не сразу.
      PdfDocumentRefDirect(widget.document, autoDispose: false),
      controller: _viewer,
      initialPageNumber: widget.pages.isEmpty ? 1 : widget.pages.first,
      params: PdfViewerParams(
        backgroundColor: Colors.transparent,
        margin: 0,
        pageDropShadow: null,
        // Ни двигать, ни масштабировать: читатель сейчас выделяет, а не
        // листает. Страница обязана стоять там же, где стояла до того,
        // как слой поднялся, — иначе выделение начиналось бы с прыжка.
        panEnabled: false,
        scaleEnabled: false,
        // Клавиши принадлежат экрану чтения: листание и поиск работают
        // и при выделенном тексте, а собственная навигация просмотрщика
        // увела бы его страницу от нашей.
        enableKeyboardNavigation: false,
        horizontalCacheExtent: 0,
        verticalCacheExtent: 0,
        maxImageBytesCachedOnMemory: SelectionSheet.imageCacheBytes,
        behaviorControlParams: const PdfViewerBehaviorControlParams(
          // Ступенька «мыло → резкость» на подъёме слоя читается как то
          // же самое моргание, от которого уходим. Слой рисуется заранее
          // и торопиться ему некуда — пусть сразу рисует резко.
          enableLowResolutionPagePreview: false,
        ),
        layoutPages: _layoutPages,
        normalizeMatrix: _pin,
        textSelectionParams: PdfTextSelectionParams(
          // Ручки включены и на ПК тоже. Это главный UX-риск проекта, и
          // проверять его владелец будет и пальцем, и мышью — значит,
          // и там и там должно быть что тянуть.
          enableSelectionHandles: true,
          showContextMenuAutomatically: false,
          magnifier: const PdfViewerSelectionMagnifierParams(enabled: true),
          onTextSelectionChange: _onSelectionChange,
        ),
        // Своё меню, а не системное: над выделением стоит панель с
        // промптами читателя, и второе меню поверх неё ни к чему.
        buildContextMenu: (BuildContext context, _) => null,
        onViewerReady: _onReady,
        onGeneralTap:
            (
              BuildContext context,
              PdfViewerController controller,
              PdfViewerGeneralTapHandlerDetails details,
            ) {
              if (details.type == PdfViewerGeneralTapType.tap &&
                  details.tapOn != PdfViewerPart.selectedText) {
                widget.onTap?.call(details.localPosition);
                return true;
              }
              return false;
            },
      ),
    );
  }

  /// Страницы в один ряд, вплотную и без полей.
  ///
  /// Ровно так их кладёт `ReaderSheet`: страницы разворота стоят рядом,
  /// верхними краями по одной линии. Совпадение раскладки — единственное,
  /// что делает подмену незаметной.
  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) {
    final List<Rect> rects = <Rect>[];
    double x = 0;
    double height = 0;
    for (final PdfPage page in pages) {
      rects.add(Rect.fromLTWH(x, 0, page.width, page.height));
      x += page.width;
      if (page.height > height) {
        height = page.height;
      }
    }
    return PdfPageLayout(
      pageLayouts: rects,
      documentSize: Size(x <= 0 ? 1 : x, height <= 0 ? 1 : height),
    );
  }

  /// Матрица, приколоченная к раскладке листа.
  ///
  /// Просмотрщик зовёт это на каждое изменение матрицы и берёт ответ как
  /// есть — своё ограничение границами он при этом не применяет вовсе.
  /// Поэтому страница не уезжает ни от инерции, ни от случайного жеста,
  /// ни от собственных попыток просмотрщика что-нибудь подровнять.
  Matrix4 _pin(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    return sheetMatrix(
      placement: widget.placement,
      documentLeft: _documentLeft(),
      transform: widget.transform,
    );
  }

  /// Смещение первой страницы листа в координатах документа.
  double _documentLeft() {
    if (widget.pages.isEmpty) {
      return 0;
    }
    final List<PdfPage> pages = widget.document.pages;
    double left = 0;
    for (int i = 1; i < widget.pages.first && i <= pages.length; i++) {
      left += pages[i - 1].width;
    }
    return left;
  }

  void _onReady(PdfDocument document, PdfViewerController controller) {
    _ready = true;
    final Offset? pending = _pendingStart;
    if (pending == null) {
      return;
    }
    _pendingStart = null;
    final bool word = _pendingWord;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startAt(pending, word: word));
      }
    });
  }

  Future<void> _startAt(Offset screen, {required bool word}) async {
    final Offset? point = _documentPoint(screen);
    if (point == null || !mounted) {
      return;
    }
    if (word) {
      await _viewer.textSelectionDelegate.selectWord(point);
      return;
    }
    final PdfTextSelectionPoint? anchor = await _pointAt(point);
    if (!mounted) {
      return;
    }
    if (anchor == null) {
      // Геометрии у страницы нет (скан) — тянуть нечего. Слово по нажатию
      // просмотрщик всё равно попробует найти, и если найдёт, читатель
      // получит хоть что-то.
      await _viewer.textSelectionDelegate.selectWord(point);
      return;
    }
    _anchor = anchor;
    await _viewer.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(anchor, anchor),
    );
  }

  /// Отдаёт просмотрщику диапазон, пока читатель ведёт указатель.
  ///
  /// События протяжки приходят чаще, чем успевает разобраться страница,
  /// поэтому берётся всегда **последняя** точка, а промежуточные
  /// выбрасываются: очередь из устаревших диапазонов — это выделение,
  /// отстающее от курсора.
  Future<void> _drain() async {
    _extending = true;
    try {
      while (mounted) {
        final Offset? next = _queued;
        final PdfTextSelectionPoint? anchor = _anchor;
        if (next == null || anchor == null) {
          return;
        }
        _queued = null;
        final Offset? point = _documentPoint(next);
        if (point == null) {
          continue;
        }
        final PdfTextSelectionPoint? focus = await _pointAt(point);
        if (focus == null || !mounted) {
          continue;
        }
        await _viewer.textSelectionDelegate.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(anchor, focus),
        );
      }
    } finally {
      _extending = false;
    }
  }

  Offset? _documentPoint(Offset screen) {
    return documentPoint(
      screen: screen,
      placement: widget.placement,
      documentLeft: _documentLeft(),
      transform: widget.transform,
    );
  }

  /// Место в тексте страницы под точкой документа.
  Future<PdfTextSelectionPoint?> _pointAt(Offset point) async {
    final PdfPage? page = _pageAt(point.dx);
    if (page == null) {
      return null;
    }
    final PageTextLayout layout = await _layoutFor(page);
    final PdfPageText? text = _texts[page.pageNumber];
    if (text == null || !layout.hasGeometry) {
      return null;
    }
    final List<ColumnBand> columns =
        await widget.columnsOf?.call(page.pageNumber) ?? const <ColumnBand>[];
    final int? index = indexAtPoint(
      layout: layout,
      x: (point.dx - _leftOf(page)) / page.width,
      y: point.dy / page.height,
      columns: columns,
    );
    if (index == null) {
      return null;
    }
    final int? rect = charRectIndex(
      text.fullText,
      index,
      text.charRects.length,
    );
    return rect == null ? null : PdfTextSelectionPoint(text, rect);
  }

  /// Страница под координатой [x] документа.
  ///
  /// Промах мимо всех страниц возможен: читатель ведёт курсор и за край
  /// листа. Слева и справа он прижимается к крайней странице — выделение,
  /// обрывающееся оттого, что рука вышла за поле, выглядит поломкой.
  PdfPage? _pageAt(double x) {
    final List<PdfPage> pages = widget.document.pages;
    if (pages.isEmpty) {
      return null;
    }
    double left = 0;
    for (final PdfPage page in pages) {
      final double right = left + page.width;
      if (x < right) {
        return page;
      }
      left = right;
    }
    return pages.last;
  }

  double _leftOf(PdfPage target) {
    double left = 0;
    for (final PdfPage page in widget.document.pages) {
      if (page.pageNumber == target.pageNumber) {
        return left;
      }
      left += page.width;
    }
    return left;
  }

  /// Слой текста страницы в счёте просмотрщика, с кэшем на страницу.
  Future<PageTextLayout> _layoutFor(PdfPage page) async {
    final PageTextLayout? ready = _layouts[page.pageNumber];
    if (ready != null) {
      return ready;
    }
    PdfPageText text;
    try {
      text = await page.loadStructuredText();
    } on Object {
      // Испорченный текстовый слой — не повод ронять выделение.
      return PageTextLayout.empty;
    }
    final double width = page.width;
    final double height = page.height;
    final List<TextBox> boxes = <TextBox>[
      for (final PdfRect rect in text.charRects)
        _boxOf(rect, page, width, height),
    ];
    final PageTextLayout layout = PageTextLayout(
      text: text.fullText,
      boxes: boxes.length == text.fullText.length ? boxes : const <TextBox>[],
    );
    if (!mounted) {
      return layout;
    }
    _texts[page.pageNumber] = text;
    _layouts[page.pageNumber] = layout;
    return layout;
  }

  TextBox _boxOf(PdfRect rect, PdfPage page, double width, double height) {
    if (rect.isEmpty || width <= 0 || height <= 0) {
      return _noBox;
    }
    final Rect display = rect.toRect(page: page);
    final TextBox box = TextBox(
      left: (display.left / width).clamp(0.0, 1.0),
      top: (display.top / height).clamp(0.0, 1.0),
      right: (display.right / width).clamp(0.0, 1.0),
      bottom: (display.bottom / height).clamp(0.0, 1.0),
    );
    return box.isValid ? box : _noBox;
  }

  void _onSelectionChange(PdfTextSelection selection) {
    unawaited(_reportSelection(selection));
  }

  Future<void> _reportSelection(PdfTextSelection selection) async {
    final List<PdfPageTextRange> ranges = await selection
        .getSelectedTextRanges();
    if (!mounted) {
      return;
    }
    widget.onSelection(ranges);
  }
}

/// Матрица просмотрщика, повторяющая раскладку листа.
///
/// Договор pdfrx простой: `экран = документ × масштаб + сдвиг`, масштаб
/// лежит в первой ячейке матрицы. Лист вписан в экран нашей математикой,
/// поэтому масштаб берётся из раскладки, а сдвиг — из места листа на
/// экране за вычетом того, где лист лежит в документе.
///
/// Щипок читателя (когда замок отперт) добавляется сверху обычным
/// умножением: и то, и другое — только сдвиг и масштаб, поэтому
/// произведение снова оказывается сдвигом и масштабом, а другого
/// просмотрщик и не ждёт.
Matrix4 sheetMatrix({
  required SheetPlacement placement,
  required double documentLeft,
  Matrix4? transform,
}) {
  final double zoom = placement.scale;
  final Matrix4 base = Matrix4.zero();
  base.setEntry(0, 0, zoom);
  base.setEntry(1, 1, zoom);
  base.setEntry(2, 2, zoom);
  base.setEntry(3, 3, 1);
  base.setEntry(0, 3, placement.left - documentLeft * zoom);
  base.setEntry(1, 3, placement.top);
  if (transform == null) {
    return base;
  }
  return transform.multiplied(base);
}

/// Переводит точку экрана в координаты документа просмотрщика.
///
/// Возвращает `null`, если переводить не во что: пустая раскладка или
/// вырожденный масштаб.
Offset? documentPoint({
  required Offset screen,
  required SheetPlacement placement,
  required double documentLeft,
  Matrix4? transform,
}) {
  final Matrix4 matrix = sheetMatrix(
    placement: placement,
    documentLeft: documentLeft,
    transform: transform,
  );
  final double zoom = matrix.storage[0];
  if (!zoom.isFinite || zoom <= 0) {
    return null;
  }
  return Offset(
    (screen.dx - matrix.storage[12]) / zoom,
    (screen.dy - matrix.storage[13]) / zoom,
  );
}
