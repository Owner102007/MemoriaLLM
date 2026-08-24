/// Категория полки: участок библиотеки со своим узором и цветом.
///
/// Категория — не папка и не фильтр, а **место на полке**. Книга лежит
/// ровно в одной категории (решение владельца, 24.08.2026): полка должна
/// вести себя как настоящая, где книга физически стоит в одном месте, а
/// не как система меток, где счёт книг и удаление становятся
/// двусмысленными.
class BookCategory {
  /// Создаёт категорию.
  const BookCategory({
    required this.id,
    required this.title,
    required this.position,
    required this.createdAt,
  });

  /// Идентификатор. Одинаков на всех устройствах — категории поедут
  /// в синхронизацию вместе с книгами.
  final String id;

  /// Название. Оно же семя узора: см. `category_style.dart`.
  final String title;

  /// Порядок на полке. Меньше — выше.
  final int position;

  /// Когда заведена. Разводит категории с одинаковым порядком, чтобы
  /// полка не перетасовывалась от запуска к запуску.
  final DateTime createdAt;

  /// Копия с изменёнными полями.
  BookCategory copyWith({String? title, int? position, DateTime? createdAt}) {
    return BookCategory(
      id: id,
      title: title ?? this.title,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookCategory &&
      other.id == id &&
      other.title == title &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, title, position);

  @override
  String toString() => 'BookCategory($id, $title, $position)';
}

/// Название постоянной категории, в которой лежат книги без своей.
///
/// Она не строка в базе, а признак «категория не задана»: заводить её
/// записью значило бы уметь её переименовать, удалить и потерять, а полка
/// обязана открываться всегда.
const String kUncategorizedTitle = 'Без категории';

/// Ключ раздела «Без категории» в раскладке полки.
///
/// Пустая строка нарочно: идентификатором настоящей категории она быть не
/// может, поэтому спутать их нельзя.
const String kUncategorizedId = '';

/// Категории полки. Реализация живёт в `infrastructure`.
abstract interface class CategoryRepository {
  /// Живой список категорий в порядке полки.
  Stream<List<BookCategory>> watchCategories();

  /// Разовый снимок списка.
  Future<List<BookCategory>> categories();

  /// Категория по идентификатору или `null`.
  Future<BookCategory?> categoryById(String id);

  /// Добавляет категорию или обновляет существующую.
  Future<void> save(BookCategory category);

  /// Помечает категорию удалённой и возвращает её книги в «Без категории».
  ///
  /// Книги не удаляются вместе с категорией никогда: читатель убирал
  /// полку, а не библиотеку. Внешний ключ здесь не помощник — удаление
  /// у нас надгробие, а не `DELETE`, и каскад при нём не срабатывает.
  Future<void> delete(String id);

  /// Физически стирает помеченные удалёнными категории.
  Future<int> purgeDeleted();
}

/// Порядок категорий на полке.
///
/// Сначала заданный порядок, затем время создания, затем идентификатор:
/// три ступени нужны, чтобы список не перетасовывался при равных
/// значениях — иначе полка выглядит по-разному при каждом открытии.
int compareCategories(BookCategory a, BookCategory b) {
  final int byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) {
    return byPosition;
  }
  final int byTime = a.createdAt.compareTo(b.createdAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}

/// Приводит название категории к виду, в котором его можно сохранить.
///
/// Пустое название превращает раздел в безымянный прямоугольник, а
/// невидимые пробелы по краям делают две одинаковые на вид категории
/// разными — и то, и другое читатель сочтёт поломкой.
String normalizeCategoryTitle(String raw) {
  final String trimmed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return trimmed.isEmpty ? 'Новая категория' : trimmed;
}
