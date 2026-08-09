import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Версия схемы. Растёт вместе с каждой миграцией.
///
/// 1 — исходная схема (S2). 2 — запас по краям полосы в настройках книги
/// (S4.6): читатель уменьшает полосу щипком, и это надо помнить.
const int appSchemaVersion = 2;

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
        // Каждая версия добавляет сюда свою ветку и тест. Ветки идут
        // по возрастанию и не заменяют друг друга: база живого читателя
        // может приехать с любой прошлой версии, а не только с соседней.
        if (from < 2) {
          await m.addColumn(bookSettings, bookSettings.stripFit);
        }
      },
      beforeOpen: (OpeningDetails details) async {
        // Без этого SQLite молча игнорирует внешние ключи, и каскадное
        // удаление вместе с ними.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}
