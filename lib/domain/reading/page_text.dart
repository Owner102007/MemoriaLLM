/// Текст страниц книги как производный артефакт (F-TEXT-04, ALG-TXT-09).
///
/// Текст страницы — не свойство открытого документа, а то, что наш код
/// один раз извлёк из файла и запомнил на устройстве. Поиск по книге
/// читает запомненное и к движку PDF идёт только за тем, чего в кэше
/// ещё нет: слово из конца толстого тома находится сразу, а повторный
/// поиск не перечитывает книгу.
///
/// Здесь — только ключ, версия и интерфейс хранилища. Реализация живёт в
/// `infrastructure`, наполнение — в `application/reading/book_text.dart`.
library;

/// Версия алгоритма извлечения текста страниц (ALG-DATA-09).
///
/// Кэш текста — производное: его посчитал наш код, а не создал читатель.
/// Поменялось извлечение — число растёт, и страницы, запомненные прежним
/// алгоритмом, читаются из файла заново, по мере надобности и без
/// «очистить кэш». Остальные не трогаются.
const int kPageTextVersion = 1;

/// Чей текст запомнен и чем: книга, отпечаток файла, версия алгоритма.
///
/// Отпечаток нужен затем же, зачем рамке книги: книгу можно привязать к
/// другому файлу — идентификатор у неё при этом прежний, а текст страниц
/// прежнего файла новому не годится.
class PageTextKey {
  /// Создаёт ключ.
  const PageTextKey({
    required this.bookId,
    required this.fingerprint,
    this.version = kPageTextVersion,
  });

  /// Книга.
  final String bookId;

  /// Отпечаток файла, из которого текст извлечён.
  final String fingerprint;

  /// Версия алгоритма извлечения.
  final int version;

  @override
  bool operator ==(Object other) {
    return other is PageTextKey &&
        other.bookId == bookId &&
        other.fingerprint == fingerprint &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(bookId, fingerprint, version);

  @override
  String toString() => 'PageTextKey($bookId, $fingerprint, v$version)';
}

/// Хранилище текста страниц. Реализация живёт в `infrastructure`.
///
/// **В облако не уходит никогда**: это производное, и на втором
/// устройстве оно извлекается из файла заново.
///
/// Страница, запомненная по другому отпечатку или другой версией
/// алгоритма, для этого ключа не существует: её нет ни в [cachedPages],
/// ни в [pageTexts], а [savePageTexts] записывает поверх неё.
abstract interface class PageTextRepository {
  /// Какие страницы книги запомнены: страница → длина её текста в
  /// знаках. Ноль — страница без текста, и это тоже ответ: за ней к
  /// движку больше не ходят.
  Future<Map<int, int>> cachedPages(PageTextKey key);

  /// Запомненный текст страниц с [from] по [to] включительно: страница →
  /// текст. Страниц, которых в кэше нет, нет и в ответе.
  Future<Map<int, String>> pageTexts(
    PageTextKey key, {
    required int from,
    required int to,
  });

  /// Запоминает текст страниц: страница → текст.
  Future<void> savePageTexts(PageTextKey key, Map<int, String> texts);
}
