import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/library/book_file_picker.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import 'book_copy.dart';
import 'descriptor_book_handle.dart';
import 'descriptor_copy.dart';
import 'document_gateway.dart';
import 'libc.dart';
import 'local_book_storage.dart';

/// Хранилище книг на Android.
///
/// Книга не копируется в приложение, а читается там, где лежит. Важно
/// понимать, что «там, где лежит» на Android означает не путь: с Android
/// 10 приложение не имеет права читать чужие файлы по пути, и системный
/// диалог возвращает ссылку `content://`. Поэтому выбор не между
/// «копировать» и «открыть по пути», а между «копировать» и «читать по
/// ссылке».
///
/// Порядок такой:
///
/// 1. Разрешение на ссылку **закрепляется** — книга открывается и через
///    месяц, и после перезагрузки.
/// 2. Открывается файловый дескриптор, и по нему проверяется, можно ли
///    перескакивать по файлу.
/// 3. Если можно — источником становится сама ссылка, и книга читается
///    `pread`'ом без единой копии.
/// 4. Если нельзя (провайдер отдал трубу — так делают облачные
///    хранилища) или разрешение закрепить не дали — книга потоково
///    переносится в папку приложения, и дальше это обычный файл.
///
/// В сборках ветвей СНО2026 порядок короче (SNO-F-LIT-02, SNO-DIV-03):
/// книга **всегда** переносится в папку приложения. Ссылка не
/// закрепляется вовсе — у тестировщика приложение не держит ни одного
/// разрешения на чужие файлы.
class AndroidBookStorage implements BookStorage {
  /// Создаёт хранилище.
  ///
  /// [booksDirectory] подменяется в тестах: настоящая папка приложения
  /// требует платформенного канала, а проверять надо перенос книги, а не
  /// умение спросить у системы путь.
  ///
  /// [alwaysCopy] — книга переносится в папку приложения всегда, а не
  /// только когда иначе нельзя.
  AndroidBookStorage({
    DocumentGateway? documents,
    Future<Directory> Function()? booksDirectory,
    bool alwaysCopy = false,
  }) : _documents = documents ?? SafDocumentGateway(),
       _booksDirectory = booksDirectory ?? applicationBooks,
       _alwaysCopy = alwaysCopy,
       _files = LocalBookStorage(
         copyInto: alwaysCopy ? booksDirectory ?? applicationBooks : null,
       );

  final DocumentGateway _documents;
  final Future<Directory> Function() _booksDirectory;
  final bool _alwaysCopy;
  final LocalBookStorage _files;

  @override
  Future<BookSource> adopt(PickedFile file) async {
    final String? uri = file.uri;
    if (uri == null) {
      // Диалог отдал настоящий путь — так бывает у файлов внутри самого
      // приложения. Посредники тут не нужны.
      return _files.adopt(file);
    }

    if (_alwaysCopy) {
      // Ветвь СНО2026: книга живёт внутри приложения. Закреплять ссылку
      // незачем — после переноса она не понадобится.
      final int source = await _documents.openDescriptor(uri);
      return _copyToBooks(uri, file.name, source);
    }

    final bool persisted = await _documents.persist(uri);
    final int? size = await _documents.sizeOf(uri);

    final int descriptor = await _documents.openDescriptor(uri);
    final bool seekable = descriptorIsSeekable(descriptor);
    final bool readable = persisted && size != null && size > 0 && seekable;
    if (readable) {
      await _documents.closeDescriptor(descriptor);
      return DocumentUriSource(uri);
    }

    // Дескриптор уже открыт и всё равно нужен для переноса — закрывать
    // его, чтобы тут же открыть заново, незачем.
    final BookSource copy = await _copyToBooks(uri, file.name, descriptor);
    // Ссылка больше не нужна: книга у нас, а закреплённых ссылок Android
    // держит ограниченное число на приложение.
    if (persisted) {
      await _documents.releasePersisted(uri);
    }
    return copy;
  }

  @override
  Future<BookHandle> open(BookSource source) async {
    switch (source) {
      case FilePathSource():
        return _files.open(source);
      case DocumentUriSource():
        final int? size = await _documents.sizeOf(source.uri);
        if (size == null || size <= 0) {
          throw BookUnavailableException(source);
        }
        final int descriptor;
        try {
          descriptor = await _documents.openDescriptor(source.uri);
        } on Object catch (error) {
          throw BookUnavailableException(source, cause: error);
        }
        return DescriptorBookHandle(
          descriptor: descriptor,
          length: size,
          onClose: () => _documents.closeDescriptor(descriptor),
        );
    }
  }

  @override
  Future<bool> available(BookSource source) async {
    switch (source) {
      case FilePathSource():
        return _files.available(source);
      case DocumentUriSource():
        final int? size = await _documents.sizeOf(source.uri);
        return size != null && size > 0;
    }
  }

  @override
  Future<void> release(BookSource source) async {
    switch (source) {
      case FilePathSource():
        await _files.release(source);
      case DocumentUriSource():
        await _documents.releasePersisted(source.uri);
    }
  }

  /// Потоково переносит книгу в папку приложения.
  ///
  /// Дескриптор закрывается здесь же: он был нужен ровно на время
  /// переноса.
  Future<BookSource> _copyToBooks(
    String uri,
    String name,
    int descriptor,
  ) async {
    final Directory books = await _booksDirectory();
    final String destination = p.join(books.path, copyFileName(uri, name));
    try {
      await copyDescriptorToFile(
        descriptor: descriptor,
        destination: destination,
      );
    } finally {
      await _documents.closeDescriptor(descriptor);
    }
    return FilePathSource(destination, owned: true);
  }
}
