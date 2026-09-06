import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';
import 'package:memoria/domain/reading/sheet_transform.dart';
import 'package:memoria/ui/reader/reader_sheet.dart';
import 'package:memoria/ui/reader/selection_panel.dart';

/// Геометрия листа: просмотрщик обязан встать ровно туда, где по нашей
/// раскладке лежит страница.
///
/// Вся сегодняшняя правка держится на одном: матрица просмотрщика — это
/// наша раскладка, а не его собственная. Разъедься они на пиксель — и
/// страница сядет по-разному на соседних страницах книги, ровно то, от
/// чего уходили в S4.2. Поэтому это проверяется числами, а не глазами.
void main() {
  const SheetPlacement placement = SheetPlacement(
    scale: 2,
    left: -100,
    top: -50,
    sheetWidth: 1190,
    sheetHeight: 1684,
  );

  group('матрица просмотрщика', () {
    test('масштаб берётся из раскладки листа', () {
      final Matrix4 matrix = sheetMatrix(placement: placement, documentLeft: 0);
      expect(matrix.storage[0], 2);
      expect(matrix.storage[12], -100);
      expect(matrix.storage[13], -50);
    });

    test('вторая страница разворота сдвигает начало документа', () {
      // Страницы в документе просмотрщика лежат в один ряд, поэтому лист,
      // начинающийся со сто первой страницы, стоит не в нуле.
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 595,
      );
      expect(matrix.storage[12], -100 - 595 * 2);
    });

    test('щипок читателя накладывается сверху', () {
      const SheetTransform pinch = SheetTransform(scale: 1.5, dx: 30, dy: 40);
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 0,
        transform: pinch,
      );
      // Сдвиг поверх масштаба снова даёт сдвиг и масштаб — большего
      // просмотрщик и не ждёт.
      expect(matrix.storage[0], closeTo(3, 1e-9));
      expect(matrix.storage[12], closeTo(-100 * 1.5 + 30, 1e-9));
      expect(matrix.storage[13], closeTo(-50 * 1.5 + 40, 1e-9));
    });
  });

  group('обратный ход: что читатель добавил сам', () {
    test('нетронутая страница даёт единичное преобразование', () {
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 595,
      );
      final SheetTransform back = sheetTransformOf(
        matrix: matrix,
        placement: placement,
        documentLeft: 595,
      );
      expect(back.scale, closeTo(1, 1e-9));
      expect(back.dx, closeTo(0, 1e-9));
      expect(back.dy, closeTo(0, 1e-9));
      expect(back.isNeutral, isTrue);
    });

    test('щипок возвращается тем же, каким его положили', () {
      const SheetTransform pinch = SheetTransform(scale: 1.5, dx: 30, dy: -40);
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 595,
        transform: pinch,
      );
      final SheetTransform back = sheetTransformOf(
        matrix: matrix,
        placement: placement,
        documentLeft: 595,
      );
      expect(back.scale, closeTo(pinch.scale, 1e-9));
      expect(back.dx, closeTo(pinch.dx, 1e-9));
      expect(back.dy, closeTo(pinch.dy, 1e-9));
      expect(back.isNeutral, isFalse);
    });

    test('вырожденная матрица преобразования не даёт', () {
      expect(
        sheetTransformOf(
          matrix: Matrix4.zero(),
          placement: placement,
          documentLeft: 0,
        ),
        SheetTransform.none,
      );
    });
  });

  group('точка экрана в координатах документа', () {
    test('перевод обратим', () {
      const Offset screen = Offset(320, 480);
      final Offset point = documentPoint(
        screen: screen,
        placement: placement,
        documentLeft: 0,
      )!;
      final Matrix4 matrix = sheetMatrix(placement: placement, documentLeft: 0);
      final Offset back = Offset(
        point.dx * matrix.storage[0] + matrix.storage[12],
        point.dy * matrix.storage[0] + matrix.storage[13],
      );
      expect(back.dx, closeTo(screen.dx, 1e-9));
      expect(back.dy, closeTo(screen.dy, 1e-9));
    });

    test('перевод обратим и после щипка', () {
      const SheetTransform pinch = SheetTransform(scale: 1.5, dx: 30, dy: -40);
      const Offset screen = Offset(320, 480);
      final Offset point = documentPoint(
        screen: screen,
        placement: placement,
        documentLeft: 595,
        transform: pinch,
      )!;
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 595,
        transform: pinch,
      );
      expect(
        point.dx * matrix.storage[0] + matrix.storage[12],
        closeTo(screen.dx, 1e-9),
      );
      expect(
        point.dy * matrix.storage[0] + matrix.storage[13],
        closeTo(screen.dy, 1e-9),
      );
    });

    test('вырожденная раскладка точки не даёт', () {
      expect(
        documentPoint(
          screen: Offset.zero,
          placement: SheetPlacement.none,
          documentLeft: 0,
        ),
        isNull,
      );
    });
  });

  group('место панели действий', () {
    const Size area = Size(400, 800);

    test('над выделением, если сверху есть место', () {
      final Offset at = panelOffset(
        anchor: const Rect.fromLTWH(100, 400, 150, 20),
        area: area,
      );
      expect(at.dy, 400 - SelectionPanel.gap - SelectionPanel.height);
    });

    test('под выделением, если сверху места нет', () {
      final Offset at = panelOffset(
        anchor: const Rect.fromLTWH(100, 10, 150, 20),
        area: area,
      );
      expect(at.dy, 30 + SelectionPanel.gap);
    });

    test('панель не вылезает за края экрана', () {
      // Выделение в самом углу страницы: середина у него у самого края,
      // и панель, поставленная по ней, уехала бы за экран.
      const List<Rect> corners = <Rect>[
        Rect.fromLTWH(0, 400, 20, 20),
        Rect.fromLTWH(380, 400, 20, 20),
      ];
      for (final Rect anchor in corners) {
        final Offset at = panelOffset(anchor: anchor, area: area);
        expect(at.dx, greaterThanOrEqualTo(0));
        expect(at.dx, lessThanOrEqualTo(area.width));
      }
    });

    test('выделение во весь экран не выталкивает панель наружу', () {
      final Offset at = panelOffset(
        anchor: const Rect.fromLTWH(0, 0, 400, 800),
        area: area,
      );
      expect(at.dy, area.height - SelectionPanel.height);
      expect(at.dy, greaterThanOrEqualTo(0));
    });
  });

  group('вид листа переводит страницу в экран', () {
    test('нетронутая страница ложится ровно по раскладке', () {
      const SheetView view = SheetView(
        placement: placement,
        transform: SheetTransform.none,
      );
      expect(view.toScreen(0, 0), const Offset(-100, -50));
      expect(view.toScreen(100, 50), const Offset(100, 50));
    });

    test('после щипка едет вместе со страницей', () {
      const SheetView view = SheetView(
        placement: placement,
        transform: SheetTransform(scale: 2, dx: 10, dy: 20),
      );
      expect(view.toScreen(0, 0), const Offset(-190, -80));
    });
  });

  group('маска ложится туда же, где лист', () {
    const CropBox strip = CropBox(left: 0, top: 0, right: 1, bottom: 0.5);

    test('без щипка лист и полоса совпадают с раскладкой', () {
      // Тот самый обратный пересчёт, которым доказывается, что рамка не
      // поехала: маска считается по тем же числам, что и посадка листа.
      final Rect sheet = sheetRectOnScreen(placement: placement);
      expect(sheet.left, placement.left);
      expect(sheet.top, placement.top);
      expect(sheet.width, placement.sheetWidth);
      expect(sheet.height, placement.sheetHeight);

      final SheetViewport window = fragmentBounds(
        placement: placement,
        fragment: strip,
      );
      final Rect band = stripRectOnScreen(
        placement: placement,
        fragment: strip,
      );
      expect(band.left, window.left);
      expect(band.top, window.top);
      expect(band.width, window.width);
      expect(band.height, window.height);
    });

    test('щипок двигает и лист, и полосу одинаково', () {
      const SheetTransform pinch = SheetTransform(scale: 1.5, dx: 30, dy: -40);
      final Rect sheet = sheetRectOnScreen(
        placement: placement,
        transform: pinch,
      );
      final Rect band = stripRectOnScreen(
        placement: placement,
        fragment: strip,
        transform: pinch,
      );
      expect(sheet.left, closeTo(placement.left * 1.5 + 30, 1e-9));
      expect(band.left, closeTo(sheet.left, 1e-9));
      expect(band.width, closeTo(sheet.width, 1e-9));
      expect(band.height, closeTo(sheet.height / 2, 1e-9));
    });

    test('пустая раскладка даёт пустые прямоугольники', () {
      expect(sheetRectOnScreen(placement: SheetPlacement.none), Rect.zero);
      expect(
        stripRectOnScreen(placement: SheetPlacement.none, fragment: strip),
        Rect.zero,
      );
    });
  });

  group('предел свободы при отпертом замке', () {
    const Size screen = Size(400, 800);
    const SheetPlacement page = SheetPlacement(
      scale: 1,
      left: 0,
      top: 0,
      sheetWidth: 400,
      sheetHeight: 800,
    );

    test('нетронутое преобразование не трогается', () {
      final SheetTransform kept = clampSheetTransform(
        transform: const SheetTransform(scale: 1.4, dx: -20, dy: -30),
        placement: page,
        screen: screen,
      );
      expect(kept.scale, 1.4);
      expect(kept.dx, -20);
      expect(kept.dy, -30);
    });

    test('масштаб держится в границах', () {
      expect(
        clampSheetTransform(
          transform: const SheetTransform(scale: 40),
          placement: page,
          screen: screen,
        ).scale,
        kSheetMaxZoom,
      );
      expect(
        clampSheetTransform(
          transform: const SheetTransform(scale: 0.01),
          placement: page,
          screen: screen,
        ).scale,
        kSheetMinZoom,
      );
    });

    test('страницу нельзя увести с экрана', () {
      // Пан у просмотрщика без границ: он увезёт лист куда угодно, а
      // вернуть его читателю нечем — кнопки «на место» у нас нет.
      final SheetTransform far = clampSheetTransform(
        transform: const SheetTransform(dx: 5000, dy: -9000),
        placement: page,
        screen: screen,
      );
      final Rect sheet = sheetRectOnScreen(placement: page, transform: far);
      expect(sheet.right, greaterThanOrEqualTo(kSheetKeepOnScreen - 1e-6));
      expect(
        sheet.left,
        lessThanOrEqualTo(screen.width - kSheetKeepOnScreen + 1e-6),
      );
      expect(sheet.bottom, greaterThanOrEqualTo(kSheetKeepOnScreen - 1e-6));
      expect(
        sheet.top,
        lessThanOrEqualTo(screen.height - kSheetKeepOnScreen + 1e-6),
      );
    });

    test('упёршись в предел масштаба, страница не прыгает вбок', () {
      final SheetTransform capped = clampSheetTransform(
        transform: const SheetTransform(scale: 10, dx: -1800, dy: -3600),
        placement: page,
        screen: screen,
      );
      // Точка под серединой экрана остаётся под ней же.
      const Offset middle = Offset(200, 400);
      final double before =
          (middle.dx - (-1800.0)) / 10; // точка листа под серединой
      final double after = (middle.dx - capped.dx) / capped.scale;
      expect(after, closeTo(before, 1e-6));
    });

    test('мусор на входе даёт нетронутый лист', () {
      expect(
        clampSheetTransform(
          transform: const SheetTransform(scale: double.nan),
          placement: page,
          screen: screen,
        ),
        SheetTransform.none,
      );
      expect(
        clampSheetTransform(
          transform: const SheetTransform(),
          placement: SheetPlacement.none,
          screen: screen,
        ),
        SheetTransform.none,
      );
    });
  });
}
