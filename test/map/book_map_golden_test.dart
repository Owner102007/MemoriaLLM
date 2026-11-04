import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_categories.dart';
import 'package:memoria/domain/map/map_layout.dart';
import 'package:memoria/domain/map/map_names.dart';
import 'package:memoria/domain/map/map_order.dart';
import 'package:memoria/domain/map/map_seating.dart';
import 'package:memoria/domain/map/map_trusted.dart';
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
    // Пять созвездий и книги без созвездия (скан, одиночка) — шесть групп.
    expect(map.groups, 6);
  });

  group('ALG-MAP-08: досадка', () {
    late Map<String, Object?> seating;
    late Set<String> added;
    late BookMap before;
    late Map<String, MapPoint> kept;

    setUp(() {
      seating = golden['seating']! as Map<String, Object?>;
      added = <String>{
        for (final Object? key in seating['added']! as List<Object?>)
          key! as String,
      };
      before = buildBookMap(<BookBag>[
        for (final BookBag bag in bags)
          if (!added.contains(bag.key)) bag,
      ])!;
      kept = <String, MapPoint>{
        for (final MapPoint point in before.points) point.key: point,
      };
    });

    test('ALG-MAP-08: карта до досадки та же, что у другой реализации', () {
      final List<Object?> rows = seating['before']! as List<Object?>;
      expect(before.points.length, rows.length);
      for (int i = 0; i < rows.length; i++) {
        final List<Object?> row = rows[i]! as List<Object?>;
        final MapPoint point = before.points[i];
        expect(point.key, row[0]);
        expect(
          (point.x - numberOf(row[1])).abs(),
          lessThanOrEqualTo(_tolerance),
        );
        expect(
          (point.y - numberOf(row[2])).abs(),
          lessThanOrEqualTo(_tolerance),
        );
        expect(point.constellation, row[3]);
        expect(point.name, row[4]);
      }
    });

    test('ALG-MAP-08: досаженные книги — те же места, созвездия и причины, '
        'что у другой реализации', () {
      final BookMap map = seatBooks(bags, kept)!;
      final List<Object?> rows = seating['points']! as List<Object?>;
      expect(map.points.length, rows.length);
      double worst = 0;
      for (int i = 0; i < rows.length; i++) {
        final List<Object?> row = rows[i]! as List<Object?>;
        final MapPoint point = map.points[i];
        expect(point.key, row[0]);
        worst = math.max(worst, (point.x - numberOf(row[1])).abs());
        worst = math.max(worst, (point.y - numberOf(row[2])).abs());
        expect(point.constellation, row[3], reason: point.key);
        expect(point.name, row[4], reason: point.key);
        expect(point.reason.name, row[5], reason: point.key);
        expect(point.seated, row[6], reason: point.key);
      }
      stdout.writeln(
        'ЗАМЕР ALG-MAP-08 | досадка | расхождение с эталоном | $worst',
      );
      expect(worst, lessThanOrEqualTo(_tolerance));
      expect(map.fingerprint, seating['fingerprint']);
    });

    test('F-MAP-04: досадка не сдвигает прежние звёзды вовсе (ε = 0)', () {
      final BookMap map = seatBooks(bags, kept)!;
      for (final MapPoint point in map.points) {
        final MapPoint? was = kept[point.key];
        if (was != null) {
          expect(point, was, reason: 'старая звезда — до бита');
        } else {
          expect(point.seated, isTrue);
          expect(point.x.abs(), lessThanOrEqualTo(1.0));
          expect(point.y.abs(), lessThanOrEqualTo(1.0));
        }
      }
      // Каждая новая звезда — не ближе наименьшего просвета к любой другой.
      final double gap = kGapShare / math.sqrt(map.points.length.toDouble());
      for (final MapPoint a in map.points.where((MapPoint p) => p.seated)) {
        for (final MapPoint b in map.points) {
          if (identical(a, b)) continue;
          final double dx = a.x - b.x;
          final double dy = a.y - b.y;
          expect(
            math.sqrt(dx * dx + dy * dy),
            greaterThanOrEqualTo(gap * 0.999),
            reason: '${a.key} у ${b.key}',
          );
        }
      }
    });

    test('ALG-MAP-08: порядок мешков на досадку не влияет', () {
      final BookMap a = seatBooks(bags, kept)!;
      final BookMap b = seatBooks(bags.reversed.toList(), kept)!;
      expect(b.fingerprint, a.fingerprint);
      expect(b.points, a.points);
    });
  });

  test('ALG-MAP-16: созвездия те же, что у другой реализации', () {
    final MapVocabulary vocabulary = vocabularyOf(bags);
    final List<SparseRow> rows = bm25Rows(bags, vocabulary);
    final List<int> expected = listOf('categories').cast<int>();
    expect(_labels(rows), expected);
    // Дробные числа — мерка и сплочённость созвездий: на них расхождение
    // реализаций видно сразу, а не только на пороге.
    final ArtResult result = artCategories(gramOf(rows), rows.length);
    expect(result.measure, numberOf(golden['measure']));
    expect(result.cohesions, listOf('cohesions').map(numberOf).toList());
    final BookMap map = buildBookMap(bags)!;
    expect(<int>[
      for (final MapPoint point in map.points) point.constellation,
    ], expected);
  });

  test(
    'F-MAP-16: созвездия эталона — темы книг, скан и одиночка без созвездия',
    () {
      final BookMap map = buildBookMap(bags)!;
      final Set<int> found = <int>{
        for (final MapPoint point in map.points) point.constellation,
      };
      expect(found, <int>{-1, 0, 1, 2, 3, 4});
      final MapPoint scan = map.points.firstWhere(
        (MapPoint point) => point.key == 'hash-scan',
      );
      expect(scan.constellation, -1);
      expect(scan.name, isEmpty);
    },
  );

  test('ALG-MAP-10: имена созвездий те же, что у другой реализации', () {
    final MapVocabulary vocabulary = vocabularyOf(bags);
    final List<int> labels = listOf('categories').cast<int>();
    final List<String> names = constellationNames(bags, vocabulary, labels);
    expect(names, listOf('names').cast<String>());
    final BookMap map = buildBookMap(bags)!;
    for (final MapPoint point in map.points) {
      if (point.constellation >= 0) {
        expect(point.name, names[point.constellation]);
      }
    }
  });

  group('ALG-MAP-16: малые наборы другой реализации', () {
    late Map<String, Object?> art;
    late List<SparseRow> rows;

    setUpAll(() {
      art = golden['art']! as Map<String, Object?>;
      final List<BookBag> books = <BookBag>[
        for (final Object? entry in art['books']! as List<Object?>)
          _bagOf(entry! as Map<String, Object?>),
      ];
      final MapVocabulary vocabulary = vocabularyOf(books);
      rows = bm25Rows(books, vocabulary);
    });

    test('ALG-MAP-16: мерка библиотеки c₀ та же', () {
      expect(libraryMeasure(gramOf(rows), rows.length), numberOf(art['c0']));
      final ArtResult result = artCategories(gramOf(rows), rows.length);
      expect(
        result.cohesions,
        (art['cohesions']! as List<Object?>).map(numberOf).toList(),
      );
    });

    test(
      'ALG-MAP-16: после повтора разметка одна при любом порядке поступления',
      () {
        final List<Object?> orders = art['orders']! as List<Object?>;
        final List<Object?> labels = art['labels']! as List<Object?>;
        for (int k = 0; k < orders.length; k++) {
          final List<int> order = (orders[k]! as List<Object?>).cast<int>();
          final List<int> got = _labels(rows, order: order);
          expect(got, (labels[k]! as List<Object?>).cast<int>());
          expect(got, (labels.first! as List<Object?>).cast<int>());
        }
        // Шесть тем по четыре книги — шесть созвездий по четыре.
        final List<int> first = (labels.first! as List<Object?>).cast<int>();
        expect(first.toSet().length, 6);
      },
    );

    test(
      'ALG-MAP-16: книга, поставленная читателем, остаётся в его группе',
      () {
        final Map<int, int> pinned = <int, int>{
          for (final Object? pair in art['pinned']! as List<Object?>)
            ((pair! as List<Object?>)[0]! as int):
                (pair as List<Object?>)[1]! as int,
        };
        final List<int> got = _labels(rows, pinned: pinned);
        expect(got, (art['pinnedLabels']! as List<Object?>).cast<int>());
        // Две книги разных тем, поставленные вместе, — в одном созвездии.
        final List<int> keys = pinned.keys.toList();
        expect(got[keys[0]], got[keys[1]]);
      },
    );
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

  test('ALG-MAP-17: типичность та же, что у другой реализации', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final Float64List typical = typicalities(
      gramOf(rows),
      rows.length,
      listOf('categories').cast<int>(),
    );
    expect(typical.toList(), listOf('typical').map(numberOf).toList());
  });

  test('F-MAP-17: порядок совпадает с эталоном', () {
    final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
    final LatentRows latent = latentRows(gramOf(rows), rows.length);
    final MapEdges edges = edgesOf(neighboursOf(latent));
    final List<int> labels = listOf('categories').cast<int>();
    final MapCoordinates placed = layoutBooks(latent, edges, <String>[
      for (final int c in labels) constellationGroup(c),
    ]);
    final List<Object?> before = listOf('placed');
    for (int i = 0; i < before.length; i++) {
      final List<Object?> point = before[i]! as List<Object?>;
      expect(placed.xs[i], numberOf(point[0]), reason: 'раскладка, $i');
      expect(placed.ys[i], numberOf(point[1]), reason: 'раскладка, $i');
    }
    final BookMap map = buildBookMap(bags)!;
    final List<Object?> after = listOf('points');
    for (int i = 0; i < after.length; i++) {
      final List<Object?> point = after[i]! as List<Object?>;
      expect(map.points[i].x, numberOf(point[0]), reason: 'порядок, $i');
      expect(map.points[i].y, numberOf(point[1]), reason: 'порядок, $i');
    }
    expect(map.fingerprint, golden['fingerprint']);
    // S57 подняла версию расчёта до 3 (дальше её поднимают следующие шаги).
    expect(kBookMapVersion, greaterThanOrEqualTo(3));
  });

  test('F-MAP-17: места группы — то же множество', () {
    final List<int> labels = listOf('categories').cast<int>();
    final BookMap map = buildBookMap(bags)!;
    final List<Object?> before = listOf('placed');
    for (final int c in labels.toSet()) {
      final Set<String> was = <String>{
        for (int i = 0; i < labels.length; i++)
          if (labels[i] == c) (before[i]! as List<Object?>).join(';'),
      };
      final Set<String> now = <String>{
        for (final MapPoint point in map.points)
          if (point.constellation == c) '${point.x};${point.y}',
      };
      expect(now, was, reason: 'созвездие $c');
    }
    // И хотя бы одна книга сменила звезду: иначе правило ничего не делает.
    int moved = 0;
    for (int i = 0; i < before.length; i++) {
      final List<Object?> point = before[i]! as List<Object?>;
      if (numberOf(point[0]) != map.points[i].x) moved++;
    }
    stdout.writeln('ЗАМЕР F-MAP-17 | эталон | книг пересажено | $moved');
    expect(moved, greaterThan(0));
  });

  test('F-MAP-17: список созвездия идёт от типичной книги к особенной '
      '(ближайшая к центру — самая типичная)', () {
    final List<int> labels = listOf('categories').cast<int>();
    final List<double> typical = listOf('typical').map(numberOf).toList();
    final BookMap map = buildBookMap(bags)!;
    for (final int c in labels.toSet()) {
      final List<int> expected =
          <int>[
            for (int i = 0; i < labels.length; i++)
              if (labels[i] == c) i,
          ].toList()..sort((int a, int b) {
            final int order = typical[b].compareTo(typical[a]);
            return order != 0 ? order : a.compareTo(b);
          });
      expect(
        <String>[
          for (final MapPoint p in constellationOrder(map.points, c)) p.key,
        ],
        <String>[for (final int i in expected) bags[i].key],
        reason: 'созвездие $c',
      );
    }
  });

  group('F-MAP-18: доверие тексту — малый набор другой реализации', () {
    late Map<String, Object?> trusted;
    late List<BookBag> trustedBags;

    setUpAll(() {
      trusted = golden['trusted']! as Map<String, Object?>;
      trustedBags = <BookBag>[
        for (final Object? book in trusted['books']! as List<Object?>)
          _bagOf(book! as Map<String, Object?>),
      ];
    });

    test('F-MAP-18: книга с ненадёжным текстом не заводит категорию', () {
      final BookMap map = buildBookMap(trustedBags)!;
      expect(<int>[
        for (final MapPoint point in map.points) point.constellation,
      ], (trusted['categories']! as List<Object?>).cast<int>());
      expect(<String>[
        for (final MapPoint point in map.points) point.reason.name,
      ], (trusted['reasons']! as List<Object?>).cast<String>());
      // Шумная копия темы — в своей теме, смесь двух тем — «не уверены»,
      // без надёжного текста — «мало текста»; своих созвездий нет.
      final Map<String, MapPoint> byKey = <String, MapPoint>{
        for (final MapPoint point in map.points) point.key: point,
      };
      expect(byKey['tr-noisy']!.constellation, byKey['tr-0-0']!.constellation);
      expect(byKey['tr-mixed']!.reason, MapReason.unsure);
      expect(byKey['tr-little']!.reason, MapReason.littleText);
      expect(byKey['tr-little']!.constellation, kNoCategory);
      expect(map.groups, 4);
      final List<Object?> points = trusted['points']! as List<Object?>;
      for (int i = 0; i < points.length; i++) {
        final List<Object?> point = points[i]! as List<Object?>;
        expect(map.points[i].x, numberOf(point[0]), reason: 'x $i');
        expect(map.points[i].y, numberOf(point[1]), reason: 'y $i');
      }
      expect(map.fingerprint, trusted['fingerprint']);
    });

    test('F-MAP-18: в мешке ненадёжной книги — только слова надёжных', () {
      final List<BookTrust> trust = <BookTrust>[
        for (final BookBag bag in trustedBags) bag.trust,
      ];
      final List<int> builders = buildersOf(trust);
      final Set<String> known = <String>{
        for (final int i in builders) ...trustedBags[i].terms,
      };
      final List<int> kept = <int>[
        for (int i = 0; i < trustedBags.length; i++)
          builders.contains(i) || trust[i].littleText
              ? trustedBags[i].terms.length
              : trustedBags[i].onlyWords(known).terms.length,
      ];
      expect(kept, (trusted['kept']! as List<Object?>).cast<int>());
      // Шумные слова шумной копии выпали.
      final BookBag noisy = trustedBags.firstWhere(
        (BookBag bag) => bag.key == 'tr-noisy',
      );
      expect(noisy.terms.any((String t) => t.startsWith('шум')), isTrue);
      expect(
        noisy.onlyWords(known).terms.any((String t) => t.startsWith('шум')),
        isFalse,
      );
    });
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
    trust: _trustOf(book['trust']),
  );
}

/// Доверие книги эталона: нет поля или `null` — как есть, `little` —
/// надёжного текста нет, число — T.
BookTrust _trustOf(Object? value) {
  if (value == null) return const BookTrust.asIs();
  if (value == 'little') return const BookTrust.littleText();
  return BookTrust.of((value as num).toDouble());
}
