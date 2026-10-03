import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/book_frame.dart';
import 'package:memoria/domain/reading/reading.dart';

/// Рамка обычной страницы выборки.
const CropBox _usual = CropBox(left: 0.14, top: 0.1, right: 0.86, bottom: 0.9);

/// Выборка из [pages] страниц с одной и той же рамкой.
List<FrameSample> _uniform(Iterable<int> pages, {CropBox box = _usual}) {
  return <FrameSample>[
    for (final int page in pages) FrameSample(page: page, content: box),
  ];
}

/// Выборка книги из переплёта: у нечётных страниц широкое поле слева, у
/// чётных — справа.
List<FrameSample> _bound(Iterable<int> pages) {
  return <FrameSample>[
    for (final int page in pages)
      FrameSample(
        page: page,
        content: page.isEven
            ? const CropBox(left: 0.07, top: 0.1, right: 0.86, bottom: 0.9)
            : const CropBox(left: 0.14, top: 0.1, right: 0.93, bottom: 0.9),
      ),
  ];
}

void main() {
  group('F-READ-15: какие страницы идут в выборку', () {
    test('F-READ-15: книга из трёх страниц идёт в выборку целиком', () {
      expect(bookFrameSamplePages(3), <int>[1, 2, 3]);
      expect(
        bookFrameSamplePages(3, attempt: 1),
        isEmpty,
        reason: 'добирать не из чего',
      );
    });

    test('F-READ-15: в книге из 700 страниц выборка разбросана', () {
      final List<int> pages = bookFrameSamplePages(700);
      expect(pages.length, kBookFrameSample);
      expect(pages.toSet().length, pages.length, reason: 'без повторов');
      // Начало и конец книги в выборку не идут: там титул, оглавление и
      // указатели.
      expect(pages.first, greaterThan(35));
      expect(pages.last, lessThanOrEqualTo(665));
      for (int i = 1; i < pages.length; i++) {
        expect(
          pages[i] - pages[i - 1],
          greaterThan(30),
          reason: 'страницы не идут подряд',
        );
      }
    });

    test('F-READ-15: чётных и нечётных страниц в выборке поровну', () {
      for (final int count in <int>[40, 120, 700, 1200]) {
        final List<int> pages = bookFrameSamplePages(count);
        final int odd = pages.where((int page) => page.isOdd).length;
        expect(odd, pages.length - odd, reason: 'книга из $count страниц');
      }
    });

    test('F-READ-15: выборка не выходит за края книги', () {
      for (int count = 1; count <= 60; count++) {
        for (int attempt = 0; attempt < 2; attempt++) {
          final List<int> pages = bookFrameSamplePages(count, attempt: attempt);
          expect(pages.every((int page) => page >= 1 && page <= count), isTrue);
        }
      }
      expect(bookFrameSamplePages(0), isEmpty);
    });

    test('F-READ-15: добор берёт страницы той же чётности рядом', () {
      final List<int> first = bookFrameSamplePages(700);
      final List<int> second = bookFrameSamplePages(700, attempt: 1);
      expect(second, <int>[for (final int page in first) page + 2]);
    });
  });

  group('F-READ-15: рамка книги по выборке', () {
    test('F-READ-15: одинаковые страницы дают их общую рамку', () {
      final BookFrame frame = bookFrameFromSamples(
        _uniform(bookFrameSamplePages(120)),
        ignoreRunningHeads: true,
      );
      expect(frame.odd, _usual);
      expect(frame.even, _usual);
      expect(frame.isMirrored, isFalse);
      expect(frame.samples, kBookFrameSample);
      expect(frame.version, kBookFrameVersion);
    });

    test('F-READ-15: страница во всю площадь рамку книги не расширяет', () {
      // Полосная иллюстрация: содержимое почти во всю страницу. Минимум
      // по выборке утянул бы за ней рамку всей книги.
      final List<FrameSample> samples = _uniform(bookFrameSamplePages(120));
      samples[5] = FrameSample(
        page: samples[5].page,
        content: const CropBox(left: 0, top: 0, right: 1, bottom: 0.995),
      );
      final BookFrame frame = bookFrameFromSamples(
        samples,
        ignoreRunningHeads: true,
      );
      expect(frame.odd, _usual);
    });

    test('F-READ-15: короткие страницы рамку не сужают', () {
      // Концевая страница главы: текста на треть листа. Рамка книги
      // берётся почти самой широкой, а не средней.
      final List<FrameSample> samples = _uniform(bookFrameSamplePages(120));
      for (final int index in <int>[1, 4, 7, 10, 13]) {
        samples[index] = FrameSample(
          page: samples[index].page,
          content: const CropBox(left: 0.2, top: 0.1, right: 0.8, bottom: 0.4),
        );
      }
      final BookFrame frame = bookFrameFromSamples(
        samples,
        ignoreRunningHeads: true,
      );
      expect(frame.odd, _usual);
    });

    test('F-READ-15: пустые страницы в расчёт не идут', () {
      final List<FrameSample> samples = <FrameSample>[
        for (int page = 1; page <= 4; page++)
          FrameSample(page: page, content: CropBox.full),
        ..._uniform(<int>[5, 6, 7, 8, 9, 10]),
      ];
      expect(usableSampleCount(samples), 6);
      final BookFrame frame = bookFrameFromSamples(
        samples,
        ignoreRunningHeads: true,
      );
      expect(frame.odd, _usual);
      expect(frame.samples, 6);
    });

    test('F-READ-15: ни одной пригодной страницы — книга без обрезки', () {
      final List<FrameSample> blank = <FrameSample>[
        for (int page = 1; page <= 8; page++)
          FrameSample(page: page, content: CropBox.full),
      ];
      final BookFrame frame = bookFrameFromSamples(
        blank,
        ignoreRunningHeads: false,
      );
      expect(frame.hasContent, isFalse);
      expect(frame.odd, CropBox.full);
      expect(frame.ignoreRunningHeads, isFalse);
      expect(pageContentInBook(book: frame, page: 3), CropBox.full);
    });

    test('F-READ-15: зеркальные поля — ширина одна, чётные сдвинуты', () {
      final BookFrame frame = bookFrameFromSamples(
        _bound(bookFrameSamplePages(120)),
        ignoreRunningHeads: true,
      );
      expect(frame.isMirrored, isTrue);
      expect(frame.odd.left, closeTo(0.14, 1e-9));
      expect(frame.odd.right, closeTo(0.93, 1e-9));
      expect(frame.even.left, closeTo(0.07, 1e-9));
      expect(frame.even.right, closeTo(0.86, 1e-9));
      expect(frame.even.width, closeTo(frame.odd.width, 1e-9));
      // Общая рамка на оба поля сразу была бы шире на само поле.
      expect(frame.odd.width, lessThan(0.86 - 0.01));
      expect(frame.forPage(7), frame.odd);
      expect(frame.forPage(8), frame.even);
    });

    test('F-READ-15: без зеркальных полей сдвига нет', () {
      final BookFrame frame = bookFrameFromSamples(
        _uniform(bookFrameSamplePages(120)),
        ignoreRunningHeads: true,
      );
      expect(frame.evenShift, 0);
      expect(frame.forPage(8), frame.forPage(7));
    });

    test('F-READ-15: по двум страницам о зеркальности не судят', () {
      // Чётных страниц в выборке две — для вывода о переплёте мало, и
      // рамка берётся общей: шире, зато ничего не срезает.
      final BookFrame frame = bookFrameFromSamples(
        _bound(<int>[1, 2, 3, 4, 5]),
        ignoreRunningHeads: true,
      );
      expect(frame.isMirrored, isFalse);
      expect(frame.odd.left, closeTo(0.07, 1e-9));
      expect(frame.odd.right, closeTo(0.93, 1e-9));
    });

    test('F-READ-15: рамка чётных страниц не выходит за край листа', () {
      final List<FrameSample> samples = <FrameSample>[
        for (int page = 1; page <= 8; page++)
          FrameSample(
            page: page,
            content: page.isEven
                ? const CropBox(left: 0, top: 0.1, right: 0.8, bottom: 0.9)
                : const CropBox(left: 0.2, top: 0.1, right: 1, bottom: 0.9),
          ),
      ];
      final BookFrame frame = bookFrameFromSamples(
        samples,
        ignoreRunningHeads: true,
      );
      expect(frame.isMirrored, isTrue);
      expect(frame.odd.isValid, isTrue);
      expect(frame.even.isValid, isTrue);
      expect(frame.even.left, greaterThanOrEqualTo(0));
      expect(frame.odd.right, lessThanOrEqualTo(1));
    });

    test('F-READ-15: рамка помнит, чем и с какой настройкой посчитана', () {
      final BookFrame frame = bookFrameFromSamples(
        _uniform(<int>[1, 2, 3]),
        ignoreRunningHeads: true,
      );
      expect(frame.isCurrentFor(ignoreRunningHeads: true), isTrue);
      expect(frame.isCurrentFor(ignoreRunningHeads: false), isFalse);
      // ALG-DATA-09: рамка прежней версии алгоритма не годится.
      const BookFrame old = BookFrame(
        odd: _usual,
        samples: 3,
        version: kBookFrameVersion - 1,
      );
      expect(old.isCurrentFor(ignoreRunningHeads: true), isFalse);
    });
  });

  group('F-READ-15: рамка страницы внутри книги', () {
    const BookFrame book = BookFrame(odd: _usual, samples: 16);

    test('F-READ-15: обычная страница получает рамку книги', () {
      expect(
        pageContentInBook(
          book: book,
          page: 9,
          ownText: const CropBox(left: 0.2, top: 0.1, right: 0.8, bottom: 0.5),
        ),
        _usual,
      );
    });

    test('F-READ-15: выход в пределах запаса вышедшим не считается', () {
      // Рамка страницы шире рамки книги ровно на запас автообрезки:
      // сами символы при этом лежат внутри рамки книги.
      expect(
        pageContentInBook(
          book: book,
          page: 9,
          ownText: const CropBox(
            left: 0.13,
            top: 0.09,
            right: 0.87,
            bottom: 0.91,
          ),
        ),
        _usual,
      );
    });

    test('F-READ-15: текст за рамкой книги расширяет рамку страницы', () {
      // Широкая таблица: текст выходит вправо. Страница получает рамку,
      // расширенную до него, — ни один символ не срезан.
      final CropBox content = pageContentInBook(
        book: book,
        page: 9,
        ownText: const CropBox(left: 0.2, top: 0.3, right: 0.95, bottom: 0.6),
      );
      expect(content.left, _usual.left);
      expect(content.top, _usual.top);
      expect(content.right, 0.95);
      expect(content.bottom, _usual.bottom);
    });

    test('F-READ-15: у скана рамка книги стоит твёрдо', () {
      // Своей рамки по текстовому слою у скана нет.
      expect(pageContentInBook(book: book, page: 9), _usual);
      expect(
        pageContentInBook(book: book, page: 9, ownText: CropBox.full),
        _usual,
        reason: 'страница целиком — это «не разобрали», а не текст',
      );
    });

    test('F-READ-15: чётная страница сверяется со своей рамкой', () {
      const BookFrame bound = BookFrame(
        odd: CropBox(left: 0.14, top: 0.1, right: 0.93, bottom: 0.9),
        evenShift: -0.07,
        samples: 16,
      );
      const CropBox even = CropBox(
        left: 0.07,
        top: 0.1,
        right: 0.86,
        bottom: 0.9,
      );
      final CropBox content = pageContentInBook(
        book: bound,
        page: 8,
        ownText: even,
      );
      expect(content.left, closeTo(0.07, 1e-9));
      expect(content.right, closeTo(0.86, 1e-9));
    });
  });
}
