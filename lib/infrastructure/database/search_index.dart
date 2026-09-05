import 'package:drift/drift.dart';

/// Индекс поиска по файлам устройства — виртуальная таблица FTS5.
///
/// Заводится не средствами drift, а прямым SQL, и на то есть причина.
/// Виртуальную таблицу drift описывает своим языком, но всё, что нам от
/// неё нужно, — четыре колонки и `bm25`; зато прямой SQL позволяет
/// **пережить отсутствие FTS5**, а это здесь главное.
///
/// FTS5 — необязательный модуль SQLite. На устройствах его приносит
/// `sqlite3_flutter_libs` и он есть всегда, но приложение открывает базу
/// и там, где библиотека системная. Если бы таблица создавалась вместе с
/// остальными, отсутствие модуля означало бы, что база не открывается
/// вовсе, — то есть читатель терял бы всю библиотеку из-за поиска.
/// Поэтому создание завёрнуто в проверку, а поиск без индекса
/// деградирует до перебора имён.
const String kSearchIndexTable = 'device_search';

/// Создаёт индекс, если SQLite умеет FTS5.
///
/// Возвращает `true`, если индекс есть и им можно пользоваться.
Future<bool> createSearchIndex(DatabaseConnectionUser db) async {
  try {
    await db.customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $kSearchIndexTable USING fts5('
      // Токенайзер самый простой намеренно: вся нормализация — свёртка
      // похожих букв, `ё`, регистр, стеммер — уже сделана в
      // `domain/library/search_text.dart`, и в индекс кладётся готовый
      // текст. Так одно и то же правило действует и на текст, и на
      // запрос, а проверяется оно юнит-тестом, а не через SQLite.
      "path UNINDEXED, name, meta, body, tokenize = 'unicode61'"
      ')',
    );
    return true;
  } on Object {
    // Модуля нет. Это не поломка: список файлов, обложки и добавление
    // книг работают полностью, а поиск идёт перебором имён.
    return false;
  }
}

/// Есть ли в этой базе рабочий индекс.
Future<bool> hasSearchIndex(DatabaseConnectionUser db) async {
  try {
    await db
        .customSelect('SELECT count(*) AS n FROM $kSearchIndexTable')
        .getSingle();
    return true;
  } on Object {
    return false;
  }
}
