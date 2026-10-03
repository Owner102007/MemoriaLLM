import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/navigation.dart';
import 'package:memoria/domain/reading/reading.dart';

void main() {
  group('clampPage', () {
    test('оставляет страницу внутри книги', () {
      expect(clampPage(5, 10), 5);
      expect(clampPage(1, 10), 1);
      expect(clampPage(10, 10), 10);
    });

    test('прижимает к краям вместо ошибки', () {
      expect(clampPage(0, 10), 1);
      expect(clampPage(-7, 10), 1);
      expect(clampPage(11, 10), 10);
      expect(clampPage(9999, 10), 10);
    });

    test('книга без страниц не роняет арифметику', () {
      expect(clampPage(3, 0), 1);
      expect(clampPage(3, -1), 1);
    });
  });

  group('progressForPage', () {
    test('первая страница уже что-то, последняя — ровно всё', () {
      expect(progressForPage(1, 10), closeTo(0.1, 1e-9));
      expect(progressForPage(10, 10), 1.0);
    });

    test('растёт монотонно и не выходит за единицу', () {
      double previous = -1;
      for (int page = 1; page <= 50; page++) {
        final double value = progressForPage(page, 50);
        expect(value, greaterThan(previous));
        expect(value, lessThanOrEqualTo(1.0));
        previous = value;
      }
    });

    test('смещение внутри страницы только увеличивает прогресс', () {
      final double base = progressForPage(3, 10);
      expect(progressForPage(3, 10, offset: 0.5), greaterThan(base));
      expect(
        progressForPage(3, 10, offset: 1),
        closeTo(progressForPage(4, 10), 1e-9),
      );
    });

    test('мусорные значения не ломают счёт', () {
      expect(progressForPage(3, 10, offset: double.nan), closeTo(0.3, 1e-9));
      expect(progressForPage(3, 10, offset: 42), closeTo(0.4, 1e-9));
      expect(progressForPage(3, 0), 0);
    });
  });

  group('pageForProgress', () {
    test('обратна progressForPage', () {
      for (final int pageCount in <int>[1, 7, 340, 1200]) {
        for (int page = 1; page <= pageCount; page += pageCount ~/ 7 + 1) {
          final double progress = progressForPage(page, pageCount);
          expect(
            pageForProgress(progress, pageCount),
            page,
            reason: 'страница $page из $pageCount',
          );
        }
      }
    });

    test('края ведут себя предсказуемо', () {
      expect(pageForProgress(0, 10), 1);
      expect(pageForProgress(-1, 10), 1);
      expect(pageForProgress(1, 10), 10);
      expect(pageForProgress(5, 10), 10);
      expect(pageForProgress(double.nan, 10), 1);
    });
  });

  group('restorePage', () {
    test('книгу без позиции открываем с первой страницы', () {
      expect(restorePage(null, 100), 1);
    });

    test('позиция возвращает туда, где остановились', () {
      const ReadingPosition position = ReadingPosition(bookId: 'b', page: 42);
      expect(restorePage(position, 100), 42);
    });

    test('позиция за краем прижимается к концу, а не к началу', () {
      // Книгу заменили редакцией покороче. Потерять место в конце
      // обиднее всего, поэтому открываем последнюю страницу.
      const ReadingPosition position = ReadingPosition(bookId: 'b', page: 900);
      expect(restorePage(position, 100), 100);
    });
  });

  group('шаги и подписи', () {
    test('на краях книги шаг никуда не уводит', () {
      expect(nextPage(10, 10), 10);
      expect(previousPage(1, 10), 1);
      expect(nextPage(1, 10), 2);
      expect(previousPage(10, 10), 9);
    });

    test('подпись страницы', () {
      expect(pageLabel(12, 340), '12 / 340');
      expect(pageLabel(0, 340), '1 / 340');
      expect(pageLabel(1, 0), '1 / 1');
    });

    test('F-READ-06: подпись разворота называет обе страницы', () {
      expect(sheetLabel(<int>[12, 13], 340), '12–13 / 340');
      expect(sheetLabel(<int>[12], 340), '12 / 340');
      expect(sheetLabel(<int>[340], 340), '340 / 340');
      // Пустой лист и страницы за краем книги не роняют подпись.
      expect(sheetLabel(const <int>[], 340), '1 / 340');
      expect(sheetLabel(<int>[340, 341], 340), '340 / 340');
      expect(sheetLabel(<int>[1], 0), '1 / 1');
    });

    test('проценты', () {
      expect(progressPercent(0), 0);
      expect(progressPercent(0.5), 50);
      expect(progressPercent(1), 100);
      expect(progressPercent(double.nan), 0);
      expect(progressPercent(2), 100);
    });
  });

  group('positionForPage', () {
    test('собирает позицию с прогрессом', () {
      final ReadingPosition position = positionForPage(
        bookId: 'book',
        page: 5,
        pageCount: 20,
      );
      expect(position.bookId, 'book');
      expect(position.page, 5);
      expect(position.progress, closeTo(0.25, 1e-9));
    });

    test('страница за краем прижимается вместе с прогрессом', () {
      final ReadingPosition position = positionForPage(
        bookId: 'book',
        page: 900,
        pageCount: 20,
      );
      expect(position.page, 20);
      expect(position.progress, 1.0);
    });
  });

  group('BUG-39: протяжка ползунка страниц', () {
    test('BUG-39: пока бегунок тянут, переходить некуда', () {
      final SliderDrag drag = SliderDrag();
      expect(drag.held, isNull);
      expect(drag.rest(current: 10), isNull, reason: 'бегунок не трогали');

      // Протяжка через полкниги: под бегунком побывали десятки страниц,
      // и ни одна из них сама по себе переходом не становится.
      for (int page = 11; page <= 400; page++) {
        drag.move(page);
      }
      expect(drag.held, 400);
    });

    test('BUG-39: переход один — туда, где бегунок остановился', () {
      final SliderDrag drag = SliderDrag();
      for (int page = 11; page <= 400; page++) {
        drag.move(page);
      }
      expect(drag.rest(current: 10), 400);
      // Отпустили там же, где он уже простоял: второй раз не переходим.
      expect(drag.rest(current: 10), isNull);
      expect(drag.rest(current: 400), isNull);
    });

    test('BUG-39: остановка посреди протяжки и продолжение — два перехода', () {
      final SliderDrag drag = SliderDrag();
      drag.move(120);
      expect(drag.rest(current: 10), 120);
      drag.move(260);
      expect(drag.rest(current: 120), 260);
    });

    test('BUG-39: вернули бегунок на место — книга не трогается', () {
      final SliderDrag drag = SliderDrag();
      drag.move(55);
      drag.move(10);
      expect(drag.rest(current: 10), isNull);
    });

    test('BUG-39: вернули бегунок после остановки — переход обратно', () {
      // Переход на сто двадцатую уже отправлен и мог ещё не закончиться:
      // книга по-прежнему на десятой, но читатель просит именно её.
      final SliderDrag drag = SliderDrag();
      drag.move(120);
      expect(drag.rest(current: 10), 120);
      drag.move(10);
      expect(drag.rest(current: 10), 10);
    });

    test('BUG-39: отпущенный бегунок снова следует за книгой', () {
      final SliderDrag drag = SliderDrag();
      drag.move(120);
      expect(drag.rest(current: 10), 120);
      drag.release();
      expect(drag.held, isNull);
      // Новая протяжка на ту же страницу — снова переход: прошлая
      // протяжка её не «помнит».
      drag.move(120);
      expect(drag.rest(current: 10), 120);
    });

    test('BUG-39: срок остановки короче заметной паузы', () {
      expect(kSliderRest, lessThanOrEqualTo(const Duration(milliseconds: 200)));
      expect(kSliderRest, greaterThan(const Duration(milliseconds: 50)));
    });
  });
}
