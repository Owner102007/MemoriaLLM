import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/spread.dart';

/// Обычная страница книги: A4 в точках PDF.
const double _width = 595;
const double _height = 842;

SheetPage _page({
  CropBox content = CropBox.full,
  List<double> breaks = const <double>[],
  double width = _width,
  double height = _height,
}) {
  return SheetPage(
    width: width,
    height: height,
    content: content,
    breaks: breaks,
  );
}

/// Проходит книгу от первой страницы до упора и записывает каждый экран.
///
/// Экран — это страницы листа и номер полосы на нём. Именно так читатель
/// и видит книгу: два одинаковых экрана подряд — это нажатие, после
/// которого ничего не изменилось.
List<String> _walk({
  required int pageCount,
  required int fragmentCount,
  required bool spread,
}) {
  final List<String> screens = <String>[];
  SheetPosition? at = const SheetPosition(page: 1, fragment: 0);
  // Потолок шагов: зацикленное листание должно упасть в сравнении, а не
  // повесить прогон.
  for (int step = 0; at != null && step < 1000; step++) {
    final List<int> pages = spread
        ? spreadPages(at.page, pageCount)
        : <int>[at.page];
    screens.add('${pages.join('+')}:${at.fragment}');
    at = stepSheet(
      page: at.page,
      fragment: at.fragment,
      pageCount: pageCount,
      fragmentCount: fragmentCount,
      spread: spread,
      forward: true,
    );
  }
  return screens;
}

void main() {
  group('листание листами', () {
    test('BUG-01: шаг в развороте ведёт на следующую пару страниц', () {
      // Прежде шаг вёл на страницу + 1: со второй на третью, а она лежит
      // на том же листе — экран не менялся.
      expect(nextSheetPage(page: 1, pageCount: 10, spread: true), 2);
      expect(nextSheetPage(page: 2, pageCount: 10, spread: true), 4);
      expect(nextSheetPage(page: 3, pageCount: 10, spread: true), 4);
      expect(nextSheetPage(page: 8, pageCount: 10, spread: true), 10);
      expect(nextSheetPage(page: 10, pageCount: 10, spread: true), isNull);

      expect(previousSheetPage(page: 10, pageCount: 10, spread: true), 8);
      expect(previousSheetPage(page: 5, pageCount: 10, spread: true), 2);
      expect(previousSheetPage(page: 4, pageCount: 10, spread: true), 2);
      expect(previousSheetPage(page: 3, pageCount: 10, spread: true), 1);
      expect(previousSheetPage(page: 2, pageCount: 10, spread: true), 1);
      expect(previousSheetPage(page: 1, pageCount: 10, spread: true), isNull);
    });

    test('BUG-01: в развороте ни один экран не показан дважды', () {
      expect(_walk(pageCount: 6, fragmentCount: 1, spread: true), <String>[
        '1:0',
        '2+3:0',
        '4+5:0',
        '6:0',
      ]);
      expect(_walk(pageCount: 7, fragmentCount: 1, spread: true), <String>[
        '1:0',
        '2+3:0',
        '4+5:0',
        '6+7:0',
      ]);
    });

    test('BUG-01: в полразворота полосы идут по одной и не повторяются', () {
      expect(_walk(pageCount: 5, fragmentCount: 2, spread: true), <String>[
        '1:0',
        '1:1',
        '2+3:0',
        '2+3:1',
        '4+5:0',
        '4+5:1',
      ]);
    });

    test('BUG-01: каждая страница книги показана ровно один раз', () {
      // Чётные и нечётные книги, от одной страницы до сотни: разворот
      // обязан пройти книгу целиком, ничего не пропустив и не повторив.
      for (int pageCount = 1; pageCount <= 101; pageCount++) {
        final List<String> screens = _walk(
          pageCount: pageCount,
          fragmentCount: 1,
          spread: true,
        );
        expect(
          screens.toSet().length,
          screens.length,
          reason: 'книга в $pageCount страниц: экран повторился',
        );
        final List<int> shown = <int>[
          for (final String screen in screens)
            for (final String page in screen.split(':').first.split('+'))
              int.parse(page),
        ];
        expect(shown, <int>[
          for (int page = 1; page <= pageCount; page++) page,
        ], reason: 'книга в $pageCount страниц');
      }
    });

    test('назад читатель попадает в низ предыдущего листа', () {
      expect(
        stepSheet(
          page: 4,
          fragment: 0,
          pageCount: 10,
          fragmentCount: 2,
          spread: true,
          forward: false,
        ),
        const SheetPosition(page: 2, fragment: 1),
      );
      expect(
        stepSheet(
          page: 2,
          fragment: 1,
          pageCount: 10,
          fragmentCount: 2,
          spread: true,
          forward: false,
        ),
        const SheetPosition(page: 2, fragment: 0),
      );
    });

    test('путь назад повторяет путь вперёд в обратном порядке', () {
      for (final int pageCount in <int>[1, 2, 6, 7, 30, 31]) {
        for (final int fragmentCount in <int>[1, 2]) {
          final List<SheetPosition> forward = <SheetPosition>[];
          SheetPosition? at = const SheetPosition(page: 1, fragment: 0);
          while (at != null && forward.length < 1000) {
            forward.add(at);
            at = stepSheet(
              page: at.page,
              fragment: at.fragment,
              pageCount: pageCount,
              fragmentCount: fragmentCount,
              spread: true,
              forward: true,
            );
          }
          final List<SheetPosition> backward = <SheetPosition>[];
          at = forward.last;
          while (at != null && backward.length < 1000) {
            backward.add(at);
            at = stepSheet(
              page: at.page,
              fragment: at.fragment,
              pageCount: pageCount,
              fragmentCount: fragmentCount,
              spread: true,
              forward: false,
            );
          }
          expect(
            backward.reversed.toList(),
            forward,
            reason: 'страниц $pageCount, полос $fragmentCount',
          );
        }
      }
    });

    test('шаг с правой страницы разворота уводит с листа, а не на него', () {
      // Читатель мог попасть на правую страницу переходом из поиска или
      // из оглавления: лист тот же, и шаг обязан считаться от листа.
      expect(
        stepSheet(
          page: 3,
          fragment: 0,
          pageCount: 10,
          fragmentCount: 1,
          spread: true,
          forward: true,
        ),
        const SheetPosition(page: 4, fragment: 0),
      );
      expect(
        stepSheet(
          page: 3,
          fragment: 0,
          pageCount: 10,
          fragmentCount: 1,
          spread: true,
          forward: false,
        ),
        const SheetPosition(page: 1, fragment: 0),
      );
    });

    test('без разворота шаг — страница, как и был', () {
      expect(_walk(pageCount: 3, fragmentCount: 1, spread: false), <String>[
        '1:0',
        '2:0',
        '3:0',
      ]);
      expect(_walk(pageCount: 2, fragmentCount: 3, spread: false), <String>[
        '1:0',
        '1:1',
        '1:2',
        '2:0',
        '2:1',
        '2:2',
      ]);
      expect(previousSheetPage(page: 5, pageCount: 10, spread: false), 4);
      expect(nextSheetPage(page: 10, pageCount: 10, spread: false), isNull);
    });

    test('на краях книги и в пустой книге шагать некуда', () {
      for (final bool spread in <bool>[false, true]) {
        expect(
          stepSheet(
            page: 1,
            fragment: 0,
            pageCount: 10,
            fragmentCount: 1,
            spread: spread,
            forward: false,
          ),
          isNull,
        );
        expect(
          stepSheet(
            page: 10,
            fragment: 0,
            pageCount: 10,
            fragmentCount: 1,
            spread: spread,
            forward: true,
          ),
          isNull,
        );
        expect(nextSheetPage(page: 1, pageCount: 0, spread: spread), isNull);
        expect(
          previousSheetPage(page: 1, pageCount: 0, spread: spread),
          isNull,
        );
      }
    });
  });

  group('рамка листа', () {
    const CropBox content = CropBox(
      left: 0.1,
      top: 0.12,
      right: 0.9,
      bottom: 0.88,
    );

    test('лист из одной страницы отдаёт её рамку как есть', () {
      expect(
        identical(sheetContent(<SheetPage>[_page(content: content)]), content),
        isTrue,
      );
      expect(sheetContent(const <SheetPage>[]), CropBox.full);
    });

    test('BUG-02: поле страницы на развороте не удваивается', () {
      // Поле в 0,1 ширины страницы — это 0,05 ширины листа из двух
      // страниц. Прежде рамка страницы шла в лист как есть, и слева
      // срезалось 0,1 листа, то есть 0,2 страницы: поле и край текста.
      final CropBox sheet = sheetContent(<SheetPage>[
        _page(content: content),
        _page(content: content),
      ]);
      expect(sheet.left, closeTo(0.05, 1e-9));
      expect(sheet.right, closeTo(0.95, 1e-9));
      expect(sheet.top, closeTo(0.12, 1e-9));
      expect(sheet.bottom, closeTo(0.88, 1e-9));
    });

    test('BUG-02: текст обеих страниц разворота остаётся внутри рамки', () {
      // Поля чётных и нечётных страниц зеркальны: у левой страницы
      // широкое поле справа, у правой — слева.
      const CropBox even = CropBox(
        left: 0.08,
        top: 0.1,
        right: 0.85,
        bottom: 0.9,
      );
      const CropBox odd = CropBox(
        left: 0.15,
        top: 0.14,
        right: 0.92,
        bottom: 0.86,
      );
      final CropBox sheet = sheetContent(<SheetPage>[
        _page(content: even),
        _page(content: odd),
      ]);
      // Левая страница занимает левую половину листа, правая — правую.
      expect(sheet.left, lessThanOrEqualTo(even.left / 2 + 1e-9));
      expect(sheet.right, greaterThanOrEqualTo(0.5 + odd.right / 2 - 1e-9));
      expect(sheet.top, lessThanOrEqualTo(even.top + 1e-9));
      expect(sheet.bottom, greaterThanOrEqualTo(even.bottom - 1e-9));
      expect(sheet.isValid, isTrue);
    });

    test('страницы разного размера сводятся к долям листа', () {
      // Левая страница 400×800, правая 600×600: лист 1000×800, правая
      // страница начинается с 0,4 его ширины и кончается на 0,75 высоты.
      final CropBox sheet = sheetContent(<SheetPage>[
        _page(
          width: 400,
          height: 800,
          content: const CropBox(left: 0.5, top: 0.5, right: 1, bottom: 0.6),
        ),
        _page(
          width: 600,
          height: 600,
          content: const CropBox(left: 0, top: 0.2, right: 0.5, bottom: 1),
        ),
      ]);
      expect(sheet.left, closeTo(0.2, 1e-9));
      expect(sheet.right, closeTo(0.7, 1e-9));
      expect(sheet.top, closeTo(0.15, 1e-9));
      expect(sheet.bottom, closeTo(0.75, 1e-9));
    });

    test('страница без рамки входит в лист целиком', () {
      // Рамка соседней страницы ещё не посчитана — резать по незнанию
      // нельзя: лишнее поле лучше потерянного текста.
      final CropBox sheet = sheetContent(<SheetPage>[
        _page(content: content),
        _page(),
      ]);
      expect(sheet.left, closeTo(0.05, 1e-9));
      expect(sheet.right, 1);
      expect(sheet.top, 0);
      expect(sheet.bottom, 1);

      const CropBox broken = CropBox(left: 0.9, top: 0, right: 0.1, bottom: 1);
      expect(
        sheetContent(<SheetPage>[_page(content: broken), _page()]),
        CropBox.full,
      );
    });

    test('лист без размеров показывается целиком', () {
      expect(
        sheetContent(<SheetPage>[
          _page(content: content, width: 0, height: 0),
          _page(content: content, width: 0, height: 0),
        ]),
        CropBox.full,
      );
    });
  });

  group('просветы листа', () {
    test('лист из одной страницы отдаёт её просветы как есть', () {
      const List<double> breaks = <double>[0.2, 0.5, 0.8];
      expect(
        identical(sheetBreaks(<SheetPage>[_page(breaks: breaks)]), breaks),
        isTrue,
      );
      expect(sheetBreaks(const <SheetPage>[]), isEmpty);
    });

    test('в развороте остаются только общие просветы', () {
      final List<double> breaks = sheetBreaks(<SheetPage>[
        _page(breaks: const <double>[0.2, 0.5, 0.8]),
        _page(breaks: const <double>[0.201, 0.5, 0.9]),
      ]);
      expect(breaks.length, 2);
      expect(breaks[0], closeTo(0.2005, 1e-9));
      expect(breaks[1], closeTo(0.5, 1e-9));
    });

    test('общего просвета нет — граница не обещана', () {
      // Строки двух страниц стоят вразнобой: просвет одной приходится на
      // середину строки другой. Деление получит пустой список и
      // перекроет полосы, вместо того чтобы рассечь строку.
      expect(
        sheetBreaks(<SheetPage>[
          _page(breaks: const <double>[0.2, 0.5]),
          _page(breaks: const <double>[0.21, 0.51]),
        ]),
        isEmpty,
      );
    });

    test('страница без просветов ограничений не ставит', () {
      final List<double> breaks = sheetBreaks(<SheetPage>[
        _page(breaks: const <double>[0.25, 0.5]),
        _page(),
      ]);
      expect(breaks, <double>[0.25, 0.5]);
    });

    test('просветы страниц разной высоты сводятся к высоте листа', () {
      // Правая страница вдвое ниже: её просвет на 0,5 высоты лежит на
      // 0,25 высоты листа.
      final List<double> breaks = sheetBreaks(<SheetPage>[
        _page(height: 800, breaks: const <double>[0.25, 0.6]),
        _page(height: 400, breaks: const <double>[0.5]),
      ]);
      expect(breaks.length, 1);
      expect(breaks.single, closeTo(0.25, 1e-9));
    });

    test('полразворота режется по общему просвету', () {
      final List<SheetPage> pages = <SheetPage>[
        _page(breaks: const <double>[0.3, 0.47, 0.7]),
        _page(breaks: const <double>[0.3, 0.47, 0.7]),
      ];
      final List<CropBox> parts = fragmentsFor(
        content: sheetContent(pages),
        mode: PageDisplayMode.spreadHalf,
        breaks: sheetBreaks(pages),
      );
      expect(parts.length, 2);
      expect(parts.first.bottom, closeTo(0.47, 1e-9));
      expect(parts.last.top, closeTo(0.47, 1e-9));
    });
  });
}
