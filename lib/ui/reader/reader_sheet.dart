import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/progress_slot.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/sheet_placement.dart';
import 'dim_outside.dart';
import 'reading_progress_book.dart';

/// Лист книги на экране: жёсткая раскладка, страница целиком.
///
/// Читалка не наводит объектив на кусок страницы, а кладёт лист так, что
/// читаемая часть занимает экран целиком. Масштаб определяется размерами
/// листа и экрана — одинаковый на каждой странице книги.
///
/// **Страница при этом не обрезается.** В режимах половины и трети лист
/// рисуется целиком, а всё за пределами читаемой полосы гаснет. Крупная
/// полоса занимает весь экран, и затемнённая часть страницы обычно лежит
/// за его краем — но она есть: отперев замок и уменьшив страницу щипком,
/// читатель видит её целиком, тёмной вокруг светлой полосы. Прежде на
/// её месте не было ничего, и страница ощущалась обрезанной.
///
/// **Замок решает, можно ли трогать страницу пальцами.** Заперт — щипок
/// и перетаскивание выключены совсем, страница стоит там, где её
/// положили, и случайное движение руки не собьёт масштаб. Отперт —
/// страница ведёт себя как в обычном просмотрщике: её можно двигать и
/// масштабировать, и она **остаётся** в этом состоянии, а не отпружинивает
/// назад. Прежний возврат масштаба и был главной жалобой: разглядеть
/// схему получалось только удерживая пальцы на экране.
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
    super.key,
  });

  /// Наибольшее увеличение щипком.
  static const double maxZoom = 5;

  /// Наименьшее уменьшение щипком.
  ///
  /// Полоса вписана в экран, поэтому лист в режиме трети втрое выше
  /// экрана: чтобы увидеть страницу целиком, уменьшать надо не меньше чем
  /// втрое. Предел взят с запасом — иначе страница упиралась бы в него
  /// ровно в тот момент, когда читатель хочет оглядеть её всю.
  static const double minZoom = 0.2;

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

  @override
  State<ReaderSheet> createState() => _ReaderSheetState();
}

class _ReaderSheetState extends State<ReaderSheet> {
  final TransformationController _zoom = TransformationController();

  @override
  void didUpdateWidget(ReaderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Замок захлопнулся — страница замирает как есть. Но если её только
    // сдвинули, не меняя масштаба, сдвиг снимается: смещённая на палец
    // страница выглядит не выбором читателя, а поломкой, и вернуть её
    // при запертом замке было бы нечем.
    if (widget.locked &&
        !oldWidget.locked &&
        isSheetZoomNeutral(_zoom.value.getMaxScaleOnAxis())) {
      _zoom.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
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
          if (!placement.isVisible) {
            return const SizedBox.expand();
          }
          final SheetViewport window = fragmentBounds(
            placement: placement,
            fragment: widget.fragment,
          );
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _zoom,
                  panEnabled: !widget.locked,
                  scaleEnabled: !widget.locked,
                  minScale: ReaderSheet.minZoom,
                  maxScale: ReaderSheet.maxZoom,
                  // Без запаса границ `InteractiveViewer` **не даёт**
                  // уменьшить масштаб: он не разрешает отвести края листа
                  // внутрь окна и молча съедает жест. Запас должен быть
                  // тем больше, чем сильнее разрешено уменьшать: окно
                  // обязано умещаться в границы и после сжатия. Две
                  // тысячи точек дают предел около 0.17 — с запасом ниже
                  // [ReaderSheet.minZoom], но не настолько, чтобы
                  // страницу можно было увести в другую галактику.
                  boundaryMargin: const EdgeInsets.all(2000),
                  child: Stack(
                    // Клипа нет намеренно: лист рисуется целиком, даже
                    // та его часть, что сейчас за краем экрана. Обрезать
                    // её здесь значило бы обрезать её и после щипка —
                    // читатель уменьшил бы страницу и увидел ту же
                    // полосу, только мельче. Край экрана обрезает сам
                    // просмотрщик, уже после преобразования.
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Лист кладётся целиком: страница в режимах
                      // половины и трети рисуется вся, лишнее не
                      // вырезается, а гаснет.
                      Positioned(
                        left: placement.left,
                        top: placement.top,
                        width: placement.sheetWidth,
                        height: placement.sheetHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (final PdfPage page in sheet)
                              SizedBox(
                                width: page.width * placement.scale,
                                height: page.height * placement.scale,
                                child: PdfPageView(
                                  document: widget.document,
                                  pageNumber: page.pageNumber,
                                  decorationBuilder: _plainPage,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: DimOutside(
                          key: const Key('reader-dim-outside'),
                          sheet: Rect.fromLTWH(
                            placement.left,
                            placement.top,
                            placement.sheetWidth,
                            placement.sheetHeight,
                          ),
                          fragment: Rect.fromLTWH(
                            window.left,
                            window.top,
                            window.width,
                            window.height,
                          ),
                          dim: widget.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Указатель места живёт поверх зума: увеличивать его вместе
              // со страницей незачем, а терять при листании — тем более.
              ReadingProgressBook(
                slot: progressSlotFor(
                  placement: placement,
                  screenWidth: limits.maxWidth,
                  screenHeight: limits.maxHeight,
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
}

/// Страница без тени и рамки.
///
/// Тень уместна на полке, а не в чтении: страница здесь и есть экран, и
/// любая её обводка превращается в лишнюю линию перед глазами.
Widget _plainPage(
  BuildContext context,
  Size pageSize,
  PdfPage page,
  RawImage? pageImage,
) {
  // Размеры у `pageImage` уже посчитаны по нашему же SizedBox, поэтому
  // картинка ложится точно, без подгонки.
  return pageImage ?? const ColoredBox(color: Color(0xFFFFFFFF));
}
