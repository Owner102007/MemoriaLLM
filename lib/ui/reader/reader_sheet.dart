import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/progress_slot.dart';
import '../../domain/reading/reader_gestures.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/sheet_placement.dart';
import '../../domain/reading/sheet_transform.dart';
import 'reader_mask.dart';
import 'reading_progress_book.dart';

/// Где сейчас лежит лист: раскладка плюс то, что читатель добавил щипком.
///
/// Экрану чтения это нужно затем, чтобы поставить панель действий над
/// выделением и подсветку на найденное: место и того, и другого известно в
/// долях страницы, а рисуются они на экране.
class SheetView {
  /// Создаёт вид листа.
  const SheetView({required this.placement, required this.transform});

  /// Куда положен лист.
  final SheetPlacement placement;

  /// Что читатель добавил сам; единичное, когда замок заперт.
  final SheetTransform transform;

  /// Переводит точку листа (в точках PDF) в точку экрана.
  Offset toScreen(double x, double y) {
    return transform.apply(
      Offset(
        placement.left + x * placement.scale,
        placement.top + y * placement.scale,
      ),
    );
  }
}

/// Управление листом снаружи.
///
/// Ровно одна нужда: снять выделение, не трогая страницу. Нажатие в
/// середину экрана, `Esc` и сохранение цитаты убирают выделение вместе с
/// панелью, а живёт оно внутри просмотрщика.
class ReaderSheetController {
  _ReaderSheetState? _sheet;

  /// Снять выделение.
  void clearSelection() => _sheet?._clearSelection();

  void _attach(_ReaderSheetState sheet) => _sheet = sheet;

  void _detach(_ReaderSheetState sheet) {
    if (identical(_sheet, sheet)) {
      _sheet = null;
    }
  }
}

/// Лист книги на экране: один просмотрщик, жёсткая раскладка, маска сверху.
///
/// Читалка не наводит объектив на кусок страницы, а кладёт лист так, что
/// читаемая часть занимает экран целиком. Масштаб определяется размерами
/// листа и экрана — одинаковый на каждой странице книги.
///
/// **Второго слоя нет** (решение владельца от 06.09.2026, по проверке S6.1
/// на ПК; отменяет подмену листа из S6). Страницу рисует один `PdfViewer`,
/// а читательская рамка стала **позицией плюс маской**:
///
/// 1. **Позиция.** Матрица просмотрщика приколочена к нашей раскладке —
///    `normalizeMatrix` возвращает нашу матрицу, а не его. Масштаб считаем
///    мы, а не жест, и он одинаков на каждой странице книги.
/// 2. **Маска.** Поверх — [ReaderMask] в координатах экрана, двух уровней:
///    за пределами листа фон наглухо (иначе на широком окне видны соседние
///    страницы — ровно то, на чём сломалась S6.1), на листе вне читаемой
///    полосы — затемнение по настройке. Страница не обрезана: она
///    продолжается в темноте.
///
/// **Замок решает, можно ли трогать страницу.** Заперт — любая попытка
/// сдвинуть или приблизить возвращает матрицу на место, страница стоит
/// там, где её положили. Отперт — пан и зум принадлежат просмотрщику, и
/// он же разводит их с выделением: мышью протяжка по тексту выделяет,
/// протяжка мимо текста двигает страницу; пальцем протяжка двигает,
/// удержание выделяет. Проверено по исходникам pdfrx 2.6.1: так работает
/// `enableSelectionHandles`, оставленный по умолчанию.
class ReaderSheet extends StatefulWidget {
  /// Создаёт лист.
  const ReaderSheet({
    required this.document,
    required this.pages,
    required this.fragment,
    required this.background,
    required this.page,
    required this.pageCount,
    required this.locked,
    this.stripFit = 1,
    this.dim = kDefaultDimOutside,
    this.sheetController,
    this.onSelection,
    this.onTap,
    this.overlay,
    super.key,
  });

  /// Открытый документ.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Какую часть листа читают сейчас, в долях листа.
  final CropBox fragment;

  /// Фон вокруг страницы.
  final Color background;

  /// Текущая страница для указателя места.
  final int page;

  /// Всего страниц в книге.
  final int pageCount;

  /// Заперт ли масштаб.
  final bool locked;

  /// Запас по краям полосы: 1 — вписана вплотную.
  final double stripFit;

  /// Сила затемнения нечитаемой части страницы.
  final double dim;

  /// Рычаги к листу снаружи.
  final ReaderSheetController? sheetController;

  /// Выделение изменилось. Пустой список означает, что выделения нет.
  final void Function(List<PdfPageTextRange> ranges)? onSelection;

  /// Нажатие по странице мимо выделенного текста: экран чтения решает,
  /// листать, снять выделение или показать панели.
  final void Function(Offset localPosition)? onTap;

  /// Что нарисовать поверх листа: подсветка найденного, панель действий.
  final Widget Function(BuildContext context, SheetView view)? overlay;

  @override
  State<ReaderSheet> createState() => _ReaderSheetState();
}

class _ReaderSheetState extends State<ReaderSheet> {
  /// Указатели, которыми выделяют удержанием, а не протяжкой.
  static final Set<PointerDeviceKind> _holdDevices = <PointerDeviceKind>{
    for (final PointerDeviceKind kind in PointerDeviceKind.values)
      if (!selectionStartsOnDrag(kind)) kind,
  };

  final PdfViewerController _viewer = PdfViewerController();

  /// Раскладка последнего построения: её же спрашивает [_pin].
  SheetPlacement _placement = SheetPlacement.none;

  /// Что читатель добавил к раскладке сам.
  SheetTransform _transform = SheetTransform.none;

  Size _screen = Size.zero;
  bool _ready = false;

  /// Раскладка и страницы, до которых просмотрщик уже доехал.
  SheetPlacement? _appliedPlacement;
  List<int> _appliedPages = const <int>[];

  PdfDocument? _refFor;
  PdfDocumentRefDirect? _ref;

  /// Ссылка на открытый документ, одна и та же между перестроениями.
  ///
  /// Новый экземпляр на каждый кадр просмотрщик считал бы за смену
  /// документа: при отпертом замке дерево перестраивается на каждое
  /// движение пальца, и книга перезагружалась бы под руками.
  PdfDocumentRefDirect get _documentRef {
    if (!identical(_refFor, widget.document)) {
      _refFor = widget.document;
      _ref = PdfDocumentRefDirect(widget.document, autoDispose: false);
    }
    return _ref!;
  }

  @override
  void initState() {
    super.initState();
    widget.sheetController?._attach(this);
    _viewer.addListener(_onMatrixChanged);
  }

  @override
  void didUpdateWidget(ReaderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sheetController, widget.sheetController)) {
      oldWidget.sheetController?._detach(this);
      widget.sheetController?._attach(this);
    }
    // Замок захлопнулся — страница замирает как есть. Но если её только
    // сдвинули, не меняя масштаба, сдвиг снимается: смещённая на палец
    // страница выглядит не выбором читателя, а поломкой, и вернуть её при
    // запертом замке было бы нечем.
    if (widget.locked && !oldWidget.locked && _transform.isNeutral) {
      _transform = SheetTransform.none;
      _sync();
    }
  }

  @override
  void dispose() {
    widget.sheetController?._detach(this);
    _viewer.removeListener(_onMatrixChanged);
    super.dispose();
  }

  /// Читатель подвинул или приблизил страницу.
  ///
  /// Пока замок заперт, матрица возвращается на место в [_pin], и слушать
  /// нечего. Отперев его, читатель двигает страницу — а вместе с ней
  /// обязаны ехать и маска, и подсветка, и панель над выделением.
  void _onMatrixChanged() {
    if (!mounted || widget.locked || !_ready || !_placement.isVisible) {
      return;
    }
    final SheetTransform next = sheetTransformOf(
      matrix: _viewer.value,
      placement: _placement,
      documentLeft: _documentLeft(),
    );
    if (next == _transform) {
      return;
    }
    // Матрицу просмотрщик меняет и во время собственной раскладки, а
    // `setState` посреди построения дерева — исключение. Тогда правка
    // откладывается на конец кадра: маска отстанет на кадр, но не уронит
    // чтение.
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _transform = next);
        }
      });
      return;
    }
    setState(() => _transform = next);
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    _ready = true;
    _sync();
  }

  /// Ставит просмотрщик туда, где по нашей раскладке лежит лист.
  ///
  /// `goTo` с нулевой длительностью проходит через [_pin] и своего
  /// ограничения границами при этом не применяет вовсе — матрица встаёт
  /// ровно нашей.
  void _sync() {
    if (!_ready || !_placement.isVisible) {
      return;
    }
    unawaited(_viewer.goTo(_target(), duration: Duration.zero));
  }

  Matrix4 _target() {
    return sheetMatrix(
      placement: _placement,
      documentLeft: _documentLeft(),
      transform: _transform,
    );
  }

  /// Матрица, приколоченная к раскладке листа.
  ///
  /// Просмотрщик зовёт это на каждое изменение матрицы и берёт ответ как
  /// есть. Заперт замок — возвращается наша матрица, и страница не уезжает
  /// ни от инерции, ни от случайного жеста. Отперт — берётся предложенная,
  /// но в разумных пределах: страницу нельзя ни увести с экрана целиком,
  /// ни уменьшить до точки.
  Matrix4 _pin(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    if (!_placement.isVisible) {
      return matrix;
    }
    if (widget.locked) {
      return _target();
    }
    final double documentLeft = _documentLeft();
    final SheetTransform clamped = clampSheetTransform(
      transform: sheetTransformOf(
        matrix: matrix,
        placement: _placement,
        documentLeft: documentLeft,
      ),
      placement: _placement,
      screen: viewSize,
    );
    return sheetMatrix(
      placement: _placement,
      documentLeft: documentLeft,
      transform: clamped,
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

  /// Страницы в один ряд, вплотную и без полей.
  ///
  /// Соседние страницы при этом остаются в раскладке — их закрывает
  /// маска, а не отсутствие. Убрать их из раскладки нельзя: номера
  /// страниц и места в тексте считаются по всему документу.
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

  bool _onGeneralTap(
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
    widget.onSelection?.call(ranges);
  }

  void _clearSelection() {
    if (_ready) {
      unawaited(_viewer.textSelectionDelegate.clearTextSelection());
    }
  }

  /// Выделить слово под пальцем.
  ///
  /// Своё долгое нажатие, а не то, что у просмотрщика: у него порог —
  /// стандартные полсекунды, а владелец на проверке S6 назвал это
  /// «слишком долго». Наш распознаватель объявляет победу раньше, поэтому
  /// нажатие просмотрщика до дела не доходит, а делает он ровно то же
  /// самое — [PdfTextSelectionDelegate.selectWord].
  void _selectWordAt(Offset screen) {
    if (!_ready || !_placement.isVisible) {
      return;
    }
    final Offset? point = documentPoint(
      screen: screen,
      placement: _placement,
      documentLeft: _documentLeft(),
      transform: _transform,
    );
    if (point == null) {
      return;
    }
    unawaited(_viewer.textSelectionDelegate.selectWord(point));
  }

  @override
  Widget build(BuildContext context) {
    final List<PdfPage> sheet = <PdfPage>[
      for (final int number in widget.pages)
        if (number >= 1 && number <= widget.document.pages.length)
          widget.document.pages[number - 1],
    ];
    if (sheet.isEmpty) {
      // Молчаливый чёрный прямоугольник — худший из возможных ответов:
      // по нему не отличить «страница ещё грузится» от «книга сломана».
      return ColoredBox(
        color: widget.background,
        child: const Center(
          child: SizedBox(
            key: Key('reader-sheet-waiting'),
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    double sheetWidth = 0;
    double sheetHeight = 0;
    for (final PdfPage page in sheet) {
      sheetWidth += page.width;
      sheetHeight = sheetHeight < page.height ? page.height : sheetHeight;
    }

    return ColoredBox(
      color: widget.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints limits) {
          final SheetPlacement placement = placeFragment(
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            fragment: widget.fragment,
            screenWidth: limits.maxWidth,
            screenHeight: limits.maxHeight,
            fit: widget.stripFit,
          );
          _placement = placement;
          _screen = Size(limits.maxWidth, limits.maxHeight);
          if (!placement.isVisible) {
            return const SizedBox.expand();
          }
          _scheduleSync(placement);

          final SheetView view = SheetView(
            placement: placement,
            transform: _transform,
          );
          return Stack(
            children: <Widget>[
              Positioned.fill(child: _buildViewer()),
              Positioned.fill(
                child: ReaderMask(
                  key: const Key('reader-mask'),
                  sheet: sheetRectOnScreen(
                    placement: placement,
                    transform: _transform,
                  ),
                  strip: stripRectOnScreen(
                    placement: placement,
                    fragment: widget.fragment,
                    transform: _transform,
                  ),
                  dim: widget.dim,
                  background: widget.background,
                ),
              ),
              // Без `IgnorePointer` намеренно: подсветка нажатий не ловит
              // (у неё нет своей области), а панель действий обязана их
              // ловить — она и есть то, ради чего выделяют.
              if (widget.overlay != null)
                Positioned.fill(child: widget.overlay!(context, view)),
              // Указатель места живёт поверх маски: гасить его вместе со
              // страницей незачем, а терять при листании — тем более.
              ReadingProgressBook(
                slot: progressSlotFor(
                  placement: placement,
                  screenWidth: _screen.width,
                  screenHeight: _screen.height,
                ),
                page: widget.page,
                pageCount: widget.pageCount,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Довозит просмотрщик до новой раскладки — но не во время построения.
  void _scheduleSync(SheetPlacement placement) {
    if (placement == _appliedPlacement && _samePages(_appliedPages)) {
      return;
    }
    _appliedPlacement = placement;
    _appliedPages = List<int>.of(widget.pages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sync();
      }
    });
  }

  bool _samePages(List<int> other) {
    if (other.length != widget.pages.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (other[i] != widget.pages[i]) {
        return false;
      }
    }
    return true;
  }

  Widget _buildViewer() {
    // Своё долгое нажатие поверх просмотрщика: порог у него стандартный,
    // полсекунды, а нужно «почти моментально». Распознаватель спорит в
    // общей арене на равных — быстрое касание он проигрывает, и зоны
    // листания живут как жили.
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: kTouchSelectionDelay,
                supportedDevices: _holdDevices,
              ),
              (LongPressGestureRecognizer instance) {
                instance.onLongPressStart = (LongPressStartDetails details) =>
                    _selectWordAt(details.localPosition);
              },
            ),
      },
      child: PdfViewer(
        // Тот же открытый документ, что и у контроллера чтения: второе
        // открытие книги стоило бы вдвое больше памяти и отдавало бы
        // страницы не сразу.
        _documentRef,
        controller: _viewer,
        initialPageNumber: widget.pages.isEmpty ? 1 : widget.pages.first,
        params: PdfViewerParams(
          backgroundColor: widget.background,
          margin: 0,
          pageDropShadow: null,
          // Пан и зум просмотрщику не запрещены вовсе, и это не оплошность.
          // Замок живёт в [_pin]: заперт — любая предложенная матрица
          // заменяется нашей, и страница стоит намертво. Запрещать их
          // параметрами значило бы пересобирать просмотрщик на каждое
          // нажатие замка, а заодно ронять кэш растров.
          //
          // Клавиши у просмотрщика отобраны целиком: листание принадлежит
          // экрану чтения, а его собственная навигация увела бы страницу
          // от нашей. Выключается это `keyHandlerParams`, а не
          // `enableKeyboardNavigation`: последний в pdfrx 2.6.1 нигде не
          // читается — параметр остался, а поведение из него ушло.
          keyHandlerParams: const PdfViewerKeyHandlerParams(enabled: false),
          // Соседних страниц на экране нет — их закрывает маска. Рисовать
          // их про запас значит платить памятью за невидимое.
          horizontalCacheExtent: 0,
          verticalCacheExtent: 0,
          // Ступенька «мыло → резкость» читается как моргание. Страница у
          // нас одна и торопиться ей некуда — пусть сразу рисует резко.
          behaviorControlParams: const PdfViewerBehaviorControlParams(
            enableLowResolutionPagePreview: false,
          ),
          layoutPages: _layoutPages,
          normalizeMatrix: _pin,
          textSelectionParams: PdfTextSelectionParams(
            // Ручки и лупа оставлены на усмотрение указателя, и это
            // главное в сегодняшней правке. По исходникам pdfrx: с
            // ручками протяжка по тексту выключена вовсе, а без них —
            // включена. Значение по умолчанию решает это по устройству:
            // палец получает ручки и удержание, мышь — протяжку сразу.
            showContextMenuAutomatically: false,
            onTextSelectionChange: _onSelectionChange,
          ),
          // Своё меню, а не системное: над выделением стоит панель с
          // промптами читателя, и второе меню поверх неё ни к чему.
          buildContextMenu: _noContextMenu,
          onViewerReady: _onViewerReady,
          onGeneralTap: _onGeneralTap,
        ),
      ),
    );
  }
}

/// Системного меню над выделением нет: над ним стоит наша панель.
Widget? _noContextMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) => null;

/// Матрица просмотрщика, повторяющая раскладку листа.
///
/// Договор pdfrx простой: `экран = документ × масштаб + сдвиг`, масштаб
/// лежит в первой ячейке матрицы. Лист вписан в экран нашей математикой,
/// поэтому масштаб берётся из раскладки, а сдвиг — из места листа на
/// экране за вычетом того, где лист лежит в документе.
///
/// То, что читатель добавил сам, накладывается сверху: и то, и другое —
/// только сдвиг и масштаб, поэтому произведение снова оказывается сдвигом
/// и масштабом, а другого просмотрщик и не ждёт.
Matrix4 sheetMatrix({
  required SheetPlacement placement,
  required double documentLeft,
  SheetTransform transform = SheetTransform.none,
}) {
  final double zoom = placement.scale * transform.scale;
  final Matrix4 matrix = Matrix4.zero();
  matrix.setEntry(0, 0, zoom);
  matrix.setEntry(1, 1, zoom);
  matrix.setEntry(2, 2, zoom);
  matrix.setEntry(3, 3, 1);
  matrix.setEntry(
    0,
    3,
    (placement.left - documentLeft * placement.scale) * transform.scale +
        transform.dx,
  );
  matrix.setEntry(1, 3, placement.top * transform.scale + transform.dy);
  return matrix;
}

/// Обратный ход: что читатель добавил к раскладке, судя по матрице.
///
/// Нужен ровно затем, чтобы маска и подсветка ехали за страницей, когда
/// замок отперт и матрицей распоряжается просмотрщик.
SheetTransform sheetTransformOf({
  required Matrix4 matrix,
  required SheetPlacement placement,
  required double documentLeft,
}) {
  final double zoom = matrix.storage[0];
  if (!placement.isVisible || !zoom.isFinite || zoom <= 0) {
    return SheetTransform.none;
  }
  final double scale = zoom / placement.scale;
  final double baseLeft = placement.left - documentLeft * placement.scale;
  return SheetTransform(
    scale: scale,
    dx: matrix.storage[12] - baseLeft * scale,
    dy: matrix.storage[13] - placement.top * scale,
  );
}

/// Переводит точку экрана в координаты документа просмотрщика.
///
/// Возвращает `null`, если переводить не во что: пустая раскладка или
/// вырожденный масштаб.
Offset? documentPoint({
  required Offset screen,
  required SheetPlacement placement,
  required double documentLeft,
  SheetTransform transform = SheetTransform.none,
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
