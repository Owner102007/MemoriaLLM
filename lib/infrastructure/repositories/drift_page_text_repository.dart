import 'package:drift/drift.dart';

import '../../domain/reading/page_text.dart';
import '../database/app_database.dart';

/// Текст страниц книги поверх drift (F-TEXT-04, ALG-TXT-09).
///
/// Меток HLC нет намеренно: текст страниц — производное и в слияние не
/// идёт. Страница, запомненная по другому отпечатку файла или другой
/// версией алгоритма, для запроса не существует, а запись ложится
/// поверх неё: ключ строки — книга и номер страницы.
class DriftPageTextRepository implements PageTextRepository {
  /// Создаёт хранилище.
  DriftPageTextRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Map<int, int>> cachedPages(PageTextKey key) async {
    final Expression<int> length = _db.pageTexts.content.length;
    final query = _db.selectOnly(_db.pageTexts);
    query.addColumns(<Expression<Object>>[_db.pageTexts.page, length]);
    query.where(
      _db.pageTexts.bookId.equals(key.bookId) &
          _db.pageTexts.fingerprint.equals(key.fingerprint) &
          _db.pageTexts.algorithmVersion.equals(key.version),
    );
    final List<TypedResult> rows = await query.get();
    final Map<int, int> pages = <int, int>{};
    for (final TypedResult row in rows) {
      final int? page = row.read(_db.pageTexts.page);
      if (page != null) {
        pages[page] = row.read(length) ?? 0;
      }
    }
    return pages;
  }

  @override
  Future<Map<int, String>> pageTexts(
    PageTextKey key, {
    required int from,
    required int to,
  }) async {
    final query = _db.select(_db.pageTexts);
    query.where(
      (tbl) =>
          tbl.bookId.equals(key.bookId) &
          tbl.fingerprint.equals(key.fingerprint) &
          tbl.algorithmVersion.equals(key.version) &
          tbl.page.isBetweenValues(from, to),
    );
    final List<PageTextRow> rows = await query.get();
    return <int, String>{
      for (final PageTextRow row in rows) row.page: row.content,
    };
  }

  @override
  Future<void> savePageTexts(PageTextKey key, Map<int, String> texts) async {
    if (texts.isEmpty) {
      return;
    }
    await _db.batch((Batch batch) {
      batch.insertAllOnConflictUpdate(_db.pageTexts, <PageTextsCompanion>[
        for (final MapEntry<int, String> entry in texts.entries)
          PageTextsCompanion(
            bookId: Value<String>(key.bookId),
            page: Value<int>(entry.key),
            content: Value<String>(entry.value),
            fingerprint: Value<String>(key.fingerprint),
            algorithmVersion: Value<int>(key.version),
          ),
      ]);
    });
  }
}
