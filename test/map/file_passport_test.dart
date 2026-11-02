/// Правило паспорта файла (ALG-MAP-18) на придуманных фактах страниц:
/// вид страницы, вид книги, качество скана. Настоящие файлы — в
/// `test/pdf/pdfium_passport_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/file_passport.dart';

/// Страница набранного текста.
const PageFacts _text = PageFacts(chars: 1800, imageShare: 0.05);

/// Лист-картинка без слоя, 300 dpi, серый.
const PageFacts _scan = PageFacts(
  chars: 0,
  imageShare: 0.98,
  images: 1,
  dpi: 300,
  bitsPerPixel: 8,
);

/// Лист-картинка с невидимым слоем, 200 dpi, ч/б.
const PageFacts _layered = PageFacts(
  chars: 1500,
  imageShare: 0.99,
  textObjects: 40,
  invisibleTextObjects: 40,
  images: 1,
  dpi: 200,
  bitsPerPixel: 1,
);

/// Пустая страница.
const PageFacts _blank = PageFacts(chars: 3, imageShare: 0);

void main() {
  group('ALG-MAP-18: вид страницы', () {
    test('ALG-MAP-18: знаки без листа-картинки — текст', () {
      expect(pageKindOf(_text), PageKind.text);
    });

    test('ALG-MAP-18: лист-картинка без знаков — скан без слоя', () {
      expect(pageKindOf(_scan), PageKind.scanNoLayer);
    });

    test('ALG-MAP-18: лист-картинка со знаками — скан со слоем', () {
      expect(pageKindOf(_layered), PageKind.scanWithLayer);
    });

    test('ALG-MAP-18: ни знаков, ни картинки — пустая', () {
      expect(pageKindOf(_blank), PageKind.empty);
    });

    test('ALG-MAP-18: пороги — 60 % площади и 40 знаков', () {
      expect(
        pageKindOf(const PageFacts(chars: 40, imageShare: 0.6)),
        PageKind.scanWithLayer,
      );
      expect(
        pageKindOf(const PageFacts(chars: 39, imageShare: 0.59)),
        PageKind.empty,
      );
      // Иллюстрация на полстраницы со строкой подписи — всё ещё текст.
      expect(
        pageKindOf(const PageFacts(chars: 400, imageShare: 0.5)),
        PageKind.text,
      );
    });
  });

  group('ALG-MAP-18: вид книги', () {
    test('ALG-MAP-18: текст у 80 % страниц — электронный оригинал', () {
      final FilePassport passport = passportOf(<PageFacts>[
        for (int i = 0; i < 8; i++) _text,
        _blank,
        _scan,
      ]);
      expect(passport.kind, BookKind.digital);
      expect(passport.count(PageKind.text), 8);
    });

    test('ALG-MAP-18: половина страниц — скан со слоем', () {
      final FilePassport passport = passportOf(<PageFacts>[
        _layered,
        _layered,
        _text,
        _blank,
      ]);
      expect(passport.kind, BookKind.scanWithLayer);
      expect(passport.dpiMedian, 200);
      expect(passport.color, ScanColor.blackWhite);
    });

    test('ALG-MAP-18: половина страниц — скан без слоя', () {
      final FilePassport passport = passportOf(<PageFacts>[
        _scan,
        _scan,
        _scan,
        _text,
        _text,
        _blank,
      ]);
      expect(passport.kind, BookKind.scanNoLayer);
      expect(passport.dpiMedian, 300);
      expect(passport.color, ScanColor.gray);
    });

    test('ALG-MAP-18: ни то ни другое — смешанный', () {
      final FilePassport passport = passportOf(<PageFacts>[
        _scan,
        _layered,
        _text,
        _text,
        _blank,
      ]);
      expect(passport.kind, BookKind.mixed);
      // Медиана по двум сканам — верхний из двух, как в шаге 46.
      expect(passport.dpiMedian, 300);
    });

    test('ALG-MAP-18: книга без страниц — смешанная, без качества скана', () {
      final FilePassport passport = passportOf(const <PageFacts>[]);
      expect(passport.kind, BookKind.mixed);
      expect(passport.dpiMedian, isNull);
      expect(passport.color, isNull);
    });

    test('ALG-MAP-18: у электронного оригинала нет качества скана', () {
      final FilePassport passport = passportOf(<PageFacts>[_text, _text]);
      expect(passport.dpiMedian, isNull);
      expect(passport.color, isNull);
    });

    test('ALG-MAP-18: метаданные — без пробелов по краям', () {
      final FilePassport passport = passportOf(
        <PageFacts>[_text],
        producer: '  ABBYY FineReader ',
        creator: 'Word',
        bookmarks: 12,
      );
      expect(passport.producer, 'ABBYY FineReader');
      expect(passport.creator, 'Word');
      expect(passport.bookmarks, 12);
    });
  });

  test('ALG-MAP-18: цветность — 1 бит ч/б, до 8 серое, больше — цвет', () {
    expect(colorOf(1), ScanColor.blackWhite);
    expect(colorOf(8), ScanColor.gray);
    expect(colorOf(24), ScanColor.color);
  });
}
