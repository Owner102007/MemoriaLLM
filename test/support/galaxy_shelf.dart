import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_map.dart';

/// Книга полки с местом на карте — заготовка тестов «Галактики»
/// (SNO-F-MAP-01).
class ShelfStar {
  /// Создаёт заготовку.
  const ShelfStar(
    this.id,
    this.title,
    this.x,
    this.y, {
    this.category,
    this.onMap = true,
  });

  /// Идентификатор книги; отпечаток файла — `hash-<id>`.
  final String id;

  /// Название.
  final String title;

  /// Абсцисса на карте.
  final double x;

  /// Ордината на карте.
  final double y;

  /// Идентификатор категории; `null` — «Без категории».
  final String? category;

  /// Есть ли у книги место на карте.
  final bool onMap;
}

/// Полка из двух категорий — как архив владельца: «Ангиология» слева,
/// «Математика» справа; книги расставлены так, чтобы по каждой можно
/// было попасть, не задев соседнюю.
const List<ShelfStar> kTwoGroups = <ShelfStar>[
  ShelfStar('a1', 'Клиническая ангиология', -0.8, -0.6, category: 'ang'),
  ShelfStar('a2', 'Сосудистая хирургия', -0.4, -0.2, category: 'ang'),
  ShelfStar('a3', 'Флебология', -0.7, 0.3, category: 'ang'),
  ShelfStar('m1', 'Математический анализ', 0.6, -0.5, category: 'math'),
  ShelfStar('m2', 'Линейная алгебра', 0.8, 0.1, category: 'math'),
  ShelfStar('m3', 'Теория вероятностей', 0.3, 0.6, category: 'math'),
];

/// Названия категорий заготовок.
const Map<String, String> kGalaxyCategories = <String, String>{
  'ang': 'Ангиология',
  'math': 'Математика',
};

/// Отпечаток файла книги-заготовки.
String hashOfStar(String id) => 'hash-$id';

/// Кладёт на полку книги [stars] и их категории, а на устройство —
/// карту: место каждой книги, у которой оно есть.
///
/// [withMap] — класть ли карту вовсе; [version] — какой версией расчёта
/// она «посчитана».
Future<void> seedGalaxy(
  AppData data,
  List<ShelfStar> stars, {
  bool withMap = true,
  int version = kBookMapVersion,
}) async {
  int position = 0;
  for (final MapEntry<String, String> entry in kGalaxyCategories.entries) {
    await data.categories.save(
      BookCategory(
        id: entry.key,
        title: entry.value,
        position: position++,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
  }
  for (int i = 0; i < stars.length; i++) {
    final ShelfStar star = stars[i];
    await data.library.save(
      Book(
        id: star.id,
        title: star.title,
        author: 'Автор ${star.id}',
        source: FilePathSource('/books/${star.id}.pdf'),
        fileSize: 1024,
        fileHash: hashOfStar(star.id),
        addedAt: DateTime.utc(2026, 10, 1, 12),
        categoryId: star.category,
        shelfPosition: i,
      ),
    );
  }
  if (!withMap) {
    return;
  }
  await data.bookMap.replace(
    StoredBookMap(
      layoutKey: 'набор',
      version: version,
      points: <String, MapPoint>{
        for (final ShelfStar star in stars)
          if (star.onMap)
            star.id: MapPoint(key: hashOfStar(star.id), x: star.x, y: star.y),
      },
    ),
  );
}
