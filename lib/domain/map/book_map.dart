/// Карта книг: от мешков слов до координат (F-MAP-02, SNO-F-MAP-01).
///
/// Здесь расчёт собран целиком — словарь корпуса, BM25, главные
/// компоненты, соседи, раскладка — и описано, где карта хранится.
/// Чистые функции: ни базы, ни файлов, ни Flutter; в приложении расчёт
/// уходит в изолят (`application/map/map_builder.dart`).
library;

import '../library/stable_hash.dart';
import 'book_bag.dart';
import 'map_layout.dart';
import 'map_vectors.dart';

/// Версия расчёта карты (ALG-DATA-09).
///
/// Карта — производное: её посчитал наш код, а не создал читатель.
/// Поменялся расчёт — число растёт, и карта, посчитанная прежней
/// версией, считается заново. Число входит и в ключ набора книг
/// (`MapBuilder.keyOf`).
const int kBookMapVersion = 1;

/// Место одной книги на карте.
class MapPoint {
  /// Создаёт точку.
  const MapPoint({required this.key, required this.x, required this.y});

  /// Отпечаток файла книги.
  final String key;

  /// Абсцисса, от −1 до 1.
  final double x;

  /// Ордината, от −1 до 1.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is MapPoint && other.key == key && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(key, x, y);

  @override
  String toString() => 'MapPoint($key, $x, $y)';
}

/// Посчитанная карта.
class BookMap {
  /// Создаёт карту.
  const BookMap({
    required this.points,
    required this.fingerprint,
    required this.words,
    required this.edges,
    required this.groups,
  });

  /// Точки книг, по возрастанию отпечатка файла.
  final List<MapPoint> points;

  /// Отпечаток карты — восемь знаков: по нему две карты сверяют
  /// глазами. У одного набора книг он один на любом устройстве.
  final String fingerprint;

  /// Сколько слов в словаре корпуса.
  final int words;

  /// Сколько рёбер между книгами.
  final int edges;

  /// Сколько групп на карте — категорий, в которых есть книги; книги
  /// без категории — тоже группа.
  final int groups;
}

/// Координата целым числом миллионных; половина округляется от нуля.
///
/// Отпечаток карты считается по таким числам, а не по самим
/// координатам: запись числа с плавающей точкой у разных платформ
/// своя, а целое пишется одинаково.
int mapQuantum(double value) {
  final double scaled = value * 1000000.0;
  if (scaled >= 0.0) {
    return (scaled + 0.5).floor();
  }
  return -(-scaled + 0.5).floor();
}

/// Отпечаток карты по её точкам.
String mapFingerprint(List<MapPoint> points) {
  final StringBuffer text = StringBuffer();
  for (final MapPoint point in points) {
    text
      ..write(point.key)
      ..write(':')
      ..write(mapQuantum(point.x))
      ..write(':')
      ..write(mapQuantum(point.y))
      ..write('\n');
  }
  return stableHash(text.toString()).toRadixString(16).padLeft(8, '0');
}

/// Считает карту по мешкам книг.
///
/// Книги обходятся по возрастанию отпечатка файла — порядок, в котором
/// мешки пришли, на карту не влияет. `null` — карты нет: книг меньше
/// [kMinMapBooks] или больше, чем берёт точное разложение
/// ([kExactBooksLimit]).
BookMap? buildBookMap(List<BookBag> bags) {
  if (bags.length < kMinMapBooks || bags.length > kExactBooksLimit) {
    return null;
  }
  final List<BookBag> sorted = List<BookBag>.of(bags)
    ..sort((BookBag a, BookBag b) => a.key.compareTo(b.key));
  final int n = sorted.length;
  final MapVocabulary vocabulary = vocabularyOf(sorted);
  final List<SparseRow> rows = bm25Rows(sorted, vocabulary);
  final LatentRows latent = latentRows(gramOf(rows), n);
  final MapEdges edges = edgesOf(neighboursOf(latent));
  final List<String> groups = <String>[
    for (final BookBag bag in sorted) bag.group,
  ];
  final MapCoordinates place = layoutBooks(latent, edges, groups);
  final List<MapPoint> points = <MapPoint>[
    for (int i = 0; i < n; i++)
      MapPoint(key: sorted[i].key, x: place.xs[i], y: place.ys[i]),
  ];
  return BookMap(
    points: points,
    fingerprint: mapFingerprint(points),
    words: vocabulary.terms.length,
    edges: edges.length,
    groups: groups.toSet().length,
  );
}

/// Карта, как она лежит на устройстве.
class StoredBookMap {
  /// Создаёт запись карты.
  const StoredBookMap({
    required this.layoutKey,
    required this.version,
    required this.points,
  });

  /// Ключ набора книг, по которому карта посчитана: изменился набор
  /// или категории — ключ другой, и карта считается заново.
  final String layoutKey;

  /// Версия расчёта ([kBookMapVersion]).
  final int version;

  /// Места книг: идентификатор книги → точка. Ключ точки — отпечаток
  /// файла книги.
  final Map<String, MapPoint> points;
}

/// Хранилище карты. Реализация живёт в `infrastructure`.
///
/// **В облако не уходит никогда**: карта — производное, и на втором
/// устройстве она считается заново — и выходит той же самой.
abstract interface class BookMapRepository {
  /// Карта, лежащая на устройстве; `null` — карты нет.
  Future<StoredBookMap?> load();

  /// Кладёт карту вместо прежней — целиком, одной транзакцией.
  Future<void> replace(StoredBookMap map);

  /// Стирает карту.
  Future<void> clear();
}
