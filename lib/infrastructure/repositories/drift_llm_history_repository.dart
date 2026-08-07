import 'package:drift/drift.dart';

import '../../domain/llm/llm_query.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';
import '../database/enum_text.dart';

/// История запросов к модели поверх drift.
class DriftLlmHistoryRepository implements LlmHistoryRepository {
  /// Создаёт репозиторий.
  DriftLlmHistoryRepository(this._db, this._clock);

  final AppDatabase _db;
  final HlcClock _clock;

  @override
  Future<void> save(LlmQuery query) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final LlmQueriesCompanion row = LlmQueriesCompanion(
      id: Value<String>(query.id),
      bookId: Value<String?>(query.bookId),
      task: Value<String>(query.task.name),
      selection: Value<String>(query.selection),
      context: Value<String?>(query.context),
      sourceLanguage: Value<String?>(query.sourceLanguage),
      targetLanguage: Value<String?>(query.targetLanguage),
      answer: Value<String?>(query.answer),
      source: Value<String?>(query.source?.name),
      model: Value<String?>(query.model),
      latencyMs: Value<int?>(query.latencyMs),
      error: Value<String?>(query.error),
      createdAt: Value<DateTime>(query.createdAt),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.llmQueries).insertOnConflictUpdate(row);
  }

  @override
  Stream<List<LlmQuery>> watchForBook(String bookId) {
    final query = _db.select(_db.llmQueries);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    return query.watch().map(_toQueries);
  }

  @override
  Future<LlmQuery?> cached({
    required LlmTask task,
    required String selection,
    String? context,
    String? targetLanguage,
  }) async {
    final query = _db.select(_db.llmQueries);
    query.where(
      (tbl) =>
          tbl.task.equals(task.name) &
          tbl.selection.equals(selection) &
          tbl.answer.isNotNull() &
          tbl.isDeleted.equals(false) &
          _matches(tbl.context, context) &
          _matches(tbl.targetLanguage, targetLanguage),
    );
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    query.limit(1);
    final LlmQueryRow? row = await query.getSingleOrNull();
    return row == null ? null : _toQuery(row);
  }

  @override
  Future<void> delete(String id) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.llmQueries);
    update.where((tbl) => tbl.id.equals(id));
    await update.write(
      LlmQueriesCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  Expression<bool> _matches(GeneratedColumn<String> column, String? value) {
    if (value == null) {
      return column.isNull();
    }
    return column.equals(value);
  }

  List<LlmQuery> _toQueries(List<LlmQueryRow> rows) {
    return rows.map(_toQuery).toList();
  }

  LlmQuery _toQuery(LlmQueryRow row) {
    return LlmQuery(
      id: row.id,
      task: enumByName(LlmTask.values, row.task, LlmTask.meaning),
      selection: row.selection,
      createdAt: row.createdAt,
      bookId: row.bookId,
      context: row.context,
      sourceLanguage: row.sourceLanguage,
      targetLanguage: row.targetLanguage,
      answer: row.answer,
      source: row.source == null
          ? null
          : enumByName(LlmSource.values, row.source, LlmSource.cloud),
      model: row.model,
      latencyMs: row.latencyMs,
      error: row.error,
    );
  }
}
