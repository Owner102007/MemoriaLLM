import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/columns.dart';
import 'package:memoria/domain/reading/crop.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';

List<TextBox> _twoColumns({int lines = 20}) {
  return <TextBox>[
    ...textBlock(
      left: 0.08,
      top: 0.1,
      right: 0.46,
      bottom: 0.9,
      lines: lines,
      charsPerLine: 15,
    ),
    ...textBlock(
      left: 0.54,
      top: 0.1,
      right: 0.92,
      bottom: 0.9,
      lines: lines,
      charsPerLine: 15,
    ),
  ];
}

void main() {
  test('двухколоночная страница делится по колонкам', () {
    final List<TextBox> boxes = _twoColumns();
    final CropBox content = contentBoxFromTextBoxes(boxes);
    final List<ColumnBand> bands = detectColumns(boxes, content);

    expect(bands.length, 2);
    expect(bands.first.left, closeTo(content.left, 0.001));
    expect(bands.first.right, lessThan(0.5));
    expect(bands.last.left, greaterThan(0.5));
    expect(bands.last.right, closeTo(content.right, 0.001));
    // Между колонками остаётся просвет — иначе это одна колонка.
    expect(bands.last.left - bands.first.right, greaterThan(0.05));
  });

  test('сплошной текст остаётся одной колонкой', () {
    final List<TextBox> boxes = textBlock(
      left: 0.1,
      top: 0.1,
      right: 0.9,
      bottom: 0.9,
      lines: 25,
      charsPerLine: 40,
    );
    final CropBox content = contentBoxFromTextBoxes(boxes);
    final List<ColumnBand> bands = detectColumns(boxes, content);

    expect(bands.length, 1);
    expect(bands.single.left, closeTo(content.left, 0.001));
    expect(bands.single.right, closeTo(content.right, 0.001));
  });

  test('титульный лист в три строки на колонки не разбирается', () {
    // Короткая страница даёт случайные просветы: между словами заголовка
    // их сколько угодно, и любой из них сошёл бы за межколоночное поле.
    final List<TextBox> boxes = <TextBox>[
      ...textBlock(
        left: 0.1,
        top: 0.3,
        right: 0.4,
        bottom: 0.4,
        lines: 2,
        charsPerLine: 6,
      ),
      ...textBlock(
        left: 0.6,
        top: 0.3,
        right: 0.9,
        bottom: 0.4,
        lines: 2,
        charsPerLine: 6,
      ),
    ];
    final CropBox content = contentBoxFromTextBoxes(boxes);
    expect(detectColumns(boxes, content).length, 1);
  });

  test('просвет у самого края колонкой не считается', () {
    // Ровный левый столбец из инициалов даёт пустую полосу сразу за
    // собой; делить по ней страницу нельзя — это не колонка, а отступ.
    final List<TextBox> boxes = <TextBox>[
      ...textBlock(
        left: 0.06,
        top: 0.1,
        right: 0.1,
        bottom: 0.9,
        lines: 20,
        charsPerLine: 1,
      ),
      ...textBlock(
        left: 0.2,
        top: 0.1,
        right: 0.94,
        bottom: 0.9,
        lines: 20,
        charsPerLine: 30,
      ),
    ];
    final CropBox content = contentBoxFromTextBoxes(boxes);
    expect(detectColumns(boxes, content).length, 1);
  });

  test('пустой список — одна колонка во всю рамку', () {
    const CropBox content = CropBox(
      left: 0.1,
      top: 0.1,
      right: 0.9,
      bottom: 0.9,
    );
    final List<ColumnBand> bands = detectColumns(
      const <TextBox>[],
      content,
    );
    expect(bands.length, 1);
    expect(bands.single, const ColumnBand(left: 0.1, right: 0.9));
  });

  test('колонки не залезают в межколоночное поле', () {
    final List<TextBox> boxes = _twoColumns();
    final CropBox content = contentBoxFromTextBoxes(boxes);
    final List<ColumnBand> bands = detectColumns(boxes, content);

    for (final TextBox box in boxes) {
      final bool insideSome = bands.any(
        (ColumnBand band) =>
            box.left >= band.left - 1e-9 && box.right <= band.right + 1e-9,
      );
      expect(insideSome, isTrue, reason: 'символ $box не попал ни в колонку');
    }
  });
}
