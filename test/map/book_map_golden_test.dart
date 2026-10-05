import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_layout.dart';
import 'package:memoria/domain/map/map_vectors.dart';

/// Эталон: посчитан `tool/make_map_goldens.py` — другой реализацией.
const String _goldenPath = 'test/goldens/book_map.json';

/// На сколько расчёт вправе разойтись с эталоном на промежуточных
/// шагах. Обе реализации складывают в одном порядке и одними точными
/// операциями, так что ждём ноль; допуск — на случай, если разойдётся
/// последний бит, а не смысл.
const double _tolerance = 1e-9;

/// ALG-MAP-02 … ALG-MAP-07: расчёт карты против другой реализации.
///
/// Тест, который зовёт ту же функцию, сверял бы её с самой собой.
/// Здесь каждый шаг — словарь, веса, матрица Грама, собственные
/// значения, соседи, рёбра, координаты — сверяется с тем, что на том же
/// корпусе посчитал Python.
void main() {
  late Map<String, Object?> golden;
  late List<BookBag> bags;

  List<Object?> listOf(String name) => golden[name]! as List<Object?>;

  double numberOf(Object? value) => (value! as num).toDouble();

  setUpAll(() {
    golden = jsonDecode(
      File(_goldenPath).readAsStringSync(),
    ) as Map<String, Object?>;
    final Map<String, Map<String, Object?>> byKey =
        <String, Map<String, Object?>>{};
    for (final Object? entry in listOf('books')) {
      final Map<String, Object?> book = entry! as Map<String, Object?>;
      byKey[book['key']! as String] = book;
    }
    // Мешки — в порядке расчёта: по возрастанию отпечатка.
    bags = <BookBag>[
      for (final Object? key in listOf('order')) _bagOf(byKey[key! as String]!),
    ];
  });

  test('ALG-MAP-02: эталон не пуст и книги стоят по отпечатку', () {
    expect(bags.length, greaterThanOrEqualTo(12));
    final List<String> keys = <String>[for (final BookBag bag in bags) bag.key];
    expect(keys, List<String>.of(keys)..sort());
    expect(keys.toSet().length, keys.length);
  });

  test('ALG-MAP-02: словарь корпуса тот же', () {
    final MapVocabulary vocabulary = vocabularyOf(bags);
    expect(vocabulary.terms, listOf('vocabulary').cast<String>());
    // Слова одной книги в словарь не идут; из общих остаются только те,
    // что стоят не во всех книгах.
    expect(vocabulary.terms, isNot(contains('общее00')));
    expect(vocabulary.terms.any((String t) => t.startsWith('книга')), isFalse);
    expect(
      vocabulary.terms.any((String t) => t.startsWith('одиночка')),
      isFalse,
    );
    for (final int count in vocabulary.bookCounts) {
      expect(count, greaterThanOrEqualTo(kMinBooks));
      expect(count * 100, lessThanOrEqualTo(kStopPercent * bags.length));
    }
  });

  test('ALG-MAP-03: веса BM25 те же, строки единичной длины', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final List<Object?> expected = listOf('rows');
    expect(rows.length, expected.length);
    double worst = 0;
    for (int i = 0; i < rows.length; i++) {
      final List<Object?> cells = expected[i]! as List<Object?>;
      expect(rows[i].length, cells.length, reason: 'книга $i');
      double square = 0;
      for (int c = 0; c < cells.length; c++) {
        final List<Object?> cell = cells[c]! as List<Object?>;
        expect(rows[i].index[c], cell[0]! as int, reason: 'книга $i');
        final double difference = (rows[i].weight[c] - numberOf(cell[1])).abs();
        worst = math.max(worst, difference);
        square += rows[i].weight[c] * rows[i].weight[c];
      }
      if (cells.isNotEmpty) {
        expect(square, closeTo(1, 1e-12), reason: 'книга $i');
      }
    }
    expect(worst, lessThanOrEqualTo(_tolerance));
    stdout.writeln(
      'ЗАМЕР ALG-MAP-03 | веса BM25 | расхождение с эталоном | $worst',
    );
  });

  test('ALG-MAP-04: матрица Грама и собственные значения те же', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final int n = rows.length;
    final Float64List gram = gramOf(rows);
    final List<Object?> expected = listOf('gram');
    double worst = 0;
    for (int i = 0; i < n; i++) {
      final List<Object?> row = expected[i]! as List<Object?>;
      for (int j = 0; j < n; j++) {
        worst = math.max(worst, (gram[i * n + j] - numberOf(row[j])).abs());
        expect(gram[i * n + j], gram[j * n + i]);
      }
    }
    expect(worst, lessThanOrEqualTo(_tolerance));

    final LatentRows latent = latentRows(gram, n);
    final List<Object?> values = listOf('values');
    expect(latent.dimensions, values.length);
    expect(latent.dimensions, lessThanOrEqualTo(math.min(n - 1, 48)));
    for (int i = 0; i < values.length; i++) {
      expect(latent.values[i], closeTo(numberOf(values[i]), _tolerance));
      if (i > 0) {
        expect(latent.values[i], lessThanOrEqualTo(latent.values[i - 1]));
      }
    }
  });

  test('ALG-MAP-04: вращения Якоби раскладывают матрицу точно', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final int n = rows.length;
    final Float64List gram = gramOf(rows);
    final EigenSystem system = jacobiEigen(gram, n);
    // V·Λ·Vᵀ собирает матрицу обратно, а столбцы V ортонормированы.
    double worst = 0;
    double skew = 0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        double back = 0;
        double dot = 0;
        for (int k = 0; k < n; k++) {
          back +=
              system.vectors[i * n + k] *
              system.values[k] *
              system.vectors[j * n + k];
          dot += system.vectors[k * n + i] * system.vectors[k * n + j];
        }
        worst = math.max(worst, (back - gram[i * n + j]).abs());
        skew = math.max(skew, (dot - (i == j ? 1 : 0)).abs());
      }
    }
    expect(worst, lessThan(1e-12));
    expect(skew, lessThan(1e-12));
  });

  test('ALG-MAP-05: соседи и рёбра те же', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final Neighbours neighbours = neighboursOf(
      latentRows(gramOf(rows), rows.length),
    );
    final List<Object?> expected = listOf('neighbours');
    expect(neighbours.near.length, expected.length);
    for (int i = 0; i < expected.length; i++) {
      expect(
        neighbours.near[i],
        (expected[i]! as List<Object?>).cast<int>(),
        reason: 'книга $i',
      );
      expect(neighbours.near[i].length, lessThanOrEqualTo(kNeighbours));
      expect(neighbours.near[i], isNot(contains(i)));
    }
    // Скан без слов и книга из одних редких слов соседей не имеют.
    final List<String> keys = <String>[for (final BookBag bag in bags) bag.key];
    expect(neighbours.near[keys.indexOf('hash-scan')], isEmpty);
    expect(neighbours.near[keys.indexOf('hash-lone')], isEmpty);

    final MapEdges edges = edgesOf(neighbours);
    final List<Object?> lines = listOf('edges');
    expect(edges.length, lines.length);
    double top = 0;
    for (int e = 0; e < lines.length; e++) {
      final List<Object?> line = lines[e]! as List<Object?>;
      expect(edges.from[e], line[0]! as int);
      expect(edges.to[e], line[1]! as int);
      expect(edges.weight[e], closeTo(numberOf(line[2]), _tolerance));
      expect(edges.from[e], lessThan(edges.to[e]));
      top = math.max(top, edges.weight[e]);
    }
    expect(top, 1);
  });

  test('ALG-MAP-06: координаты те же, что у другой реализации', () {
    final BookMap map = buildBookMap(bags)!;
    final List<Object?> points = listOf('points');
    expect(map.points.length, points.length);
    double worst = 0;
    for (int i = 0; i < points.length; i++) {
      final List<Object?> point = points[i]! as List<Object?>;
      expect(map.points[i].key, bags[i].key);
      worst = math.max(worst, (map.points[i].x - numberOf(point[0])).abs());
      worst = math.max(worst, (map.points[i].y - numberOf(point[1])).abs());
    }
    stdout.writeln(
      'ЗАМЕР ALG-MAP-06 | координаты | расхождение с эталоном | $worst',
    );
    expect(worst, lessThanOrEqualTo(_tolerance));
    expect(map.fingerprint, golden['fingerprint']);
    expect(map.words, listOf('vocabulary').length);
    expect(map.edges, listOf('edges').length);
    expect(map.groups, 3);
  });

  test('ALG-MAP-06: порядок мешков на карту не влияет', () {
    final BookMap straight = buildBookMap(bags)!;
    final BookMap reversed = buildBookMap(bags.reversed.toList())!;
    expect(reversed.points, straight.points);
    expect(reversed.fingerprint, straight.fingerprint);
  });

  test('ALG-MAP-06: отпечаток карты считается по миллионным долям', () {
    expect(mapQuantum(0), 0);
    expect(mapQuantum(0.1234564), 123456);
    expect(mapQuantum(0.1234566), 123457);
    expect(mapQuantum(-0.1234566), -123457);
    expect(mapQuantum(1), 1000000);
    expect(mapQuantum(-1), -1000000);
    const List<MapPoint> points = <MapPoint>[
      MapPoint(key: 'a', x: 0.5, y: -0.25),
      MapPoint(key: 'b', x: -1, y: 1),
    ];
    final String print = mapFingerprint(points);
    expect(print, hasLength(8));
    expect(print, matches(RegExp(r'^[0-9a-f]{8}$')));
    // Сдвиг меньше миллионной отпечатка не меняет, больше — меняет.
    expect(
      mapFingerprint(const <MapPoint>[
        MapPoint(key: 'a', x: 0.5000000001, y: -0.25),
        MapPoint(key: 'b', x: -1, y: 1),
      ]),
      print,
    );
    expect(
      mapFingerprint(const <MapPoint>[
        MapPoint(key: 'a', x: 0.50001, y: -0.25),
        MapPoint(key: 'b', x: -1, y: 1),
      ]),
      isNot(print),
    );
  });

  test('ALG-MAP-06: раскладка — те же числа при втором расчёте', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final LatentRows latent = latentRows(gramOf(rows), rows.length);
    final MapEdges edges = edgesOf(neighboursOf(latent));
    final List<String> groups = <String>[
      for (final BookBag bag in bags) bag.group,
    ];
    final MapCoordinates one = layoutBooks(latent, edges, groups);
    final MapCoordinates two = layoutBooks(latent, edges, groups);
    expect(two.xs, one.xs);
    expect(two.ys, one.ys);
  });
}

BookBag _bagOf(Map<String, Object?> book) {
  final List<Object?> terms = book['terms']! as List<Object?>;
  return BookBag(
    key: book['key']! as String,
    group: book['group']! as String,
    terms: <String>[
      for (final Object? term in terms) (term! as List<Object?>)[0]! as String,
    ],
    counts: <int>[
      for (final Object? term in terms) (term! as List<Object?>)[1]! as int,
    ],
    length: book['length']! as int,
  );
}
