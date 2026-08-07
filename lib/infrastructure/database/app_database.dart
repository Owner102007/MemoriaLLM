import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Версия схемы. Растёт вместе с каждой миграцией.
const int appSchemaVersion = 1;

/// База данных приложения.
///
/// Хранит библиотеку, прогресс чтения, настройки чтения на книгу, цитаты,
/// заметки, закладки, историю запросов к модели и локальные настройки.
/// Всё, кроме локальных настроек, несёт поля CRDT — движок слияния
/// появится в S10 и не должен трогать структуру таблиц.
@DriftDatabase(
  tables: <Type>[
    Books,
    ReadingProgress,
    BookSettings,
    Quotes,
    Notes,
    Bookmarks,
    LlmQueries,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Создаёт базу поверх готового подключения.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => appSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Схема существует в единственной версии, миграций пока нет.
        // Каждая следующая версия добавляет сюда свою ветку и тест.
      },
      beforeOpen: (OpeningDetails details) async {
        // Без этого SQLite молча игнорирует внешние ключи, и каскадное
        // удаление вместе с ними.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
