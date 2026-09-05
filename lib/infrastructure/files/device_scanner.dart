import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/library/device_scan.dart';

/// Обход файловой системы устройства.
///
/// Сам обход — чистая работа с диском, и вынесен в функцию, которая ничего
/// не знает ни про изоляты, ни про базу: её можно позвать прямо в тесте на
/// дереве, собранном во временной папке, и проверить каждое правило
/// отбора. Изолят надет сверху отдельно — ровно для того, чтобы обход не
/// подтормаживал список, который в это время растёт на экране.
typedef ScanSink = void Function(ScannedFile file);

/// Обходит [roots] и отдаёт найденные PDF в [onFile].
///
/// Правила отбора живут в `domain/library/device_scan.dart`: сюда они
/// приходят готовыми, и менять их надо там. Здесь остаётся то, чего в
/// домене быть не может, — сам диск.
///
/// Ошибки на отдельных ветках проглатываются намеренно: на телефоне
/// половина папок закрыта даже с полным доступом, и упасть на первой из
/// них значило бы не найти ничего вовсе.
Future<int> scanForPdfs({
  required List<String> roots,
  required ScanSink onFile,
  void Function(String directory, int visited)? onDirectory,
  bool Function()? isCancelled,
  int maxDepth = 24,
}) async {
  final Set<String> seen = <String>{};
  final List<_PendingDirectory> stack = <_PendingDirectory>[
    for (final String root in roots) _PendingDirectory(root, 0),
  ];
  int visited = 0;
  int found = 0;

  while (stack.isNotEmpty) {
    if (isCancelled?.call() ?? false) {
      break;
    }
    final _PendingDirectory current = stack.removeLast();
    if (current.depth > maxDepth || !seen.add(current.path)) {
      continue;
    }
    visited++;
    onDirectory?.call(current.path, visited);

    final List<FileSystemEntity> entries;
    try {
      entries = await Directory(current.path).list(followLinks: false).toList();
    } on FileSystemException {
      // Папка закрыта или исчезла под руками — обычное дело на телефоне.
      continue;
    }

    for (final FileSystemEntity entry in entries) {
      final String name = _nameOf(entry.path);
      if (entry is Directory) {
        if (shouldSkipDirectory(path: entry.path, name: name)) {
          continue;
        }
        stack.add(_PendingDirectory(entry.path, current.depth + 1));
        continue;
      }
      if (entry is! File || isHiddenName(name) || !looksLikePdfName(name)) {
        continue;
      }
      final FileStat stat;
      try {
        stat = await entry.stat();
      } on FileSystemException {
        continue;
      }
      if (stat.size <= 0 || !await fileHasPdfSignature(entry)) {
        continue;
      }
      found++;
      onFile(
        ScannedFile(
          path: entry.path,
          size: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
  }
  return found;
}

/// Есть ли в начале файла сигнатура PDF.
///
/// Читается только начало: расширение `.pdf` носят и переименованные
/// картинки, и обрубленные закачки, и html-страницы «скачивание
/// начнётся автоматически». Открывать их движком, чтобы это выяснить, —
/// секунды на каждый файл.
Future<bool> fileHasPdfSignature(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final Uint8List head = await handle.read(kSignatureProbe);
    return hasPdfSignature(head);
  } on FileSystemException {
    return false;
  } finally {
    await handle?.close();
  }
}

/// Обход в отдельном изоляте с потоком находок.
///
/// Поток закрывается сам, когда обход закончен. Отмена — обычная отписка:
/// изолят убивается, и полусотня оставшихся папок не обходится вовсе.
///
/// В `flutter test` изоляты не используются: время там подменено, и ждать
/// настоящий изолят тест не станет. Поэтому сценарии проверяются на
/// [scanForPdfs] напрямую, а эта обёртка остаётся тонкой настолько,
/// чтобы в ней нечему было сломаться.
Stream<ScanEvent> scanInIsolate(List<String> roots) {
  final ReceivePort port = ReceivePort();
  late final StreamController<ScanEvent> controller;
  Isolate? isolate;
  StreamSubscription<dynamic>? listener;

  Future<void> stop() async {
    await listener?.cancel();
    listener = null;
    port.close();
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
  }

  controller = StreamController<ScanEvent>(
    onListen: () async {
      isolate = await Isolate.spawn(_scanEntryPoint, <Object>[
        port.sendPort,
        roots,
      ]);
      listener = port.listen((Object? message) {
        final ScanEvent? event = _decodeEvent(message);
        if (event == null) {
          unawaited(controller.close());
          return;
        }
        controller.add(event);
      });
    },
    onCancel: stop,
  );
  return controller.stream;
}

/// Что пришло из обхода: найденный файл или отметка о продвижении.
class ScanEvent {
  /// Создаёт событие.
  const ScanEvent({this.file, required this.directory, required this.visited});

  /// Найденный файл, если это находка.
  final ScannedFile? file;

  /// В какой папке обход сейчас.
  final String directory;

  /// Сколько папок обойдено.
  final int visited;
}

class _PendingDirectory {
  const _PendingDirectory(this.path, this.depth);

  final String path;
  final int depth;
}

String _nameOf(String path) {
  final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
  return slash < 0 ? path : path.substring(slash + 1);
}

/// Точка входа изолята.
///
/// Через порт летят простые списки, а не свои классы: изолят умеет
/// передавать только то, что умеет копировать, и держать это правило
/// явным дешевле, чем разбираться потом, почему падает передача.
Future<void> _scanEntryPoint(List<Object> args) async {
  final SendPort port = args[0] as SendPort;
  final List<String> roots = (args[1] as List<Object?>).cast<String>();
  int lastReport = 0;
  await scanForPdfs(
    roots: roots,
    onFile: (ScannedFile file) {
      port.send(<Object>[
        'file',
        file.path,
        file.size,
        file.modifiedAt.millisecondsSinceEpoch,
      ]);
    },
    onDirectory: (String directory, int visited) {
      // Не каждая папка: на телефоне их десятки тысяч, и отчёт о каждой
      // стоил бы больше самого обхода. Раз в двадцать пять — это
      // несколько отметок в секунду, чего глазу более чем достаточно.
      if (visited - lastReport < 25) {
        return;
      }
      lastReport = visited;
      port.send(<Object>['dir', directory, visited]);
    },
  );
  port.send('done');
}

ScanEvent? _decodeEvent(Object? message) {
  if (message is! List<Object?>) {
    return null;
  }
  final Object? kind = message.first;
  if (kind == 'file') {
    return ScanEvent(
      file: ScannedFile(
        path: message[1]! as String,
        size: message[2]! as int,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(message[3]! as int),
      ),
      directory: '',
      visited: 0,
    );
  }
  if (kind == 'dir') {
    return ScanEvent(
      directory: message[1]! as String,
      visited: message[2]! as int,
    );
  }
  return null;
}
