import 'package:drift/drift.dart';

import '../../domain/library/device_files.dart';
import '../../domain/library/search_text.dart';
import '../database/app_database.dart';
import '../database/enum_text.dart';
import '../database/search_index.dart';

/// Файлы устройства и индекс поиска по ним, поверх drift.
///
/// Индекс живёт в отдельной виртуальной таблице FTS5 и заполняется здесь
/// же: две записи в одной транзакции. Разъехавшийся с базой индекс — это
/// книга, которая есть на полке и не находится поиском, то есть ровно то
/// поведение, из-за которого поиску перестают верить.
class DriftDeviceFileRepository implements DeviceFileRepository {
  /// Создаёт репозиторий.
  ///
  /// [indexed] говорит, есть ли в этой базе FTS5. Проверяется один раз при
  /// открытии: спрашивать SQLite об этом на каждый запрос незачем.
  DriftDeviceFileRepository(this._db, {required bool indexed})
    : _indexed = indexed;

  /// Вес имени файла и папки в ранжировании.
  ///
  /// Имя весит больше текста намеренно: читатель ищет книгу, которую
  /// **помнит**, и помнит он её по названию. Совпадение в тексте на
  /// четырёхсотой странице — довод куда слабее, чем совпадение в имени
  /// файла, и веса это отражают.
  static const double kNameWeight = 8;

  /// Вес метаданных PDF.
  static const double kMetaWeight = 3;

  /// Вес текста первых страниц.
  static const double kBodyWeight = 1;

  final AppDatabase _db;
  final bool _indexed;

  /// Работает ли поиск по индексу.
  bool get isIndexed => _indexed;

  @override
  Future<List<DeviceFileRecord>> files() async {
    final List<DeviceFileRow> rows = await _db.select(_db.deviceFiles).get();
    return rows.map(_toRecord).toList();
  }

  @override
  Stream<List<DeviceFileRecord>> watchFiles() {
    return _db
        .select(_db.deviceFiles)
        .watch()
        .map((List<DeviceFileRow> rows) => rows.map(_toRecord).toList());
  }

  @override
  Future<void> applyScan(List<ScanDecision> decisions) async {
    if (decisions.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final ScanDecision decision in decisions) {
        switch (decision.verdict) {
          case ScanVerdict.added:
          case ScanVerdict.changed:
            // Изменившийся файл — это другая книга, пока не доказано
            // обратное: отпечаток, метаданные и текст от прежней к ней не
            // относятся. Строка индекса поэтому заводится заново, с одним
            // только именем.
            await _write(decision.record);
            await _reindex(decision.record, body: '');
          case ScanVerdict.unchanged:
            await _write(decision.record);
          case ScanVerdict.gone:
            await _write(decision.record);
            await _dropFromIndex(decision.record.path);
        }
      }
    });
  }

  @override
  Future<void> saveFile(DeviceFileRecord record, {String? body}) async {
    await _db.transaction(() async {
      await _write(record);
      await _reindex(record, body: body);
    });
  }

  @override
  Future<List<DeviceFileRecord>> pendingIndex({
    required IndexStage upTo,
    int limit = 32,
  }) async {
    final List<String> wanted = <String>[
      for (final IndexStage stage in IndexStage.values)
        if (stage.index < upTo.index) stage.name,
    ];
    if (wanted.isEmpty) {
      return const <DeviceFileRecord>[];
    }
    final query = _db.select(_db.deviceFiles);
    query.where((tbl) => tbl.missing.equals(false) & tbl.stage.isIn(wanted));
    // Порядок обязан быть устойчивым: иначе один и тот же файл может
    // браться в работу дважды, а другой не взяться ни разу. Ступени при
    // этом идут не вперемешку, а слоями — сначала весь проход до
    // метаданных, потом весь проход до текста, — и внутри одного прохода
    // сортировать по ступени нечего.
    query.orderBy([(tbl) => OrderingTerm.asc(tbl.path)]);
    query.limit(limit);
    return (await query.get()).map(_toRecord).toList();
  }

  @override
  Future<List<String>> search(String query, {int limit = 200}) async {
    final String match = ftsQueryFor(query);
    if (match.isEmpty) {
      return const <String>[];
    }
    if (!_indexed) {
      return _searchWithoutIndex(query, limit: limit);
    }
    try {
      final List<QueryRow> rows = await _db
          .customSelect(
            'SELECT path, bm25($kSearchIndexTable, 0.0, ?, ?, ?) AS weight '
            'FROM $kSearchIndexTable WHERE $kSearchIndexTable MATCH ? '
            'ORDER BY weight LIMIT ?',
            variables: <Variable<Object>>[
              Variable<double>(kNameWeight),
              Variable<double>(kMetaWeight),
              Variable<double>(kBodyWeight),
              Variable<String>(match),
              Variable<int>(limit),
            ],
          )
          .get();
      return <String>[
        for (final QueryRow row in rows) row.read<String>('path'),
      ];
    } on Object {
      // Запрос, который FTS5 не разобрала, — не повод показать читателю
      // пустой экран: перебор имён найдёт меньше, но найдёт.
      return _searchWithoutIndex(query, limit: limit);
    }
  }

  @override
  Future<void> forgetEverything() async {
    await _db.transaction(() async {
      await _db.delete(_db.deviceFiles).go();
      if (_indexed) {
        await _db.customStatement('DELETE FROM $kSearchIndexTable');
      }
    });
  }

  /// Поиск без индекса: подстрока в свёрнутом имени файла.
  ///
  /// Слабее FTS5 во всём, кроме одного — работает всегда.
  Future<List<String>> _searchWithoutIndex(
    String query, {
    required int limit,
  }) async {
    final List<String> tokens = searchTokens(query);
    if (tokens.isEmpty) {
      return const <String>[];
    }
    final List<DeviceFileRecord> all = await files();
    final List<String> found = <String>[];
    for (final DeviceFileRecord record in all) {
      if (record.missing) {
        continue;
      }
      final String haystack = indexableText(
        '${record.name} ${record.folder} ${record.title ?? ''} '
        '${record.author ?? ''}',
      );
      if (tokens.every(haystack.contains)) {
        found.add(record.path);
        if (found.length >= limit) {
          break;
        }
      }
    }
    return found;
  }

  Future<void> _write(DeviceFileRecord record) {
    return _db
        .into(_db.deviceFiles)
        .insertOnConflictUpdate(
          DeviceFilesCompanion(
            path: Value<String>(record.path),
            size: Value<int>(record.size),
            modifiedAt: Value<DateTime>(record.modifiedAt),
            seenAt: Value<DateTime>(record.seenAt),
            fingerprint: Value<String?>(record.fingerprint),
            title: Value<String?>(record.title),
            author: Value<String?>(record.author),
            stage: Value<String>(record.stage.name),
            hasTextLayer: Value<bool?>(record.hasTextLayer),
            missing: Value<bool>(record.missing),
          ),
        );
  }

  /// Перекладывает запись в индекс.
  ///
  /// [body] — текст первых страниц. `null` означает «не трогать то, что
  /// уже лежит»: метаданные подъезжают раньше текста, и обновление
  /// заголовка не должно стирать разобранные страницы.
  Future<void> _reindex(DeviceFileRecord record, {String? body}) async {
    if (!_indexed) {
      return;
    }
    final String text = body ?? await _bodyOf(record.path);
    await _dropFromIndex(record.path);
    await _db.customStatement(
      'INSERT INTO $kSearchIndexTable (path, name, meta, body) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[
        record.path,
        indexableText('${record.name} ${record.folder}'),
        indexableText('${record.title ?? ''} ${record.author ?? ''}'),
        text,
      ],
    );
  }

  Future<String> _bodyOf(String path) async {
    final List<QueryRow> rows = await _db
        .customSelect(
          'SELECT body FROM $kSearchIndexTable WHERE path = ?',
          variables: <Variable<Object>>[Variable<String>(path)],
        )
        .get();
    return rows.isEmpty ? '' : rows.first.read<String>('body');
  }

  Future<void> _dropFromIndex(String path) async {
    if (!_indexed) {
      return;
    }
    await _db.customStatement(
      'DELETE FROM $kSearchIndexTable WHERE path = ?',
      <Object?>[path],
    );
  }

  DeviceFileRecord _toRecord(DeviceFileRow row) {
    return DeviceFileRecord(
      path: row.path,
      size: row.size,
      modifiedAt: row.modifiedAt,
      seenAt: row.seenAt,
      fingerprint: row.fingerprint,
      title: row.title,
      author: row.author,
      stage: enumByName(IndexStage.values, row.stage, IndexStage.name),
      hasTextLayer: row.hasTextLayer,
      missing: row.missing,
    );
  }
}
