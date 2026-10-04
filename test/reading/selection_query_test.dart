import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/selection_query.dart';
import 'package:memoria/domain/reading/text_search.dart';

/// SNO-F-READ-01: «Найти в книге» — запросы из выделенного и место
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
      // Без разрезанных слов запрос один.
      expect(selectionSearchQueries('плечевая\nкость'), <String>[
        'плечевая кость',
      ]);
    });

    test('SNO-F-READ-01: слово, разрезанное переносом, склеено', () {
      expect(selectionSearchQuery('остео-\nлогия'), 'остеология');
      expect(selectionSearchQuery('остео- \r\n  логия'), 'остеология');
      expect(selectionSearchQuery('micro-\nscope'), 'microscope');
      expect(selectionSearchQuery('остео\u00AD\nлогия'), 'остеология');
    });

    test('SNO-F-READ-01: запасные запросы — с дефисом и как выделено', () {
      // По тексту не узнать, перенос это или дефис составного слова:
      // склеенное не нашлось — ищется с дефисом, потом как выделено.
      expect(selectionSearchQueries('остео-\nлогия'), <String>[
        'остеология',
        'остео-логия',
        'остео- логия',
      ]);
      expect(selectionSearchQueries('сердечно-\nсосудистая система'), <String>[
        'сердечнососудистая система',
        'сердечно-сосудистая система',
        'сердечно- сосудистая система',
      ]);
    });

    test('SNO-F-READ-01: дефис внутри строки остаётся дефисом', () {
      expect(selectionSearchQueries('что-то'), <String>['что-то']);
      expect(selectionSearchQueries('кость - длинная'), <String>[
        'кость - длинная',
      ]);
    });

    test('SNO-F-READ-01: заглавная после переноса — это новое слово', () {
      // Не склеивается, но дефис без перевода строки — первым.
      expect(selectionSearchQueries('Санкт-\nПетербург'), <String>[
        'Санкт-Петербург',
        'Санкт- Петербург',
      ]);
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

    test('SNO-F-READ-01: предел на границе слова слов не теряет', () {
      expect(selectionSearchQuery('ааа ббб ввв', limit: 7), 'ааа ббб');
      expect(selectionSearchQuery('ааа ббб ввв', limit: 8), 'ааа ббб');
      expect(selectionSearchQuery('ааа ббб ввв', limit: 6), 'ааа');
    });

    test('SNO-F-READ-01: пустое выделение запросов не даёт', () {
      expect(selectionSearchQueries(''), isEmpty);
      expect(selectionSearchQueries(' \n '), isEmpty);
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

    test('SNO-F-READ-01: «как выделено» находит разрезанное слово', () {
      // Последний из запросов обязан найти само выделенное место — что
      // бы ни стояло на переносе.
      const String page = 'Строение сердечно-\nсосудистой системы.';
      const String selected = 'сердечно-\nсосудистой';
      final List<String> queries = selectionSearchQueries(selected);
      List<SearchHit> find(String query) {
        return findInPageText(pageNumber: 1, pageText: page, query: query);
      }

      expect(find(queries.first), isEmpty);
      expect(find(queries.last), hasLength(1));
      expect(find(queries.last).single.sourceStart, page.indexOf('сердечно'));
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

    test('SNO-F-READ-01: соседнее совпадение на странице не берётся', () {
      // Слово склеено из переноса: на своём месте оно не найдено, а
      // уводить читателя в другую полосу страницы незачем.
      expect(hitIndexAt(hits, pageNumber: 5, start: 50, end: 60), -1);
      expect(hitIndexAt(hits, pageNumber: 5, start: 100, end: 110), -1);
    });

    test('SNO-F-READ-01: совпадение вплотную — не пересечение', () {
      // Кусок кончается там, где совпадение начинается.
      expect(hitIndexAt(hits, pageNumber: 5, start: 8, end: 40), -1);
    });

    test('SNO-F-READ-01: с другой страницы совпадение не берётся', () {
      expect(hitIndexAt(hits, pageNumber: 3, start: 0, end: 5), -1);
      expect(hitIndexAt(hits, pageNumber: 2, start: 3, end: 8), -1);
      expect(
        hitIndexAt(const <SearchHit>[], pageNumber: 1, start: 0, end: 5),
        -1,
      );
    });
  });
}
