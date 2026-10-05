/// Архив записи: манифест, упаковка, сверка (SNO-F-REC-05,
/// SNO-ALG-REC-03).
///
/// Завершённая запись сессии исследования СНО2026 лежит папкой потоков:
/// журнал, снимки состояния, сведения о записи. Здесь папка становится
/// одним файлом `sno2026_<ветвь>_<код>_<устройство>_<дата-время>.zip`,
/// который узнаётся по имени, проверяется по суммам и читается любым
/// распаковщиком. Первым в архиве лежит `manifest.json` — паспорт
/// записи: всё, что было в `recording.json`, и перечень файлов с
/// числом строк и SHA-256.
///
/// **Запись нельзя потерять при упаковке.** Архив пишется в файл
/// `.part`, открывается заново, каждая его запись распаковывается и
/// сверяется с суммой, посчитанной по исходному файлу, — и только
/// после этого архив получает своё имя, а папка потоков удаляется.
/// Любой отказ оставляет папку как была.
///
/// Виджетов здесь нет; диск настоящий, проверяется на временной папке.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/library/book_source.dart';
import '../../infrastructure/files/file_book_handle.dart';
import '../../infrastructure/files/zip_reader.dart';
import '../../infrastructure/files/zip_writer.dart';
import 'event.dart';
import 'session.dart';
import 'store.dart';

/// Имя манифеста в архиве записи.
const String kManifestFile = 'manifest.json';

/// Расширение архива записи.
const String kArchiveExtension = '.zip';

/// Хвост имени недописанного файла.
const String kPartSuffix = '.part';

/// Чем собран архив: по этой строке разбор узнаёт раскладку.
const String kArchivePacker = 'memoria-zip/1';

/// Манифест больше этого — не манифест.
const int kManifestLimit = 4 * 1024 * 1024;

/// Оглавление архива записи больше этого не читается: записей в нём
/// десяток, а не сотни тысяч.
const int _directoryLimit = 1024 * 1024;

const int _newline = 0x0A;

/// Почему запись не упаковалась.
class PackException implements Exception {
  /// Создаёт отказ.
  const PackException(this.reason, {this.cause});

  /// Причина словами — для журнала, не для экрана.
  final String reason;

  /// Что случилось на самом деле.
  final Object? cause;

  @override
  String toString() => 'PackException($reason, $cause)';
}

/// Файл записи, как он лёг в архив.
class PackedFile {
  /// Создаёт сведения.
  const PackedFile({
    required this.name,
    required this.bytes,
    required this.sha256,
    this.lines,
    this.droppedLines = 0,
  });

  /// Имя в архиве, папки через `/`.
  final String name;

  /// Сколько байт легло в архив.
  final int bytes;

  /// SHA-256 того, что легло в архив, шестнадцатеричной строкой.
  final String sha256;

  /// Сколько строк в потоке; `null` — файл не поток строк.
  final int? lines;

  /// Сколько строк отброшено: оборванный хвост потока — строка без
  /// перевода строки в конце.
  final int droppedLines;

  /// Запись для манифеста.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bytes': bytes,
      'sha256': sha256,
      if (lines != null) 'lines': lines,
      if (lines != null) 'dropped_lines': droppedLines,
    };
  }
}

/// Идентификатор записи в её сведениях [info] — в `recording.json`
/// или в манифесте; `null` — его там нет.
String? recordingIdOf(Map<String, Object?>? info) {
  final Object? recording = info?['recording'];
  if (recording is! Map<String, Object?>) {
    return null;
  }
  final Object? id = recording['id'];
  return id is String && id.isNotEmpty ? id : null;
}

/// Манифест архива (SNO-ALG-REC-03, шаг 4).
///
/// [info] — содержимое `recording.json`: ветвь, сборка, устройство,
/// участник, часы, остановка, блоки и отлучки переходят в манифест как
/// есть, второго файла с теми же сведениями в архиве нет. Не
/// прочитался — манифест говорит об этом (`info_missing`), а архив
/// собирается всё равно. Потока, которого в записи нет, нет и в
/// перечне [files]: пустых заглушек не бывает.
Map<String, Object?> buildManifest({
  required Map<String, Object?>? info,
  required String archiveName,
  required DateTime packedAt,
  required List<PackedFile> files,
}) {
  return <String, Object?>{
    'schema': kRecordingSchema,
    if (info != null)
      for (final MapEntry<String, Object?> field in info.entries)
        if (field.key != 'schema') field.key: field.value,
    if (info == null) 'info_missing': true,
    // Взгляда в записи нет: айтрекер придёт со своей функцией.
    'eye_tracker': const <String, Object?>{'present': false},
    'archive': <String, Object?>{
      'name': archiveName,
      'packer': kArchivePacker,
      'packed_at': isoWithOffset(packedAt),
    },
    'files': <String, Object?>{
      for (final PackedFile file in files) file.name: file.toJson(),
    },
  };
}

/// Один файл папки записи.
class _Source {
  _Source(this.name, this.file);

  /// Имя в архиве.
  final String name;

  final File file;

  /// Сколько байт берётся в архив: весь файл либо поток без
  /// оборванной последней строки.
  int keep = 0;

  int? lines;
  int dropped = 0;
  String sha = '';
  DateTime? modified;

  Stream<List<int>> open() {
    return keep == 0 ? const Stream<List<int>>.empty() : file.openRead(0, keep);
  }

  PackedFile get packed {
    return PackedFile(
      name: name,
      bytes: keep,
      sha256: sha,
      lines: lines,
      droppedLines: dropped,
    );
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// SHA-256 потока [content] и число переводов строки в нём.
Future<({String sha, int bytes, int lines})> _sum(
  Stream<List<int>> content,
) async {
  final _DigestSink result = _DigestSink();
  final ByteConversionSink input = sha256.startChunkedConversion(result);
  int bytes = 0;
  int lines = 0;
  await for (final List<int> chunk in content) {
    input.add(chunk);
    bytes += chunk.length;
    for (final int byte in chunk) {
      if (byte == _newline) {
        lines++;
      }
    }
  }
  input.close();
  return (sha: '${result.value}', bytes: bytes, lines: lines);
}

/// SHA-256 файла шестнадцатеричной строкой.
Future<String> fileSha256(File file) async {
  return (await _sum(file.openRead())).sha;
}

/// Сколько байт файла [file] занимают целые строки: до последнего
/// перевода строки включительно.
Future<int> _wholeLines(File file, int length) async {
  if (length == 0) {
    return 0;
  }
  const int block = 64 * 1024;
  final RandomAccessFile opened = await file.open();
  try {
    int end = length;
    while (end > 0) {
      final int start = end > block ? end - block : 0;
      await opened.setPosition(start);
      final Uint8List chunk = await opened.read(end - start);
      final int at = chunk.lastIndexOf(_newline);
      if (at >= 0) {
        return start + at + 1;
      }
      end = start;
    }
    return 0;
  } finally {
    await opened.close();
  }
}

/// Файлы папки записи по именам, которые они получат в архиве.
///
/// `recording.json` в перечень не входит — он переходит в манифест;
/// недописанные файлы `.part` тоже.
Future<List<_Source>> _sourcesOf(Directory folder) async {
  final List<_Source> sources = <_Source>[];
  await for (final FileSystemEntity entity in folder.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) {
      continue;
    }
    final String name = p
        .split(p.relative(entity.path, from: folder.path))
        .join('/');
    if (name == kRecordingFile ||
        name == kManifestFile ||
        name.endsWith(kPartSuffix)) {
      continue;
    }
    sources.add(_Source(name, entity));
  }
  sources.sort((_Source a, _Source b) => a.name.compareTo(b.name));
  return sources;
}

Future<void> _measure(_Source source) async {
  final int length = await source.file.length();
  final bool lined = source.name.endsWith('.jsonl');
  source.keep = lined ? await _wholeLines(source.file, length) : length;
  final ({String sha, int bytes, int lines}) sum = await _sum(source.open());
  if (sum.bytes != source.keep) {
    throw PackException('файл ${source.name} изменился, пока его считали');
  }
  source
    ..sha = sum.sha
    ..lines = lined ? sum.lines : null
    ..dropped = lined && length > source.keep ? 1 : 0;
  try {
    source.modified = await source.file.lastModified();
  } on FileSystemException {
    source.modified = null;
  }
}

/// Читает файл JSON с объектом; `null` — файла нет или он не читается.
Future<Map<String, Object?>?> readJsonFile(File file) async {
  try {
    if (!await file.exists()) {
      return null;
    }
    final Object? raw = jsonDecode(await file.readAsString());
    return raw is Map<String, Object?> ? raw : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// Что известно об архиве на диске.
class ArchiveCheck {
  /// Создаёт ответ.
  const ArchiveCheck({required this.manifest, required this.intact});

  /// Манифест; `null` — архив не читается или манифеста в нём нет.
  final Map<String, Object?>? manifest;

  /// Все ли файлы из перечня манифеста лежат в архиве и сходятся с
  /// его суммами.
  final bool intact;
}

/// Открывает архив [archive], читает манифест и сверяет суммы.
///
/// [sums] — имена и SHA-256, которые обязаны сойтись; без них сверка
/// идёт по перечню самого манифеста. Ничего не бросает: архив, который
/// не читается, — ответ, а не ошибка.
Future<ArchiveCheck> checkArchive(
  File archive, {
  Map<String, String>? sums,
}) async {
  FileBookHandle? handle;
  try {
    handle = await FileBookHandle.open(FilePathSource(archive.path));
    final ZipArchive zip = await ZipArchive.read(
      handle,
      directoryLimit: _directoryLimit,
    );
    final Map<String, ZipEntry> entries = <String, ZipEntry>{
      for (final ZipEntry entry in zip.entries) entry.name: entry,
    };
    final ZipEntry? first = entries[kManifestFile];
    if (first == null || first.size > kManifestLimit) {
      return const ArchiveCheck(manifest: null, intact: false);
    }
    final BytesBuilder text = BytesBuilder(copy: true);
    await zip.extract(first, (Uint8List chunk) async => text.add(chunk));
    final Uint8List manifestBytes = text.takeBytes();
    final Object? raw = jsonDecode(utf8.decode(manifestBytes));
    if (raw is! Map<String, Object?>) {
      return const ArchiveCheck(manifest: null, intact: false);
    }
    final Map<String, String> expected = <String, String>{};
    if (sums != null) {
      expected.addAll(sums);
    } else {
      final Object? files = raw['files'];
      if (files is! Map<String, Object?>) {
        return ArchiveCheck(manifest: raw, intact: false);
      }
      for (final MapEntry<String, Object?> file in files.entries) {
        final Object? about = file.value;
        final Object? sha = about is Map<String, Object?>
            ? about['sha256']
            : null;
        if (sha is! String) {
          return ArchiveCheck(manifest: raw, intact: false);
        }
        expected[file.key] = sha;
      }
    }
    for (final MapEntry<String, String> want in expected.entries) {
      if (want.key == kManifestFile) {
        if ('${sha256.convert(manifestBytes)}' != want.value) {
          return ArchiveCheck(manifest: raw, intact: false);
        }
        continue;
      }
      final ZipEntry? entry = entries[want.key];
      if (entry == null) {
        return ArchiveCheck(manifest: raw, intact: false);
      }
      final _DigestSink result = _DigestSink();
      final ByteConversionSink input = sha256.startChunkedConversion(result);
      await zip.extract(entry, (Uint8List chunk) async => input.add(chunk));
      input.close();
      if ('${result.value}' != want.value) {
        return ArchiveCheck(manifest: raw, intact: false);
      }
    }
    return ArchiveCheck(manifest: raw, intact: true);
  } on Object {
    // Не ZIP, оборван, не читается, манифест не JSON — архив повреждён.
    return const ArchiveCheck(manifest: null, intact: false);
  } finally {
    await handle?.close();
  }
}

Future<void> _remove(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Обрывок остался: следующая упаковка запишет поверх него.
  }
}

/// Та же ли запись лежит в архиве с манифестом [manifest], что и в
/// папке: по идентификатору записи, а без него — по сумме журнала.
bool _sameRecording(
  Map<String, Object?> manifest,
  String? id,
  List<_Source> sources,
) {
  final String? packed = recordingIdOf(manifest);
  if (id != null && packed != null) {
    return id == packed;
  }
  final Object? files = manifest['files'];
  if (files is! Map<String, Object?>) {
    return false;
  }
  for (final _Source source in sources) {
    if (source.name != kEventsFile) {
      continue;
    }
    final Object? about = files[kEventsFile];
    return about is Map<String, Object?> && about['sha256'] == source.sha;
  }
  return false;
}

/// Упаковывает папку записи [folder] в архив рядом с ней
/// (SNO-F-REC-05).
///
/// Отвечает готовым архивом; папки после этого нет. Любой отказ —
/// [PackException]: папка цела, обрывка архива не осталось, упаковку
/// можно повторить. Если архив этой же записи уже лежит рядом —
/// приложение закрыли между архивом и уборкой папки, — он сверяется, и
/// папка убирается без второй упаковки.
///
/// [now] подменяется в тестах; [beforeVerify] и [beforeCleanup] —
/// тоже только там: по ним проверяется отказ на каждом шаге.
Future<File> packRecording(
  Directory folder, {
  DateTime Function()? now,
  Future<void> Function(File part)? beforeVerify,
  Future<void> Function(File archive)? beforeCleanup,
}) async {
  final String base = p.basename(folder.path);
  final Directory records = folder.parent;
  final List<_Source> sources;
  final Map<String, Object?>? info;
  try {
    sources = await _sourcesOf(folder);
    if (sources.isEmpty) {
      throw const PackException('в папке записи нет файлов');
    }
    for (final _Source source in sources) {
      await _measure(source);
    }
    info = await readJsonFile(File(p.join(folder.path, kRecordingFile)));
  } on FileSystemException catch (error) {
    throw PackException('папка записи не читается', cause: error);
  }
  final String? id = recordingIdOf(info);

  // Имя архива — имя папки. Занято архивом другой записи (две записи
  // одного участника в одну минуту) — хвост `-2`, `-3`.
  File target = File(p.join(records.path, '$base$kArchiveExtension'));
  for (int number = 2; await target.exists(); number++) {
    final ArchiveCheck known = await checkArchive(target);
    final Map<String, Object?>? manifest = known.manifest;
    if (known.intact &&
        manifest != null &&
        _sameRecording(manifest, id, sources)) {
      await _cleanup(folder);
      return target;
    }
    target = File(p.join(records.path, '$base-$number$kArchiveExtension'));
  }

  final File part = File('${target.path}$kPartSuffix');
  final DateTime stamp = (now ?? DateTime.now)();
  try {
    final List<int> manifest = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(
        buildManifest(
          info: info,
          archiveName: p.basename(target.path),
          packedAt: stamp,
          files: <PackedFile>[
            for (final _Source source in sources) source.packed,
          ],
        ),
      ),
    );
    final ZipWriter writer = await ZipWriter.create(part);
    try {
      // Манифест — первым: его читают, не распаковывая остального.
      await writer.addBytes(kManifestFile, manifest, modified: stamp);
      for (final _Source source in sources) {
        final ZipWritten written = await writer.add(
          source.name,
          source.open(),
          modified: source.modified ?? stamp,
        );
        if (written.size != source.keep) {
          throw PackException(
            'файл ${source.name} изменился, пока упаковывался',
          );
        }
      }
      await writer.finish();
    } on Object {
      await writer.abort();
      rethrow;
    }
    await beforeVerify?.call(part);
    final ArchiveCheck check = await checkArchive(
      part,
      sums: <String, String>{
        kManifestFile: '${sha256.convert(manifest)}',
        for (final _Source source in sources) source.name: source.sha,
      },
    );
    if (!check.intact) {
      throw const PackException('архив не сошёлся с записью');
    }
    await part.rename(target.path);
  } on PackException {
    await _remove(part);
    rethrow;
  } on Object catch (error) {
    await _remove(part);
    throw PackException('архив не собрался', cause: error);
  }
  await beforeCleanup?.call(target);
  // Папка убирается только теперь: архив на месте и сверен.
  await _cleanup(folder);
  return target;
}

/// Убирает папку потоков упакованной записи.
///
/// Не убралась (файл занят, диск отказал) — не беда: архив уже лежит,
/// а следующий запуск узнает в папке ту же запись и уберёт её.
Future<void> _cleanup(Directory folder) async {
  try {
    await folder.delete(recursive: true);
  } on FileSystemException {
    // Останется до следующего запуска.
  }
}
