import 'package:drift/native.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';

/// Слой данных поверх базы в памяти: каждый тест получает свою.
Future<AppData> openTestData() =>
    AppData.open(executor: NativeDatabase.memory());

/// Книга-заготовка. Поля заполнены так, чтобы не мешать проверкам.
Book testBook({
  String id = 'book-1',
  String title = 'Пиковая дама',
  String hash = 'hash-1',
}) {
  return Book(
    id: id,
    title: title,
    source: FilePathSource('/books/$id.pdf'),
    fileSize: 1024,
    fileHash: hash,
    addedAt: DateTime.utc(2026, 8, 1, 12),
    author: 'Пушкин',
  );
}
