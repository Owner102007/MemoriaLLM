import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/archive_scan.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/infrastructure/files/archive_scanner.dart';
import 'package:path/path.dart' as p;

/// Архивы-образцы, собранные другими реализациями
/// (`tool/make_zip_fixtures.py`).
const String _fixtures = 'test/fixtures/zip';

/// Изолят поиска, который падает, не найдя ничего (BUG-16).
Future<void> crashingSearch(List<Object> args) async {
  throw StateError('диск отвалился');
}

/// SNO-ALG-LIT-02: поиск архивов с книгами на дереве, собранном в тесте.
///
/// Телефона у сессии нет, но отбор — это работа с файловой системой и с
/// оглавлением архива, и проверяется он на настоящих папках во временном
/// каталоге, с архивами, которые собрала не наша реализация ZIP.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('memoria-archives');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  /// Кладёт архив-образец [fixture] в дерево под именем [relative].
  Future<File> place(String fixture, String relative) async {
    final File file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    return File(p.join(_fixtures, fixture)).copy(file.path);
  }

  Future<List<FoundArchive>> search() async {
    final List<FoundArchive> found = <FoundArchive>[];
    await scanForArchives(roots: <String>[root.path], onArchive: found.add);
    return found;
  }

  /// Найденное: путь относительно корня → число книг.
  Future<Map<String, int>> counts() async {
    return <String, int>{
      for (final FoundArchive archive in await search())
        p.relative(archive.path, from: root.path): archive.books,
    };
  }

  group('SNO-ALG-LIT-02: что считается архивом с книгами', () {
    test('SNO-ALG-LIT-02: число книг — столько встанет на полку', () async {
      await place('shelf_stored.zip', 'a/shelf_stored.zip');
      await place('shelf_deflate_cp866.zip', 'a/shelf_deflate_cp866.zip');
      await place('wrapped_infozip.zip', 'a/wrapped_infozip.zip');
      await place('zip64_python.zip', 'a/zip64_python.zip');
      await place('zip64_infozip.zip', 'a/zip64_infozip.zip');
      await place('descriptor_python.zip', 'a/descriptor_python.zip');
      await place('unicode_extra.zip', 'a/unicode_extra.zip');
      await place('backslash.zip', 'a/backslash.zip');

      expect(await counts(), <String, int>{
        p.join('a', 'shelf_stored.zip'): 4,
        // Не-PDF и служебные файлы систем книгами не считаются.
        p.join('a', 'shelf_deflate_cp866.zip'): 4,
        p.join('a', 'wrapped_infozip.zip'): 5,
        p.join('a', 'zip64_python.zip'): 4,
        p.join('a', 'zip64_infozip.zip'): 4,
        p.join('a', 'descriptor_python.zip'): 2,
        p.join('a', 'unicode_extra.zip'): 2,
        p.join('a', 'backslash.zip'): 1,
      });
    });

    test('SNO-ALG-LIT-02: архив без книг в список не попадает', () async {
      await place('no_books.zip', 'Download/фото с дачи.zip');
      await place('empty.zip', 'Download/пустой.zip');

      expect(await search(), isEmpty);
    });

    test('SNO-ALG-LIT-02: не ZIP и оборванный архив — не архив', () async {
      await place('not_a_zip.zip', 'Download/текст.zip');
      await place('truncated.zip', 'Download/недокачанный.zip');
      await File(p.join(root.path, 'Download', 'нулевой.zip')).create();

      expect(await search(), isEmpty);
    });

    test('SNO-ALG-LIT-02: пароль и чужое сжатие узнает распаковка', () async {
      // Оглавление у них читается, и книги в нём есть: в списке такие
      // архивы стоят, а отказ словами получают при распаковке.
      await place('encrypted_infozip.zip', 'a/с паролем.zip');
      await place('bzip2_python.zip', 'a/bzip2.zip');
      await place('bad_crc.zip', 'a/битая книга.zip');

      expect(await counts(), <String, int>{
        p.join('a', 'с паролем.zip'): 2,
        p.join('a', 'bzip2.zip'): 2,
        p.join('a', 'битая книга.zip'): 4,
      });
    });

    test('SNO-ALG-LIT-02: архив узнаётся по расширению', () async {
      await place('shelf_stored.zip', 'Книги/Литература.ZIP');
      await place('shelf_stored.zip', 'Книги/литература.bin');
      await place('shelf_stored.zip', 'Книги/литература');

      expect(await counts(), <String, int>{
        p.join('Книги', 'Литература.ZIP'): 4,
      });
    });

    test('SNO-ALG-LIT-02: книги устройства поиск не показывает', () async {
      // Решение П3: свои PDF в сборках для тестирования не добавляются.
      final File book = File(p.join(root.path, 'Книги', 'Онегин.pdf'));
      await book.parent.create(recursive: true);
      await book.writeAsString('%PDF-1.7\nкнига');
      await place('shelf_stored.zip', 'Книги/Литература.zip');

      expect(
        (await search()).map((FoundArchive archive) => archive.name).toList(),
        <String>['Литература.zip'],
      );
    });

    test('SNO-ALG-LIT-02: размер и время берутся с диска', () async {
      final File file = await place('shelf_stored.zip', 'a/Литература.zip');
      final FileStat stat = await file.stat();

      final FoundArchive archive = (await search()).single;

      expect(archive.path, file.path);
      expect(archive.size, stat.size);
      expect(archive.modifiedAt, stat.modified);
      expect(archive.name, 'Литература.zip');
    });

    test('SNO-ALG-LIT-02: файла нет — не архив, а не ошибка', () async {
      expect(
        await probeArchive(File(p.join(root.path, 'нет такого.zip'))),
        isNull,
      );
    });
  });

  group('SNO-ALG-LIT-02: где поиск не ищет', () {
    test('SNO-ALG-LIT-02: служебные и скрытые папки не обходятся', () async {
      await place('shelf_stored.zip', 'Download/Литература.zip');
      await place('shelf_stored.zip', 'Android/data/com.chat/files/x.zip');
      await place('shelf_stored.zip', '.thumbnails/x.zip');
      await place('shelf_stored.zip', 'Download/cache/x.zip');
      await place('shelf_stored.zip', 'Download/.скрытый.zip');

      expect(await counts(), <String, int>{
        p.join('Download', 'Литература.zip'): 4,
      });
    });

    test('SNO-ALG-LIT-02: отмена останавливает обход', () async {
      for (int i = 0; i < 5; i++) {
        await place('shelf_stored.zip', 'Папка $i/Литература.zip');
      }
      final List<FoundArchive> found = <FoundArchive>[];
      int directories = 0;

      await scanForArchives(
        roots: <String>[root.path],
        onArchive: found.add,
        onDirectory: (String directory, int visited) => directories = visited,
        isCancelled: () => directories >= 2,
      );

      // Точное число здесь не важно: важно, что обход слушается и не
      // идёт до конца.
      expect(found.length, lessThan(5));
    });
  });

  group('SNO-ALG-LIT-02: с чего обход начинает', () {
    test('SNO-ALG-LIT-02: «Загрузки» и «Документы» — первыми', () async {
      await place('shelf_stored.zip', 'Aaa/первая по алфавиту.zip');
      await place('shelf_stored.zip', 'Documents/в документах.zip');
      await place('shelf_stored.zip', 'Download/в загрузках.zip');
      await place('shelf_stored.zip', 'Zzz/последняя по алфавиту.zip');

      final List<String> order = <String>[
        for (final FoundArchive archive in await search()) archive.name,
      ];

      expect(order, hasLength(4));
      // Как бы папки ни лежали на диске.
      expect(order[0], 'в загрузках.zip');
      expect(order[1], 'в документах.zip');
    });

    test('SNO-ALG-LIT-02: «Загрузки» раньше архива, лежащего глубже', () async {
      await place('shelf_stored.zip', 'Download/в загрузках.zip');
      await place('shelf_stored.zip', 'Zzz/Download/глубже.zip');

      final List<String> order = <String>[
        for (final FoundArchive archive in await search()) archive.name,
      ];

      expect(order, <String>['в загрузках.zip', 'глубже.zip']);
    });
  });

  group('SNO-ALG-LIT-02: поиск в изоляте', () {
    // Время здесь настоящее — это обычный тест, не widget-тест, — и
    // изолят в нём живёт так же, как на устройстве.
    test('SNO-ALG-LIT-02: находки доходят, поток закрывается сам', () async {
      await place('shelf_stored.zip', 'Download/Литература.zip');
      await place('no_books.zip', 'Download/фото.zip');

      final List<FoundArchive> found = await findArchivesInIsolate(<String>[
        root.path,
      ]).toList();

      expect(found.single.name, 'Литература.zip');
      expect(found.single.books, 4);
      expect(
        found.single.path,
        p.join(root.path, 'Download', 'Литература.zip'),
      );
    });

    test('SNO-ALG-LIT-02: упавший изолят закрывает поток ошибкой', () async {
      final List<Object> errors = <Object>[];
      final List<FoundArchive> found = await findArchivesInIsolate(
        <String>[root.path],
        entryPoint: crashingSearch,
      ).handleError((Object error) => errors.add(error)).toList();

      expect(found, isEmpty);
      expect(errors.single, isA<ScanFailure>());
      expect((errors.single as ScanFailure).reason, contains('диск отвалился'));
    });
  });
}
