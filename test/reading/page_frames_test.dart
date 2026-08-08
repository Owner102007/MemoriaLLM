import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/page_frames.dart';
import 'package:memoria/domain/reading/crop.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';

FakeReaderDocument _document() {
  return FakeReaderDocument(
    pages: List<String>.filled(4, 'текст'),
    boxes: <int, List<TextBox>>{
      1: textBlock(
        left: 0.15,
        top: 0.12,
        right: 0.85,
        bottom: 0.88,
        lines: 14,
        charsPerLine: 24,
      ),
      3: <TextBox>[
        ...textBlock(
          left: 0.08,
          top: 0.1,
          right: 0.46,
          bottom: 0.9,
          lines: 20,
          charsPerLine: 15,
        ),
        ...textBlock(
          left: 0.54,
          top: 0.1,
          right: 0.92,
          bottom: 0.9,
          lines: 20,
          charsPerLine: 15,
        ),
      ],
    },
  );
}

void main() {
  test('страница с текстом разбирается по тексту', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    final PageFrame frame = await frames.frameFor(1);
    expect(frame.fromText, isTrue);
    expect(frame.content.isValid, isTrue);
    expect(frame.content.width, lessThan(0.85));
    expect(frame.hasColumns, isFalse);
    expect(document.renders[1], isNull, reason: 'рисовать страницу не нужно');
  });

  test('двухколоночная страница отдаёт две колонки', () async {
    final PageFrameSource frames = PageFrameSource(document: _document());
    final PageFrame frame = await frames.frameFor(3);
    expect(frame.hasColumns, isTrue);
    expect(frame.columns.length, 2);
  });

  test('страница без текста разбирается по пикселям', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    final PageFrame frame = await frames.frameFor(2);
    expect(frame.fromText, isFalse);
    expect(frame.columns.length, 1);
    expect(document.renders[2], 1, reason: 'страница нарисована для разбора');
  });

  test('одинокий номер страницы за текстовый слой не считается', () async {
    final FakeReaderDocument document = FakeReaderDocument(
      pages: const <String>['7'],
      boxes: <int, List<TextBox>>{
        1: textBlock(
          left: 0.48,
          top: 0.94,
          right: 0.52,
          bottom: 0.96,
          lines: 1,
          charsPerLine: 2,
        ),
      },
    );
    final PageFrameSource frames = PageFrameSource(document: document);
    final PageFrame frame = await frames.frameFor(1);
    expect(frame.fromText, isFalse);
    expect(document.renders[1], 1);
  });

  test('рамка считается один раз, а не в каждом кадре', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    await frames.frameFor(1);
    await frames.frameFor(1);
    await frames.frameFor(1);

    expect(document.boxReads[1], 1);
    expect(frames.cached(1), isNotNull);
  });

  test('два одновременных запроса не считают страницу дважды', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    await Future.wait(<Future<PageFrame>>[
      frames.frameFor(1),
      frames.frameFor(1),
    ]);

    expect(document.boxReads[1], 1);
  });

  test('смена настроек обрезки забывает посчитанное', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    await frames.frameFor(1);
    frames.options = const CropOptions(ignoreRunningHeads: false);
    expect(frames.cached(1), isNull);

    await frames.frameFor(1);
    expect(document.boxReads[1], 2);
  });

  test('те же настройки кэш не сбрасывают', () async {
    final FakeReaderDocument document = _document();
    final PageFrameSource frames = PageFrameSource(document: document);

    await frames.frameFor(1);
    frames.options = CropOptions.standard;
    expect(frames.cached(1), isNotNull);
  });

  test('кэш не растёт бесконечно', () async {
    final FakeReaderDocument document = FakeReaderDocument(
      pages: List<String>.filled(40, ''),
    );
    final PageFrameSource frames = PageFrameSource(
      document: document,
      cacheSize: 8,
    );
    for (int page = 1; page <= 20; page++) {
      await frames.frameFor(page);
    }
    expect(frames.cached(1), isNull, reason: 'старое вытеснено');
    expect(frames.cached(20), isNotNull);
  });

  test('страница за краем книги даёт страницу целиком', () async {
    final PageFrameSource frames = PageFrameSource(document: _document());
    final PageFrame frame = await frames.frameFor(99);
    expect(frame.content, CropBox.full);
    expect(frame.columns.length, 1);
  });
}
