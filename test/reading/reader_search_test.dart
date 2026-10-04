import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/book_text.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/full_screen.dart';
import 'package:memoria/domain/reading/page_text.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/search_dock.dart';
import 'package:memoria/domain/reading/volume_keys.dart';
import 'package:memoria/domain/reading/window_settle.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/page_text.dart';
import '../support/test_services.dart';

/// Шаги 08 и 09: поиск по книге на экране чтения.
///
/// Сам лист с настоящим PDFium в widget-тестах не строится; здесь
/// проверяется то, что от него не зависит: куда ведёт переход к
/// найденному, что делают кнопки громкости при открытом поиске,
/// сколько места панель оставляет листу и откуда поиск берёт текст
/// страниц (F-TEXT-04).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppData data;

  setUp(() async {
    data = await openTestData();
  });
  tearDown(() async => data.close());

  /// Снимает дерево виджетов и даёт базе прибраться (см.
  /// `reader_controls_test`).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Страница, где искомое слово стоит в нижней половине.
  final PageTextLayout lower = buildLayout(<TestLine>[
    const TestLine('первая строка страницы', top: 0.10),
    const TestLine('вторая строка страницы', top: 0.14),
    const TestLine('здесь внизу лежит тройка', top: 0.80),
    const TestLine('последняя строка страницы', top: 0.84),
  ]);

  Future<void> pumpReader(
    WidgetTester tester, {
    FakeReaderDocument? document,
    VolumeKeys volumeKeys = const NoVolumeKeys(),
    FullScreenWindow window = const NoFullScreenWindow(),
  }) async {
    await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
    final Book book = testBook();
    await data.library.save(book);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: testServices(
            data: data,
            document:
                document ??
                FakeReaderDocument(
                  pages: <String>['вступление', lower.text, 'окончание'],
                  layouts: <int, PageTextLayout>{2: lower},
                ),
            volumeKeys: volumeKeys,
            window: window,
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

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('reader-page-label'))).data!;

  /// Книга, где «тройка» встречается на второй и пятой страницах.
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

  testWidgets('BUG-10: переход к найденному ведёт в полосу, где оно лежит', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    final ReaderController controller = scaffoldOf(tester).controller;
    await controller.setDisplayMode(PageDisplayMode.half);
    await tester.pumpAndSettle();
    expect(controller.fragmentCount, 2, reason: 'страница делится пополам');

    await scaffoldOf(tester).search.start('тройка');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
    // Прежде переход всегда вёл в первую полосу страницы, и найденное в
    // нижней половине оставалось в тени или за экраном.
    expect(controller.fragment, 1, reason: 'найденное — в нижней полосе');

    await unmount(tester);
  });

  testWidgets('BUG-10: читателя на той же странице к её началу не возвращает', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);
    final ReaderController controller = scaffoldOf(tester).controller;
    await controller.setDisplayMode(PageDisplayMode.half);
    await controller.goToPage(2, fragment: 1);
    await tester.pumpAndSettle();
    expect(controller.fragment, 1);

    await scaffoldOf(tester).search.start('тройка');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();

    expect(controller.page, 2);
    expect(controller.fragment, 1, reason: 'найденное уже на экране');

    await unmount(tester);
  });

  group('F-TEXT-11: кнопки громкости при открытом поиске', () {
    testWidgets('ведут по совпадениям, а не листают', (
      WidgetTester tester,
    ) async {
      final FakeVolumeKeys keys = FakeVolumeKeys();
      await pumpReader(tester, document: threes(), volumeKeys: keys);
      await scaffoldOf(tester).search.start('тройка');
      await tester.pumpAndSettle();
      expect(keys.active, isTrue);

      // Узкий экран, читатель набирает запрос: панель — полоса у
      // нижнего края, страницу она не закрывает (F-TEXT-12), и перехват
      // кнопок остаётся.
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();
      expect(keys.active, isTrue);

      // «Тише» при открытом поиске — первое совпадение, а не листание.
      expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
      await tester.pumpAndSettle();
      expect(label(tester), '2 / 6');
      expect(keys.active, isTrue);

      // «Тише» — следующее совпадение: пятая страница, а не третья.
      expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
      await tester.pumpAndSettle();
      expect(label(tester), '5 / 6');

      // «Громче» — предыдущее.
      expect(keys.click(VolumeKey.up), VolumeKeyOutcome.back);
      await tester.pumpAndSettle();
      expect(label(tester), '2 / 6');

      // Поиск закрыли — кнопки снова листают.
      stateOf(tester).closeSearch();
      await tester.pumpAndSettle();
      expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
      await tester.pumpAndSettle();
      expect(label(tester), '3 / 6');

      await unmount(tester);
    });

    testWidgets('без найденного листают, как всегда', (
      WidgetTester tester,
    ) async {
      final FakeVolumeKeys keys = FakeVolumeKeys();
      await pumpReader(tester, document: threes(), volumeKeys: keys);
      await scaffoldOf(tester).search.start('тройка');
      await tester.pumpAndSettle();
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-hit-0')));
      await tester.pumpAndSettle();
      expect(label(tester), '2 / 6');

      // Запрос сменили на тот, которого в книге нет: перебирать нечего.
      await scaffoldOf(tester).search.start('тролль');
      await tester.pumpAndSettle();
      expect(keys.click(VolumeKey.down), VolumeKeyOutcome.forward);
      await tester.pumpAndSettle();
      expect(label(tester), '3 / 6');

      await unmount(tester);
    });
  });

  group('F-TEXT-04: текст книги в кэше', () {
    const PageTextKey key = PageTextKey(
      bookId: 'book-1',
      fingerprint: 'hash-1',
    );

    int reads(FakeReaderDocument document) {
      int total = 0;
      for (final int count in document.textReads.values) {
        total += count;
      }
      return total;
    }

    testWidgets('фоновый проход запоминает книгу после открытия', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = threes();
      await pumpReader(tester, document: document);

      // Сразу после открытия проход не идёт: движок занят страницей.
      expect(reads(document), 0);
      expect(await data.pageTexts.cachedPages(key), isEmpty);

      await tester.pump(kTextPassDelay);
      await tester.pump();

      expect(reads(document), 6);
      expect((await data.pageTexts.cachedPages(key)).keys.toSet(), <int>{
        1,
        2,
        3,
        4,
        5,
        6,
      });
      expect(await data.pageTexts.pageTexts(key, from: 5, to: 5), <int, String>{
        5: 'и снова тройка',
      });

      // Поиск после этого к движку не ходит вовсе.
      await scaffoldOf(tester).search.start('тройка');
      await tester.pumpAndSettle();
      expect(scaffoldOf(tester).search.hits.length, 2);
      expect(reads(document), 6);

      await unmount(tester);
    });

    testWidgets('поиск сразу после открытия находит слово из конца книги', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = threes();
      await pumpReader(tester, document: document);

      // Проход ещё не начинался — поиск читает книгу сам и запоминает.
      await scaffoldOf(tester).search.start('снова');
      await tester.pumpAndSettle();
      expect(scaffoldOf(tester).search.hits.single.pageNumber, 5);
      expect(reads(document), 6);
      expect((await data.pageTexts.cachedPages(key)).length, 6);

      // Второй поиск — уже по запомненному.
      await scaffoldOf(tester).search.start('окончание');
      await tester.pumpAndSettle();
      expect(scaffoldOf(tester).search.hits.single.pageNumber, 6);
      expect(reads(document), 6, reason: 'книгу второй раз не читали');

      // И проходу после него читать нечего.
      await tester.pump(kTextPassDelay);
      await tester.pump();
      expect(reads(document), 6);

      await unmount(tester);
    });

    testWidgets('в скане поиск говорит, что текста нет', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, document: FakeReaderDocument.blank(3));
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search-field')), 'слово');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('В этой книге нет текста: это скан.'), findsOneWidget);
      expect(find.text('Ничего не найдено.'), findsNothing);

      await unmount(tester);
    });

    testWidgets('в книге с текстом пустой результат — «ничего не найдено»', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, document: threes());
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search-field')), 'тролль');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Ничего не найдено.'), findsOneWidget);
      expect(find.text('В этой книге нет текста: это скан.'), findsNothing);

      await unmount(tester);
    });

    testWidgets('закрытая книга проход не продолжает', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = threes();
      await pumpReader(tester, document: document);

      // Книгу закрыли раньше, чем проход начался.
      await unmount(tester);
      await tester.pump(kTextPassDelay);

      expect(reads(document), 0);
    });

    testWidgets('F-DEV-13: прочитанная книга с текстом — не скан', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, document: threes());
      // Книга заведена без признака: при импорте узнать не удалось.
      expect((await data.library.bookById('book-1'))!.hasTextLayer, isNull);

      await tester.pump(kTextPassDelay);
      await tester.pump();
      await tester.pump();

      expect((await data.library.bookById('book-1'))!.hasTextLayer, isTrue);

      await unmount(tester);
    });

    testWidgets('F-DEV-13: прочитанный целиком скан назван сканом', (
      WidgetTester tester,
    ) async {
      await pumpReader(tester, document: FakeReaderDocument.blank(4));

      await tester.pump(kTextPassDelay);
      await tester.pump();
      await tester.pump();

      expect((await data.library.bookById('book-1'))!.hasTextLayer, isFalse);

      await unmount(tester);
    });
  });

  group('F-TEXT-11: панель рядом со страницей на широком окне', () {
    /// Место, которое отведено листу.
    Size sheetSize(WidgetTester tester) => tester.getSize(
      find.descendant(
        of: find.byKey(const Key('reader-sheet-box')),
        matching: find.byType(SizedBox),
      ),
    );

    void resize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
    }

    testWidgets('лист переложен один раз при открытии и один — при закрытии', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, const Size(1280, 800));
      await pumpReader(tester, window: FakeFullScreenWindow());
      expect(sheetSize(tester), const Size(1280, 800));

      // Панель открылась: это не протяжка окна, и новое место под лист
      // принимается сразу — без отсчёта, которым ждут конца протяжки.
      stateOf(tester).openSearch();
      await tester.pump();
      expect(sheetSize(tester), const Size(1280 - kSearchPanelWidth, 800));
      await tester.pump(kWindowSettle);
      await tester.pump();
      expect(sheetSize(tester), const Size(1280 - kSearchPanelWidth, 800));

      // Режим выбирается по месту, которое странице в самом деле
      // досталось, а не по окну целиком.
      final ReaderController controller = scaffoldOf(tester).controller;
      expect(
        controller.displayArea,
        const DisplayArea(width: 1280 - kSearchPanelWidth, height: 800),
      );

      // Закрылась — лист снова во всё окно, и тоже сразу.
      await tester.pump(kWindowJump * 2);
      stateOf(tester).closeSearch();
      await tester.pump();
      expect(sheetSize(tester), const Size(1280, 800));
      expect(
        controller.displayArea,
        const DisplayArea(width: 1280, height: 800),
      );

      // Протяжка окна после этого ждёт, как и ждала (F-DESK-02).
      await tester.pump(kWindowJump * 2);
      resize(tester, const Size(1400, 900));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sheetSize(tester), const Size(1280, 800));
      await tester.pump(kWindowSettle);
      await tester.pump();
      expect(sheetSize(tester), const Size(1400, 900));

      await unmount(tester);
    });

    testWidgets('страница рядом с панелью листается клавишами', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      resize(tester, const Size(1280, 800));
      await pumpReader(tester, document: threes());
      await scaffoldOf(tester).search.start('тройка');
      await tester.pumpAndSettle();
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-hit-1')));
      await tester.pumpAndSettle();
      expect(label(tester), '5 / 6');
      expect(find.byKey(const Key('search-panel')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(label(tester), '4 / 6');
      expect(find.byKey(const Key('search-panel')), findsOneWidget);

      // F3 — следующее совпадение по кругу: со второго на первое.
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(label(tester), '2 / 6');

      await unmount(tester);
    });
  });
}
