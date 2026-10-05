import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/infrastructure/files/file_book_handle.dart';
import 'package:memoria/infrastructure/files/zip_reader.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/file_records.dart';
import 'package:memoria/sno/recording/file_store.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

import '../support/recording_fakes.dart';
import '../support/recording_folders.dart';

/// SNO-F-REC-07, SNO-F-REC-06, SNO-F-REC-05, SNO-F-REC-08: записи на
/// настоящем диске.
///
/// Папка `Записи/` — временная. Список читается из неё самой; отправка
/// и «Проводник» подменены (`FakeRecordOutlet`): до системного окна
/// тест не доходит, зато всё, что решает приложение, — что отдать, что
/// пометить, когда удалить, — проверяется целиком.
void main() {
  late Directory temp;
  late Directory folder;
  late FakeRecordOutlet outlet;
  late DateTime now;

  const String first = 'sno2026_I_67954332_a91f3c_20261103-1402';
  const String second = 'sno2026_I_94532726_a91f3c_20261104-0915';
  const String firstId = '01KB5Z3M4N7Q8R9S0T1V2W3X4Y';
  const String secondId = '01KB8A3M4N7Q8R9S0T1V2W3X4Y';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-device-records-');
    folder = Directory(p.join(temp.path, FileRecordingStore.folderName));
    await folder.create(recursive: true);
    outlet = FakeRecordOutlet(shares: true);
    now = DateTime(2026, 11, 4, 10, 30);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  FileDeviceRecords open({String? Function()? active}) {
    final FileDeviceRecords records = FileDeviceRecords(
      root: () async => folder,
      outlet: outlet,
      activeFolder: active,
      now: () => now,
    );
    addTearDown(records.dispose);
    return records;
  }

  /// Кладёт в папку записей готовый архив записи [name].
  Future<File> archiveOf(
    String name, {
    required String id,
    String anchor = '2026-11-03T14:02:11.482+03:00',
    String stoppedBy = 'experimenter',
    int durationMs = 480000,
    int events = 5,
  }) async {
    return packRecording(
      await makeRecordingFolder(
        folder,
        name,
        events: events,
        about: recordingInfo(
          id: id,
          anchor: anchor,
          stoppedBy: stoppedBy,
          durationMs: durationMs,
          events: events,
        ),
      ),
      now: () => now,
    );
  }

  Future<void> both() async {
    await archiveOf(first, id: firstId);
    await archiveOf(
      second,
      id: secondId,
      anchor: '2026-11-04T09:15:40.120+03:00',
      stoppedBy: 'crash',
      durationMs: 1062000,
    );
  }

  /// Что лежит в папке записей, по именам.
  Future<List<String>> listing([Directory? where]) async {
    final List<String> names = <String>[
      await for (final FileSystemEntity entity in (where ?? folder).list())
        p.basename(entity.path),
    ];
    return names..sort();
  }

  /// Имена записей в порядке списка.
  List<String> namesOf(FileDeviceRecords records) {
    return <String>[
      for (final DeviceRecord record in records.entries) record.name,
    ];
  }

  Map<String, Object?> stateOnDisk() {
    return jsonDecode(
      File(p.join(folder.path, FileDeviceRecords.stateName)).readAsStringSync(),
    ) as Map<String, Object?>;
  }

  group('SNO-F-REC-07: список читается из папки записей', () {
    test('SNO-F-REC-07: записей нет — список пуст и прочитан', () async {
      final FileDeviceRecords records = open();
      expect(records.loaded, isFalse);

      await records.refresh();

      expect(records.loaded, isTrue);
      expect(records.entries, isEmpty);
    });

    test('SNO-F-REC-07: архивы стоят от новых к старым, сведения — из '
        'манифеста', () async {
      await both();
      final FileDeviceRecords records = open();

      await records.refresh();

      expect(namesOf(records), <String>[second, first]);
      final DeviceRecord newer = records.entries.first;
      expect(newer.packed, isTrue);
      expect(newer.damaged, isFalse);
      expect(newer.branch, 'I');
      expect(newer.participant, '67954332');
      expect(newer.durationMs, 1062000);
      expect(newer.events, 5);
      expect(newer.interrupted, isTrue);
      expect(newer.taken, isFalse);
      expect(
        newer.bytes,
        await File(p.join(folder.path, '$second.zip')).length(),
      );
      expect(
        newer.startedAt!.isAtSameMomentAs(
          DateTime.parse('2026-11-04T09:15:40.120+03:00'),
        ),
        isTrue,
      );
      expect(records.entries.last.interrupted, isFalse);
    });

    test('SNO-F-REC-07: слушатели узнают о перечитанном списке', () async {
      await both();
      final FileDeviceRecords records = open();
      int told = 0;
      records.addListener(() => told++);

      await records.refresh();

      expect(told, 1);
    });

    test('SNO-F-REC-07: архив убрали руками — из списка он пропал, положили '
        '— появился', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      final File moved = File(p.join(folder.path, '$first.zip'));
      final File aside = await moved.rename(p.join(temp.path, 'aside.zip'));

      await records.refresh();
      expect(namesOf(records), <String>[second]);

      await aside.rename(moved.path);
      await records.refresh();
      expect(records.entries, hasLength(2));
    });

    test('SNO-F-REC-07: файл с именем архива, который не архив, помечен и '
        'остаётся в списке', () async {
      await File(p.join(folder.path, '$first.zip')).writeAsString('не архив');
      final FileDeviceRecords records = open();

      await records.refresh();

      final DeviceRecord record = records.entries.single;
      expect(record.name, first);
      expect(record.packed, isTrue);
      expect(record.damaged, isTrue);
      expect(record.durationMs, isNull);
      // Отправить его всё равно можно: разбор решит, что с ним делать.
      expect(await records.share(<DeviceRecord>[record]), 1);
      expect(outlet.shared.single, <String>[p.join(folder.path, '$first.zip')]);
    });

    test('SNO-F-REC-07: папка записи — «не упакована», со сведениями из '
        'recording.json', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId, durationMs: 61000),
      );
      final FileDeviceRecords records = open();

      await records.refresh();

      final DeviceRecord record = records.entries.single;
      expect(record.packed, isFalse);
      expect(record.damaged, isFalse);
      expect(record.durationMs, 61000);
      expect(record.bytes, greaterThan(0));
      // Папку окну «Поделиться» не отдать.
      expect(await records.share(<DeviceRecord>[record]), 0);
      expect(outlet.shared, isEmpty);
    });

    test('SNO-F-REC-07: служебное в список не попадает', () async {
      await both();
      await makeRecordingFolder(
        Directory(p.join(folder.path, FileRecordingStore.currentName)),
        'sno2026_I_11111111_a91f3c_20261104-1000',
      );
      await File(p.join(folder.path, FileDeviceRecords.stateName))
          .writeAsString('{}');
      await File(p.join(folder.path, 'заметка.txt')).writeAsString('чужое');
      final FileDeviceRecords records = open();

      await records.refresh();

      expect(records.entries, hasLength(2));
    });
  });

  group('SNO-F-REC-05: упаковка при запуске', () {
    test('SNO-F-REC-05: папки записей прежних сборок становятся '
        'архивами', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      await makeRecordingFolder(
        folder,
        second,
        about: recordingInfo(
          id: secondId,
          anchor: '2026-11-04T09:15:40.120+03:00',
        ),
      );
      final FileDeviceRecords records = open();

      await records.packPending();

      expect(await listing(), <String>['$first.zip', '$second.zip']);
      expect(records.entries, hasLength(2));
      expect(
        records.entries.every((DeviceRecord record) => record.packed),
        isTrue,
      );
    });

    test('SNO-ALG-REC-03: обрывок архива и пустая папка убираются', () async {
      await both();
      await File(p.join(folder.path, '$first-2.zip$kPartSuffix'))
          .writeAsString('обрывок');
      final Directory empty = Directory(p.join(folder.path, 'пустая'));
      await empty.create();
      await File(p.join(empty.path, kEventsFile)).writeAsString('');
      final FileDeviceRecords records = open();

      await records.packPending();

      expect(await listing(), <String>['$first.zip', '$second.zip']);
    });

    test('SNO-ALG-REC-03: запись, которая не упаковалась, остаётся папкой и '
        'видна в списке', () async {
      // В папке нет ни одного потока — только сведения: упаковывать
      // нечего, но и выбрасывать запись приложение не вправе.
      final Directory bare = Directory(p.join(folder.path, first));
      await bare.create();
      await File(p.join(bare.path, kRecordingFile))
          .writeAsString(jsonEncode(recordingInfo(id: firstId)));
      final FileDeviceRecords records = open();

      await records.packPending();

      expect(await listing(), <String>[first]);
      expect(records.entries.single.packed, isFalse);
    });

    test('SNO-F-REC-08: папка без сессии среди незавершённых подбирается и '
        'упаковывается', () async {
      final Directory current = Directory(
        p.join(folder.path, FileRecordingStore.currentName),
      );
      await makeRecordingFolder(
        current,
        first,
        about: recordingInfo(id: firstId),
      );
      // Запись, которая так и не началась: пустой журнал.
      final Directory unborn = Directory(p.join(current.path, 'не началась'));
      await unborn.create(recursive: true);
      await File(p.join(unborn.path, kEventsFile)).writeAsString('');
      // Папка идущей сессии: её трогать нельзя.
      await makeRecordingFolder(
        current,
        second,
        about: recordingInfo(id: secondId),
      );
      final FileDeviceRecords records = open(active: () => second);

      await records.adoptOrphans();

      expect(await listing(current), <String>[second]);
      expect(await listing(), <String>[FileRecordingStore.currentName, first]);

      await records.packPending();

      expect(await listing(), <String>[
        FileRecordingStore.currentName,
        '$first.zip',
      ]);
      expect(await listing(current), <String>[second]);
      expect(records.entries.single.name, first);
    });

    test('SNO-F-REC-08: подобранная папка не затирает завершённую с тем же '
        'именем', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      await makeRecordingFolder(
        Directory(p.join(folder.path, FileRecordingStore.currentName)),
        first,
        events: 2,
        about: recordingInfo(id: secondId),
      );
      final FileDeviceRecords records = open();

      await records.adoptOrphans();
      await records.packPending();

      expect(await listing(), <String>[
        FileRecordingStore.currentName,
        '$first-2.zip',
        '$first.zip',
      ]);
    });
  });

  group('SNO-F-REC-05: упаковка завершённой записи', () {
    test('SNO-F-REC-05: папка завершённой записи становится строкой '
        'списка', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      final FileDeviceRecords records = open();

      final DeviceRecord? record = await records.pack(first);

      expect(record, isNotNull);
      expect(record!.name, first);
      expect(record.packed, isTrue);
      expect(record.durationMs, 480000);
      expect(await listing(), <String>['$first.zip']);
      expect(records.entries.single.name, first);
    });

    test('SNO-F-REC-05: завершение не сумело перенести папку — упаковка '
        'переносит её сама', () async {
      await makeRecordingFolder(
        Directory(p.join(folder.path, FileRecordingStore.currentName)),
        first,
        about: recordingInfo(id: firstId),
      );
      final FileDeviceRecords records = open();

      final DeviceRecord? record = await records.pack(first);

      expect(record?.packed, isTrue);
      expect(await listing(), <String>[
        FileRecordingStore.currentName,
        '$first.zip',
      ]);
    });

    test('SNO-F-REC-05: папку идущей сессии упаковка не трогает', () async {
      final Directory current = Directory(
        p.join(folder.path, FileRecordingStore.currentName),
      );
      await makeRecordingFolder(
        current,
        first,
        about: recordingInfo(id: firstId),
      );
      final FileDeviceRecords records = open(active: () => first);

      expect(await records.pack(first), isNull);

      expect(await listing(current), <String>[first]);
      expect(await listing(), <String>[FileRecordingStore.currentName]);
    });

    test('SNO-F-REC-05: упаковка при запуске и упаковка завершённой записи '
        'на одной папке не встречаются', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      final FileDeviceRecords records = open();

      final Future<void> pending = records.packPending();
      final Future<DeviceRecord?> packed = records.pack(first);
      await pending;

      expect((await packed)?.packed, isTrue);
      expect(await listing(), <String>['$first.zip']);
    });

    test('SNO-F-REC-05: записи с таким именем нет — ответа нет', () async {
      final FileDeviceRecords records = open();

      expect(await records.pack(first), isNull);
    });
  });

  group('SNO-F-REC-08: папку незавершённой сессии не трогают', () {
    // Завершение сессии перенесло папку к остальным, а отметку о
    // сессии снять не успело: после перезапуска сессия поднимется на
    // этой папке, и завершат её ещё раз.
    test('SNO-F-REC-08: папки незавершённой сессии нет ни в списке, ни в '
        'упаковке, ни в удалении', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      await makeRecordingFolder(
        folder,
        second,
        about: recordingInfo(id: secondId),
      );
      String? active = first;
      final FileDeviceRecords records = open(active: () => active);

      await records.packPending();

      // Упакована только чужая папка; папка сессии цела и не в списке.
      expect(await listing(), <String>[first, '$second.zip']);
      expect(namesOf(records), <String>[second]);
      expect(await records.pack(first), isNull);
      expect(
        await records.delete(
          const DeviceRecord(name: first, bytes: 1, packed: false),
        ),
        isFalse,
      );
      expect(await listing(), <String>[first, '$second.zip']);

      // Сессию завершили — запись упаковывается как обычная.
      active = null;
      expect((await records.pack(first))?.packed, isTrue);
      expect(await listing(), <String>['$first.zip', '$second.zip']);
    });

    test('SNO-F-REC-05: имя папки — одно слово: пустое и с разделителем '
        'упаковка не принимает', () async {
      await both();
      await makeRecordingFolder(
        folder,
        'sno2026_I_11111111_a91f3c_20261104-1000',
        about: recordingInfo(id: '01KB9A3M4N7Q8R9S0T1V2W3X4Y'),
      );
      final FileDeviceRecords records = open();
      final List<String> before = await listing();

      expect(await records.pack(''), isNull);
      expect(await records.pack('.current'), isNull);
      expect(await records.pack('../$first'), isNull);
      expect(await records.pack(r'..\..'), isNull);

      expect(await listing(), before);
    });

    test('SNO-ALG-REC-03: папка упакованной записи, которую не успели '
        'убрать, убирается при запуске', () async {
      await archiveOf(first, id: firstId);
      await makeRecordingFolder(folder, '$kGonePrefix$first');
      final FileDeviceRecords records = open();

      await records.packPending();

      expect(await listing(), <String>['$first.zip']);
      expect(namesOf(records), <String>[first]);
    });

    test('SNO-F-REC-07: архив и папка с одним именем — две разные '
        'строки, отметка — только у архива', () async {
      await archiveOf(first, id: firstId);
      // Папка другой записи с тем же именем: упаковка ещё не дошла.
      await makeRecordingFolder(
        folder,
        first,
        events: 2,
        about: recordingInfo(id: secondId),
      );
      final FileDeviceRecords records = open();
      await records.refresh();
      final DeviceRecord archive = records.entries.firstWhere(
        (DeviceRecord record) => record.packed,
      );

      expect(await records.share(<DeviceRecord>[archive]), 1);

      expect(records.entries, hasLength(2));
      expect(
        <String>{
          for (final DeviceRecord record in records.entries) record.rowId,
        },
        <String>{first, '$first/'},
      );
      for (final DeviceRecord record in records.entries) {
        expect(record.taken, record.packed, reason: record.rowId);
      }
    });
  });

  group('SNO-F-REC-06: поделиться', () {
    test('SNO-F-REC-06: архив уходит окну «Поделиться» и помечен '
        'отправленным', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      final DeviceRecord record = records.entries.last;

      expect(await records.share(<DeviceRecord>[record]), 1);

      expect(outlet.shared.single, <String>[p.join(folder.path, '$first.zip')]);
      final DeviceRecord marked = records.entries.last;
      expect(marked.name, first);
      expect(marked.sharedAt, now);
      expect(marked.taken, isTrue);
      expect(records.entries.first.taken, isFalse);
    });

    test('SNO-F-REC-06: отметка переживает перезапуск приложения', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.share(<DeviceRecord>[records.entries.last]);

      final FileDeviceRecords again = open();
      await again.refresh();

      expect(again.entries.last.sharedAt, now);
      expect(again.entries.first.sharedAt, isNull);
      final Map<String, Object?> state = stateOnDisk();
      expect(state['schema'], FileDeviceRecords.stateSchema);
      expect((state['records']! as Map<String, Object?>).keys, <String>[first]);
    });

    test('SNO-F-REC-06: окно не открылось — запись не помечена', () async {
      await both();
      outlet.opens = false;
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.share(records.entries), 0);

      expect(records.entries.any((DeviceRecord r) => r.taken), isFalse);
      expect(
        await File(p.join(folder.path, FileDeviceRecords.stateName)).exists(),
        isFalse,
      );
    });

    test('SNO-F-REC-06: все неотправленные уходят одним окном', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.share(unshared(records.entries)), 2);

      expect(outlet.shared, hasLength(1));
      expect(outlet.shared.single, <String>[
        p.join(folder.path, '$second.zip'),
        p.join(folder.path, '$first.zip'),
      ]);
      expect(unshared(records.entries), isEmpty);
    });

    test('SNO-ALG-REC-04: архив убрали с диска, пока список был на экране, '
        '— окно не открывается, список перечитан', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();
      final DeviceRecord record = records.entries.single;
      await File(p.join(folder.path, '$first.zip')).delete();

      expect(await records.share(<DeviceRecord>[record]), 0);

      expect(outlet.shared, isEmpty);
      expect(records.entries, isEmpty);
    });

    test('SNO-F-REC-06: файл отметок потерялся — записи снова не '
        'отправлены', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.share(records.entries);
      await File(p.join(folder.path, FileDeviceRecords.stateName)).delete();

      final FileDeviceRecords again = open();
      await again.refresh();

      expect(untaken(again.entries), hasLength(2));
    });

    test('SNO-F-REC-06: файл отметок не читается — записи не отправлены, '
        'список цел', () async {
      await both();
      await File(p.join(folder.path, FileDeviceRecords.stateName))
          .writeAsString('{"records": [');
      final FileDeviceRecords records = open();

      await records.refresh();

      expect(untaken(records.entries), hasLength(2));
    });
  });

  group('SNO-F-REC-06: сохранить копию на ПК', () {
    late Directory target;

    setUp(() async {
      outlet = FakeRecordOutlet(saves: true);
      target = Directory(p.join(temp.path, 'флешка'));
      await target.create();
      outlet.folder = target.path;
    });

    test('SNO-F-REC-06: копия ложится в выбранную папку и сходится с '
        'архивом', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.saveCopy(records.entries.single), CopyOutcome.done);

      expect(await listing(target), <String>['$first.zip']);
      expect(
        await File(p.join(target.path, '$first.zip')).readAsBytes(),
        await File(p.join(folder.path, '$first.zip')).readAsBytes(),
      );
      final DeviceRecord marked = records.entries.single;
      expect(marked.copiedAt, now);
      expect(marked.sharedAt, isNull);
      expect(marked.taken, isTrue);
      // Архив на устройстве остаётся.
      expect(await listing(), contains('$first.zip'));
    });

    test('SNO-F-REC-06: папка запоминается и предлагается в следующий '
        'раз', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.saveCopy(records.entries.first);

      final FileDeviceRecords again = open();
      await again.refresh();
      await again.saveCopy(again.entries.last);

      // Первый раз начинать не с чего; второй — с прошлой папки, и
      // после перезапуска приложения тоже.
      expect(outlet.initials, <String?>[null, target.path]);
      expect(await listing(target), <String>['$first.zip', '$second.zip']);
    });

    test('SNO-F-REC-06: запомненной папки больше нет — диалог начинает с '
        'чистого листа', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.saveCopy(records.entries.first);
      await target.delete(recursive: true);
      outlet.folder = null;

      expect(
        await records.saveCopy(records.entries.last),
        CopyOutcome.cancelled,
      );

      expect(outlet.initials.last, isNull);
    });

    test('SNO-F-REC-06: папку не выбрали — ничего не случилось', () async {
      await archiveOf(first, id: firstId);
      outlet.folder = null;
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(
        await records.saveCopy(records.entries.single),
        CopyOutcome.cancelled,
      );

      expect(records.entries.single.taken, isFalse);
      expect(await listing(target), isEmpty);
    });

    test('SNO-F-REC-06: папка самих записей копией не считается', () async {
      await archiveOf(first, id: firstId);
      outlet.folder = folder.path;
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(
        await records.saveCopy(records.entries.single),
        CopyOutcome.inside,
      );

      expect(records.entries.single.taken, isFalse);
    });

    test('SNO-F-REC-06: та же копия уже лежит в папке — второй рядом '
        'нет', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.saveCopy(records.entries.single);

      expect(await records.saveCopy(records.entries.single), CopyOutcome.done);

      expect(await listing(target), <String>['$first.zip']);
    });

    test('SNO-F-REC-06: под тем же именем лежит другой файл — он не '
        'затирается', () async {
      await archiveOf(first, id: firstId);
      await File(p.join(target.path, '$first.zip')).writeAsString('чужое');
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.saveCopy(records.entries.single), CopyOutcome.done);

      expect(await listing(target), <String>['$first (2).zip', '$first.zip']);
      expect(
        await File(p.join(target.path, '$first.zip')).readAsString(),
        'чужое',
      );
      expect(
        await File(p.join(target.path, '$first (2).zip')).readAsBytes(),
        await File(p.join(folder.path, '$first.zip')).readAsBytes(),
      );
    });

    test('SNO-F-REC-06: выбранной папки нет — копии нет, запись не '
        'помечена', () async {
      await archiveOf(first, id: firstId);
      outlet.folder = p.join(temp.path, 'нет такой');
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(
        await records.saveCopy(records.entries.single),
        CopyOutcome.failed,
      );

      expect(records.entries.single.taken, isFalse);
    });

    test('SNO-F-REC-06: папка записей под другим именем копией тоже не '
        'считается', () async {
      if (Platform.isWindows) {
        // Ссылку на папку без прав администратора там не завести.
        return;
      }
      await archiveOf(first, id: firstId);
      final Link alias = await Link(
        p.join(temp.path, 'ярлык'),
      ).create(folder.path);
      outlet.folder = alias.path;
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(
        await records.saveCopy(records.entries.single),
        CopyOutcome.inside,
      );

      expect(records.entries.single.taken, isFalse);
      expect(await listing(), <String>['$first.zip']);
    });

    test('SNO-ALG-REC-04: «Открыть папку» — на файле записи или на самой '
        'папке', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.reveal(records.entries.single), isTrue);
      expect(await records.reveal(), isTrue);

      expect(outlet.revealed, <({String path, bool file})>[
        (path: p.join(folder.path, '$first.zip'), file: true),
        (path: folder.path, file: false),
      ]);
    });
  });

  group('SNO-F-REC-07: удаление', () {
    test('SNO-F-REC-07: архив удалён — нет ни файла, ни строки, ни '
        'отметки', () async {
      await both();
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.share(records.entries);

      expect(await records.delete(records.entries.last), isTrue);

      expect(await listing(), <String>[
        FileDeviceRecords.stateName,
        '$second.zip',
      ]);
      expect(records.entries.single.name, second);
      expect((stateOnDisk()['records']! as Map<String, Object?>).keys, <String>[
        second,
      ]);
    });

    test('SNO-F-REC-07: неупакованная запись удаляется папкой', () async {
      await makeRecordingFolder(
        folder,
        first,
        about: recordingInfo(id: firstId),
      );
      final FileDeviceRecords records = open();
      await records.refresh();

      expect(await records.delete(records.entries.single), isTrue);

      expect(await listing(), isEmpty);
      expect(records.entries, isEmpty);
    });
  });

  group('SNO-F-REC-08: запись сессии от старта до архива', () {
    late MemorySettings settings;
    late FakeTime time;
    late FileRecordingStore store;

    setUp(() {
      settings = MemorySettings();
      time = FakeTime(DateTime(2026, 11, 3, 14, 2, 11));
      store = FileRecordingStore(() async => folder);
    });

    RecordingSession session() {
      return RecordingSession(
        settings: settings,
        store: store,
        nodeId: kTestNode,
        snapshot: () async => <String, Object?>{'schema': 'начало'},
        endSnapshot: () async => <String, Object?>{'schema': 'конец'},
        branch: 'I',
        device: 'a91f3c',
        now: time.now,
        monotonic: () =>
            () => time.monotonic,
        ticker: (void Function() onTick) => () {},
      );
    }

    /// Файлы архива: имя → текст.
    Future<Map<String, String>> textsOf(String name) async {
      final FileBookHandle handle = await FileBookHandle.open(
        FilePathSource(p.join(folder.path, '$name.zip')),
      );
      try {
        final ZipArchive zip = await ZipArchive.read(handle);
        final Map<String, String> found = <String, String>{};
        for (final ZipEntry entry in zip.entries) {
          final BytesBuilder bytes = BytesBuilder();
          await zip.extract(entry, (Uint8List chunk) async => bytes.add(chunk));
          found[entry.name] = utf8.decode(bytes.takeBytes());
        }
        return found;
      } finally {
        await handle.close();
      }
    }

    test('SNO-F-REC-05: старт, остановка, завершение — и запись лежит '
        'одним архивом', () async {
      final RecordingSession recording = session();
      final FileDeviceRecords records = open(
        active: () => recording.state?.folder,
      );
      final ParticipantCode code = await recording.proposeCode();
      await recording.start(code);
      final String name = recording.state!.folder;
      for (int i = 0; i < 12; i++) {
        time.pass(const Duration(seconds: 1));
        recording.tick();
      }
      await recording.stop(StopReason.experimenter);
      await recording.finish();

      final DeviceRecord? record = await records.pack(name);

      expect(record, isNotNull);
      expect(record!.packed, isTrue);
      expect(record.interrupted, isFalse);
      expect(record.participant, code.code);
      expect(record.durationMs, 12000);
      expect(await listing(), <String>[
        FileRecordingStore.currentName,
        '$name.zip',
      ]);
      final Map<String, String> texts = await textsOf(name);
      expect(texts.keys.toList(), <String>[
        kManifestFile,
        kEventsFile,
        kSnapshotEndFile,
        kSnapshotStartFile,
      ]);
      // Снимок конца снят в миг остановки, не задним числом.
      expect(jsonDecode(texts[kSnapshotEndFile]!), <String, Object?>{
        'schema': 'конец',
      });
      expect(jsonDecode(texts[kSnapshotStartFile]!), <String, Object?>{
        'schema': 'начало',
      });
      final Map<String, Object?> manifest =
          jsonDecode(texts[kManifestFile]!) as Map<String, Object?>;
      final Map<String, Object?> about =
          manifest['recording']! as Map<String, Object?>;
      expect(about['finished'], isTrue);
      expect(about['stopped_by'], 'experimenter');
      // Событий в журнале архива столько, сколько сказано в манифесте.
      final List<String> lines = const LineSplitter().convert(
        texts[kEventsFile]!,
      );
      expect(lines, hasLength(about['events']! as int));
      expect(
        ((manifest['files']! as Map<String, Object?>)[kEventsFile]!
            as Map<String, Object?>)['lines'],
        lines.length,
      );
      recording.dispose();
    });

    test('SNO-F-REC-08: запись, оборванная после N событий, даёт архив с '
        'этими событиями и меткой «прервана»', () async {
      const int logged = 7;
      final RecordingSession dead = session();
      await dead.start(await dead.proposeCode());
      final String name = dead.state!.folder;
      for (int i = 0; i < logged; i++) {
        time.pass(const Duration(seconds: 1));
        dead.log(
          SnoEventType.pageShown,
          data: <String, Object?>{'page': i + 1},
        );
        dead.tick();
      }
      // Журнал уходит на диск раз в секунду и ответа не ждёт: тест
      // ждёт, пока на диске окажутся старт и все показы страниц.
      final File journalFile = File(
        p.join(folder.path, FileRecordingStore.currentName, name, kEventsFile),
      );
      for (int wait = 0; wait < 500; wait++) {
        if ((await journalFile.readAsLines()).length > logged) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await journalFile.readAsLines(), hasLength(logged + 1));
      // Приложение умерло посреди строки журнала.
      await journalFile.writeAsString(
        '{"seq":99,"t":10',
        mode: FileMode.append,
        flush: true,
      );
      dead.dispose();
      time.pass(const Duration(minutes: 3));

      final RecordingSession recording = session();
      final FileDeviceRecords records = open(
        active: () => recording.state?.folder,
      );
      await recording.restore();
      // Пока сессия не завершена, её папку не подбирают.
      await records.adoptOrphans();
      await records.packPending();
      expect(await listing(), <String>[FileRecordingStore.currentName]);
      expect(recording.state!.stoppedBy, StopReason.crash);
      await recording.finish();

      final DeviceRecord? record = await records.pack(name);

      expect(record, isNotNull);
      expect(record!.packed, isTrue);
      expect(record.interrupted, isTrue);
      expect(record.damaged, isFalse);
      final Map<String, String> texts = await textsOf(name);
      final List<EventMarks> events = readableEvents(
        const LineSplitter().convert(texts[kEventsFile]!),
      );
      // Старт и семь показов страниц — как были, без пропусков; за
      // ними — остановка сбоем и завершение сессии. Обрывка нет.
      expect(
        <int>[for (final EventMarks event in events) event.seq],
        <int>[for (int seq = 1; seq <= logged + 3; seq++) seq],
      );
      expect(
        <String>[
          for (final EventMarks event in events.take(logged + 1)) event.type,
        ],
        <String>[
          'recording.start',
          for (int i = 0; i < logged; i++) 'page.shown',
        ],
      );
      expect(events[logged + 1].type, 'recording.stop');
      expect(events[logged + 1].data['stopped_by'], 'crash');
      expect(events.last.type, 'session.finish');
      expect(texts[kEventsFile], isNot(contains('"seq":99')));
      final Map<String, Object?> manifest =
          jsonDecode(texts[kManifestFile]!) as Map<String, Object?>;
      expect(
        (manifest['recording']! as Map<String, Object?>)['stopped_by'],
        'crash',
      );
      final Map<String, Object?> journal =
          (manifest['files']! as Map<String, Object?>)[kEventsFile]!
              as Map<String, Object?>;
      expect(journal['lines'], logged + 3);
      expect(journal['dropped_lines'], 0);
      // Снимок конца снят при следующем запуске и так и помечен.
      expect(jsonDecode(texts[kSnapshotEndFile]!), <String, Object?>{
        'schema': 'конец',
        'late': true,
      });
      recording.dispose();
    });

    test('SNO-ALG-REC-03: вторая запись того же участника в ту же минуту '
        'получает своё имя и свой архив', () async {
      final RecordingSession recording = session();
      final FileDeviceRecords records = open(
        active: () => recording.state?.folder,
      );
      final ParticipantCode code = await recording.proposeCode();
      await recording.start(code);
      final String one = recording.state!.folder;
      await recording.stop(StopReason.experimenter);
      await recording.finish();
      await records.pack(one);

      // Та же минута, тот же код: папки первой записи уже нет — есть
      // её архив, и имя занято им.
      await recording.start(code);
      final String two = recording.state!.folder;
      await recording.stop(StopReason.experimenter);
      await recording.finish();
      await records.pack(two);

      expect(two, '$one-2');
      expect(await listing(), <String>[
        FileRecordingStore.currentName,
        '$two.zip',
        '$one.zip',
      ]);
      recording.dispose();
    });
  });
}
