import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/reading/context_paragraph.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

import '../support/fake_reading.dart';
import '../support/page_text.dart';

/// Что контроллер обязан уметь ради выделения.
///
/// Слой текста страницы стоит похода в движок, а выделение спрашивает его
/// при каждом движении ручки: кэш здесь не украшение, а условие того,
/// чтобы ручку вообще можно было тянуть.
void main() {
  late FakeReadingRepository reading;

  setUp(() {
    reading = FakeReadingRepository();
  });

  Future<ReaderController> makeController(FakeReaderDocument document) {
    return ReaderController.open(
      book: fakeBook(),
      opener: FakeDocumentOpener(document),
      reading: reading,
    );
  }

  test('слой текста страницы разбирается один раз', () async {
    final PageTextLayout layout = buildLayout(<TestLine>[
      const TestLine('первая строка страницы', top: 0.10),
      const TestLine('вторая строка страницы', top: 0.13),
    ]);
    final FakeReaderDocument document = FakeReaderDocument(
      pages: <String>[layout.text, ''],
      layouts: <int, PageTextLayout>{1: layout},
    );
    final ReaderController controller = await makeController(document);

    await controller.textLayout(1);
    await controller.textLayout(1);
    expect(document.layoutReads[1], 1);
    expect(controller.cachedLayout(1)!.text, layout.text);

    await controller.close();
    controller.dispose();
  });

  test('страница за краем книги слоя не даёт и не падает', () async {
    final ReaderController controller = await makeController(
      FakeReaderDocument(pages: <String>['одна страница']),
    );
    expect((await controller.textLayout(0)).text, isEmpty);
    expect((await controller.textLayout(99)).text, isEmpty);
    await controller.close();
    controller.dispose();
  });

  test('контекст вокруг выделения приходит абзацем', () async {
    final PageTextLayout layout = buildLayout(<TestLine>[
      const TestLine('это первая строка абзаца тут', top: 0.10),
      const TestLine('а это вторая строка абзаца', top: 0.13),
    ]);
    final FakeReaderDocument document = FakeReaderDocument(
      pages: <String>[layout.text],
      layouts: <int, PageTextLayout>{1: layout},
    );
    final ReaderController controller = await makeController(document);

    final int start = layout.text.indexOf('вторая');
    final ParagraphContext? context = await controller.contextAround(
      pageNumber: 1,
      start: start,
      end: start + 6,
    );
    expect(context, isNotNull);
    expect(context!.selection, 'вторая');
    expect(context.text, startsWith('это первая строка'));

    await controller.close();
    controller.dispose();
  });

  test('подсветка приходит прямоугольниками по строкам', () async {
    final PageTextLayout layout = buildLayout(<TestLine>[
      const TestLine('первая строка страницы', top: 0.10),
      const TestLine('вторая строка страницы', top: 0.13),
    ]);
    final FakeReaderDocument document = FakeReaderDocument(
      pages: <String>[layout.text],
      layouts: <int, PageTextLayout>{1: layout},
    );
    final ReaderController controller = await makeController(document);

    final List<TextBox> rects = await controller.highlightFor(
      pageNumber: 1,
      start: 0,
      end: layout.text.length,
    );
    expect(rects, hasLength(2));
    for (final TextBox rect in rects) {
      expect(rect.isValid, isTrue);
    }

    await controller.close();
    controller.dispose();
  });

  group('место выделения в нашем счёте', () {
    /// Страница, на которой одно и то же слово встречается дважды.
    PageTextLayout twice() {
      return buildLayout(<TestLine>[
        const TestLine('идея первая и ясная', top: 0.10),
        const TestLine('идея вторая и мутная', top: 0.14),
      ]);
    }

    test('подсказка совпала — берётся она', () async {
      final PageTextLayout layout = twice();
      final ReaderController controller = await makeController(
        FakeReaderDocument(
          pages: <String>[layout.text],
          layouts: <int, PageTextLayout>{1: layout},
        ),
      );

      final int hint = layout.text.indexOf('вторая');
      final ({int start, int end})? place = await controller.locateOnPage(
        pageNumber: 1,
        text: 'вторая',
        hint: hint,
      );
      expect(place!.start, hint);
      expect(place.end, hint + 'вторая'.length);

      await controller.close();
      controller.dispose();
    });

    test('подсказка сбилась — берётся ближайшее вхождение', () async {
      // Ровно это и происходит на живой книге: просмотрщик считает места
      // по своему разбору страницы, где лишние пробелы склеены, и его
      // число в нашем тексте означает не то же место.
      final PageTextLayout layout = twice();
      final ReaderController controller = await makeController(
        FakeReaderDocument(
          pages: <String>[layout.text],
          layouts: <int, PageTextLayout>{1: layout},
        ),
      );

      final int second = layout.text.lastIndexOf('идея');
      final ({int start, int end})? place = await controller.locateOnPage(
        pageNumber: 1,
        text: 'идея',
        hint: second - 2,
      );
      expect(place!.start, second, reason: 'ближайшее, а не первое');

      await controller.close();
      controller.dispose();
    });

    test('текст не нашёлся — числа остаются просмотрщика', () async {
      final PageTextLayout layout = twice();
      final ReaderController controller = await makeController(
        FakeReaderDocument(
          pages: <String>[layout.text],
          layouts: <int, PageTextLayout>{1: layout},
        ),
      );

      expect(
        await controller.locateOnPage(pageNumber: 1, text: 'третья', hint: 0),
        isNull,
      );
      expect(
        await controller.locateOnPage(pageNumber: 1, text: '', hint: 0),
        isNull,
      );

      await controller.close();
      controller.dispose();
    });
  });

  test('у страницы без геометрии подсветки нет, но текст есть', () async {
    // Скан: символов с местом на странице нет вовсе. Подсвечивать нечего,
    // и это не ошибка — это честный ответ.
    final FakeReaderDocument document = FakeReaderDocument(
      pages: <String>['страница без текстового слоя'],
    );
    final ReaderController controller = await makeController(document);

    expect(
      await controller.highlightFor(pageNumber: 1, start: 0, end: 5),
      isEmpty,
    );
    expect((await controller.textLayout(1)).text, isNotEmpty);

    await controller.close();
    controller.dispose();
  });
}
