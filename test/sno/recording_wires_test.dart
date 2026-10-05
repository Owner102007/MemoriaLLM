import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/library/library_screen.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// Шаг 18, SNO-F-REC-02: провода от экранов к журналу записи.
///
/// Сессия настоящая — на памяти и подменённом времени, — а экраны те
/// же, что в приложении: полка, экран чтения, «Тестирование». Здесь
/// проверяется, что действие на экране ложится в журнал своим видом, в
/// своём порядке и со своими данными. Выделение на листе в widget-тестах
/// не строится — его действия проверены в `selection_text_test.dart`.
void main() {
  const String branchOnly =
      'основной прогон: проверяется прогонами ветвей '
      '(--dart-define=SNO_BRANCH=I и II)';

  late AppData data;
  late SessionKit kit;

  setUp(() async {
    data = await openTestData();
    kit = SessionKit(status: FakeDeviceStatus(battery: 84, free: 1288490189));
    await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
  });
  tearDown(() async {
    kit.session.dispose();
    await data.close();
  });

  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  /// Служебные события записи: к действиям участника они не относятся.
  const Set<String> service = <String>{
    'session.heartbeat',
    'app.state',
    'clock.resync',
  };

  /// События журнала без служебных, по порядку.
  List<Map<String, Object?>> acts() {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(kit.folder))
        if (!service.contains(event['type'])) event,
    ];
  }

  List<Object?> types() {
    return <Object?>[
      for (final Map<String, Object?> event in acts()) event['type'],
    ];
  }

  Map<String, Object?> dataOf(Map<String, Object?> event) {
    return event['data']! as Map<String, Object?>;
  }

  List<Map<String, Object?>> only(String type) {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in acts())
        if (event['type'] == type) event,
    ];
  }

  /// Даёт журналу лечь на диск: его сбрасывает секунда записи.
  Future<void> written(WidgetTester tester) async {
    kit.session.tick();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  String textOf(WidgetTester tester, String key) {
    return tester.widget<Text>(find.byKey(Key(key))).data!;
  }

  group('SNO-F-REC-02: полка и книга', () {
    Future<void> pumpShelf(
      WidgetTester tester,
      AppServices services, {
      required bool visible,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            services: services,
            canAddBooks: false,
            defaultSort: ShelfSort.manual,
            titleSearch: true,
            models: false,
            locked: true,
            visible: visible,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<AppServices> twoBooks() async {
      await data.library.save(testBook());
      await data.library.save(
        testBook(id: 'book-2', title: 'Анатомия человека', hash: 'hash-2'),
      );
      return testServices(
        data: data,
        recording: kit.session,
        document: FakeReaderDocument(
          pages: <String>['один', 'два', 'три', 'четыре'],
        ),
      );
    }

    testWidgets('SNO-F-REC-02: нашёл книгу поиском, открыл, полистал, закрыл '
        '— всё в журнале по порядку', (WidgetTester tester) async {
      final AppServices services = await twoBooks();
      await pumpShelf(tester, services, visible: false);
      await kit.session.start(code);
      // Полка снова перед участником — как после старта записи.
      await pumpShelf(tester, services, visible: true);

      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      // Запрос набирают по буквам: в журнал идёт то, что простояло.
      await tester.enterText(find.byKey(const Key('shelf-search-field')), 'ан');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(
        find.byKey(const Key('shelf-search-field')),
        'анат',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('shelf-search-hit-book-2')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await tester.pumpAndSettle();
      await written(tester);

      expect(types(), <String>[
        'recording.start',
        'shelf.shown',
        'search.query',
        'search.result.open',
        'search.close',
        'book.open',
        'page.shown',
        'page.shown',
        'page.shown',
        'book.close',
      ]);
      final Map<String, Object?> shelf = dataOf(only('shelf.shown').single);
      expect(shelf['books'], 2);
      expect(shelf['locked'], isTrue);
      expect(shelf['sort'], 'manual');
      expect(dataOf(only('search.query').single), <String, Object?>{
        'scope': 'shelf',
        'text': 'анат',
        'hits': 1,
      });
      final Map<String, Object?> found = dataOf(
        only('search.result.open').single,
      );
      expect(found['rank'], 1);
      expect(found['of'], 1);
      expect(found['book'], 'hash-2');
      final Map<String, Object?> opened = only('book.open').single;
      expect(opened['book'], 'hash-2');
      expect(dataOf(opened), <String, Object?>{
        'via': 'shelf_search',
        'visit': 1,
        'title': 'Анатомия человека',
        'pages': 4,
        'page': 1,
      });
      final List<Map<String, Object?>> shown = only('page.shown');
      expect(shown.map((Map<String, Object?> event) => event['page']), <int>[
        1,
        2,
        3,
      ]);
      expect(
        shown.map((Map<String, Object?> event) => dataOf(event)['cause']),
        <String>['open', 'key', 'key'],
      );
      expect(shown.first['book'], 'hash-2');
      expect(shown.first['strip'], 1);
      expect(shown.first['mode'], 'full');
      expect(dataOf(shown.last)['from'], <String, Object?>{
        'page': 2,
        'strip': 1,
      });
      // Закрытие несёт страницу, на которой книгу закрыли.
      expect(only('book.close').single['page'], 3);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-02: книга с полки напрямую — путь `shelf`, второе '
        'обращение — номером', (WidgetTester tester) async {
      final AppServices services = await twoBooks();
      await kit.session.start(code);
      await pumpShelf(tester, services, visible: true);

      for (int visit = 1; visit <= 2; visit++) {
        await tester.tap(find.byKey(const Key('library-book-book-1')));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
        await tester.pumpAndSettle();
      }

      await written(tester);
      final List<Map<String, Object?>> opened = only('book.open');
      expect(opened, hasLength(2));
      expect(dataOf(opened[0])['via'], 'shelf');
      expect(dataOf(opened[0])['visit'], 1);
      expect(dataOf(opened[1])['visit'], 2);
      expect(only('book.close'), hasLength(2));
      // Поиском не пользовались — событий поиска нет.
      expect(only('search.query'), isEmpty);
      expect(only('search.close'), isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-02: запись не идёт — полка и книга работают, '
        'журнал пуст', (WidgetTester tester) async {
      final AppServices services = await twoBooks();
      await pumpShelf(tester, services, visible: false);
      await pumpShelf(tester, services, visible: true);
      await tester.tap(find.byKey(const Key('library-book-book-1')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await tester.pumpAndSettle();

      expect(kit.store.journals, isEmpty);
      // Место чтения при этом известно: запись может начаться в любой миг.
      expect(kit.session.context.book, isNull);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-02: экран чтения', () {
    FakeReaderDocument threes() {
      return FakeReaderDocument(
        pages: <String>[
          'вступление',
          'здесь встречается тройка',
          'ничего',
          'ничего',
          'и снова тройка',
          'окончание',
        ],
      );
    }

    Future<void> pumpReader(
      WidgetTester tester, {
      FakeReaderDocument? document,
      DocumentOpener? opener,
    }) async {
      final Book book = testBook();
      await data.library.save(book);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: book,
            models: false,
            services: testServices(
              data: data,
              recording: kit.session,
              document: document ?? threes(),
              opener: opener,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ReaderScaffold scaffoldOf(WidgetTester tester) =>
        tester.widget<ReaderScaffold>(find.byType(ReaderScaffold));

    ReaderScaffoldState stateOf(WidgetTester tester) =>
        tester.state<ReaderScaffoldState>(find.byType(ReaderScaffold));

    testWidgets('SNO-F-REC-02: поиск по книге и переход к найденному — в '
        'журнале', (WidgetTester tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize =
          const Size(1280, 800) * tester.view.devicePixelRatio;
      await kit.session.start(code);
      await pumpReader(tester);

      stateOf(tester).openSearch();
      await tester.pumpAndSettle();
      await scaffoldOf(tester).search.start('тройка');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-hit-1')));
      await tester.pumpAndSettle();
      stateOf(tester).closeSearch();
      await tester.pumpAndSettle();
      await written(tester);

      expect(types(), <String>[
        'recording.start',
        'book.open',
        'page.shown',
        'panel.open',
        'search.query',
        'search.result.open',
        'page.shown',
        'search.close',
      ]);
      expect(dataOf(only('panel.open').single), <String, Object?>{
        'panel': 'search',
      });
      final Map<String, Object?> query = dataOf(only('search.query').single);
      expect(query['scope'], 'book');
      expect(query['text'], 'тройка');
      expect(query['hits'], 2);
      expect(query['ms'], isA<int>());
      final Map<String, Object?> found = dataOf(
        only('search.result.open').single,
      );
      expect(found['scope'], 'book');
      expect(found['rank'], 2);
      expect(found['of'], 2);
      expect(found['page'], 5);
      expect(found['by'], 'list');
      final Map<String, Object?> jumped = only('page.shown').last;
      expect(jumped['page'], 5);
      expect(dataOf(jumped)['cause'], 'search');
      expect(dataOf(only('search.close').single), <String, Object?>{
        'scope': 'book',
      });

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-02: светофильтр — событием сразу, ползунок — '
        'когда остановился', (WidgetTester tester) async {
      await kit.session.start(code);
      await pumpReader(tester);
      final ReaderController controller = scaffoldOf(tester).controller;
      final ReadingFilter next =
          controller.settings.filter == ReadingFilter.sepia
          ? ReadingFilter.warm
          : ReadingFilter.sepia;

      await controller.setFilter(next);
      await tester.pump();
      // Ползунок тянут: значение меняется много раз подряд.
      for (final double value in <double>[0.2, 0.25, 0.3]) {
        await controller.setDimOutside(value, persist: false);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await written(tester);
      expect(
        only('settings.change').where(
          (Map<String, Object?> event) =>
              (dataOf(event)['changed']! as Map<String, Object?>).containsKey(
                'dim_outside',
              ),
        ),
        isEmpty,
        reason: 'ползунок ещё не остановился',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await written(tester);

      final Map<String, Object?> filter = dataOf(only('view.filter').single);
      expect(filter['filter'], next.name);
      final List<Map<String, Object?>> slid = <Map<String, Object?>>[
        for (final Map<String, Object?> event in only('settings.change'))
          dataOf(event)['changed']! as Map<String, Object?>,
      ];
      expect(slid, hasLength(1));
      expect(slid.single['dim_outside'], 0.3);
      expect(dataOf(only('settings.change').single)['scope'], 'book');

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-02: книга не открылась — участнику показана '
        'ошибка, и это записано', (WidgetTester tester) async {
      await kit.session.start(code);
      await pumpReader(
        tester,
        opener: FakeDocumentOpener(
          threes(),
          failure: const DocumentOpenException(
            DocumentProblem.missing,
            FilePathSource('/books/book-1.pdf'),
          ),
        ),
      );

      expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
      await written(tester);
      expect(types(), <String>['recording.start', 'error.shown']);
      expect(dataOf(only('error.shown').single), <String, Object?>{
        'what': 'book_open',
        'problem': 'missing',
        'book': 'hash-1',
      });

      await unmount(tester);
    });
  });

  group('SNO-F-CFG-03: «Блок №» в «Тестировании»', () {
    Future<void> pumpTesting(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, recording: kit.session),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-CFG-03: блок начат и закончен; длительность и '
        'отлучка — на экране завершения', (WidgetTester tester) async {
      await pumpTesting(tester);
      // Запись не идёт — строки «Блок №» нет.
      expect(find.byKey(const Key('sno-block')), findsNothing);

      await kit.session.start(code);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-block')), findsOneWidget);
      expect(textOf(tester, 'sno-block-number'), '1');
      // Номер можно поправить.
      await tap(tester, 'sno-block-more');
      expect(textOf(tester, 'sno-block-number'), '2');
      await tap(tester, 'sno-block-less');
      expect(textOf(tester, 'sno-block-number'), '1');

      await tap(tester, 'sno-block-start');
      expect(find.byKey(const Key('sno-block')), findsNothing);
      expect(find.byKey(const Key('sno-block-running')), findsOneWidget);
      kit.run(65);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-block-passed'), 'Блок 1 идёт · 01:05');

      await tap(tester, 'sno-block-end');
      // Следующему блоку предложен следующий номер.
      expect(textOf(tester, 'sno-block-number'), '2');

      kit.session.appState('inactive');
      kit.time.pass(const Duration(seconds: 9));
      kit.session.appState('resumed');
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-block')), findsNothing);

      await tap(tester, 'sno-session-finish');
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(textOf(tester, 'sno-finish-blocks'), 'Блоки: 1 — 1:05');
      expect(
        textOf(tester, 'sno-finish-away'),
        'Уходил из приложения: 1 раз, 0:09',
      );
      expect(only('block.start'), hasLength(1));
      expect(dataOf(only('block.end').single), <String, Object?>{
        'n': 1,
        'duration_ms': 65000,
        'by': 'experimenter',
      });

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: блоков не отмечали, участник не уходил — '
        'лишних строк на экране завершения нет', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();

      await tap(tester, 'sno-session-finish');
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-events')), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-blocks')), findsNothing);
      expect(find.byKey(const Key('sno-finish-away')), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-02: приложение в сборе', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-REC-02: переходы между разделами, показ полки и '
        'смена темы — в журнале', (WidgetTester tester) async {
      await data.library.save(testBook());
      final ThemeController theme = ThemeController();
      await tester.pumpWidget(
        MemoriaApp(
          themeController: theme,
          services: testServices(data: data, recording: kit.session),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('nav-testing')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('sno-record-start')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('sno-code-confirm')));
      await settle(tester);
      expect(kit.session.recording, isTrue);

      await tester.tap(find.byKey(const Key('nav-settings')));
      await settle(tester);
      theme.value = AppThemeId.sepia;
      await settle(tester);
      await tester.tap(find.byKey(const Key('nav-library')));
      await settle(tester);
      await written(tester);

      expect(types(), <String>[
        'recording.start',
        'nav.screen',
        'shelf.shown',
        'nav.screen',
        'settings.change',
        'nav.screen',
        'shelf.shown',
      ]);
      final List<Map<String, Object?>> moves = only('nav.screen');
      expect(dataOf(moves[0]), <String, Object?>{
        'from': 'testing',
        'to': 'shelf',
      });
      expect(dataOf(moves[1]), <String, Object?>{
        'from': 'shelf',
        'to': 'settings',
      });
      expect(dataOf(moves[2]), <String, Object?>{
        'from': 'settings',
        'to': 'shelf',
      });
      expect(dataOf(only('settings.change').single), <String, Object?>{
        'key': SettingsKeys.theme,
        'value': 'sepia',
      });
      expect(only('shelf.shown').first['screen'], 'shelf');

      await unmount(tester);
    });
  }, skip: Sno.recording ? false : branchOnly);
}
