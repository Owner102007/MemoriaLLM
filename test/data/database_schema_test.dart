import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/infrastructure/database/app_database.dart';

import 'test_data.dart';

Future<List<String>> _tableNames(AppDatabase db) async {
  final Selectable<QueryRow> q = db.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ?',
    variables: [Variable<String>('table')],
  );
  final List<QueryRow> result = await q.get();
  return result.map((QueryRow row) => row.read<String>('name')).toList();
}

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final Selectable<QueryRow> q = db.customSelect('PRAGMA table_info($table)');
  final List<QueryRow> result = await q.get();
  return result.map((QueryRow row) => row.read<String>('name')).toList();
}

Future<int> _countRows(AppDatabase db, String table) async {
  final Selectable<QueryRow> q = db.customSelect(
    'SELECT COUNT(*) AS c FROM $table',
  );
  final QueryRow row = await q.getSingle();
  return row.read<int>('c');
}

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
  });

  tearDown(() async {
    await data.close();
  });

  test('версия схемы — первая', () {
    expect(data.database.schemaVersion, appSchemaVersion);
    expect(appSchemaVersion, 1);
  });

  test('созданы все таблицы слоя данных', () async {
    final List<String> names = await _tableNames(data.database);
    expect(
      names,
      containsAll(<String>[
        'books',
        'reading_progress',
        'book_settings',
        'quotes',
        'notes',
        'bookmarks',
        'llm_queries',
        'app_settings',
      ]),
    );
  });

  test('синхронизируемые таблицы несут поля CRDT', () async {
    const List<String> synced = <String>[
      'books',
      'reading_progress',
      'book_settings',
      'quotes',
      'notes',
      'bookmarks',
      'llm_queries',
    ];
    for (final String table in synced) {
      final List<String> columns = await _columnNames(data.database, table);
      expect(
        columns,
        containsAll(<String>['hlc', 'node_id', 'modified', 'is_deleted']),
        reason: 'таблица $table не готова к слиянию в S10',
      );
    }
  });

  test('локальные настройки полей CRDT не несут', () async {
    final List<String> columns = await _columnNames(
      data.database,
      'app_settings',
    );
    expect(columns, isNot(contains('hlc')));
    expect(columns, <String>['setting_key', 'setting_value']);
  });

  test('имена колонок переведены в snake_case', () async {
    final List<String> columns = await _columnNames(data.database, 'books');
    expect(columns, contains('file_hash'));
    expect(columns, contains('has_text_layer'));
    expect(columns, isNot(contains('fileHash')));
  });

  test('внешние ключи включены', () async {
    final Selectable<QueryRow> q = data.database.customSelect(
      'PRAGMA foreign_keys',
    );
    final QueryRow row = await q.getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('чистка удалённых книг уносит и всё, что на них ссылалось', () async {
    await data.library.save(testBook());
    await data.annotations.saveQuote(
      Quote(
        id: 'quote-1',
        bookId: 'book-1',
        page: 7,
        content: 'Две неподвижные идеи',
        createdAt: DateTime.utc(2026, 8, 2),
      ),
    );
    expect(await _countRows(data.database, 'quotes'), 1);

    await data.library.delete('book-1');
    expect(await _countRows(data.database, 'quotes'), 1);
    expect(await _countRows(data.database, 'books'), 1);

    expect(await data.library.purgeDeleted(), 1);
    expect(await _countRows(data.database, 'books'), 0);
    expect(await _countRows(data.database, 'quotes'), 0);
  });
}
