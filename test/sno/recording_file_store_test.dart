import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/file_store.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

/// SNO-F-REC-01, SNO-ALG-REC-01: записи на настоящем диске.
///
/// Папка — временная; что именно лежит в папке записи и что бывает с
/// журналом, оборванным посреди строки.
void main() {
  late Directory temp;
  late Directory records;
  late FileRecordingStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-records-');
    records = Directory(p.join(temp.path, FileRecordingStore.folderName));
    store = FileRecordingStore(() async => records);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Папка незавершённой записи [name].
  Directory current(String name) {
    return Directory(
      p.join(records.path, FileRecordingStore.currentName, name),
    );
  }

  /// Журнал незавершённой записи [name].
  File journalOf(String name) {
    return File(p.join(current(name).path, kEventsFile));
  }

  test('SNO-F-REC-01: папка записей заводится сама', () async {
    expect(await records.exists(), isFalse);
    expect(await store.location(), records.path);
    expect(await records.exists(), isTrue);
  });

  test('SNO-F-REC-01: незавершённая запись лежит отдельно', () async {
    final String name = await store.create('sno2026_I_1_a_20261103-1402');
    expect(name, 'sno2026_I_1_a_20261103-1402');
    expect(await current(name).exists(), isTrue);
    expect(await Directory(p.join(records.path, name)).exists(), isFalse);
  });

  test('SNO-F-REC-01: занятое имя папки получает хвост', () async {
    const String wanted = 'sno2026_I_1_a_20261103-1402';
    final String first = await store.create(wanted);
    final String second = await store.create(wanted);
    await store.finish(first);
    // Имя занято и завершённой записью, и незавершённой.
    final String third = await store.create(wanted);
    expect(first, wanted);
    expect(second, '$wanted-2');
    expect(third, '$wanted-3');
  });

  test('SNO-ALG-REC-01: журнал дописывается и переживает закрытие', () async {
    final String name = await store.create('запись');
    final JournalFile first = await store.openJournal(name);
    await first.append('{"seq":1,"t":0,"text":"«первая»"}\n');
    await first.append('{"seq":2,"t":10}\n');
    await first.close();
    final JournalFile second = await store.openJournal(name);
    await second.append('{"seq":3,"t":20}\n');
    await second.close();

    final List<String> lines = const LineSplitter().convert(
      await journalOf(name).readAsString(),
    );
    expect(lines, <String>[
      '{"seq":1,"t":0,"text":"«первая»"}',
      '{"seq":2,"t":10}',
      '{"seq":3,"t":20}',
    ]);
    expect(await store.lastLine(name), '{"seq":3,"t":20}');
  });

  test('SNO-F-REC-08: оборванный хвост журнала отрезается', () async {
    final String name = await store.create('запись');
    final JournalFile journal = await store.openJournal(name);
    await journal.append('{"seq":1,"t":0}\n{"seq":2,"t":10,"к":"я"}\n');
    await journal.append('{"seq":3,"t":2');
    await journal.close();

    expect(await store.lastLine(name), '{"seq":2,"t":10,"к":"я"}');
    // Обрывка в файле больше нет: дописывать можно сразу за целой строкой.
    expect(
      await journalOf(name).readAsString(),
      '{"seq":1,"t":0}\n{"seq":2,"t":10,"к":"я"}\n',
    );
    final JournalFile again = await store.openJournal(name);
    await again.append('{"seq":3,"t":10}\n');
    await again.close();
    expect(await store.lastLine(name), '{"seq":3,"t":10}');
  });

  test('SNO-F-REC-08: журнал из одного обрывка — целых строк нет', () async {
    final String name = await store.create('запись');
    final JournalFile journal = await store.openJournal(name);
    await journal.append('{"seq":1,"t"');
    await journal.close();

    expect(await store.lastLine(name), isNull);
    expect(await journalOf(name).readAsString(), isEmpty);
  });

  test('SNO-F-REC-08: журнала нет — и последней строки нет', () async {
    final String name = await store.create('запись');
    expect(await store.lastLine(name), isNull);
    final JournalFile journal = await store.openJournal(name);
    await journal.close();
    expect(await store.lastLine(name), isNull);
    // Одна-единственная целая строка.
    final JournalFile again = await store.openJournal(name);
    await again.append('{"seq":1,"t":0}\n');
    await again.close();
    expect(await store.lastLine(name), '{"seq":1,"t":0}');
  });

  test('SNO-F-REC-01: файл записи кладётся целиком и заменяется', () async {
    final String name = await store.create('запись');
    await store.put(name, kRecordingFile, '{"finished": false}');
    await store.put(name, kRecordingFile, '{"finished": true}');

    final Directory folder = current(name);
    expect(
      await File(p.join(folder.path, kRecordingFile)).readAsString(),
      '{"finished": true}',
    );
    // Временного файла после записи не остаётся.
    final List<String> names = <String>[
      await for (final FileSystemEntity entity in folder.list())
        p.basename(entity.path),
    ];
    expect(names, <String>[kRecordingFile]);
  });

  test('SNO-F-REC-01: завершённая запись переезжает к остальным', () async {
    final String name = await store.create('запись');
    final JournalFile journal = await store.openJournal(name);
    await journal.append('{"seq":1,"t":0}\n');
    await journal.close();
    await store.put(name, kSnapshotStartFile, '{}');

    await store.finish(name);

    expect(await current(name).exists(), isFalse);
    final Directory done = Directory(p.join(records.path, name));
    expect(await done.exists(), isTrue);
    expect(await File(p.join(done.path, kEventsFile)).exists(), isTrue);
    expect(await File(p.join(done.path, kSnapshotStartFile)).exists(), isTrue);
    // Завершённую запись хранилище по-прежнему находит по имени.
    expect(await store.lastLine(name), '{"seq":1,"t":0}');
    await store.put(name, kRecordingFile, '{"finished": true}');
    expect(await File(p.join(done.path, kRecordingFile)).exists(), isTrue);
    // Второе завершение ничего не ломает.
    await store.finish(name);
    expect(await done.exists(), isTrue);
  });
}
