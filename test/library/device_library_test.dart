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
      expect(records.every((DeviceFileRecord r) => r.stage == IndexStage.name),
          isTrue);
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

    test('нечитаемый файл не заходит на второй круг', () async {
      // Иначе разборка будет вечно возвращаться к одному и тому же
      // битому файлу и никогда не доберётся до остальных.
      final DeviceLibrary device = build(
        files: <ScannedFile>[onDisk('/device/битая.pdf')],
        contents: <String, List<int>>{'/device/битая.pdf': const <int>[]},
      );
      await runScan(device);
      await device.indexBatch(upTo: IndexStage.meta);

      expect(
        (await data.deviceFiles.files()).single.stage,
        IndexStage.meta,
      );
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

      expect(
        (await data.deviceFiles.files()).single.stage,
        IndexStage.name,
      );
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
