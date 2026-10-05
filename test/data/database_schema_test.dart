import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/infrastructure/database/app_database.dart';

import 'test_data.dart';

Future<List<String>> _tableNames(AppDatabase db) async {
  final Selectable<QueryRow> q = db.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ?',
    variables: [const Variable<String>('table')],
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

  test('версия схемы — двенадцатая: места книг на карте', () {
    expect(data.database.schemaVersion, appSchemaVersion);
    expect(appSchemaVersion, 12);
  });

  test('созданы все таблицы слоя данных', () async {
    final List<String> names = await _tableNames(data.database);
    expect(
      names,
      containsAll(<String>[
        'book_categories',
        'books',
        'reading_progress',
        'book_settings',
        'quotes',
        'notes',
        'bookmarks',
        'llm_queries',
        'app_settings',
        'device_files',
        'selection_prompts',
        'book_frames',
        'page_texts',
        'map_points',
      ]),
    );
  });

  test('синхронизируемые таблицы несут поля CRDT', () async {
    const List<String> synced = <String>[
      'book_categories',
      'books',
      'reading_progress',
      'book_settings',
      'quotes',
      'notes',
      'bookmarks',
      'llm_queries',
      // Промпты синхронизируются наравне с цитатами: это текст, который
      // читатель сочинил сам, и переписывать его на втором устройстве —
      // работа, которой быть не должно (решение владельца, 06.09.2026).
      'selection_prompts',
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

  test('F-READ-15: рамка книги полей CRDT не несёт', () async {
    // Рамка — производное: её посчитал наш код, а не создал читатель.
    // В слияние она не идёт, и поля для него ей не нужны.
    final List<String> columns = await _columnNames(
      data.database,
      'book_frames',
    );
    expect(columns, isNot(contains('hlc')));
    expect(columns, isNot(contains('is_deleted')));
    expect(
      columns,
      containsAll(<String>[
        'book_id',
        'crop_left',
        'crop_top',
        'crop_right',
        'crop_bottom',
        'even_shift',
        'sample_pages',
        'ignore_running_heads',
        'fingerprint',
        'algorithm_version',
      ]),
    );
  });

  test('F-TEXT-04: текст страниц полей CRDT не несёт', () async {
    // Текст страниц — производное: наш код извлёк его из файла, а не
    // создал читатель. В слияние он не идёт и в облако не уходит.
    final List<String> columns = await _columnNames(
      data.database,
      'page_texts',
    );
    expect(columns, isNot(contains('hlc')));
    expect(columns, isNot(contains('node_id')));
    expect(columns, isNot(contains('modified')));
    expect(columns, isNot(contains('is_deleted')));
    expect(columns, <String>[
      'book_id',
      'page',
      'content',
      'fingerprint',
      'algorithm_version',
    ]);
  });

  test('F-MAP-02: место книги на карте полей CRDT не несёт', () async {
    // Карта — производное: её посчитал наш код по тексту книг. В
    // слияние она не идёт и в облако не уходит.
    final List<String> columns = await _columnNames(
      data.database,
      'map_points',
    );
    expect(columns, isNot(contains('hlc')));
    expect(columns, isNot(contains('node_id')));
    expect(columns, isNot(contains('modified')));
    expect(columns, isNot(contains('is_deleted')));
    expect(columns, <String>[
      'book_id',
      'x',
      'y',
      'fingerprint',
      'layout_key',
      'algorithm_version',
    ]);
  });

  test('цитата носит своё место в тексте страницы', () async {
    // Без координат карточка цитаты умеет только «открыть страницу», а
    // читатель ждёт «покажи, где это было».
    final List<String> columns = await _columnNames(data.database, 'quotes');
    expect(columns, containsAll(<String>['text_start', 'text_end']));
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
