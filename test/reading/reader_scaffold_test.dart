import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/ui/reader/reader_scaffold.dart';

import '../support/fake_reading.dart';

const List<OutlineEntry> _outline = <OutlineEntry>[
  OutlineEntry(
    title: 'Часть I',
    pageNumber: 1,
    children: <OutlineEntry>[
      OutlineEntry(title: 'Глава 1', pageNumber: 3),
    ],
  ),
  OutlineEntry(title: 'Часть II', pageNumber: 6),
];

void main() {
  late FakeReadingRepository reading;
  late List<int> jumps;

  setUp(() {
    reading = FakeReadingRepository();
    jumps = <int>[];
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScaffold(
          controller: controller,
          search: search ?? DocumentSearch(document: controller.document),
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

    testWidgets('пустой результат так и написан', (WidgetTester tester) async {
      final ReaderController controller = await makeController();
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
}
