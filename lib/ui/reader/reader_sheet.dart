import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/progress_slot.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/sheet_placement.dart';
import 'reading_progress_book.dart';

/// Лист книги на экране: жёсткая раскладка без постоянного зума.
///
/// Читалка не наводит объектив на кусок страницы, а кладёт лист так, что
/// нужный прямоугольник занимает экран целиком. Масштаб определяется
/// только размерами листа и экрана — одинаковый на каждой странице.
///
/// Приблизить всё-таки можно: щипком, чтобы разглядеть схему или сноску.
/// Но это увеличение **временное** — палец отпущен, и лист возвращается
/// на место. Так разглядывание не превращается в потерянный масштаб,
/// который потом непонятно как вернуть. Тем, кому такое поведение мешает,
/// возврат отключается в настройках.
class ReaderSheet extends StatefulWidget {
  /// Создаёт лист.
  const ReaderSheet({
    required this.document,
    required this.pages,
    required this.fragment,
    required this.background,
    required this.page,
    required this.pageCount,
    required this.snapBack,
    super.key,
  });

  /// Наибольшее увеличение щипком.
  static const double maxZoom = 5;

  /// Открытый документ.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Какую часть листа показывать, в долях листа.
  final CropBox fragment;

  /// Фон вокруг страницы.
  final Color background;

  /// Текущая страница для указателя места.
  final int page;

  /// Всего страниц в книге.
  final int pageCount;

  /// Возвращать ли масштаб, когда читатель отпустил пальцы.
  final bool snapBack;

  @override
  State<ReaderSheet> createState() => _ReaderSheetState();
}

class _ReaderSheetState extends State<ReaderSheet>
    with SingleTickerProviderStateMixin {
  final TransformationController _zoom = TransformationController();
  late final AnimationController _release = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Animation<Matrix4>? _back;

  @override
  void initState() {
    super.initState();
    _release.addListener(() {
      final Animation<Matrix4>? back = _back;
      if (back != null) {
        _zoom.value = back.value;
      }
    });
  }

  @override
  void didUpdateWidget(ReaderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Сменилась страница или фрагмент — увеличение к ним не относится.
    if (oldWidget.page != widget.page ||
        oldWidget.fragment != widget.fragment) {
      _release.stop();
      _zoom.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _release.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    if (!widget.snapBack || _zoom.value == Matrix4.identity()) {
      return;
    }
    _back = Matrix4Tween(
      begin: _zoom.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _release, curve: Curves.easeOut));
    _release.forward(from: 0);
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
          );
          if (!placement.isVisible) {
            return const SizedBox.expand();
          }
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: ReaderSheet.maxZoom,
                  onInteractionEnd: _onInteractionEnd,
                  child: ClipRect(
                    child: Stack(
                      children: <Widget>[
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
                      ],
                    ),
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
