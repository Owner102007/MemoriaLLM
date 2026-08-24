import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/library/ids.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/files/file_fingerprint.dart';

/// Чем закончился импорт пачки книг.
class ImportReport {
  /// Создаёт отчёт.
  const ImportReport({required this.added, required this.failed});

  /// Книги, вставшие на полку. В порядке выбора.
  final List<Book> added;

  /// Файлы, которые завести не удалось, и причина у каждого.
  final List<ImportFailure> failed;

  /// Сколько файлов было выбрано.
  int get total => added.length + failed.length;

  /// Всё ли получилось.
  bool get isClean => failed.isEmpty;
}

/// Файл, который не удалось завести.
class ImportFailure {
  /// Создаёт запись об отказе.
  const ImportFailure({required this.name, required this.reason});

  /// Имя файла — по нему читатель поймёт, о какой книге речь.
  final String name;

  /// Что именно случилось, человеческими словами.
  final String reason;
}

/// Заводит выбранные файлы в библиотеке.
///
/// У книги должен быть постоянный идентификатор, иначе некуда записать
/// место, на котором её оставили, — с этого импорт и начался в S3. В S5.2
/// к нему добавились две вещи: книги заводятся пачкой и сразу в нужную
/// категорию полки.
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
       _newId = newId ?? newLibraryId,
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
  Future<Book> register(PickedFile file, {String? categoryId}) async {
    final BookSource source = await _storage.adopt(file);
    try {
      return await _save(
        source,
        titleFromFileName(file.name),
        null,
        categoryId: categoryId,
      );
    } on Object {
      // Приняли файл, а прочесть не смогли: отпускаем принятое, чтобы
      // не копить в папке приложения копии нечитаемых книг и не держать
      // закреплённых ссылок в никуда.
      await _storage.release(source);
      rethrow;
    }
  }

  /// Заводит сразу несколько выбранных файлов.
  ///
  /// Одна неудача не отменяет остальных: в папке с учебниками попадётся и
  /// битый файл, и защищённый паролем, и вовсе не PDF с расширением
  /// `.pdf`. Читателю важнее, чтобы встали двадцать девять книг из
  /// тридцати, чем чтобы импорт целиком провалился из-за одной.
  ///
  /// [onProgress] зовётся после каждого файла — полке есть что показать,
  /// пока идёт разбор: «добавлено 7 из 12».
  Future<ImportReport> registerAll(
    List<PickedFile> files, {
    String? categoryId,
    void Function(int done, int total)? onProgress,
  }) async {
    final List<Book> added = <Book>[];
    final List<ImportFailure> failed = <ImportFailure>[];
    for (int i = 0; i < files.length; i++) {
      final PickedFile file = files[i];
      try {
        added.add(await register(file, categoryId: categoryId));
      } on DocumentOpenException catch (error) {
        failed.add(
          ImportFailure(
            name: file.name,
            reason: describeDocumentProblem(error.problem),
          ),
        );
      } on Object {
        failed.add(
          ImportFailure(name: file.name, reason: 'файл не удалось прочесть'),
        );
      }
      onProgress?.call(i + 1, files.length);
    }
    return ImportReport(added: added, failed: failed);
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
  ///
  /// [categoryId] назначается только **новой** книге. Уже стоящую на
  /// полке импорт не переставляет: читатель мог унести её в другую
  /// категорию руками, и повторный выбор того же файла — не повод
  /// отменять это решение.
  Future<Book> _save(
    BookSource source,
    String title,
    Book? known, {
    String? categoryId,
  }) async {
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
            categoryId: categoryId,
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
