import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';

/// Книга в обычном файле: Windows, наши копии и весь корпус тестов.
///
/// Путь отдаётся наружу — движок откроет файл сам и прочитает его лучше
/// нас. Чтение кусками остаётся для отпечатка файла и на случай, когда
/// путь показывать нельзя.
class FileBookHandle implements BookHandle {
  FileBookHandle._(this._file, this.length, this.path);

  /// Открывает файл на чтение.
  ///
  /// [exposePath] выключается там, где нужно заставить движок читать
  /// кусками через тот же колбэк, каким он читает документ по ссылке.
  static Future<FileBookHandle> open(
    FilePathSource source, {
    bool exposePath = true,
  }) async {
    final File file = File(source.path);
    final RandomAccessFile handle;
    final int length;
    try {
      length = await file.length();
      handle = await file.open();
    } on FileSystemException catch (error) {
      throw BookUnavailableException(source, cause: error);
    }
    return FileBookHandle._(handle, length, exposePath ? source.path : null);
  }

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  final String? path;

  /// Очередь чтений.
  ///
  /// Позиция у дескриптора одна на всех, поэтому два чтения внахлёст
  /// прочитали бы друг у друга не то место. Движок сегодня зовёт колбэк
  /// по одному, но полагаться на это значит однажды получить редкое
  /// «файл повреждён» на ровном месте.
  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  @override
  Future<int> read(Uint8List buffer, int position, int size) {
    final Completer<int> done = Completer<int>();
    _queue = _queue.then((_) async {
      if (_closed) {
        done.complete(-1);
        return;
      }
      try {
        await _file.setPosition(position);
        done.complete(await _file.readInto(buffer, 0, size));
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    // Ждём очередь: закрытый дескриптор посреди чтения — это исключение
    // из движка, а не аккуратное завершение.
    await _queue;
    await _file.close();
  }
}
