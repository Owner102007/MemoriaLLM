import 'dart:io';
import 'dart:math';

import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/files/file_fingerprint.dart';

/// Заводит выбранный файл в библиотеке.
///
/// Полноценный импорт с обложками и сеткой книг — задача S5. Здесь ровно
/// столько, сколько нужно чтению: у книги должен быть постоянный
/// идентификатор, иначе некуда записать место, на котором её оставили.
class BookImporter {
  /// Создаёт сценарий импорта.
  ///
  /// [fingerprint] и [newId] подменяются в тестах: первый читает диск,
  /// второй недетерминирован, и оба мешают проверять сам сценарий.
  BookImporter({
    required LibraryRepository library,
    required DocumentOpener opener,
    Future<String> Function(String path)? fingerprint,
    String Function()? newId,
    DateTime Function()? now,
  }) : _library = library,
       _opener = opener,
       _fingerprint = fingerprint ?? fileFingerprint,
       _newId = newId ?? _randomId,
       _now = now ?? DateTime.now;

  final LibraryRepository _library;
  final DocumentOpener _opener;
  final Future<String> Function(String path) _fingerprint;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Регистрирует файл и возвращает книгу.
  ///
  /// Если такая книга уже в библиотеке (совпал отпечаток), заводится не
  /// вторая её копия, а обновляется путь у прежней: файл мог переехать,
  /// но место, на котором книгу оставили, принадлежит книге, а не пути.
  ///
  /// Бросает [DocumentOpenException], если файл не открывается: заводить
  /// в библиотеке книгу, которую нельзя прочесть, незачем.
  Future<Book> register(PickedFile file) async {
    final String hash = await _fingerprint(file.path);
    final Book? existing = await _library.bookByHash(hash);

    final ReaderDocument document = await _opener.open(file.path);
    final int pageCount;
    final bool textLayer;
    try {
      pageCount = document.pageCount;
      textLayer = await hasTextLayer(document);
    } finally {
      await document.close();
    }

    final int size = await File(file.path).length();
    final DateTime moment = _now();
    final Book book = existing == null
        ? Book(
            id: _newId(),
            title: titleFromFileName(file.name),
            filePath: file.path,
            fileSize: size,
            fileHash: hash,
            addedAt: moment,
            pageCount: pageCount,
            hasTextLayer: textLayer,
            openedAt: moment,
          )
        : existing.copyWith(
            filePath: file.path,
            fileSize: size,
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
