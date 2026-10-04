import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/library/book_card.dart';

import '../data/test_data.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-01…03, SNO-F-LIT-02: приложение в сборе.
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

    testWidgets('SNO-F-CFG-02: устройство не обходится, доступ не просится', (
      WidgetTester tester,
    ) async {
      int scans = 0;
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
        ),
      );
      await settle(tester);

      // Ни при старте, ни при открытии полки, ни в одном из разделов.
      for (final String section in <String>['testing', 'settings', 'library']) {
        await open(tester, section);
      }

      expect(scans, 0, reason: 'обход устройства в ветви не запускается');
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

    testWidgets('SNO-F-LIT-02: книга из «Тестирования» встаёт на полку', (
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
      await tester.tap(find.byKey(const Key('sno-add-pdf')));
      await settle(tester);

      final List<Book> books = await data.library.books();
      expect(books, hasLength(1));
      expect(books.single.categoryId, isNull);

      await open(tester, 'library');
      expect(
        find.byKey(Key('library-book-${books.single.id}')),
        findsOneWidget,
      );
      // И на полке с книгами добавления по-прежнему нет.
      expect(find.byType(AddBookCard), findsNothing);

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
