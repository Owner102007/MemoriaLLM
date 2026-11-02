/// Карта книг: от мешков слов до координат (F-MAP-02, SNO-F-MAP-01).
///
/// Здесь расчёт собран целиком — словарь корпуса, BM25, главные
/// компоненты, соседи, раскладка — и описано, где карта хранится.
/// Чистые функции: ни базы, ни файлов, ни Flutter; в приложении расчёт
/// уходит в изолят (`application/map/map_builder.dart`).
library;

import 'dart:typed_data';

import '../library/stable_hash.dart';
import 'book_bag.dart';
import 'map_categories.dart';
import 'map_layout.dart';
import 'map_names.dart';
import 'map_order.dart';
import 'map_vectors.dart';

/// Версия расчёта карты (ALG-DATA-09).
///
/// Карта — производное: её посчитал наш код, а не создал читатель.
/// Поменялся расчёт — число растёт, и карта, посчитанная прежней
/// версией, считается заново. Число входит и в ключ набора книг
/// (`MapBuilder.keyOf`).
///
/// 2 — S56: группы карты складывает адаптивный резонанс, а не полки
/// (F-MAP-16), у созвездий есть имена (F-MAP-03).
/// 3 — S57: внутри созвездия типичная книга ближе к центру (F-MAP-17).
const int kBookMapVersion = 3;

/// Группа раскладки по номеру созвездия: `art:0000`, `art:0001` …;
/// у книги без созвездия — пустая строка (раскладка не тянет её ни к
/// какому центру). Ноли впереди — чтобы группы шли по порядку и как
/// строки: раскладка перебирает их по алфавиту.
String constellationGroup(int constellation) =>
    constellation < 0 ? '' : 'art:${constellation.toString().padLeft(4, '0')}';

/// Место одной книги на карте.
class MapPoint {
  /// Создаёт точку.
  const MapPoint({
    required this.key,
    required this.x,
    required this.y,
    this.constellation = kNoCategory,
    this.name = '',
  });

  /// Отпечаток файла книги.
  final String key;

  /// Абсцисса, от −1 до 1.
  final double x;

  /// Ордината, от −1 до 1.
  final double y;

  /// Созвездие книги (F-MAP-16): 0, 1, 2 …; −1 — без созвездия (у книги
  /// нет значимых слов).
  final int constellation;

  /// Имя созвездия (F-MAP-03); у книги без созвездия — пусто.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is MapPoint &&
      other.key == key &&
      other.x == x &&
      other.y == y &&
      other.constellation == constellation &&
      other.name == name;

  @override
  int get hashCode => Object.hash(key, x, y, constellation, name);

  @override
  String toString() => 'MapPoint($key, $x, $y, $constellation, $name)';
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

  /// Сколько групп на карте — созвездий; книги без созвездия — тоже
  /// группа.
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
  final Float64List gram = gramOf(rows);
  final LatentRows latent = latentRows(gram, n);
  final MapEdges edges = edgesOf(neighboursOf(latent));
  // Созвездия складывает адаптивный резонанс (F-MAP-16, D-029); группа
  // раскладки — созвездие, а не категория полки.
  final List<int> constellations = artCategories(gram, n).labels;
  final List<String> names = constellationNames(
    sorted,
    vocabulary,
    constellations,
  );
  final List<String> groups = <String>[
    for (final int c in constellations) constellationGroup(c),
  ];
  // Раскладка ставит группу на место, а порядок книг внутри неё задаёт
  // правило: типичная — ближе к центру созвездия (F-MAP-17, D-044).
  final MapCoordinates place = orderWithinGroups(
    layoutBooks(latent, edges, groups),
    typicalities(gram, n, constellations),
    constellations,
  );
  final List<MapPoint> points = <MapPoint>[
    for (int i = 0; i < n; i++)
      MapPoint(
        key: sorted[i].key,
        x: place.xs[i],
        y: place.ys[i],
        constellation: constellations[i],
        name: constellations[i] < 0 ? '' : names[constellations[i]],
      ),
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
