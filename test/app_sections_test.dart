import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/library/device_book_card.dart';

import 'data/test_data.dart';
import 'support/shown_reading.dart';
import 'support/test_services.dart';

/// F-APP-02: три раздела главной навигации в собранном приложении.
///
/// Правило места навигации проверено числами в
/// `test/domain/sections_test.dart`, сам раздел «Устройство» — в
/// `test/library/device_books_screen_test.dart`. Здесь — то, что видно
/// только в сборе: разделы помнят себя, «+» полки ведёт в раздел, обход
/// не начинается при запуске и стоит, пока читают книгу.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  ScannedFile onDisk(String path) {
    return ScannedFile(
      path: path,
      size: 900,
      modifiedAt: DateTime.utc(2026, 9, 1),
    );
  }

  Future<void> pumpApp(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      MemoriaApp(themeController: ThemeController(), services: services),
    );
    await tester.pumpAndSettle();
  }

  /// Даёт обходу и разборке устройства доработать: они идут своими
  /// шагами с паузами, и между двумя из них может не оказаться кадра.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String section) async {
    await tester.tap(find.byKey(Key('nav-$section')));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  void resize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
  }

  double shelfOffset(WidgetTester tester) {
    // Первый по дереву — сам список категорий; сетки внутри него тоже
    // прокручиваемые виджеты, но места у них нет.
    final Finder scrollable = find
        .descendant(
          of: find.byKey(const Key('library-shelf')),
          matching: find.byType(Scrollable),
        )
        .first;
    return tester.state<ScrollableState>(scrollable).position.pixels;
  }

  group('F-APP-02: три раздела', () {
    testWidgets('F-APP-02: «Устройство» — раздел, а не экран поверх полки', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[onDisk('/device/Книги/Онегин.pdf')],
        ),
      );

      await open(tester, 'device');

      expect(find.byType(DeviceBookCard), findsOneWidget);
      // Навигация на месте: из раздела уходят ею, а не стрелкой «назад».
      expect(find.byKey(const Key('nav-bottom')), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      final NavigatorState navigator = Navigator.of(
        tester.element(find.byType(HomeShell)),
      );
      expect(navigator.canPop(), isFalse, reason: 'поверх полки ничего нет');

      await unmount(tester);
    });

    testWidgets('F-APP-02: запуск приложения обход не начинает', (
      WidgetTester tester,
    ) async {
      int scans = 0;
      await pumpApp(
        tester,
        testServices(
          data: data,
          scanRunner: (List<String> roots) {
            scans++;
            return fakeScan(const <ScannedFile>[]);
          },
        ),
      );
      await settle(tester);
      expect(scans, 0, reason: 'до первого захода раздела нет вовсе');

      await open(tester, 'device');
      expect(scans, 1);

      await unmount(tester);
    });

    testWidgets('F-APP-02: поиск и отмеченное переживают уход из раздела', (
      WidgetTester tester,
    ) async {
      const String path = '/device/Книги/Онегин.pdf';
      await pumpApp(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[
            onDisk(path),
            onDisk('/device/Книги/Гладиатор.pdf'),
          ],
        ),
      );
      await open(tester, 'device');
      await tester.enterText(find.byKey(const Key('device-search')), 'онегин');
      await settle(tester);
      await tester.tap(find.byKey(const Key('device-card-$path')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceBookCard), findsOneWidget);
      expect(find.byKey(const Key('device-add')), findsOneWidget);

      await open(tester, 'settings');
      expect(find.byKey(const Key('device-search')), findsNothing);
      await open(tester, 'library');
      await open(tester, 'device');

      // Раздел остался там, где его оставили: запрос набран, список
      // сужен, книга отмечена.
      expect(find.text('онегин'), findsOneWidget);
      expect(find.byType(DeviceBookCard), findsOneWidget);
      expect(find.byKey(const Key('device-add')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-APP-02: полка помнит место прокрутки', (
      WidgetTester tester,
    ) async {
      for (int i = 0; i < 40; i++) {
        await data.library.save(
          testBook(id: 'book-$i', title: 'Книга $i', hash: 'hash-$i'),
        );
      }
      await pumpApp(tester, testServices(data: data));
      await tester.drag(
        find.byKey(const Key('library-shelf')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final double before = shelfOffset(tester);
      expect(before, greaterThan(0));

      await open(tester, 'settings');
      await open(tester, 'library');

      expect(shelfOffset(tester), before);

      await unmount(tester);
    });

    testWidgets('F-APP-02: «+» категории ведёт в раздел и называет её', (
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
      await data.library.save(testBook());
      await placeBook(data, 'book-1', 'study');
      const String path = '/device/Книги/Онегин.pdf';
      await pumpApp(
        tester,
        testServices(data: data, onDevice: <ScannedFile>[onDisk(path)]),
      );

      await tester.tap(find.byKey(const Key('library-add-study')));
      await settle(tester);

      expect(find.byKey(const Key('device-search')), findsOneWidget);
      expect(find.textContaining('«Учёба»'), findsOneWidget);

      // Добавленная книга ложится в названную категорию — и читателя
      // возвращают на полку: посмотреть, что получилось.
      await tester.tap(find.byKey(const Key('device-card-$path')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-add')));
      await settle(tester);

      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(find.byKey(const Key('device-search')), findsNothing);
      final List<Book> books = await data.library.books();
      expect(books.length, 2);
      expect(books.every((Book book) => book.categoryId == 'study'), isTrue);

      await unmount(tester);
    });

    testWidgets('F-APP-02: категорию можно снять; кнопка шапки её не зовёт', (
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
      await data.library.save(testBook());
      await placeBook(data, 'book-1', 'study');
      await pumpApp(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-add-study')));
      await settle(tester);
      expect(find.byKey(const Key('device-target')), findsOneWidget);

      await tester.tap(find.byKey(const Key('device-target-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-target')), findsNothing);

      // «+» называет категорию снова, кнопка в шапке полки — нет.
      await open(tester, 'library');
      await tester.tap(find.byKey(const Key('library-add-study')));
      await settle(tester);
      expect(find.byKey(const Key('device-target')), findsOneWidget);
      await open(tester, 'library');
      await tester.tap(find.byKey(const Key('library-open-file')));
      await settle(tester);
      expect(find.byKey(const Key('device-search')), findsOneWidget);
      expect(find.byKey(const Key('device-target')), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-APP-02: «назад» из раздела ведёт на полку', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data));

      for (final String section in <String>['device', 'settings']) {
        await open(tester, section);
        expect(find.byKey(const Key('library-shelf')), findsNothing);

        await tester.binding.handlePopRoute();
        await settle(tester);

        expect(
          find.byKey(const Key('library-shelf')),
          findsOneWidget,
          reason: 'назад из «$section»',
        );
      }

      await unmount(tester);
    });
  });

  group('F-APP-02: навигация на широком окне', () {
    testWidgets('F-APP-02: от 900 точек разделы стоят наверху', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, const Size(1280, 800));
      await pumpApp(
        tester,
        testServices(
          data: data,
          onDevice: <ScannedFile>[onDisk('/device/Книги/Онегин.pdf')],
        ),
      );

      expect(find.byKey(const Key('nav-top')), findsOneWidget);
      expect(find.byKey(const Key('nav-bottom')), findsNothing);
      // Полоса — у верхнего края окна, над шапкой раздела.
      expect(tester.getTopLeft(find.byKey(const Key('nav-top'))).dy, 0);

      // Разделы слева, настройки справа, середина оставлена вкладкам
      // книг (F-DESK-01).
      final double device = tester
          .getTopRight(find.byKey(const Key('nav-device')))
          .dx;
      final double settings = tester
          .getTopLeft(find.byKey(const Key('nav-settings')))
          .dx;
      expect(device, lessThan(1280 / 2));
      expect(settings, greaterThan(1280 / 2));

      await open(tester, 'device');
      expect(find.byType(DeviceBookCard), findsOneWidget);
      await open(tester, 'settings');
      expect(find.byKey(const Key('theme-sepia')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-APP-02: окно сузили — навигация внизу, раздел тот же', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, const Size(1280, 800));
      int scans = 0;
      await pumpApp(
        tester,
        testServices(
          data: data,
          scanRunner: (List<String> roots) {
            scans++;
            return fakeScan(<ScannedFile>[onDisk('/device/Онегин.pdf')]);
          },
        ),
      );
      await open(tester, 'device');
      await tester.enterText(find.byKey(const Key('device-search')), 'онегин');
      await settle(tester);
      expect(scans, 1);

      resize(tester, const Size(600, 800));
      await settle(tester);

      expect(find.byKey(const Key('nav-top')), findsNothing);
      expect(find.byKey(const Key('nav-bottom')), findsOneWidget);
      // Раздел не построен заново: запрос на месте, второго обхода нет.
      expect(find.text('онегин'), findsOneWidget);
      expect(scans, 1);

      await unmount(tester);
    });
  });

  group('F-APP-02: обход и открытая книга', () {
    testWidgets('F-APP-02: пока книгу читают, обход устройства стоит', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await data.library.save(testBook());
      final List<StreamController<ScanEvent>> feeds =
          <StreamController<ScanEvent>>[];
      // Потоки закрываются после теста, а не в нём: ожидание настоящего
      // будущего внутри widget-теста, где время подменено, не кончается.
      addTearDown(() async {
        for (final StreamController<ScanEvent> feed in feeds) {
          await feed.close();
        }
      });
      final AppServices services = testServices(
        data: data,
        scanRunner: (List<String> roots) {
          final StreamController<ScanEvent> feed =
              StreamController<ScanEvent>();
          feeds.add(feed);
          return feed.stream;
        },
      );
      await pumpApp(tester, services);

      // Обход начался в «Устройстве» и идёт, пока читатель на полке.
      await open(tester, 'device');
      await open(tester, 'library');
      expect(services.deviceLibrary.isScanning, isTrue);

      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await tester.pumpAndSettle();
      expect(services.deviceLibrary.isScanning, isFalse);

      // Книгу закрыли. Обход не идёт сам собой, пока раздел не открыли…
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(services.deviceLibrary.isScanning, isFalse);

      // …а в разделе начинается заново.
      await open(tester, 'device');
      expect(services.deviceLibrary.isScanning, isTrue);
      expect(feeds.length, 2);

      await unmount(tester);
    });

    testWidgets('SNO-F-IDX-04: пока книгу читают, проход по полке стоит', (
      WidgetTester tester,
    ) async {
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await data.library.save(testBook());
      final ShownReading reading = ShownReading(data);
      addTearDown(reading.dispose);
      final AppServices services = testServices(
        data: data,
        shelfReading: reading,
      );
      await pumpApp(tester, services);
      expect(reading.held, isFalse);

      // Книгу открыли: движок PDF отдан странице.
      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await tester.pumpAndSettle();
      expect(reading.held, isTrue);

      // Книгу закрыли: проход вправе продолжать.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(reading.held, isFalse);

      await unmount(tester);
    });
  });
}
