/// Созвездия карты и их имена (F-MAP-16, ALG-MAP-16, F-MAP-03, ALG-MAP-10).
///
/// Сверка с другой реализацией до бита — в `book_map_golden_test.dart`.
/// Здесь — свойства правила: что выходит на краях, на большой библиотеке
/// с известным ответом, и что имя созвездия — характерное слово, а не
/// просто частое.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/exact_math.dart';
import 'package:memoria/domain/map/map_categories.dart';
import 'package:memoria/domain/map/map_names.dart';
import 'package:memoria/domain/map/map_vectors.dart';

/// Созвездия по строкам книг: матрица Грама — как в расчёте карты.
List<int> _labels(
  List<SparseRow> rows, {
  List<int>? order,
  Map<int, int> pinned = const <int, int>{},
}) => artCategories(
  gramOf(rows),
  rows.length,
  order: order,
  pinned: pinned,
).labels;

/// Мешок из словаря «слово → сколько раз».
BookBag _bag(String key, Map<String, int> words, {List<String>? forms}) {
  final List<String> terms = words.keys.toList()..sort();
  int length = 0;
  for (final int count in words.values) {
    length += count;
  }
  return BookBag(
    key: key,
    group: '',
    terms: terms,
    counts: <int>[for (final String term in terms) words[term]!],
    length: length,
    forms: forms,
  );
}

/// Составная библиотека: [sections] разделов по [topics] тем, в теме —
/// [books] книг. У книги слова фона (общие для всех), своего раздела,
/// своей темы и свои; немного слов чужого раздела.
///
/// Доли и размеры — по подбору шага 45 (литература СНО2026): тема 6 %,
/// раздел 5 %, фон 80 %, свои 5 %, чужой раздел 4 %; слово фона берётся
/// со степенью 3 — частые слова языка, слово темы и раздела — равномерно.
List<BookBag> _library({
  int sections = 6,
  int topics = 4,
  int books = 10,
  int seed = 2026,
}) {
  final MapRandom random = MapRandom(seed);
  final List<BookBag> out = <BookBag>[];
  int number = 0;
  for (int s = 0; s < sections; s++) {
    for (int t = 0; t < topics; t++) {
      for (int b = 0; b < books; b++) {
        final Map<String, int> words = <String, int>{};
        void draw(String prefix, int size, int times, {bool skew = false}) {
          for (int i = 0; i < times; i++) {
            double share = random.unit();
            if (skew) {
              share = share * share * share;
            }
            final String word = '$prefix${(size * share).floor()}';
            words[word] = (words[word] ?? 0) + 1;
          }
        }

        // Длина книги — 2500·2^(1,5u) слов, как у настоящих (2^(1,5u)
        // приближено отрезком от 1 до 2,8).
        final int length = (2500 * (1 + random.unit() * 1.8)).floor();
        draw('фон', 4000, length * 80 ~/ 100, skew: true);
        draw('раздел${s}_', 800, length * 5 ~/ 100);
        draw('тема${s}_${t}_', 1000, length * 6 ~/ 100);
        draw('книга${number}_', 60, length * 5 ~/ 100);
        draw(
          'раздел${(s + 1 + random.below(sections - 1)) % sections}_',
          800,
          length * 4 ~/ 100,
        );
        out.add(_bag('b${number.toString().padLeft(4, '0')}', words));
        number++;
      }
    }
  }
  return out;
}

/// Скорректированный индекс Рэнда (Hubert, Arabie, 1985): 1 — разбиения
/// совпадают, 0 — как случайные.
double _ari(List<int> a, List<int> b) {
  final Map<String, int> table = <String, int>{};
  final Map<int, int> rowSum = <int, int>{};
  final Map<int, int> colSum = <int, int>{};
  for (int i = 0; i < a.length; i++) {
    table['${a[i]}:${b[i]}'] = (table['${a[i]}:${b[i]}'] ?? 0) + 1;
    rowSum[a[i]] = (rowSum[a[i]] ?? 0) + 1;
    colSum[b[i]] = (colSum[b[i]] ?? 0) + 1;
  }
  double pairs(int x) => x * (x - 1) / 2;
  double index = 0;
  for (final int v in table.values) {
    index += pairs(v);
  }
  double sa = 0;
  for (final int v in rowSum.values) {
    sa += pairs(v);
  }
  double sb = 0;
  for (final int v in colSum.values) {
    sb += pairs(v);
  }
  final double total = pairs(a.length);
  final double expected = sa * sb / total;
  final double top = (sa + sb) / 2;
  if (top == expected) {
    return 1;
  }
  return (index - expected) / (top - expected);
}

void main() {
  group('ALG-MAP-16: края правила', () {
    test('ALG-MAP-16: книга без слов — без созвездия', () {
      final List<BookBag> bags = <BookBag>[
        _bag('a', <String, int>{'кость': 5, 'сустав': 3, 'мышца': 2}),
        _bag('b', <String, int>{'кость': 4, 'сустав': 4, 'мышца': 1}),
        _bag('c', <String, int>{'кость': 6, 'сустав': 2, 'мышца': 3}),
        _bag('d', const <String, int>{}),
      ];
      final MapVocabulary vocabulary = vocabularyOf(bags);
      final List<int> labels = _labels(bm25Rows(bags, vocabulary));
      expect(labels.last, kNoCategory);
      expect(labels.sublist(0, 3).toSet(), <int>{0});
    });

    test('ALG-MAP-16: меньше трёх книг со словами — одно созвездие', () {
      SparseRow row(int word) => SparseRow(
        Int32List.fromList(<int>[word]),
        Float64List.fromList(<double>[1]),
      );
      final List<int> labels = _labels(<SparseRow>[
        row(0),
        row(1),
        SparseRow(Int32List(0), Float64List(0)),
      ]);
      expect(labels, <int>[0, 0, kNoCategory]);
    });

    test('ALG-MAP-16: мерка библиотеки — медиана ближайших соседей', () {
      // Три книги: у первых двух ближайшая соседка — друг друга.
      final List<BookBag> bags = <BookBag>[
        _bag('a', <String, int>{'x': 3, 'y': 1, 'z': 1}),
        _bag('b', <String, int>{'x': 3, 'y': 1, 'w': 1}),
        _bag('c', <String, int>{'y': 1, 'z': 2, 'w': 2}),
      ];
      final MapVocabulary vocabulary = vocabularyOf(bags);
      final List<SparseRow> rows = bm25Rows(bags, vocabulary);
      final List<double> best = <double>[
        for (int i = 0; i < 3; i++)
          <double>[
            for (int j = 0; j < 3; j++)
              if (i != j) sparseDot(rows[i], rows[j]),
          ].reduce((double p, double q) => p > q ? p : q),
      ]..sort();
      expect(libraryMeasure(gramOf(rows), rows.length), best[1]);
    });
  });

  test('F-MAP-16: составная библиотека — все темы найдены при любом порядке '
      'поступления', () {
    final List<BookBag> bags = _library();
    final MapVocabulary vocabulary = vocabularyOf(bags);
    final List<SparseRow> rows = bm25Rows(bags, vocabulary);
    final List<int> truth = <int>[
      for (int i = 0; i < bags.length; i++) i ~/ 10,
    ];
    final int n = bags.length;
    final Stopwatch watch = Stopwatch()..start();
    final List<int> straight = _labels(rows);
    final int ms = watch.elapsedMilliseconds;
    final List<int> backward = _labels(
      rows,
      order: <int>[for (int i = n - 1; i >= 0; i--) i],
    );
    final List<int> mixed = _labels(
      rows,
      order: <int>[for (int i = 0; i < n; i++) (i * 97) % n],
    );
    final double score = _ari(straight, truth);
    stdout.writeln(
      'ЗАМЕР F-MAP-16 | составная библиотека $n книг, 24 темы | '
      'созвездий ${straight.toSet().length}, ARI $score | $ms мс',
    );
    expect(score, 1.0);
    expect(backward, straight);
    expect(mixed, straight);
  });

  group('ALG-MAP-10: имена созвездий', () {
    test(
      'ALG-MAP-10: имя — характерное слово созвездия, а не частое везде',
      () {
        // «общее» — самое частое слово первого созвездия, но оно так же
        // часто и во втором; «кость» реже, зато только здесь — она и
        // стоит в имени первой.
        final List<BookBag> bags = <BookBag>[
          _bag('a', <String, int>{'общее': 20, 'кость': 8, 'сустав': 5}),
          _bag('b', <String, int>{'общее': 20, 'кость': 9, 'сустав': 4}),
          _bag('c', <String, int>{'общее': 20, 'интеграл': 8, 'предел': 5}),
          _bag('d', <String, int>{'общее': 20, 'интеграл': 7, 'предел': 6}),
        ];
        const MapVocabulary vocabulary = MapVocabulary(
          terms: <String>['интеграл', 'кость', 'общее', 'предел', 'сустав'],
          bookCounts: <int>[2, 2, 4, 2, 2],
        );
        final List<String> names = constellationNames(bags, vocabulary, <int>[
          0,
          0,
          1,
          1,
        ]);
        expect(names[0], startsWith('кость'));
        expect(names[1], startsWith('интеграл'));
      },
    );

    test('F-MAP-03: в имени — целое слово, а не основа', () {
      final List<BookBag> bags = <BookBag>[
        _bag(
          'a',
          <String, int>{'анатоми': 9, 'кост': 5},
          forms: <String>['анатомия', 'кости'],
        ),
        _bag(
          'b',
          <String, int>{'анатоми': 4, 'кост': 7},
          forms: <String>['анатомии', 'костей'],
        ),
      ];
      const MapVocabulary vocabulary = MapVocabulary(
        terms: <String>['анатоми', 'кост'],
        bookCounts: <int>[2, 2],
      );
      // У каждого слова — форма из книги, где оно чаще всего.
      expect(
        constellationNames(bags, vocabulary, <int>[0, 0]).single,
        anyOf('анатомия · костей', 'костей · анатомия'),
      );
    });

    test('F-MAP-03: одинаковые имена различаются номером', () {
      final List<BookBag> bags = <BookBag>[
        _bag('a', <String, int>{'кость': 5}),
        _bag('b', <String, int>{'кость': 5}),
      ];
      const MapVocabulary vocabulary = MapVocabulary(
        terms: <String>['кость'],
        bookCounts: <int>[2],
      );
      expect(constellationNames(bags, vocabulary, <int>[0, 1]), <String>[
        'кость',
        'кость 2',
      ]);
    });
  });

  test('F-MAP-03: мешок помнит самую частую целую форму слова', () {
    final BagBuilder builder = BagBuilder()
      ..add('Анатомия человека. Анатомия органов. Анатомии сосудов.');
    final BookBag bag = builder.build(key: 'k', group: '');
    final int i = bag.terms.indexOf(mapTokens('анатомия').single);
    expect(i, isNonNegative);
    expect(bag.formAt(i), 'анатомия');
    expect(bag.terms.length, bag.forms!.length);
  });
}
