import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/reading.dart';
import '../../domain/reading/sheet_placement.dart';

/// Лист книги на экране: жёсткая раскладка без зума и панорамирования.
///
/// Читалка не наводит объектив на кусок страницы, а кладёт лист так, что
/// нужный прямоугольник занимает экран целиком. Масштаб определяется
/// только размерами листа и экрана — одинаковый на каждой странице, не
/// зависящий от того, куда читатель случайно потянул пальцем.
///
/// Лист — это одна страница или две страницы разворота рядом; страницы
/// разворота стоят вплотную, без полосы между ними.
class ReaderSheet extends StatelessWidget {
  /// Создаёт лист.
  const ReaderSheet({
    required this.document,
    required this.pages,
    required this.fragment,
    required this.background,
    super.key,
  });

  /// Открытый документ.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Какую часть листа показывать, в долях листа.
  final CropBox fragment;

  /// Фон вокруг страницы.
  final Color background;

  @override
  Widget build(BuildContext context) {
    final List<PdfPage> sheet = <PdfPage>[
      for (final int number in pages)
        if (number >= 1 && number <= document.pages.length)
          document.pages[number - 1],
    ];
    if (sheet.isEmpty) {
      return ColoredBox(color: background, child: const SizedBox.expand());
    }

    double sheetWidth = 0;
    double sheetHeight = 0;
    for (final PdfPage page in sheet) {
      sheetWidth += page.width;
      sheetHeight = sheetHeight < page.height ? page.height : sheetHeight;
    }

    return ColoredBox(
      color: background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints limits) {
          final SheetPlacement placement = placeFragment(
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            fragment: fragment,
            screenWidth: limits.maxWidth,
            screenHeight: limits.maxHeight,
          );
          if (!placement.isVisible) {
            return const SizedBox.expand();
          }
          return ClipRect(
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
                            document: document,
                            pageNumber: page.pageNumber,
                            decorationBuilder: _plainPage,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
