import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_directory.dart';

/// Папка, где лежат **наши** копии книг.
///
/// Копия делается, когда книгу нельзя читать там, где она лежит
/// (провайдер Android отдал поток, а не файл), и всегда — в сборках
/// ветвей СНО2026: там книги живут внутри приложения (SNO-DIV-03).
Future<Directory> applicationBooks() async {
  final Directory data = await appDataDirectory();
  return Directory(p.join(data.path, 'books'));
}

/// Имя копии: краткий отпечаток места, откуда книга взята, плюс имя
/// файла.
///
/// Отпечаток нужен, чтобы две книги с одинаковым именем из разных
/// папок не легли одна поверх другой; имя — чтобы папку приложения
/// можно было открыть и понять, что в ней лежит. [origin] — ссылка
/// `content://` или путь к файлу.
String copyFileName(String origin, String name) {
  final String digest = sha256
      .convert(utf8.encode(origin))
      .toString()
      .substring(0, 16);
  final String safe = name.replaceAll(RegExp(r'[^\w.\- ]+'), '_');
  return '$digest-$safe';
}

/// Копирует файл [source] в папку [books] и возвращает путь копии.
///
/// Книга в память не читается: копирует система, кусками, и файл в
/// сотню мегабайт занимает столько же памяти, сколько файл в один.
/// Пишется сначала соседний файл `.part`, готовым он переименовывается:
/// оборванная копия не остаётся под именем книги.
Future<String> copyFileInto({
  required String source,
  required String name,
  required Directory books,
}) async {
  if (!await books.exists()) {
    await books.create(recursive: true);
  }
  final String destination = p.join(books.path, copyFileName(source, name));
  if (p.equals(source, destination)) {
    // Выбрали саму копию: копировать файл в самого себя — значит
    // обнулить его.
    return destination;
  }
  final File part = File('$destination.part');
  try {
    await File(source).copy(part.path);
    await part.rename(destination);
  } on Object {
    if (await part.exists()) {
      await part.delete();
    }
    rethrow;
  }
  return destination;
}
