/// Как листы книги лежат в документе просмотрщика и что от соседних
/// листов видно на экране — чистая математика.
///
/// Страницу рисует один просмотрщик, и раскладку всех страниц книги ему
/// задаём мы. Пока лист показывался целиком, страницы лежали **в ряд**:
/// сосед читаемого листа — слева и справа. С нахлёстом (F-READ-12) этого
/// мало: под последней полосой страницы читатель обязан видеть верх
/// следующей страницы, а в ряду её там нет. Поэтому в режимах с полосами
/// листы встают **в столбик**: следующий лист физически лежит под
/// текущим, и подглядывание в него получается само — тем же
/// просмотрщиком, без второго слоя.
///
/// Здесь же — какие куски соседних листов остаются видны (F-READ-13):
/// маска закрывает фоном всё, кроме самого листа и этих кусков.
library;

import 'dart:ui' show Offset, Rect, Size;

import 'fragments.dart';
import 'reading.dart';

/// Как листы лежат в документе просмотрщика.
enum SheetArrangement {
  /// В один ряд, слева направо: лист показывается целиком, соседние
  /// листы — по бокам.
  row,

  /// В столбик, сверху вниз: лист читается полосами, соседние листы —
  /// над ним и под ним.
  column,
}

/// Какая раскладка листов нужна режиму.
///
/// Полосы идут сверху вниз, и продолжение последней полосы — верх
/// следующего листа: в режимах с полосами листы лежат в столбик.
SheetArrangement arrangementFor(PageDisplayMode mode) {
  return fragmentCountFor(mode: mode) > 1
      ? SheetArrangement.column
      : SheetArrangement.row;
}

/// Последняя страница листа, который начинается со страницы [first].
///
/// В развороте первая страница стоит одна, дальше идут пары (2, 3),
/// (4, 5) — тот же счёт, что у `spreadPages`, но без списка на каждый
/// лист: раскладка считается на каждое построение просмотрщика, и на
/// книге в тысячу страниц списки стоили бы заметно.
int sheetLastPage({
  required int first,
  required int pageCount,
  required bool spread,
}) {
  if (!spread || first <= 1 || first.isOdd) {
    return first;
  }
  return first + 1 > pageCount ? first : first + 1;
}

/// Где в документе просмотрщика лежит каждая страница книги.
///
/// Страницы стоят вплотную и без полей. В ряду — все подряд, слева
/// направо. В столбике — листами сверху вниз; лист разворота при этом
/// остаётся двумя страницами рядом.
///
/// [widthOf] и [heightOf] отвечают по номеру страницы, начиная с
/// единицы.
List<Rect> arrangePages({
  required int pageCount,
  required double Function(int page) widthOf,
  required double Function(int page) heightOf,
  required SheetArrangement arrangement,
  required bool spread,
}) {
  final List<Rect> rects = <Rect>[];
  if (arrangement == SheetArrangement.row) {
    double x = 0;
    for (int page = 1; page <= pageCount; page++) {
      final double width = widthOf(page);
      rects.add(Rect.fromLTWH(x, 0, width, heightOf(page)));
      x += width;
    }
    return rects;
  }
  double y = 0;
  int first = 1;
  while (first <= pageCount) {
    final int last = sheetLastPage(
      first: first,
      pageCount: pageCount,
      spread: spread,
    );
    double x = 0;
    double height = 0;
    for (int page = first; page <= last; page++) {
      final double width = widthOf(page);
      final double pageHeight = heightOf(page);
      rects.add(Rect.fromLTWH(x, y, width, pageHeight));
      x += width;
      if (pageHeight > height) {
        height = pageHeight;
      }
    }
    y += height;
    first = last + 1;
  }
  return rects;
}

/// Размер документа просмотрщика по разложенным страницам.
///
/// Пустому документу отдаётся точка: нулевой размер просмотрщик делит.
Size arrangedSize(List<Rect> pages) {
  double width = 0;
  double height = 0;
  for (final Rect page in pages) {
    if (page.right > width) {
      width = page.right;
    }
    if (page.bottom > height) {
      height = page.bottom;
    }
  }
  return Size(width <= 0 ? 1 : width, height <= 0 ? 1 : height);
}

/// Где в документе просмотрщика лежит лист, начинающийся со страницы
/// [firstPage].
///
/// Считается так же, как [arrangePages], но только до нужного листа: это
/// спрашивают на каждое движение матрицы.
Offset sheetOrigin({
  required int firstPage,
  required int pageCount,
  required double Function(int page) widthOf,
  required double Function(int page) heightOf,
  required SheetArrangement arrangement,
  required bool spread,
}) {
  if (arrangement == SheetArrangement.row) {
    double left = 0;
    for (int page = 1; page < firstPage && page <= pageCount; page++) {
      left += widthOf(page);
    }
    return Offset(left, 0);
  }
  double top = 0;
  int first = 1;
  while (first < firstPage && first <= pageCount) {
    final int last = sheetLastPage(
      first: first,
      pageCount: pageCount,
      spread: spread,
    );
    double height = 0;
    for (int page = first; page <= last; page++) {
      final double pageHeight = heightOf(page);
      if (pageHeight > height) {
        height = pageHeight;
      }
    }
    top += height;
    first = last + 1;
  }
  return Offset(0, top);
}

/// Кусок соседнего листа, который остаётся виден на экране.
class NeighbourZone {
  /// Создаёт кусок.
  const NeighbourZone({
    required this.rect,
    required this.seamFrom,
    required this.seamTo,
  });

  /// Где кусок лежит на экране.
  final Rect rect;

  /// Начало стыка с читаемым листом.
  final Offset seamFrom;

  /// Конец стыка с читаемым листом.
  final Offset seamTo;

  @override
  bool operator ==(Object other) {
    return other is NeighbourZone &&
        other.rect == rect &&
        other.seamFrom == seamFrom &&
        other.seamTo == seamTo;
  }

  @override
  int get hashCode => Object.hash(rect, seamFrom, seamTo);

  @override
  String toString() => 'NeighbourZone($rect)';
}

/// Какие куски соседних листов видны рядом с читаемым листом.
///
/// F-READ-13, ALG-UI-16. В S6.1 сквозь полупрозрачную тень просачивалось
/// то, что случайно поместилось в окно: на широком окне ПК из-под тени
/// торчал кусок чужой страницы, и ширина его зависела от размера окна.
/// Здесь ширину **назначаем мы**: за её пределами маска закрывает всё
/// фоном, как и раньше.
///
/// В ряду соседи стоят по бокам листа, и от каждого видна полоска шириной
/// [width]. В столбике соседи — над листом и под ним, и видно их ровно в
/// пределах нахлёста [band] вокруг читаемой полосы [strip]: на последней
/// полосе страницы это верх следующей страницы, на первой — низ
/// предыдущей (F-READ-12).
///
/// [sheet], [strip], [band] и [width] — в точках экрана. Соседа, которого
/// нет ([hasBefore], [hasAfter] — начало и конец книги), нет и на экране.
List<NeighbourZone> neighbourZones({
  required SheetArrangement arrangement,
  required Rect sheet,
  required Rect strip,
  required double band,
  required double width,
  required bool hasBefore,
  required bool hasAfter,
}) {
  final List<NeighbourZone> zones = <NeighbourZone>[];
  if (sheet.isEmpty) {
    return zones;
  }
  if (arrangement == SheetArrangement.row) {
    if (!width.isFinite || width <= 0) {
      return zones;
    }
    if (hasBefore) {
      zones.add(
        NeighbourZone(
          rect: Rect.fromLTRB(
            sheet.left - width,
            sheet.top,
            sheet.left,
            sheet.bottom,
          ),
          seamFrom: sheet.topLeft,
          seamTo: sheet.bottomLeft,
        ),
      );
    }
    if (hasAfter) {
      zones.add(
        NeighbourZone(
          rect: Rect.fromLTRB(
            sheet.right,
            sheet.top,
            sheet.right + width,
            sheet.bottom,
          ),
          seamFrom: sheet.topRight,
          seamTo: sheet.bottomRight,
        ),
      );
    }
    return zones;
  }
  if (strip.isEmpty || !band.isFinite || band <= 0) {
    return zones;
  }
  final double windowTop = strip.top - band;
  if (hasBefore && windowTop < sheet.top) {
    zones.add(
      NeighbourZone(
        rect: Rect.fromLTRB(sheet.left, windowTop, sheet.right, sheet.top),
        seamFrom: sheet.topLeft,
        seamTo: sheet.topRight,
      ),
    );
  }
  final double windowBottom = strip.bottom + band;
  if (hasAfter && windowBottom > sheet.bottom) {
    zones.add(
      NeighbourZone(
        rect: Rect.fromLTRB(
          sheet.left,
          sheet.bottom,
          sheet.right,
          windowBottom,
        ),
        seamFrom: sheet.bottomLeft,
        seamTo: sheet.bottomRight,
      ),
    );
  }
  return zones;
}

/// Какая доля разницы между затемнением своей страницы и чернотой
/// добавляется соседней.
const double kNeighbourExtraDim = 0.5;

/// Насколько гаснет соседняя страница.
///
/// Всегда сильнее своей (F-READ-13): своя страница вне полосы гаснет по
/// настройке [dim], соседняя — на полпути от неё к черноте. Даже при
/// нулевом затемнении сосед остаётся притушенным: иначе на широком окне
/// он читался бы как вторая страница разворота.
double neighbourDimFor(double dim) {
  final double own = clampDimOutside(dim);
  return own + (1 - own) * kNeighbourExtraDim;
}
