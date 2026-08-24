import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Версия схемы. Растёт вместе с каждой миграцией.
///
/// 1 — исходная схема (S2). 2 — запас по краям полосы в настройках книги
/// (S4.6). 3 — сила затемнения нечитаемой части страницы (S4.7): страница
/// в режимах половины и трети больше не обрезается, а гаснет. 4 —
/// категории полки (S5.2): своя таблица и ссылка на неё у книги.
const int appSchemaVersion = 4;

/// База данных приложения.
///
/// Хранит библиотеку, прогресс чтения, настройки чтения на книгу, цитаты,
/// заметки, закладки, историю запросов к модели и локальные настройки.
/// Всё, кроме локальных настроек, несёт поля CRDT — движок слияния
/// появится в S10 и не должен трогать структуру таблиц.
@DriftDatabase(
  tables: <Type>[
    BookCategories,
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
        if (from < 3) {
          await m.addColumn(bookSettings, bookSettings.dimOutside);
        }
        if (from < 4) {
          await m.createTable(bookCategories);
          // Колонка добавляется пустой, и все книги читателя оказываются
          // в разделе «Без категории». Раскладывать их по категориям
          // автоматически — по папке, по автору, по чему угодно — нельзя:
          // приложение не знает, как читатель мыслит свою библиотеку, а
          // разобрать чужую раскладку дороже, чем сделать её самому.
          await m.addColumn(books, books.categoryId);
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
