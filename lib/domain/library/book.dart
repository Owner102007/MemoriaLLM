import 'book_source.dart';

/// Книга в библиотеке.
///
/// Место файла у каждого устройства своё, поэтому одну и ту же книгу на
/// телефоне и на ПК опознаёт [fileHash], а не [source]: это понадобится
/// синхронизации в S11.
class Book {
  /// Создаёт книгу.
  const Book({
    required this.id,
    required this.title,
    required this.source,
    required this.fileSize,
    required this.fileHash,
    required this.addedAt,
    this.author,
    this.pageCount,
    this.language,
    this.hasTextLayer,
    this.coverPath,
    this.openedAt,
    this.categoryId,
    this.shelfPosition = 0,
  });

  /// Идентификатор книги (UUID). Одинаков на всех устройствах.
  final String id;

  /// Заголовок: из метаданных PDF, иначе имя файла.
  final String title;

  /// Автор, если известен.
  final String? author;

  /// Где лежит книга на этом устройстве: путь, ссылка или наша копия.
  final BookSource source;

  /// Размер файла в байтах.
  final int fileSize;

  /// Отпечаток содержимого — опознание книги между устройствами.
  final String fileHash;

  /// Число страниц. Заполняется при первом открытии (S3).
  final int? pageCount;

  /// Язык книги. Определяется при разборе текста (S8).
  final String? language;

  /// Есть ли текстовый слой. `null` — ещё не проверяли; `false` — скан,
  /// о котором честно предупреждаем при импорте.
  final bool? hasTextLayer;

  /// Путь к кэшу обложки на этом устройстве (S5).
  final String? coverPath;

  /// Когда книга добавлена в библиотеку.
  final DateTime addedAt;

  /// Когда книгу открывали в последний раз.
  final DateTime? openedAt;

  /// Категория полки, в которой лежит книга.
  ///
  /// `null` — «Без категории»: постоянный раздел наверху полки. Он не
  /// строка в базе, а именно отсутствие категории, поэтому книги, которые
  /// завели до появления категорий, попадают туда сами и без миграции
  /// данных.
  final String? categoryId;

  /// Место книги на полке внутри своей категории.
  ///
  /// Читается только ручным порядком («Как расставил»). Остальные
  /// сортировки его не трогают: расстановка ждёт возврата к ручному
  /// порядку, а не пропадает при первом же переключении.
  final int shelfPosition;

  /// Копия с изменёнными полями. Обнулить поле копией нельзя — это
  /// осознанное упрощение: сбрасывать значения приходится редко.
  /// Исключение — [categoryId]: книга возвращается в «Без категории»
  /// достаточно часто, чтобы для этого был явный [withoutCategory].
  Book copyWith({
    String? title,
    String? author,
    BookSource? source,
    int? fileSize,
    String? fileHash,
    int? pageCount,
    String? language,
    bool? hasTextLayer,
    String? coverPath,
    DateTime? addedAt,
    DateTime? openedAt,
    String? categoryId,
    int? shelfPosition,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      source: source ?? this.source,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      addedAt: addedAt ?? this.addedAt,
      author: author ?? this.author,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      hasTextLayer: hasTextLayer ?? this.hasTextLayer,
      coverPath: coverPath ?? this.coverPath,
      openedAt: openedAt ?? this.openedAt,
      categoryId: categoryId ?? this.categoryId,
      shelfPosition: shelfPosition ?? this.shelfPosition,
    );
  }

  /// Та же книга, вернувшаяся в «Без категории».
  Book get withoutCategory => Book(
    id: id,
    title: title,
    source: source,
    fileSize: fileSize,
    fileHash: fileHash,
    addedAt: addedAt,
    author: author,
    pageCount: pageCount,
    language: language,
    hasTextLayer: hasTextLayer,
    coverPath: coverPath,
    openedAt: openedAt,
    shelfPosition: shelfPosition,
  );
}

/// Заголовок книги по имени файла.
///
/// Метаданных в PDF часто нет или в них лежит мусор вроде «Microsoft Word —
/// Document1», поэтому имя файла — не запасной вариант, а основной.
/// Расширение убирается, подчёркивания и точки между словами становятся
/// пробелами: `voyna_i_mir.pdf` читается лучше, чем `voyna_i_mir`.
String titleFromFileName(String fileName) {
  String name = fileName.trim();
  final int slash = name.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) {
    name = name.substring(slash + 1);
  }
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4);
  }
  name = name.replaceAll(RegExp(r'[_.]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  name = name.trim();
  return name.isEmpty ? 'Без названия' : name;
}

/// Куда встаёт книга: в какую категорию и на какое место.
class BookPlacement {
  /// Создаёт расстановку.
  const BookPlacement({
    required this.bookId,
    required this.categoryId,
    required this.position,
  });

  /// Книга.
  final String bookId;

  /// Категория; `null` — «Без категории».
  final String? categoryId;

  /// Место внутри категории, начиная с нуля.
  final int position;

  @override
  bool operator ==(Object other) =>
      other is BookPlacement &&
      other.bookId == bookId &&
      other.categoryId == categoryId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(bookId, categoryId, position);

  @override
  String toString() => 'BookPlacement($bookId → $categoryId, $position)';
}

/// Доступ к библиотеке. Реализация живёт в `infrastructure`.
abstract interface class LibraryRepository {
  /// Живой список книг: обновляется сам при изменениях в базе.
  Stream<List<Book>> watchBooks();

  /// Разовый снимок списка книг.
  Future<List<Book>> books();

  /// Книга по идентификатору или `null`, если её нет или она удалена.
  Future<Book?> bookById(String id);

  /// Книга по отпечатку файла — защита от повторного импорта.
  Future<Book?> bookByHash(String fileHash);

  /// Добавляет книгу или обновляет существующую.
  Future<void> save(Book book);

  /// Отмечает открытие книги.
  Future<void> markOpened(String id, DateTime when);

  /// Расставляет книги: у каждой меняются категория и место на полке.
  ///
  /// Одной транзакцией и обязательно целым списком: половина
  /// расставленной полки хуже, чем нерасставленная. Отдельный метод, а не
  /// `save` целых книг — перенос случается на полке, где под рукой только
  /// карточка, и перезаписывать из неё все поля книги значило бы затереть
  /// то, что параллельно записало чтение.
  Future<void> placeBooks(List<BookPlacement> placements);

  /// Ставит обложку книге. Путь местный и между устройствами не ездит.
  Future<void> setCoverPath(String bookId, String? coverPath);

  /// Возвращает книги категории в «Без категории».
  ///
  /// Нужно при удалении категории: удаление у нас надгробие, а не
  /// `DELETE`, и внешний ключ с каскадом при нём не срабатывает.
  Future<void> clearCategory(String categoryId);

  /// Помечает книгу удалённой (tombstone), не стирая строку: иначе
  /// удаление не доедет до второго устройства.
  Future<void> delete(String id);

  /// Физически стирает помеченные удалёнными книги вместе со всем, что
  /// на них ссылается. Вызывается сборщиком мусора после синхронизации.
  Future<int> purgeDeleted();
}
