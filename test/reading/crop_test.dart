import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/crop.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';

/// Страница-растр: белый лист с одним тёмным прямоугольником.
///
/// Так выглядит скан в глазах автообрезки: фон берётся с краёв, чернилами
/// считается всё, что от него отличается.
PageRaster _scan({
  int width = 100,
  int height = 100,
  required int left,
  required int top,
  required int right,
  required int bottom,
  List<List<int>> speckles = const <List<int>>[],
}) {
  final Uint8List pixels = Uint8List(width * height * 4);
  for (int i = 0; i < width * height; i++) {
    pixels[i * 4] = 255;
    pixels[i * 4 + 1] = 255;
    pixels[i * 4 + 2] = 255;
    pixels[i * 4 + 3] = 255;
  }
  void ink(int x, int y) {
    final int base = (y * width + x) * 4;
    pixels[base] = 20;
    pixels[base + 1] = 20;
    pixels[base + 2] = 20;
  }

  for (int y = top; y <= bottom; y++) {
    for (int x = left; x <= right; x++) {
      ink(x, y);
    }
  }
  for (final List<int> speck in speckles) {
    ink(speck[0], speck[1]);
  }
  return PageRaster(width: width, height: height, pixels: pixels);
}

void main() {
  group('рамка по тексту', () {
    test('поля обрезаются, содержимое остаётся внутри', () {
      final List<TextBox> boxes = textBlock(
        left: 0.2,
        top: 0.15,
        right: 0.8,
        bottom: 0.85,
        lines: 10,
        charsPerLine: 20,
      );
      final CropBox crop = contentBoxFromTextBoxes(boxes);

      expect(crop.isValid, isTrue);
      // Рамка шире содержимого на запас и уже страницы — иначе обрезки
      // не случилось вовсе.
      expect(crop.left, lessThanOrEqualTo(0.2));
      expect(crop.left, greaterThan(0.1));
      expect(crop.right, greaterThanOrEqualTo(0.79));
      expect(crop.right, lessThan(0.9));
      expect(crop.top, lessThanOrEqualTo(0.15));
      expect(crop.bottom, greaterThanOrEqualTo(0.82));
      expect(crop.width, lessThan(1));
      expect(crop.height, lessThan(1));
    });

    test('ни один символ не остаётся за рамкой', () {
      final List<TextBox> boxes = textBlock(
        left: 0.13,
        top: 0.21,
        right: 0.87,
        bottom: 0.79,
        lines: 12,
        charsPerLine: 30,
      );
      final CropBox crop = contentBoxFromTextBoxes(boxes);
      for (final TextBox box in boxes) {
        expect(box.left, greaterThanOrEqualTo(crop.left));
        expect(box.right, lessThanOrEqualTo(crop.right));
        expect(box.top, greaterThanOrEqualTo(crop.top));
        expect(box.bottom, lessThanOrEqualTo(crop.bottom));
      }
    });

    test('без текста рамка — страница целиком', () {
      expect(contentBoxFromTextBoxes(const <TextBox>[]), CropBox.full);
    });

    test('одно слово посреди листа не растягивается на весь экран', () {
      final List<TextBox> boxes = textBlock(
        left: 0.48,
        top: 0.49,
        right: 0.52,
        bottom: 0.51,
        lines: 1,
        charsPerLine: 4,
      );
      final CropBox crop = contentBoxFromTextBoxes(boxes);
      expect(crop.isValid, isTrue);
      expect(crop.width, greaterThanOrEqualTo(0.2));
      expect(crop.height, greaterThanOrEqualTo(0.2));
    });
  });

  group('колонтитулы', () {
    List<TextBox> withRunningHeads() {
      return <TextBox>[
        ...textBlock(
          left: 0.45,
          top: 0.05,
          right: 0.55,
          bottom: 0.07,
          lines: 1,
          charsPerLine: 3,
        ),
        ...textBlock(
          left: 0.15,
          top: 0.3,
          right: 0.85,
          bottom: 0.8,
          lines: 8,
          charsPerLine: 20,
        ),
        ...textBlock(
          left: 0.45,
          top: 0.93,
          right: 0.55,
          bottom: 0.95,
          lines: 1,
          charsPerLine: 3,
        ),
      ];
    }

    test('оторванные строки сверху и снизу не считаются содержимым', () {
      final CropBox crop = contentBoxFromTextBoxes(withRunningHeads());
      expect(crop.top, greaterThan(0.25));
      expect(crop.bottom, lessThan(0.85));
    });

    test('если колонтитулы считать содержимым, рамка растёт', () {
      final CropBox crop = contentBoxFromTextBoxes(
        withRunningHeads(),
        options: const CropOptions(ignoreRunningHeads: false),
      );
      expect(crop.top, lessThan(0.06));
      expect(crop.bottom, greaterThan(0.93));
    });

    test('на короткой странице ничего не выбрасывается', () {
      // Три строки — это не книга с колонтитулами, а титул или
      // посвящение. Выбросить из него строку значит потерять треть.
      final List<TextLine> lines = groupTextLines(
        textBlock(
          left: 0.2,
          top: 0.2,
          right: 0.8,
          bottom: 0.4,
          lines: 3,
          charsPerLine: 10,
        ),
      );
      expect(dropRunningHeads(lines).length, lines.length);
    });
  });

  group('рамка по пикселям', () {
    test('тёмный прямоугольник на белом листе находится', () {
      final CropBox crop = contentBoxFromRaster(
        _scan(left: 20, top: 30, right: 79, bottom: 69),
      );
      expect(crop.isValid, isTrue);
      expect(crop.left, closeTo(0.19, 0.02));
      expect(crop.top, closeTo(0.29, 0.02));
      expect(crop.right, closeTo(0.81, 0.02));
      expect(crop.bottom, closeTo(0.71, 0.02));
    });

    test('одинокая пылинка на поле рамку не растягивает', () {
      final CropBox clean = contentBoxFromRaster(
        _scan(left: 30, top: 30, right: 69, bottom: 69),
      );
      final CropBox dusty = contentBoxFromRaster(
        _scan(
          left: 30,
          top: 30,
          right: 69,
          bottom: 69,
          speckles: const <List<int>>[
            <int>[3, 4],
            <int>[96, 92],
          ],
        ),
      );
      expect(dusty, clean);
    });

    test('чистый лист — страница целиком, а не вывернутая рамка', () {
      final Uint8List pixels = Uint8List(40 * 40 * 4);
      for (int i = 0; i < pixels.length; i++) {
        pixels[i] = 255;
      }
      final CropBox crop = contentBoxFromRaster(
        PageRaster(width: 40, height: 40, pixels: pixels),
      );
      expect(crop, CropBox.full);
    });

    test('светлый текст на тёмном фоне обрезается так же', () {
      final Uint8List pixels = Uint8List(60 * 60 * 4);
      for (int i = 0; i < 60 * 60; i++) {
        pixels[i * 4 + 3] = 255;
      }
      for (int y = 10; y < 50; y++) {
        for (int x = 15; x < 45; x++) {
          final int base = (y * 60 + x) * 4;
          pixels[base] = 240;
          pixels[base + 1] = 240;
          pixels[base + 2] = 240;
        }
      }
      final CropBox crop = contentBoxFromRaster(
        PageRaster(width: 60, height: 60, pixels: pixels),
      );
      expect(crop.isValid, isTrue);
      expect(crop.width, lessThan(0.9));
    });

    test('несогласованный растр не роняет обрезку', () {
      final CropBox crop = contentBoxFromRaster(
        PageRaster(width: 10, height: 10, pixels: Uint8List(4)),
      );
      expect(crop, CropBox.full);
    });
  });

  group('нормализация', () {
    test('вывернутая рамка превращается в страницу целиком', () {
      const CropBox inverted = CropBox(
        left: 0.8,
        top: 0.9,
        right: 0.2,
        bottom: 0.1,
      );
      expect(normalizeCrop(inverted), CropBox.full);
    });

    test('рамка никогда не выходит за страницу', () {
      const CropBox huge = CropBox(left: 0, top: 0, right: 1, bottom: 1);
      final CropBox crop = normalizeCrop(huge);
      expect(crop.left, greaterThanOrEqualTo(0));
      expect(crop.top, greaterThanOrEqualTo(0));
      expect(crop.right, lessThanOrEqualTo(1));
      expect(crop.bottom, lessThanOrEqualTo(1));
    });

    test('бесконечности не проходят', () {
      const CropBox broken = CropBox(
        left: double.nan,
        top: 0,
        right: 1,
        bottom: 1,
      );
      expect(normalizeCrop(broken), CropBox.full);
    });
  });

  group('какая рамка в итоге показывается', () {
    const BookReadingSettings base = BookReadingSettings(
      bookId: 'b',
      orientation: ScreenOrientation.portrait,
    );
    const CropBox automatic = CropBox(
      left: 0.1,
      top: 0.1,
      right: 0.9,
      bottom: 0.9,
    );

    test('по умолчанию — автообрезка', () {
      expect(
        effectiveCrop(settings: base, automatic: automatic),
        automatic,
      );
    });

    test('автообрезка выключена — страница целиком', () {
      expect(
        effectiveCrop(
          settings: base.copyWith(autoCrop: false),
          automatic: automatic,
        ),
        CropBox.full,
      );
    });

    test('ручная рамка главнее автоматической', () {
      const CropBox manual = CropBox(
        left: 0.2,
        top: 0.2,
        right: 0.7,
        bottom: 0.7,
      );
      expect(
        effectiveCrop(
          settings: base.copyWith(manualCrop: manual),
          automatic: automatic,
        ),
        manual,
      );
    });

    test('испорченная автоматическая рамка не показывается', () {
      expect(
        effectiveCrop(
          settings: base,
          automatic: const CropBox(left: 1, top: 1, right: 0, bottom: 0),
        ),
        CropBox.full,
      );
    });
  });

  group('строки', () {
    test('символы разных кеглей в строке не разбегаются', () {
      const List<TextBox> line = <TextBox>[
        TextBox(left: 0.1, top: 0.1, right: 0.13, bottom: 0.14),
        TextBox(left: 0.14, top: 0.11, right: 0.16, bottom: 0.14),
        TextBox(left: 0.17, top: 0.105, right: 0.2, bottom: 0.145),
      ];
      expect(groupTextLines(line).length, 1);
    });

    test('строки идут сверху вниз', () {
      final List<TextLine> lines = groupTextLines(
        textBlock(lines: 5, charsPerLine: 4),
      );
      expect(lines.length, 5);
      for (int i = 1; i < lines.length; i++) {
        expect(lines[i].top, greaterThan(lines[i - 1].top));
      }
    });

    test('мусорные прямоугольники выбрасываются', () {
      const List<TextBox> junk = <TextBox>[
        TextBox(left: 0.5, top: 0.5, right: 0.4, bottom: 0.6),
        TextBox(left: -1, top: 0, right: 2, bottom: 1),
      ];
      expect(groupTextLines(junk), isEmpty);
    });
  });
}
