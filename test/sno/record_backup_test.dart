import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/file_records.dart';
import 'package:memoria/sno/recording/file_store.dart';
import 'package:memoria/sno/recording/record_outlet.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:path/path.dart' as p;

import '../support/recording_folders.dart';

/// SNO-F-REC-13, SNO-F-REC-14: вторая копия архива и отметка
/// «отправлена» — записи на настоящем диске.
///
/// Папка `Записи/` — временная; общая папка устройства и системное
/// окно подменены (`FakeRecordOutlet`): что положить, с какой суммой
/// сверить и что после этого пометить, решает Dart, и проверяется оно
/// здесь. Сама запись в «Загрузки» и приёмник выбора — родной код:
/// сборкой и руками.
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
    temp = await Directory.systemTemp.createTemp('memoria-record-backup-');
    folder = Directory(p.join(temp.path, FileRecordingStore.folderName));
    await folder.create(recursive: true);
    outlet = FakeRecordOutlet(shares: true)..backs = true;
    now = DateTime(2026, 11, 4, 10, 30);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  FileDeviceRecords open() {
    final FileDeviceRecords records = FileDeviceRecords(
      root: () async => folder,
      outlet: outlet,
      now: () => now,
    );
    addTearDown(records.dispose);
    return records;
  }

  /// Заводит в папке записей папку завершённой записи [name].
  Future<Directory> folderOf(String name, {required String id}) {
    return makeRecordingFolder(folder, name, about: recordingInfo(id: id));
  }

  /// Кладёт в папку записей готовый архив записи [name].
  Future<File> archiveOf(String name, {required String id}) async {
    return packRecording(await folderOf(name, id: id), now: () => now);
  }

  Map<String, Object?> marksOnDisk() {
    final Map<String, Object?> state =
        jsonDecode(
              File(
                p.join(folder.path, FileDeviceRecords.stateName),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    return state['records']! as Map<String, Object?>;
  }

  DeviceRecord named(FileDeviceRecords records, String name) {
    return records.entries.singleWhere(
      (DeviceRecord record) => record.name == name,
    );
  }

  group('SNO-F-REC-13: вторая копия архива', () {
    test('SNO-F-REC-13: упакованная запись тут же получает вторую '
        'копию', () async {
      await folderOf(first, id: firstId);
      final FileDeviceRecords records = open();

      final DeviceRecord? record = await records.pack(first);

      expect(record, isNotNull);
      expect(record!.packed, isTrue);
      expect(records.backs, isTrue);
      // В общую папку ушёл сам архив — с его суммой и в свою папку.
      final File archive = File(p.join(folder.path, '$first.zip'));
      expect(outlet.backups, hasLength(1));
      expect(outlet.backups.single.path, archive.path);
      expect(outlet.backups.single.sha256, await fileSha256(archive));
      expect(outlet.backups.single.folder, kBackupFolder);
      // Запись помечена, и отметка лежит на диске.
      expect(record.copiedAt, now);
      expect(record.sharedAt, isNull);
      expect(record.taken, isTrue);
      final Map<String, Object?> mark =
          marksOnDisk()[first]! as Map<String, Object?>;
      expect(mark['copied_to'], '$kBackupPlace/$first.zip');
      expect(mark.containsKey('shared_at'), isFalse);
    });

    test('SNO-F-REC-13: копия не легла — запись без отметки, упаковка '
        'удалась', () async {
      outlet.backupWorks = false;
      await folderOf(first, id: firstId);
      final FileDeviceRecords records = open();

      final DeviceRecord? record = await records.pack(first);

      expect(record!.packed, isTrue);
      expect(record.copiedAt, isNull);
      expect(record.taken, isFalse);
      expect(outlet.backups, hasLength(1));
      expect(await File(p.join(folder.path, '$first.zip')).exists(), isTrue);
    });

    test('SNO-F-REC-13: общая папка отказала ошибкой — упаковка всё равно '
        'удалась', () async {
      final FileDeviceRecords records = FileDeviceRecords(
        root: () async => folder,
        outlet: _ThrowingOutlet(),
        now: () => now,
      );
      addTearDown(records.dispose);
      await folderOf(first, id: firstId);

      final DeviceRecord? record = await records.pack(first);

      expect(record!.packed, isTrue);
      expect(record.copiedAt, isNull);
    });

    test('SNO-F-REC-13: копии прежних записей докладываются при '
        'запуске', () async {
      // Архивы собраны сборкой, которая вторых копий не клала.
      await archiveOf(first, id: firstId);
      await archiveOf(second, id: secondId);
      final FileDeviceRecords records = open();

      await records.backupPending();

      expect(<String>[
        for (final ({String path, String sha256, String folder}) one
            in outlet.backups)
          p.basename(one.path),
      ], <String>['$first.zip', '$second.zip']);
      expect(named(records, first).copiedAt, now);
      expect(named(records, second).copiedAt, now);

      // Второй запуск: копии уже лежат, класть нечего.
      final FileDeviceRecords again = open();
      await again.backupPending();
      expect(outlet.backups, hasLength(2));
      await again.refresh();
      expect(named(again, first).copiedAt, now);
    });

    test('SNO-F-REC-13: копия, не лёгшая в прошлый раз, кладётся при '
        'следующем запуске', () async {
      outlet.backupWorks = false;
      await folderOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.pack(first);
      expect(named(records, first).copiedAt, isNull);

      outlet.backupWorks = true;
      final FileDeviceRecords again = open();
      await again.backupPending();

      expect(outlet.backups, hasLength(2));
      expect(named(again, first).copiedAt, now);
    });

    test('SNO-F-REC-13: упаковка при запуске кладёт копии тоже', () async {
      // Папка записи прежней сборки: архива у неё ещё нет.
      await folderOf(first, id: firstId);
      final FileDeviceRecords records = open();

      await records.packPending();

      expect(outlet.backups, hasLength(1));
      expect(named(records, first).packed, isTrue);
      expect(named(records, first).copiedAt, now);
    });

    test('SNO-F-REC-13: устройство без общей папки копий не кладёт', () async {
      // ПК и телефоны старше Android 10.
      outlet.backs = false;
      await folderOf(first, id: firstId);
      await archiveOf(second, id: secondId);
      final FileDeviceRecords records = open();

      final DeviceRecord? record = await records.pack(first);
      await records.backupPending();

      expect(records.backs, isFalse);
      expect(outlet.backups, isEmpty);
      expect(record!.copiedAt, isNull);
      expect(
        await File(p.join(folder.path, FileDeviceRecords.stateName)).exists(),
        isFalse,
      );
    });

    test('SNO-F-REC-13: удаление записи копии не касается, отметка '
        'уходит', () async {
      await folderOf(first, id: firstId);
      final FileDeviceRecords records = open();
      final DeviceRecord record = (await records.pack(first))!;

      expect(await records.delete(record), isTrue);

      expect(records.entries, isEmpty);
      expect(marksOnDisk().containsKey(first), isFalse);
      // К общей папке при удалении не обращались вовсе.
      expect(outlet.backups, hasLength(1));
    });
  });

  group('SNO-F-REC-14: отправлена — когда в окне выбрано приложение', () {
    test('SNO-F-REC-14: выбрано приложение — запись отправлена', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();

      final ShareReport report = await records.share(records.entries);

      expect(report.outcome, ShareOutcome.chosen);
      expect(report.sent, 1);
      expect(named(records, first).sharedAt, now);
    });

    test('SNO-F-REC-14: окно закрыто без выбора — отметки нет', () async {
      outlet.outcome = ShareOutcome.dismissed;
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();

      final ShareReport report = await records.share(records.entries);

      expect(report.outcome, ShareOutcome.dismissed);
      expect(report.sent, 0);
      // Окно открывали, но отметка — не об этом.
      expect(outlet.shared, hasLength(1));
      expect(named(records, first).sharedAt, isNull);
      expect(unshared(records.entries), hasLength(1));
    });

    test('SNO-F-REC-14: система о выборе не сообщила — запись остаётся '
        'неотправленной', () async {
      outlet.outcome = ShareOutcome.untold;
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();

      final ShareReport report = await records.share(records.entries);

      expect(report.outcome, ShareOutcome.untold);
      expect(named(records, first).sharedAt, isNull);
    });

    test('SNO-F-REC-14: пачка помечается целиком и только по выбору', () async {
      await archiveOf(first, id: firstId);
      await archiveOf(second, id: secondId);
      final FileDeviceRecords records = open();
      await records.refresh();

      outlet.outcome = ShareOutcome.dismissed;
      expect((await records.share(records.entries)).sent, 0);
      expect(unshared(records.entries), hasLength(2));

      outlet.outcome = ShareOutcome.chosen;
      final ShareReport report = await records.share(records.entries);
      expect(report.sent, 2);
      expect(unshared(records.entries), isEmpty);
    });

    test('SNO-F-REC-14: повторная отправка разрешена, прежняя отметка '
        'остаётся', () async {
      await archiveOf(first, id: firstId);
      final FileDeviceRecords records = open();
      await records.refresh();
      await records.share(records.entries);
      final DateTime marked = now;

      // Второй раз окно закрыли без выбора: запись уже отправляли.
      now = now.add(const Duration(minutes: 5));
      outlet.outcome = ShareOutcome.dismissed;
      final ShareReport report = await records.share(records.entries);

      expect(report.outcome, ShareOutcome.dismissed);
      expect(named(records, first).sharedAt, marked);
    });

    test('SNO-F-REC-14: слово канала читается в исход окна', () {
      expect(shareOutcomeOf('chosen'), ShareOutcome.chosen);
      expect(shareOutcomeOf('dismissed'), ShareOutcome.dismissed);
      expect(shareOutcomeOf('untold'), ShareOutcome.untold);
      expect(shareOutcomeOf('failed'), ShareOutcome.failed);
      expect(shareOutcomeOf(null), ShareOutcome.failed);
      expect(shareOutcomeOf(false), ShareOutcome.failed);
      // Незнакомое слово и «окно открылось» прежних сборок — не выбор:
      // отметки не будет.
      expect(shareOutcomeOf(true), ShareOutcome.untold);
      expect(shareOutcomeOf('выбрано'), ShareOutcome.untold);
    });
  });

  group('SNO-F-REC-13: две отметки записи словами', () {
    final DateTime at = DateTime(2026, 11, 3, 14, 50);

    DeviceRecord record({DateTime? sharedAt, DateTime? copiedAt}) {
      return DeviceRecord(
        name: first,
        bytes: 3145728,
        durationMs: 40 * 60 * 1000,
        sharedAt: sharedAt,
        copiedAt: copiedAt,
      );
    }

    test('SNO-F-REC-13: на телефоне с копиями названы обе отметки', () {
      String about(DeviceRecord one) {
        return describeRecord(one, shares: true, backs: true);
      }

      expect(about(record()), '40:00 · 3,0 МБ · не отправлена · копии нет');
      expect(
        about(record(copiedAt: at)),
        '40:00 · 3,0 МБ · не отправлена · копия есть',
      );
      expect(
        about(record(sharedAt: at)),
        '40:00 · 3,0 МБ · отправлена · копии нет',
      );
      expect(
        about(record(sharedAt: at, copiedAt: at)),
        '40:00 · 3,0 МБ · отправлена · копия есть',
      );
    });

    test('SNO-F-REC-13: в строке раздела считаются неотправленные, а не '
        'записи без копии', () {
      final List<DeviceRecord> records = <DeviceRecord>[
        record(copiedAt: at),
        record(sharedAt: at, copiedAt: at),
      ];

      // Копия в «Загрузках» лежит на том же телефоне: отправки она не
      // заменяет.
      expect(
        describeRecordsCount(records, shares: true),
        '2 · не отправлено 1',
      );
      // На ПК копия — это и есть «ушла с устройства».
      expect(describeRecordsCount(records, shares: false), '2');
    });

    test('SNO-F-REC-13: запись с копией удаляется одним вопросом, без '
        'отметок — двумя', () {
      expect(record().taken, isFalse);
      expect(record(copiedAt: at).taken, isTrue);
      expect(record(sharedAt: at).taken, isTrue);
    });

    test('SNO-F-REC-13: экран завершения говорит, легла ли копия', () {
      expect(
        describeBackup(record(copiedAt: at), backs: true),
        'Копия: Загрузки/Memoria-SNO2026',
      );
      expect(
        describeBackup(record(), backs: true),
        startsWith('Копии в «Загрузках» нет'),
      );
      // ПК вторых копий сам не кладёт: и говорить не о чем.
      expect(describeBackup(record(), backs: false), isNull);
    });

    test('SNO-F-REC-14: после окна «Поделиться» сказано, чем оно '
        'кончилось', () {
      expect(
        describeShared(const ShareReport(ShareOutcome.chosen, sent: 1)),
        'Запись помечена отправленной.',
      );
      expect(
        describeShared(const ShareReport(ShareOutcome.chosen, sent: 2)),
        'Записи помечены отправленными: 2.',
      );
      expect(
        describeShared(const ShareReport(ShareOutcome.dismissed)),
        'Окно закрыто без выбора — запись не отправлена.',
      );
      expect(
        describeShared(const ShareReport(ShareOutcome.untold)),
        startsWith('Телефон не сообщил'),
      );
      expect(
        describeShared(const ShareReport(ShareOutcome.failed)),
        startsWith('Поделиться не получилось'),
      );
    });
  });
}

/// Выход записей, у которого общая папка есть, но отказывает ошибкой.
class _ThrowingOutlet extends NoRecordOutlet {
  @override
  Future<bool> canBackup() async => true;

  @override
  Future<bool> backup(
    String path, {
    required String sha256,
    required String folder,
  }) {
    throw StateError('общая папка не отвечает');
  }
}
