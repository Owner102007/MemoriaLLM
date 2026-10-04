import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/selection_query.dart';
import 'package:memoria/domain/reading/text_search.dart';

/// SNO-F-READ-01: «Найти в книге» — запросы из выделенного и место
/// выделения среди найденного.
void main() {
  /// Знак, который движок ставит на месте дефиса переноса.
  final String mark = String.fromCharCode(kLineBreakHyphen);

  /// Слово, разрезанное переносом: между частями стоит знак движка.
  String cut(String head, String tail) => '$head$mark$tail';

  group('SNO-F-READ-01: запросы из выделенного', () {
    test('SNO-F-READ-01: края и лишние пробелы убраны', () {
      expect(selectionSearchQueries('  остеология  '), <String>['остеология']);
      expect(
        selectionSearchQueries('плечевая\r\nкость\n\nи  лопатка'),
        <String>['плечевая кость и лопатка'],
      );
      expect(selectionSearchQueries('плечевая\u00A0кость'), <String>[
        'плечевая кость',
      ]);
    });

    test('SNO-F-READ-01: дефис в выделенном остаётся дефисом', () {
      expect(selectionSearchQueries('что-то'), <String>['что-то']);
      expect(selectionSearchQueries('кость - длинная'), <String>[
        'кость - длинная',
      ]);
      // Тире в конце строки с переводом строки после него — не перенос.
      expect(selectionSearchQueries('1998 -\r\n2001'), <String>['1998 - 2001']);
    });

    test('SNO-F-READ-01: слово с переноса ищется с дефисом и слитно', () {
      // По тексту не узнать, перенос это или дефис составного слова.
      // С дефисом — первым: обычное слово так не найдётся нигде, и
      // поиск перейдёт к слитному.
      expect(selectionSearchQueries(cut('остео', 'логия')), <String>[
        'остео-логия',
        'остеология',
      ]);
      expect(
        selectionSearchQueries('${cut('сердечно', 'сосудистая')} система'),
        <String>['сердечно-сосудистая система', 'сердечнососудистая система'],
      );
      expect(selectionSearchQueries(cut('Санкт', 'Петербург')), <String>[
        'Санкт-Петербург',
        'СанктПетербург',
      ]);
    });

    test('SNO-F-READ-01: знак переноса на краю выделенного отброшен', () {
      // Выделили слово до конца строки или с начала следующей: резать
      // здесь нечего, и запрос один.
      expect(selectionSearchQueries('остео$mark'), <String>['остео']);
      expect(selectionSearchQueries(cut('', 'логия')), <String>['логия']);
      expect(selectionSearchQueries(' $mark '), isEmpty);
    });

    test('SNO-F-READ-01: знака переноса в запросах нет', () {
      final List<String> queries = selectionSearchQueries(
        'строение ${cut('остео', 'логии')} и '
        '${cut('сердечно', 'сосудистой')} системы',
      );
      expect(queries, hasLength(2));
      for (final String query in queries) {
        expect(query.contains(mark), isFalse, reason: query);
      }
    });

    test('SNO-F-READ-01: слишком длинное обрезано по слову', () {
      final String long = List<String>.filled(60, 'слово').join(' ');
      final String query = selectionSearchQueries(long).single;
      expect(query.length, lessThanOrEqualTo(kSelectionQueryLimit));
      expect(query.endsWith('слово'), isTrue);
      expect(long.startsWith(query), isTrue);

      // Одно слово длиннее предела режется по пределу.
      final String solid = 'а' * 300;
      expect(selectionSearchQueries(solid).single.length, kSelectionQueryLimit);
      expect(selectionSearchQueries('абвгд еж', limit: 6), <String>['абвгд']);
    });

    test('SNO-F-READ-01: предел на границе слова слов не теряет', () {
      const String text = 'ааа ббб ввв';
      expect(selectionSearchQueries(text, limit: 7), <String>['ааа ббб']);
      expect(selectionSearchQueries(text, limit: 8), <String>['ааа ббб']);
      expect(selectionSearchQueries(text, limit: 6), <String>['ааа']);
      expect(selectionSearchQueries(text, limit: 0), isEmpty);
    });

    test('SNO-F-READ-01: пустое выделение запросов не даёт', () {
      expect(selectionSearchQueries(''), isEmpty);
      expect(selectionSearchQueries(' \n '), isEmpty);
      expect(isSearchableQuery(selectionSearchQueries(' я ').single), isFalse);
    });

    test('SNO-F-READ-01: запрос находит то, что выделяли', () {
      // Текст страницы с переводом строки внутри фразы; выделенное —
      // тот же кусок, как его отдаёт просмотрщик.
      const String page = 'Плечевая кость,\r\nили humerus, — длинная.';
      const String selected = 'кость,\nили humerus';
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: page,
        query: selectionSearchQueries(selected).single,
      );
      expect(hits, hasLength(1));
      expect(hits.single.sourceStart, page.indexOf('кость'));
    });

    test('SNO-F-READ-01: слитный запрос находит и само слово с переноса', () {
      // Слово разрезано переносом, а ниже по странице написано целиком.
      final String page =
          'Строение ${cut('остео', 'логии')}.\r\nОстеология — наука о костях.';
      final String selected = cut('остео', 'логии');
      final int at = page.indexOf(selected);
      final List<String> queries = selectionSearchQueries(selected);
      List<SearchHit> find(String query) {
        return findInPageText(pageNumber: 1, pageText: page, query: query);
      }

      // С дефисом слово не написано нигде — поиск перейдёт к слитному.
      expect(find(queries.first), isEmpty);
      final List<SearchHit> hits = find(queries.last);
      expect(hits, hasLength(1));
      // Найденное — то самое место, которое выделяли.
      expect(
        hitIndexAt(hits, pageNumber: 1, start: at, end: at + selected.length),
        0,
      );
      expect(find('остеологи'), hasLength(2));
    });

    test('SNO-F-READ-01: составное слово с переноса находится с дефисом', () {
      final String page =
          'Болезни ${cut('сердечно', 'сосудистой')} системы.\r\n'
          'Сердечно-сосудистая система и сердечно-сосудистые болезни.';
      final List<String> queries = selectionSearchQueries(
        cut('сердечно', 'сосудист'),
      );
      List<SearchHit> find(String query) {
        return findInPageText(pageNumber: 1, pageText: page, query: query);
      }

      // С дефисом находятся остальные места, слитно — только свой.
      expect(find(queries.first), hasLength(2));
      expect(find(queries.last), hasLength(1));
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
      // На своём месте не найдено — уводить читателя в другую полосу
      // страницы незачем.
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
