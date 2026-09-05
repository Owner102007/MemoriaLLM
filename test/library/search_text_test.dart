import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/search_text.dart';

/// Нормализация запросов и текста для поиска по книгам устройства.
///
/// Главное здесь — свёртка латинских двойников в кириллице. Без неё
/// половина сканов не находится по собственному названию: `ВОЙНА`,
/// набранное с латинскими `B`, `O`, `H`, `A`, выглядит на экране в
/// точности как настоящее, а совпадает с ним нулём символов.
void main() {
  group('свёртка похожих букв', () {
    test('латинские двойники и кириллица сходятся', () {
      // Слева — латинские B, O, N?.. нет: латинские B, O, H, A.
      const String spoofed = 'BOЙHA';
      const String honest = 'ВОЙНА';
      expect(foldSearchText(spoofed), foldSearchText(honest));
    });

    test('все пять названных владельцем букв свёрнуты', () {
      for (final List<String> pair in <List<String>>[
        <String>['А', 'A'],
        <String>['О', 'O'],
        <String>['Е', 'E'],
        <String>['С', 'C'],
        <String>['Р', 'P'],
      ]) {
        expect(
          foldSearchText(pair[0]),
          foldSearchText(pair[1]),
          reason: '${pair[0]} и ${pair[1]} обязаны совпасть',
        );
      }
    });

    test('ё и е — одна буква', () {
      expect(foldSearchText('Ёжик'), foldSearchText('ежик'));
      expect(foldSearchText('всё'), foldSearchText('все'));
    });

    test('регистр не имеет значения', () {
      expect(foldSearchText('Пиковая ДАМА'), foldSearchText('пиковая дама'));
    });

    test('буквы без двойников остаются собой', () {
      // `и`, `й`, `ж`, `ш` похожего в латинице не имеют, и трогать их
      // незачем: лишняя свёртка — это лишние совпадения.
      expect(foldSearchText('жий'), 'жий');
    });
  });

  group('слова', () {
    test('имя файла распадается на слова', () {
      expect(searchTokens('voyna_i_mir(1).pdf', stem: false), <String>[
        'voyna',
        'i',
        'mir',
        '1',
        'pdf',
      ]);
    });

    test('пустая строка не даёт слов', () {
      expect(searchTokens('   '), isEmpty);
      expect(searchTokens('...'), isEmpty);
    });

    test('стеммер сводит падежи', () {
      expect(
        stemFolded(foldSearchText('книги')),
        stemFolded(foldSearchText('книга')),
      );
      expect(
        stemFolded(foldSearchText('учебники')),
        stemFolded(foldSearchText('учебника')),
      );
    });

    test('короткое слово не обрезается', () {
      // У `дом` снять `о` значит превратить его в `дм`.
      expect(stemFolded(foldSearchText('дом')), foldSearchText('дом'));
      expect(stemFolded(foldSearchText('мир')), foldSearchText('мир'));
    });

    test('от слова остаётся не меньше трёх букв', () {
      for (final String word in <String>[
        'книга',
        'ученик',
        'память',
        'слово',
        'история',
      ]) {
        final String stem = stemFolded(foldSearchText(word));
        expect(stem.length, greaterThanOrEqualTo(3));
      }
    });
  });

  group('запрос к индексу', () {
    test('пустой запрос не строится', () {
      expect(ftsQueryFor(''), '');
      expect(ftsQueryFor(' - '), '');
    });

    test('последнее слово ищется по началу', () {
      // Читатель, набравший «войн», ищет «войну», а не ошибку синтаксиса.
      expect(ftsQueryFor('войн'), endsWith('*'));
    });

    test('слова соединяются через AND', () {
      final String query = ftsQueryFor('война и мир');
      expect(query, contains(' AND '));
      expect('AND'.allMatches(query).length, 2);
    });

    test('в запрос не утекает пунктуация', () {
      expect(ftsQueryFor('война: "мир"'), isNot(contains(':')));
      expect(ftsQueryFor("d'artagnan"), isNot(contains("'")));
    });
  });

  group('опечатки', () {
    test('одна буква не та — строки всё ещё похожи', () {
      expect(
        trigramSimilarity('Достаевский', 'Достоевский'),
        greaterThan(0.34),
      );
    });

    test('разные слова не похожи', () {
      expect(trigramSimilarity('Достоевский', 'Гладиатор'), lessThan(0.2));
    });

    test('пустая строка ни на что не похожа', () {
      expect(trigramSimilarity('', 'Достоевский'), 0);
      expect(trigramSimilarity('Достоевский', '   '), 0);
    });

    test('строка похожа сама на себя ровно на единицу', () {
      expect(trigramSimilarity('Онегин', 'онегин'), 1);
    });

    test('опечатка в первой букве тоже видна', () {
      // Ради этого строка обрамляется пробелами: иначе начало слова
      // весило бы меньше середины.
      expect(trigramSimilarity('Пнегин', 'Онегин'), greaterThan(0.34));
    });
  });
}
