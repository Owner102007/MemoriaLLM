import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/category_style.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

/// Эталонная таблица: посчитана `tool/make_category_goldens.py` — другой
/// реализацией той же математики. Тест, зовущий ту же функцию, сверял бы
/// её с самой собой; здесь сверяются две независимо написанные.
const String _goldenPath = 'test/goldens/category_styles.json';

void main() {
  group('вид категории выводится из названия', () {
    test('одно название — один вид, сколько ни спрашивай', () {
      final CategoryStyle first = categoryStyleFor('Справочники');
      final CategoryStyle second = categoryStyleFor('Справочники');
      expect(first, second);
    });

    test('регистр и лишние пробелы вида не меняют', () {
      final CategoryStyle plain = categoryStyleFor('Учёба');
      expect(categoryStyleFor('учёба'), plain);
      expect(categoryStyleFor('  Учёба  '), plain);
      expect(categoryStyleFor('Учёба\n'), plain);
      // А переименование в другое слово — меняет: полка обязана
      // откликнуться на переименование, иначе непонятно, что произошло.
      expect(categoryStyleFor('Учебники'), isNot(plain));
    });

    test('сдвиг рисунка лежит в своих границах', () {
      for (final String title in <String>['А', 'Проза', 'Ноты', '日本語']) {
        final CategoryStyle style = categoryStyleFor(title);
        expect(style.phase, inInclusiveRange(0.0, 1.0));
        expect(style.hueIndex, inInclusiveRange(0, kCategoryHues - 1));
      }
    });

    test('сто названий расходятся почти по всем сочетаниям', () {
      // Смысл узора — различать категории взглядом. Если хеш выродится и
      // половина названий получит один и тот же вид, узор перестанет
      // работать, а тест на детерминизм этого не заметит.
      final Set<String> combos = <String>{};
      for (int i = 0; i < 100; i++) {
        final CategoryStyle style = categoryStyleFor('Категория $i');
        combos.add('${style.pattern.name}/${style.hueIndex}');
      }
      const int possible = kCategoryHues * 6;
      expect(combos.length, greaterThan(possible ~/ 2));
    });
  });

  group('эталонная таблица совпадает с расчётом', () {
    late List<Map<String, Object?>> golden;

    setUpAll(() {
      final Map<String, Object?> file =
          jsonDecode(File(_goldenPath).readAsStringSync())
              as Map<String, Object?>;
      golden = (file['styles']! as List<Object?>)
          .cast<Map<String, Object?>>();
    });

    test('таблица непустая и покрывает все узоры', () {
      expect(golden.length, greaterThanOrEqualTo(10));
      final Set<Object?> patterns = <Object?>{
        for (final Map<String, Object?> entry in golden) entry['pattern'],
      };
      expect(patterns.length, greaterThanOrEqualTo(4));
    });

    test('узор, оттенок и сдвиг сходятся до последнего разряда', () {
      for (final Map<String, Object?> entry in golden) {
        final String title = entry['title']! as String;
        final CategoryStyle style = categoryStyleFor(title);
        expect(style.seed, entry['seed'], reason: 'хеш «$title»');
        expect(style.pattern.name, entry['pattern'], reason: 'узор «$title»');
        expect(style.hueIndex, entry['hueIndex'], reason: 'оттенок «$title»');
        expect(
          style.phase,
          closeTo((entry['phase']! as num).toDouble(), 1e-9),
          reason: 'сдвиг «$title»',
        );
      }
    });

    test('цвета подложки и узора сходятся на каждой теме', () {
      for (final Map<String, Object?> entry in golden) {
        final String title = entry['title']! as String;
        final CategoryStyle style = categoryStyleFor(title);
        final Map<String, Object?> colours =
            entry['colours']! as Map<String, Object?>;
        for (final AppThemeId id in AppThemeId.values) {
          final Map<String, Object?> expected =
              colours[id.name]! as Map<String, Object?>;
          final AppPalette palette = appPalettes[id]!;
          expect(
            style.backgroundOn(palette),
            expected['background'],
            reason: 'подложка «$title» на теме ${id.name}',
          );
          expect(
            style.inkOn(palette),
            expected['ink'],
            reason: 'узор «$title» на теме ${id.name}',
          );
        }
      }
    });
  });

  group('полка остаётся читаемой', () {
    /// Названия, на которых проверяются все темы разом.
    List<String> titles() => <String>[
      'Без категории',
      'Учёба',
      'Фантастика',
      'Справочники',
      'История',
      'Ноты',
      for (int i = 0; i < 60; i++) 'Категория $i',
    ];

    test('основной текст темы читается на любой подложке', () {
      // Подложка категории окрашивается произвольным оттенком, выведенным
      // из названия. Ни одно название не имеет права сделать полку
      // нечитаемой — это тот же порог WCAG AA, которым проверяются темы.
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final int background = categoryStyleFor(
            title,
          ).backgroundOn(palette);
          expect(
            contrastRatio(palette.text, background),
            greaterThanOrEqualTo(wcagAaNormalText),
            reason: 'текст на подложке «$title», тема ${id.name}',
          );
          expect(
            contrastRatio(palette.textSecondary, background),
            greaterThanOrEqualTo(wcagAaNormalText),
            reason: 'вторичный текст на подложке «$title», тема ${id.name}',
          );
        }
      }
    });

    test('узор остаётся фактурой, а не рябью', () {
      // Слишком заметный узор соревнуется с обложками, слишком бледный не
      // различает категории вовсе. Обе границы закреплены числами: это
      // ровно та величина, которую случайная правка испортит молча.
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final CategoryStyle style = categoryStyleFor(title);
          final double ratio = contrastRatio(
            style.inkOn(palette),
            style.backgroundOn(palette),
          );
          expect(
            ratio,
            inInclusiveRange(1.05, 1.6),
            reason: 'узор «$title» на теме ${id.name}',
          );
        }
      }
    });

    test('подложка отличается от поверхности темы, но не спорит с ней', () {
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        final Set<int> backgrounds = <int>{};
        for (final String title in titles()) {
          backgrounds.add(categoryStyleFor(title).backgroundOn(palette));
        }
        // Категории различимы между собой…
        expect(backgrounds.length, greaterThanOrEqualTo(kCategoryHues - 1));
        // …и при этом ни одна не уходит от темы дальше, чем на полтора
        // раза по контрасту: подложка обязана остаться цветом этой темы.
        for (final int background in backgrounds) {
          expect(
            contrastRatio(background, palette.surface),
            lessThan(1.9),
            reason: 'подложка ушла от поверхности темы ${id.name}',
          );
        }
      }
    });
  });

  group('шаг узора', () {
    test('привязан к блоку, а не к экрану', () {
      expect(patternStepFor(180), closeTo(30, 1e-9));
      expect(patternStepFor(360), closeTo(60, 1e-9));
    });

    test('не вырождается на крошечном блоке', () {
      expect(patternStepFor(0), greaterThanOrEqualTo(12));
      expect(patternStepFor(-5), greaterThanOrEqualTo(12));
    });
  });
}
