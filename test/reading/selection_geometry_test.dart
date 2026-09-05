import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/sheet_placement.dart';
import 'package:memoria/ui/reader/selection_panel.dart';
import 'package:memoria/ui/reader/selection_sheet.dart';

/// Геометрия слоя выделения: он обязан встать ровно туда, где лежит лист.
///
/// Вся подмена держится на одном: просмотрщик, поднятый над листом,
/// показывает страницу в том же масштабе и в том же месте. Разъедься они
/// на пиксель — читатель увидит рывок ровно в тот момент, когда начал
/// выделять. Поэтому это проверяется числами, а не глазами.
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
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 0,
      );
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

    test('щипок читателя умножается сверху', () {
      final Matrix4 pinch = Matrix4.identity()
        ..setEntry(0, 0, 1.5)
        ..setEntry(1, 1, 1.5)
        ..setEntry(2, 2, 1.5)
        ..setEntry(0, 3, 30)
        ..setEntry(1, 3, 40);
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 0,
        transform: pinch,
      );
      // Произведение сдвига и масштаба снова сдвиг и масштаб — большего
      // просмотрщик и не ждёт.
      expect(matrix.storage[0], closeTo(3, 1e-9));
      expect(matrix.storage[12], closeTo(-100 * 1.5 + 30, 1e-9));
      expect(matrix.storage[13], closeTo(-50 * 1.5 + 40, 1e-9));
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
      final Matrix4 matrix = sheetMatrix(
        placement: placement,
        documentLeft: 0,
      );
      final Offset back = Offset(
        point.dx * matrix.storage[0] + matrix.storage[12],
        point.dy * matrix.storage[0] + matrix.storage[13],
      );
      expect(back.dx, closeTo(screen.dx, 1e-9));
      expect(back.dy, closeTo(screen.dy, 1e-9));
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
}
