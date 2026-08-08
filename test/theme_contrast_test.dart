import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

/// Тёмно-красные схемы очень легко сделать красивыми и нечитаемыми,
/// поэтому контраст каждой темы проверяется автоматически.
void main() {
  group('расчёт контраста', () {
    test('чёрный против белого даёт максимум 21:1', () {
      expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21.0, 0.01));
    });

    test('одинаковые цвета дают 1:1', () {
      expect(contrastRatio(0xFF7F7F7F, 0xFF7F7F7F), closeTo(1.0, 0.001));
    });

    test('порядок цветов не влияет на результат', () {
      expect(
        contrastRatio(0xFFA32F35, 0xFF0E0708),
        closeTo(contrastRatio(0xFF0E0708, 0xFFA32F35), 0.0001),
      );
    });

    test('яркость белого равна единице, чёрного — нулю', () {
      expect(relativeLuminance(0xFFFFFFFF), closeTo(1.0, 0.0001));
      expect(relativeLuminance(0xFF000000), closeTo(0.0, 0.0001));
    });
  });

  group('читаемость тем', () {
    test('в приложении есть все объявленные темы', () {
      expect(appPalettes.length, AppThemeId.values.length);
      for (final AppThemeId id in AppThemeId.values) {
        expect(appPalettes[id], isNotNull, reason: 'нет палитры для $id');
        expect(
          appPalettes[id]!.id,
          id,
          reason: 'палитра $id лежит не на месте',
        );
      }
    });

    test('тема по умолчанию — тёмно-красная', () {
      expect(defaultThemeId, AppThemeId.darkRed);
    });

    for (final AppPalette palette in appPalettes.values) {
      group(palette.title, () {
        void checkText(String what, int foreground, String on, int background) {
          final double ratio = contrastRatio(foreground, background);
          expect(
            ratio,
            greaterThanOrEqualTo(wcagAaNormalText),
            reason:
                '$what на фоне «$on» даёт ${ratio.toStringAsFixed(2)}:1, '
                'нужно не ниже $wcagAaNormalText:1',
          );
        }

        test('основной текст читается на фоне и на поверхности', () {
          checkText('основной текст', palette.text, 'фон', palette.background);
          checkText(
            'основной текст',
            palette.text,
            'поверхность',
            palette.surface,
          );
        });

        test('вторичный текст читается на фоне и на поверхности', () {
          checkText(
            'вторичный текст',
            palette.textSecondary,
            'фон',
            palette.background,
          );
          checkText(
            'вторичный текст',
            palette.textSecondary,
            'поверхность',
            palette.surface,
          );
        });

        test('акцентный текст читается', () {
          checkText(
            'акцентный текст',
            palette.accentText,
            'фон',
            palette.background,
          );
          checkText(
            'акцентный текст',
            palette.accentText,
            'поверхность',
            palette.surface,
          );
        });

        test('подпись на акцентной заливке читается', () {
          checkText(
            'текст на акценте',
            palette.onAccent,
            'акцент',
            palette.accent,
          );
        });

        test('нажатый акцент виден на фоне', () {
          final double ratio = contrastRatio(
            palette.accentPressed,
            palette.background,
          );
          expect(
            ratio,
            greaterThanOrEqualTo(wcagAaLargeText),
            reason: 'нажатое состояние даёт ${ratio.toStringAsFixed(2)}:1',
          );
        });

        test('разделитель не сливается с фоном', () {
          expect(palette.divider, isNot(palette.background));
          expect(
            contrastRatio(palette.divider, palette.background),
            greaterThanOrEqualTo(1.1),
          );
        });

        test('цвета непрозрачные', () {
          final List<int> colors = <int>[
            palette.background,
            palette.surface,
            palette.divider,
            palette.accent,
            palette.accentPressed,
            palette.onAccent,
            palette.accentText,
            palette.text,
            palette.textSecondary,
          ];
          for (final int color in colors) {
            expect(
              (color >> 24) & 0xFF,
              0xFF,
              reason: 'цвет 0x${color.toRadixString(16)} полупрозрачный',
            );
          }
        });
      });
    }
  });
}
