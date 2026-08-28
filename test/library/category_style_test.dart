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

/// Потолок громкости участка, выбранный владельцем (28.08.2026).
///
/// Кислотная категория обязана быть заметной, но не обязана перекрикивать
/// обложки: вес участка — средний цвет подложки под узором — не уходит от
/// самой подложки дальше чем втрое по контрасту.
const double _weightCap = 3.0;

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

    test('триста названий расходятся по сотням сочетаний', () {
      // Смысл узора — различать категории взглядом. Если хеш выродится и
      // половина названий получит один и тот же вид, узор перестанет
      // работать, а тест на детерминизм этого не заметит.
      final Set<String> combos = <String>{};
      for (int i = 0; i < 300; i++) {
        final CategoryStyle style = categoryStyleFor('Категория $i');
        combos.add('${style.pattern.name}/${style.hueIndex}');
      }
      // 288 сочетаний на 300 названий: при честном разбросе занятыми
      // окажутся около двух третей. Половина — уже вырождение.
      expect(combos.length, greaterThan(150));
    });

    test('каждый узор кому-нибудь достаётся', () {
      // Узор, который не выпадает никогда, — мёртвый код в художнике.
      final Set<ShelfPattern> seen = <ShelfPattern>{};
      for (int i = 0; i < 600; i++) {
        seen.add(categoryStyleFor('Категория $i').pattern);
      }
      expect(seen.length, ShelfPattern.values.length);
    });
  });

  group('кислота встречается редко', () {
    test('примерно одна категория из семи', () {
      // Решение владельца: яркие цвета — в малом количестве. Если доля
      // уползёт к трети, полка перестанет быть тёмной, и заметить это
      // без числа невозможно.
      int acid = 0;
      const int total = 1400;
      for (int i = 0; i < total; i++) {
        if (categoryStyleFor('Категория $i').acid) {
          acid++;
        }
      }
      expect(acid / total, inInclusiveRange(0.10, 0.19));
    });

    test('на светлых темах кислота приглушается', () {
      // Неон на бумажном фоне читается как маркер, а не как свечение
      // (решение владельца, 28.08.2026).
      final CategoryStyle acid = _anyAcidStyle();
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        expect(acid.acidOn(palette), palette.isDark, reason: id.name);
      }
    });

    test('спокойная категория не светится нигде', () {
      final CategoryStyle calm = _anyCalmStyle();
      for (final AppThemeId id in AppThemeId.values) {
        expect(calm.acidOn(appPalettes[id]!), isFalse, reason: id.name);
      }
    });
  });

  group('эталонная таблица совпадает с расчётом', () {
    late List<Map<String, Object?>> golden;

    setUpAll(() {
      final Map<String, Object?> file =
          jsonDecode(File(_goldenPath).readAsStringSync())
              as Map<String, Object?>;
      golden = (file['styles']! as List<Object?>).cast<Map<String, Object?>>();
    });

    test('таблица непустая и покрывает большинство узоров', () {
      expect(golden.length, greaterThanOrEqualTo(30));
      final Set<Object?> patterns = <Object?>{
        for (final Map<String, Object?> entry in golden) entry['pattern'],
      };
      expect(patterns.length, greaterThanOrEqualTo(10));
      // И хотя бы одна кислотная запись: иначе весь неон остался бы
      // непроверенным вторым расчётом.
      expect(
        golden.where((Map<String, Object?> e) => e['acid'] == true),
        isNotEmpty,
      );
    });

    test('узор, оттенок, сдвиг и кислота сходятся до последнего разряда', () {
      for (final Map<String, Object?> entry in golden) {
        final String title = entry['title']! as String;
        final CategoryStyle style = categoryStyleFor(title);
        expect(style.seed, entry['seed'], reason: 'хеш «$title»');
        expect(style.pattern.name, entry['pattern'], reason: 'узор «$title»');
        expect(style.hueIndex, entry['hueIndex'], reason: 'оттенок «$title»');
        expect(style.acid, entry['acid'], reason: 'кислота «$title»');
        expect(
          style.phase,
          closeTo((entry['phase']! as num).toDouble(), 1e-9),
          reason: 'сдвиг «$title»',
        );
      }
    });

    test('подложка, узор и вес сходятся на каждой теме', () {
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
          expect(
            style.weightOn(palette),
            expected['weight'],
            reason: 'вес «$title» на теме ${id.name}',
          );
          expect(
            style.acidOn(palette),
            expected['acid'],
            reason: 'свечение «$title» на теме ${id.name}',
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
      for (int i = 0; i < 300; i++) 'Категория $i',
    ];

    test('основной текст темы читается на любой подложке', () {
      // Подложка категории окрашивается произвольным оттенком, выведенным
      // из названия. Ни одно название не имеет права сделать полку
      // нечитаемой — это тот же порог WCAG AA, которым проверяются темы.
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final int background = categoryStyleFor(title).backgroundOn(palette);
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

    test('спокойный узор остаётся фактурой, а не рябью', () {
      // Слишком заметный узор соревнуется с обложками, слишком бледный не
      // различает категории вовсе. Обе границы закреплены числами: это
      // ровно та величина, которую случайная правка испортит молча.
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final CategoryStyle style = categoryStyleFor(title);
          if (style.acidOn(palette)) {
            continue;
          }
          expect(
            contrastRatio(style.inkOn(palette), style.backgroundOn(palette)),
            inInclusiveRange(1.05, 1.6),
            reason: 'узор «$title» на теме ${id.name}',
          );
        }
      }
    });

    test('кислотный узор — настоящий неон, а не притушенный цвет', () {
      // Смысл кислоты в том, что она светится. Если однажды неон уползёт
      // в границы фактуры, отличить кислотную категорию от спокойной
      // станет нельзя — а тест на вес участка этого не заметит: он
      // проверяет обратное, чтобы неон не кричал.
      bool checked = false;
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final CategoryStyle style = categoryStyleFor(title);
          if (!style.acidOn(palette)) {
            continue;
          }
          checked = true;
          expect(
            contrastRatio(style.inkOn(palette), style.backgroundOn(palette)),
            greaterThan(2.0),
            reason: 'неон «$title» на теме ${id.name}',
          );
        }
      }
      expect(checked, isTrue, reason: 'кислотных категорий не нашлось вовсе');
    });

    test('ни одна категория не кричит громче потолка', () {
      // Кислотный узор светится в полную силу, но рисуется тонкой линией:
      // громкость участка держится не цветом, а тем, сколько его. Здесь и
      // проверяется потолок, выбранный владельцем.
      for (final AppThemeId id in AppThemeId.values) {
        final AppPalette palette = appPalettes[id]!;
        for (final String title in titles()) {
          final CategoryStyle style = categoryStyleFor(title);
          expect(
            categoryWeightContrast(style, palette),
            lessThanOrEqualTo(_weightCap),
            reason: 'вес «$title» на теме ${id.name}',
          );
        }
      }
    });

    test('кислотная категория заметнее спокойной', () {
      // Иначе весь смысл кислоты пропадает: она обязана выделяться на
      // полке, а не просто иначе называться внутри кода.
      final AppPalette dark = appPalettes[AppThemeId.darkRed]!;
      final double acid = categoryWeightContrast(_anyAcidStyle(), dark);
      final double calm = categoryWeightContrast(_anyCalmStyle(), dark);
      expect(acid, greaterThan(calm));
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

  group('шаг и толщина узора', () {
    test('шаг привязан к блоку, а не к экрану', () {
      expect(patternStepFor(180), closeTo(30, 1e-9));
      expect(patternStepFor(360), closeTo(60, 1e-9));
    });

    test('шаг не вырождается на крошечном блоке', () {
      expect(patternStepFor(0), greaterThanOrEqualTo(12));
      expect(patternStepFor(-5), greaterThanOrEqualTo(12));
    });

    test('кислотная линия тоньше спокойной', () {
      // На этом и держится потолок громкости: неон светит в полную силу,
      // но занимает меньше места.
      final AppPalette dark = appPalettes[AppThemeId.darkRed]!;
      expect(
        _anyAcidStyle().strokeOn(dark, 60),
        lessThan(_anyCalmStyle().strokeOn(dark, 60)),
      );
    });

    test('линия никогда не тоньше точки', () {
      final AppPalette dark = appPalettes[AppThemeId.darkRed]!;
      expect(_anyAcidStyle().strokeOn(dark, 1), greaterThanOrEqualTo(1.0));
      expect(_anyCalmStyle().strokeOn(dark, 0), greaterThanOrEqualTo(1.0));
    });
  });
}

/// Первая попавшаяся кислотная категория — их примерно одна из семи.
CategoryStyle _anyAcidStyle() => _firstWhere((CategoryStyle s) => s.acid);

/// Первая попавшаяся спокойная категория.
CategoryStyle _anyCalmStyle() => _firstWhere((CategoryStyle s) => !s.acid);

CategoryStyle _firstWhere(bool Function(CategoryStyle) test) {
  for (int i = 0; i < 500; i++) {
    final CategoryStyle style = categoryStyleFor('Категория $i');
    if (test(style)) {
      return style;
    }
  }
  throw StateError('подходящей категории не нашлось за 500 названий');
}
