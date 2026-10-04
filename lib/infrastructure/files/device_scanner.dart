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

/// Обходит [roots] и отдаёт в [onFile] каждый файл, имя которого
/// принимает [accept].
///
/// Сам обход — один на всё, что ищут на устройстве: книги основного
/// приложения ([scanForPdfs]) и архивы с литературой в сборках ветвей
/// СНО2026 (`archive_scanner.dart`, SNO-ALG-LIT-02). Разница между ними —
/// только в том, какое имя годится и что делать с найденным файлом.
///
/// Правила пропуска папок живут в `domain/library/device_scan.dart`.
/// Скрытые файлы не отдаются никогда. [rootOrder] расставляет папки
/// корня: папка с меньшим числом обходится раньше — так находки из
/// «Загрузок» появляются в первые секунды, а не в конце обхода. Без него
/// порядок прежний — как папки лежат на диске.
///
/// Ошибки на отдельных ветках проглатываются намеренно: на телефоне
/// половина папок закрыта даже с полным доступом, и упасть на первой из
/// них значило бы не найти ничего вовсе.
Future<void> walkFiles({
  required List<String> roots,
  required bool Function(String name) accept,
  required Future<void> Function(File file, String name) onFile,
  void Function(String directory, int visited)? onDirectory,
  bool Function()? isCancelled,
  int maxDepth = 24,
  int Function(String name)? rootOrder,
}) async {
  final Set<String> seen = <String>{};
  final List<_PendingDirectory> stack = <_PendingDirectory>[
    for (final String root in roots) _PendingDirectory(root, 0),
  ];
  int visited = 0;

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

    final List<_PendingDirectory> children = <_PendingDirectory>[];
    for (final FileSystemEntity entry in entries) {
      final String name = _nameOf(entry.path);
      if (entry is Directory) {
        if (shouldSkipDirectory(path: entry.path, name: name)) {
          continue;
        }
        children.add(_PendingDirectory(entry.path, current.depth + 1));
        continue;
      }
      if (entry is! File || isHiddenName(name) || !accept(name)) {
        continue;
      }
      await onFile(entry, name);
    }
    if (rootOrder != null && current.depth == 0 && children.length > 1) {
      // Со стопки снимается последнее положенное: папка, которой идти
      // первой, кладётся последней. При равенстве порядок — как на
      // диске, поэтому сравнение дополнено местом в списке.
      final List<int> rank = <int>[
        for (final _PendingDirectory child in children)
          rootOrder(_nameOf(child.path)),
      ];
      final List<int> order = <int>[
        for (int i = 0; i < children.length; i++) i,
      ];
      order.sort((int a, int b) {
        final int byRank = rank[b].compareTo(rank[a]);
        return byRank != 0 ? byRank : a.compareTo(b);
      });
      for (final int i in order) {
        stack.add(children[i]);
      }
    } else {
      stack.addAll(children);
    }
  }
}

/// Обходит [roots] и отдаёт найденные PDF в [onFile].
///
/// Правила отбора живут в `domain/library/device_scan.dart`: сюда они
/// приходят готовыми, и менять их надо там. Здесь остаётся то, чего в
/// домене быть не может, — сам диск ([walkFiles]).
Future<int> scanForPdfs({
  required List<String> roots,
  required ScanSink onFile,
  void Function(String directory, int visited)? onDirectory,
  bool Function()? isCancelled,
  int maxDepth = 24,
}) async {
  int found = 0;
  await walkFiles(
    roots: roots,
    accept: looksLikePdfName,
    onDirectory: onDirectory,
    isCancelled: isCancelled,
    maxDepth: maxDepth,
    onFile: (File file, String name) async {
      final FileStat stat;
      try {
        stat = await file.stat();
      } on FileSystemException {
        return;
      }
      if (stat.size <= 0 || !await fileHasPdfSignature(file)) {
        return;
      }
      found++;
      onFile(
        ScannedFile(
          path: file.path,
          size: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    },
  );
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

/// Что запускается в изоляте обхода. Подменяется в тестах: настоящему
/// обходу упасть не на чем, а проверить надо именно падение (BUG-16).
typedef ScanEntryPoint = FutureOr<void> Function(List<Object> args);

/// Обход в отдельном изоляте с потоком находок.
///
/// Поток закрывается сам, когда обход закончен. Отмена — обычная отписка:
/// изолят убивается, и полусотня оставшихся папок не обходится вовсе.
///
/// **Упавший обход тоже кончается** (BUG-16). Изолят заводится с
/// `onError` и `onExit`: необработанная ошибка и выход без слова «готово»
/// закрывают поток ошибкой [ScanFailure]. Прежде о них не узнавал никто —
/// поток не закрывался, обход считался идущим, и строка «Смотрим
/// устройство…» висела вечно. Всё идёт через один порт: порядок сообщений
/// одного отправителя сохраняется, и «готово» не обгонит выход изолята.
///
/// В widget-тестах изоляты не используются: время там подменено, и ждать
/// настоящий изолят тест не станет. Сценарии обхода проверяются на
/// [scanForPdfs] напрямую, а сама обёртка — обычным тестом, где время
/// настоящее.
Stream<ScanEvent> scanInIsolate(
  List<String> roots, {
  ScanEntryPoint entryPoint = _scanEntryPoint,
}) {
  return scanStreamInIsolate<ScanEvent>(
    roots,
    entryPoint: entryPoint,
    decode: _decodeEvent,
  );
}

/// Изолят обхода и поток того, что он шлёт, — общая часть [scanInIsolate]
/// и поиска архивов (`archive_scanner.dart`, SNO-ALG-LIT-02).
///
/// [entryPoint] получает порт и корни и шлёт в порт простые списки;
/// [decode] превращает список в событие. Последним изолят шлёт
/// [kScanDone]. Сообщение, которого [decode] не узнал, считается ошибкой
/// изолята: её он шлёт списком из текста и стека.
Stream<T> scanStreamInIsolate<T>(
  List<String> roots, {
  required ScanEntryPoint entryPoint,
  required T? Function(Object? message) decode,
}) {
  final ReceivePort port = ReceivePort();
  late final StreamController<T> controller;
  Isolate? isolate;
  StreamSubscription<dynamic>? listener;
  bool ended = false;

  Future<void> stop() async {
    ended = true;
    await listener?.cancel();
    listener = null;
    port.close();
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
  }

  void finish([String? failure]) {
    if (ended) {
      return;
    }
    ended = true;
    if (failure != null) {
      controller.addError(ScanFailure(failure));
    }
    unawaited(controller.close());
  }

  controller = StreamController<T>(
    onListen: () async {
      listener = port.listen((Object? message) {
        if (ended) {
          return;
        }
        if (message == kScanDone) {
          finish();
          return;
        }
        if (message == null) {
          // Изолят вышел, а «готово» не сказал: его убила система или он
          // кончился сам, не дойдя до конца.
          finish('обход остановился, не дойдя до конца');
          return;
        }
        final T? event = decode(message);
        if (event == null) {
          // Не находка и не отметка — значит, сообщение об ошибке:
          // изолят шлёт его списком из текста ошибки и стека.
          finish(_describeIsolateError(message));
          return;
        }
        controller.add(event);
      });
      try {
        isolate = await Isolate.spawn<List<Object>>(
          entryPoint,
          <Object>[port.sendPort, roots],
          onError: port.sendPort,
          onExit: port.sendPort,
        );
        if (ended) {
          // Отписались, пока изолят заводился: `stop` его ещё не видел.
          // Не убить его здесь — он обошёл бы весь диск в закрытый порт.
          isolate?.kill(priority: Isolate.immediate);
          isolate = null;
        }
      } on Object catch (error) {
        finish('обход не запустился: $error');
      }
    },
    onCancel: stop,
  );
  return controller.stream;
}

/// Слово, которым изолят сообщает, что обошёл всё.
const String kScanDone = 'done';

String _describeIsolateError(Object message) {
  if (message is List<Object?> && message.isNotEmpty) {
    return '${message.first}';
  }
  return '$message';
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
  port.send(kScanDone);
}

ScanEvent? _decodeEvent(Object? message) {
  if (message is! List<Object?> || message.isEmpty) {
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
