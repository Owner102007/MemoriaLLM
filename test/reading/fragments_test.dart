import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/columns.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reading.dart';

const CropBox _content = CropBox(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9);

const List<ColumnBand> _twoColumns = <ColumnBand>[
  ColumnBand(left: 0.1, right: 0.45),
  ColumnBand(left: 0.55, right: 0.9),
];

void main() {
  group('одна колонка', () {
    test('страница целиком — один фрагмент', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.full,
      );
      expect(parts, <CropBox>[_content]);
    });

    test('половина — две полосы, накрывающие всё содержимое', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      expect(parts.length, 2);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      expect(parts.first.left, _content.left);
      expect(parts.last.right, _content.right);
    });

    test('половины делятся чёткой линией, без повторов', () {
      // Нахлёст задумывался как забота о строке на границе, но повторял
      // её на обоих экранах, и читатель терял место. Граница одна.
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      expect(parts.first.bottom, closeTo(parts.last.top, 1e-9));
      expect(
        parts.first.height,
        closeTo(parts.last.height, 1e-9),
        reason: 'половины равны',
      );
    });

    test('треть — три полосы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.third,
      );
      expect(parts.length, 3);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      for (final CropBox part in parts) {
        expect(part.isValid, isTrue);
        expect(part.height, lessThan(_content.height));
      }
    });

    test('половина действительно вдвое крупнее страницы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
      );
      // Смысл режима: во столько же раз вырастет кегль на экране.
      expect(_content.height / parts.first.height, closeTo(2, 0.1));
    });
  });

  group('две колонки', () {
    test('половина — это колонка, а не верх страницы', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.half,
        columns: _twoColumns,
      );
      expect(parts.length, 2);
      expect(parts.first.left, 0.1);
      expect(parts.first.right, 0.45);
      expect(parts.first.top, _content.top);
      expect(parts.first.bottom, _content.bottom);
      expect(parts.last.left, 0.55);
    });

    test('треть — половина колонки, и порядок чтения сохранён', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.third,
        columns: _twoColumns,
      );
      expect(parts.length, 4);
      // Левая колонка сверху вниз, потом правая.
      expect(parts[0].right, 0.45);
      expect(parts[1].right, 0.45);
      expect(parts[0].top, lessThan(parts[1].top));
      expect(parts[2].left, 0.55);
      expect(parts[3].left, 0.55);
      expect(parts[2].top, lessThan(parts[3].top));
    });

    test('разворот колонками не делится', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.spread,
        columns: _twoColumns,
      );
      expect(parts, <CropBox>[_content]);
    });
  });

  test('испорченная рамка не оставляет читателя без фрагмента', () {
    final List<CropBox> parts = fragmentsFor(
      content: const CropBox(left: 1, top: 1, right: 0, bottom: 0),
      mode: PageDisplayMode.half,
    );
    expect(parts, <CropBox>[CropBox.full]);
  });

  group('число фрагментов', () {
    test('совпадает с тем, что вернуло деление', () {
      for (final PageDisplayMode mode in PageDisplayMode.values) {
        for (final int columns in <int>[1, 2]) {
          final List<CropBox> parts = fragmentsFor(
            content: _content,
            mode: mode,
            columns: columns == 2
                ? _twoColumns
                : const <ColumnBand>[ColumnBand(left: 0.1, right: 0.9)],
          );
          expect(
            parts.length,
            fragmentCountFor(mode: mode, columnCount: columns),
            reason: 'режим $mode, колонок $columns',
          );
        }
      }
    });
  });

  group('смена режима не теряет место', () {
    test('верхняя половина остаётся верхом при переходе на треть', () {
      expect(remapFragment(index: 0, oldCount: 2, newCount: 3), 0);
    });

    test('нижняя половина попадает в нижнюю треть', () {
      expect(remapFragment(index: 1, oldCount: 2, newCount: 3), 2);
    });

    test('середина трети попадает в ту же половину', () {
      expect(remapFragment(index: 1, oldCount: 3, newCount: 2), 1);
      expect(remapFragment(index: 0, oldCount: 3, newCount: 2), 0);
      expect(remapFragment(index: 2, oldCount: 3, newCount: 2), 1);
    });

    test('переход на страницу целиком всегда даёт нулевой фрагмент', () {
      for (int i = 0; i < 4; i++) {
        expect(remapFragment(index: i, oldCount: 4, newCount: 1), 0);
      }
    });

    test('мусорный номер фрагмента не выводит за диапазон', () {
      expect(remapFragment(index: -5, oldCount: 3, newCount: 2), 0);
      expect(remapFragment(index: 99, oldCount: 3, newCount: 2), 1);
      expect(clampFragment(-1, 3), 0);
      expect(clampFragment(9, 3), 2);
      expect(clampFragment(9, 0), 0);
    });

    test('обратный переход возвращает примерно туда же', () {
      for (int i = 0; i < 3; i++) {
        final int toHalf = remapFragment(index: i, oldCount: 3, newCount: 2);
        final int back = remapFragment(index: toHalf, oldCount: 2, newCount: 3);
        expect((back - i).abs(), lessThanOrEqualTo(1));
      }
    });
  });

  group('разворот', () {
    test('первая страница стоит одна, дальше идут пары', () {
      expect(spreadPages(1, 10), <int>[1]);
      expect(spreadPages(2, 10), <int>[2, 3]);
      expect(spreadPages(3, 10), <int>[2, 3]);
      expect(spreadPages(4, 10), <int>[4, 5]);
      expect(spreadPages(9, 10), <int>[8, 9]);
    });

    test('последняя страница без пары показывается одна', () {
      expect(spreadPages(10, 10), <int>[10]);
    });

    test('края книги не ломают пару', () {
      expect(spreadPages(0, 10), <int>[1]);
      expect(spreadPages(99, 10), <int>[10]);
      expect(spreadPages(1, 0), <int>[1]);
      expect(spreadPages(1, 1), <int>[1]);
    });

    test('половина разворота делит его по горизонтали', () {
      final List<CropBox> parts = fragmentsFor(
        content: _content,
        mode: PageDisplayMode.spreadHalf,
        columns: _twoColumns,
      );
      expect(parts.length, 2);
      // Строка идёт через обе страницы сразу, поэтому колонки внутри
      // страниц разворот не делят.
      expect(parts.first.left, _content.left);
      expect(parts.first.right, _content.right);
      expect(parts.first.top, _content.top);
      expect(parts.last.bottom, _content.bottom);
      expect(parts.first.bottom, closeTo(parts.last.top, 1e-9));
    });

    test('разворот и его половина показывают по две страницы', () {
      expect(isSpreadMode(PageDisplayMode.spread), isTrue);
      expect(isSpreadMode(PageDisplayMode.spreadHalf), isTrue);
      expect(isSpreadMode(PageDisplayMode.half), isFalse);
      expect(isSpreadMode(PageDisplayMode.full), isFalse);
    });
  });

  group('положение экрана', () {
    test('целая страница читается вертикально, деление — горизонтально', () {
      expect(
        preferredOrientationFor(PageDisplayMode.full),
        ScreenOrientation.portrait,
      );
      for (final PageDisplayMode mode in <PageDisplayMode>[
        PageDisplayMode.half,
        PageDisplayMode.third,
        PageDisplayMode.spread,
        PageDisplayMode.spreadHalf,
      ]) {
        expect(
          preferredOrientationFor(mode),
          ScreenOrientation.landscape,
          reason: '$mode',
        );
      }
    });
  });

  group('ради чего всё затевалось: текст должен стать крупнее', () {
    // Обрезанное содержимое страницы А4 и экран телефона 1080×2400.
    const double pageWidth = 428;
    const double pageHeight = 640;
    const double screenShort = 1080;
    const double screenLong = 2400;

    double scale({
      required double width,
      required double height,
      required bool landscape,
    }) {
      return fragmentScale(
        fragmentWidth: width,
        fragmentHeight: height,
        screenWidth: landscape ? screenLong : screenShort,
        screenHeight: landscape ? screenShort : screenLong,
      );
    }

    final double wholeInPortrait = scale(
      width: pageWidth,
      height: pageHeight,
      landscape: false,
    );

    test('половина на вертикальном экране не даёт ничего', () {
      // Ровно то, на что наткнулся владелец: полоса вдвое ниже, но той же
      // ширины, а страница вписывается в вертикальный экран по ширине.
      final double halfInPortrait = scale(
        width: pageWidth,
        height: pageHeight / 2,
        landscape: false,
      );
      expect(halfInPortrait, closeTo(wholeInPortrait, 1e-9));
    });

    test('половина на горизонтальном экране крупнее', () {
      final double halfInLandscape = scale(
        width: pageWidth,
        height: pageHeight / 2,
        landscape: true,
      );
      expect(halfInLandscape, greaterThan(wholeInPortrait));
      expect(halfInLandscape / wholeInPortrait, greaterThan(1.3));
    });

    test('треть на горизонтальном экране крупнее вдвое', () {
      final double thirdInLandscape = scale(
        width: pageWidth,
        height: pageHeight / 3,
        landscape: true,
      );
      expect(thirdInLandscape / wholeInPortrait, greaterThan(1.9));
    });

    test('бессмысленные размеры дают ноль, а не бесконечность', () {
      expect(
        fragmentScale(
          fragmentWidth: 0,
          fragmentHeight: 10,
          screenWidth: 100,
          screenHeight: 100,
        ),
        0,
      );
      expect(
        fragmentScale(
          fragmentWidth: 10,
          fragmentHeight: 10,
          screenWidth: -1,
          screenHeight: 100,
        ),
        0,
      );
    });
  });
}
