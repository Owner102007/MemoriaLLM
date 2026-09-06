import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_geometry.dart';
import 'package:memoria/domain/reading/text_highlight.dart';

import '../support/page_text.dart';

/// Перевод «кусок текста → прямоугольники на странице».
///
/// На этой математике держатся двое: подсветка найденного (долг S3) и
/// панель действий, которой надо знать, где стоит выделение. Обратный
/// перевод — «точка на странице → место в тексте» — ушёл вместе со слоем
/// выделения в S6.2: диапазон теперь ведёт сам просмотрщик.
void main() {
  final PageTextLayout page = buildLayout(<TestLine>[
    const TestLine('первая строка страницы', top: 0.10),
    const TestLine('вторая строка страницы', top: 0.14),
  ]);

  group('прямоугольники подсветки', () {
    test('на каждую строку — один прямоугольник, а не на каждую букву', () {
      final ({int start, int end}) word = at(page, 'строка страницы\nвторая');
      final List<TextBox> rects = highlightRects(
        layout: page,
        start: word.start,
        end: word.end,
      );
      expect(rects, hasLength(2));
    });

    test('прямоугольник тянется на всю высоту строки', () {
      final ({int start, int end}) word = at(page, 'первая');
      final TextBox rect = highlightRects(
        layout: page,
        start: word.start,
        end: word.end,
      ).single;
      expect(rect.top, closeTo(0.10, 1e-9));
      expect(rect.bottom, closeTo(0.10 + kLineHeight, 1e-9));
      // Ширина — ровно по буквам слова, а не по всей строке.
      expect(rect.left, closeTo(0.10, 1e-9));
      expect(rect.right, closeTo(0.10 + 6 * kCharWidth, 1e-9));
    });

    test('пустой кусок ничего не подсвечивает', () {
      expect(highlightRects(layout: page, start: 5, end: 5), isEmpty);
      expect(
        highlightRects(
          layout: const PageTextLayout(text: 'нет мест', boxes: <TextBox>[]),
          start: 0,
          end: 3,
        ),
        isEmpty,
      );
    });

    test('подсветка не выходит за пределы страницы', () {
      final List<TextBox> rects = highlightRects(
        layout: page,
        start: 0,
        end: 10000,
      );
      expect(rects, isNotEmpty);
      for (final TextBox rect in rects) {
        expect(rect.isValid, isTrue);
      }
    });
  });

  group('слово вокруг места', () {
    test('палец в середине слова берёт слово целиком', () {
      const String text = 'мир полон вещей';
      final ({int start, int end})? word = wordAround(text, 5);
      expect(text.substring(word!.start, word.end), 'полон');
    });

    test('палец в пробел берёт слово слева', () {
      const String text = 'мир полон вещей';
      final ({int start, int end})? word = wordAround(text, 3);
      expect(text.substring(word!.start, word.end), 'мир');
    });

    test('дефис внутри слова слово не разрезает', () {
      const String text = 'сделал по-моему и ушёл';
      final ({int start, int end})? word = wordAround(text, 10);
      expect(text.substring(word!.start, word.end), 'по-моему');
    });

    test('строка из одних знаков препинания слова не даёт', () {
      expect(wordAround('— … —', 2), isNull);
      expect(wordAround('', 0), isNull);
    });

    test('иероглиф считается словом', () {
      const String text = '这是 书';
      final ({int start, int end})? word = wordAround(text, 0);
      expect(text.substring(word!.start, word.end), '这是');
    });
  });
}
