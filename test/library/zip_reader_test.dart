import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/infrastructure/files/file_book_handle.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';
import 'package:memoria/infrastructure/files/zip_reader.dart';

import '../support/fake_reading.dart';

/// SNO-ALG-LIT-01: читатель ZIP на архивах, собранных другими
/// реализациями — модулем `zipfile` из Python и программой `zip` от
/// Info-ZIP (`tool/make_zip_fixtures.py`).
const String _fixtures = 'test/fixtures/zip';

/// Содержимое файла архива выводится из его пути — то же правило, что в
/// `tool/make_zip_fixtures.py`. Сверяются разом и имя, и байты.
List<int> contentOf(String path) => utf8.encode('%PDF-1.4\n${'$path\n' * 40}');

const List<String> _books = <String>[
  '01 Анатомия/01 Анатомия человека, т. 1.pdf',
  '01 Анатомия/02 Атлас.pdf',
  '02 Физиология/Нормальная физиология.pdf',
  'Латинский язык.pdf',
];

Future<T> withArchive<T>(
  String name,
  Future<T> Function(ZipArchive archive) body,
) async {
  final BookHandle handle = await FileBookHandle.open(
    FilePathSource('$_fixtures/$name'),
  );
  try {
    return await body(await ZipArchive.read(handle));
  } finally {
    await handle.close();
  }
}

Future<Uint8List> unpack(
  ZipArchive archive,
  ZipEntry entry, {
  int chunkSize = zipChunkSize,
}) async {
  final BytesBuilder out = BytesBuilder();
  await archive.extract(entry, (Uint8List chunk) async {
    out.add(chunk);
  }, chunkSize: chunkSize);
  return out.takeBytes();
}

List<String> filesOf(ZipArchive archive) => <String>[
  for (final ZipEntry entry in archive.entries)
    if (!entry.isDirectory) entry.name,
];

Matcher zipProblem(ZipProblem problem) {
  return isA<ZipException>().having(
    (ZipException error) => error.problem,
    'problem',
    problem,
  );
}

Future<ZipArchive> readBytes(List<int> bytes) {
  return ZipArchive.read(MemoryBookHandle(bytes));
}

void main() {
  group('SNO-ALG-LIT-01: архивы от других реализаций', () {
    for (final String name in <String>[
      'shelf_stored.zip',
      'shelf_deflate_cp866.zip',
      'descriptor_python.zip',
      'zip64_python.zip',
      'zip64_infozip.zip',
      'wrapped_infozip.zip',
      'unicode_extra.zip',
      'backslash.zip',
    ]) {
      test('SNO-ALG-LIT-01: $name — имена и содержимое сходятся', () async {
        await withArchive(name, (ZipArchive archive) async {
          final List<String> files = filesOf(archive);
          expect(files, isNotEmpty);
          for (final ZipEntry entry in archive.entries) {
            if (entry.isDirectory) {
              continue;
            }
            expect(
              await unpack(archive, entry),
              contentOf(entry.name),
              reason: entry.name,
            );
          }
        });
      });
    }

    test('SNO-ALG-LIT-01: без сжатия — имена в UTF-8 и записи-папки', () async {
      await withArchive('shelf_stored.zip', (ZipArchive archive) async {
        expect(
          archive.entries.map((ZipEntry entry) => entry.name),
          <String>['01 Анатомия/', '02 Физиология/', ..._books],
        );
        expect(archive.entries.first.isDirectory, isTrue);
        expect(archive.entries.last.isStored, isTrue);
        expect(archive.entries.last.size, contentOf(_books.last).length);
      });
    });

    test('SNO-ALG-LIT-01: имена в 866-й странице без признака UTF-8', () async {
      await withArchive('shelf_deflate_cp866.zip', (ZipArchive archive) async {
        expect(filesOf(archive), containsAll(_books));
        expect(filesOf(archive), contains('Заметки.txt'));
        expect(filesOf(archive), contains('__MACOSX/._Латинский язык.pdf'));
        // Deflate: запись в архиве короче распакованной.
        final ZipEntry book = archive.entries.firstWhere(
          (ZipEntry entry) => entry.name == _books.first,
        );
        expect(book.isStored, isFalse);
        expect(book.compressedSize, lessThan(book.size));
      });
    });

    test('SNO-ALG-LIT-01: имена в UTF-8 без признака (Info-ZIP)', () async {
      await withArchive('wrapped_infozip.zip', (ZipArchive archive) async {
        expect(
          filesOf(archive),
          containsAll(<String>[
            'Литература/2 Биохимия/Биохимия.pdf',
            'Литература/10 Гистология/Гистология.pdf',
            'Литература/1 Анатомия/Атласы/Синельников.pdf',
            'Литература/Словарь.pdf',
          ]),
        );
      });
    });

    test('SNO-ALG-LIT-01: ZIP64 читается у обеих реализаций', () async {
      for (final String name in <String>[
        'zip64_python.zip',
        'zip64_infozip.zip',
      ]) {
        await withArchive(name, (ZipArchive archive) async {
          expect(filesOf(archive), _books, reason: name);
          for (final ZipEntry entry in archive.entries) {
            expect(entry.size, contentOf(entry.name).length, reason: name);
          }
        });
      }
    });

    test('SNO-ALG-LIT-01: длины и суммы после данных', () async {
      await withArchive('descriptor_python.zip', (ZipArchive archive) async {
        expect(filesOf(archive), _books.take(2));
        // Признак «описатель после данных» стоит, а числа известны.
        expect(archive.entries.first.flags & 0x8, 0x8);
        expect(archive.entries.first.size, contentOf(_books.first).length);
      });
    });

    test('SNO-ALG-LIT-01: имя в Юникоде рядом с обычным', () async {
      await withArchive('unicode_extra.zip', (ZipArchive archive) async {
        // У первой записи поле верное. У второй сумма обычного имени не
        // сошлась — поле про другое имя, и оно не принимается.
        expect(filesOf(archive), <String>['Анатомия.pdf', 'Atlas.pdf']);
      });
    });

    test('SNO-ALG-LIT-01: обратная черта — тоже разделитель папок', () async {
      await withArchive('backslash.zip', (ZipArchive archive) async {
        expect(filesOf(archive), <String>['Папка/Книга.pdf']);
      });
    });

    test('SNO-ALG-LIT-01: пустой архив — архив без записей', () async {
      await withArchive('empty.zip', (ZipArchive archive) async {
        expect(archive.entries, isEmpty);
      });
    });
  });

  group('SNO-ALG-LIT-01: распаковка потоком', () {
    test('SNO-ALG-LIT-01: кусок любого размера даёт то же самое', () async {
      for (final String name in <String>[
        'shelf_stored.zip',
        'shelf_deflate_cp866.zip',
      ]) {
        await withArchive(name, (ZipArchive archive) async {
          final ZipEntry entry = archive.entries.firstWhere(
            (ZipEntry entry) => entry.name == _books.first,
          );
          for (final int chunkSize in <int>[1, 7, 100, 4096]) {
            expect(
              await unpack(archive, entry, chunkSize: chunkSize),
              contentOf(entry.name),
              reason: '$name, кусок $chunkSize',
            );
          }
        });
      }
    });

    test('SNO-ALG-LIT-01: книга отдаётся кусками, не целиком', () async {
      await withArchive('shelf_stored.zip', (ZipArchive archive) async {
        final ZipEntry entry = archive.entries.last;
        final List<int> sizes = <int>[];
        await archive.extract(entry, (Uint8List chunk) async {
          sizes.add(chunk.length);
        }, chunkSize: 500);
        // Память не растёт с размером книги: ни один кусок не больше
        // заданного.
        expect(sizes.every((int size) => size <= 500), isTrue);
        expect(sizes.length, (entry.size / 500).ceil());
      });
    });

    test('SNO-ALG-LIT-01: запись без сжатия читается как книга', () async {
      await withArchive('shelf_stored.zip', (ZipArchive archive) async {
        final ZipEntry entry = archive.entries.last;
        final BookHandle book = await archive.stored(entry);
        final List<int> expected = contentOf(entry.name);
        expect(book.length, expected.length);

        final Uint8List middle = Uint8List(50);
        expect(await book.read(middle, 100, 50), 50);
        expect(middle, expected.sublist(100, 150));
        // За концом книги архив не читается.
        final Uint8List tail = Uint8List(64);
        expect(await book.read(tail, expected.length - 10, 64), 10);
        expect(await book.read(tail, expected.length, 64), 0);

        // Отпечаток книги считается прямо из архива.
        expect(
          await bookFingerprint(book),
          await bookFingerprint(MemoryBookHandle(expected)),
        );
      });
    });

    test('SNO-ALG-LIT-01: сжатая запись книгой не читается', () async {
      await withArchive('shelf_deflate_cp866.zip', (ZipArchive archive) async {
        final ZipEntry entry = archive.entries.first;
        await expectLater(
          archive.stored(entry),
          throwsA(zipProblem(ZipProblem.unsupportedMethod)),
        );
      });
    });
  });

  group('SNO-ALG-LIT-01: отказы названы', () {
    test('SNO-ALG-LIT-01: не архив', () async {
      await expectLater(
        withArchive('not_a_zip.zip', (ZipArchive archive) async {}),
        throwsA(zipProblem(ZipProblem.notZip)),
      );
      await expectLater(
        readBytes(const <int>[]),
        throwsA(zipProblem(ZipProblem.notZip)),
      );
    });

    test('SNO-ALG-LIT-01: оборванный архив', () async {
      await expectLater(
        withArchive('truncated.zip', (ZipArchive archive) async {}),
        throwsA(zipProblem(ZipProblem.truncated)),
      );
      // Начало ZIP есть, а до оглавления файл не дожил.
      await expectLater(
        readBytes(<int>[0x50, 0x4b, 0x03, 0x04, ...List<int>.filled(10, 0)]),
        throwsA(zipProblem(ZipProblem.truncated)),
      );
    });

    test('SNO-ALG-LIT-01: оглавление указывает мимо файла', () async {
      final Uint8List bytes = File(
        '$_fixtures/shelf_stored.zip',
      ).readAsBytesSync();
      // Смещение оглавления — четыре байта перед длиной комментария.
      final int offset = bytes.length - 6;
      bytes.setRange(offset, offset + 4, <int>[0x00, 0xff, 0xff, 0x7f]);
      await expectLater(
        readBytes(bytes),
        throwsA(zipProblem(ZipProblem.damaged)),
      );
    });

    test('SNO-ALG-LIT-01: архив с паролем', () async {
      await withArchive('encrypted_infozip.zip', (ZipArchive archive) async {
        final ZipEntry entry = archive.entries.first;
        expect(entry.isEncrypted, isTrue);
        await expectLater(
          unpack(archive, entry),
          throwsA(zipProblem(ZipProblem.encrypted)),
        );
      });
    });

    test('SNO-ALG-LIT-01: сжатие не ZIP-овское', () async {
      await withArchive('bzip2_python.zip', (ZipArchive archive) async {
        final ZipEntry entry = archive.entries.first;
        expect(entry.isSupported, isFalse);
        await expectLater(
          unpack(archive, entry),
          throwsA(zipProblem(ZipProblem.unsupportedMethod)),
        );
      });
    });

    test('SNO-ALG-LIT-01: контрольная сумма не сошлась', () async {
      await withArchive('bad_crc.zip', (ZipArchive archive) async {
        for (final ZipEntry entry in archive.entries) {
          if (entry.isDirectory) {
            continue;
          }
          if (entry.name == _books[1]) {
            await expectLater(
              unpack(archive, entry),
              throwsA(zipProblem(ZipProblem.badChecksum)),
            );
          } else {
            // Остальные книги архива целы.
            expect(await unpack(archive, entry), contentOf(entry.name));
          }
        }
      });
    });

    test('SNO-ALG-LIT-01: испорченный Deflate — отказ, а не мусор', () async {
      final Uint8List bytes = File(
        '$_fixtures/descriptor_python.zip',
      ).readAsBytesSync();
      final ZipArchive intact = await readBytes(bytes);
      final ZipEntry entry = intact.entries.first;
      // Данные первой записи идут сразу за её заголовком и именем.
      final int data = 30 + utf8.encode(entry.name).length;
      for (int i = 0; i < 16; i++) {
        bytes[data + 8 + i] ^= 0xff;
      }
      final ZipArchive broken = await readBytes(bytes);
      await expectLater(
        unpack(broken, broken.entries.first),
        throwsA(
          anyOf(
            zipProblem(ZipProblem.damaged),
            zipProblem(ZipProblem.badChecksum),
          ),
        ),
      );
    });
  });

  group('SNO-ALG-LIT-01: кодировки и суммы', () {
    test('SNO-ALG-LIT-01: CRC-32 — как у всех', () {
      // Проверочное значение из описания алгоритма.
      expect(crc32Of(ascii.encode('123456789')), 0xcbf43926);
      expect(crc32Of(const <int>[]), 0);
    });

    test('SNO-ALG-LIT-01: 866-я кодовая страница', () {
      expect(
        decodeCp866(<int>[0x80, 0xad, 0xa0, 0xe2, 0xae, 0xac, 0xa8, 0xef]),
        'Анатомия',
      );
      expect(decodeCp866(<int>[0xf0, 0xf1, 0xfc, 0x20, 0x31]), 'Ёё№ 1');
      expect(decodeCp866(ascii.encode('Atlas.pdf')), 'Atlas.pdf');
    });
  });
}
