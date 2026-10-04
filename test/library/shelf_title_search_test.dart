import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/search_text.dart';
import 'package:memoria/domain/library/shelf_title_search.dart';

import '../data/test_data.dart';

/// SNO-ALG-LIB-01: поиск по названию на полке.
///
/// Чистые функции над названиями: что находится, в каком порядке стоит
/// и что в названии подсвечено.
void main() {
  Book book(String id, String title) {
    return testBook(id: id, title: title, hash: 'hash-$id');
  }

  List<String> found(String query, List<Book> books) {
    return <String>[
      for (final ShelfTitleHit hit in searchShelfTitles(
        query: query,
        books: books,
      ))
        hit.book.id,
    ];
  }

  /// Подсвеченное — словами исходного названия.
  List<String> marked(ShelfTitleHit hit) {
    return <String>[
      for (final TitleSpan span in hit.spans)
        hit.book.title.substring(span.start, span.end),
    ];
  }

  final List<Book> shelf = <Book>[
    book('pat', 'Патанатомия'),
    book('prives', 'Привес М. Г. Анатомия человека'),
    book('hist', 'Гистология. Атлас'),
    book('sin', 'Синельников. Атлас анатомии, том 1'),
    book('ezh', 'Ёжик в тумане'),
    book('heart', 'Сердце и сосуды'),
  ];

  group('SNO-ALG-LIB-01: что находится', () {
    test('SNO-ALG-LIB-01: набранное ищется подстрокой, без регистра', () {
      expect(found('ГИСТ', shelf), <String>['hist']);
      expect(found('олог', shelf), <String>['hist']);
    });

    test('SNO-ALG-LIB-01: «е» и «ё» не различаются', () {
      expect(found('ежик', shelf), <String>['ezh']);
      expect(found('ёжик', shelf), <String>['ezh']);
      expect(found('сёрдце', shelf), <String>['heart']);
    });

    test('SNO-ALG-LIB-01: латинская буква-двойник не мешает', () {
      // Латинские буквы записаны кодами: на глаз их от русских не
      // отличить. U+0063, U+0065 и U+0070 — строчные «c», «e» и «p»,
      // U+0043, U+0045 и U+0050 — они же заглавные.
      const List<String> typed = <String>[
        '\u0063ердце',
        '\u0063\u0065\u0070дц\u0065',
        '\u0043\u0045\u0050ДЦ\u0045',
      ];
      final List<ShelfTitleHit> cyrillic = searchShelfTitles(
        query: 'сердце',
        books: shelf,
      );
      expect(cyrillic.single.book.id, 'heart');
      for (final String query in typed) {
        final List<ShelfTitleHit> latin = searchShelfTitles(
          query: query,
          books: shelf,
        );
        expect(latin.single.book.id, 'heart', reason: query);
        expect(latin.single.spans, cyrillic.single.spans, reason: query);
      }
    });

    test('SNO-ALG-LIB-01: название с латиницей находится кириллицей', () {
      // Скан после распознавания: «Сердце» с латинскими «C» и «e».
      final List<Book> scans = <Book>[
        book('scan', '\u0043ердц\u0065 и сосуды'),
      ];
      expect(found('сердце', scans), <String>['scan']);
    });

    test('SNO-ALG-LIB-01: каждое слово запроса должно быть в названии', () {
      expect(found('анатомия привес', shelf), <String>['prives']);
      expect(found('привес анатомия', shelf), <String>['prives']);
      expect(found('атлас гист', shelf), <String>['hist']);
      expect(found('атлас физиология', shelf), isEmpty);
    });

    test('SNO-ALG-LIB-01: знаки в запросе — разделители, а не буквы', () {
      expect(found('привес, анатомия!', shelf), <String>['prives']);
      expect(found('«атлас» — том', shelf), <String>['sin']);
    });

    test('SNO-ALG-LIB-01: пустой запрос и одни знаки не находят ничего', () {
      expect(found('', shelf), isEmpty);
      expect(found('   ', shelf), isEmpty);
      expect(found('«—»…', shelf), isEmpty);
      expect(titleQueryWords(' ., '), isEmpty);
    });

    test('SNO-ALG-LIB-01: окончания не снимаются', () {
      // Стеммер нашёл бы «анатомии» по «анатомия»; подстрока — нет.
      expect(found('анатомия', shelf), <String>['prives', 'pat']);
      expect(found('анатоми', shelf), <String>['prives', 'sin', 'pat']);
    });
  });

  group('SNO-ALG-LIB-01: в каком порядке', () {
    test('SNO-ALG-LIB-01: начало слова выше середины слова', () {
      // «Патанатомия» стоит на полке первой, но набранное в ней —
      // внутри слова.
      expect(found('анат', shelf), <String>['prives', 'sin', 'pat']);
      final List<ShelfTitleHit> hits = searchShelfTitles(
        query: 'анат',
        books: shelf,
      );
      expect(hits.first.rank, kTitleWordStartRank);
      expect(hits.last.rank, kTitleInsideRank);
    });

    test('SNO-ALG-LIB-01: при равном весе — порядок полки', () {
      expect(found('атлас', shelf), <String>['hist', 'sin']);
      expect(found('атлас', shelf.reversed.toList()), <String>['sin', 'hist']);
    });

    test('SNO-ALG-LIB-01: вес складывается по словам запроса', () {
      final List<Book> books = <Book>[
        book('inside', 'Патанатомия: податлас'),
        book('mixed', 'Патанатомия. Атлас'),
        book('starts', 'Анатомия. Атлас'),
      ];
      expect(found('анат атлас', books), <String>['starts', 'mixed', 'inside']);
    });
  });

  group('SNO-ALG-LIB-01: что подсвечено', () {
    test('SNO-ALG-LIB-01: подсветка стоит в исходном названии', () {
      final ShelfTitleHit hit = searchShelfTitles(
        query: 'прив анат',
        books: shelf,
      ).single;
      expect(marked(hit), <String>['Прив', 'Анат']);
    });

    test('SNO-ALG-LIB-01: подсвечено написанное, а не набранное', () {
      final ShelfTitleHit hit = searchShelfTitles(
        query: 'ежик',
        books: shelf,
      ).single;
      expect(marked(hit), <String>['Ёжик']);
    });

    test('SNO-ALG-LIB-01: все вхождения слова подсвечены', () {
      final ShelfTitleHit hit = matchShelfTitle(
        book('twice', 'Атлас и ещё атлас'),
        titleQueryWords('атлас'),
      )!;
      expect(marked(hit), <String>['Атлас', 'атлас']);
    });

    test('SNO-ALG-LIB-01: наложившиеся куски склеены в один', () {
      final ShelfTitleHit hit = matchShelfTitle(
        book('aaa', 'ааа'),
        titleQueryWords('аа а'),
      )!;
      expect(hit.spans, <TitleSpan>[const TitleSpan(0, 3)]);
    });

    test('SNO-ALG-LIB-01: свёртка не меняет длины названия', () {
      const List<String> titles = <String>[
        'Ёлка',
        'Привес М. Г. Анатомия человека',
        'İstanbul: путеводитель',
        'ΣΟΦΙΑ',
        'Книга 📚 с картинкой',
        'voyna_i_mir(1)',
      ];
      for (final String title in titles) {
        expect(foldShelfTitle(title).length, title.length, reason: title);
      }
    });

    test('SNO-ALG-LIB-01: свёртка та же, что у поиска по устройству', () {
      // Одно правило на оба поиска: то, что находится там, находится и
      // здесь.
      const List<String> titles = <String>[
        'Привес М. Г. Анатомия человека',
        'ВОЙНА И МИР',
        'Ёжик в тумане',
        'Sobotta. Atlas der Anatomie',
      ];
      for (final String title in titles) {
        expect(foldShelfTitle(title), foldSearchText(title), reason: title);
      }
    });
  });
}
