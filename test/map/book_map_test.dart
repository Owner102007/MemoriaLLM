import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/exact_math.dart';
import 'package:memoria/domain/map/map_layout.dart';
import 'package:memoria/domain/map/map_vectors.dart';

/// Придуманная книга: у неё есть общие слова, слова своей темы и свои.
class _Volume {
  const _Volume(this.key, this.group, this.topic);

  final String key;
  final String group;
  final String topic;
}

/// Корпус с известным ответом (ALG-MAP-05).
///
/// Темы лежат в группах; у каждой книги — слова, общие для всех книг
/// («титульный лист»), слова своей группы, слова своей темы и свои
/// собственные. Какая книга какой близка, известно заранее: книги одной
/// темы.
List<BookBag> _corpus(
  List<_Volume> volumes, {
  int seed = 11,
  Map<String, String> groupWords = const <String, String>{},
}) {
  final MapRandom random = MapRandom(seed);
  final List<BookBag> bags = <BookBag>[];
  for (int v = 0; v < volumes.length; v++) {
    final _Volume volume = volumes[v];
    final Map<String, int> counts = <String, int>{};

    void draw(String prefix, int words, int times) {
      for (int i = 0; i < times; i++) {
        final double share = random.unit();
        final int place = (words * share * share).floor();
        final String word = '$prefix${place.toString().padLeft(3, '0')}';
        counts[word] = (counts[word] ?? 0) + 1;
      }
    }

    draw('титул', 20, 400);
    draw('группа-${groupWords[volume.group] ?? volume.group}-', 60, 500);
    draw('тема-${volume.topic}-', 40, 400);
    draw('книга-$v-', 30, 200);
    final List<String> terms = counts.keys.toList()..sort();
    int length = 0;
    for (final int count in counts.values) {
      length += count;
    }
    bags.add(
      BookBag(
        key: volume.key,
        group: volume.group,
        terms: terms,
        counts: <int>[for (final String term in terms) counts[term]!],
        length: length,
      ),
    );
  }
  return bags;
}

/// Две группы по три темы, по четыре книги в теме.
List<_Volume> _library() {
  const Map<String, List<String>> topics = <String, List<String>>{
    'Ангиология': <String>['артерии', 'вены', 'лимфа'],
    'Математика': <String>['анализ', 'алгебра', 'геометрия'],
  };
  final List<_Volume> volumes = <_Volume>[];
  int number = 0;
  for (final MapEntry<String, List<String>> entry in topics.entries) {
    for (final String topic in entry.value) {
      for (int i = 0; i < 4; i++) {
        // Отпечатки перемешаны: порядок расчёта не совпадает с порядком
        // тем, и соседство не может получиться из одного порядка.
        final int mixed = (number * 7) % 24;
        volumes.add(
          _Volume(
            'hash-${mixed.toString().padLeft(2, '0')}',
            entry.key,
            topic,
          ),
        );
        number++;
      }
    }
  }
  return volumes;
}

double _distance(MapPoint a, MapPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// ALG-MAP-02 … ALG-MAP-07: свойства карты на корпусе с известным
/// ответом.
void main() {
  group('ALG-MAP-02: стоп-слова порогом', () {
    test('ALG-MAP-02: слова титульного листа из расчёта выброшены', () {
      final List<BookBag> bags = _corpus(_library());
      final MapVocabulary vocabulary = vocabularyOf(bags);
      // «титул000» стоит в каждой книге: больше 85 % — стоп-слово.
      expect(vocabulary.terms, isNot(contains('титул000')));
      // Слова группы стоят в половине книг — они остаются: в плане
      // порог был 40 %, и он срезал бы словарь целой категории.
      expect(
        vocabulary.terms.any((String t) => t.startsWith('группа-Ангиология')),
        isTrue,
      );
      // Слова одной книги никого ни с кем не роднят.
      expect(vocabulary.terms.any((String t) => t.startsWith('книга-')), isFalse);
    });

    test('ALG-MAP-02: порог считается от числа книг', () {
      BookBag bag(String key, List<String> terms) {
        final List<String> sorted = List<String>.of(terms)..sort();
        return BookBag(
          key: key,
          group: '',
          terms: sorted,
          counts: List<int>.filled(sorted.length, 1),
          length: sorted.length,
        );
      }

      // Двадцать книг: «везде» — во всех, «часто» — в семнадцати (85 %),
      // «чаще» — в восемнадцати (90 %), «пара» — в двух, «одна» — в
      // одной.
      final List<BookBag> bags = <BookBag>[
        for (int i = 0; i < 20; i++)
          bag('k$i', <String>[
            'везде',
            if (i < 17) 'часто',
            if (i < 18) 'чаще',
            if (i < 2) 'пара',
            if (i == 0) 'одна',
          ]),
      ];
      expect(vocabularyOf(bags).terms, <String>['пара', 'часто']);
    });
  });

  group('ALG-MAP-05: соседи', () {
    test('ALG-MAP-05: книги одной темы — ближайшие соседи', () {
      final List<_Volume> volumes = _library();
      final List<BookBag> bags = _corpus(volumes)
        ..sort((BookBag a, BookBag b) => a.key.compareTo(b.key));
      final Map<String, String> topicOf = <String, String>{
        for (final _Volume volume in volumes) volume.key: volume.topic,
      };
      final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
      final Neighbours neighbours = neighboursOf(
        latentRows(gramOf(rows), rows.length),
      );
      for (int i = 0; i < bags.length; i++) {
        // Трое ближайших — три другие книги той же темы.
        final Set<String> nearest = <String>{
          for (final int j in neighbours.near[i].take(3)) topicOf[bags[j].key]!,
        };
        expect(nearest, <String>{topicOf[bags[i].key]!}, reason: bags[i].key);
        expect(neighbours.near[i], isNot(contains(i)));
      }
    });

    test('ALG-MAP-05: сходство симметрично и не больше единицы', () {
      final List<BookBag> bags = _corpus(_library());
      final List<SparseRow> rows = bm25Rows(bags, vocabularyOf(bags));
      final int n = rows.length;
      final Neighbours neighbours = neighboursOf(latentRows(gramOf(rows), n));
      for (int i = 0; i < n; i++) {
        expect(neighbours.similarity[i * n + i], 0);
        for (int j = 0; j < n; j++) {
          expect(
            neighbours.similarity[i * n + j],
            neighbours.similarity[j * n + i],
          );
          expect(neighbours.similarity[i * n + j], lessThanOrEqualTo(1 + 1e-12));
        }
      }
    });
  });

  group('ALG-MAP-06: раскладка', () {
    test('ALG-MAP-06: один набор книг — одна карта', () {
      final List<BookBag> bags = _corpus(_library());
      final BookMap one = buildBookMap(bags)!;
      final BookMap two = buildBookMap(List<BookBag>.of(bags.reversed))!;
      expect(two.points, one.points);
      expect(two.fingerprint, one.fingerprint);
    });

    test('ALG-MAP-06: карта лежит в квадрате от −1 до 1 и касается края', () {
      final BookMap map = buildBookMap(_corpus(_library()))!;
      double top = 0;
      for (final MapPoint point in map.points) {
        expect(point.x.isFinite && point.y.isFinite, isTrue);
        expect(point.x.abs(), lessThanOrEqualTo(1));
        expect(point.y.abs(), lessThanOrEqualTo(1));
        top = math.max(top, math.max(point.x.abs(), point.y.abs()));
      }
      expect(top, 1);
    });

    test('ALG-MAP-06: книги одной темы стоят рядом', () {
      final List<_Volume> volumes = _library();
      final BookMap map = buildBookMap(_corpus(volumes))!;
      final Map<String, String> topicOf = <String, String>{
        for (final _Volume volume in volumes) volume.key: volume.topic,
      };
      for (final MapPoint point in map.points) {
        MapPoint? nearest;
        for (final MapPoint other in map.points) {
          if (other.key == point.key) {
            continue;
          }
          if (nearest == null ||
              _distance(point, other) < _distance(point, nearest)) {
            nearest = other;
          }
        }
        expect(topicOf[nearest!.key], topicOf[point.key], reason: point.key);
      }
    });

    test('ALG-MAP-06: между любыми двумя книгами есть просвет', () {
      final List<_Volume> volumes = _library();
      // Две книги с одним и тем же текстом: без просвета они встали бы
      // в одну точку, и по второй нельзя было бы попасть.
      final List<BookBag> bags = _corpus(volumes);
      final BookBag twin = bags.first;
      bags.add(
        BookBag(
          key: 'hash-twin',
          group: twin.group,
          terms: twin.terms,
          counts: twin.counts,
          length: twin.length,
        ),
      );
      final BookMap map = buildBookMap(bags)!;
      final double gap = kGapShare / math.sqrt(bags.length.toDouble());
      double closest = double.infinity;
      for (int i = 0; i < map.points.length; i++) {
        for (int j = i + 1; j < map.points.length; j++) {
          closest = math.min(
            closest,
            _distance(map.points[i], map.points[j]),
          );
        }
      }
      // Вторая нормировка после раздвижки может сжать карту на долю
      // процента — отсюда запас.
      expect(closest, greaterThan(gap * 0.9));
    });

    test('ALG-MAP-06: раздвижка разводит точки, стоящие в одном месте', () {
      final Float64List xs = Float64List.fromList(<double>[0, 0, 0, 1, -1]);
      final Float64List ys = Float64List.fromList(<double>[0, 0, 0, 1, -1]);
      spreadApart(xs, ys);
      final double gap = kGapShare / math.sqrt(5);
      for (int i = 0; i < 5; i++) {
        for (int j = i + 1; j < 5; j++) {
          final double dx = xs[i] - xs[j];
          final double dy = ys[i] - ys[j];
          expect(
            math.sqrt(dx * dx + dy * dy),
            greaterThanOrEqualTo(gap - 1e-9),
            reason: '$i и $j',
          );
        }
      }
    });
  });

  group('ALG-MAP-07: притяжение к категории', () {
    double spreadOf(List<MapPoint> points) {
      double x = 0;
      double y = 0;
      for (final MapPoint point in points) {
        x += point.x;
        y += point.y;
      }
      x /= points.length;
      y /= points.length;
      double worst = 0;
      for (final MapPoint point in points) {
        final double dx = point.x - x;
        final double dy = point.y - y;
        worst = math.max(worst, math.sqrt(dx * dx + dy * dy));
      }
      return worst;
    }

    test('ALG-MAP-07: у книги ближайший сосед — из её категории', () {
      // Худший случай: слова у обеих категорий общие — тексты похожи,
      // и одни соседи по смыслу категории не разделят.
      final List<_Volume> volumes = <_Volume>[
        for (final _Volume volume in _library())
          _Volume(
            volume.key,
            volume.group,
            // Темы тоже общие: «артерии» есть в обеих категориях.
            const <String, String>{
                  'анализ': 'артерии',
                  'алгебра': 'вены',
                  'геометрия': 'лимфа',
                }[volume.topic] ??
                volume.topic,
          ),
      ];
      final BookMap map = buildBookMap(
        _corpus(
          volumes,
          groupWords: const <String, String>{
            'Ангиология': 'общая',
            'Математика': 'общая',
          },
        ),
      )!;
      final Map<String, String> groupOf = <String, String>{
        for (final _Volume volume in volumes) volume.key: volume.group,
      };
      for (final MapPoint point in map.points) {
        MapPoint? nearest;
        for (final MapPoint other in map.points) {
          if (other.key == point.key) {
            continue;
          }
          if (nearest == null ||
              _distance(point, other) < _distance(point, nearest)) {
            nearest = other;
          }
        }
        expect(groupOf[nearest!.key], groupOf[point.key], reason: point.key);
      }
    });

    test('ALG-MAP-07: категории не смешиваются и не налезают', () {
      final List<_Volume> volumes = _library();
      final BookMap map = buildBookMap(_corpus(volumes))!;
      final Map<String, String> groupOf = <String, String>{
        for (final _Volume volume in volumes) volume.key: volume.group,
      };
      List<MapPoint> of(String group) => <MapPoint>[
        for (final MapPoint point in map.points)
          if (groupOf[point.key] == group) point,
      ];
      final List<MapPoint> first = of('Ангиология');
      final List<MapPoint> second = of('Математика');
      double between = double.infinity;
      for (final MapPoint a in first) {
        for (final MapPoint b in second) {
          between = math.min(between, _distance(a, b));
        }
      }
      // Самые близкие книги разных категорий дальше друг от друга, чем
      // наименьший просвет: между категориями виден зазор.
      final double gap = kGapShare / math.sqrt(volumes.length.toDouble());
      expect(between, greaterThan(gap * 1.5));
      // И ни одна категория не занимает всю карту.
      expect(spreadOf(first), lessThan(1));
      expect(spreadOf(second), lessThan(1));
    });

    test('ALG-MAP-07: скан без текста стоит при своей категории', () {
      final List<_Volume> volumes = _library();
      final List<BookBag> bags = _corpus(volumes)
        ..add(
          const BookBag(
            key: 'hash-scan',
            group: 'Математика',
            terms: <String>[],
            counts: <int>[],
            length: 0,
          ),
        );
      final BookMap map = buildBookMap(bags)!;
      final Map<String, String> groupOf = <String, String>{
        for (final _Volume volume in volumes) volume.key: volume.group,
        'hash-scan': 'Математика',
      };
      final MapPoint scan = map.points.firstWhere(
        (MapPoint point) => point.key == 'hash-scan',
      );
      expect(scan.x.isFinite && scan.y.isFinite, isTrue);
      MapPoint? nearest;
      for (final MapPoint other in map.points) {
        if (other.key == scan.key) {
          continue;
        }
        if (nearest == null ||
            _distance(scan, other) < _distance(scan, nearest)) {
          nearest = other;
        }
      }
      expect(groupOf[nearest!.key], 'Математика');
    });
  });

  group('F-MAP-02: когда карты нет', () {
    test('F-MAP-02: меньше трёх книг — карты нет', () {
      final List<BookBag> bags = _corpus(_library());
      expect(buildBookMap(const <BookBag>[]), isNull);
      expect(buildBookMap(bags.sublist(0, 1)), isNull);
      expect(buildBookMap(bags.sublist(0, 2)), isNull);
      expect(buildBookMap(bags.sublist(0, 3)), isNotNull);
    });

    test('F-MAP-02: книги без единого общего слова всё равно расставлены', () {
      final List<BookBag> bags = <BookBag>[
        for (int i = 0; i < 6; i++)
          BookBag(
            key: 'k$i',
            group: i.isEven ? 'А' : 'Б',
            terms: <String>['слово$i'],
            counts: const <int>[5],
            length: 5,
          ),
      ];
      final BookMap map = buildBookMap(bags)!;
      expect(map.words, 0);
      expect(map.edges, 0);
      final double gap = kGapShare / math.sqrt(6);
      for (int i = 0; i < 6; i++) {
        expect(map.points[i].x.isFinite && map.points[i].y.isFinite, isTrue);
        for (int j = i + 1; j < 6; j++) {
          expect(
            _distance(map.points[i], map.points[j]),
            greaterThan(gap * 0.9),
          );
        }
      }
    });

    test('F-MAP-02: одинаковые книги без категорий не стоят в одной точке', () {
      final BookBag bag = _corpus(_library()).first;
      final List<BookBag> bags = <BookBag>[
        for (int i = 0; i < 5; i++)
          BookBag(
            key: 'same$i',
            group: '',
            terms: bag.terms,
            counts: bag.counts,
            length: bag.length,
          ),
      ];
      final BookMap map = buildBookMap(bags)!;
      final Set<String> places = <String>{
        for (final MapPoint point in map.points)
          '${mapQuantum(point.x)}:${mapQuantum(point.y)}',
      };
      expect(places, hasLength(5));
    });
  });

  group('ALG-MAP-06: бюджет раскладки', () {
    /// Раскладка [n] книг по готовому графу: у каждой пятнадцать
    /// соседей, книги разбиты на группы по пятьдесят.
    Duration layoutOf(int n) {
      final MapRandom random = MapRandom(5);
      final Float64List cells = Float64List(n * 3);
      for (int i = 0; i < cells.length; i++) {
        cells[i] = random.unit() * 2 - 1;
      }
      final LatentRows rows = LatentRows(
        count: n,
        dimensions: 3,
        cells: cells,
        values: Float64List(3),
      );
      final List<int> from = <int>[];
      final List<int> to = <int>[];
      final List<double> weight = <double>[];
      for (int i = 0; i < n; i++) {
        final int home = i - i % 50;
        for (int k = 1; k <= 8; k++) {
          final int j = home + (i % 50 + k) % 50;
          if (j < n && j != i) {
            from.add(math.min(i, j));
            to.add(math.max(i, j));
            weight.add(0.3 + random.unit() * 0.7);
          }
        }
      }
      final MapEdges edges = MapEdges(
        from: Int32List.fromList(from),
        to: Int32List.fromList(to),
        weight: Float64List.fromList(weight),
      );
      final List<String> groups = <String>[
        for (int i = 0; i < n; i++) 'группа ${i ~/ 200}',
      ];
      final Stopwatch watch = Stopwatch()..start();
      final MapCoordinates place = layoutBooks(rows, edges, groups);
      watch.stop();
      for (int i = 0; i < n; i++) {
        expect(place.xs[i].isFinite && place.ys[i].isFinite, isTrue);
      }
      return watch.elapsed;
    }

    test('ALG-MAP-06: тысяча книг раскладывается за секунды', () {
      final Duration took = layoutOf(1000);
      stdout.writeln(
        'ЗАМЕР ALG-MAP-06 | раскладка 1000 книг | бюджет 2 с | '
        '${took.inMilliseconds} мс',
      );
      // Порог — от провала на порядок, а не бюджет: прогон идёт без
      // оптимизации сборки, и на устройстве раскладка быстрее.
      expect(took, lessThan(const Duration(seconds: 30)));
    });

    test('ALG-MAP-06: десять тысяч книг — десятки секунд, не минуты', () {
      final Duration took = layoutOf(10000);
      stdout.writeln(
        'ЗАМЕР ALG-MAP-06 | раскладка 10000 книг | бюджет 20 с | '
        '${took.inMilliseconds} мс',
      );
      expect(took, lessThan(const Duration(minutes: 3)));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
