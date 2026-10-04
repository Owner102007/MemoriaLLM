import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/category_style.dart';
import 'package:memoria/domain/library/shelf_caption.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

/// BUG-14: подпись блока полки читается на любой категории и теме.
void main() {
  /// Названия, на которых проверяются все темы разом.
  List<String> titles() => <String>[
    'Без категории',
    'Учёба',
    'Фантастика',
    for (int i = 0; i < 300; i++) 'Категория $i',
  ];

  group('BUG-14: почему подписи нужна своя подложка', () {
    test('BUG-14: против неоновой линии основной текст не читается', () {
      // Это и есть дефект в числах: подпись лежала на узоре, а у
      // кислотной категории узор — неон. Подложка категории проходит
      // порог с запасом, линия узора — нет.
      for (final AppPalette palette in appPalettes.values) {
        if (!palette.isDark) {
          continue;
        }
        double worst = double.infinity;
        for (final String title in titles()) {
          final CategoryStyle style = categoryStyleFor(title);
          if (!style.acidOn(palette)) {
            continue;
          }
          final double ratio = contrastRatio(
            palette.text,
            style.inkOn(palette),
          );
          if (ratio < worst) {
            worst = ratio;
          }
        }
        expect(
          worst,
          lessThan(wcagAaLargeText),
          reason:
              '${palette.title}: худший контраст текста к неону — '
              '${worst.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('BUG-14: подпись на своей подложке читается везде', () {
    for (final AppPalette palette in appPalettes.values) {
      test('BUG-14: ${palette.title} — не ниже 4,5:1', () {
        final ({int background, int text}) colors = shelfCaptionColors(palette);
        final double ratio = contrastRatio(colors.text, colors.background);
        expect(
          ratio,
          greaterThanOrEqualTo(wcagAaNormalText),
          reason: 'подпись даёт ${ratio.toStringAsFixed(2)}:1',
        );
        // Подложка непрозрачная: под ней узор, а он бывает любым.
        expect(colors.background >> 24, 0xFF);
      });
    }

    test('BUG-14: цвет подписи не зависит от названия категории', () {
      // Оттенок категории к подложке подписи не подмешивается: иначе
      // читаемость снова зависела бы от того, как категорию назвали.
      for (final AppPalette palette in appPalettes.values) {
        final ({int background, int text}) colors = shelfCaptionColors(palette);
        expect(colors.background, palette.surface);
        expect(colors.text, palette.text);
      }
    });

    test('BUG-14: подложка не отняла места у обложки', () {
      // Прежняя подпись занимала 6 точек отступа и 30 точек текста.
      expect(kShelfCaptionExtent, 36);
    });
  });
}
