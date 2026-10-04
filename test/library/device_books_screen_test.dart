import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/device_files.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';
import 'package:memoria/ui/library/device_book_card.dart';
import 'package:memoria/ui/library/device_books_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
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
      // Название встречается дважды на карточку: подписью под обложкой и
      // на самой подложке, пока обложка не нарисована.
      expect(find.text('Онегин.pdf'), findsWidgets);

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
      expect(find.text('Онегин.pdf'), findsWidgets);
      expect(find.text('Гладиатор.pdf'), findsNothing);

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

  group('F-DEV-13: скан назван сканом', () {
    const String path = '/device/Книги/Атлас.pdf';

    testWidgets('F-DEV-13: скан помечен на карточке', (
      WidgetTester tester,
    ) async {
      // Ни на одной странице текста нет — разборка это увидит.
      await pumpScreen(
        tester,
        testServices(
          data: data,
          document: FakeReaderDocument.blank(3),
          onDevice: <ScannedFile>[onDisk(path)],
        ),
      );

      expect(find.byKey(const Key('device-scan-$path')), findsOneWidget);
      expect(find.text('скан'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-DEV-13: книга с текстом метки не получает', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        testServices(data: data, onDevice: <ScannedFile>[onDisk(path)]),
      );

      expect(find.byType(DeviceBookCard), findsOneWidget);
      expect(find.text('скан'), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-DEV-13: при добавлении скана сказано, что в нём не так', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        testServices(
          data: data,
          document: FakeReaderDocument.blank(3),
          onDevice: <ScannedFile>[onDisk(path)],
        ),
      );

      await tester.tap(find.byKey(const Key('device-card-$path')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-add')));
      await tester.pumpAndSettle();

      expect((await data.library.books()).single.hasTextLayer, isFalse);
      expect(find.textContaining('скан: текст не распознан'), findsOneWidget);
      expect(
        find.textContaining('выделение, поиск и функции'),
        findsOneWidget,
      );

      await unmount(tester);
    });
  });

  group('BUG-16: оборванный обход', () {
    testWidgets('BUG-16: причина названа, и обход можно повторить', (
      WidgetTester tester,
    ) async {
      final ScannedFile file = onDisk('/device/Книги/Онегин.pdf');
      Stream<ScanEvent> broken() async* {
        throw const ScanFailure('нет доступа к папке');
      }

      final List<Stream<ScanEvent>> runs = <Stream<ScanEvent>>[
        broken(),
        fakeScan(<ScannedFile>[file]),
      ];
      await pumpScreen(
        tester,
        testServices(
          data: data,
          scanRunner: (List<String> roots) => runs.removeAt(0),
        ),
      );

      // Прежде здесь вечно висело «Смотрим устройство…».
      expect(find.byKey(const Key('device-scan-failure')), findsOneWidget);
      expect(find.textContaining('нет доступа к папке'), findsOneWidget);
      expect(find.textContaining('Смотрим устройство'), findsNothing);
      // И пустой список не выдаётся за «PDF не нашлось»: обход не дошёл.
      expect(find.textContaining('PDF на устройстве не нашлось'), findsNothing);
      expect(find.textContaining('Обход устройства прервался'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-rescan')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('device-scan-failure')), findsNothing);
      expect(find.byType(DeviceBookCard), findsOneWidget);

      await unmount(tester);
    });
  });

  group('F-APP-02: раздел «Устройство»', () {
    /// Обход, который идёт, пока его не остановят: по событию за раз.
    late List<StreamController<ScanEvent>> feeds;

    setUp(() => feeds = <StreamController<ScanEvent>>[]);
    tearDown(() async {
      for (final StreamController<ScanEvent> feed in feeds) {
        await feed.close();
      }
    });

    AppServices endless() {
      return testServices(
        data: data,
        scanRunner: (List<String> roots) {
          final StreamController<ScanEvent> feed =
              StreamController<ScanEvent>();
          feeds.add(feed);
          return feed.stream;
        },
      );
    }

    Future<void> pumpSection(
      WidgetTester tester,
      AppServices services, {
      bool visible = true,
      bool paused = false,
      String? categoryId,
      VoidCallback? onClearCategory,
      VoidCallback? onAdded,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceBooksScreen(
            services: services,
            section: true,
            visible: visible,
            paused: paused,
            categoryId: categoryId,
            onClearCategory: onClearCategory,
            onAdded: onAdded,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('F-APP-02: у раздела своё название', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, testServices(data: data));

      expect(find.text('Устройство'), findsOneWidget);
      expect(find.text('Книги на устройстве'), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-APP-02: уход в другой раздел обход не останавливает', (
      WidgetTester tester,
    ) async {
      final AppServices services = endless();
      await pumpSection(tester, services);
      expect(services.deviceLibrary.isScanning, isTrue);

      await pumpSection(tester, services, visible: false);

      expect(services.deviceLibrary.isScanning, isTrue);
      expect(feeds.length, 1, reason: 'обход тот же, а не новый');

      await unmount(tester);
    });

    testWidgets('F-APP-02: при идущем обходе возвращение нового не заводит', (
      WidgetTester tester,
    ) async {
      final AppServices services = endless();
      await pumpSection(tester, services);
      await pumpSection(tester, services, visible: false);
      await pumpSection(tester, services);

      expect(feeds.length, 1);
      expect(services.deviceLibrary.isScanning, isTrue);

      await unmount(tester);
    });

    testWidgets('F-APP-02: возвращение после обхода — новый обход', (
      WidgetTester tester,
    ) async {
      int scans = 0;
      final AppServices services = testServices(
        data: data,
        scanRunner: (List<String> roots) {
          scans++;
          return fakeScan(<ScannedFile>[onDisk('/device/Онегин.pdf')]);
        },
      );
      await pumpSection(tester, services);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(scans, 1);

      await pumpSection(tester, services, visible: false);
      expect(scans, 1);
      await pumpSection(tester, services);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(scans, 2);
      expect(find.byType(DeviceBookCard), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-APP-02: открытая книга останавливает обход', (
      WidgetTester tester,
    ) async {
      final AppServices services = endless();
      await pumpSection(tester, services);
      feeds.single.add(
        ScanEvent(
          file: onDisk('/device/Онегин.pdf'),
          directory: '',
          visited: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Смотрим устройство:'), findsOneWidget);

      await pumpSection(tester, services, paused: true);

      expect(services.deviceLibrary.isScanning, isFalse);
      // Строка хода убрана: обхода, о котором она говорила, больше нет.
      expect(find.textContaining('Смотрим устройство:'), findsNothing);
      // BUG-06: остановка ничего не испортила — найденное записано.
      expect((await data.deviceFiles.files()).single.missing, isFalse);

      // Книгу закрыли — обход начинается заново.
      await pumpSection(tester, services);
      expect(feeds.length, 2);
      expect(services.deviceLibrary.isScanning, isTrue);

      // Разборка найденного файла идёт с паузами — даём ей кончиться.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('F-APP-02: раздел не на виду обход не начинает', (
      WidgetTester tester,
    ) async {
      final AppServices services = endless();
      await pumpSection(tester, services, visible: false);
      expect(feeds, isEmpty);

      await pumpSection(tester, services);
      expect(feeds.length, 1);

      await unmount(tester);
    });

    testWidgets('F-APP-02: названа категория, в которую лягут книги', (
      WidgetTester tester,
    ) async {
      await data.categories.save(
        BookCategory(
          id: 'study',
          title: 'Учёба',
          position: 0,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      );
      int cleared = 0;
      const String path = '/device/Книги/Онегин.pdf';
      await pumpSection(
        tester,
        testServices(data: data, onDevice: <ScannedFile>[onDisk(path)]),
        categoryId: 'study',
        onClearCategory: () => cleared++,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('device-target')), findsOneWidget);
      expect(find.textContaining('«Учёба»'), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-target-clear')));
      await tester.pumpAndSettle();
      expect(cleared, 1);

      // Книга ложится в названную категорию.
      await tester.tap(find.byKey(const Key('device-card-$path')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-add')));
      await tester.pumpAndSettle();
      expect((await data.library.books()).single.categoryId, 'study');

      await unmount(tester);
    });

    testWidgets('F-APP-02: без категории строки о ней нет', (
      WidgetTester tester,
    ) async {
      await pumpSection(tester, testServices(data: data));

      expect(find.byKey(const Key('device-target')), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-APP-02: добавленные книги — повод показать полку', (
      WidgetTester tester,
    ) async {
      int added = 0;
      const String path = '/device/Книги/Онегин.pdf';
      await pumpSection(
        tester,
        testServices(data: data, onDevice: <ScannedFile>[onDisk(path)]),
        onAdded: () => added++,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('device-card-$path')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-add')));
      await tester.pumpAndSettle();

      expect(added, 1);
      expect((await data.library.books()).length, 1);

      await unmount(tester);
    });
  });
}
