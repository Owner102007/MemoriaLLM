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

    test('F-TEXT-04: ё и е не различаются', () {
      const String text = 'Ребёнок спал. РЕБЕНОК проснулся.';
      final List<SearchHit> plain = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'ребенок',
      );
      expect(plain.length, 2);
      expect(plain.first.matchedText, 'Ребёнок', reason: 'показан как в книге');
      expect(
        findInPageText(pageNumber: 1, pageText: text, query: 'ребёнок').length,
        2,
      );
    });

    test('F-TEXT-04: буквы-двойники в распознанном слове находятся', () {
      // «сердце» с латинскими c, e, p на месте кириллических: так текст
      // выходит из распознавания, и на экране разницы не видно.
      const String text = 'Левое cepдцe и правое сердце.';
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'сердце',
      );
      expect(hits.length, 2);
      expect(hits.first.matchedText, 'cepдцe');
      expect(
        text.substring(hits.first.sourceStart, hits.first.sourceEnd),
        'cepдцe',
        reason: 'место совпадения — в исходном тексте',
      );
      expect(hits.last.matchedText, 'сердце');
    });

    test('F-TEXT-04: слово другого алфавита двойниками не находится', () {
      // Без этого «рот» находился бы в hypothesis, а «вас» — в bacillus:
      // в учебнике с латинскими терминами — на каждой странице.
      const String text = 'The hypothesis: Bacillus potential. Открыл рот.';
      final List<SearchHit> mouth = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'рот',
      );
      expect(mouth.length, 1);
      expect(mouth.single.matchedText, 'рот');
      expect(
        findInPageText(pageNumber: 1, pageText: text, query: 'вас'),
        isEmpty,
      );
      // И в обратную сторону: латинский запрос в кириллическом слове
      // «рот» не находится — только там, где pot написано латиницей.
      final List<SearchHit> latin = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'pot',
      );
      expect(
        <String>[for (final SearchHit hit in latin) hit.matchedText],
        <String>['pot', 'pot'],
        reason: 'hypothesis и potential',
      );
      expect(latin.last.sourceEnd, lessThan(text.indexOf('рот')));
    });

    test('F-TEXT-04: за отвергнутым совпадением находится настоящее', () {
      // «сос» по двойникам совпадает с латинским coc в cocos, а следом
      // стоит настоящее слово.
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: 'cocos сосна',
        query: 'сос',
      );
      expect(hits.single.matchedText, 'сос');
      expect(hits.single.sourceStart, 6);
    });

    test('F-TEXT-04: регистр с учётом — без ё/е и без двойников', () {
      const String text = 'Ребёнок и cepдцe';
      expect(
        findInPageText(
          pageNumber: 1,
          pageText: text,
          query: 'Ребенок',
          caseSensitive: true,
        ),
        isEmpty,
      );
      expect(
        findInPageText(
          pageNumber: 1,
          pageText: text,
          query: 'сердце',
          caseSensitive: true,
        ),
        isEmpty,
      );
    });

    test('F-TEXT-04: все виды текста одной длины', () {
      // У «İ» нижний регистр длиннее верхнего. Место совпадения после
      // такой буквы обязано остаться местом в исходном тексте.
      const String text = 'İstanbul — ЁЛКА и Ёж';
      expect(plainSearchText(text).length, text.length);
      expect(foldedSearchText(plainSearchText(text)).length, text.length);
      expect(plainSearchText('ЁЛКА'), 'елка');
      expect(foldedSearchText('сорт'), 'copt');

      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'елка',
      );
      expect(
        text.substring(hits.single.sourceStart, hits.single.sourceEnd),
        'ЁЛКА',
      );
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

  group('BUG-50: слово, разрезанное переносом в конце строки', () {
    // На месте дефиса переноса движок ставит служебный знак U+0002, а
    // перевода строки после него нет (корпус, `hyphen_breaks.pdf`).
    final String mark = String.fromCharCode(0x02);
    // Слово, разрезанное переносом: между частями стоит знак движка.
    String cut(String head, String tail) => '$head$mark$tail';
    final String page =
        'Строение ${cut('остео', 'логии')} и сердца.\r\n'
        'Остеология — наука о костях.';

    List<SearchHit> find(String query) {
      return findInPageText(pageNumber: 1, pageText: page, query: query);
    }

    test('BUG-50: набранное слово находится и на переносе', () {
      final List<SearchHit> hits = find('остеологи');
      expect(hits, hasLength(2));
      // Первое совпадение лежит поверх знака переноса: в исходном тексте
      // оно захватывает слово целиком, вместе со знаком.
      final SearchHit broken = hits.first;
      expect(
        page.substring(broken.sourceStart, broken.sourceEnd),
        cut('остео', 'логи'),
      );
    });

    test('BUG-50: в отрывке слово показано целым, без знака', () {
      final SearchHit broken = find('остеологи').first;
      expect(broken.matchedText, 'остеологи');
      expect(broken.snippet.contains(mark), isFalse);
      expect(broken.snippet, contains('Строение остеологии и сердца.'));
    });

    test('BUG-50: знак переноса в запросе ничего не меняет', () {
      // Запрос из выделенного может принести знак с собой.
      final List<SearchHit> typed = find('остеологии');
      final List<SearchHit> selected = find(cut('остео', 'логии'));
      expect(typed, hasLength(1));
      expect(selected, typed);
    });

    test('BUG-50: совпадение рядом со знаком его не захватывает', () {
      final int at = page.indexOf(mark);
      final SearchHit before = find('остео').first;
      expect(before.sourceEnd, at);
      final SearchHit after = find('логии').single;
      expect(after.sourceStart, at + 1);
    });

    test('BUG-50: страница без знака ищется как прежде', () {
      const String plain = 'Остео-логии нет, остеология есть.';
      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: plain,
        query: 'остеология',
      );
      expect(hits, hasLength(1));
      expect(hits.single.sourceStart, plain.indexOf('остеология'));
    });
  });
}
