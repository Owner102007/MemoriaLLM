import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/device_files.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';
import 'package:memoria/ui/library/device_book_card.dart';
import 'package:memoria/ui/library/device_books_screen.dart';

import '../data/test_data.dart';
import '../support/test_services.dart';

/// Экран «Книги на устройстве».
///
/// Две проверки здесь главные и равноправные: экран работает с
/// разрешением и экран работает **без** него. Второе — не оговорка в
/// конце, а обещание сессии: отказ ничего не ломает.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  ScannedFile onDisk(String path, {int size = 900}) {
    return ScannedFile(
      path: path,
      size: size,
      modifiedAt: DateTime.utc(2026, 9, 1),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      MaterialApp(home: DeviceBooksScreen(services: services)),
    );
    // Двумя заходами намеренно. Обход и разборка идут своими шагами, и
    // между двумя из них может не оказаться ни одного запланированного
    // кадра — тогда `pumpAndSettle` считает, что всё улеглось, хотя книги
    // ещё не дошли до базы. Явный шаг времени даёт цепочке доработать.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Отпечаток, который получит файл после разборки.
  Future<String> hashOf(String path) async {
    final BookHandle handle = await const PathBytesStorage().open(
      FilePathSource(path),
    );
    try {
      return await bookFingerprint(handle);
    } finally {
      await handle.close();
    }
  }

  group('разрешения нет', () {
    testWidgets('экран объясняет, что ищем, что делаем и чего не делаем', (
      WidgetTester tester,
    ) async {
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpScreen(tester, testServices(data: data, access: access));

      expect(find.text('Найти книги на устройстве'), findsOneWidget);
      expect(find.textContaining('Ищем:'), findsOneWidget);
      expect(find.textContaining('Делаем:'), findsOneWidget);
      expect(find.textContaining('Не делаем:'), findsOneWidget);
      // И главное — что без разрешения приложение остаётся рабочим.
      expect(find.textContaining('Отказ ничего не ломает'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('кнопка ведёт к системному экрану', (
      WidgetTester tester,
    ) async {
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpScreen(tester, testServices(data: data, access: access));

      await tester.tap(find.byKey(const Key('device-grant')));
      await tester.pumpAndSettle();

      expect(access.requests, 1);

      await unmount(tester);
    });

    testWidgets('выбрать файлы вручную можно и без разрешения', (
      WidgetTester tester,
    ) async {
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpScreen(
        tester,
        testServices(
          data: data,
          access: access,
          batch: const <PickedFile>[
            PickedFile(path: '/выбранная.pdf', name: 'Выбранная.pdf'),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('device-pick-manually')));
      await tester.pumpAndSettle();

      expect((await data.library.books()).length, 1);

      await unmount(tester);
    });

    testWidgets('список файлов после отказа не хранится', (
      WidgetTester tester,
    ) async {
      // Держать перечень чужих файлов после того, как доступ к ним
      // отобрали, — ровно то, чего мы обещали не делать.
      await data.deviceFiles.saveFile(
        DeviceFileRecord(
          path: '/device/старая.pdf',
          size: 1000,
          modifiedAt: DateTime.utc(2026, 9, 1),
          seenAt: DateTime.utc(2026, 9, 1),
        ),
      );
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await pumpScreen(tester, testServices(data: data, access: access));

      expect(await data.deviceFiles.files(), isEmpty);

      await unmount(tester);
    });
  });

  group('разрешение есть', () {
    testWidgets('найденные книги показаны карточками', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[
            onDisk('/device/Книги/Онегин.pdf'),
            onDisk('/device/Книги/Гладиатор.pdf'),
          ],
        ),
      );

      expect(find.byType(DeviceBookCard), findsNWidgets(2));
      expect(find.text('Онегин.pdf'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('отмеченная книга встаёт на полку', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[onDisk('/device/Книги/Онегин.pdf')],
        ),
      );

      await tester.tap(
        find.byKey(const Key('device-card-/device/Книги/Онегин.pdf')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-add')));
      await tester.pumpAndSettle();

      final List<Book> books = await data.library.books();
      expect(books.length, 1);
      expect(
        books.single.source,
        const FilePathSource('/device/Книги/Онегин.pdf'),
      );

      await unmount(tester);
    });

    testWidgets('книга, уже стоящая на полке, помечена', (
      WidgetTester tester,
    ) async {
      const String path = '/device/Книги/Онегин.pdf';
      await data.library.save(testBook(hash: await hashOf(path)));
      await pumpScreen(
        tester,
        testServices(data: data, onDevice: <ScannedFile>[onDisk(path)]),
      );

      expect(find.text('на полке'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('поиск сужает список', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[
            onDisk('/device/Книги/Онегин.pdf'),
            onDisk('/device/Книги/Гладиатор.pdf'),
          ],
        ),
      );

      await tester.enterText(find.byKey(const Key('device-search')), 'онегин');
      await tester.pumpAndSettle();

      expect(find.byType(DeviceBookCard), findsOneWidget);
      expect(find.text('Онегин.pdf'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('пустой экран не молчит', (WidgetTester tester) async {
      await pumpScreen(tester, testServices(data: data));

      expect(
        find.textContaining('PDF на устройстве не нашлось'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('device-pick-empty')), findsOneWidget);

      await unmount(tester);
    });
  });
}
