import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/search_dock.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

/// F-TEXT-11, ALG-UI-31: где стоит панель поиска.
///
/// Панель остаётся на экране после выбора результата и не должна
/// закрывать то, ради чего её открыли, — найденное. Правило — чистый
/// счёт, и проверяется числами: широкое окно, телефон в портрете и в
/// альбоме, сетка положений найденного.
void main() {
  const Size phone = Size(360, 760);
  const Size phoneTurned = Size(760, 360);
  const Size desktop = Size(1280, 800);

  /// Строка текста на экране: во всю ширину колонки, у высоты [top].
  Rect line(Size screen, double top, {double height = 24}) {
    return Rect.fromLTWH(
      screen.width * 0.1,
      top,
      screen.width * 0.8,
      height,
    );
  }

  SearchDock place(
    Size screen, {
    Rect? found,
    SearchDockSide? current,
    Size? area,
  }) {
    return placeSearchPanel(
      screen: screen,
      area: area ?? screen,
      found: found,
      current: current,
    );
  }

  group('F-TEXT-11: широкое окно', () {
    test('панель стоит справа, рядом со страницей', () {
      final SearchDock dock = place(desktop);
      expect(dock.side, SearchDockSide.right);
      expect(dock.extent, kSearchPanelWidth);
      expect(dock.beside, isTrue);
      expect(dock.compact, isFalse);
    });

    test('место под лист — окно минус панель', () {
      final SearchDock dock = place(desktop);
      expect(dock.taken, kSearchPanelWidth);
      const double left = 1280 - kSearchPanelWidth;
      expect(
        dock.rectIn(desktop),
        const Rect.fromLTWH(left, 0, kSearchPanelWidth, 800),
      );
    });

    test('найденное панель не двигает: под ней ему не оказаться', () {
      for (double left = 0; left < 1200; left += 100) {
        final SearchDock dock = place(
          desktop,
          found: Rect.fromLTWH(left, 300, 80, 20),
          current: SearchDockSide.left,
        );
        expect(dock.side, SearchDockSide.right, reason: 'слева $left');
        expect(dock.beside, isTrue);
      }
    });

    test('граница широкого окна — 900 точек', () {
      expect(isSearchWide(const Size(900, 600)), isTrue);
      expect(isSearchWide(const Size(899, 600)), isFalse);
      expect(place(const Size(900, 600)).beside, isTrue);
      expect(place(const Size(899, 600)).beside, isFalse);
    });
  });

  group('F-TEXT-11: телефон в портрете', () {
    test('из коробки панель внизу и не выше 40 % экрана', () {
      final SearchDock dock = place(phone);
      expect(dock.side, SearchDockSide.bottom);
      expect(dock.extent, closeTo(760 * 0.4, 1e-9));
      expect(dock.beside, isFalse, reason: 'лежит поверх страницы');
      expect(dock.taken, 0, reason: 'лист под ней не перекладывается');
      expect(dock.vertical, isFalse);
    });

    test('найденное наверху — панель остаётся внизу', () {
      final SearchDock dock = place(phone, found: line(phone, 120));
      expect(dock.side, SearchDockSide.bottom);
    });

    test('найденное внизу — панель переезжает наверх', () {
      final SearchDock dock = place(phone, found: line(phone, 600));
      expect(dock.side, SearchDockSide.top);
      expect(dock.compact, isFalse);
    });

    test('панель не переезжает, пока найденное не закрыто', () {
      // Стояла наверху, следующее совпадение — в середине экрана, мимо
      // обеих полос: панель остаётся где была, а не возвращается вниз.
      final SearchDock dock = place(
        phone,
        found: line(phone, 370),
        current: SearchDockSide.top,
      );
      expect(dock.side, SearchDockSide.top);
    });

    test('найденное под верхней панелью — она возвращается вниз', () {
      final SearchDock dock = place(
        phone,
        found: line(phone, 100),
        current: SearchDockSide.top,
      );
      expect(dock.side, SearchDockSide.bottom);
    });

    test('найденное нигде не закрыто панелью — на сетке положений', () {
      for (final SearchDockSide start in <SearchDockSide>[
        SearchDockSide.bottom,
        SearchDockSide.top,
      ]) {
        for (double top = 0; top <= 736; top += 8) {
          final Rect found = line(phone, top);
          final SearchDock dock = place(phone, found: found, current: start);
          expect(
            dock.rectIn(phone).overlaps(found),
            isFalse,
            reason: 'найденное на высоте $top, панель была $start, стала $dock',
          );
        }
      }
    });

    test('выделение через весь экран — панель сжимается до строки', () {
      final SearchDock dock = place(
        phone,
        found: const Rect.fromLTWH(36, 200, 288, 400),
      );
      expect(dock.compact, isTrue);
      expect(dock.extent, kSearchCompactExtent);
      expect(dock.side, SearchDockSide.bottom, reason: 'остаётся где была');
    });

    test('сжатая панель уходит от найденного, если оно у её края', () {
      // Найденное занимает весь низ экрана и середину: одна строка
      // панели встаёт наверху, где его нет.
      final SearchDock dock = place(
        phone,
        found: const Rect.fromLTWH(36, 250, 288, 510),
      );
      expect(dock.compact, isTrue);
      expect(dock.side, SearchDockSide.top);
    });
  });

  group('F-TEXT-11: телефон в альбоме', () {
    test('из коробки панель справа и не шире 40 % экрана', () {
      final SearchDock dock = place(phoneTurned);
      expect(dock.side, SearchDockSide.right);
      expect(dock.extent, closeTo(760 * 0.4, 1e-9));
      expect(dock.beside, isFalse);
      expect(dock.vertical, isTrue);
    });

    test('найденное справа — панель переезжает налево', () {
      final SearchDock dock = place(
        phoneTurned,
        found: const Rect.fromLTWH(520, 150, 120, 20),
      );
      expect(dock.side, SearchDockSide.left);
    });

    test('найденное слева — панель остаётся справа', () {
      final SearchDock dock = place(
        phoneTurned,
        found: const Rect.fromLTWH(60, 150, 120, 20),
      );
      expect(dock.side, SearchDockSide.right);
    });

    test('строка через всю полосу — панель сжимается до строки', () {
      final SearchDock dock = place(
        phoneTurned,
        found: const Rect.fromLTWH(40, 100, 680, 20),
      );
      expect(dock.compact, isTrue);
      expect(dock.side, SearchDockSide.bottom);
      expect(
        dock.rectIn(phoneTurned).overlaps(
          const Rect.fromLTWH(40, 100, 680, 20),
        ),
        isFalse,
      );
    });

    test('поворот экрана выбирает сторону заново', () {
      // Панель стояла наверху в портрете; в альбоме верхнего края у неё
      // нет — она встаёт справа.
      final SearchDock dock = place(phoneTurned, current: SearchDockSide.top);
      expect(dock.side, SearchDockSide.right);
    });
  });

  group('F-TEXT-11: без найденного', () {
    test('прямоугольника нет — панель стоит где стояла', () {
      expect(
        place(phone, current: SearchDockSide.top).side,
        SearchDockSide.top,
      );
      expect(place(phone).side, SearchDockSide.bottom);
      expect(
        place(phoneTurned, current: SearchDockSide.left).side,
        SearchDockSide.left,
      );
    });

    test('пустой прямоугольник — то же, что его отсутствие', () {
      expect(
        place(phone, found: Rect.zero, current: SearchDockSide.top).side,
        SearchDockSide.top,
      );
    });

    test('место меньше экрана — доля считается от места', () {
      // Клавиатура или системная панель отняли у места часть высоты.
      final SearchDock dock = place(phone, area: const Size(360, 500));
      expect(dock.extent, closeTo(200, 1e-9));
    });
  });

  group('F-TEXT-11: строки результатов читаются на любой странице', () {
    // Что может оказаться под полупрозрачной панелью: белая и сепийная
    // бумага, чёрный фон «Инверсии», красный «Ночного красного», серая
    // картинка.
    const Map<String, int> backdrops = <String, int>{
      'белая страница': 0xFFFFFFFF,
      'сепийная страница': 0xFFF4ECD8,
      'тёмная страница': 0xFF000000,
      'ночной красный': 0xFFFF0000,
      'серая картинка': 0xFF808080,
    };

    for (final AppPalette palette in appPalettes.values) {
      test('${palette.title}: основной текст держит 4,5:1', () {
        for (final MapEntry<String, int> backdrop in backdrops.entries) {
          final int seen = blendOver(
            palette.surface,
            kSearchPanelOpacity,
            backdrop.value,
          );
          final double ratio = contrastRatio(palette.text, seen);
          expect(
            ratio,
            greaterThanOrEqualTo(wcagAaNormalText),
            reason:
                'над «${backdrop.key}» выходит '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }

    test('панель в самом деле прозрачна', () {
      expect(kSearchPanelOpacity, lessThan(0.9));
      expect(kSearchPanelOpacity, greaterThan(0.5));
    });

    test('смешение цветов: края и середина', () {
      expect(blendOver(0xFF102030, 1, 0xFFFFFFFF), 0xFF102030);
      expect(blendOver(0xFF102030, 0, 0xFFFFFFFF), 0xFFFFFFFF);
      expect(blendOver(0xFF000000, 0.5, 0xFFFFFFFF), 0xFF808080);
    });
  });
}
