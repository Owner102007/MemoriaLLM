import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/map/book_map.dart';
import '../../domain/map/map_layout.dart';
import '../../domain/map/map_order.dart';
import '../../domain/map/map_trusted.dart';

/// Книга на карте — звезда (F-MAP-02, SNO-F-MAP-01).
class GalaxyStar {
  /// Создаёт звезду.
  const GalaxyStar({
    required this.book,
    required this.x,
    required this.y,
    required this.group,
    required this.ms,
    this.reason = MapReason.none,
  });

  /// Книга полки.
  final Book book;

  /// Абсцисса на карте, от −1 до 1.
  final double x;

  /// Ордината на карте, от −1 до 1.
  final double y;

  /// Созвездие книги — его имя (F-MAP-03); у книги без созвездия —
  /// [kUncategorizedTitle]. С S56 группы на карте складывает сама система
  /// адаптивным резонансом (F-MAP-16, D-029), а не полки.
  final String group;

  /// Сколько времени читатель провёл в книге, в миллисекундах.
  final int ms;

  /// Почему книга без созвездия (F-MAP-18) — строкой в карточке.
  final MapReason reason;
}

/// Что раздел «Галактика» может показать.
enum GalaxyStatus {
  /// Карта есть: звёзды стоят на местах.
  ready,

  /// Книг на полке меньше [kMinMapBooks]: карте не из чего сложиться.
  tooFew,

  /// Книги есть, а карты нет: она ещё не посчитана или не посчиталась.
  noMap,
}

/// Карта для экрана (F-MAP-06, F-MAP-11).
class Galaxy {
  /// Создаёт карту.
  const Galaxy({
    required this.status,
    required this.books,
    this.stars = const <GalaxyStar>[],
    this.constellations = const <String, List<GalaxyStar>>{},
  });

  /// Что можно показать.
  final GalaxyStatus status;

  /// Сколько книг на полке.
  final int books;

  /// Звёзды, по возрастанию отпечатка файла — в том же порядке, в каком
  /// карта считалась: порядок не зависит от того, как книги стоят на
  /// полке.
  final List<GalaxyStar> stars;

  /// Книги каждого созвездия — по его имени ([GalaxyStar.group]), от
  /// типичной к особенной (F-MAP-17, D-044): список по нажатию на имя
  /// созвездия. «Без категории» — тоже список, под [kUncategorizedTitle].
  final Map<String, List<GalaxyStar>> constellations;

  /// Сколько книг полки на карте места не получили: их добавили после
  /// расчёта, и место им даст следующая подготовка книг.
  int get missing => books - stars.length;
}

/// Собирает карту для экрана из того, что лежит на устройстве.
///
/// Карту здесь не считают: места книг берутся из хранилища [store],
/// куда их кладёт `MapBuilder`. Книга получает звезду, только если её
/// место посчитано по тому же файлу: у книги, привязанной к другому
/// файлу, место прежнего не годится. [times] — время чтения по книгам,
/// в миллисекундах (`BookTimes.times`).
Future<Galaxy> loadGalaxy({
  required LibraryRepository library,
  required BookMapRepository store,
  Map<String, int> times = const <String, int>{},
}) async {
  final List<Book> books = await library.books();
  if (books.length < kMinMapBooks) {
    return Galaxy(status: GalaxyStatus.tooFew, books: books.length);
  }
  final StoredBookMap? stored = await store.load();
  if (stored == null || stored.version != kBookMapVersion) {
    return Galaxy(status: GalaxyStatus.noMap, books: books.length);
  }
  final List<GalaxyStar> stars = <GalaxyStar>[];
  final List<MapPoint> placed = <MapPoint>[];
  final Map<String, GalaxyStar> byKey = <String, GalaxyStar>{};
  for (final Book book in books) {
    final MapPoint? point = stored.points[book.id];
    if (point == null || point.key != book.fileHash) {
      continue;
    }
    final GalaxyStar star = GalaxyStar(
      book: book,
      x: point.x,
      y: point.y,
      group: point.constellation < 0 ? kUncategorizedTitle : point.name,
      ms: times[book.id] ?? 0,
      reason: point.reason,
    );
    stars.add(star);
    // Две книги полки с одним файлом стоят на одной точке карты: в
    // списке созвездия — обе, но порядок у них общий.
    if (byKey.putIfAbsent(point.key, () => star) == star) {
      placed.add(point);
    }
  }
  if (stars.isEmpty) {
    return Galaxy(status: GalaxyStatus.noMap, books: books.length);
  }
  stars.sort(
    (GalaxyStar a, GalaxyStar b) => a.book.fileHash.compareTo(b.book.fileHash),
  );
  return Galaxy(
    status: GalaxyStatus.ready,
    books: books.length,
    stars: stars,
    constellations: _constellationsOf(stars, placed),
  );
}

/// Книги каждого созвездия от типичной к особенной (F-MAP-17).
///
/// Порядок даёт `constellationOrder` — с самой карты: типичная книга
/// стоит ближе всех к центру созвездия. Считаются только точки книг,
/// которые на полке и на карте ([placed]): книги, снятые с полки,
/// порядок не сдвигают.
Map<String, List<GalaxyStar>> _constellationsOf(
  List<GalaxyStar> stars,
  List<MapPoint> placed,
) {
  final Map<String, List<GalaxyStar>> byKey = <String, List<GalaxyStar>>{};
  for (final GalaxyStar star in stars) {
    byKey.putIfAbsent(star.book.fileHash, () => <GalaxyStar>[]).add(star);
  }
  final Set<int> numbers = <int>{
    for (final MapPoint point in placed) point.constellation,
  };
  final Map<String, List<GalaxyStar>> out = <String, List<GalaxyStar>>{};
  for (final int number in numbers.toList()..sort()) {
    final List<GalaxyStar> ordered = <GalaxyStar>[
      for (final MapPoint point in constellationOrder(placed, number))
        ...byKey[point.key]!,
    ];
    out[ordered.first.group] = List<GalaxyStar>.unmodifiable(ordered);
  }
  return out;
}
