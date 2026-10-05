import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/annotations/markdown_export.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/domain/reading/context_paragraph.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_geometry.dart';
import 'package:memoria/domain/reading/text_search.dart';

/// BUG-51: знак переноса не уходит из книги вместе с текстом.
///
/// Дефис в конце строки, за которым слово продолжается, движок отдаёт
/// служебным знаком U+0002 без перевода строки (закреплено на настоящем
/// движке файлом `hyphen_breaks.pdf` корпуса). Поиск читает его двояко
/// (BUG-50), а всё, что уходит из книги, — цитата, буфер обмена, запрос
/// к модели, выгрузка — обязано уйти без него.
void main() {
  final String mark = String.fromCharCode(kLineBreakHyphen);

  /// Страница, как её отдаёт движок: слово разрезано знаком, перевода
  /// строки после знака нет, а продолжение слова лежит строкой ниже.
  PageTextLayout brokenPage() {
    const double width = 0.02;
    const double height = 0.02;
    final List<String> lines = <String>[
      'в этой главе описан микро$mark',
      'скоп и его устройство',
    ];
    final StringBuffer text = StringBuffer();
    final List<TextBox> boxes = <TextBox>[];
    for (int i = 0; i < lines.length; i++) {
      final double top = 0.10 + i * 0.03;
      for (int c = 0; c < lines[i].length; c++) {
        text.write(lines[i][c]);
        final double left = 0.1 + c * width;
        boxes.add(
          TextBox(
            left: left,
            top: top,
            right: left + width,
            bottom: top + height,
          ),
        );
      }
    }
    return PageTextLayout(text: text.toString(), boxes: boxes);
  }

  test('BUG-51: готовый запрос к модели не несёт знака переноса', () {
    final String filled = fillPrompt(
      'Объясни «{{выделение}}».\nОтрывок: {{контекст}}',
      selection: 'остео${mark}логия',
      context: 'Наука остео${mark}логия изучает кости.',
    );
    expect(filled, isNot(contains(mark)));
    expect(filled, contains('«остеология»'));
    expect(filled, contains('Наука остеология изучает кости.'));
  });

  test('BUG-51: выгрузка цитат не несёт знака переноса', () {
    final String markdown = annotationsToMarkdown(
      bookTitle: 'Анатомия',
      quotes: <Quote>[
        Quote(
          id: 'q-1',
          bookId: 'book-1',
          page: 3,
          content: 'остео${mark}логия изучает кости',
          createdAt: DateTime.utc(2026, 10, 5),
        ),
      ],
      notes: const <Note>[],
    );
    expect(markdown, isNot(contains(mark)));
    expect(markdown, contains('> остеология изучает кости'));
  });

  test('BUG-51: абзац-контекст не рвёт слово с переноса пробелом', () {
    final PageTextLayout page = brokenPage();
    final int start = page.text.indexOf('устройство');
    final ParagraphContext? context = paragraphAround(
      layout: page,
      selectionStart: start,
      selectionEnd: start + 'устройство'.length,
    );
    expect(context, isNotNull);
    // Слово, разрезанное концом строки, в абзаце обязано остаться
    // одним словом: между его половинами нет ни пробела, ни дефиса.
    expect(context!.text.replaceAll(mark, ''), contains('описан микроскоп и'));
  });
}
