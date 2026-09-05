import 'package:drift/drift.dart';

import '../../domain/prompts/selection_prompt.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/sync/hlc.dart';
import '../database/app_database.dart';

/// Промпты к выделению поверх drift.
///
/// Оба уровня лежат в одной таблице и различаются `book_id`: пусто —
/// мастер-набор, заполнено — набор книги. Слияние уровней делает домен
/// (`mergePromptLevels`), а не запрос: правило «книга главнее целиком»
/// проверяется юнит-тестом на числах, а не на живой базе.
class DriftPromptRepository implements PromptRepository {
  /// Создаёт репозиторий.
  DriftPromptRepository(this._db, this._clock, this._settings);

  final AppDatabase _db;
  final HlcClock _clock;
  final AppSettingsRepository _settings;

  @override
  Stream<List<SelectionPrompt>> watchMasterPrompts() {
    return _masterQuery().watch().map(_toPrompts);
  }

  @override
  Future<List<SelectionPrompt>> masterPrompts() async {
    return _toPrompts(await _masterQuery().get());
  }

  @override
  Future<List<SelectionPrompt>> bookPrompts(String bookId) async {
    return _toPrompts(await _bookQuery(bookId).get());
  }

  @override
  Stream<PromptSet> watchPromptsFor(String bookId) {
    final query = _db.select(_db.selectionPrompts);
    query.where(
      (tbl) =>
          tbl.isDeleted.equals(false) &
          (tbl.bookId.isNull() | tbl.bookId.equals(bookId)),
    );
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.position)]);
    return query.watch().map((List<SelectionPromptRow> rows) {
      final List<SelectionPrompt> master = <SelectionPrompt>[];
      final List<SelectionPrompt> book = <SelectionPrompt>[];
      for (final SelectionPromptRow row in rows) {
        final SelectionPrompt prompt = _toPrompt(row);
        if (prompt.isBookLevel) {
          book.add(prompt);
        } else {
          master.add(prompt);
        }
      }
      return mergePromptLevels(master: master, book: book);
    });
  }

  @override
  Future<void> savePrompt(SelectionPrompt prompt) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final SelectionPromptsCompanion row = SelectionPromptsCompanion(
      id: Value<String>(prompt.id),
      bookId: Value<String?>(prompt.bookId),
      name: Value<String>(prompt.name),
      body: Value<String>(prompt.body),
      position: Value<int>(prompt.position),
      isPrimary: Value<bool>(prompt.isPrimary),
      createdAt: Value<DateTime>(prompt.createdAt),
      updatedAt: Value<DateTime>(prompt.updatedAt),
      hlc: Value<String>(mark),
      nodeId: Value<String>(stamp.nodeId),
      modified: Value<String>(mark),
      isDeleted: const Value<bool>(false),
    );
    await _db.into(_db.selectionPrompts).insertOnConflictUpdate(row);
  }

  @override
  Future<void> deletePrompt(String id) async {
    await _markDeleted((tbl) => tbl.id.equals(id));
  }

  @override
  Future<void> resetBookPrompts(String bookId) async {
    // «Вернуть как у всех» — это надгробие на каждой строке уровня книги,
    // а не `DELETE`: иначе набор, стёртый на телефоне, снова приехал бы
    // с ПК при первом же слиянии.
    await _markDeleted((tbl) => tbl.bookId.equals(bookId));
  }

  @override
  Future<bool> seedDefaultsOnce() async {
    final String? seeded = await _settings.read(SettingsKeys.promptsSeeded);
    if (seeded == 'true') {
      return false;
    }
    for (final SelectionPrompt prompt in defaultPrompts(now: DateTime.now())) {
      await savePrompt(prompt);
    }
    await _settings.write(SettingsKeys.promptsSeeded, 'true');
    return true;
  }

  Future<void> _markDeleted(
    Expression<bool> Function($SelectionPromptsTable tbl) filter,
  ) async {
    final Hlc stamp = _clock.issue();
    final String mark = stamp.toString();
    final update = _db.update(_db.selectionPrompts);
    update.where(filter);
    await update.write(
      SelectionPromptsCompanion(
        isDeleted: const Value<bool>(true),
        hlc: Value<String>(mark),
        nodeId: Value<String>(stamp.nodeId),
        modified: Value<String>(mark),
      ),
    );
  }

  SimpleSelectStatement<$SelectionPromptsTable, SelectionPromptRow>
  _masterQuery() {
    final query = _db.select(_db.selectionPrompts);
    query.where((tbl) => tbl.bookId.isNull() & tbl.isDeleted.equals(false));
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.position)]);
    return query;
  }

  SimpleSelectStatement<$SelectionPromptsTable, SelectionPromptRow> _bookQuery(
    String bookId,
  ) {
    final query = _db.select(_db.selectionPrompts);
    query.where(
      (tbl) => tbl.bookId.equals(bookId) & tbl.isDeleted.equals(false),
    );
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.position)]);
    return query;
  }

  List<SelectionPrompt> _toPrompts(List<SelectionPromptRow> rows) {
    return rows.map(_toPrompt).toList();
  }

  SelectionPrompt _toPrompt(SelectionPromptRow row) {
    return SelectionPrompt(
      id: row.id,
      bookId: row.bookId,
      name: row.name,
      body: row.body,
      position: row.position,
      isPrimary: row.isPrimary,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
