import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/archive_scan.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/library/book_card.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-01…03, SNO-F-LIT-02, SNO-F-LIT-03: приложение в сборе.
///
/// Флаги ветви — константы сборки, поэтому один прогон тестов видит
/// одно приложение из трёх. Основной прогон (`flutter test`) проверяет
/// здесь, что тестового в основном приложении нет; прогоны ветвей
/// (`flutter test test/sno --dart-define=SNO_BRANCH=I` и `II`) — что
/// собранная ветвь выглядит и ведёт себя как ветвь. Группа не своего
/// прогона пропускается.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  const String mainOnly = 'прогон ветви: проверяется основным прогоном';
  const String branchOnly =
      'основной прогон: проверяется прогонами ветвей '
      '(--dart-define=SNO_BRANCH=I и II)';

  Future<void> pumpApp(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      MemoriaApp(themeController: ThemeController(), services: services),
    );
    await tester.pumpAndSettle();
  }

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

  // Узкий и очень высокий экран: настройки помещаются целиком, и строку
  // сборки в конце списка не надо искать прокруткой.
  const Size tall = Size(500, 2400);

  group('SNO-F-CFG-01: основная сборка', () {
    testWidgets('SNO-F-CFG-01: раздела «Тестирование» в ней нет', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('nav-testing')), findsNothing);
      expect(find.text('Тестирование'), findsNothing);
      expect(find.byType(TestingScreen), findsNothing);
      // Своё у основного приложения на месте.
      expect(find.byKey(const Key('nav-library')), findsOneWidget);
      expect(find.byKey(const Key('nav-device')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsOneWidget);
      expect(find.byKey(const Key('library-open-file')), findsOneWidget);
      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.title, 'Memoria LLM HB');

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-01: строка сборки — без ветви и флагов', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, tall);
      await pumpApp(tester, testServices(data: data));
      await open(tester, 'settings');

      expect(find.byKey(const Key('build-label')), findsOneWidget);
      expect(find.textContaining('ветвь'), findsNothing);
      expect(find.textContaining('флаги'), findsNothing);

      await unmount(tester);
    });
  }, skip: Sno.enabled ? mainOnly : false);

  group('SNO-F-CFG-01…03: сборка ветви', () {
    testWidgets('SNO-F-CFG-03: разделы — «Полка · Тестирование · Настройки»', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('nav-device')), findsNothing);
      expect(find.text('Устройство'), findsNothing);
      final double shelf = tester
          .getCenter(find.byKey(const Key('nav-library')))
          .dx;
      final double testing = tester
          .getCenter(find.byKey(const Key('nav-testing')))
          .dx;
      final double settings = tester
          .getCenter(find.byKey(const Key('nav-settings')))
          .dx;
      expect(shelf, lessThan(testing));
      expect(testing, lessThan(settings));

      await open(tester, 'testing');
      expect(find.byType(TestingScreen), findsOneWidget);
      expect(find.byKey(const Key('sno-device')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-01: имя приложения и строка сборки — ветви', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, tall);
      await pumpApp(tester, testServices(data: data));

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.title, 'Memoria · СНО2026 · ${Sno.branch}');

      await open(tester, 'testing');
      expect(find.textContaining('ветвь ${Sno.branch} · '), findsOneWidget);

      await open(tester, 'settings');
      expect(find.byKey(const Key('build-label')), findsOneWidget);
      expect(find.textContaining('ветвь ${Sno.branch} · '), findsOneWidget);
      expect(find.textContaining('флаги: запись, литература'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-02: книг устройства не ищут, доступ не просят', (
      WidgetTester tester,
    ) async {
      int scans = 0;
      int searches = 0;
      final FakeStorageAccess access = FakeStorageAccess(
        current: StorageAccessState.denied,
      );
      await data.library.save(testBook());
      await pumpApp(
        tester,
        testServices(
          data: data,
          access: access,
          scanRunner: (List<String> roots) {
            scans++;
            return fakeScan(const <ScannedFile>[]);
          },
          archiveSearch: (List<String> roots) {
            searches++;
            return const Stream<FoundArchive>.empty();
          },
        ),
      );
      await settle(tester);

      // Ни при старте, ни при открытии полки, ни в одном из разделов.
      for (final String section in <String>['testing', 'settings', 'library']) {
        await open(tester, section);
      }

      expect(scans, 0, reason: 'книги устройства в ветви не ищутся');
      // SNO-F-LIT-03: архив ищет только блок «Для экспериментатора», и
      // доступ просит только его кнопка.
      expect(searches, 0, reason: 'архивы не ищутся, пока блок не раскрыт');
      expect(access.requests, 0, reason: 'доступ к файлам не просится');

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-02: с полки на «Устройство» не уйти', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('library-empty-branch')), findsOneWidget);
      expect(find.byKey(const Key('library-open-file')), findsNothing);
      expect(find.byKey(const Key('library-open-file-empty')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-02: свой PDF из «Тестирования» на полку не встаёт', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        testServices(
          data: data,
          picked: const PickedFile(
            name: 'Анатомия.pdf',
            path: '/picked/Анатомия.pdf',
          ),
        ),
      );

      await open(tester, 'testing');
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sno-add-archive')));
      await settle(tester);

      // Решение П3: книги приходят только архивом литературы.
      expect(await data.library.books(), isEmpty);
      expect(
        find.textContaining('Не добавлено: «Анатомия.pdf».'),
        findsOneWidget,
      );
      await tester.tap(find.text('Понятно'));
      await settle(tester);

      await open(tester, 'library');
      expect(find.byKey(const Key('library-empty-branch')), findsOneWidget);
      expect(find.byType(AddBookCard), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIT-03: архивы устройства видны в «Тестировании»', (
      WidgetTester tester,
    ) async {
      final List<List<String>> searches = <List<String>>[];
      await pumpApp(
        tester,
        testServices(
          data: data,
          archiveSearch: (List<String> roots) {
            searches.add(roots);
            return Stream<FoundArchive>.fromIterable(<FoundArchive>[
              FoundArchive(
                path: '/device/Download/Литература.zip',
                size: 1024 * 1024,
                modifiedAt: DateTime.utc(2026, 10, 4, 12),
                books: 21,
              ),
            ]);
          },
        ),
      );

      await open(tester, 'testing');
      expect(searches, isEmpty);
      await tester.tap(find.text('Для экспериментатора'));
      await settle(tester);

      expect(searches, hasLength(1));
      expect(find.text('Литература.zip'), findsOneWidget);
      expect(find.text('21 книга · 1,0 МБ · Download'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('BUG-46: книгу с пропавшим файлом к своему PDF не привязать', (
      WidgetTester tester,
    ) async {
      // Копия книги пропала из папки приложения: на ПК её можно удалить
      // руками. Решение П3: свои PDF в сборке ветви не добавляются —
      // значит, и выбрать «файл заново» у такой книги нельзя.
      final Book book = testBook();
      await data.library.save(book);
      await pumpApp(
        tester,
        testServices(
          data: data,
          opener: FakeDocumentOpener(
            FakeReaderDocument(pages: <String>['текст']),
            failure: DocumentOpenException(
              DocumentProblem.missing,
              book.source,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await settle(tester);

      expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
      expect(find.byKey(const Key('reader-relink')), findsNothing);
      expect(find.text('Выбрать файл заново'), findsNothing);
      expect(find.byKey(const Key('reader-readd-archive')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: «назад» из «Тестирования» ведёт на полку', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data));

      await open(tester, 'testing');
      expect(find.byKey(const Key('library-shelf')), findsNothing);

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(find.byKey(const Key('library-shelf')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: на широком окне разделы стоят наверху', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, const Size(1280, 800));
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('nav-top')), findsOneWidget);
      expect(find.byKey(const Key('nav-bottom')), findsNothing);
      expect(find.byKey(const Key('nav-device')), findsNothing);
      final double testing = tester
          .getTopRight(find.byKey(const Key('nav-testing')))
          .dx;
      final double settings = tester
          .getTopLeft(find.byKey(const Key('nav-settings')))
          .dx;
      expect(testing, lessThan(1280 / 2));
      expect(settings, greaterThan(1280 / 2));

      await open(tester, 'testing');
      expect(find.byType(TestingScreen), findsOneWidget);

      await unmount(tester);
    });
  }, skip: Sno.enabled ? false : branchOnly);
}
