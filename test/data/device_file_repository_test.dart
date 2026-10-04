import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/device_files.dart';

import 'test_data.dart';

/// Список файлов устройства и индекс поиска в базе.
///
/// Индекс — отдельная виртуальная таблица FTS5, и главная опасность здесь
/// не в том, что он не найдёт, а в том, что он **разъедется** с базой:
/// книга есть в списке, а поиском не находится. Поэтому проверяется не
/// только выдача, но и то, что записи уходят и приходят вместе.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  DeviceFileRecord record(
    String path, {
    String? hash,
    String? title,
    String? author,
    IndexStage stage = IndexStage.name,
  }) {
    return DeviceFileRecord(
      path: path,
      size: 1000,
      modifiedAt: DateTime.utc(2026, 9, 1),
      seenAt: DateTime.utc(2026, 9, 5),
      fingerprint: hash,
      title: title,
      author: author,
      stage: stage,
    );
  }

  Future<void> add(DeviceFileRecord file, {String? body}) {
    return data.deviceFiles.saveFile(file, body: body);
  }

  test('в этой сборке SQLite есть FTS5', () async {
    // Не формальность: без модуля поиск деградирует до перебора имён, и
    // все проверки ниже проверяли бы не то, что написано в плане. Если
    // этот тест однажды упадёт — падать должен именно он, а не десяток
    // непонятных.
    expect(
      data.searchIndexed,
      isTrue,
      reason: 'FTS5 обязан быть и в системной SQLite, и в sqlite3_flutter_libs',
    );
  });

  group('запись', () {
    test('файл сохраняется и читается', () async {
      await add(record('/device/книга.pdf', hash: 'h1'));
      final DeviceFileRecord saved = (await data.deviceFiles.files()).single;
      expect(saved.path, '/device/книга.pdf');
      expect(saved.fingerprint, 'h1');
      expect(saved.stage, IndexStage.name);
      expect(saved.missing, isFalse);
    });

    test('обновление заголовка не стирает разобранный текст', () async {
      // Метаданные подъезжают раньше текста, но бывает и наоборот:
      // порядок ступеней не должен стоить уже сделанной работы.
      await add(
        record('/device/книга.pdf', stage: IndexStage.text),
        body: 'редкоеслово внутри текста',
      );
      await add(
        record('/device/книга.pdf', title: 'Название', stage: IndexStage.text),
      );

      expect(await data.deviceFiles.search('редкоеслово'), <String>[
        '/device/книга.pdf',
      ]);
    });

    test('изменившийся файл теряет прежний текст в индексе', () async {
      await add(
        record('/device/книга.pdf', stage: IndexStage.text),
        body: 'прежнеесодержимое',
      );
      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(ScanVerdict.changed, record('/device/книга.pdf')),
      ]);

      expect(await data.deviceFiles.search('прежнеесодержимое'), isEmpty);
    });

    test('пропавший файл уходит из индекса', () async {
      await add(record('/device/Онегин.pdf'));
      expect(await data.deviceFiles.search('онегин'), isNotEmpty);

      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(
          ScanVerdict.gone,
          record('/device/Онегин.pdf').copyWith(missing: true),
        ),
      ]);

      expect(await data.deviceFiles.search('онегин'), isEmpty);
    });

    test('«файл на месте» не трогает индекс', () async {
      await add(
        record('/device/книга.pdf', stage: IndexStage.text),
        body: 'сохранённоеслово',
      );
      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(
          ScanVerdict.unchanged,
          record('/device/книга.pdf', stage: IndexStage.text),
        ),
      ]);

      expect(await data.deviceFiles.search('сохранённоеслово'), isNotEmpty);
    });

    test('F-APP-02: обход не затирает узнанное, пока он шёл', () async {
      // Разборка успела дойти до текста, а обход несёт снимок записи на
      // своё начало — без отпечатка и со ступенью «имя».
      await add(
        record(
          '/device/книга.pdf',
          hash: 'h1',
          title: 'Онегин',
          stage: IndexStage.text,
        ).copyWith(hasTextLayer: false),
      );
      final DateTime later = DateTime.utc(2026, 9, 9);

      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(
          ScanVerdict.unchanged,
          record('/device/книга.pdf').copyWith(seenAt: later),
        ),
      ]);

      final DeviceFileRecord saved = (await data.deviceFiles.files()).single;
      expect(saved.seenAt, later, reason: 'файл отмечен как виденный');
      expect(saved.stage, IndexStage.text);
      expect(saved.fingerprint, 'h1');
      expect(saved.title, 'Онегин');
      expect(saved.hasTextLayer, isFalse);
    });

    test('BUG-06: пропавший файл тоже не теряет узнанного', () async {
      await add(
        record('/device/книга.pdf', hash: 'h1', stage: IndexStage.meta),
      );

      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(
          ScanVerdict.gone,
          record('/device/книга.pdf').copyWith(missing: true),
        ),
      ]);

      final DeviceFileRecord saved = (await data.deviceFiles.files()).single;
      expect(saved.missing, isTrue);
      // Карту памяти вернут — и отпечаток считать заново не придётся.
      expect(saved.fingerprint, 'h1');
      expect(saved.stage, IndexStage.meta);
    });

    test('«файл на месте» о незнакомом файле заводит запись', () async {
      await data.deviceFiles.applyScan(<ScanDecision>[
        ScanDecision(ScanVerdict.unchanged, record('/device/новая.pdf')),
      ]);

      expect((await data.deviceFiles.files()).single.path, '/device/новая.pdf');
    });
  });

  group('F-DEV-13: правило «есть ли текст» поменялось', () {
    test('F-DEV-13: ответ «текста нет» проверяется заново', () async {
      await add(
        record(
          '/device/скан.pdf',
          hash: 'h1',
          stage: IndexStage.text,
        ).copyWith(hasTextLayer: false),
      );
      await add(
        record(
          '/device/книга.pdf',
          hash: 'h2',
          stage: IndexStage.text,
        ).copyWith(hasTextLayer: true),
      );

      expect(await data.deviceFiles.recheckTextLayers(), 1);

      final Map<String, DeviceFileRecord> saved = <String, DeviceFileRecord>{
        for (final DeviceFileRecord file in await data.deviceFiles.files())
          file.path: file,
      };
      final DeviceFileRecord scan = saved['/device/скан.pdf']!;
      expect(scan.hasTextLayer, isNull, reason: 'прежний ответ снят');
      expect(scan.stage, IndexStage.meta, reason: 'текст прочитают ещё раз');
      expect(scan.fingerprint, 'h1', reason: 'остальное на месте');
      final DeviceFileRecord book = saved['/device/книга.pdf']!;
      expect(book.hasTextLayer, isTrue);
      expect(book.stage, IndexStage.text);
    });

    test('F-DEV-13: без ответов «текста нет» менять нечего', () async {
      await add(record('/device/книга.pdf'));

      expect(await data.deviceFiles.recheckTextLayers(), 0);
    });
  });

  group('ранжирование', () {
    test('имя файла весит больше текста', () async {
      // Читатель ищет книгу, которую помнит, и помнит он её по названию.
      // Совпадение на четырёхсотой странице — довод куда слабее.
      await add(record('/device/Онегин.pdf'), body: 'ничего общего');
      await add(
        record('/device/Справочник.pdf', stage: IndexStage.text),
        body: 'онегин упомянут здесь мимоходом среди прочих героев',
      );

      final List<String> found = await data.deviceFiles.search('онегин');
      expect(found.length, 2);
      expect(found.first, '/device/Онегин.pdf');
    });

    test('метаданные весят больше текста', () async {
      await add(
        record('/device/scan0043.pdf', title: 'Пиковая дама'),
        body: 'ничего общего',
      );
      await add(
        record('/device/другая.pdf', stage: IndexStage.text),
        body: 'пиковая дама упомянута здесь мимоходом',
      );

      final List<String> found = await data.deviceFiles.search('пиковая');
      expect(found.first, '/device/scan0043.pdf');
    });
  });

  group('очередь разборки', () {
    test('берутся только неразобранные', () async {
      await add(record('/device/новая.pdf'));
      await add(record('/device/готовая.pdf', stage: IndexStage.text));

      final List<DeviceFileRecord> pending = await data.deviceFiles
          .pendingIndex(upTo: IndexStage.meta);
      expect(pending.single.path, '/device/новая.pdf');
    });

    test('до текста берутся и те, у кого есть метаданные', () async {
      await add(record('/device/с-метаданными.pdf', stage: IndexStage.meta));
      final List<DeviceFileRecord> pending = await data.deviceFiles
          .pendingIndex(upTo: IndexStage.text);
      expect(pending.length, 1);
    });

    test('пропавшие в очередь не попадают', () async {
      await add(record('/device/пропала.pdf').copyWith(missing: true));
      expect(
        await data.deviceFiles.pendingIndex(upTo: IndexStage.meta),
        isEmpty,
      );
    });

    test('порядок устойчив, а порция ограничена', () async {
      for (int i = 0; i < 5; i++) {
        await add(record('/device/книга-$i.pdf'));
      }
      final List<DeviceFileRecord> first = await data.deviceFiles.pendingIndex(
        upTo: IndexStage.meta,
        limit: 2,
      );
      final List<DeviceFileRecord> second = await data.deviceFiles.pendingIndex(
        upTo: IndexStage.meta,
        limit: 2,
      );
      expect(first.length, 2);
      expect(
        first.map((DeviceFileRecord r) => r.path),
        second.map((DeviceFileRecord r) => r.path),
        reason: 'иначе один файл берётся дважды, а другой не берётся вовсе',
      );
    });
  });

  test('забыть устройство — значит забыть и индекс', () async {
    await add(record('/device/Онегин.pdf'));
    await data.deviceFiles.forgetEverything();

    expect(await data.deviceFiles.files(), isEmpty);
    expect(await data.deviceFiles.search('онегин'), isEmpty);
  });

  test('пустой запрос ничего не ищет', () async {
    await add(record('/device/Онегин.pdf'));
    expect(await data.deviceFiles.search('   '), isEmpty);
  });
}
