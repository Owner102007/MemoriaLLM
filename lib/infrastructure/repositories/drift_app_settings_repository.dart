import 'package:drift/drift.dart';

import '../../domain/settings/app_settings.dart';
import '../database/app_database.dart';

/// Локальные настройки приложения поверх drift.
class DriftAppSettingsRepository implements AppSettingsRepository {
  /// Создаёт репозиторий.
  DriftAppSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) async {
    final AppSettingRow? row = await _query(key).getSingleOrNull();
    return row?.settingValue;
  }

  @override
  Future<void> write(String key, String value) async {
    final AppSettingsCompanion row = AppSettingsCompanion(
      settingKey: Value<String>(key),
      settingValue: Value<String>(value),
    );
    await _db.into(_db.appSettings).insertOnConflictUpdate(row);
  }

  @override
  Future<void> remove(String key) async {
    final statement = _db.delete(_db.appSettings);
    statement.where((tbl) => tbl.settingKey.equals(key));
    await statement.go();
  }

  @override
  Stream<String?> watch(String key) {
    return _query(key).watchSingleOrNull().map(_value);
  }

  String? _value(AppSettingRow? row) => row?.settingValue;

  SimpleSelectStatement<$AppSettingsTable, AppSettingRow> _query(String key) {
    final query = _db.select(_db.appSettings);
    query.where((tbl) => tbl.settingKey.equals(key));
    return query;
  }
}
