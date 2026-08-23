import 'dart:math';

import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/files/file_fingerprint.dart';

/// Заводит выбранный файл в библиотеке.
///
/// Полноценный импорт с обложками и сеткой книг — задача S5.2. Здесь
/// ровно столько, сколько нужно чтению: у книги должен быть постоянный
/// идентификатор, иначе некуда записать место, на котором её оставили.
class BookImporter {
  /// Создаёт сценарий импорта.
  ///
  /// [fingerprint] и [newId] подменяются в тестах: первый читает книгу,
  /// второй недетерминирован, и оба мешают проверять сам сценарий.
  BookImporter({
    required LibraryRepository library,
    required BookStorage storage,
    required DocumentOpener opener,
    Future<String> Function(BookHandle book)? fingerprint,
    String Function()? newId,
    DateTime Function()? now,
  }) : _library = library,
       _storage = storage,
       _opener = opener,
       _fingerprint = fingerprint ?? bookFingerprint,
       _newId = newId ?? _randomId,
       _now = now ?? DateTime.now;

  final LibraryRepository _library;
  final BookStorage _storage;
  final DocumentOpener _opener;
  final Future<String> Function(BookHandle book) _fingerprint;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Заводит выбранный файл и возвращает книгу.
  ///
  /// Сначала файл принимается хранилищем: на Android закрепляется
  /// разрешение на ссылку, а книга, которую нельзя читать кусками,
  /// потоково переносится к нам. Только потом она разбирается движком.
  ///
  /// Если такая книга уже на полке (совпал отпечаток), заводится не
  /// вторая её копия, а обновляется источник у прежней: файл мог
  /// переехать, но место, на котором книгу оставили, принадлежит книге,
  /// а не файлу.
  ///
  /// Бросает [DocumentOpenException], если файл не открывается: заводить
  /// в библиотеке книгу, которую нельзя прочесть, незачем.
  Future<Book> register(PickedFile file) async {
    final BookSource source = await _storage.adopt(file);
    try {
      return await _save(source, titleFromFileName(file.name), null);
    } on Object {
      // Приняли файл, а прочесть не смогли: отпускаем принятое, чтобы
      // не копить в папке приложения копии нечитаемых книг и не держать
      // закреплённых ссылок в никуда.
      await _storage.release(source);
      rethrow;
    }
  }

  /// Привязывает книгу к заново выбранному файлу.
  ///
  /// Нужно, когда файл переименовали, перенесли или отозвали разрешение
  /// на ссылку. Идентификатор книги остаётся прежним, поэтому место
  /// чтения, цитаты и заметки не теряются: они принадлежат книге, а не
  /// файлу.
  Future<Book> relink(Book book, PickedFile file) async {
    final BookSource source = await _storage.adopt(file);
    final BookSource previous = book.source;
    final Book relinked;
    try {
      relinked = await _save(source, book.title, book);
    } on Object {
      await _storage.release(source);
      rethrow;
    }
    if (previous != source) {
      await _storage.release(previous);
    }
    return relinked;
  }

  /// Разбирает книгу и кладёт её на полку.
  ///
  /// [known] — книга, к которой файл привязывается принудительно; если
  /// его нет, книга ищется по отпечатку.
  Future<Book> _save(BookSource source, String title, Book? known) async {
    final BookHandle handle = await _storage.open(source);
    final String hash;
    final int size;
    try {
      hash = await _fingerprint(handle);
      size = handle.length;
    } finally {
      await handle.close();
    }

    final Book? existing = known ?? await _library.bookByHash(hash);

    final ReaderDocument document = await _opener.open(source);
    final int pageCount;
    final bool textLayer;
    try {
      pageCount = document.pageCount;
      textLayer = await hasTextLayer(document);
    } finally {
      await document.close();
    }

    final DateTime moment = _now();
    final Book book = existing == null
        ? Book(
            id: _newId(),
            title: title,
            source: source,
            fileSize: size,
            fileHash: hash,
            addedAt: moment,
            pageCount: pageCount,
            hasTextLayer: textLayer,
            openedAt: moment,
          )
        : existing.copyWith(
            source: source,
            fileSize: size,
            fileHash: hash,
            pageCount: pageCount,
            hasTextLayer: textLayer,
            openedAt: moment,
          );
    await _library.save(book);
    return book;
  }
}

final Random _random = Random.secure();

/// Идентификатор книги: UUID-подобная строка из случайных байтов.
///
/// Пакет ради генерации шестнадцати байт не подключается: пользы от него
/// здесь на одну строку, а в открытом проекте каждая зависимость — это
/// ещё и лицензия, которую придётся объяснять.
String _randomId() {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < 16; i++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    if (i == 3 || i == 5 || i == 7 || i == 9) {
      buffer.write('-');
    }
  }
  return buffer.toString();
}
