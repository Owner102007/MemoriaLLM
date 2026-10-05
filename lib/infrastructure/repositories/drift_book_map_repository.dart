import 'package:drift/drift.dart';

import '../../domain/map/book_map.dart';
import '../database/app_database.dart';

/// Карта книг поверх drift (F-MAP-02, SNO-F-MAP-01).
///
/// Меток HLC нет намеренно: карта — производное и в слияние не идёт.
/// Карта лежит целиком или не лежит вовсе: новая кладётся вместо
/// прежней одной транзакцией, и половины карты в базе не бывает.
class DriftBookMapRepository implements BookMapRepository {
  /// Создаёт хранилище.
  DriftBookMapRepository(this._db);

  final AppDatabase _db;

  @override
  Future<StoredBookMap?> load() async {
    final List<MapPointRow> rows = await _db.select(_db.mapPoints).get();
    if (rows.isEmpty) {
      return null;
    }
    // У строк одной карты ключ набора и версия одни. Строка с другими —
    // след карты, которую не дописали прежние версии; в карту она не
    // идёт, и набор без неё не сойдётся с полкой — карта пересчитается.
    final MapPointRow first = rows.first;
    return StoredBookMap(
      layoutKey: first.layoutKey,
      version: first.algorithmVersion,
      points: <String, MapPoint>{
        for (final MapPointRow row in rows)
          if (row.layoutKey == first.layoutKey &&
              row.algorithmVersion == first.algorithmVersion)
            row.bookId: MapPoint(key: row.fingerprint, x: row.x, y: row.y),
      },
    );
  }

  @override
  Future<void> replace(StoredBookMap map) async {
    await _db.transaction(() async {
      await _db.delete(_db.mapPoints).go();
      await _db.batch((Batch batch) {
        batch.insertAll(_db.mapPoints, <MapPointsCompanion>[
          for (final MapEntry<String, MapPoint> entry in map.points.entries)
            MapPointsCompanion(
              bookId: Value<String>(entry.key),
              x: Value<double>(entry.value.x),
              y: Value<double>(entry.value.y),
              fingerprint: Value<String>(entry.value.key),
              layoutKey: Value<String>(map.layoutKey),
              algorithmVersion: Value<int>(map.version),
            ),
        ]);
      });
    });
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.mapPoints).go();
  }
}
