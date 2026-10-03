import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/sheet_arrangement.dart';

/// Раскладка листов в документе просмотрщика и куски соседних листов.
///
/// Всё здесь — числа: где лежит страница, где начинается лист, что от
/// соседа остаётся видно. Просмотрщик с настоящим PDFium в тестах не
/// строится, поэтому правила проверяются отдельно от него — исчерпывающе.
void main() {
  /// Книга из страниц разного размера: ширины и высоты по номеру.
  const List<double> widths = <double>[400, 420, 380, 400, 410];
  const List<double> heights = <double>[600, 640, 620, 600, 610];

  List<Rect> arrange({
    required SheetArrangement arrangement,
    required bool spread,
    int pageCount = 5,
  }) {
    return arrangePages(
      pageCount: pageCount,
      widthOf: (int page) => widths[page - 1],
      heightOf: (int page) => heights[page - 1],
      arrangement: arrangement,
      spread: spread,
    );
  }

  Offset originOf(
    int firstPage, {
    required SheetArrangement arrangement,
    required bool spread,
    int pageCount = 5,
  }) {
    return sheetOrigin(
      firstPage: firstPage,
      pageCount: pageCount,
      widthOf: (int page) => widths[page - 1],
      heightOf: (int page) => heights[page - 1],
      arrangement: arrangement,
      spread: spread,
    );
  }

  group('какая раскладка нужна режиму', () {
    test('F-READ-12: лист целиком — в ряд, полосы — в столбик', () {
      expect(arrangementFor(PageDisplayMode.full), SheetArrangement.row);
      expect(arrangementFor(PageDisplayMode.spread), SheetArrangement.row);
      expect(arrangementFor(PageDisplayMode.half), SheetArrangement.column);
      expect(arrangementFor(PageDisplayMode.third), SheetArrangement.column);
      expect(
        arrangementFor(PageDisplayMode.spreadHalf),
        SheetArrangement.column,
      );
    });
  });

  group('ряд', () {
    test('страницы стоят вплотную слева направо, как и прежде', () {
      final List<Rect> rects = arrange(
        arrangement: SheetArrangement.row,
        spread: false,
      );
      expect(rects, hasLength(5));
      expect(rects[0], const Rect.fromLTWH(0, 0, 400, 600));
      expect(rects[1], const Rect.fromLTWH(400, 0, 420, 640));
      expect(rects[2], const Rect.fromLTWH(820, 0, 380, 620));
      expect(arrangedSize(rects), const Size(2010, 640));
    });

    test('разворот ряда не меняет', () {
      expect(
        arrange(arrangement: SheetArrangement.row, spread: true),
        arrange(arrangement: SheetArrangement.row, spread: false),
      );
    });

    test('лист начинается там, где кончились страницы перед ним', () {
      expect(
        originOf(1, arrangement: SheetArrangement.row, spread: false),
        Offset.zero,
      );
      expect(
        originOf(3, arrangement: SheetArrangement.row, spread: false),
        const Offset(820, 0),
      );
      expect(
        originOf(4, arrangement: SheetArrangement.row, spread: true),
        const Offset(1200, 0),
      );
    });
  });

  group('столбик', () {
    test('F-READ-12: следующая страница лежит под текущей', () {
      final List<Rect> rects = arrange(
        arrangement: SheetArrangement.column,
        spread: false,
      );
      expect(rects, hasLength(5));
      expect(rects[0], const Rect.fromLTWH(0, 0, 400, 600));
      expect(rects[1], const Rect.fromLTWH(0, 600, 420, 640));
      expect(rects[2], const Rect.fromLTWH(0, 1240, 380, 620));
      // Вплотную: низ страницы — это верх следующей.
      for (int i = 1; i < rects.length; i++) {
        expect(rects[i].top, rects[i - 1].bottom);
      }
      expect(arrangedSize(rects), const Size(420, 3070));
    });

    test('F-READ-12: лист разворота — две страницы рядом, листы столбиком', () {
      final List<Rect> rects = arrange(
        arrangement: SheetArrangement.column,
        spread: true,
      );
      // Первая страница стоит одна — обложка.
      expect(rects[0], const Rect.fromLTWH(0, 0, 400, 600));
      // Дальше пары (2, 3) и (4, 5): правая начинается, где кончилась
      // левая, а следующая пара — под самой высокой страницей этой.
      expect(rects[1], const Rect.fromLTWH(0, 600, 420, 640));
      expect(rects[2], const Rect.fromLTWH(420, 600, 380, 620));
      expect(rects[3], const Rect.fromLTWH(0, 1240, 400, 600));
      expect(rects[4], const Rect.fromLTWH(400, 1240, 410, 610));
      expect(arrangedSize(rects), const Size(810, 1850));
    });

    test('F-READ-12: последняя страница разворота может остаться одна', () {
      final List<Rect> rects = arrange(
        arrangement: SheetArrangement.column,
        spread: true,
        pageCount: 4,
      );
      expect(rects, hasLength(4));
      expect(rects[3], const Rect.fromLTWH(0, 1240, 400, 600));
    });

    test('F-READ-12: начало листа совпадает с местом его первой страницы', () {
      // Матрица просмотрщика считается от начала листа, а страницы
      // раскладывает другая функция: разойдись они на точку — и страница
      // сядет не туда. Проверяется на всех листах всех раскладок.
      for (final SheetArrangement arrangement in SheetArrangement.values) {
        for (final bool spread in <bool>[false, true]) {
          for (final int pageCount in <int>[1, 2, 4, 5]) {
            final List<Rect> rects = arrange(
              arrangement: arrangement,
              spread: spread,
              pageCount: pageCount,
            );
            int first = 1;
            while (first <= pageCount) {
              final int last = sheetLastPage(
                first: first,
                pageCount: pageCount,
                spread: spread,
              );
              expect(
                originOf(
                  first,
                  arrangement: arrangement,
                  spread: spread,
                  pageCount: pageCount,
                ),
                rects[first - 1].topLeft,
                reason: '$arrangement, разворот: $spread, лист с $first',
              );
              first = last + 1;
            }
          }
        }
      }
    });

    test('листы разворота считаются так же, как при листании', () {
      expect(sheetLastPage(first: 1, pageCount: 5, spread: true), 1);
      expect(sheetLastPage(first: 2, pageCount: 5, spread: true), 3);
      expect(sheetLastPage(first: 4, pageCount: 5, spread: true), 5);
      expect(sheetLastPage(first: 4, pageCount: 4, spread: true), 4);
      expect(sheetLastPage(first: 3, pageCount: 5, spread: false), 3);
    });

    test('пустой документ не делит на ноль', () {
      expect(
        arrange(
          arrangement: SheetArrangement.column,
          spread: false,
          pageCount: 0,
        ),
        isEmpty,
      );
      expect(arrangedSize(const <Rect>[]), const Size(1, 1));
    });
  });

  group('что видно от соседних листов', () {
    const Rect sheet = Rect.fromLTWH(200, 0, 400, 600);

    test('F-READ-13: в ряду сосед — полоска заданной ширины у края', () {
      final List<NeighbourZone> zones = neighbourZones(
        arrangement: SheetArrangement.row,
        sheet: sheet,
        strip: sheet,
        band: 0,
        width: 40,
        hasBefore: true,
        hasAfter: true,
      );
      expect(zones, hasLength(2));
      expect(zones[0].rect, const Rect.fromLTRB(160, 0, 200, 600));
      expect(zones[1].rect, const Rect.fromLTRB(600, 0, 640, 600));
      // Стык идёт по краю своей страницы.
      expect(zones[0].seamFrom, sheet.topLeft);
      expect(zones[0].seamTo, sheet.bottomLeft);
      expect(zones[1].seamFrom, sheet.topRight);
      expect(zones[1].seamTo, sheet.bottomRight);
    });

    test('F-READ-13: ширина полоски не зависит от окна', () {
      // В S6.1 из-под тени торчало столько чужой страницы, сколько
      // влезло в окно. Теперь ширину назначаем мы: лист может стоять где
      // угодно, полоска остаётся той же.
      for (final double left in <double>[0, 200, 900]) {
        final Rect moved = Rect.fromLTWH(left, 0, 400, 600);
        final List<NeighbourZone> zones = neighbourZones(
          arrangement: SheetArrangement.row,
          sheet: moved,
          strip: moved,
          band: 0,
          width: 40,
          hasBefore: true,
          hasAfter: true,
        );
        for (final NeighbourZone zone in zones) {
          expect(zone.rect.width, 40, reason: 'лист в $left');
          expect(zone.rect.height, 600, reason: 'лист в $left');
        }
      }
    });

    test('F-READ-13: нулевая ширина — соседа не видно вовсе', () {
      expect(
        neighbourZones(
          arrangement: SheetArrangement.row,
          sheet: sheet,
          strip: sheet,
          band: 0,
          width: 0,
          hasBefore: true,
          hasAfter: true,
        ),
        isEmpty,
      );
    });

    test('F-READ-13: у начала и конца книги соседа нет', () {
      final List<NeighbourZone> first = neighbourZones(
        arrangement: SheetArrangement.row,
        sheet: sheet,
        strip: sheet,
        band: 0,
        width: 40,
        hasBefore: false,
        hasAfter: true,
      );
      expect(first, hasLength(1));
      expect(first.single.rect.left, sheet.right);

      final List<NeighbourZone> last = neighbourZones(
        arrangement: SheetArrangement.row,
        sheet: sheet,
        strip: sheet,
        band: 0,
        width: 40,
        hasBefore: true,
        hasAfter: false,
      );
      expect(last, hasLength(1));
      expect(last.single.rect.right, sheet.left);
    });

    group('столбик: подглядывание в соседнюю страницу', () {
      // Лист в три полосы: верхняя, средняя, нижняя. Нахлёст — 30 точек.
      const Rect page = Rect.fromLTWH(0, -400, 800, 1200);

      List<NeighbourZone> zonesFor(Rect strip, {double band = 30}) {
        return neighbourZones(
          arrangement: SheetArrangement.column,
          sheet: page,
          strip: strip,
          band: band,
          width: 40,
          hasBefore: true,
          hasAfter: true,
        );
      }

      test('F-READ-12: под последней полосой — верх следующей страницы', () {
        final List<NeighbourZone> zones = zonesFor(
          const Rect.fromLTWH(0, 400, 800, 400),
        );
        expect(zones, hasLength(1));
        // Ровно на высоту нахлёста и ровно под листом.
        expect(zones.single.rect, const Rect.fromLTRB(0, 800, 800, 830));
        expect(zones.single.seamFrom, page.bottomLeft);
        expect(zones.single.seamTo, page.bottomRight);
      });

      test('F-READ-12: над первой полосой — низ предыдущей страницы', () {
        final List<NeighbourZone> zones = zonesFor(
          const Rect.fromLTWH(0, -400, 800, 400),
        );
        expect(zones, hasLength(1));
        expect(zones.single.rect, const Rect.fromLTRB(0, -430, 800, -400));
        expect(zones.single.seamFrom, page.topLeft);
        expect(zones.single.seamTo, page.topRight);
      });

      test('F-READ-12: средняя полоса соседних страниц не видит', () {
        // Над ней и под ней — своя страница: её гасит обычное затемнение.
        expect(zonesFor(const Rect.fromLTWH(0, 0, 800, 400)), isEmpty);
      });

      test('F-READ-12: поле короче нахлёста — сосед виден в остатке', () {
        // Рамка обрезки оставила под последней полосой десять точек поля:
        // от нахлёста в тридцать на соседа приходится двадцать.
        final List<NeighbourZone> zones = zonesFor(
          const Rect.fromLTWH(0, 390, 800, 400),
        );
        expect(zones.single.rect, const Rect.fromLTRB(0, 800, 800, 820));
      });

      test('F-READ-12: без нахлёста соседней страницы не видно', () {
        expect(
          zonesFor(const Rect.fromLTWH(0, 400, 800, 400), band: 0),
          isEmpty,
        );
      });

      test('F-READ-12: по бокам в столбике никого нет', () {
        final List<NeighbourZone> zones = zonesFor(
          const Rect.fromLTWH(0, 400, 800, 400),
        );
        expect(zones, isNotEmpty);
        for (final NeighbourZone zone in zones) {
          expect(zone.rect.left, page.left);
          expect(zone.rect.right, page.right);
        }
      });
    });

    test('пустой лист соседей не показывает', () {
      expect(
        neighbourZones(
          arrangement: SheetArrangement.row,
          sheet: Rect.zero,
          strip: Rect.zero,
          band: 30,
          width: 40,
          hasBefore: true,
          hasAfter: true,
        ),
        isEmpty,
      );
    });
  });

  group('F-READ-13: сосед темнее своей страницы', () {
    test('F-READ-13: при любом затемнении сосед темнее', () {
      for (final double dim in <double>[0, 0.3, kDefaultDimOutside, 0.9]) {
        expect(neighbourDimFor(dim), greaterThan(dim), reason: '$dim');
        expect(neighbourDimFor(dim), lessThan(1), reason: '$dim');
      }
    });

    test('F-READ-13: и при нулевом затемнении сосед притушен', () {
      // Иначе на широком окне он читался бы как вторая страница
      // разворота.
      expect(neighbourDimFor(0), closeTo(0.5, 1e-12));
      expect(neighbourDimFor(kDefaultDimOutside), closeTo(0.8, 1e-12));
    });

    test('F-READ-13: мусор на входе не даёт мусора', () {
      expect(neighbourDimFor(double.nan), closeTo(0.5, 1e-12));
      expect(neighbourDimFor(7), lessThan(1));
    });
  });
}
