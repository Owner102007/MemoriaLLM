/// Цитата — сохранённый фрагмент текста книги.
class Quote {
  /// Создаёт цитату.
  const Quote({
    required this.id,
    required this.bookId,
    required this.page,
    required this.content,
    required this.createdAt,
    this.context,
    this.color,
  });

  /// Идентификатор (UUID).
  final String id;

  /// Книга.
  final String bookId;

  /// Страница, с которой снята цитата.
  final int page;

  /// Сам текст цитаты.
  final String content;

  /// Абзац вокруг выделения. Нужен LLM, чтобы объяснять слово в контексте
  /// (S6 достаёт его по координатам, S8 передаёт модели).
  final String? context;

  /// Цвет маркера в формате `0xAARRGGBB`.
  final int? color;

  /// Когда цитата сохранена.
  final DateTime createdAt;
}

/// Заметка читателя. Может быть привязана к цитате, а может стоять сама
/// по себе — как пометка на полях.
class Note {
  /// Создаёт заметку.
  const Note({
    required this.id,
    required this.bookId,
    required this.page,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.quoteId,
  });

  /// Идентификатор (UUID).
  final String id;

  /// Книга.
  final String bookId;

  /// Цитата, к которой привязана заметка.
  final String? quoteId;

  /// Страница.
  final int page;

  /// Текст заметки.
  final String body;

  /// Когда создана.
  final DateTime createdAt;

  /// Когда изменялась в последний раз.
  final DateTime updatedAt;

  /// Копия с изменённым текстом.
  Note copyWith({String? body, DateTime? updatedAt}) {
    return Note(
      id: id,
      bookId: bookId,
      page: page,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      quoteId: quoteId,
    );
  }
}

/// Закладка на месте в книге.
class Bookmark {
  /// Создаёт закладку.
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.page,
    required this.createdAt,
    this.fragment = 0,
    this.label,
  });

  /// Идентификатор (UUID).
  final String id;

  /// Книга.
  final String bookId;

  /// Страница.
  final int page;

  /// Фрагмент внутри страницы — режимы половины и трети (S4).
  final int fragment;

  /// Подпись закладки.
  final String? label;

  /// Когда поставлена.
  final DateTime createdAt;
}

/// Цитаты, заметки и закладки. Реализация живёт в `infrastructure`.
abstract interface class AnnotationRepository {
  /// Живой список цитат книги, новые сверху.
  Stream<List<Quote>> watchQuotes(String bookId);

  /// Разовый снимок цитат книги.
  Future<List<Quote>> quotes(String bookId);

  /// Добавляет или обновляет цитату.
  Future<void> saveQuote(Quote quote);

  /// Помечает цитату удалённой.
  Future<void> deleteQuote(String id);

  /// Живой список заметок книги.
  Stream<List<Note>> watchNotes(String bookId);

  /// Разовый снимок заметок книги.
  Future<List<Note>> notes(String bookId);

  /// Добавляет или обновляет заметку.
  Future<void> saveNote(Note note);

  /// Помечает заметку удалённой.
  Future<void> deleteNote(String id);

  /// Живой список закладок книги по возрастанию страниц.
  Stream<List<Bookmark>> watchBookmarks(String bookId);

  /// Разовый снимок закладок книги.
  Future<List<Bookmark>> bookmarks(String bookId);

  /// Ставит или обновляет закладку.
  Future<void> saveBookmark(Bookmark bookmark);

  /// Помечает закладку удалённой.
  Future<void> deleteBookmark(String id);
}
