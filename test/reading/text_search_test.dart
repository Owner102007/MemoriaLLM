import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/text_search.dart';

void main() {
  group('SearchableText', () {
    test('схлопывает переносы и лишние пробелы', () {
      final SearchableText prepared = SearchableText.of(
        '  Пиковая\r\n  дама\t\tи   тройка  ',
      );
      expect(prepared.text, 'Пиковая дама и тройка');
    });

    test('помнит, откуда взялся каждый символ', () {
      const String raw = 'аб\r\nвг';
      final SearchableText prepared = SearchableText.of(raw);
      expect(prepared.text, 'аб вг');
      expect(raw[prepared.sourceOf(0)], 'а');
      expect(raw[prepared.sourceOf(3)], 'в');
      expect(raw[prepared.sourceOf(4)], 'г');
    });

    test('текст из одних пробелов схлопывается в пустоту', () {
      expect(SearchableText.of('   \n\t ').text, '');
    });
  });

  group('isSearchableQuery', () {
    test('одного символа мало, двух достаточно', () {
      expect(isSearchableQuery('а'), isFalse);
      expect(isSearchableQuery('  а  '), isFalse);
      expect(isSearchableQuery(''), isFalse);
      expect(isSearchableQuery('аб'), isTrue);
    });
  });

  group('findInPageText', () {
    test('находит слово и показывает его в контексте', () {
      final List<SearchHit> hits = findInPageText(
        pageNumber: 7,
        pageText: 'Германн стоял у окна. Германн молчал.',
        query: 'Германн',
      );
      expect(hits.length, 2);
      expect(hits.first.pageNumber, 7);
      expect(hits.first.matchedText, 'Германн');
      expect(hits.first.snippet, contains('стоял у окна'));
    });

    test('фраза находится через перенос строки', () {
      // Ради этого текст и нормализуется: в PDF перенос строки стоит
      // ровно там, где кончилась строка на бумаге, а не там, где кончилась
      // мысль.
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: 'три карты,\r\nтри карты, три карты',
        query: 'карты, три',
      );
      expect(hits.length, 2);
    });

    test('регистр по умолчанию не важен, но его можно потребовать', () {
      const String text = 'Тройка, семёрка, туз. тройка';
      expect(
        findInPageText(pageNumber: 1, pageText: text, query: 'тройка').length,
        2,
      );
      expect(
        findInPageText(
          pageNumber: 1,
          pageText: text,
          query: 'тройка',
          caseSensitive: true,
        ).length,
        1,
      );
    });

    test('совпадения не накладываются друг на друга', () {
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: 'аааа',
        query: 'аа',
      );
      expect(hits.length, 2);
      expect(hits[0].sourceEnd, lessThanOrEqualTo(hits[1].sourceStart));
    });

    test('координаты указывают в исходный текст, а не в схлопнутый', () {
      const String text = 'начало\r\n\r\n   искомое слово';
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'искомое',
      );
      expect(
        text.substring(hits.single.sourceStart, hits.single.sourceEnd),
        'искомое',
      );
    });

    test('многоточия появляются только там, где текст обрезан', () {
      final String long = 'x' * 200;
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: '$long ЦЕЛЬ $long',
        query: 'ЦЕЛЬ',
      );
      expect(hits.single.snippet.startsWith('…'), isTrue);
      expect(hits.single.snippet.endsWith('…'), isTrue);

      final List<SearchHit> short = findInPageText(
        pageNumber: 1,
        pageText: 'ЦЕЛЬ',
        query: 'ЦЕЛЬ',
      );
      expect(short.single.snippet, 'ЦЕЛЬ');
    });

    test('подсветка внутри фрагмента указывает на само совпадение', () {
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: 'слева ЦЕЛЬ справа',
        query: 'ЦЕЛЬ',
      );
      final SearchHit hit = hits.single;
      expect(
        hit.snippet.substring(hit.snippetMatchStart, hit.snippetMatchEnd),
        'ЦЕЛЬ',
      );
    });

    test('предел совпадений соблюдается', () {
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: 'аб ' * 100,
        query: 'аб',
        limit: 5,
      );
      expect(hits.length, 5);
    });

    test('пустая страница и пустой запрос ничего не находят', () {
      expect(
        findInPageText(pageNumber: 1, pageText: '', query: 'что-то'),
        isEmpty,
      );
      expect(
        findInPageText(pageNumber: 1, pageText: 'текст', query: '   '),
        isEmpty,
      );
    });
  });
}
