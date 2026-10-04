import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/search_dock.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

/// F-TEXT-11, F-TEXT-12, ALG-UI-31: где стоит панель поиска.
///
/// Панель остаётся на экране после выбора результата. На широком окне
/// она стоит рядом со страницей; на узком экране — полупрозрачной
/// полосой всегда у нижнего края (F-TEXT-12, замечание владельца
/// 04.10.2026). Правило — чистый счёт, и проверяется числами: широкое
/// окно, телефон в портрете и в альбоме, клавиатура, ввод и просмотр.
void main() {
  const Size phone = Size(360, 760);
  const Size phoneTurned = Size(760, 360);
  const Size desktop = Size(1280, 800);

  SearchDock place(
    Size screen, {
    Size? area,
    double keyboard = 0,
    bool typing = false,
  }) {
    return placeSearchPanel(
      screen: screen,
      area: area ?? screen,
      keyboard: keyboard,
      typing: typing,
    );
  }

  group('F-TEXT-11: широкое окно', () {
    test('панель стоит справа, рядом со страницей', () {
      final SearchDock dock = place(desktop);
      expect(dock.side, SearchDockSide.right);
      expect(dock.extent, kSearchPanelWidth);
      expect(dock.beside, isTrue);
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

    test('ввод и просмотр панель не двигают', () {
      expect(place(desktop, typing: true), place(desktop));
    });

    test('граница широкого окна — 900 точек', () {
      expect(isSearchWide(const Size(900, 600)), isTrue);
      expect(isSearchWide(const Size(899, 600)), isFalse);
      expect(place(const Size(900, 600)).beside, isTrue);
      expect(place(const Size(899, 600)).beside, isFalse);
    });

    test('клавиатура поднимает панель, а ширины у листа не отнимает', () {
      final SearchDock dock = place(desktop, keyboard: 300);
      expect(dock.taken, kSearchPanelWidth);
      expect(dock.lift, 300);
      expect(dock.rectIn(desktop).bottom, 500);
    });
  });

  group('F-TEXT-12: узкий экран — полоса всегда снизу', () {
    test('портрет: у нижнего края, не выше 40 % экрана', () {
      final SearchDock dock = place(phone);
      expect(dock.side, SearchDockSide.bottom);
      expect(dock.extent, closeTo(760 * 0.4, 1e-9));
      expect(dock.beside, isFalse, reason: 'лежит поверх страницы');
      expect(dock.taken, 0, reason: 'лист под ней не перекладывается');
      expect(dock.rectIn(phone).bottom, 760);
      expect(dock.rectIn(phone).width, 360);
    });

    test('альбом: тоже у нижнего края, а не сбоку', () {
      final SearchDock dock = place(phoneTurned);
      expect(dock.side, SearchDockSide.bottom);
      expect(dock.extent, closeTo(360 * 0.4, 1e-9));
      expect(dock.rectIn(phoneTurned).bottom, 360);
      expect(dock.rectIn(phoneTurned).width, 760);
    });

    test('нижний край — на сетке размеров экрана, при вводе и просмотре', () {
      for (double width = 240; width < kSearchWideWindow; width += 60) {
        for (double height = 240; height <= 1200; height += 80) {
          for (final bool typing in <bool>[false, true]) {
            final Size screen = Size(width, height);
            final SearchDock dock = place(screen, typing: typing);
            final Rect rect = dock.rectIn(screen);
            final String where = '$width×$height, ввод: $typing';
            expect(dock.side, SearchDockSide.bottom, reason: where);
            expect(dock.beside, isFalse, reason: where);
            expect(rect.bottom, height, reason: where);
            expect(rect.left, 0, reason: where);
            expect(rect.width, width, reason: where);
            expect(rect.top, greaterThanOrEqualTo(0), reason: where);
          }
        }
      }
    });

    test('место меньше экрана — доля считается от места', () {
      // Системная панель отняла у места часть высоты.
      final SearchDock dock = place(phone, area: const Size(360, 500));
      expect(dock.extent, closeTo(200, 1e-9));
    });

    test('без клавиатуры ввод и просмотр — одно и то же место', () {
      // Найденное правилу не подаётся вовсе: двигать полосу или менять
      // её размер ему нечем. А пока клавиатуры нет, не меняет его и
      // переход от ввода к просмотру.
      expect(place(phone, typing: true), place(phone));
      expect(place(phoneTurned, typing: true).side, SearchDockSide.bottom);
    });
  });

  group('F-TEXT-12: клавиатура', () {
    test('полоса стоит над клавиатурой', () {
      final SearchDock dock = place(phone, keyboard: 300, typing: true);
      expect(dock.lift, 300);
      expect(dock.rectIn(phone).bottom, 460, reason: 'верх клавиатуры');
      expect(dock.taken, 0, reason: 'лист под клавиатурой не перекладывается');
    });

    test('доля считается от места над клавиатурой', () {
      final SearchDock dock = place(phone, keyboard: 300);
      expect(dock.extent, closeTo(460 * 0.4, 1e-9));
    });

    test('при вводе полосе хватает места на строку списка', () {
      // 40 % от 360 точек над клавиатурой — 144: на поле, строку счёта и
      // строку списка этого мало.
      final SearchDock dock = place(phone, keyboard: 400, typing: true);
      expect(dock.extent, kSearchTypingExtent);
      // При просмотре поля нет — и доля прежняя.
      expect(place(phone, keyboard: 400).extent, closeTo(144, 1e-9));
    });

    test('полоса не выше места над клавиатурой', () {
      // Телефон на боку: над клавиатурой осталось 140 точек.
      final SearchDock dock = place(phoneTurned, keyboard: 220, typing: true);
      expect(dock.extent, 140);
      expect(dock.rectIn(phoneTurned).top, 0);
      expect(dock.rectIn(phoneTurned).bottom, 140);
    });

    test('клавиатура выше места — полосы нет, а счёт не ломается', () {
      final SearchDock dock = place(phoneTurned, keyboard: 500, typing: true);
      expect(dock.lift, 360);
      expect(dock.extent, 0);
    });

    test('тесная полоса — та, где поле и счёт вместе не помещаются', () {
      // Поле, строка счёта и разделитель — около 110 точек; при вводе
      // полосе положено не меньше места под них и одну строку списка.
      expect(kSearchCrampedExtent, greaterThan(kSearchCounterExtent * 2));
      expect(kSearchCrampedExtent, lessThan(kSearchTypingExtent));
    });

    test('отрицательная высота клавиатуры — её нет', () {
      expect(place(phone, keyboard: -10), place(phone));
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
