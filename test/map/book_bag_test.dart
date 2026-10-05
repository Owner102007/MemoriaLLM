import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/search_text.dart';
import 'package:memoria/domain/map/book_bag.dart';

/// ALG-MAP-02: слова книги для карты.
///
/// Разбор текста на слова у карты свой — быстрый, — и он обязан давать
/// те же слова, что и разбор поиска: иначе карта и поиск по содержимому
/// разошлись бы в том, что считать одним словом.
void main() {
  group('ALG-MAP-02: разбор на слова', () {
    const List<String> samples = <String>[
      'Анатомия человека. Том 1: остеология, артрология, миология',
      'Сердечно-сосудистая система — артерии, вены и капилляры.',
      'ЁЖИК в тумане; ежик, Ёжики, ежиками',
      'voyna_i_mir(1).pdf  ВОЙНА И МИР',
      // Латинские буквы-двойники в русском слове: U+0041, U+0043.
      'Aртерия и Cосуд',
      'Число e ≈ 2,71828; предел (1 + 1/n)^n при n → ∞',
      'мягкий­перенос, неразрывный пробел, «кавычки» и тире —',
      'x² + y² = r², α-частица, β-распад, 𝔘 и 📖',
      '',
      '   ',
      '...---...',
    ];

    test('ALG-MAP-02: слова те же, что у разбора поиска', () {
      for (final String sample in samples) {
        expect(mapTokens(sample), searchTokens(sample), reason: sample);
      }
    });

    test('ALG-MAP-02: слово, разрезанное переносом, собирается целым', () {
      // U+0002 — знак, которым движок PDF отмечает перенос слова.
      const String page = 'остео\u0002логия изучает кости';
      expect(mapTokens(page), searchTokens('остеология изучает кости'));
      expect(mapTokens(page), isNot(contains(searchTokens('остео').single)));
    });

    test('ALG-MAP-02: короткие слова и числа в мешок не идут', () {
      expect(isBagToken('ab'), isFalse);
      expect(isBagToken('abc'), isTrue);
      expect(isBagToken('2019'), isFalse);
      expect(isBagToken('123456'), isFalse);
      expect(isBagToken('b12'), isTrue);
      expect(isBagToken('12b'), isTrue);
      expect(isBagToken(''), isFalse);
    });
  });

  group('ALG-MAP-02: мешок книги', () {
    Map<String, int> countsOf(BookBag bag) {
      return <String, int>{
        for (int i = 0; i < bag.terms.length; i++) bag.terms[i]: bag.counts[i],
      };
    }

    String word(String raw) => mapTokens(raw).single;

    test('ALG-MAP-02: слово названия весит втрое, автора — вдвое', () {
      final BookBag bag = bagOfBook(
        const BagRequest(
          key: 'hash-1',
          group: 'Ангиология',
          title: 'Сосуды',
          author: 'Привес',
          pages: <String>['Сосуды и нервы.', 'Нервы, сосуды, Привес.'],
        ),
      );
      final Map<String, int> counts = countsOf(bag);
      expect(counts[word('сосуды')], kBagTitleWeight + 2);
      expect(counts[word('привес')], kBagAuthorWeight + 1);
      expect(counts[word('нервы')], 2);
      expect(bag.key, 'hash-1');
      expect(bag.group, 'Ангиология');
      // Длина — все слова вместе с весами названия и автора.
      expect(bag.length, kBagTitleWeight + kBagAuthorWeight + 5);
    });

    test('ALG-MAP-02: слова мешка стоят по возрастанию', () {
      final BookBag bag = bagOfBook(
        const BagRequest(
          key: 'hash-1',
          group: '',
          title: 'Яблоко',
          pages: <String>['вишня абрикос груша вишня'],
        ),
      );
      final List<String> sorted = List<String>.of(bag.terms)..sort();
      expect(bag.terms, sorted);
      expect(bag.terms.toSet().length, bag.terms.length);
    });

    test('ALG-MAP-02: у скана без текста мешок из одного названия', () {
      final BookBag bag = bagOfBook(
        const BagRequest(
          key: 'hash-scan',
          group: 'Ангиология',
          title: 'Атлас сосудов',
          pages: <String>[],
        ),
      );
      expect(bag.terms, hasLength(2));
      expect(bag.length, 2 * kBagTitleWeight);
    });

    test('ALG-MAP-02: в мешке остаются самые частые слова', () {
      final BagBuilder builder = BagBuilder();
      // Двадцать слов: слово номер i встречается i раз.
      for (int i = 1; i <= 20; i++) {
        builder.add(List<String>.filled(i, 'слово${i + 100}').join(' '));
      }
      final BookBag bag = builder.build(key: 'k', group: '', limit: 5);
      expect(bag.terms, hasLength(5));
      expect(bag.counts.toSet(), <int>{16, 17, 18, 19, 20});
      // Длина считается по всем словам, а не по оставшимся.
      expect(bag.length, 210);
    });

    test('ALG-MAP-02: при равном счёте остаётся раннее по алфавиту', () {
      BookBag build(List<String> order) {
        final BagBuilder builder = BagBuilder();
        for (final String text in order) {
          builder.add(text);
        }
        return builder.build(key: 'k', group: '', limit: 2);
      }

      final BookBag one = build(<String>['груша', 'абрикос', 'вишня']);
      final BookBag two = build(<String>['вишня', 'груша', 'абрикос']);
      expect(one.terms, two.terms);
      expect(one.terms, <String>[word('абрикос'), word('вишня')]);
    });

    test('ALG-MAP-02: мешок не зависит от разбивки текста на страницы', () {
      const String text = 'артерия вена капилляр артерия сосуд вена артерия';
      final BookBag whole = bagOfBook(
        const BagRequest(key: 'k', group: '', title: 'т', pages: <String>[text]),
      );
      final BookBag split = bagOfBook(
        BagRequest(key: 'k', group: '', title: 'т', pages: text.split(' ')),
      );
      expect(split.terms, whole.terms);
      expect(split.counts, whole.counts);
      expect(split.length, whole.length);
    });
  });
}
