import 'package:drift/drift.dart';

import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';

/// Категории полки поверх drift.
class DriftCategoryRepository implements CategoryRepository {
  /// Создаёт репозиторий.
  ///
  /// [library] нужен ради одного действия — удаления категории: её книги
  /// обязаны вернуться в «Без категории», а не исчезнуть вместе с ней.
  DriftCategoryRepository(this._db, this._clock, this._library);

  final AppDatabase _db;
  final HlcClock _clock;
  final LibraryRepository _library;

  @override
  Stream<List<BookCategory>> watchCategories() {
    final query = _db.select(_db.bookCategories);
    query.where((tbl) => tbl.isDeleted.equals(false));
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.position),
      (tbl) => OrderingTerm.asc(tbl.createdAt),
      (tbl) => OrderingTerm.asc(tbl.id),
    ]);
    return query.watch().map(_toCategories);
  }

  @override
  Future<List<BookCategory>> categories() async {
    final query = _db.select(_db.bookCategories);
    query.where((tbl) => tbl.isDeleted.equals(false));
    query.orderBy([
      (tbl) => OrderingTerm.asc(tbl.position),
      (tbl) => OrderingTerm.asc(tbl.createdAt),
      (tbl) => OrderingTerm.asc(tbl.id),
    ]);
    return _toCategories(await query.get());
  }

  @override
  Future<BookCategory?> categoryById(String id) async {
    final query = _db.select(_db.bookCategories);
    query.where((tbl) => tbl.id.equals(id) & tbl.isDeleted.equals(false));
    final BookCategoryRow? row = await query.getSingleOrNull();
    return row == null ? null : _toCategory(row);
  }

  @override
  Future<void> save(BookCategory category) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    await _db
        .into(_db.bookCategories)
        .insertOnConflictUpdate(
          BookCategoriesCompanion(
            id: Value<String>(category.id),
            title: Value<String>(category.title),
            position: Value<int>(category.position),
            createdAt: Value<DateTime>(category.createdAt),
            hlc: Value<String>(mark),
            nodeId: Value<String>(stamp.nodeId),
            modified: Value<String>(mark),
            isDeleted: const Value<bool>(false),
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    // Обе записи в одной транзакции: книга, потерявшая категорию, но
    // оставшаяся с ссылкой на удалённую, не пропадёт с полки (раскладка
    // считает такую ссылку отсутствующей), но и полуправды в базе быть
    // не должно.
    await _db.transaction(() async {
      await _library.clearCategory(id);
      final Hlc stamp = _clock.issue();
      final String mark = stamp.toString();
      final update = _db.update(_db.bookCategories);
      update.where((tbl) => tbl.id.equals(id));
      await update.write(
        BookCategoriesCompanion(
          isDeleted: const Value<bool>(true),
          hlc: Value<String>(mark),
          nodeId: Value<String>(stamp.nodeId),
          modified: Value<String>(mark),
        ),
      );
    });
  }

  @override
  Future<int> purgeDeleted() async {
    final statement = _db.delete(_db.bookCategories);
    statement.where((tbl) => tbl.isDeleted.equals(true));
    return statement.go();
  }

  List<BookCategory> _toCategories(List<BookCategoryRow> rows) {
    return rows.map(_toCategory).toList();
  }

  BookCategory _toCategory(BookCategoryRow row) {
    return BookCategory(
      id: row.id,
      title: row.title,
      position: row.position,
      createdAt: row.createdAt,
    );
  }
}
