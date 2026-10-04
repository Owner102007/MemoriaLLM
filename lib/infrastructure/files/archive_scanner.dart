/// Поиск архивов с книгами на устройстве (SNO-ALG-LIT-02, SNO-F-LIT-03).
///
/// Обход — тот же, что ищет книги в основном приложении
/// (`device_scanner.dart`): те же корни, те же правила пропуска папок,
/// тот же изолят с тем же поведением при падении. Отличается отбор:
/// файл с расширением `.zip`, у которого читается оглавление и в
/// котором лежит хотя бы один PDF. Книги устройства при этом не ищутся
/// и не показываются — в сборках ветвей СНО2026 свои PDF на полку не
/// добавляются (решение владельца П3 от 04.10.2026).
library;

import 'dart:io';
import 'dart:isolate';

import '../../domain/library/archive_scan.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/shelf_archive.dart';
import 'device_scanner.dart';
import 'file_book_handle.dart';
import 'zip_reader.dart';

/// Обходит [roots] и отдаёт в [onArchive] ZIP-архивы с книгами.
///
/// Папки корня, где архив лежит чаще всего («Загрузки», «Документы»),
/// обходятся первыми (`archiveRootOrder`). Возвращает число найденных
/// архивов.
Future<int> scanForArchives({
  required List<String> roots,
  required void Function(FoundArchive archive) onArchive,
  void Function(String directory, int visited)? onDirectory,
  bool Function()? isCancelled,
  int maxDepth = 24,
}) async {
  int found = 0;
  await walkFiles(
    roots: roots,
    accept: isArchiveName,
    rootOrder: archiveRootOrder,
    onDirectory: onDirectory,
    isCancelled: isCancelled,
    maxDepth: maxDepth,
    onFile: (File file, String name) async {
      final FoundArchive? archive = await probeArchive(file);
      if (archive == null) {
        return;
      }
      found++;
      onArchive(archive);
    },
  );
  return found;
}

/// Смотрит, архив ли [file] с книгами; `null` — нет.
///
/// Читается только оглавление — оно стоит в конце файла, и архив в
/// несколько гигабайт стоит столько же, сколько архив в мегабайт. Число
/// книг считает то же правило, что раскладывает архив по полке
/// (`layoutShelfArchive`): список обещает ровно то, что встанет.
///
/// Не ZIP, оборванный, повреждённый, многотомный и нечитаемый файл —
/// не архив с книгами: в список он не попадает, и причину здесь никто
/// не называет. Архив с паролем и с чужим сжатием в список попадает:
/// оглавление у него читается, а отказ словами он получит при
/// распаковке.
Future<FoundArchive?> probeArchive(File file) async {
  FileBookHandle? handle;
  try {
    final FileStat stat = await file.stat();
    if (stat.size <= 0) {
      return null;
    }
    handle = await FileBookHandle.open(FilePathSource(file.path));
    final ZipArchive archive = await ZipArchive.read(handle);
    final int books = layoutShelfArchive(<String>[
      for (final ZipEntry entry in archive.entries) entry.name,
    ]).books.length;
    if (books == 0) {
      return null;
    }
    return FoundArchive(
      path: file.path,
      size: stat.size,
      modifiedAt: stat.modified,
      books: books,
    );
  } on Object {
    // Что бы ни случилось с одним файлом, обход идёт дальше: архив,
    // который не прочёлся, просто не показан.
    return null;
  } finally {
    await handle?.close();
  }
}

/// Поиск архивов в отдельном изоляте с потоком находок.
///
/// Поток закрывается сам, когда обход закончен; отписка убивает изолят;
/// упавший обход закрывает поток ошибкой `ScanFailure` — всё это даёт
/// общая обёртка `scanStreamInIsolate` (BUG-16).
Stream<FoundArchive> findArchivesInIsolate(
  List<String> roots, {
  ScanEntryPoint entryPoint = _archiveEntryPoint,
}) {
  return scanStreamInIsolate<FoundArchive>(
    roots,
    entryPoint: entryPoint,
    decode: _decodeArchive,
  );
}

/// Точка входа изолята: через порт летят простые списки.
Future<void> _archiveEntryPoint(List<Object> args) async {
  final SendPort port = args[0] as SendPort;
  final List<String> roots = (args[1] as List<Object?>).cast<String>();
  await scanForArchives(
    roots: roots,
    onArchive: (FoundArchive archive) {
      port.send(<Object>[
        'archive',
        archive.path,
        archive.size,
        archive.modifiedAt.millisecondsSinceEpoch,
        archive.books,
      ]);
    },
  );
  port.send(kScanDone);
}

FoundArchive? _decodeArchive(Object? message) {
  if (message is! List<Object?> ||
      message.length != 5 ||
      message.first != 'archive') {
    return null;
  }
  return FoundArchive(
    path: message[1]! as String,
    size: message[2]! as int,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(message[3]! as int),
    books: message[4]! as int,
  );
}
