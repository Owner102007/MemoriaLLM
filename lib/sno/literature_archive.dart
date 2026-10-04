/// Архив с книгами встаёт полкой (SNO-F-LIT-01, SNO-ALG-LIT-01).
///
/// Литература исследования СНО2026 приходит тестировщику одним
/// ZIP-архивом (решение владельца 04.10.2026): в установщик она не
/// вшита. Экспериментатор выбирает архив в разделе «Тестирование», и
/// книги раскладываются по полке: папка архива — категория, порядок — по
/// именам (`domain/library/shelf_archive.dart`).
///
/// Книга распаковывается потоком в файл `.part` в папке приложения и
/// готовой получает имя по отпечатку содержимого — тем же путём, каким
/// встаёт книга, добавленная файлом (`book_copy.dart`). Отсюда три
/// свойства, ради которых так сделано: память не растёт с размером
/// книги; тот же архив, добавленный ещё раз, ничего не дублирует;
/// оборванная распаковка не оставляет обрезанного файла под именем
/// книги, а повторное добавление доводит полку до конца.
library;

import 'dart:io';
import 'dart:typed_data';

import '../application/library/book_importer.dart';
import '../domain/library/book.dart';
import '../domain/library/book_category.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/library/book_source.dart';
import '../domain/library/book_storage.dart';
import '../domain/library/ids.dart';
import '../domain/library/shelf.dart';
import '../domain/library/shelf_archive.dart';
import '../domain/reading/reader_document.dart';
import '../infrastructure/files/book_copy.dart';
import '../infrastructure/files/file_fingerprint.dart';
import '../infrastructure/files/zip_reader.dart';

/// Какая книга распаковывается сейчас.
class ArchiveProgress {
  /// Создаёт отметку хода.
  const ArchiveProgress({
    required this.number,
    required this.total,
    required this.title,
    this.category,
  });

  /// Номер книги, считая с единицы.
  final int number;

  /// Сколько книг в архиве.
  final int total;

  /// Название книги.
  final String title;

  /// Категория, в которую она встаёт; `null` — «Без категории».
  final String? category;
}

/// Чем закончилось добавление архива.
class ArchiveReport {
  /// Создаёт отчёт.
  const ArchiveReport({
    required this.archive,
    this.total = 0,
    this.added = const <Book>[],
    this.already = 0,
    this.skipped = 0,
    this.failed = const <ImportFailure>[],
    this.refusal,
    this.stopped,
  });

  /// Имя файла архива.
  final String archive;

  /// Сколько книг (PDF) в архиве.
  final int total;

  /// Книги, которых на полке не было и которые встали на неё.
  final List<Book> added;

  /// Сколько книг архива уже стояло на полке: они не дублируются и с
  /// места не сдвигаются.
  final int already;

  /// Сколько файлов архива пропущено, потому что это не PDF.
  final int skipped;

  /// Книги, которые не встали на полку, с причиной у каждой.
  final List<ImportFailure> failed;

  /// Почему архив не принят вовсе; `null` — принят.
  final String? refusal;

  /// Почему распаковка остановилась, не дойдя до конца; `null` — дошла.
  /// Уже распакованное при этом остаётся на полке.
  final String? stopped;

  /// Сколько категорий получили новые книги.
  int get categories {
    return <String>{
      for (final Book book in added)
        if (book.categoryId != null) book.categoryId!,
    }.length;
  }
}

/// Добавление архива: то, что раздел «Тестирование» зовёт по кнопке.
///
/// Отдельным типом — чтобы widget-тест раздела подставлял своё: в нём
/// не должно быть настоящего файлового ввода-вывода.
typedef ArchiveUnpack = Future<ArchiveReport> Function(
  PickedFile archive, {
  void Function(ArchiveProgress progress)? onProgress,
});

/// Причина отказа архива — словами для экспериментатора.
///
/// У каждой причины сказано, что делать: архив собирают руками, и
/// «не удалось» без пояснения оставило бы человека гадать.
String describeZipProblem(ZipProblem problem) {
  return switch (problem) {
    ZipProblem.notZip => 'это не ZIP-архив',
    ZipProblem.truncated => 'архив оборван — перешлите или скачайте его заново',
    ZipProblem.damaged => 'архив повреждён',
    ZipProblem.encrypted =>
      'архив защищён паролем — пересоберите его без пароля',
    ZipProblem.unsupportedMethod =>
      'способ сжатия не ZIP-овский (LZMA, bzip2) — пересоберите '
          'обычным ZIP',
    ZipProblem.multiDisk => 'архив разбит на тома — пересоберите одним файлом',
    ZipProblem.badChecksum =>
      'контрольная сумма не сошлась — файл в архиве повреждён',
    ZipProblem.unreadable => 'архив не удалось прочесть',
  };
}

/// Почему книгу не удалось записать — словами.
///
/// Нехватка места названа прямо: это единственный отказ записи, с
/// которым экспериментатор может что-то сделать сам.
String describeWriteFailure(FileSystemException error) {
  final int? code = error.osError?.errorCode;
  // 28 — ENOSPC у Android и Linux; 112 и 39 — «диск полон» у Windows.
  final bool full = Platform.isWindows ? code == 112 || code == 39 : code == 28;
  return full
      ? 'на устройстве кончилось место'
      : 'книгу не удалось записать на устройство';
}

/// Раскладывает архив с книгами по полке (SNO-F-LIT-01).
class LiteratureArchive {
  /// Создаёт сценарий.
  ///
  /// [booksDirectory] — папка копий книг; подменяется в тестах, как у
  /// хранилища Android. [newId] и [now] подменяются там же.
  LiteratureArchive({
    required LibraryRepository library,
    required CategoryRepository categories,
    required BookStorage storage,
    required DocumentOpener opener,
    Future<Directory> Function()? booksDirectory,
    String Function()? newId,
    DateTime Function()? now,
  }) : _library = library,
       _categories = categories,
       _storage = storage,
       _booksDirectory = booksDirectory ?? applicationBooks,
       _newId = newId ?? newLibraryId,
       _now = now ?? DateTime.now,
       _importer = BookImporter(
         library: library,
         storage: storage,
         opener: opener,
         newId: newId,
         now: now,
       );

  final LibraryRepository _library;
  final CategoryRepository _categories;
  final BookStorage _storage;
  final Future<Directory> Function() _booksDirectory;
  final String Function() _newId;
  final DateTime Function() _now;
  final BookImporter _importer;

  /// Добавляет книги архива [file] на полку.
  ///
  /// Не бросает: всё, что пошло не так, названо в отчёте словами.
  /// [onProgress] зовётся перед каждой книгой.
  Future<ArchiveReport> add(
    PickedFile file, {
    void Function(ArchiveProgress progress)? onProgress,
  }) async {
    final _Opened opened;
    try {
      opened = await _open(file);
    } on ZipException catch (error) {
      return ArchiveReport(
        archive: file.name,
        refusal: describeZipProblem(error.problem),
      );
    } on Object {
      return ArchiveReport(
        archive: file.name,
        refusal: describeZipProblem(ZipProblem.unreadable),
      );
    }
    try {
      return await _unpack(file.name, opened.archive, onProgress);
    } finally {
      await opened.handle.close();
      final BookSource? borrowed = opened.borrowed;
      if (borrowed != null) {
        await _storage.release(borrowed);
      }
    }
  }

  /// Открывает архив там, где он лежит.
  ///
  /// На Windows это файл. На Android — документ по ссылке: он читается
  /// на месте, без копии, и места на устройстве нужно только под сами
  /// книги. Если провайдер отдал поток, по которому нельзя перескакивать
  /// (так делают облачные хранилища), архив сначала переносится в
  /// приложение — как книга в таком же случае — и убирается после.
  Future<_Opened> _open(PickedFile file) async {
    final String? path = file.path;
    final BookSource direct = path != null
        ? FilePathSource(path)
        : DocumentUriSource(file.uri!);
    try {
      return await _read(direct);
    } on ZipException catch (error) {
      if (path != null || error.problem != ZipProblem.unreadable) {
        rethrow;
      }
    } on BookUnavailableException {
      if (path != null) {
        throw const ZipException(ZipProblem.unreadable);
      }
    }
    final BookSource copy = await _storage.adopt(file);
    try {
      return await _read(copy, borrowed: copy);
    } on Object {
      await _storage.release(copy);
      rethrow;
    }
  }

  Future<_Opened> _read(BookSource source, {BookSource? borrowed}) async {
    final BookHandle handle = await _storage.open(source);
    try {
      return _Opened(handle, await ZipArchive.read(handle), borrowed);
    } on Object {
      await handle.close();
      rethrow;
    }
  }

  Future<ArchiveReport> _unpack(
    String name,
    ZipArchive archive,
    void Function(ArchiveProgress progress)? onProgress,
  ) async {
    final ArchiveLayout layout = layoutShelfArchive(<String>[
      for (final ZipEntry entry in archive.entries) entry.name,
    ]);
    final int total = layout.books.length;
    if (total == 0) {
      return ArchiveReport(
        archive: name,
        skipped: layout.skipped,
        refusal: 'в архиве нет ни одного PDF',
      );
    }
    // Пароль и чужое сжатие — отказ до первой книги: такой архив
    // пересобирают целиком, и половина полки из него никому не нужна.
    for (final ArchiveBook book in layout.books) {
      final ZipEntry entry = archive.entries[book.entry];
      if (entry.isEncrypted || !entry.isSupported) {
        return ArchiveReport(
          archive: name,
          total: total,
          skipped: layout.skipped,
          refusal: describeZipProblem(
            entry.isEncrypted
                ? ZipProblem.encrypted
                : ZipProblem.unsupportedMethod,
          ),
        );
      }
    }

    final List<Book> added = <Book>[];
    final List<ImportFailure> failed = <ImportFailure>[];
    int already = 0;
    String? stopped;
    final Directory books;
    try {
      books = await _booksDirectory();
      if (!await books.exists()) {
        await books.create(recursive: true);
      }
      // Недописанное с прошлого раза — мусор: приложение закрыли
      // посреди распаковки.
      await sweepIncoming(books);
    } on FileSystemException catch (error) {
      return ArchiveReport(
        archive: name,
        total: total,
        skipped: layout.skipped,
        stopped: describeWriteFailure(error),
      );
    }

    final Map<String, String> categoryIds = <String, String>{};
    for (int i = 0; i < total; i++) {
      final ArchiveBook planned = layout.books[i];
      onProgress?.call(
        ArchiveProgress(
          number: i + 1,
          total: total,
          title: planned.title,
          category: planned.category,
        ),
      );
      final ZipEntry entry = archive.entries[planned.entry];
      try {
        // Книга без сжатия лежит в архиве как есть — её отпечаток
        // считается без распаковки, и уже стоящая на полке книга не
        // переписывается заново.
        if (entry.isStored && await _onShelf(archive, entry)) {
          already++;
          continue;
        }
        final String path = await _extract(archive, entry, books, name);
        final Book? known = await _library.bookByHash(
          await fileFingerprint(path),
        );
        final Book book = await _importer.registerSource(
          FilePathSource(path, owned: true),
          title: planned.title,
        );
        if (known != null) {
          // Стоящую на полке книгу архив не переставляет.
          already++;
          continue;
        }
        added.add(await _shelve(book, planned.category, categoryIds));
      } on ZipException catch (error) {
        failed.add(
          ImportFailure(
            name: planned.fileName,
            reason: describeZipProblem(error.problem),
          ),
        );
      } on DocumentOpenException catch (error) {
        failed.add(
          ImportFailure(
            name: planned.fileName,
            reason: describeDocumentProblem(error.problem),
            problem: error.problem,
          ),
        );
      } on FileSystemException catch (error) {
        // Записать не вышло — дальше будет то же самое. Распакованное
        // остаётся на полке, повторное добавление продолжит отсюда.
        stopped = describeWriteFailure(error);
        break;
      } on Object {
        failed.add(
          ImportFailure(
            name: planned.fileName,
            reason: 'файл не удалось прочесть',
          ),
        );
      }
    }
    return ArchiveReport(
      archive: name,
      total: total,
      added: added,
      already: already,
      skipped: layout.skipped,
      failed: failed,
      stopped: stopped,
    );
  }

  /// Стоит ли книга из записи без сжатия уже на полке, с файлом на месте.
  Future<bool> _onShelf(ZipArchive archive, ZipEntry entry) async {
    final String hash = await bookFingerprint(await archive.stored(entry));
    final Book? known = await _library.bookByHash(hash);
    return known != null && await _storage.available(known.source);
  }

  /// Распаковывает запись в папку книг и возвращает путь готового файла.
  Future<String> _extract(
    ZipArchive archive,
    ZipEntry entry,
    Directory books,
    String archiveName,
  ) async {
    final File part = File(
      incomingPathIn(books, 'zip:$archiveName:${entry.name}'),
    );
    try {
      final RandomAccessFile sink = await part.open(mode: FileMode.writeOnly);
      try {
        await archive.extract(entry, (Uint8List chunk) async {
          await sink.writeFrom(chunk);
        });
      } finally {
        await sink.close();
      }
      return await settleCopy(part: part, books: books);
    } on Object {
      await discardPart(part);
      rethrow;
    }
  }

  /// Ставит новую книгу в категорию [category] — последней.
  ///
  /// Книга к этому мигу уже на полке, в «Без категории»: категория
  /// заводится только под книгу, которая открылась. Папка архива, из
  /// которой не открылось ничего, пустой категории не оставляет.
  Future<Book> _shelve(
    Book book,
    String? category,
    Map<String, String> known,
  ) async {
    if (category == null) {
      return book;
    }
    final String id = await _categoryId(category, known);
    final int position = shelfPlaceAfterLast(await _library.books(), id);
    await _library.placeBooks(<BookPlacement>[
      BookPlacement(bookId: book.id, categoryId: id, position: position),
    ]);
    return book.copyWith(categoryId: id, shelfPosition: position);
  }

  /// Категория с названием [title]: существующая или новая, в конце
  /// полки.
  Future<String> _categoryId(String title, Map<String, String> known) async {
    final String key = title.toLowerCase();
    final String? ready = known[key];
    if (ready != null) {
      return ready;
    }
    int last = -1;
    for (final BookCategory category in await _categories.categories()) {
      if (category.title.toLowerCase() == key) {
        known[key] = category.id;
        return category.id;
      }
      if (category.position > last) {
        last = category.position;
      }
    }
    final BookCategory created = BookCategory(
      id: _newId(),
      title: title,
      position: last + 1,
      createdAt: _now(),
    );
    await _categories.save(created);
    known[key] = created.id;
    return created.id;
  }
}

/// Открытый архив и то, что за ним надо убрать.
class _Opened {
  const _Opened(this.handle, this.archive, this.borrowed);

  final BookHandle handle;
  final ZipArchive archive;

  /// Архив, перенесённый в приложение; отпускается после распаковки.
  final BookSource? borrowed;
}
