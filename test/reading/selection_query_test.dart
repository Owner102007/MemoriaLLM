import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/selection_query.dart';
import 'package:memoria/domain/reading/text_search.dart';

/// SNO-F-READ-01: «Найти в книге» — запрос из выделенного и место
/// выделения среди найденного.
void main() {
  group('SNO-F-READ-01: запрос из выделенного', () {
    test('SNO-F-READ-01: края и лишние пробелы убраны', () {
      expect(selectionSearchQuery('  остеология  '), 'остеология');
      expect(
        selectionSearchQuery('плечевая\r\nкость\n\nи  лопатка'),
        'плечевая кость и лопатка',
      );
      expect(selectionSearchQuery('плечевая\u00A0кость'), 'плечевая кость');
    });

    test('SNO-F-READ-01: слово, разрезанное переносом, склеено', () {
      expect(selectionSearchQuery('остео-\nлогия'), 'остеология');
      expect(selectionSearchQuery('остео- \r\n  логия'), 'остеология');
      expect(selectionSearchQuery('micro-\nscope'), 'microscope');
      expect(selectionSearchQuery('остео\u00AD\nлогия'), 'остеология');
    });

    test('SNO-F-READ-01: дефис внутри строки остаётся дефисом', () {
      expect(selectionSearchQuery('что-то'), 'что-то');
      expect(
        selectionSearchQuery('плечевая кость - длинная'),
        'плечевая кость - длинная',
      );
    });

    test('SNO-F-READ-01: заглавная после переноса — это новое слово', () {
      expect(selectionSearchQuery('Санкт-\nПетербург'), 'Санкт- Петербург');
      expect(selectionSearchQuery('Иванов-\nПетров'), 'Иванов- Петров');
    });

    test('SNO-F-READ-01: слишком длинное обрезано по слову', () {
      final String long = List<String>.filled(60, 'слово').join(' ');
      final String query = selectionSearchQuery(long);
      expect(query.length, lessThanOrEqualTo(kSelectionQueryLimit));
      expect(query.endsWith('слово'), isTrue);
      expect(long.startsWith(query), isTrue);

      // Одно слово длиннее предела режется по пределу.
      final String solid = 'а' * 300;
      expect(selectionSearchQuery(solid).length, kSelectionQueryLimit);
      expect(selectionSearchQuery('абвгд еж', limit: 6), 'абвгд');
    });

    test('SNO-F-READ-01: пустое выделение даёт пустой запрос', () {
      expect(selectionSearchQuery(''), '');
      expect(selectionSearchQuery(' \n '), '');
      expect(isSearchableQuery(selectionSearchQuery(' я ')), isFalse);
    });

    test('SNO-F-READ-01: запрос находит то, что выделяли', () {
      // Текст страницы с переводом строки внутри фразы; выделенное —
      // тот же кусок, как его отдаёт просмотрщик.
      const String page = 'Плечевая кость,\r\nили humerus, — длинная.';
      const String selected = 'кость,\r\nили humerus';
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: page,
        query: selectionSearchQuery(selected),
      );
      expect(hits, hasLength(1));
      expect(hits.single.sourceStart, page.indexOf('кость'));
    });
  });

  group('SNO-F-READ-01: какое из найденного — место выделения', () {
    SearchHit hit(int page, int start, int end) {
      return SearchHit(
        pageNumber: page,
        sourceStart: start,
        sourceEnd: end,
        snippet: 'слово',
        snippetMatchStart: 0,
        snippetMatchEnd: 5,
      );
    }

    final List<SearchHit> hits = <SearchHit>[
      hit(2, 10, 15),
      hit(5, 3, 8),
      hit(5, 40, 45),
      hit(5, 90, 95),
      hit(7, 1, 6),
    ];

    test('SNO-F-READ-01: совпадение, пересекающееся с выделением', () {
      expect(hitIndexAt(hits, pageNumber: 5, start: 40, end: 45), 2);
      expect(hitIndexAt(hits, pageNumber: 5, start: 42, end: 60), 2);
      expect(hitIndexAt(hits, pageNumber: 5, start: 0, end: 4), 1);
    });

    test('SNO-F-READ-01: нет пересечения — ближайшее на странице', () {
      // Слово склеено из переноса: на своём месте оно не найдено.
      expect(hitIndexAt(hits, pageNumber: 5, start: 50, end: 60), 2);
      expect(hitIndexAt(hits, pageNumber: 5, start: 70, end: 80), 3);
      expect(hitIndexAt(hits, pageNumber: 5, start: 100, end: 110), 3);
    });

    test('SNO-F-READ-01: совпадение вплотную — не пересечение', () {
      // Кусок кончается там, где совпадение начинается.
      expect(hitIndexAt(hits, pageNumber: 5, start: 8, end: 40), 1);
    });

    test('SNO-F-READ-01: с другой страницы совпадение не берётся', () {
      expect(hitIndexAt(hits, pageNumber: 3, start: 0, end: 5), -1);
      expect(
        hitIndexAt(const <SearchHit>[], pageNumber: 1, start: 0, end: 5),
        -1,
      );
    });
  });
}
