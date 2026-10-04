import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/device_library.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/device_files.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// Книги на устройстве целиком: обход, три ступени разборки и поиск.
///
/// Здесь же проверяется сценарий «разрешения не дали» — не как оговорка в
/// конце, а наравне с основным: приложение обязано остаться полностью
/// рабочим, а список чужих файлов после отзыва разрешения обязан исчезнуть.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  ScannedFile onDisk(String path, {int size = 900, DateTime? modified}) {
    return ScannedFile(
      path: path,
      size: size,
      modifiedAt: modified ?? DateTime.utc(2026, 9, 1),
    );
  }

  DeviceLibrary build({
    required List<ScannedFile> files,
    StorageAccess? access,
    Map<String, List<int>> contents = const <String, List<int>>{},
    List<String> pages = const <String>['страница книги'],
  }) {
    return DeviceLibrary(
      files: data.deviceFiles,
      access: access ?? FakeStorageAccess(),
      storage: _PathBookStorage(contents),
      opener: FakeDocumentOpener(FakeReaderDocument(pages: pages)),
      runner: (List<String> roots) => fakeScan(files),
      now: () => DateTime.utc(2026, 9, 5),
    );
  }

  Future<void> runScan(DeviceLibrary device) async {
    await device.scan().toList();
  }

  /// Служба, чей обход идёт так, как велит тест: по событию за раз.
  DeviceLibrary buildWith(ScanRunner runner) {
    return DeviceLibrary(
      files: data.deviceFiles,
      access: FakeStorageAccess(),
      storage: _PathBookStorage(const <String, List<int>>{}),
      opener: FakeDocumentOpener(
        FakeReaderDocument(pages: const <String>['страница книги']),
      ),
      runner: runner,
      now: () => DateTime.utc(2026, 9, 6),
    );
  }

  ScanEvent foundEvent(ScannedFile file) {
    return ScanEvent(file: file, directory: '', visited: 0);
  }

  group('обход', () {
    test('найденные файлы попадают в базу', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[
          onDisk('/device/Книги/Онегин.pdf'),
          onDisk('/device/Downloads/учебник.pdf'),
        ],
      );

      await runScan(device);

      final List<DeviceFileRecord> records = await data.deviceFiles.files();
      expect(records.length, 2);
      expect(
        records.every((DeviceFileRecord r) => r.stage == IndexStage.name),
        isTrue,
      );
    });

    test('обход отдаёт растущий счёт, а не один ответ в конце', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[
          onDisk('/device/один.pdf'),
          onDisk('/device/два.pdf'),
        ],
      );

      final List<ScanProgress> steps = await device.scan().toList();
      expect(steps.length, greaterThan(1));
      expect(steps.last.done, isTrue);
      expect(steps.last.found, 2);
    });

    test('пропавший файл помечается при повторном обходе', () async {
      final ScannedFile stays = onDisk('/device/остался.pdf');
      final ScannedFile goes = onDisk('/device/пропал.pdf');
      await runScan(build(files: <ScannedFile>[stays, goes]));
      await runScan(build(files: <ScannedFile>[stays]));

      final List<DeviceFileRecord> records = await data.deviceFiles.files();
      final DeviceFileRecord gone = records.firstWhere(
        (DeviceFileRecord r) => r.path == goes.path,
      );
      expect(gone.missing, isTrue);
      // Запись не удалена: карту памяти вынимают и вставляют обратно.
      expect(records.length, 2);
    });

    test('без разрешения обход не начинается вовсе', () async {
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/книга.pdf')],
        access: access,
      );

      final List<ScanProgress> steps = await device.scan().toList();
      expect(steps.single.done, isTrue);
      expect(steps.single.found, 0);
      expect(await data.deviceFiles.files(), isEmpty);
    });
  });

  group('BUG-06: прерванный обход', () {
    test('BUG-06: остановленный обход никого не объявляет пропавшим', () async {
      final ScannedFile near = onDisk('/device/А/ближняя.pdf');
      final ScannedFile far = onDisk('/device/Я/дальняя.pdf');
      await runScan(build(files: <ScannedFile>[near, far]));

      // Второй обход дошёл до первой книги — и читатель ушёл с экрана.
      final StreamController<ScanEvent> feed = StreamController<ScanEvent>();
      final DeviceLibrary device = buildWith((List<String> roots) {
        return feed.stream;
      });
      final Future<List<ScanProgress>> steps = device.scan().toList();
      feed.add(foundEvent(near));
      await pumpEventQueue();
      await device.stopScan();
      final List<ScanProgress> seen = await steps;
      await feed.close();

      expect(seen.last.done, isTrue);
      expect(seen.last.interrupted, isFalse, reason: 'остановка — не сбой');
      final List<DeviceFileRecord> records = await data.deviceFiles.files();
      expect(records.length, 2);
      expect(
        records.where((DeviceFileRecord r) => r.missing),
        isEmpty,
        reason: 'до второй книги обход не дошёл — судить о ней нельзя',
      );
      // И индекс цел: книга, до которой не дошли, находится по-прежнему.
      expect(await data.deviceFiles.search('дальняя'), <String>[far.path]);
      expect(device.isScanning, isFalse);
    });

    test('BUG-06: остановленный обход записывает то, что нашёл', () async {
      final ScannedFile fresh = onDisk('/device/новая.pdf');
      final StreamController<ScanEvent> feed = StreamController<ScanEvent>();
      final DeviceLibrary device = buildWith((List<String> roots) {
        return feed.stream;
      });
      final Future<List<ScanProgress>> steps = device.scan().toList();
      feed.add(foundEvent(fresh));
      await pumpEventQueue();
      await device.stopScan();
      await steps;
      await feed.close();

      expect((await data.deviceFiles.files()).single.path, fresh.path);
    });

    test('BUG-06: вернувшийся файл снова находится поиском', () async {
      final ScannedFile file = onDisk('/device/Книги/Онегин.pdf');
      await runScan(build(files: <ScannedFile>[file]));
      // Карту памяти вынули: обход дошёл до конца и файла не встретил.
      await runScan(build(files: const <ScannedFile>[]));
      expect(await data.deviceFiles.search('Онегин'), isEmpty);

      // Вставили обратно.
      await runScan(build(files: <ScannedFile>[file]));

      final DeviceFileRecord record = (await data.deviceFiles.files()).single;
      expect(record.missing, isFalse);
      // Именно по индексу, а не через `find`: тот подстраховался бы
      // вторым проходом по похожим именам и дефект бы спрятал.
      expect(await data.deviceFiles.search('Онегин'), <String>[file.path]);
    });

    test('новый обход останавливает прежний', () async {
      final StreamController<ScanEvent> first = StreamController<ScanEvent>();
      final List<Stream<ScanEvent>> runs = <Stream<ScanEvent>>[
        first.stream,
        fakeScan(<ScannedFile>[onDisk('/device/вторая.pdf')]),
      ];
      final DeviceLibrary device = buildWith((List<String> roots) {
        return runs.removeAt(0);
      });

      final Future<List<ScanProgress>> stale = device.scan().toList();
      await pumpEventQueue();
      final List<ScanProgress> fresh = await device.scan().toList();

      expect((await stale).last.done, isTrue);
      expect(fresh.last.done, isTrue);
      expect(fresh.last.found, 1);
      expect(device.isScanning, isFalse);
      await first.close();
    });
  });

  group('BUG-06: отписка останавливает свой обход', () {
    test('BUG-06: прежний обход, доживая, новый не останавливает', () async {
      // Поток хода зовёт `onCancel` и когда закрывается сам. Прежде это
      // останавливало обход, который шёл в ту минуту, — то есть новый.
      final StreamController<ScanEvent> first = StreamController<ScanEvent>();
      final StreamController<ScanEvent> second =
          StreamController<ScanEvent>();
      final List<Stream<ScanEvent>> runs = <Stream<ScanEvent>>[
        first.stream,
        second.stream,
      ];
      final DeviceLibrary device = buildWith((List<String> roots) {
        return runs.removeAt(0);
      });

      final Future<List<ScanProgress>> stale = device.scan().toList();
      await pumpEventQueue();
      final Future<List<ScanProgress>> fresh = device.scan().toList();
      // Прежний обход доживает и закрывает свой поток.
      await stale;
      await pumpEventQueue();

      expect(device.isScanning, isTrue, reason: 'новый обход идёт');
      second.add(foundEvent(onDisk('/device/книга.pdf')));
      await second.close();
      expect((await fresh).last.found, 1);
      await first.close();
    });

    test('BUG-06: отписка до начала обхода идущий не трогает', () async {
      final StreamController<ScanEvent> live = StreamController<ScanEvent>();
      int started = 0;
      final DeviceLibrary device = buildWith((List<String> roots) {
        started++;
        return live.stream;
      });
      final Future<List<ScanProgress>> running = device.scan().toList();
      await pumpEventQueue();
      expect(started, 1);

      // Второй обход попросили — и тут же раздумали.
      await device.scan().listen((ScanProgress _) {}).cancel();
      await pumpEventQueue();

      expect(started, 1, reason: 'отменённый обход не начинался');
      expect(device.isScanning, isTrue, reason: 'идущий не остановлен');
      await live.close();
      expect((await running).last.done, isTrue);
    });
  });

  group('BUG-16: сбой в обходе', () {
    Stream<ScanEvent> broken(ScannedFile file) async* {
      yield foundEvent(file);
      throw const ScanFailure('диск отвалился');
    }

    test('BUG-16: упавший обход кончается и называет причину', () async {
      final ScannedFile seen = onDisk('/device/успели.pdf');
      final DeviceLibrary device = buildWith((List<String> roots) {
        return broken(seen);
      });

      final List<ScanProgress> steps = await device.scan().toList();

      expect(steps.last.done, isTrue, reason: 'обход не висит вечно');
      expect(steps.last.interrupted, isTrue);
      expect(steps.last.failure, 'диск отвалился');
      expect(device.isScanning, isFalse);
    });

    test('BUG-16: найденное до сбоя записано, пропавших нет', () async {
      final ScannedFile near = onDisk('/device/А/ближняя.pdf');
      final ScannedFile far = onDisk('/device/Я/дальняя.pdf');
      await runScan(build(files: <ScannedFile>[near, far]));

      await runScan(buildWith((List<String> roots) => broken(near)));

      final List<DeviceFileRecord> records = await data.deviceFiles.files();
      expect(records.length, 2);
      expect(records.where((DeviceFileRecord r) => r.missing), isEmpty);
    });

    test('BUG-16: после сбоя обход можно повторить', () async {
      final ScannedFile file = onDisk('/device/книга.pdf');
      final List<Stream<ScanEvent>> runs = <Stream<ScanEvent>>[
        broken(file),
        fakeScan(<ScannedFile>[file, onDisk('/device/ещё.pdf')]),
      ];
      final DeviceLibrary device = buildWith((List<String> roots) {
        return runs.removeAt(0);
      });

      expect((await device.scan().toList()).last.interrupted, isTrue);
      final List<ScanProgress> again = await device.scan().toList();

      expect(again.last.interrupted, isFalse);
      expect((await data.deviceFiles.files()).length, 2);
    });
  });

  group('разборка', () {
    test('вторая ступень даёт отпечаток и заголовок', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/scan0043.pdf')],
        contents: <String, List<int>>{
          '/device/scan0043.pdf': _pdfWith('Pikovaya dama', 'Pushkin'),
        },
      );
      await runScan(device);

      expect(await device.indexBatch(upTo: IndexStage.meta), 1);

      final DeviceFileRecord record = (await data.deviceFiles.files()).single;
      expect(record.stage, IndexStage.meta);
      expect(record.fingerprint, isNotNull);
      expect(record.title, 'Pikovaya dama');
      expect(record.author, 'Pushkin');
    });

    test('третья ступень читает текст и отмечает скан', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/книга.pdf')],
        pages: const <String>['', 'война и мир', 'вторая страница'],
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);
      expect(await device.indexBatch(upTo: IndexStage.text), 1);

      final DeviceFileRecord record = (await data.deviceFiles.files()).single;
      expect(record.stage, IndexStage.text);
      expect(record.hasTextLayer, isTrue);
    });

    test('книга без текстового слоя честно помечается', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/скан.pdf')],
        pages: const <String>['', '', ''],
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);
      await device.indexBatch(upTo: IndexStage.text);

      final DeviceFileRecord record = (await data.deviceFiles.files()).single;
      expect(record.hasTextLayer, isFalse);
    });

    test('F-DEV-13: не открывшаяся книга — не скан', () async {
      // Прежде ей писалось «текста нет», и с меткой на карточке она
      // была бы названа сканом. «Не знаю» — пустой признак.
      final ScannedFile file = onDisk('/device/не-открылась.pdf');
      final DeviceLibrary device = DeviceLibrary(
        files: data.deviceFiles,
        access: FakeStorageAccess(),
        storage: _PathBookStorage(const <String, List<int>>{}),
        opener: FakeDocumentOpener(
          FakeReaderDocument.blank(1),
          failure: DocumentOpenException(
            DocumentProblem.damaged,
            FilePathSource(file.path),
          ),
        ),
        runner: (List<String> roots) => fakeScan(<ScannedFile>[file]),
        now: () => DateTime.utc(2026, 9, 5),
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);
      await device.indexBatch(upTo: IndexStage.text);

      final DeviceFileRecord record = (await data.deviceFiles.files()).single;
      expect(record.stage, IndexStage.text, reason: 'на второй круг не идёт');
      expect(record.hasTextLayer, isNull);
    });

    test('нечитаемый файл не заходит на второй круг', () async {
      // Иначе разборка будет вечно возвращаться к одному и тому же
      // битому файлу и никогда не доберётся до остальных.
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/битая.pdf')],
        contents: <String, List<int>>{'/device/битая.pdf': const <int>[]},
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);

      expect((await data.deviceFiles.files()).single.stage, IndexStage.meta);
      expect(await device.indexBatch(upTo: IndexStage.meta), 0);
    });

    test('разобранное не пересчитывается при повторном обходе', () async {
      final ScannedFile file = onDisk('/device/книга.pdf');
      final DeviceLibrary device = build(files: <ScannedFile>[file]);
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);

      await runScan(build(files: <ScannedFile>[file]));

      expect(
        (await data.deviceFiles.files()).single.stage,
        IndexStage.meta,
        reason: 'файл не менялся — открывать его заново незачем',
      );
    });

    test('изменившийся файл разбирается заново', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/книга.pdf')],
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);

      await runScan(
        build(files: <ScannedFile>[onDisk('/device/книга.pdf', size: 5000)]),
      );

      expect((await data.deviceFiles.files()).single.stage, IndexStage.name);
    });
  });

  group('поиск', () {
    Future<DeviceLibrary> withFiles(List<String> paths) async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[for (final String path in paths) onDisk(path)],
      );
      await runScan(device);
      return device;
    }

    test('находит по имени файла', () async {
      final DeviceLibrary device = await withFiles(<String>[
        '/device/Книги/Пиковая дама.pdf',
        '/device/Книги/Гладиатор.pdf',
      ]);

      final List<DeviceBookEntry> found = await device.find('пиковая');
      expect(found.length, 1);
      expect(found.single.title, 'Пиковая дама.pdf');
    });

    test('находит скан с латиницей вместо кириллицы', () async {
      // Главный случай всей сессии: имя набрано латинскими двойниками, и
      // без свёртки такая книга не находится по собственному названию.
      final DeviceLibrary device = await withFiles(<String>[
        '/device/scan/BOЙHA и MИP.pdf',
      ]);

      final List<DeviceBookEntry> found = await device.find('война и мир');
      expect(found.length, 1);
    });

    test('находит по имени папки', () async {
      final DeviceLibrary device = await withFiles(<String>[
        '/device/Учебники/doc0043.pdf',
      ]);

      expect((await device.find('учебники')).length, 1);
    });

    test('опечатка находится вторым проходом', () async {
      final DeviceLibrary device = await withFiles(<String>[
        '/device/Книги/Достоевский.pdf',
      ]);

      expect((await device.find('Достаевский')).length, 1);
    });

    test('пустой запрос показывает всё', () async {
      final DeviceLibrary device = await withFiles(<String>[
        '/device/один.pdf',
        '/device/два.pdf',
      ]);

      expect((await device.find('   ')).length, 2);
    });

    test('чужое слово не находит ничего', () async {
      final DeviceLibrary device = await withFiles(<String>[
        '/device/Книги/Онегин.pdf',
      ]);

      expect(await device.find('квантовая хромодинамика'), isEmpty);
    });

    test('пропавший файл в выдачу не попадает', () async {
      final ScannedFile file = onDisk('/device/Книги/Онегин.pdf');
      await runScan(build(files: <ScannedFile>[file]));
      final DeviceLibrary second = build(files: const <ScannedFile>[]);
      await runScan(second);

      expect(await second.find('Онегин'), isEmpty);
    });
  });

  group('разрешение отозвали', () {
    test('список файлов и индекс забываются целиком', () async {
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/Книги/Онегин.pdf')],
      );
      await runScan(device);
      expect(await data.deviceFiles.files(), isNotEmpty);

      await device.forgetDevice();

      expect(await data.deviceFiles.files(), isEmpty);
      expect(await device.find('Онегин'), isEmpty);
    });

    test('полка при этом остаётся нетронутой', () async {
      // Отзыв разрешения — про файлы устройства, а не про библиотеку
      // читателя: книги, которые он поставил на полку, никуда не деваются.
      await data.library.save(testBook());
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/Книги/Онегин.pdf')],
      );
      await runScan(device);
      await device.forgetDevice();

      expect((await data.library.books()).length, 1);
    });
  });
}

/// Хранилище, где у каждого пути своё содержимое.
class _PathBookStorage implements BookStorage {
  _PathBookStorage(this.contents);

  final Map<String, List<int>> contents;

  static const List<int> _default = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31];

  @override
  Future<BookSource> adopt(PickedFile file) async => FilePathSource(file.path!);

  @override
  Future<BookHandle> open(BookSource source) async {
    final List<int> bytes = source is FilePathSource
        ? contents[source.path] ?? _default
        : _default;
    if (bytes.isEmpty) {
      throw BookUnavailableException(source);
    }
    return MemoryBookHandle(bytes);
  }

  @override
  Future<bool> available(BookSource source) async => true;

  @override
  Future<void> release(BookSource source) async {}
}

/// Байты PDF с метаданными — ровно столько, сколько нужно разбору.
List<int> _pdfWith(String title, String author) {
  final String text =
      '%PDF-1.7\n'
      '7 0 obj\n<< /Title ($title) /Author ($author) >>\nendobj\n'
      'trailer\n<< /Info 7 0 R >>\n';
  return Uint8List.fromList(text.codeUnits);
}
