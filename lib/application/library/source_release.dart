import '../../domain/library/book.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';

/// Отпускает источник книги — если он больше ничей (BUG-45, BUG-17).
///
/// Отпустить источник — значит удалить свою копию книги и отозвать
/// закреплённую ссылку; вернуть их назад нельзя. Поэтому отпускается
/// только источник, которого нет ни у одной книги на полке. Один файл
/// бывает источником двух книг: копия названа по содержимому, а книгу
/// можно привязать к файлу другой — и снятие одной из них с полки или
/// неудачное добавление не должно отнимать файл у второй.
///
/// Здесь единственное место, где это правило записано: импорт,
/// перепривязка и полка отпускают источники только через него.
///
/// Возвращает, отпущен ли источник.
Future<bool> releaseUnusedSource({
  required BookStorage storage,
  required LibraryRepository library,
  required BookSource source,
}) async {
  final List<Book> books = await library.books();
  if (books.any((Book book) => book.source == source)) {
    return false;
  }
  await storage.release(source);
  return true;
}
