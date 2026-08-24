import 'package:drift/drift.dart';

import '../../domain/library/book.dart';
import '../../domain/library/book_source.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';

/// Библиотека поверх drift.
class DriftLibraryRepository implements LibraryRepository {
  /// Создаёт репозиторий.
  DriftLibraryRepository(this._db, this._clock);

  final AppDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Book>> watchBooks() {
    final query = _db.select(_db.books);
    query.where((tbl) => tbl.isDeleted.equals(false));
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.addedAt)]);
    return query.watch().map(_toBooks);
  }

  @override
  Future<List<Book>> books() async {
    final query = _db.select(_db.books);
    query.where((tbl) => tbl.isDeleted.equals(false));
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.addedAt)]);
    return _toBooks(await query.get());
  }

  @override
  Future<Book?> bookById(String id) async {
    final query = _db.select(_db.books);
    query.where((tbl) => tbl.id.equals(id) & tbl.isDeleted.equals(false));
    final BookRow? row = await query.getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<Book?> bookByHash(String fileHash) async {
    final query = _db.select(_db.books);
    query.where(
      (tbl) => tbl.fileHash.equals(fileHash) & tbl.isDeleted.equals(false),
    );
    query.limit(1);
    final BookRow? row = await query.getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<void> save(Book book) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final BooksCompanion row = BooksCompanion(
      id: Value<String>(book.id),
      title: Value<String>(book.title),
      author: Value<String?>(book.author),
      filePath: Value<String>(book.source.encode()),
      fileSize: Value<int>(book.fileSize),
      fileHash: Value<String>(book.fileHash),
      pageCount: Value<int?>(book.pageCount),
      language: Value<String?>(book.language),
      hasTextLayer: Value<bool?>(book.hasTextLayer),
      coverPath: Value<String?>(book.coverPath),
      addedAt: Value<DateTime>(book.addedAt),
      openedAt: Value<DateTime?>(book.openedAt),
      categoryId: Value<String?>(book.categoryId),
      shelfPosition: Value<int>(book.shelfPosition),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.books).insertOnConflictUpdate(row);
  }

  @override
  Future<void> markOpened(String id, DateTime when) async {
    await _touch(id, BooksCompanion(openedAt: Value<DateTime?>(when)));
  }

  /// Правит у книги одно-два поля, проставляя метку изменения.
  ///
  /// Полная перезапись книги ради одного поля затирала бы то, что
  /// параллельно записал другой экран: полка и чтение работают с одной и
  /// той же строкой одновременно.
  Future<void> _touch(String id, BooksCompanion changes) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.books);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      changes.copyWith(
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  @override
  Future<void> placeBooks(List<BookPlacement> placements) async {
    if (placements.isEmpty) {
      return;
    }
    // Одной транзакцией: полка, расставленная наполовину, хуже
    // нерасставленной — две книги окажутся на одном месте, и порядок
    // начнёт меняться сам собой при каждом открытии.
    await _db.transaction(() async {
      for (final BookPlacement placement in placements) {
        await _touch(
          placement.bookId,
          BooksCompanion(
            categoryId: Value<String?>(placement.categoryId),
            shelfPosition: Value<int>(placement.position),
          ),
        );
      }
    });
  }

  @override
  Future<void> setCoverPath(String bookId, String? coverPath) async {
    // Обложка — местный кэш, а не данные читателя, и метку изменения ей
    // ставят наравне со всем остальным только потому, что она лежит в той
    // же строке. В облако у книги уедут заголовок и источник, а не путь
    // к картинке на этом устройстве.
    await _touch(bookId, BooksCompanion(coverPath: Value<String?>(coverPath)));
  }

  @override
  Future<void> clearCategory(String categoryId) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.books);
    update.where((tbl) => tbl.categoryId.equals(categoryId));
    await update.write(
      BooksCompanion(
        categoryId: const Value<String?>(null),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.books);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      BooksCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  @override
  Future<int> purgeDeleted() async {
    final statement = _db.delete(_db.books);
    statement.where((tbl) => tbl.isDeleted.equals(true));
    return statement.go();
  }

  List<Book> _toBooks(List<BookRow> rows) {
    return rows.map(_toBook).toList();
  }

  Book _toBook(BookRow row) {
    return Book(
      id: row.id,
      title: row.title,
      source: BookSource.decode(row.filePath),
      fileSize: row.fileSize,
      fileHash: row.fileHash,
      addedAt: row.addedAt,
      author: row.author,
      pageCount: row.pageCount,
      language: row.language,
      hasTextLayer: row.hasTextLayer,
      coverPath: row.coverPath,
      openedAt: row.openedAt,
      categoryId: row.categoryId,
      shelfPosition: row.shelfPosition,
    );
  }
}
