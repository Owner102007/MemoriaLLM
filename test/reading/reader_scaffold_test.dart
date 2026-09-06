import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/text_search.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';

import '../support/fake_reading.dart';

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

  setUp(() {
    reading = FakeReadingRepository();
    jumps = <int>[];
    steps = <String>[];
    bubbled = <LogicalKeyboardKey>[];
    dismissals = 0;
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
            onGoToPage: (int page) async {
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
