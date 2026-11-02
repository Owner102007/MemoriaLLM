/// Порядок звёзд в созвездии (F-MAP-17, ALG-MAP-17) на составном
/// корпусе, где самая типичная книга известна заранее.
///
/// Корпус. Книга «ядро» содержит слова всех пяти тем группы, каждая из
/// пяти «тем» — слово только своей темы (общее с ядром), «пустая» — ни
/// одного слова, которое встречалось бы ещё где-то (у неё нулевая
/// строка, как у скана без текста). Значит, ядро — самая типичная,
/// пустая — самая особенная.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_layout.dart';
import 'package:memoria/domain/map/map_order.dart';
import 'package:memoria/domain/map/map_vectors.dart';

/// Мешок книги из пар «слово → сколько раз».
BookBag _bag(String key, Map<String, int> words) {
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
  );
}

/// Составной корпус — по возрастанию отпечатка, как в расчёте карты:
/// `a-core` — ядро, `b-topic1` … `b-topic5` — темы, `c-empty` — пустая.
List<BookBag> _corpus() => <BookBag>[
  _bag('a-core', <String, int>{for (int k = 1; k <= 5; k++) 'тема$k': 3}),
  for (int k = 1; k <= 5; k++)
    _bag('b-topic$k', <String, int>{'тема$k': 4, 'своё$k': 4}),
  _bag('c-empty', <String, int>{'одно': 7}),
];

/// Матрица Грама корпуса — как в `buildBookMap`.
Float64List _gramOf(List<BookBag> bags) =>
    gramOf(bm25Rows(bags, vocabularyOf(bags)));

void main() {
  test('F-MAP-17: самая типичная книга группы — наверху', () {
    final List<BookBag> bags = _corpus();
    final int n = bags.length;
    final List<int> labels = List<int>.filled(n, 0);
    final Float64List typical = typicalities(_gramOf(bags), n, labels);
    // Ядро — типичнее всех, пустая — 0 и последняя.
    for (int i = 1; i < n; i++) {
      expect(typical[0], greaterThan(typical[i]), reason: bags[i].key);
    }
    expect(typical[n - 1], 0);
    // Места: раскладка «случайно» дала ядру самую дальнюю от центра
    // точку (0,5; 0,9).
    final MapCoordinates place = MapCoordinates(
      Float64List.fromList(<double>[0.5, 0.4, 0.3, 0.6, 0.7, 0.5, 0.0]),
      Float64List.fromList(<double>[0.9, 0.1, 0.3, 0.3, 0.1, -0.2, 0.0]),
    );
    final MapCoordinates ordered = orderWithinGroups(place, typical, labels);
    final List<MapPoint> points = <MapPoint>[
      for (int i = 0; i < n; i++)
        MapPoint(
          key: bags[i].key,
          x: ordered.xs[i],
          y: ordered.ys[i],
          constellation: 0,
        ),
    ];
    final List<MapPoint> list = constellationOrder(points, 0);
    // «Наверху» списка и в центре созвездия — ядро; в конце и на краю —
    // пустая.
    expect(list.first.key, 'a-core');
    expect(list.last.key, 'c-empty');
    // Центр точек группы — (0,4286; 0,2143): ближе всех к нему (0,4; 0,1).
    expect(ordered.xs[0], 0.4);
    expect(ordered.ys[0], 0.1);
  });

  test('F-MAP-17: места группы — то же множество', () {
    final List<BookBag> bags = _corpus();
    final int n = bags.length;
    final List<int> labels = <int>[0, 1, 0, 1, 0, 1, -1];
    final MapCoordinates place = MapCoordinates(
      Float64List.fromList(<double>[for (int i = 0; i < n; i++) i * 0.1]),
      Float64List.fromList(<double>[for (int i = 0; i < n; i++) -i * 0.05]),
    );
    final MapCoordinates ordered = orderWithinGroups(
      place,
      typicalities(_gramOf(bags), n, labels),
      labels,
    );
    for (final int c in labels.toSet()) {
      Set<String> spots(MapCoordinates m) => <String>{
        for (int i = 0; i < n; i++)
          if (labels[i] == c) '${m.xs[i]};${m.ys[i]}',
      };
      expect(spots(ordered), spots(place), reason: 'группа $c');
    }
  });

  test(
    'F-MAP-17: группа из одной-двух книг и «без созвездия» — правило то же',
    () {
      final List<BookBag> bags = _corpus();
      final int n = bags.length;
      // Ядро и пустая — без созвездия (−1), тема 1 — одна в своём,
      // темы 2–5 — созвездие 3.
      final List<int> labels = <int>[-1, 2, 3, 3, 3, 3, -1];
      final Float64List typical = typicalities(_gramOf(bags), n, labels);
      expect(typical[0], greaterThan(typical[6]));
      final MapCoordinates place = MapCoordinates(
        Float64List.fromList(<double>[0.0, 0.8, 0.1, 0.2, 0.3, 0.4, 0.0]),
        // Ядру раскладка дала нижнюю точку пары, пустой — верхнюю.
        Float64List.fromList(<double>[0.5, 0.8, 0.0, 0.0, 0.0, 0.0, -0.5]),
      );
      final MapCoordinates ordered = orderWithinGroups(place, typical, labels);
      // Две точки пары от центра равноудалены — типичная книга встаёт на
      // верхнюю (y меньше).
      expect(ordered.ys[0], -0.5);
      expect(ordered.ys[6], 0.5);
      // Одна книга остаётся на своей точке.
      expect(ordered.xs[1], 0.8);
      expect(ordered.ys[1], 0.8);
    },
  );

  test('ALG-MAP-17: у группы без слов типичность всех книг — 0', () {
    final Float64List gram = Float64List(4);
    final Float64List typical = typicalities(gram, 2, <int>[0, 0]);
    expect(typical.toList(), <double>[0, 0]);
    // Порядок тогда — по отпечатку: первая книга на ближнюю к центру
    // (из двух равноудалённых — верхнюю).
    final MapCoordinates ordered = orderWithinGroups(
      MapCoordinates(
        Float64List.fromList(<double>[0, 0]),
        Float64List.fromList(<double>[1, -1]),
      ),
      typical,
      <int>[0, 0],
    );
    expect(ordered.ys.toList(), <double>[-1, 1]);
  });

  test('ALG-MAP-17: типичность — косинус со средним строк группы', () {
    final List<BookBag> bags = _corpus();
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final int n = rows.length;
    final List<int> labels = List<int>.filled(n, 0);
    final Float64List typical = typicalities(gramOf(rows), n, labels);
    // Прямой расчёт: среднее строк, косинус каждой строки с ним.
    final Map<int, double> mean = <int, double>{};
    for (final SparseRow row in rows) {
      for (int k = 0; k < row.length; k++) {
        mean[row.index[k]] = (mean[row.index[k]] ?? 0) + row.weight[k] / n;
      }
    }
    double norm = 0;
    for (final double value in mean.values) {
      norm += value * value;
    }
    for (int i = 0; i < n; i++) {
      double dot = 0;
      for (int k = 0; k < rows[i].length; k++) {
        dot += rows[i].weight[k] * (mean[rows[i].index[k]] ?? 0);
      }
      final double cosine = norm == 0 ? 0 : dot / _sqrt(norm);
      expect(typical[i], closeTo(cosine, 1e-12), reason: bags[i].key);
    }
  });
}

/// Корень методом Ньютона — чтобы проверка не повторяла код расчёта.
double _sqrt(double value) {
  double x = value;
  for (int k = 0; k < 60; k++) {
    x = (x + value / x) / 2;
  }
  return x;
}
