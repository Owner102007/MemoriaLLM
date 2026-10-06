import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/map/book_map.dart';
import '../../domain/map/map_layout.dart';

/// Книга на карте — звезда (F-MAP-02, SNO-F-MAP-01).
class GalaxyStar {
  /// Создаёт звезду.
  const GalaxyStar({
    required this.book,
    required this.x,
    required this.y,
    required this.group,
    required this.ms,
  });

  /// Книга полки.
  final Book book;

  /// Абсцисса на карте, от −1 до 1.
  final double x;

  /// Ордината на карте, от −1 до 1.
  final double y;

  /// Название категории книги; у книги без категории —
  /// [kUncategorizedTitle]. Группа на карте — категория полки (решение
  /// владельца Э4 от 05.10.2026).
  final String group;

  /// Сколько времени читатель провёл в книге, в миллисекундах.
  final int ms;
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
  });

  /// Что можно показать.
  final GalaxyStatus status;

  /// Сколько книг на полке.
  final int books;

  /// Звёзды, по возрастанию отпечатка файла — в том же порядке, в каком
  /// карта считалась: порядок не зависит от того, как книги стоят на
  /// полке.
  final List<GalaxyStar> stars;

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
  required CategoryRepository categories,
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
  final Map<String, String> titles = <String, String>{
    for (final BookCategory category in await categories.categories())
      category.id: category.title,
  };
  final List<GalaxyStar> stars = <GalaxyStar>[];
  for (final Book book in books) {
    final MapPoint? point = stored.points[book.id];
    if (point == null || point.key != book.fileHash) {
      continue;
    }
    stars.add(
      GalaxyStar(
        book: book,
        x: point.x,
        y: point.y,
        group: titles[book.categoryId] ?? kUncategorizedTitle,
        ms: times[book.id] ?? 0,
      ),
    );
  }
  if (stars.isEmpty) {
    return Galaxy(status: GalaxyStatus.noMap, books: books.length);
  }
  stars.sort(
    (GalaxyStar a, GalaxyStar b) =>
        a.book.fileHash.compareTo(b.book.fileHash),
  );
  return Galaxy(
    status: GalaxyStatus.ready,
    books: books.length,
    stars: stars,
  );
}
