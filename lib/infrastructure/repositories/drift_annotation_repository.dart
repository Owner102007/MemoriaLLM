import 'package:drift/drift.dart';

import '../../domain/annotations/annotations.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';

/// Цитаты, заметки и закладки поверх drift.
class DriftAnnotationRepository implements AnnotationRepository {
  /// Создаёт репозиторий.
  DriftAnnotationRepository(this._db, this._clock);

  final AppDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Quote>> watchQuotes(String bookId) {
    return _quotesQuery(bookId).watch().map(_toQuotes);
  }

  @override
  Future<List<Quote>> quotes(String bookId) async {
    return _toQuotes(await _quotesQuery(bookId).get());
  }

  @override
  Future<void> saveQuote(Quote quote) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final QuotesCompanion row = QuotesCompanion(
      id: Value<String>(quote.id),
      bookId: Value<String>(quote.bookId),
      page: Value<int>(quote.page),
      content: Value<String>(quote.content),
      context: Value<String?>(quote.context),
      color: Value<int?>(quote.color),
      textStart: Value<int?>(quote.textStart),
      textEnd: Value<int?>(quote.textEnd),
      createdAt: Value<DateTime>(quote.createdAt),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.quotes).insertOnConflictUpdate(row);
  }

  @override
  Future<void> deleteQuote(String id) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.quotes);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      QuotesCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  @override
  Stream<List<Note>> watchNotes(String bookId) {
    return _notesQuery(bookId).watch().map(_toNotes);
  }

  @override
  Future<List<Note>> notes(String bookId) async {
    return _toNotes(await _notesQuery(bookId).get());
  }

  @override
  Future<void> saveNote(Note note) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final NotesCompanion row = NotesCompanion(
      id: Value<String>(note.id),
      bookId: Value<String>(note.bookId),
      quoteId: Value<String?>(note.quoteId),
      page: Value<int>(note.page),
      body: Value<String>(note.body),
      createdAt: Value<DateTime>(note.createdAt),
      updatedAt: Value<DateTime>(note.updatedAt),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.notes).insertOnConflictUpdate(row);
  }

  @override
  Future<void> deleteNote(String id) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.notes);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      NotesCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  @override
  Stream<List<Bookmark>> watchBookmarks(String bookId) {
    return _bookmarksQuery(bookId).watch().map(_toBookmarks);
  }

  @override
  Future<List<Bookmark>> bookmarks(String bookId) async {
    return _toBookmarks(await _bookmarksQuery(bookId).get());
  }

  @override
  Future<void> saveBookmark(Bookmark bookmark) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final BookmarksCompanion row = BookmarksCompanion(
      id: Value<String>(bookmark.id),
      bookId: Value<String>(bookmark.bookId),
      page: Value<int>(bookmark.page),
      fragment: Value<int>(bookmark.fragment),
      label: Value<String?>(bookmark.label),
      createdAt: Value<DateTime>(bookmark.createdAt),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.bookmarks).insertOnConflictUpdate(row);
  }

  @override
  Future<void> deleteBookmark(String id) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.bookmarks);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      BookmarksCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  SimpleSelectStatement<$QuotesTable, QuoteRow> _quotesQuery(String bookId) {
    final query = _db.select(_db.quotes);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    return query;
  }

  SimpleSelectStatement<$NotesTable, NoteRow> _notesQuery(String bookId) {
    final query = _db.select(_db.notes);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    return query;
  }

  SimpleSelectStatement<$BookmarksTable, BookmarkRow> _bookmarksQuery(
    String bookId,
  ) {
    final query = _db.select(_db.bookmarks);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.page)]);
    return query;
  }

  List<Quote> _toQuotes(List<QuoteRow> rows) {
    return rows.map(_toQuote).toList();
  }

  Quote _toQuote(QuoteRow row) {
    return Quote(
      id: row.id,
      bookId: row.bookId,
      page: row.page,
      content: row.content,
      createdAt: row.createdAt,
      context: row.context,
      color: row.color,
      textStart: row.textStart,
      textEnd: row.textEnd,
    );
  }

  List<Note> _toNotes(List<NoteRow> rows) {
    return rows.map(_toNote).toList();
  }

  Note _toNote(NoteRow row) {
    return Note(
      id: row.id,
      bookId: row.bookId,
      page: row.page,
      body: row.body,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      quoteId: row.quoteId,
    );
  }

  List<Bookmark> _toBookmarks(List<BookmarkRow> rows) {
    return rows.map(_toBookmark).toList();
  }

  Bookmark _toBookmark(BookmarkRow row) {
    return Bookmark(
      id: row.id,
      bookId: row.bookId,
      page: row.page,
      createdAt: row.createdAt,
      fragment: row.fragment,
      label: row.label,
    );
  }
}
