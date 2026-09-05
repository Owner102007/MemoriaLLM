import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/columns.dart';
import 'package:memoria/domain/reading/context_paragraph.dart';
import 'package:memoria/domain/reading/page_rows.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/page_text.dart';

/// Абзац вокруг выделения: чистая математика над текстом и координатами.
///
/// Страницы здесь собираются из строк с заданными координатами, поэтому
/// проверяется именно правило поиска границ абзаца, а не поведение
/// конкретного PDF. Корпус проверяет другое — что настоящий движок отдаёт
/// координаты, с которыми это правило работает.
void main() {
  group('одноколоночная страница', () {
    // Два абзаца: первый кончается недописанной строкой, второй начинается
    // с красной строки — ровно так это и видит глаз.
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('первая строка первого абзаца длинная', top: 0.10),
      const TestLine('вторая строка первого абзаца тоже', top: 0.13),
      const TestLine('конец.', top: 0.16),
      const TestLine('новый абзац с красной строки идёт', top: 0.19, left: 0.13),
      const TestLine('и продолжается вот такой строкой', top: 0.22),
    ]);

    test('абзац берётся целиком и не захватывает соседний', () {
      final ({int start, int end}) word = at(page, 'вторая');
      final ParagraphContext? context = paragraphAround(
        layout: page,
        selectionStart: word.start,
        selectionEnd: word.end,
      );
      expect(context, isNotNull);
      expect(context!.text, startsWith('первая строка'));
      expect(context.text, endsWith('конец.'));
      expect(context.text, isNot(contains('новый абзац')));
    });

    test('выделение находится внутри абзаца по своему месту', () {
      final ({int start, int end}) word = at(page, 'вторая');
      final ParagraphContext context = paragraphAround(
        layout: page,
        selectionStart: word.start,
        selectionEnd: word.end,
      )!;
      expect(context.selection, 'вторая');
    });

    test('выделение во втором абзаце не тащит за собой первый', () {
      final ({int start, int end}) word = at(page, 'продолжается');
      final ParagraphContext context = paragraphAround(
        layout: page,
        selectionStart: word.start,
        selectionEnd: word.end,
      )!;
      expect(context.text, startsWith('новый абзац'));
      expect(context.text, isNot(contains('первая строка')));
    });

    test('строки склеиваются пробелом, а не переводом строки', () {
      final ({int start, int end}) word = at(page, 'вторая');
      final ParagraphContext context = paragraphAround(
        layout: page,
        selectionStart: word.start,
        selectionEnd: word.end,
      )!;
      expect(context.text, isNot(contains('\n')));
      expect(context.text, contains('длинная вторая'));
    });
  });

  test('пустая пустота между абзацами тоже граница', () {
    // Здесь ни красной строки, ни короткой последней строки нет — есть
    // только пустая полоса между абзацами. Её одной должно хватать.
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('строка первого абзаца ровно такая', top: 0.10),
      const TestLine('вторая строка первого абзаца тоже', top: 0.13),
      const TestLine('первая строка второго абзаца идёт', top: 0.22),
      const TestLine('вторая строка второго абзаца тоже', top: 0.25),
    ]);
    final ({int start, int end}) word = at(page, 'второго');
    final ParagraphContext context = paragraphAround(
      layout: page,
      selectionStart: word.start,
      selectionEnd: word.end,
    )!;
    expect(context.text, isNot(contains('первого абзаца')));
  });

  test('перенос через дефис склеивает слово обратно', () {
    // Слово, разрезанное концом строки, обязано приехать в модель целым:
    // «пре-» и «красный» двумя обрубками ей ничего не говорят.
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('это было совершенно пре-', top: 0.10),
      const TestLine('красное утро в середине лета', top: 0.13),
    ]);
    final ({int start, int end}) word = at(page, 'утро');
    final ParagraphContext context = paragraphAround(
      layout: page,
      selectionStart: word.start,
      selectionEnd: word.end,
    )!;
    expect(context.text, contains('прекрасное'));
    expect(context.text, isNot(contains('пре-')));
  });

  test('дефис перед заглавной буквой не склеивается', () {
    // «Иванов-» и «Петров» на границе строк — это почти всегда список, а
    // не одно слово.
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('в списке значились Иванов-', top: 0.10),
      const TestLine('Петров и другие фамилии тут', top: 0.13),
    ]);
    final ({int start, int end}) word = at(page, 'фамилии');
    final ParagraphContext context = paragraphAround(
      layout: page,
      selectionStart: word.start,
      selectionEnd: word.end,
    )!;
    expect(context.text, contains('Иванов- Петров'));
  });

  group('двухколоночная страница', () {
    // Левая колонка кончается внизу, правая начинается вверху: продолжение
    // текста лежит там, а вовсе не справа на той же высоте.
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('левая строка одна', top: 0.60),
      const TestLine('левая строка два', top: 0.63),
      const TestLine('правая строка одна', top: 0.10, left: 0.52),
      const TestLine('правая строка два', top: 0.13, left: 0.52),
    ]);
    const List<ColumnBand> columns = <ColumnBand>[
      ColumnBand(left: 0.05, right: 0.45),
      ColumnBand(left: 0.5, right: 0.95),
    ];

    test('контекст идёт в порядке чтения, а не по горизонтали', () {
      final ({int start, int end}) word = at(page, 'левая строка два');
      final ParagraphContext context = paragraphAround(
        layout: page,
        selectionStart: word.start,
        selectionEnd: word.end,
        columns: columns,
      )!;
      // Продолжение — верх правой колонки: это одна и та же мысль.
      expect(context.text, contains('правая строка одна'));
      // А сама подсветка при этом начинается там, где начинался абзац.
      expect(context.text, startsWith('левая строка одна'));
    });

    test('строки колонок не сливаются в одну', () {
      final List<TextRow> rows = pageRows(page, columns: columns);
      expect(rows, hasLength(4));
      expect(rows.first.column, 0);
      expect(rows.last.column, 1);
    });
  });

  test('без геометрии контекст всё равно есть', () {
    // Испорченный текстовый слой: текст пришёл, а мест у символов нет.
    // Половина контекста лучше, чем ничего.
    const PageTextLayout page = PageTextLayout(
      text: 'мир полон вещей, которые надо объяснить',
      boxes: <TextBox>[],
    );
    final ParagraphContext context = paragraphAround(
      layout: page,
      selectionStart: 10,
      selectionEnd: 16,
    )!;
    expect(context.text, contains('объяснить'));
    expect(context.selection, page.text.substring(10, 16));
  });

  test('длинный абзац режется вокруг выделения, а не с начала', () {
    final PageTextLayout page = buildLayout(<TestLine>[
      for (int i = 0; i < 40; i++)
        TestLine('строка номер $i со словами', top: 0.02 + i * 0.021),
    ]);
    final ({int start, int end}) word = at(page, 'номер 30');
    final ParagraphContext context = paragraphAround(
      layout: page,
      selectionStart: word.start,
      selectionEnd: word.end,
      maxChars: 200,
    )!;
    expect(context.text.length, lessThanOrEqualTo(220));
    expect(context.selection, 'номер 30');
  });

  test('пустое выделение контекста не даёт', () {
    final PageTextLayout page = buildLayout(<TestLine>[
      const TestLine('одна строка на странице', top: 0.1),
    ]);
    expect(
      paragraphAround(layout: page, selectionStart: 3, selectionEnd: 3),
      isNull,
    );
    expect(
      paragraphAround(layout: page, selectionStart: 0, selectionEnd: 9999),
      isNull,
    );
  });
}
