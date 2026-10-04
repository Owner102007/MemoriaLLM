import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/text_geometry.dart';

/// Прямоугольники выделения, которые посчитал сам просмотрщик, — в долях
/// страницы [page] (BUG-25).
///
/// Место выделения мы считаем по своему слою текста: по нему же идут
/// подсветка, контекст и цитаты. Но слой бывает непригоден — число знаков
/// не сошлось с числом прямоугольников, или выделенное в нашем тексте не
/// нашлось. Просмотрщик при этом выделение уже нарисовал, то есть знает,
/// где оно. Его прямоугольники — запасной путь: по ним встаёт панель
/// действий, когда своих нет.
///
/// Берутся куски только страницы [page]: выделение через границу страниц
/// привязывает панель к первой.
List<TextBox> viewerSelectionBoxes(
  List<PdfPageTextRange> ranges,
  PdfPage page,
) {
  final double width = page.width;
  final double height = page.height;
  if (width <= 0 || height <= 0) {
    return const <TextBox>[];
  }
  final List<TextBox> boxes = <TextBox>[];
  for (final PdfPageTextRange range in ranges) {
    if (range.pageNumber != page.pageNumber) {
      continue;
    }
    try {
      for (final PdfTextFragmentBoundingRect part
          in range.enumerateFragmentBoundingRects()) {
        final PdfRect bounds = part.bounds;
        if (bounds.isEmpty) {
          continue;
        }
        // Координаты лежат в неповёрнутом пространстве страницы и снизу
        // вверх; `toRect` разворачивает их в то, что видит читатель.
        final Rect display = bounds.toRect(page: page);
        final TextBox box = TextBox(
          left: (display.left / width).clamp(0.0, 1.0),
          top: (display.top / height).clamp(0.0, 1.0),
          right: (display.right / width).clamp(0.0, 1.0),
          bottom: (display.bottom / height).clamp(0.0, 1.0),
        );
        if (box.isValid) {
          boxes.add(box);
        }
      }
    } on Object {
      // Места выделения разошлись с разбором страницы: берём то, что
      // успели собрать, — пустой ответ здесь честнее падения.
    }
  }
  return boxes;
}
