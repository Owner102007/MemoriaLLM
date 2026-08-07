/// Книга в библиотеке.
///
/// Путь к файлу у каждого устройства свой, поэтому одну и ту же книгу на
/// телефоне и на ПК опознаёт [fileHash], а не [filePath]: это понадобится
/// синхронизации в S11.
class Book {
  /// Создаёт книгу.
  const Book({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileSize,
    required this.fileHash,
    required this.addedAt,
    this.author,
    this.pageCount,
    this.language,
    this.hasTextLayer,
    this.coverPath,
    this.openedAt,
  });

  /// Идентификатор книги (UUID). Одинаков на всех устройствах.
  final String id;

  /// Заголовок: из метаданных PDF, иначе имя файла.
  final String title;

  /// Автор, если известен.
  final String? author;

  /// Путь к файлу на этом устройстве.
  final String filePath;

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

  /// Копия с изменёнными полями. Обнулить поле копией нельзя — это
  /// осознанное упрощение: сбрасывать значения приходится редко.
  Book copyWith({
    String? title,
    String? author,
    String? filePath,
    int? fileSize,
    String? fileHash,
    int? pageCount,
    String? language,
    bool? hasTextLayer,
    String? coverPath,
    DateTime? addedAt,
    DateTime? openedAt,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      addedAt: addedAt ?? this.addedAt,
      author: author ?? this.author,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      hasTextLayer: hasTextLayer ?? this.hasTextLayer,
      coverPath: coverPath ?? this.coverPath,
      openedAt: openedAt ?? this.openedAt,
    );
  }
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

  /// Помечает книгу удалённой (tombstone), не стирая строку: иначе
  /// удаление не доедет до второго устройства.
  Future<void> delete(String id);

  /// Физически стирает помеченные удалёнными книги вместе со всем, что
  /// на них ссылается. Вызывается сборщиком мусора после синхронизации.
  Future<int> purgeDeleted();
}
