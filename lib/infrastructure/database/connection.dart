import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Имя файла базы. Меняться не должно: файл лежит на устройствах.
const String databaseFileName = 'memoria.sqlite';

/// Открывает базу в каталоге данных приложения.
///
/// Тяжёлая работа уходит в отдельный изолят: разбор большого PDF и запись
/// в базу не должны подтормаживать листание.
QueryExecutor openDatabaseFile() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationSupportDirectory();
    final File file = File(p.join(dir.path, databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}

/// Открывает базу в памяти — для тестов.
QueryExecutor openInMemoryDatabase() => NativeDatabase.memory();
