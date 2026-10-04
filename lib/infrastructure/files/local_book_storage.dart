import 'dart:io';

import '../../domain/library/book_file_picker.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import 'book_copy.dart';
import 'file_book_handle.dart';

/// Хранилище книг в обычной файловой системе.
///
/// Это весь Windows и вся десктопная часть: там системный диалог отдаёт
/// настоящий путь, книга открывается по нему, и посредники не нужны.
/// На Android этим же кодом открываются **наши копии** — те, что
/// пришлось сделать для провайдеров, чья ссылка не годится для
/// перескоков.
///
/// В сборках ветвей СНО2026 книга копируется в папку приложения
/// (SNO-F-LIT-02, SNO-DIV-03): у всех тестировщиков одни и те же книги,
/// и они не должны зависеть от того, что лежит на диске устройства.
class LocalBookStorage implements BookStorage {
  /// Создаёт хранилище.
  ///
  /// [copyInto] — папка, куда книга копируется при добавлении. Без неё
  /// книга остаётся там, где лежит, — так живёт основное приложение.
  const LocalBookStorage({Future<Directory> Function()? copyInto})
    : _copyInto = copyInto;

  final Future<Directory> Function()? _copyInto;

  @override
  Future<BookSource> adopt(PickedFile file) async {
    final String? path = file.path;
    if (path == null) {
      throw StateError('файл выбран без пути: ${file.name}');
    }
    final Future<Directory> Function()? copyInto = _copyInto;
    if (copyInto == null) {
      // Файл остаётся там, где лежит: копировать чужую книгу к себе
      // незачем, а место она заняла бы дважды.
      return FilePathSource(path);
    }
    final String copy = await copyFileInto(
      source: path,
      books: await copyInto(),
    );
    return FilePathSource(copy, owned: true);
  }

  @override
  Future<BookHandle> open(BookSource source) {
    if (source is! FilePathSource) {
      throw BookUnavailableException(source);
    }
    return FileBookHandle.open(source);
  }

  @override
  Future<bool> available(BookSource source) async {
    return source is FilePathSource && await File(source.path).exists();
  }

  @override
  Future<void> release(BookSource source) async {
    // Чужой файл не трогается никогда: книгу сняли с полки, а не
    // выбросили с диска. Своя копия — другое дело, её больше некому
    // удалить.
    if (source is! FilePathSource || !source.owned) {
      return;
    }
    try {
      await File(source.path).delete();
    } on FileSystemException {
      // Копии уже нет — ровно то, чего мы и добивались.
    }
  }
}
