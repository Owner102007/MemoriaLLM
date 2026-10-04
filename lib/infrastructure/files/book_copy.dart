import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_directory.dart';
import 'file_fingerprint.dart';

/// Папка, где лежат **наши** копии книг.
///
/// Копия делается, когда книгу нельзя читать там, где она лежит
/// (провайдер Android отдал поток, а не файл), и всегда — в сборках
/// ветвей СНО2026: там книги живут внутри приложения (SNO-DIV-03).
Future<Directory> applicationBooks() async {
  final Directory data = await appDataDirectory();
  return Directory(p.join(data.path, 'books'));
}

/// Имя копии книги с отпечатком [fingerprint].
///
/// Копия названа по **содержимому**, а не по месту, откуда её взяли.
/// Имя по месту подводило трижды: файл, пересохранённый под прежним
/// именем, затирал копию книги, уже стоящей на полке; та же книга из
/// другой папки ложилась второй копией, а первая оставалась сиротой; и
/// отказ открыть файл удалял копию, принадлежащую другой книге. Отпечаток
/// тот же, каким книга опознаётся на полке, — одна книга, один файл.
String copyNameFor(String fingerprint) => '$fingerprint.pdf';

/// Куда пишется копия, пока она не готова.
///
/// [origin] — ссылка `content://` или путь к файлу: два переноса из
/// разных мест не пишут в один файл.
String incomingPathIn(Directory books, String origin) {
  final String digest = sha256
      .convert(utf8.encode(origin))
      .toString()
      .substring(0, 16);
  return p.join(books.path, 'incoming-$digest.part');
}

/// Принимает дописанную копию [part]: называет её по отпечатку
/// содержимого и возвращает путь, по которому она теперь лежит.
///
/// Если такая книга в папке уже есть, [part] удаляется, а готовый файл
/// не трогается: он может быть открыт прямо сейчас.
Future<String> settleCopy({
  required File part,
  required Directory books,
}) async {
  final String fingerprint = await fileFingerprint(part.path);
  final File destination = File(p.join(books.path, copyNameFor(fingerprint)));
  if (await destination.exists()) {
    await part.delete();
    return destination.path;
  }
  await part.rename(destination.path);
  return destination.path;
}

/// Копирует файл [source] в папку [books] и возвращает путь копии.
///
/// Книга в память не читается: копирует система, кусками, и файл в
/// сотню мегабайт занимает столько же памяти, сколько файл в один.
/// Пишется сначала соседний файл `.part`, готовым он получает имя книги:
/// оборванная копия не остаётся под именем книги.
Future<String> copyFileInto({
  required String source,
  required Directory books,
}) async {
  // Выбрана сама копия из этой папки — особого случая нет: её копия
  // получит тот же отпечаток, и [settleCopy] вернёт уже лежащий файл.
  if (!await books.exists()) {
    await books.create(recursive: true);
  }
  await sweepIncoming(books);
  final File part = File(incomingPathIn(books, source));
  try {
    await File(source).copy(part.path);
    return await settleCopy(part: part, books: books);
  } on Object {
    await discardPart(part);
    rethrow;
  }
}

/// Выметает из [books] недописанные копии прежних переносов.
///
/// Остаться они могут только после того, как приложение убили посреди
/// переноса: при ошибке перенос убирает свой файл сам. Импорт идёт по
/// одной книге за раз, поэтому любой `.part` к началу нового переноса —
/// мусор.
Future<void> sweepIncoming(Directory books) async {
  if (!await books.exists()) {
    return;
  }
  await for (final FileSystemEntity entry in books.list()) {
    if (entry is File && _isIncoming(p.basename(entry.path))) {
      await discardPart(entry);
    }
  }
}

/// Имя недописанной копии — то, что даёт [incomingPathIn].
bool _isIncoming(String name) {
  return name.startsWith('incoming-') && name.endsWith('.part');
}

/// Убирает недописанную копию, если она осталась.
Future<void> discardPart(File part) async {
  try {
    if (await part.exists()) {
      await part.delete();
    }
  } on FileSystemException {
    // Убрать не вышло — файл `.part` книгой не считается и никому не
    // мешает; следующая копия из того же места ляжет поверх него.
  }
}
