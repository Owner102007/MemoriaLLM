import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/navigation.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/search_dock.dart';
import 'package:memoria/domain/reading/text_search.dart';
import 'package:memoria/ui/reader/key_bindings.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';

import '../support/fake_reading.dart';

/// Открытая книга и поиск по ней — для тестов поиска.
typedef _Searched = ({ReaderController controller, DocumentSearch search});

const List<OutlineEntry> _outline = <OutlineEntry>[
  OutlineEntry(
    title: 'Часть I',
    pageNumber: 1,
    children: <OutlineEntry>[OutlineEntry(title: 'Глава 1', pageNumber: 3)],
  ),
  OutlineEntry(title: 'Часть II', pageNumber: 6),
];

void main() {
  late FakeReadingRepository reading;
  late List<int> jumps;
  late List<String> steps;
  late List<LogicalKeyboardKey> bubbled;
  late int dismissals;
  late List<bool> windows;

  /// Что обвязка говорила экрану чтения: закрыта ли страница панелью,
  /// открыт ли поиск и сколько ширины он отнял у страницы.
  late List<bool> covers;
  late List<bool> searches;
  late List<double> docks;

  setUp(() {
    reading = FakeReadingRepository();
    jumps = <int>[];
    steps = <String>[];
    bubbled = <LogicalKeyboardKey>[];
    dismissals = 0;
    windows = <bool>[];
    covers = <bool>[];
    searches = <bool>[];
    docks = <double>[];
  });

  Future<ReaderController> makeController({
    int pages = 10,
    List<OutlineEntry> outline = _outline,
  }) {
    return ReaderController.open(
      book: fakeBook(pageCount: pages),
      opener: FakeDocumentOpener(
        FakeReaderDocument(
          pages: List<String>.generate(pages, (int i) => 'страница ${i + 1}'),
          outlineNodes: outline,
        ),
      ),
      reading: reading,
    );
  }

  Future<void> pumpReader(
    WidgetTester tester,
    ReaderController controller, {
    DocumentSearch? search,
    Future<void> Function(SearchHit hit)? onGoToHit,
    Future<void> Function(int page)? onGoToPage,
    bool selecting = false,
    bool fullScreen = false,
    bool hasWindow = false,
    KeyBindings keyBindings = KeyBindings.standard,
    ValueListenable<Rect?>? found,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // Узел-свидетель над экраном чтения: до него доходит только то,
        // чего экран не забрал себе. Так проверяется, что клавиши поля
        // ввода не съедены по дороге.
        home: Focus(
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is KeyDownEvent) {
              bubbled.add(event.logicalKey);
            }
            return KeyEventResult.ignored;
          },
          child: ReaderScaffold(
            controller: controller,
            search: search ?? DocumentSearch(document: controller.document),
            onGoToHit: onGoToHit,
            onPreviousFragment: () => steps.add('назад'),
            onNextFragment: () => steps.add('вперёд'),
            onDismiss: () => dismissals++,
            onPanelsChanged: covers.add,
            onSearchOpen: searches.add,
            onSearchDock: docks.add,
            found: found,
            selecting: () => selecting,
            fullScreen: fullScreen,
            onFullScreen: hasWindow ? windows.add : null,
            keyBindings: keyBindings,
            onGoToPage:
                onGoToPage ??
                (int page) async {
                  jumps.add(page);
                  controller.onPageChanged(page);
                },
            viewerBuilder: (BuildContext context, VoidCallback onTap) {
              return GestureDetector(
                key: const Key('fake-viewer'),
                onTap: onTap,
                child: const ColoredBox(color: Color(0xFF101010)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double chromeOpacity(WidgetTester tester) {
    final Finder finder = find
        .ancestor(
          of: find.byKey(const Key('reader-page-label')),
          matching: find.byType(AnimatedOpacity),
        )
        .first;
    return tester.widget<AnimatedOpacity>(finder).opacity;
  }

  group('панели', () {
    testWidgets('по умолчанию не видно ничего, кроме страницы', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);

      expect(find.byKey(const Key('fake-viewer')), findsOneWidget);
      expect(chromeOpacity(tester), 0);

      await controller.close();
      controller.dispose();
    });

    testWidgets('нажатие в середину показывает и прячет панели', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);

      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester), 1);

      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester), 0);

      await controller.close();
      controller.dispose();
    });
  });

  group('навигация', () {
    testWidgets('счётчик страниц следует за просмотрщиком', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController(pages: 340);
      await pumpReader(tester, controller);
      expect(find.text('1 / 340'), findsOneWidget);

      controller.onPageChanged(42);
      await tester.pumpAndSettle();
      expect(find.text('42 / 340'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);

      await controller.close();
      controller.dispose();
    });

    testWidgets('кнопки шага переводят на соседние страницы', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reader-next-page')));
      await tester.pumpAndSettle();
      expect(jumps, <int>[2]);

      await tester.tap(find.byKey(const Key('reader-prev-page')));
      await tester.pumpAndSettle();
      expect(jumps, <int>[2, 1]);

      await controller.close();
      controller.dispose();
    });

    testWidgets('BUG-01: стрелки в развороте шагают листами', (
      WidgetTester tester,
    ) async {
      // Прежде стрелка вела на страницу + 1: со второй на третью, а она
      // уже на экране, — и каждое второе нажатие ничего не меняло.
      final ReaderController controller = await makeController();
      await controller.setDisplayMode(PageDisplayMode.spread);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reader-next-page')));
      await tester.pumpAndSettle();
      expect(find.text('2–3 / 10'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-next-page')));
      await tester.pumpAndSettle();
      expect(jumps, <int>[2, 4]);
      expect(find.text('4–5 / 10'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reader-prev-page')));
      await tester.pumpAndSettle();
      expect(jumps, <int>[2, 4, 2]);

      await controller.close();
      controller.dispose();
    });

    testWidgets('на краях книги шагать некуда', (WidgetTester tester) async {
      final ReaderController controller = await makeController(pages: 3);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final IconButton back = tester.widget<IconButton>(
        find.byKey(const Key('reader-prev-page')),
      );
      expect(back.onPressed, isNull);

      controller.onPageChanged(3);
      await tester.pumpAndSettle();
      final IconButton forward = tester.widget<IconButton>(
        find.byKey(const Key('reader-next-page')),
      );
      expect(forward.onPressed, isNull);

      await controller.close();
      controller.dispose();
    });

    testWidgets('ползунок переводит на выбранную страницу', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController(pages: 100);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final Finder slider = find.byKey(const Key('reader-progress-slider'));
      await tester.drag(slider, const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(jumps, isNotEmpty);
      expect(jumps.last, greaterThan(1));

      await controller.close();
      controller.dispose();
    });

    testWidgets('BUG-39: протяжка ползунка открывает одну страницу', (
      WidgetTester tester,
    ) async {
      // Прежде переход шёл на каждое промежуточное значение: протяжка
      // через полкниги ставила в очередь движка десятки страниц, и та,
      // где читатель остановился, ждала за ними белым листом.
      final ReaderController controller = await makeController(pages: 100);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final Finder slider = find.byKey(const Key('reader-progress-slider'));
      final Rect box = tester.getRect(slider);
      final TestGesture gesture = await tester.startGesture(
        Offset(box.left + 40, box.center.dy),
      );
      // Между движениями проходит меньше срока остановки: бегунок едет
      // без пауз.
      for (int i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(jumps, isEmpty, reason: 'пока бегунок тянут, книга стоит');
      expect(
        tester.widget<Slider>(slider).value,
        greaterThan(20),
        reason: 'а бегунок и подпись над ним едут за пальцем',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(jumps, hasLength(1), reason: 'переход один');
      expect(jumps.single, greaterThan(20));
      expect(controller.page, jumps.single);

      await controller.close();
      controller.dispose();
    });

    testWidgets('BUG-39: бегунок остановили, не отпуская, — страница открыта', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController(pages: 100);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final Finder slider = find.byKey(const Key('reader-progress-slider'));
      final Rect box = tester.getRect(slider);
      final TestGesture gesture = await tester.startGesture(
        Offset(box.left + 40, box.center.dy),
      );
      for (int i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(jumps, isEmpty);

      // Палец на месте: срок вышел — открывается страница под бегунком.
      await tester.pump(kSliderRest + const Duration(milliseconds: 20));
      expect(jumps, hasLength(1));
      final int rested = jumps.single;

      // Держит дальше, не двигая: второй раз та же страница не зовётся.
      await tester.pump(const Duration(milliseconds: 400));
      expect(jumps, hasLength(1));

      // Потянул дальше и отпустил — открывается страница, где отпустил.
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(jumps, hasLength(2));
      expect(jumps.last, greaterThan(rested));

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-28: бегунок ждёт конца перехода и не отскакивает', (
      WidgetTester tester,
    ) async {
      // Страница меняется не в тот же миг, что отпущен бегунок. Пока
      // переход идёт, бегунок стоит там, где его оставили, а не
      // возвращается на прежнюю страницу.
      final ReaderController controller = await makeController(pages: 100);
      final List<Completer<void>> arrivals = <Completer<void>>[];
      await pumpReader(
        tester,
        controller,
        onGoToPage: (int page) async {
          jumps.add(page);
          final Completer<void> arrival = Completer<void>();
          arrivals.add(arrival);
          await arrival.future;
          controller.onPageChanged(page);
        },
      );
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final Finder slider = find.byKey(const Key('reader-progress-slider'));
      await tester.drag(slider, const Offset(200, 0));
      await tester.pump();
      expect(jumps, hasLength(1));
      expect(controller.page, 1, reason: 'переход ещё идёт');
      expect(tester.widget<Slider>(slider).value, jumps.single.toDouble());

      arrivals.single.complete();
      await tester.pumpAndSettle();
      expect(controller.page, jumps.single);
      expect(tester.widget<Slider>(slider).value, jumps.single.toDouble());

      // Книга ушла дальше стрелкой — бегунок снова следует за ней.
      controller.onPageChanged(7);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, 7);

      await controller.close();
      controller.dispose();
    });

    testWidgets('книга из одной страницы обходится без ползунка', (
      WidgetTester tester,
    ) async {
      // Slider с одинаковыми min и max падает — а книга из одной
      // страницы существует и открываться обязана.
      final ReaderController controller = await makeController(pages: 1);
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-progress-slider')), findsNothing);
      expect(find.text('1 / 1'), findsOneWidget);

      await controller.close();
      controller.dispose();
    });
  });

  group('оглавление', () {
    testWidgets('открывается и переводит на выбранный раздел', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await controller.loadOutline();
      await pumpReader(tester, controller);

      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-outline-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('outline-panel')), findsOneWidget);
      expect(find.text('Часть I'), findsOneWidget);
      expect(find.text('Часть II'), findsOneWidget);
      // Верхний уровень раскрыт, поэтому вложенная глава тоже видна.
      expect(find.text('Глава 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('outline-item-1')));
      await tester.pumpAndSettle();

      expect(jumps, <int>[6]);
      expect(find.byKey(const Key('outline-panel')), findsNothing);

      await controller.close();
      controller.dispose();
    });

    testWidgets('книга без оглавления объясняет, почему его нет', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController(
        outline: const <OutlineEntry>[],
      );
      await controller.loadOutline();
      await pumpReader(tester, controller);

      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-outline-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('outline-empty')), findsOneWidget);

      await controller.close();
      controller.dispose();
    });
  });

  group('поиск', () {
    testWidgets('показывает найденное и переводит на страницу', (
      WidgetTester tester,
    ) async {
      final Book book = fakeBook(pageCount: 4);
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>[
          'вступление',
          'здесь встречается тройка',
          'ничего',
          'и снова тройка семёрка туз',
        ],
      );
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      await pumpReader(tester, controller, search: search);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-search-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-panel')), findsOneWidget);
      expect(find.byKey(const Key('search-hit-0')), findsOneWidget);
      expect(find.byKey(const Key('search-hit-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-hit-1')));
      await tester.pumpAndSettle();
      expect(jumps, <int>[4]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('переход к найденному несёт само совпадение', (
      WidgetTester tester,
    ) async {
      // Подсветить найденное по одному номеру страницы нельзя: нужны
      // координаты в тексте. Поэтому экран чтения получает сам SearchHit,
      // а не только страницу.
      final Book book = fakeBook(pageCount: 2);
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['вступление', 'здесь встречается тройка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: book,
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<SearchHit> hits = <SearchHit>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => hits.add(hit),
      );
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-search-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-hit-0')));
      await tester.pumpAndSettle();

      expect(hits, hasLength(1));
      expect(hits.single.sourceEnd, greaterThan(hits.single.sourceStart));
      // И старый путь при этом не зовётся: переход теперь один.
      expect(jumps, isEmpty);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('кнопка поиска стоит в верхней панели', (
      WidgetTester tester,
    ) async {
      // Владелец её не нашёл: она жила внизу, а искал он наверху. Поиск,
      // до которого не добрался читатель, всё равно что отсутствует.
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();

      final double search = tester
          .getCenter(find.byKey(const Key('reader-search-button')))
          .dy;
      final double label = tester
          .getCenter(find.byKey(const Key('reader-page-label')))
          .dy;
      final double outline = tester
          .getCenter(find.byKey(const Key('reader-outline-button')))
          .dy;
      expect(search, lessThan(outline), reason: 'поиск выше оглавления');
      expect(
        (search - label).abs(),
        lessThan(40),
        reason: 'поиск стоит в одной строке с названием книги',
      );

      await controller.close();
      controller.dispose();
    });

    testWidgets('пустой результат так и написан', (WidgetTester tester) async {
      // Книга нарочно короче, чем шаг, на котором поиск уступает
      // управление интерфейсу. В widget-тестах время подменено, и
      // отложенная на «ноль секунд» пауза внутри поиска не наступит
      // сама — тест повис бы, дожидаясь её.
      final ReaderController controller = await makeController(pages: 4);
      final DocumentSearch search = DocumentSearch(
        document: controller.document,
      );
      await search.start('тролль');

      await pumpReader(tester, controller, search: search);
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-search-button')));
      await tester.pumpAndSettle();

      expect(find.text('Ничего не найдено.'), findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });
  });

  group('F-TEXT-11: поиск остаётся открытым', () {
    final Finder panel = find.byKey(const Key('search-panel'));
    final Finder field = find.byKey(const Key('search-field'));
    final Finder marker = find.byKey(const Key('search-current'));

    /// Книга, где «тройка» встречается на трёх страницах.
    Future<_Searched> threes() async {
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>[
          'вступление',
          'здесь встречается тройка',
          'ничего',
          'и снова тройка семёрка туз',
          'ничего',
          'последняя тройка',
        ],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 6),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');
      return (controller: controller, search: search);
    }

    ReaderScaffoldState stateOf(WidgetTester tester) =>
        tester.state<ReaderScaffoldState>(find.byType(ReaderScaffold));

    Future<void> openSearch(WidgetTester tester) async {
      stateOf(tester).openSearch();
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    String count(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('search-count'))).data!;

    /// Меняет размер экрана на время теста.
    void resize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
    }

    testWidgets('выбор результата не закрывает панель', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      expect(panel, findsOneWidget);
      expect(field, findsOneWidget);
      expect(marker, findsNothing, reason: 'ещё ни на каком результате');

      await tapKey(tester, 'search-hit-1');

      expect(jumps, <int>[4]);
      expect(panel, findsOneWidget, reason: 'панель осталась на экране');
      expect(find.byKey(const Key('search-results')), findsOneWidget);
      expect(marker, findsOneWidget, reason: 'текущий результат отмечен');
      expect(count(tester), '2 из 3');

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('второй результат выбирается без повторного открытия', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);

      await tapKey(tester, 'search-hit-1');
      await tapKey(tester, 'search-hit-2');
      await tapKey(tester, 'search-hit-0');

      expect(jumps, <int>[4, 6, 2]);
      expect(count(tester), '1 из 3');
      expect(panel, findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('‹ и › ведут по совпадениям по кругу', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-1');

      await tapKey(tester, 'search-next');
      expect(count(tester), '3 из 3');
      await tapKey(tester, 'search-next');
      expect(count(tester), '1 из 3', reason: 'за последним — первое');
      await tapKey(tester, 'search-previous');
      expect(count(tester), '3 из 3', reason: 'перед первым — последнее');
      expect(jumps, <int>[4, 6, 2, 6]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('F3 при открытом поиске — тоже выбор результата', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      expect(field, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();

      expect(jumps, <int>[2]);
      expect(panel, findsOneWidget);
      expect(count(tester), '1 из 3');
      // Узкий экран: результат выбран — панель сжалась в полосу, и поля
      // ввода в ней нет.
      expect(field, findsNothing);
      expect(find.byKey(const Key('search-query')), findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('Esc закрывает поиск и после выбора результата', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');
      expect(panel, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(panel, findsNothing);
      expect(dismissals, 0, reason: 'Esc ушёл на поиск, а не на страницу');

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('кнопка ✕ закрывает поиск', (WidgetTester tester) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-close');
      expect(panel, findsNothing);

      // И из полосы просмотра — тоже.
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');
      await tapKey(tester, 'search-close');
      expect(panel, findsNothing);
      expect(searches, <bool>[true, false, true, false]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('системное «назад» закрывает поиск, а не книгу', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(panel, findsNothing);
      expect(find.byType(ReaderScaffold), findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('при повторном открытии запрос и место в списке на месте', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-1');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);

      await openSearch(tester);

      expect(tester.widget<TextField>(field).controller!.text, 'тройка');
      expect(count(tester), '2 из 3');
      expect(marker, findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('нажатие по запросу возвращает ко вводу', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');
      expect(field, findsNothing);
      expect(find.text('тройка'), findsWidgets);

      await tapKey(tester, 'search-query');

      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'тройка');

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('узкий экран: страница закрыта, только пока набирают', (
      WidgetTester tester,
    ) async {
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      final ReaderScaffoldState state = stateOf(tester);
      expect(state.searchSteps, isFalse, reason: 'поиск закрыт');

      await openSearch(tester);
      expect(covers, <bool>[true]);
      expect(tester.getSize(panel), const Size(800, 600), reason: 'весь экран');
      expect(state.searchSteps, isFalse, reason: 'страницы не видно');

      await tapKey(tester, 'search-hit-0');
      expect(covers, <bool>[true, false]);
      expect(state.searchSteps, isTrue, reason: 'страница видна');
      expect(docks, isEmpty, reason: 'поверх страницы, а не рядом с ней');

      await tapKey(tester, 'search-close');
      expect(covers, <bool>[true, false]);
      expect(state.searchSteps, isFalse);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('телефон в альбоме: полоса сбоку и уступает найденному', (
      WidgetTester tester,
    ) async {
      // Экран теста — 800×600: узкий и лежит на боку.
      final ValueNotifier<Rect?> found = ValueNotifier<Rect?>(null);
      addTearDown(found.dispose);
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search, found: found);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');

      Rect strip() => tester.getRect(panel);
      expect(strip().width, closeTo(800 * kSearchStripShare, 0.5));
      expect(strip().right, 800, reason: 'из коробки — у правого края');
      expect(strip().height, 600);

      // Найденное оказалось под панелью — она переезжает налево.
      found.value = const Rect.fromLTWH(600, 200, 100, 20);
      await tester.pumpAndSettle();
      expect(strip().left, 0);

      // Следующее найденное панелью не закрыто — она стоит где стояла.
      found.value = const Rect.fromLTWH(400, 300, 100, 20);
      await tester.pumpAndSettle();
      expect(strip().left, 0, reason: 'без нужды не переезжает');

      // А это — под ней: возвращается направо.
      found.value = const Rect.fromLTWH(100, 300, 100, 20);
      await tester.pumpAndSettle();
      expect(strip().right, 800);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('телефон в портрете: полоса снизу, не выше 40 % экрана', (
      WidgetTester tester,
    ) async {
      resize(tester, const Size(400, 800));
      final ValueNotifier<Rect?> found = ValueNotifier<Rect?>(null);
      addTearDown(found.dispose);
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search, found: found);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');

      Rect strip() => tester.getRect(panel);
      expect(strip().bottom, 800, reason: 'из коробки — у нижнего края');
      expect(strip().width, 400);
      expect(strip().height, lessThanOrEqualTo(800 * kSearchStripShare));
      // Страница под полосой не перекладывается: место под неё прежнее.
      expect(
        tester.getSize(find.byKey(const Key('fake-viewer'))),
        const Size(400, 800),
      );

      // Найденное внизу экрана — полоса переезжает наверх.
      found.value = const Rect.fromLTWH(40, 700, 320, 20);
      await tester.pumpAndSettle();
      expect(strip().top, 0);

      // Выделение через весь экран — остаётся одна строка счёта.
      found.value = const Rect.fromLTWH(40, 20, 320, 760);
      await tester.pumpAndSettle();
      expect(strip().height, lessThanOrEqualTo(kSearchCompactExtent));
      expect(find.byKey(const Key('search-results')), findsNothing);
      expect(find.byKey(const Key('search-count')), findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('широкое окно: панель рядом со страницей, страница живая', (
      WidgetTester tester,
    ) async {
      resize(tester, const Size(1280, 800));
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      final Finder viewer = find.byKey(const Key('fake-viewer'));
      expect(tester.getSize(viewer), const Size(1280, 800));

      await openSearch(tester);

      // Панель стоит справа, страница — в оставшейся ширине.
      expect(tester.getRect(panel).left, 1280 - kSearchPanelWidth);
      expect(tester.getRect(panel).right, 1280);
      expect(tester.getSize(viewer), const Size(1280 - kSearchPanelWidth, 800));
      expect(docks, <double>[kSearchPanelWidth]);
      expect(covers, isEmpty, reason: 'страницу панель не закрывает');

      // Результат выбран: панель на месте, поле и список — тоже.
      await tapKey(tester, 'search-hit-1');
      expect(jumps, <int>[4]);
      expect(panel, findsOneWidget);
      expect(field, findsOneWidget);
      expect(marker, findsOneWidget);
      expect(tester.getSize(viewer), const Size(1280 - kSearchPanelWidth, 800));

      // Страница рядом с панелью листается клавишами…
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(steps, <String>['вперёд', 'вперёд']);

      // …и нажатием: панели чтения показываются по нажатию в неё.
      await tester.tap(viewer);
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester), 1);

      // Закрыли — страница снова во всю ширину.
      await tapKey(tester, 'search-close');
      expect(panel, findsNothing);
      expect(tester.getSize(viewer), const Size(1280, 800));
      expect(docks, <double>[kSearchPanelWidth, 0]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('широкое окно: пока набирают запрос, клавиши — у поля', (
      WidgetTester tester,
    ) async {
      resize(tester, const Size(1280, 800));
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search);
      await openSearch(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(steps, isEmpty, reason: 'пробел принадлежит полю');

      // Читатель нажал по странице — клавиши вернулись к ней.
      stateOf(tester).focusPage();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(steps, <String>['вперёд']);
      expect(panel, findsOneWidget);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets(
      'ПК: поле отдало указатель ввода — клавиши чтения живы',
      (WidgetTester tester) async {
        // Найдено независимой проверкой шага 08. `Enter` в поле запускает
        // поиск и отбирает у поля указатель ввода. Панель стоит прямо в
        // теле экрана, и без своей области фокуса указатель уходил бы к
        // маршруту — выше узла клавиш чтения: `Esc`, `F3` и стрелки
        // замолкали до следующего нажатия по полю.
        resize(tester, const Size(1280, 800));
        final _Searched book = await threes();
        final ReaderController controller = book.controller;
        final DocumentSearch search = book.search;
        await pumpReader(tester, controller, search: search);
        await openSearch(tester);

        await tester.enterText(field, 'семёрка');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(search.query, 'семёрка');
        expect(count(tester), 'из 1');

        // Стрелка листает страницу рядом с панелью…
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(steps, <String>['вперёд']);

        // …`F3` ведёт к найденному…
        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        await tester.pumpAndSettle();
        expect(jumps, <int>[4]);

        // …а `Esc` закрывает поиск.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);

        search.dispose();
        await controller.close();
        controller.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('Esc рядом с панелью сначала снимает выделение', (
      WidgetTester tester,
    ) async {
      // Панель стоит рядом со страницей подолгу: закрывать её раньше,
      // чем снято выделение на видимой странице, значило бы отбирать у
      // `Esc` привычное дело.
      resize(tester, const Size(1280, 800));
      final _Searched book = await threes();
      final ReaderController controller = book.controller;
      final DocumentSearch search = book.search;
      await pumpReader(tester, controller, search: search, selecting: true);
      await openSearch(tester);
      await tapKey(tester, 'search-hit-0');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(dismissals, 1, reason: 'Esc ушёл на страницу');
      expect(panel, findsOneWidget, reason: 'поиск остался открытым');

      search.dispose();
      await controller.close();
      controller.dispose();
    });
  });

  group('клавиатура', () {
    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool control = false,
      bool shift = false,
    }) async {
      if (control) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      }
      if (shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyEvent(key);
      if (shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      if (control) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('стрелки и пробел листают книгу', (WidgetTester tester) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.pageDown);

      expect(steps, <String>['вперёд', 'вперёд', 'назад', 'вперёд']);

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-25: листают клавиши из таблицы читателя', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      // Читатель назначил «J» вперёд, а пробел у листания отобрал.
      await pumpReader(
        tester,
        controller,
        keyBindings: KeyBindings.standard
            .assign(TurnKey.forward, const KeyStroke(LogicalKeyboardKey.keyJ))
            .without(
              TurnKey.forward,
              const KeyStroke(LogicalKeyboardKey.space),
            ),
      );

      await press(tester, LogicalKeyboardKey.keyJ);
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.arrowLeft);

      expect(steps, <String>['вперёд', 'назад']);
      // Пробел экран чтения не забрал: он ушёл дальше, как любая
      // посторонняя клавиша.
      expect(bubbled, contains(LogicalKeyboardKey.space));
      expect(bubbled, isNot(contains(LogicalKeyboardKey.keyJ)));

      await controller.close();
      controller.dispose();
    });

    testWidgets('Ctrl+F открывает поиск, Esc его закрывает', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);

      // Панели при этом спрятаны: поиск обязан открываться и с чистой
      // страницы, иначе клавиша ничем не лучше кнопки.
      expect(find.byKey(const Key('search-panel')), findsNothing);
      await press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(find.byKey(const Key('search-panel')), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('search-panel')), findsNothing);
      // Esc ушёл на закрытие поиска и до выделения не добрался.
      expect(dismissals, 0);

      await controller.close();
      controller.dispose();
    });

    testWidgets('Esc без открытых панелей снимает выделение', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);

      await press(tester, LogicalKeyboardKey.escape);
      expect(dismissals, 1);

      await controller.close();
      controller.dispose();
    });

    testWidgets('F3 ведёт по совпадениям по кругу', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['тройка', 'ничего', 'снова тройка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 3),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );

      await press(tester, LogicalKeyboardKey.f3);
      await press(tester, LogicalKeyboardKey.f3);
      // Третье нажатие возвращает к первому: упереться в конец списка и
      // не понять, кончился он или сломалась клавиша, — худший исход.
      await press(tester, LogicalKeyboardKey.f3);
      expect(visited, <int>[1, 3, 1]);

      // Shift+F3 — назад по тому же кругу.
      await press(tester, LogicalKeyboardKey.f3, shift: true);
      expect(visited.last, 3);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('BUG-08: первое Shift+F3 ведёт на последнее совпадение', (
      WidgetTester tester,
    ) async {
      // Счёт начинается с «ни на каком»: шаг назад оттуда — это последнее
      // совпадение, а не предпоследнее, как выходило из `(−2) mod n`.
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['тройка', 'тройка', 'ничего', 'тройка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 4),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );

      await press(tester, LogicalKeyboardKey.f3, shift: true);
      expect(visited, <int>[4], reason: 'последнее совпадение');

      // Дальше — назад по кругу, как и прежде.
      await press(tester, LogicalKeyboardKey.f3, shift: true);
      await press(tester, LogicalKeyboardKey.f3, shift: true);
      await press(tester, LogicalKeyboardKey.f3, shift: true);
      expect(visited, <int>[4, 2, 1, 4]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('BUG-08: при двух совпадениях первое Shift+F3 — на второе', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['тройка', 'ничего', 'тройка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 3),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );

      await press(tester, LogicalKeyboardKey.f3, shift: true);
      expect(visited, <int>[3]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('новый запрос начинает счёт совпадений заново', (
      WidgetTester tester,
    ) async {
      // Иначе `F3` по новому запросу продолжал бы с того места, где
      // читатель бросил прошлый, и первое совпадение оказалось бы
      // пропущено — а оно обычно и есть нужное.
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['тройка семёрка', 'семёрка', 'тройка семёрка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 3),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );

      await press(tester, LogicalKeyboardKey.f3);
      await press(tester, LogicalKeyboardKey.f3);
      expect(visited, <int>[1, 3]);

      await search.start('семёрка');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.f3);
      expect(visited.last, 1, reason: 'первое совпадение нового запроса');

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('пробел и Backspace в поле поиска принадлежат полю', (
      WidgetTester tester,
    ) async {
      // Регрессия S6.1, и она видна ровно так: клавиатурный узел стоит
      // над `Scaffold`, событие из поля проходит через него раньше, чем
      // через правила редактирования текста, и ответ «разобрано»
      // отбирает у поля пробел и `Backspace`. Фразу с пробелами было не
      // набрать, набранное — не стереть.
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);
      await press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(find.byKey(const Key('search-field')), findsOneWidget);

      steps.clear();
      bubbled.clear();
      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.backspace);

      expect(steps, isEmpty, reason: 'книга не листается, пока набирают');
      expect(
        bubbled,
        containsAll(<LogicalKeyboardKey>[
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.backspace,
        ]),
        reason: 'клавиши доходят до правил редактирования текста',
      );

      await controller.close();
      controller.dispose();
    });

    testWidgets('F3 работает и из поля: его поле не ждёт', (
      WidgetTester tester,
    ) async {
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['тройка', 'ничего', 'снова тройка'],
      );
      final ReaderController controller = await ReaderController.open(
        book: fakeBook(pageCount: 3),
        opener: FakeDocumentOpener(document),
        reading: reading,
      );
      final DocumentSearch search = DocumentSearch(document: document);
      await search.start('тройка');

      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        search: search,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );
      await press(tester, LogicalKeyboardKey.keyF, control: true);
      await press(tester, LogicalKeyboardKey.f3);
      expect(visited, <int>[1]);

      search.dispose();
      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-35: F11 разворачивает чтение и возвращает окно', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller, hasWindow: true);
      await press(tester, LogicalKeyboardKey.f11);
      expect(windows, <bool>[true]);

      await pumpReader(tester, controller, hasWindow: true, fullScreen: true);
      await press(tester, LogicalKeyboardKey.f11);
      expect(windows, <bool>[true, false]);

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-35: без окна F11 уходит мимо экрана чтения', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller);
      await press(tester, LogicalKeyboardKey.f11);
      expect(windows, isEmpty);
      expect(bubbled, contains(LogicalKeyboardKey.f11));

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-35: Esc возвращает окно, когда закрывать нечего', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller, hasWindow: true, fullScreen: true);

      await press(tester, LogicalKeyboardKey.escape);
      expect(windows, <bool>[false]);
      expect(dismissals, 0);

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-35: Esc сначала прячет панели и снимает выделение', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller, hasWindow: true, fullScreen: true);

      // Панели на экране — Esc прячет их, окно остаётся во весь экран.
      await tester.tap(find.byKey(const Key('fake-viewer')));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester), 1);
      await press(tester, LogicalKeyboardKey.escape);
      expect(chromeOpacity(tester), 0);
      expect(windows, isEmpty);

      // Текст выделен — Esc снимает выделение, окно остаётся.
      await pumpReader(
        tester,
        controller,
        hasWindow: true,
        fullScreen: true,
        selecting: true,
      );
      await press(tester, LogicalKeyboardKey.escape);
      expect(dismissals, 2);
      expect(windows, isEmpty);

      await controller.close();
      controller.dispose();
    });

    testWidgets('F-READ-35: Esc при открытом поиске закрывает поиск', (
      WidgetTester tester,
    ) async {
      final ReaderController controller = await makeController();
      await pumpReader(tester, controller, hasWindow: true, fullScreen: true);

      await press(tester, LogicalKeyboardKey.keyF, control: true);
      expect(find.byKey(const Key('search-panel')), findsOneWidget);
      // Курсор стоит в поле поиска, и Esc там разбирает сама панель.
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const Key('search-panel')), findsNothing);
      expect(windows, isEmpty);

      await controller.close();
      controller.dispose();
    });

    testWidgets('без найденного F3 молчит', (WidgetTester tester) async {
      final ReaderController controller = await makeController();
      final List<int> visited = <int>[];
      await pumpReader(
        tester,
        controller,
        onGoToHit: (SearchHit hit) async => visited.add(hit.pageNumber),
      );

      await press(tester, LogicalKeyboardKey.f3);
      expect(visited, isEmpty);

      await controller.close();
      controller.dispose();
    });
  });
}
