/// Что просили у модели.
enum LlmTask {
  /// Объяснить слово или выражение в контексте.
  meaning,

  /// Перевести выделение.
  translate,
}

/// Кто отвечал.
enum LlmSource {
  /// Облачная модель через свой прокси.
  cloud,

  /// Модель на устройстве.
  local,
}

/// Запрос к модели и её ответ.
///
/// История — не только журнал: она же кэш. Повторное выделение того же
/// слова в том же контексте не должно стоить ни запроса в сеть, ни
/// нагрева телефона локальной моделью.
class LlmQuery {
  /// Создаёт запись истории.
  const LlmQuery({
    required this.id,
    required this.task,
    required this.selection,
    required this.createdAt,
    this.bookId,
    this.context,
    this.sourceLanguage,
    this.targetLanguage,
    this.answer,
    this.source,
    this.model,
    this.latencyMs,
    this.error,
  });

  /// Идентификатор (UUID).
  final String id;

  /// Книга, если запрос сделан во время чтения.
  final String? bookId;

  /// Задача.
  final LlmTask task;

  /// Выделенный текст.
  final String selection;

  /// Абзац вокруг выделения.
  final String? context;

  /// Язык книги.
  final String? sourceLanguage;

  /// Язык, на который переводим.
  final String? targetLanguage;

  /// Ответ модели. `null`, если запрос не удался.
  final String? answer;

  /// Кто отвечал.
  final LlmSource? source;

  /// Имя модели — пригодится, когда придётся сравнивать качество.
  final String? model;

  /// Сколько ждали ответ, миллисекунды.
  final int? latencyMs;

  /// Текст ошибки, если ответа нет.
  final String? error;

  /// Когда запрос сделан.
  final DateTime createdAt;
}

/// История запросов к модели. Реализация живёт в `infrastructure`.
abstract interface class LlmHistoryRepository {
  /// Сохраняет запись.
  Future<void> save(LlmQuery query);

  /// Живая история по книге, новые сверху.
  Stream<List<LlmQuery>> watchForBook(String bookId);

  /// Ищет готовый ответ на такой же запрос.
  Future<LlmQuery?> cached({
    required LlmTask task,
    required String selection,
    String? context,
    String? targetLanguage,
  });

  /// Помечает запись удалённой.
  Future<void> delete(String id);
}
