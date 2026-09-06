/// Синтетическая страница для тестов выделения, контекста и подсветки.
///
/// Строки задаются координатами, поэтому проверяются правила, а не
/// поведение конкретного PDF. Настоящий движок проверяет корпус.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

class TestLine {
  const TestLine(this.text, {required this.top, this.left = 0.1});

  final String text;
  final double top;
  final double left;
}

const double kCharWidth = 0.02;
const double kLineHeight = 0.02;

/// Собирает слой текста страницы из строк.
///
/// Символы стоят подряд слева направо, строки разделены переводом строки —
/// у него, как и у настоящего движка, своего места на странице нет.
PageTextLayout buildLayout(List<TestLine> lines) {
  final StringBuffer text = StringBuffer();
  final List<TextBox> boxes = <TextBox>[];
  for (int i = 0; i < lines.length; i++) {
    if (i > 0) {
      text.write('\n');
      boxes.add(const TextBox(left: 0, top: 0, right: 0, bottom: 0));
    }
    final TestLine line = lines[i];
    for (int c = 0; c < line.text.length; c++) {
      text.write(line.text[c]);
      final double left = line.left + c * kCharWidth;
      boxes.add(
        TextBox(
          left: left,
          top: line.top,
          right: left + kCharWidth,
          bottom: line.top + kLineHeight,
        ),
      );
    }
  }
  return PageTextLayout(text: text.toString(), boxes: boxes);
}

/// Место первого вхождения слова в тексте страницы.
({int start, int end}) at(PageTextLayout layout, String word) {
  final int start = layout.text.indexOf(word);
  expect(start, isNot(-1), reason: 'слова «$word» нет на странице');
  return (start: start, end: start + word.length);
}
