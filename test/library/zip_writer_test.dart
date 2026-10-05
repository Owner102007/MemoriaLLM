import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/infrastructure/files/file_book_handle.dart';
import 'package:memoria/infrastructure/files/zip_reader.dart';
import 'package:memoria/infrastructure/files/zip_writer.dart';
import 'package:path/path.dart' as p;

import '../support/other_zip.dart';

/// SNO-ALG-REC-03: писатель ZIP.
///
/// Архив записи открывают «Проводником», 7-Zip и разбором на Python,
/// поэтому писателя проверяет не только свой читатель — он простил бы
/// писателю общие с ним ошибки, — но и чужая реализация: модуль
/// `zipfile` из Python (`test/support/other_zip.dart`).
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-zip-');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Содержимое, которое сжимается плохо: псевдослучайные байты.
  Uint8List noise(int length, int seed) {
    final Random random = Random(seed);
    return Uint8List.fromList(<int>[
      for (int i = 0; i < length; i++) random.nextInt(256),
    ]);
  }

  /// Записи образца: пустая, маленькая, строки журнала, шум больше
  /// куска чтения, вложенная папка и имя кириллицей.
  Map<String, List<int>> sample() {
    return <String, List<int>>{
      'manifest.json': utf8.encode('{"schema": "проба"}'),
      'empty.txt': const <int>[],
      'events.jsonl': utf8.encode('{"seq":1,"type":"page.shown"}\n' * 5000),
      'noise.bin': noise(300 * 1024, 7),
      'clt/answers.json': utf8.encode('{"q1": 5}'),
      'заметки/читателя.txt': utf8.encode('ядерный гриб'),
    };
  }

  Future<File> write(Map<String, List<int>> entries) async {
    final File archive = File(p.join(temp.path, 'sample.zip'));
    final ZipWriter writer = await ZipWriter.create(archive);
    for (final MapEntry<String, List<int>> entry in entries.entries) {
      await writer.addBytes(
        entry.key,
        entry.value,
        modified: DateTime(2026, 11, 3, 14, 2, 11),
      );
    }
    await writer.finish();
    return archive;
  }

  Future<Map<String, Uint8List>> readBack(File archive) async {
    final FileBookHandle handle = await FileBookHandle.open(
      FilePathSource(archive.path),
    );
    try {
      final ZipArchive zip = await ZipArchive.read(handle);
      final Map<String, Uint8List> found = <String, Uint8List>{};
      for (final ZipEntry entry in zip.entries) {
        final BytesBuilder bytes = BytesBuilder();
        await zip.extract(entry, (Uint8List chunk) async => bytes.add(chunk));
        found[entry.name] = bytes.takeBytes();
      }
      return found;
    } finally {
      await handle.close();
    }
  }

  group('SNO-ALG-REC-03: записанное читается', () {
    test('SNO-ALG-REC-03: свой читатель видит те же имена и байты', () async {
      final Map<String, List<int>> entries = sample();
      final Map<String, Uint8List> found = await readBack(await write(entries));

      // Порядок записей — порядок записи: манифест остаётся первым.
      expect(found.keys.toList(), entries.keys.toList());
      for (final MapEntry<String, List<int>> entry in entries.entries) {
        expect(found[entry.key], entry.value, reason: entry.key);
      }
    });

    test('SNO-ALG-REC-03: чужая реализация читает архив без ошибок', () async {
      final Map<String, List<int>> entries = sample();
      final File archive = await write(entries);

      final OtherZip? other = await readWithPython(archive);
      if (other == null) {
        // Python нет только на машине разработчика: в CI он есть, и
        // там отсутствие — отказ (`readWithPython`).
        return;
      }
      expect(other.problem, isNull);
      expect(other.names, entries.keys.toList());
      for (final MapEntry<String, List<int>> entry in entries.entries) {
        expect(
          other.sha256[entry.key],
          '${sha256.convert(entry.value)}',
          reason: entry.key,
        );
        expect(other.sizes[entry.key], entry.value.length, reason: entry.key);
      }
    });

    test('SNO-ALG-REC-03: содержимое берётся потоком, кусками', () async {
      final Uint8List big = noise(700 * 1024, 11);
      final File archive = File(p.join(temp.path, 'stream.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      // Куски разной длины, в том числе пустой: граница куска не должна
      // значить ничего.
      Stream<List<int>> chunks() async* {
        yield big.sublist(0, 1);
        yield const <int>[];
        yield big.sublist(1, 70000);
        yield big.sublist(70000);
      }

      final ZipWritten written = await writer.add('big.bin', chunks());
      await writer.finish();

      expect(written.size, big.length);
      expect(written.crc32, crc32Of(big));
      expect((await readBack(archive))['big.bin'], big);
    });

    test('SNO-ALG-REC-03: длины и сумма стоят в заголовке записи', () async {
      final List<int> text = utf8.encode('строка\n' * 100);
      final File archive = await write(<String, List<int>>{'a.txt': text});
      final ByteData head = ByteData.sublistView(await archive.readAsBytes());

      expect(head.getUint32(0, Endian.little), 0x04034b50);
      // Описателя данных после записи нет: флаг 3 снят.
      expect(head.getUint16(6, Endian.little) & 0x8, 0);
      // Способ сжатия — Deflate.
      expect(head.getUint16(8, Endian.little), 8);
      expect(head.getUint32(14, Endian.little), crc32Of(text));
      expect(head.getUint32(18, Endian.little), greaterThan(0));
      expect(head.getUint32(18, Endian.little), lessThan(text.length));
      expect(head.getUint32(22, Endian.little), text.length);
    });

    test('SNO-ALG-REC-03: заголовок каждой записи сходится с '
        'оглавлением', () async {
      // Длины и сумму писатель вписывает в заголовок записи, вернувшись
      // назад; свой читатель и Python берут их из оглавления, а
      // «Проводник» и 7-Zip смотрят и в заголовок. Поэтому сверяется
      // каждая запись, а не только первая.
      final Map<String, List<int>> entries = sample();
      final File archive = await write(entries);
      final ByteData bytes = ByteData.sublistView(await archive.readAsBytes());
      final FileBookHandle handle = await FileBookHandle.open(
        FilePathSource(archive.path),
      );
      try {
        final ZipArchive zip = await ZipArchive.read(handle);
        expect(zip.entries, hasLength(entries.length));
        for (final ZipEntry entry in zip.entries) {
          final int at = entry.headerOffset;
          expect(
            bytes.getUint32(at, Endian.little),
            0x04034b50,
            reason: entry.name,
          );
          expect(
            bytes.getUint32(at + 14, Endian.little),
            entry.crc32,
            reason: entry.name,
          );
          expect(
            bytes.getUint32(at + 18, Endian.little),
            entry.compressedSize,
            reason: entry.name,
          );
          expect(
            bytes.getUint32(at + 22, Endian.little),
            entry.size,
            reason: entry.name,
          );
          expect(entry.size, entries[entry.name]!.length, reason: entry.name);
        }
      } finally {
        await handle.close();
      }
    });

    test('SNO-ALG-REC-03: пустые записи пишутся и после того, как архив '
        'читали', () async {
      // Фильтру сжатия, которому не дали ни байта, при завершении нужен
      // пустой кусок — иначе он читает невыставленную длину входа. Чаще
      // всего это видно после распаковки: память фильтра занята её
      // следами.
      await readBack(await write(sample()));
      final File archive = File(p.join(temp.path, 'empties.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      for (int i = 0; i < 40; i++) {
        await writer.addBytes('empty/$i.txt', const <int>[]);
        await writer.add('stream/$i.txt', const Stream<List<int>>.empty());
      }
      await writer.finish();

      final Map<String, Uint8List> found = await readBack(archive);
      expect(found, hasLength(80));
      expect(found.values.every((Uint8List bytes) => bytes.isEmpty), isTrue);
      final OtherZip? other = await readWithPython(archive);
      if (other != null) {
        expect(other.problem, isNull);
        expect(other.names, hasLength(80));
      }
    });

    test('SNO-ALG-REC-03: имя кириллицей помечено как UTF-8', () async {
      final File archive = await write(<String, List<int>>{
        'a.txt': const <int>[1],
        'б.txt': const <int>[2],
      });
      final FileBookHandle handle = await FileBookHandle.open(
        FilePathSource(archive.path),
      );
      try {
        final ZipArchive zip = await ZipArchive.read(handle);
        expect(zip.entries[0].flags & 0x800, 0);
        expect(zip.entries[1].flags & 0x800, 0x800);
        expect(zip.entries[1].name, 'б.txt');
      } finally {
        await handle.close();
      }
    });
  });

  group('SNO-ALG-REC-03: отказы писателя', () {
    Future<void> refuses(String name) async {
      final ZipWriter writer = await ZipWriter.create(
        File(p.join(temp.path, 'bad.zip')),
      );
      try {
        await expectLater(
          writer.addBytes(name, const <int>[1]),
          throwsA(isA<ZipWriteException>()),
          reason: name,
        );
      } finally {
        await writer.abort();
      }
    }

    test('SNO-ALG-REC-03: имя, которое распаковщики читают по-разному, не '
        'принимается', () async {
      await refuses('');
      await refuses('/events.jsonl');
      await refuses('folder/');
      await refuses(r'folder\events.jsonl');
      await refuses('../events.jsonl');
      await refuses('a//b.txt');
    });

    test('SNO-ALG-REC-03: двух записей с одним именем не бывает', () async {
      final ZipWriter writer = await ZipWriter.create(
        File(p.join(temp.path, 'twice.zip')),
      );
      await writer.addBytes('a.txt', const <int>[1]);
      await expectLater(
        writer.addBytes('a.txt', const <int>[2]),
        throwsA(isA<ZipWriteException>()),
      );
      await writer.abort();
    });

    test('SNO-ALG-REC-03: в закрытый архив записи не добавляются', () async {
      final ZipWriter writer = await ZipWriter.create(
        File(p.join(temp.path, 'closed.zip')),
      );
      await writer.addBytes('a.txt', const <int>[1]);
      await writer.finish();
      await expectLater(
        writer.addBytes('b.txt', const <int>[2]),
        throwsA(isA<ZipWriteException>()),
      );
      // Второе закрытие ничего не ломает.
      await writer.finish();
    });

    test('SNO-ALG-REC-03: архив без оглавления архивом не считается', () async {
      final File archive = File(p.join(temp.path, 'torn.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      await writer.addBytes('a.txt', utf8.encode('текст'));
      await writer.abort();

      final FileBookHandle handle = await FileBookHandle.open(
        FilePathSource(archive.path),
      );
      try {
        await expectLater(
          ZipArchive.read(handle),
          throwsA(isA<ZipException>()),
        );
      } finally {
        await handle.close();
      }
    });
  });
}
