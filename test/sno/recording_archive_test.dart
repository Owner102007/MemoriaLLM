import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/infrastructure/files/file_book_handle.dart';
import 'package:memoria/infrastructure/files/zip_reader.dart';
import 'package:memoria/infrastructure/files/zip_writer.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

import '../support/mini_schema.dart';
import '../support/other_zip.dart';

/// SNO-F-REC-05, SNO-ALG-REC-03: папка записи становится архивом.
///
/// Папки — придуманные, во временной папке; диск настоящий. Главное,
/// что здесь проверяется, — запись нельзя потерять при упаковке: отказ
/// на любом шаге оставляет папку как была.
void main() {
  late Directory temp;
  late Directory records;

  const String name = 'sno2026_I_67954332_a91f3c_20261103-1402';
  final DateTime packedAt = DateTime(2026, 11, 3, 14, 45, 30);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-archive-');
    records = Directory(p.join(temp.path, 'Записи'));
    await records.create(recursive: true);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Строки журнала: [count] событий подряд.
  String journal(int count) {
    final RecordingContext context = RecordingContext();
    final StringBuffer text = StringBuffer();
    for (int seq = 1; seq <= count; seq++) {
      text
        ..write(
          encodeEvent(
            seq: seq,
            t: seq * 1000,
            wall: DateTime(2026, 11, 3, 14, 2, 11).add(Duration(seconds: seq)),
            type: SnoEventType.pageShown,
            context: context,
            data: <String, Object?>{'page': seq},
          ),
        )
        ..write('\n');
    }
    return text.toString();
  }

  /// Сведения о записи — как их пишет сессия.
  Map<String, Object?> info({
    String id = '01KB5Z3M4N7Q8R9S0T1V2W3X4Y',
    String stoppedBy = 'experimenter',
  }) {
    return <String, Object?>{
      'schema': 'sno2026-recording/1',
      'branch': 'I',
      'app': <String, Object?>{'version': '0.25.0-sno2026.I'},
      'device': <String, Object?>{'node_id': 'a91f3c0b', 'code': 'a91f3c'},
      'participant': <String, Object?>{
        'code': '67954332',
        'generated': true,
        'generator': 'sno-code/1',
        'generated_at': '2026-11-03T11:02:00.000Z',
        'attempt': 0,
      },
      'recording': <String, Object?>{
        'id': id,
        'clock_anchor': '2026-11-03T14:02:11.482+03:00',
        'planned_s': 2400,
        'duration_s': 480,
        'duration_ms': 480000,
        'stopped_by': stoppedBy,
        'resyncs': 0,
        'events': 5,
        'write_failed': false,
        'finished': true,
        'away': <String, Object?>{
          'count': 1,
          'total_ms': 9000,
          'hidden_ms': 0,
          'longest_ms': 9000,
        },
        'in_background': false,
        'blocks': <Object?>[
          <String, Object?>{
            'n': 1,
            'start_ms': 1000,
            'duration_ms': 3000,
            'closed_by': 'experimenter',
          },
        ],
      },
    };
  }

  /// Заводит папку записи [folder] с файлами [files]; сведения о записи
  /// кладутся, если названы.
  Future<Directory> make(
    Map<String, String> files, {
    String folder = name,
    Map<String, Object?>? about,
  }) async {
    final Directory directory = Directory(p.join(records.path, folder));
    await directory.create(recursive: true);
    for (final MapEntry<String, String> file in files.entries) {
      final File target = File(p.join(directory.path, file.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(file.value, flush: true);
    }
    if (about != null) {
      await File(p.join(directory.path, kRecordingFile))
          .writeAsString(jsonEncode(about), flush: true);
    }
    return directory;
  }

  /// Обычная запись: журнал на пять событий и два снимка.
  Map<String, String> usual() {
    return <String, String>{
      kEventsFile: journal(5),
      kSnapshotStartFile: '{"schema": "sno2026-snapshot/1", "traces": 0}',
      kSnapshotEndFile: '{"schema": "sno2026-snapshot/1", "traces": 3}',
    };
  }

  /// Записи архива: имя → содержимое, в порядке оглавления.
  Future<Map<String, Uint8List>> entriesOf(File archive) async {
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

  Map<String, Object?> manifestOf(Map<String, Uint8List> entries) {
    return jsonDecode(utf8.decode(entries[kManifestFile]!))
        as Map<String, Object?>;
  }

  Map<String, Object?> fileOf(Map<String, Object?> manifest, String file) {
    return (manifest['files']! as Map<String, Object?>)[file]!
        as Map<String, Object?>;
  }

  /// Что лежит в папке записей, по именам.
  Future<List<String>> listing() async {
    final List<String> names = <String>[
      await for (final FileSystemEntity entity in records.list())
        p.basename(entity.path),
    ];
    return names..sort();
  }

  group('SNO-F-REC-05: папка записи становится архивом', () {
    test('SNO-F-REC-05: один файл с именем записи, папки больше нет', () async {
      final Map<String, String> files = usual();
      final Directory folder = await make(files, about: info());

      final File archive = await packRecording(folder, now: () => packedAt);

      expect(p.basename(archive.path), '$name.zip');
      expect(await listing(), <String>['$name.zip']);
      final Map<String, Uint8List> entries = await entriesOf(archive);
      // Манифест — первым; `recording.json` в архив не кладётся: всё
      // его содержимое — в манифесте.
      expect(entries.keys.toList(), <String>[
        kManifestFile,
        kEventsFile,
        kSnapshotEndFile,
        kSnapshotStartFile,
      ]);
      for (final MapEntry<String, String> file in files.entries) {
        expect(utf8.decode(entries[file.key]!), file.value, reason: file.key);
      }
    });

    test('SNO-ALG-REC-03: манифест — паспорт записи с перечнем '
        'файлов', () async {
      final Map<String, String> files = usual();
      final Directory folder = await make(files, about: info());

      final Map<String, Object?> manifest = manifestOf(
        await entriesOf(await packRecording(folder, now: () => packedAt)),
      );

      expect(manifest['schema'], 'sno2026-recording/1');
      expect(manifest['branch'], 'I');
      expect(manifest['app'], <String, Object?>{'version': '0.25.0-sno2026.I'});
      expect((manifest['device']! as Map<String, Object?>)['code'], 'a91f3c');
      expect(
        (manifest['participant']! as Map<String, Object?>)['code'],
        '67954332',
      );
      final Map<String, Object?> recording =
          manifest['recording']! as Map<String, Object?>;
      expect(recording['id'], '01KB5Z3M4N7Q8R9S0T1V2W3X4Y');
      expect(recording['clock_anchor'], '2026-11-03T14:02:11.482+03:00');
      expect(recording['duration_s'], 480);
      expect(recording['stopped_by'], 'experimenter');
      // Блоки и отлучки переходят как были.
      expect(recording['blocks'], hasLength(1));
      expect((recording['away']! as Map<String, Object?>)['count'], 1);
      expect(manifest['archive'], <String, Object?>{
        'name': '$name.zip',
        'packer': kArchivePacker,
        'packed_at': isoWithOffset(packedAt),
      });
      expect(manifest.containsKey('info_missing'), isFalse);

      // Перечень файлов: строки — только у потоков строк.
      final List<int> events = utf8.encode(files[kEventsFile]!);
      expect(fileOf(manifest, kEventsFile), <String, Object?>{
        'bytes': events.length,
        'sha256': '${sha256.convert(events)}',
        'lines': 5,
        'dropped_lines': 0,
      });
      final List<int> start = utf8.encode(files[kSnapshotStartFile]!);
      expect(fileOf(manifest, kSnapshotStartFile), <String, Object?>{
        'bytes': start.length,
        'sha256': '${sha256.convert(start)}',
      });
      expect(
        (manifest['files']! as Map<String, Object?>).keys,
        unorderedEquals(files.keys),
      );
    });

    test('SNO-F-CLT-03: ответы теста нагрузки лежат в архиве подпапкой, а '
        'итог теста — в манифесте', () async {
      const String answers = 'clt/sno-clt-main_B_2400000.json';
      const String scores = 'clt/scores.json';
      final Map<String, String> files = <String, String>{
        ...usual(),
        answers: '{"schema": "sno2026-clt-result/1", "part": "B"}',
        scores: '{"schema": "sno2026-clt-scores/1"}',
        'clt/scenario.json': '{"schema": "sno2026-clt/1"}',
      };
      final Map<String, Object?> clt = <String, Object?>{
        'effort_answers': 2,
        'final': 'complete',
        'final_answers': 16,
        'final_items': 16,
        'files': <String>[answers],
      };
      final Directory folder = await make(
        files,
        about: info()..['clt'] = clt,
      );

      final File archive = await packRecording(folder, now: () => packedAt);

      final Map<String, Uint8List> entries = await entriesOf(archive);
      final Map<String, Object?> manifest = manifestOf(entries);
      // Итог теста переходит в манифест как был.
      expect(manifest['clt'], clt);
      // Файлы подпапки — в архиве под своими именами и в перечне с
      // суммами, как остальные.
      expect(utf8.decode(entries[answers]!), files[answers]);
      expect(utf8.decode(entries[scores]!), files[scores]);
      expect(
        (manifest['files']! as Map<String, Object?>).keys,
        unorderedEquals(files.keys),
      );
      final List<int> bytes = utf8.encode(files[answers]!);
      expect(fileOf(manifest, answers), <String, Object?>{
        'bytes': bytes.length,
        'sha256': '${sha256.convert(bytes)}',
      });
      // Архив сходится со своим манифестом и открывается чужой
      // реализацией.
      expect((await checkArchive(archive)).intact, isTrue);
      final OtherZip? other = await readWithPython(archive);
      // Python нет только на машине разработчика: в CI он есть.
      if (other != null) {
        expect(other.problem, isNull);
        expect(other.names, containsAll(files.keys));
      }
      final Map<String, Object?> schema =
          jsonDecode(await File('tool/sno_manifest.schema.json').readAsString())
              as Map<String, Object?>;
      expect(schemaProblems(manifest, schema), isEmpty);
    });

    test('SNO-F-REC-05: потока нет — нет и файла, без заглушек', () async {
      final Directory folder = await make(<String, String>{
        kEventsFile: journal(2),
      }, about: info());

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      expect(entries.keys.toList(), <String>[kManifestFile, kEventsFile]);
      expect(
        (manifestOf(entries)['files']! as Map<String, Object?>).keys,
        <String>[kEventsFile],
      );
    });

    test('SNO-F-REC-05: поток во вложенной папке ложится с путём', () async {
      final Directory folder = await make(<String, String>{
        ...usual(),
        'clt/final_20261103-1445.json': '{"q1": 5}',
      }, about: info());

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      expect(
        utf8.decode(entries['clt/final_20261103-1445.json']!),
        '{"q1": 5}',
      );
      expect(
        fileOf(manifestOf(entries), 'clt/final_20261103-1445.json')['bytes'],
        9,
      );
    });

    test('SNO-ALG-REC-03: оборванная последняя строка отброшена и '
        'посчитана', () async {
      final String whole = journal(3);
      final Directory folder = await make(<String, String>{
        kEventsFile: '$whole{"seq":4,"t":40',
      }, about: info());

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      expect(utf8.decode(entries[kEventsFile]!), whole);
      final List<int> kept = utf8.encode(whole);
      expect(fileOf(manifestOf(entries), kEventsFile), <String, Object?>{
        'bytes': kept.length,
        'sha256': '${sha256.convert(kept)}',
        'lines': 3,
        'dropped_lines': 1,
      });
    });

    test('SNO-ALG-REC-03: журнал из одного обрывка — пустой поток', () async {
      final Directory folder = await make(<String, String>{
        kEventsFile: '{"seq":1',
        kSnapshotStartFile: '{}',
      }, about: info());

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      expect(entries[kEventsFile], isEmpty);
      final Map<String, Object?> events = fileOf(
        manifestOf(entries),
        kEventsFile,
      );
      expect(events['bytes'], 0);
      expect(events['lines'], 0);
      expect(events['dropped_lines'], 1);
    });

    test('SNO-ALG-REC-03: сведений о записи нет — архив собирается, манифест '
        'говорит об этом', () async {
      final Directory folder = await make(usual());

      final Map<String, Object?> manifest = manifestOf(
        await entriesOf(await packRecording(folder, now: () => packedAt)),
      );

      expect(manifest['info_missing'], isTrue);
      expect(manifest.containsKey('recording'), isFalse);
      expect(fileOf(manifest, kEventsFile)['lines'], 5);
    });

    test('SNO-F-REC-05: недописанный файл ложится в архив как есть: из '
        'папки не пропадает ничего', () async {
      // Приложение закрыли между записью снимка и его переименованием.
      final Directory folder = await make(<String, String>{
        kEventsFile: journal(2),
        '$kSnapshotEndFile$kPartSuffix': '{"schema": "sno2026-snapshot/1"',
      }, about: info());

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      expect(
        utf8.decode(entries['$kSnapshotEndFile$kPartSuffix']!),
        '{"schema": "sno2026-snapshot/1"',
      );
      expect(
        (manifestOf(entries)['files']! as Map<String, Object?>).keys,
        unorderedEquals(<String>[kEventsFile, '$kSnapshotEndFile$kPartSuffix']),
      );
    });

    test('SNO-F-REC-05: сведения о записи не разбираются — файл ложится в '
        'архив как есть, манифест говорит об этом', () async {
      final Directory folder = await make(usual());
      await File(
        p.join(folder.path, kRecordingFile),
      ).writeAsString('{"schema": "sno2026-recording/1", "branch": "I", "rec');

      final Map<String, Uint8List> entries = await entriesOf(
        await packRecording(folder, now: () => packedAt),
      );

      final Map<String, Object?> manifest = manifestOf(entries);
      expect(manifest['info_missing'], isTrue);
      expect(
        utf8.decode(entries[kRecordingFile]!),
        '{"schema": "sno2026-recording/1", "branch": "I", "rec',
      );
      expect(fileOf(manifest, kRecordingFile)['bytes'], 53);
      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-F-REC-05: в папке лежит свой manifest.json — отказ, папка '
        'цела', () async {
      final Directory folder = await make(<String, String>{
        ...usual(),
        kManifestFile: '{"чужой": true}',
      }, about: info());

      await expectLater(
        packRecording(folder, now: () => packedAt),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
      expect(
        await File(p.join(folder.path, kManifestFile)).readAsString(),
        '{"чужой": true}',
      );
    });

    test('SNO-F-REC-05: в папке лежит ярлык, а не файл — отказ, папка '
        'цела', () async {
      if (Platform.isWindows) {
        // Ярлык там заводится только с особыми правами.
        return;
      }
      final Directory folder = await make(usual(), about: info());
      final File outside = File(p.join(temp.path, 'чужой.txt'));
      await outside.writeAsString('не запись');
      await Link(p.join(folder.path, 'input.jsonl')).create(outside.path);

      // Что за ярлыком, в архив не попало бы, а папку убрали бы вместе
      // с ним: упаковка такую папку не берёт.
      await expectLater(
        packRecording(folder, now: () => packedAt),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
      expect(await Link(p.join(folder.path, 'input.jsonl')).exists(), isTrue);
      expect(await outside.readAsString(), 'не запись');
    });

    test('SNO-ALG-REC-03: манифест проходит схему', () async {
      final Map<String, Object?> schema = jsonDecode(
        await File('tool/sno_manifest.schema.json').readAsString(),
      ) as Map<String, Object?>;

      // Обычная запись, оборванная и запись без сведений.
      final List<Directory> folders = <Directory>[
        await make(usual(), about: info()),
        await make(
          usual(),
          folder: '$name-crash',
          about: info(id: '01KB5Z3M4N7Q8R9S0T1V2W3X4Z', stoppedBy: 'crash'),
        ),
        await make(usual(), folder: '$name-bare'),
      ];
      for (final Directory folder in folders) {
        final Map<String, Object?> manifest = manifestOf(
          await entriesOf(await packRecording(folder, now: () => packedAt)),
        );
        expect(
          schemaProblems(manifest, schema),
          isEmpty,
          reason: p.basename(folder.path),
        );
      }
    });

    test('SNO-ALG-REC-03: схема ловит манифест без сумм', () async {
      final Map<String, Object?> schema = jsonDecode(
        await File('tool/sno_manifest.schema.json').readAsString(),
      ) as Map<String, Object?>;
      final Map<String, Object?> manifest = buildManifest(
        info: info(),
        archiveName: '$name.zip',
        packedAt: packedAt,
        files: const <PackedFile>[
          PackedFile(name: kEventsFile, bytes: 10, sha256: 'не сумма'),
        ],
      );

      expect(schemaProblems(manifest, schema), hasLength(1));
    });

    test('SNO-F-REC-05: чужая реализация открывает архив, суммы манифеста '
        'сходятся', () async {
      final Directory folder = await make(usual(), about: info());
      final File archive = await packRecording(folder, now: () => packedAt);

      final OtherZip? other = await readWithPython(archive);
      if (other == null) {
        // Python нет только на машине разработчика: в CI он есть.
        return;
      }
      expect(other.problem, isNull);
      expect(other.names.first, kManifestFile);
      final Map<String, Object?> manifest = manifestOf(
        await entriesOf(archive),
      );
      final Map<String, Object?> files =
          manifest['files']! as Map<String, Object?>;
      expect(other.names.skip(1), unorderedEquals(files.keys));
      for (final String file in files.keys) {
        final Map<String, Object?> about = fileOf(manifest, file);
        expect(other.sha256[file], about['sha256'], reason: file);
        expect(other.sizes[file], about['bytes'], reason: file);
      }
    });

    test('SNO-F-REC-05: восемь тысяч событий — архив меньше журнала', () async {
      final String long = journal(8000);
      final Directory folder = await make(<String, String>{
        kEventsFile: long,
      }, about: info());

      final File archive = await packRecording(folder, now: () => packedAt);

      expect(await archive.length(), lessThan(utf8.encode(long).length ~/ 4));
      final Map<String, Uint8List> entries = await entriesOf(archive);
      expect(utf8.decode(entries[kEventsFile]!), long);
      expect(fileOf(manifestOf(entries), kEventsFile)['lines'], 8000);
    });
  });

  group('SNO-ALG-REC-03: имя архива', () {
    test('SNO-ALG-REC-03: имя занято архивом другой записи — хвост', () async {
      final File first = await packRecording(
        await make(usual(), about: info()),
        now: () => packedAt,
      );
      // Вторая запись того же участника в ту же минуту: имя папки то же.
      final File second = await packRecording(
        await make(<String, String>{
          kEventsFile: journal(2),
        }, about: info(id: '01KB5Z3M4N7Q8R9S0T1V2W3X5A')),
        now: () => packedAt,
      );

      expect(p.basename(first.path), '$name.zip');
      expect(p.basename(second.path), '$name-2.zip');
      expect(await listing(), <String>['$name-2.zip', '$name.zip']);
      // Имя в манифесте — то, под которым архив лежит.
      expect(
        (manifestOf(await entriesOf(second))['archive']!
            as Map<String, Object?>)['name'],
        '$name-2.zip',
      );
      expect(
        fileOf(manifestOf(await entriesOf(first)), kEventsFile)['lines'],
        5,
      );
    });

    test('SNO-ALG-REC-03: архив этой же записи уже лежит — папка убирается '
        'без второй упаковки', () async {
      final Map<String, String> files = usual();
      final File first = await packRecording(
        await make(files, about: info()),
        now: () => packedAt,
      );
      final List<int> before = await first.readAsBytes();
      // Приложение закрыли между архивом и уборкой папки: при следующем
      // запуске папка на месте.
      final Directory again = await make(files, about: info());

      final File second = await packRecording(
        again,
        now: () => packedAt.add(const Duration(hours: 1)),
      );

      expect(second.path, first.path);
      expect(await second.readAsBytes(), before);
      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-ALG-REC-03: та же запись без сведений узнаётся по сумме '
        'журнала', () async {
      final Map<String, String> files = usual();
      await packRecording(await make(files), now: () => packedAt);
      final Directory again = await make(files);

      await packRecording(again, now: () => packedAt);

      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-ALG-REC-03: уборку папки оборвали после файла сведений — '
        'остаток убирается, второго архива нет', () async {
      final Map<String, String> files = usual();
      final File first = await packRecording(
        await make(files, about: info()),
        now: () => packedAt,
      );
      final List<int> before = await first.readAsBytes();
      // От папки остались два файла из трёх и ни слова о записи: всё
      // это уже лежит в архиве, и сверять сведения не с чем.
      final Directory rest = await make(<String, String>{
        kEventsFile: files[kEventsFile]!,
        kSnapshotEndFile: files[kSnapshotEndFile]!,
      });

      final File second = await packRecording(rest, now: () => packedAt);

      expect(second.path, first.path);
      expect(await second.readAsBytes(), before);
      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-ALG-REC-03: остаток с файлом, которого в архиве нет, — не '
        'остаток: он упаковывается', () async {
      final Map<String, String> files = usual();
      await packRecording(
        await make(files, about: info()),
        now: () => packedAt,
      );
      final Directory other = await make(<String, String>{
        kEventsFile: journal(7),
      });

      final File second = await packRecording(other, now: () => packedAt);

      expect(p.basename(second.path), '$name-2.zip');
      expect(await listing(), <String>['$name-2.zip', '$name.zip']);
    });
  });

  group('SNO-F-REC-05: архив уже лежит, а папка — другая', () {
    test('SNO-F-REC-05: в папке появился файл, которого нет в архиве, — '
        'она упаковывается заново, а не убирается', () async {
      final Map<String, String> files = usual();
      await packRecording(
        await make(files, about: info()),
        now: () => packedAt,
      );
      // После первой упаковки в папку той же записи дописали снимок:
      // приложение закрыли до уборки, а следующий запуск закрывал
      // сессию ещё раз.
      final Directory again = await make(<String, String>{
        ...files,
        kSnapshotEndFile: '{"schema": "sno2026-snapshot/1", "late": true}',
      }, about: info());

      final File second = await packRecording(again, now: () => packedAt);

      expect(p.basename(second.path), '$name-2.zip');
      expect(await listing(), <String>['$name-2.zip', '$name.zip']);
      expect(
        utf8.decode((await entriesOf(second))[kSnapshotEndFile]!),
        '{"schema": "sno2026-snapshot/1", "late": true}',
      );
    });

    test('SNO-F-REC-05: сведения о записи в папке новее, чем в архиве, — '
        'папка упаковывается заново', () async {
      final Map<String, String> files = usual();
      await packRecording(
        await make(files, about: info()),
        now: () => packedAt,
      );
      final Map<String, Object?> newer = info();
      (newer['recording']! as Map<String, Object?>)['events'] = 6;
      final Directory again = await make(files, about: newer);

      final File second = await packRecording(again, now: () => packedAt);

      expect(p.basename(second.path), '$name-2.zip');
      expect(
        (manifestOf(await entriesOf(second))['recording']!
            as Map<String, Object?>)['events'],
        6,
      );
    });

    test('SNO-F-REC-05: архив без сведений не даёт убрать папку, в которой '
        'сведения есть', () async {
      final Map<String, String> files = usual();
      // Первый раз сведения о записи не прочитались.
      await packRecording(await make(files), now: () => packedAt);
      final Directory again = await make(files, about: info());

      final File second = await packRecording(again, now: () => packedAt);

      expect(p.basename(second.path), '$name-2.zip');
      expect(manifestOf(await entriesOf(second))['branch'], 'I');
    });
  });

  group('SNO-F-REC-05: запись не теряется при упаковке', () {
    test('SNO-F-REC-05: архив не сошёлся с записью — папка цела, обрывка '
        'нет', () async {
      final Map<String, String> files = usual();
      final Directory folder = await make(files, about: info());

      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          // Диск испортил архив до сверки: вторая половина пропала.
          beforeVerify: (File part) async {
            final List<int> bytes = await part.readAsBytes();
            await part.writeAsBytes(
              bytes.sublist(0, bytes.length ~/ 2),
              flush: true,
            );
          },
        ),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
      for (final MapEntry<String, String> file in files.entries) {
        expect(
          await File(p.join(folder.path, file.key)).readAsString(),
          file.value,
          reason: file.key,
        );
      }
      expect(await File(p.join(folder.path, kRecordingFile)).exists(), isTrue);
    });

    test('SNO-F-REC-05: в архиве подменён один байт журнала — сверка '
        'ловит', () async {
      final Directory folder = await make(usual(), about: info());

      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          beforeVerify: (File part) async {
            final Uint8List bytes = await part.readAsBytes();
            // Первый байт сжатого журнала: он стоит сразу за именем в
            // заголовке записи, а имя открытым текстом встречается в
            // архиве впервые именно там.
            final List<int> entry = utf8.encode(kEventsFile);
            int at = -1;
            for (int i = 0; at < 0 && i + entry.length < bytes.length; i++) {
              bool same = true;
              for (int j = 0; same && j < entry.length; j++) {
                same = bytes[i + j] == entry[j];
              }
              if (same) {
                at = i + entry.length;
              }
            }
            expect(at, greaterThan(0));
            bytes[at] ^= 0xFF;
            await part.writeAsBytes(bytes, flush: true);
          },
        ),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
    });

    test('SNO-F-REC-05: после неудачи упаковка повторяется и '
        'удаётся', () async {
      final Directory folder = await make(usual(), about: info());
      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          beforeVerify: (File part) => part.writeAsString('мусор'),
        ),
        throwsA(isA<PackException>()),
      );

      final File archive = await packRecording(folder, now: () => packedAt);

      expect(await listing(), <String>['$name.zip']);
      expect(
        fileOf(manifestOf(await entriesOf(archive)), kEventsFile)['lines'],
        5,
      );
    });

    test('SNO-F-REC-05: приложение закрыли между архивом и уборкой папки — '
        'следующая упаковка убирает папку', () async {
      final Directory folder = await make(usual(), about: info());
      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          beforeCleanup: (File archive) async => throw StateError('закрыли'),
        ),
        throwsStateError,
      );
      // Архив уже на месте, папка ещё тоже.
      expect(await listing(), <String>[name, '$name.zip']);

      final File archive = await packRecording(folder, now: () => packedAt);

      expect(p.basename(archive.path), '$name.zip');
      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-F-REC-05: обрывок прежней упаковки не мешает новой', () async {
      final Directory folder = await make(usual(), about: info());
      await File(p.join(records.path, '$name.zip$kPartSuffix'))
          .writeAsString('обрывок');

      await packRecording(folder, now: () => packedAt);

      expect(await listing(), <String>['$name.zip']);
    });

    test('SNO-F-REC-05: папка изменилась, пока её упаковывали, — она '
        'остаётся, архива нет', () async {
      final Directory folder = await make(usual(), about: info());

      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          // Пока архив писался, в журнал дописали строку.
          beforeVerify: (File part) => File(p.join(folder.path, kEventsFile))
              .writeAsString('{"seq":6}\n', mode: FileMode.append, flush: true),
        ),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
      expect(
        await File(p.join(folder.path, kEventsFile)).readAsString(),
        endsWith('{"seq":6}\n'),
      );

      // Вторая попытка берёт папку какой она стала.
      final File archive = await packRecording(folder, now: () => packedAt);
      expect(
        fileOf(manifestOf(await entriesOf(archive)), kEventsFile)['lines'],
        6,
      );
    });

    test('SNO-F-REC-05: в папке появился новый файл, пока её упаковывали, '
        '— она остаётся', () async {
      final Directory folder = await make(usual(), about: info());

      await expectLater(
        packRecording(
          folder,
          now: () => packedAt,
          beforeVerify: (File part) =>
              File(p.join(folder.path, 'input.jsonl'))
                  .writeAsString('{"seq":1}\n', flush: true),
        ),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
    });

    test('SNO-F-REC-05: упакованная папка убирается целиком, скрытых '
        'остатков нет', () async {
      final Directory folder = await make(usual(), about: info());

      await packRecording(folder, now: () => packedAt);

      expect(await listing(), <String>['$name.zip']);
      expect(await folder.exists(), isFalse);
    });

    test('SNO-ALG-REC-03: в папке нет файлов — отказ, а не пустой '
        'архив', () async {
      final Directory folder = await make(<String, String>{});

      await expectLater(
        packRecording(folder, now: () => packedAt),
        throwsA(isA<PackException>()),
      );

      expect(await listing(), <String>[name]);
    });
  });

  group('SNO-F-REC-07: сверка архива на диске', () {
    test('SNO-F-REC-07: целый архив — манифест и суммы сходятся', () async {
      final File archive = await packRecording(
        await make(usual(), about: info()),
        now: () => packedAt,
      );

      final ArchiveCheck check = await checkArchive(archive);

      expect(check.intact, isTrue);
      expect(recordingIdOf(check.manifest), '01KB5Z3M4N7Q8R9S0T1V2W3X4Y');
    });

    test('SNO-F-REC-07: не архив — манифеста нет', () async {
      final File archive = File(p.join(records.path, '$name.zip'));
      await archive.writeAsString('это не архив');

      final ArchiveCheck check = await checkArchive(archive);

      expect(check.manifest, isNull);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-07: архива нет — ответ, а не ошибка', () async {
      final ArchiveCheck check = await checkArchive(
        File(p.join(records.path, 'нет такого.zip')),
      );

      expect(check.manifest, isNull);
      expect(check.intact, isFalse);
    });

    test('SNO-F-REC-07: сумма не сходится — манифест читается, архив '
        'помечен', () async {
      final File archive = File(p.join(records.path, '$name.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      await writer.addBytes(
        kManifestFile,
        utf8.encode(
          jsonEncode(
            buildManifest(
              info: info(),
              archiveName: '$name.zip',
              packedAt: packedAt,
              files: <PackedFile>[
                PackedFile(
                  name: kEventsFile,
                  bytes: 3,
                  sha256: '${sha256.convert(utf8.encode('другое'))}',
                  lines: 1,
                ),
              ],
            ),
          ),
        ),
      );
      await writer.addBytes(kEventsFile, utf8.encode('{}\n'));
      await writer.finish();

      final ArchiveCheck check = await checkArchive(archive);

      expect(check.intact, isFalse);
      expect(recordingIdOf(check.manifest), '01KB5Z3M4N7Q8R9S0T1V2W3X4Y');
    });

    test('SNO-F-REC-07: файла из перечня в архиве нет — архив '
        'помечен', () async {
      final File archive = File(p.join(records.path, '$name.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      await writer.addBytes(
        kManifestFile,
        utf8.encode(
          jsonEncode(
            buildManifest(
              info: info(),
              archiveName: '$name.zip',
              packedAt: packedAt,
              files: <PackedFile>[
                PackedFile(
                  name: kEventsFile,
                  bytes: 3,
                  sha256: '${sha256.convert(utf8.encode('{}\n'))}',
                ),
              ],
            ),
          ),
        ),
      );
      await writer.finish();

      expect((await checkArchive(archive)).intact, isFalse);
    });

    test('SNO-F-REC-07: заголовок записи расходится с оглавлением — архив '
        'помечен', () async {
      final File archive = await packRecording(
        await make(usual(), about: info()),
        now: () => packedAt,
      );
      // Сумма в заголовке записи журнала: её читают «Проводник» и
      // 7-Zip, а свой читатель и Python берут сумму из оглавления и
      // подмены не заметили бы.
      final Uint8List bytes = await archive.readAsBytes();
      final List<int> entry = utf8.encode(kEventsFile);
      int at = -1;
      for (int i = 0; at < 0 && i + entry.length < bytes.length; i++) {
        bool same = true;
        for (int j = 0; same && j < entry.length; j++) {
          same = bytes[i + j] == entry[j];
        }
        if (same) {
          at = i;
        }
      }
      expect(at, greaterThan(30));
      // Заголовок — тридцать байт перед именем; сумма — с четырнадцатого.
      bytes[at - 30 + 14] ^= 0xFF;
      await archive.writeAsBytes(bytes, flush: true);

      final ArchiveCheck check = await checkArchive(archive);

      expect(check.intact, isFalse);
      expect(check.manifest, isNotNull);
    });

    test('SNO-F-REC-07: архив с пустым перечнем файлов целым не '
        'считается', () async {
      final File archive = File(p.join(records.path, '$name.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      await writer.addBytes(
        kManifestFile,
        utf8.encode(
          jsonEncode(
            buildManifest(
              info: info(),
              archiveName: '$name.zip',
              packedAt: packedAt,
              files: const <PackedFile>[],
            ),
          ),
        ),
      );
      await writer.finish();

      expect((await checkArchive(archive)).intact, isFalse);
    });

    test('SNO-F-REC-07: архив без манифеста — повреждён', () async {
      final File archive = File(p.join(records.path, '$name.zip'));
      final ZipWriter writer = await ZipWriter.create(archive);
      await writer.addBytes(kEventsFile, utf8.encode('{}\n'));
      await writer.finish();

      final ArchiveCheck check = await checkArchive(archive);

      expect(check.manifest, isNull);
      expect(check.intact, isFalse);
    });
  });
}
