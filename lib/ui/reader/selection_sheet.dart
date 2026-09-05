import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/sheet_placement.dart';

/// Слой выделения поверх листа.
///
/// **Почему он вообще есть.** Постраничное чтение с S4.2 рисует страницы
/// собственным виджетом (`ReaderSheet` через `PdfPageView`), а вся работа
/// с выделением в pdfrx заперта внутри `PdfViewer`: ручки, лупа над
/// ручкой, выбор «тянуть пальцем или только за ручки» по типу указателя,
/// слово по нажатию, выделение через границу страниц. `PdfPageView` не
/// умеет из этого ничего.
///
/// Решение владельца от 06.09.2026: **чтение остаётся жёсткой раскладкой,
/// а `PdfViewer` поднимается над листом только на время выделения** — в
/// той же раскладке и в том же масштабе. Ради этого его матрица
/// приколочена (`normalizeMatrix` возвращает нашу, а не свою), панорама и
/// зум выключены, поля убраны, а страницы разложены нашей собственной
/// функцией. Читатель разницы не видит: под слоем остаётся тот же лист,
/// нарисованный тем же движком в том же месте.
///
/// **Первый жест не пропадает.** Виджет, поднятый по долгому нажатию, не
/// видел ни касания, ни его удержания — Flutter отдаёт события того
/// указателя тем, кто был на месте в момент нажатия. Поэтому намерение
/// читателя повторяется программно: [startAt] — точка, в которой он
/// держал палец, и по готовности просмотрщика в ней выделяется слово.
/// Дальше работают настоящие ручки, и они уже видят все жесты.
class SelectionSheet extends StatefulWidget {
  /// Создаёт слой выделения.
  const SelectionSheet({
    required this.document,
    required this.pages,
    required this.placement,
    required this.transform,
    required this.startAt,
    required this.onSelection,
    this.onReady,
    this.onDismiss,
    super.key,
  });

  /// Открытый документ — тот же, которым рисует лист.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Раскладка листа: масштаб и место на экране.
  final SheetPlacement placement;

  /// Преобразование, которое читатель добавил щипком. Единичное, когда
  /// замок заперт.
  final Matrix4 transform;

  /// Точка на экране, с которой началось выделение.
  final Offset startAt;

  /// Выделение изменилось. Пустой список означает, что выделения нет.
  final void Function(List<PdfPageTextRange> ranges) onSelection;

  /// Просмотрщик готов и нарисовал страницу.
  final VoidCallback? onReady;

  /// Читатель нажал мимо выделения.
  final VoidCallback? onDismiss;

  @override
  State<SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<SelectionSheet> {
  final PdfViewerController _viewer = PdfViewerController();
  bool _started = false;

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
        enableKeyboardNavigation: false,
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
                widget.onDismiss?.call();
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
    widget.onReady?.call();
    if (_started) {
      return;
    }
    _started = true;
    // Слово выделяется после того, как просмотрщик встал на место:
    // до этого у него нет ни раскладки, ни размера окна, и точка на
    // экране не во что переводить.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final Offset? point = documentPoint(
        screen: widget.startAt,
        placement: widget.placement,
        documentLeft: _documentLeft(),
        transform: widget.transform,
      );
      if (point == null) {
        return;
      }
      unawaited(controller.textSelectionDelegate.selectWord(point));
    });
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
