import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/page_turning.dart';
import 'package:memoria/domain/reading/reading.dart';

/// Рамка с заданными полями слева и справа; сверху и снизу — по десятой.
CropBox _box(double left, double right) =>
    CropBox(left: left, top: 0.1, right: right, bottom: 0.9);

void main() {
  group('F-READ-02: какие рамки считать заранее', () {
    test('вперёд по ходу чтения — два листа, назад — один', () {
      expect(
        framesAhead(page: 10, pageCount: 100, spread: false, forward: true),
        <int>[11, 12, 9],
      );
    });

    test('читатель листает назад — готовится то, что позади', () {
      expect(
        framesAhead(page: 10, pageCount: 100, spread: false, forward: false),
        <int>[9, 8, 11],
      );
    });

    test('у края книги готовить за краем нечего', () {
      expect(
        framesAhead(page: 1, pageCount: 100, spread: false, forward: true),
        <int>[2, 3],
      );
      expect(
        framesAhead(page: 100, pageCount: 100, spread: false, forward: true),
        <int>[99],
      );
      expect(
        framesAhead(page: 1, pageCount: 1, spread: false, forward: true),
        isEmpty,
      );
    });

    test('в развороте лист — две страницы, и готовятся обе', () {
      expect(
        framesAhead(page: 4, pageCount: 100, spread: true, forward: true),
        <int>[6, 7, 8, 9, 2, 3],
      );
      // Обложка стоит одна, последняя страница чётной книги — тоже.
      expect(
        framesAhead(page: 2, pageCount: 6, spread: true, forward: true),
        <int>[4, 5, 6, 1],
      );
    });
  });

  group('BUG-23: рамка взаймы', () {
    CropBox? Function(int) from(Map<int, CropBox> known) =>
        (int page) => known[page];

    test('берётся страница той же чётности, а не соседняя', () {
      // Поля в книге из переплёта зеркальны: нечётной странице подходит
      // рамка нечётной, хотя чётная ближе.
      final CropBox odd = _box(0.15, 0.92);
      final CropBox even = _box(0.08, 0.85);
      expect(
        borrowedContent(
          page: 9,
          pageCount: 100,
          known: from(<int, CropBox>{7: odd, 8: even}),
        ),
        odd,
      );
    });

    test('нет той же чётности — годится ближайшая любая', () {
      final CropBox even = _box(0.08, 0.85);
      expect(
        borrowedContent(
          page: 9,
          pageCount: 100,
          known: from(<int, CropBox>{8: even}),
        ),
        even,
      );
    });

    test('рамка издалека не берётся: лучше страница целиком', () {
      expect(
        borrowedContent(
          page: 50,
          pageCount: 100,
          known: from(<int, CropBox>{10: _box(0.1, 0.9)}),
        ),
        isNull,
      );
    });

    test('вывернутая рамка взаймы не идёт', () {
      const CropBox broken = CropBox(left: 0.8, top: 0, right: 0.2, bottom: 1);
      expect(
        borrowedContent(
          page: 5,
          pageCount: 10,
          known: from(<int, CropBox>{3: broken}),
        ),
        isNull,
      );
    });

    test('за край книги поиск не выходит', () {
      final List<int> asked = <int>[];
      borrowedContent(
        page: 1,
        pageCount: 3,
        known: (int page) {
          asked.add(page);
          return null;
        },
      );
      expect(asked, <int>[2, 3]);
    });
  });

  group('F-READ-02: запас кэша просмотрщика', () {
    /// Какие листы попадают в видимую область, расширенную на запас.
    ///
    /// Листы одинаковой ширины лежат в ряд, видимая область стоит по
    /// центру нулевого листа со сдвигом [shift] — поля книги
    /// несимметричны. Возвращает номера листов: 0 — свой, ±1 — соседние.
    List<int> covered({
      required double sheet,
      required double visible,
      required int sheets,
      double shift = 0,
    }) {
      final double extent = neighbourCacheExtent(
        sheetWidth: sheet,
        visibleWidth: visible,
        sheets: sheets,
      );
      final double left = shift - visible / 2 - visible * extent;
      final double right = shift + visible / 2 + visible * extent;
      return <int>[
        for (int n = -4; n <= 4; n++)
          if (sheet * (n - 0.5) < right && sheet * (n + 0.5) > left) n,
      ];
    }

    test('запас 1 — ровно по листу с каждой стороны', () {
      expect(covered(sheet: 595, visible: 476, sheets: 1), <int>[-1, 0, 1]);
    });

    test('запас 2 — по два листа, третий не захвачен', () {
      expect(covered(sheet: 595, visible: 476, sheets: 2), <int>[
        -2,
        -1,
        0,
        1,
        2,
      ]);
    });

    test('перекос полей не теряет соседа и не цепляет лишнего', () {
      for (final double shift in <double>[-60, 60]) {
        expect(
          covered(sheet: 595, visible: 476, sheets: 1, shift: shift),
          <int>[-1, 0, 1],
          reason: 'сдвиг $shift',
        );
      }
    });

    test('в развороте запас достаёт до дальней страницы соседа', () {
      // Лист — две страницы по 595. Дальняя страница соседнего листа
      // начинается в целой ширине листа от центра своего.
      final double extent = neighbourCacheExtent(
        sheetWidth: 1190,
        visibleWidth: 1100,
        sheets: 1,
      );
      expect(1100 / 2 + 1100 * extent, greaterThan(1190));
      expect(1100 / 2 + 1100 * extent, lessThan(1190 * 1.5));
    });

    test('запас 0 и широкое окно запаса не просят', () {
      expect(
        neighbourCacheExtent(sheetWidth: 595, visibleWidth: 476, sheets: 0),
        0,
      );
      // Окно ПК в два с половиной листа: соседи и так видны.
      expect(
        neighbourCacheExtent(sheetWidth: 595, visibleWidth: 1500, sheets: 1),
        0,
      );
    });

    test('вырожденные размеры — ноль, а не бесконечность', () {
      expect(
        neighbourCacheExtent(sheetWidth: 595, visibleWidth: 0, sheets: 1),
        0,
      );
      expect(
        neighbourCacheExtent(sheetWidth: 0, visibleWidth: 476, sheets: 1),
        0,
      );
    });
  });

  group('F-READ-12: запас соседних листов в столбике', () {
    /// Какие листы попадают в запас: ноль — читаемый, отрицательные —
    /// над ним, положительные — под ним. Листы одной высоты.
    List<int> covered({
      required double sheet,
      required double top,
      required double visible,
      required int sheets,
    }) {
      final double extent = columnCacheExtent(
        sheetHeight: sheet,
        visibleTop: top,
        visibleHeight: visible,
        sheets: sheets,
      );
      final double from = top - visible * extent;
      final double to = top + visible + visible * extent;
      return <int>[
        for (int n = -4; n <= 4; n++)
          if (sheet * n < to && sheet * (n + 1) > from) n,
      ];
    }

    test('F-READ-12: с любой полосы запас 1 — по листу сверху и снизу', () {
      // Полоса стоит не посередине листа: первая у его верха, последняя
      // у низа. Сосед обязан быть наготове с обеих сторон — а лист за
      // ним в запас попадать не должен.
      const double sheet = 842;
      for (final int count in <int>[2, 3]) {
        final double strip = sheet / count;
        // Видимая область чуть выше полосы: над ней и под ней нахлёст.
        final double visible = strip * 1.16;
        for (int i = 0; i < count; i++) {
          expect(
            covered(
              sheet: sheet,
              top: strip * i - strip * 0.08,
              visible: visible,
              sheets: 1,
            ),
            <int>[-1, 0, 1],
            reason: 'полос $count, полоса $i',
          );
        }
      }
    });

    test('F-READ-12: запас 2 — по два листа, третий не захвачен', () {
      const double sheet = 842;
      for (final double top in <double>[-30, 250, 530]) {
        expect(
          covered(sheet: sheet, top: top, visible: 320, sheets: 2),
          <int>[-2, -1, 0, 1, 2],
          reason: 'верх видимой области $top',
        );
      }
    });

    test('F-READ-12: запас 0 запаса не просит', () {
      expect(
        columnCacheExtent(
          sheetHeight: 842,
          visibleTop: 0,
          visibleHeight: 421,
          sheets: 0,
        ),
        0,
      );
    });

    test('F-READ-12: вырожденные размеры — ноль, а не бесконечность', () {
      expect(
        columnCacheExtent(
          sheetHeight: 0,
          visibleTop: 0,
          visibleHeight: 421,
          sheets: 1,
        ),
        0,
      );
      expect(
        columnCacheExtent(
          sheetHeight: 842,
          visibleTop: 0,
          visibleHeight: 0,
          sheets: 1,
        ),
        0,
      );
      expect(
        columnCacheExtent(
          sheetHeight: 842,
          visibleTop: double.nan,
          visibleHeight: 421,
          sheets: 1,
        ),
        0,
      );
    });
  });

  group('F-READ-02: масштаб грубой картинки', () {
    test('предел пикселей: страница A4 — около двух с половиной', () {
      final double cap = previewScaleCap(pageWidth: 595, pageHeight: 842);
      expect(cap, closeTo(2.45, 0.05));
      expect(595 * cap * 842 * cap, closeTo(kPreviewPixels, 1));
    });

    test('у страницы без размеров предела нет', () {
      expect(previewScaleCap(pageWidth: 0, pageHeight: 842), 0);
    });

    test('первая картинка чуть мельче нужного экрану', () {
      // Крупнее нужного она стала бы окончательной, а уменьшенная
      // картинка мягче резкой: чтение стало бы хуже, чем было.
      final double held = heldPreviewScale(held: 0, wanted: 2);
      expect(held, lessThan(2));
      expect(held, closeTo(2 * kPreviewShare, 1e-9));
    });

    test('рамки страниц гуляют — картинки не перерисовываются', () {
      final double held = heldPreviewScale(held: 0, wanted: 2);
      for (final double wanted in <double>[1.9, 2.0, 2.1, 2.3]) {
        expect(heldPreviewScale(held: held, wanted: wanted), held);
      }
    });

    test('удерживаемый масштаб крупнее нужного не остаётся', () {
      final double held = heldPreviewScale(held: 0, wanted: 2);
      final double next = heldPreviewScale(held: held, wanted: 1.5);
      expect(next, lessThan(1.5));
    });

    test('страница стала намного крупнее — картинки догоняют', () {
      final double held = heldPreviewScale(held: 0, wanted: 2);
      final double next = heldPreviewScale(held: held, wanted: 5);
      expect(next, closeTo(5 * kPreviewShare, 1e-9));
    });

    test('бессмысленный запрос масштаба ничего не меняет', () {
      expect(heldPreviewScale(held: 1.8, wanted: 0), 1.8);
      expect(heldPreviewScale(held: 1.8, wanted: double.nan), 1.8);
    });
  });

  group('F-READ-02: настройки показа страницы', () {
    test('без сохранённого — сразу, запас по платформе', () {
      expect(
        PageTurnSettings.parse(preview: null, reserve: null, desktop: false),
        const PageTurnSettings(preview: true, reserve: 1),
      );
      expect(
        PageTurnSettings.parse(preview: null, reserve: null, desktop: true),
        const PageTurnSettings(preview: true, reserve: 2),
      );
    });

    test('сохранённое главнее умолчания', () {
      expect(
        PageTurnSettings.parse(preview: 'false', reserve: '0', desktop: true),
        const PageTurnSettings(preview: false, reserve: 0),
      );
    });

    test('мусор в базе не ломает чтение', () {
      expect(
        PageTurnSettings.parse(preview: 'да', reserve: 'много', desktop: false),
        const PageTurnSettings(preview: true, reserve: 1),
      );
      expect(
        PageTurnSettings.parse(preview: null, reserve: '99', desktop: false),
        const PageTurnSettings(preview: true, reserve: 2),
      );
      expect(
        PageTurnSettings.parse(preview: null, reserve: '-3', desktop: false),
        const PageTurnSettings(preview: true, reserve: 0),
      );
    });

    test('выключенная ступенька запаса не держит', () {
      // Наготове держатся грубые картинки: без них держать нечего, и
      // просмотрщик работает как до F-READ-02.
      const PageTurnSettings off = PageTurnSettings(preview: false, reserve: 2);
      expect(off.effectiveReserve, 0);
      const PageTurnSettings on = PageTurnSettings(preview: true, reserve: 2);
      expect(on.effectiveReserve, 2);
    });
  });
}
