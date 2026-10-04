import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/library/book_card.dart';
import 'package:memoria/ui/library/library_screen.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/test_services.dart';

/// SNO-F-LIB-02: полка закреплена на время записи.
///
/// Замок приходит полке параметром: включать его будет запись сессии
/// (этап 2 ветви). Здесь проверяется сам замок — что под ним нет ничего,
/// чем расположение книг можно изменить, и что данные полки не меняются.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpShelf(
    WidgetTester tester,
    AppServices services, {
    required bool locked,
    bool titleSearch = false,
    bool canAddBooks = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          services: services,
          canAddBooks: canAddBooks,
          titleSearch: titleSearch,
          locked: locked,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Просторный экран: категории помещаются целиком.
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Три книги в одной категории и одна — в другой.
  Future<void> fillShelf() async {
    await data.categories.save(
      BookCategory(
        id: 'study',
        title: 'Учёба',
        position: 0,
        createdAt: DateTime.utc(2026, 8, 20),
      ),
    );
    await data.categories.save(
      BookCategory(
        id: 'rest',
        title: 'Отдых',
        position: 1,
        createdAt: DateTime.utc(2026, 8, 20),
      ),
    );
    const Map<String, String> titles = <String, String>{
      'a': 'Аа',
      'b': 'Бб',
      'c': 'Вв',
    };
    int place = 0;
    for (final MapEntry<String, String> entry in titles.entries) {
      await data.library.save(
        testBook(id: entry.key, title: entry.value, hash: 'hash-${entry.key}'),
      );
      await placeBook(data, entry.key, 'study', position: place++);
    }
    await data.library.save(testBook(id: 'd', title: 'Гг', hash: 'hash-d'));
    await placeBook(data, 'd', 'rest');
  }

  /// Всё, что составляет расположение: строки книг и категорий словами.
  Future<List<String>> layoutOf() async {
    final List<Book> books = await data.library.books();
    final List<BookCategory> categories = await data.categories.categories();
    final List<String> rows = <String>[
      for (final Book book in books)
        'книга ${book.id}: ${book.categoryId} / ${book.shelfPosition}',
      for (final BookCategory category in categories)
        'категория ${category.id}: ${category.title} / ${category.position}',
      'порядок: ${await data.settings.read(SettingsKeys.shelfSort)}',
    ]..sort();
    return rows;
  }

  /// Ведёт книгу [from] и отпускает её над левой частью блока [to] —
  /// тем же жестом, каким книги переставляют на телефоне.
  Future<void> dragBook(WidgetTester tester, String from, String to) async {
    final Rect box = tester.getRect(find.byKey(Key('library-book-$to')));
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key('library-book-$from'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(Offset(box.left + box.width * 0.2, box.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('SNO-F-LIB-02: под замком расположение не меняется', () {
    testWidgets('SNO-F-LIB-02: перенос книги не меняет ни одной строки', (
      WidgetTester tester,
    ) async {
      bigScreen(tester);
      await fillShelf();
      final List<String> before = await layoutOf();
      await pumpShelf(tester, testServices(data: data), locked: true);

      // Внутри категории и в чужую категорию.
      await dragBook(tester, 'c', 'a');
      await dragBook(tester, 'a', 'd');

      expect(await layoutOf(), before);

      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: без замка тот же жест книгу переносит', (
      WidgetTester tester,
    ) async {
      // Проверка самой проверки: жест настоящий, и держит его замок.
      bigScreen(tester);
      await fillShelf();
      final List<String> before = await layoutOf();
      await pumpShelf(tester, testServices(data: data), locked: false);

      await dragBook(tester, 'c', 'a');

      expect(await layoutOf(), isNot(before));

      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: в шапке нет ни порядка, ни новой категории', (
      WidgetTester tester,
    ) async {
      await fillShelf();
      await pumpShelf(
        tester,
        testServices(data: data),
        locked: true,
        titleSearch: true,
      );

      expect(find.byKey(const Key('library-sort')), findsNothing);
      expect(find.byKey(const Key('library-new-category')), findsNothing);
      expect(find.byKey(const Key('library-open-file')), findsNothing);
      // Поиск по названию остаётся: расположения он не меняет.
      expect(find.byKey(const Key('library-search')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: замок прячет и добавление книг', (
      WidgetTester tester,
    ) async {
      // Полка, с которой книги добавляют: без замка «+» и кнопка в
      // шапке есть, под замком — нет.
      bigScreen(tester);
      await fillShelf();
      await pumpShelf(
        tester,
        testServices(data: data),
        locked: false,
        canAddBooks: true,
      );
      expect(find.byType(AddBookCard), findsWidgets);
      expect(find.byKey(const Key('library-open-file')), findsOneWidget);
      await unmount(tester);

      await pumpShelf(
        tester,
        testServices(data: data),
        locked: true,
        canAddBooks: true,
      );
      expect(find.byType(AddBookCard), findsNothing);
      expect(find.byKey(const Key('library-open-file')), findsNothing);
      expect(find.byKey(const Key('library-book-a')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: под замком книги стоят, как расставлены', (
      WidgetTester tester,
    ) async {
      bigScreen(tester);
      await fillShelf();
      // Выбран порядок по названию, а места книг — обратные ему.
      await placeBook(data, 'c', 'study', position: 0);
      await placeBook(data, 'b', 'study', position: 1);
      await placeBook(data, 'a', 'study', position: 2);
      await data.settings.write(SettingsKeys.shelfSort, ShelfSort.title.name);

      double left(String id) {
        return tester.getTopLeft(find.byKey(Key('library-book-$id'))).dx;
      }

      // Без замка действует выбранный порядок.
      await pumpShelf(tester, testServices(data: data), locked: false);
      expect(left('a'), lessThan(left('b')));
      expect(left('b'), lessThan(left('c')));
      await unmount(tester);

      // Под замком — порядок мест: его запоминает участник, и открытая
      // книга его не меняет.
      await pumpShelf(tester, testServices(data: data), locked: true);
      expect(left('c'), lessThan(left('b')));
      expect(left('b'), lessThan(left('a')));
      // Выбранный порядок при этом не стёрт: замок снимут — он вернётся.
      expect(
        await data.settings.read(SettingsKeys.shelfSort),
        ShelfSort.title.name,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: у книги и у категории нет меню', (
      WidgetTester tester,
    ) async {
      bigScreen(tester);
      await fillShelf();
      await pumpShelf(tester, testServices(data: data), locked: true);

      expect(find.byKey(const Key('library-book-a')), findsOneWidget);
      expect(find.byKey(const Key('library-menu-a')), findsNothing);
      expect(find.byKey(const Key('shelf-menu-study')), findsNothing);
      expect(find.byKey(const Key('shelf-menu-rest')), findsNothing);
      expect(find.byType(AddBookCard), findsNothing);

      // Правая кнопка мыши меню тоже не открывает.
      await tester.tap(
        find.byKey(const Key('library-book-a')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-action-open')), findsNothing);
      expect(find.byKey(const Key('book-action-remove')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: книга под замком открывается нажатием', (
      WidgetTester tester,
    ) async {
      bigScreen(tester);
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await fillShelf();
      final List<String> before = await layoutOf();
      await pumpShelf(tester, testServices(data: data), locked: true);

      await tester.tap(find.byKey(const Key('library-book-b')));
      await tester.pumpAndSettle();
      final ReaderScreen reader = tester.widget(find.byType(ReaderScreen));
      expect(reader.book.id, 'b');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Открытая книга места на полке не меняет.
      expect(await layoutOf(), before);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: без замка всё, что было, на месте', (
      WidgetTester tester,
    ) async {
      bigScreen(tester);
      await fillShelf();
      await pumpShelf(tester, testServices(data: data), locked: false);

      expect(find.byKey(const Key('library-sort')), findsOneWidget);
      expect(find.byKey(const Key('library-new-category')), findsOneWidget);
      expect(find.byKey(const Key('library-menu-a')), findsOneWidget);
      expect(find.byKey(const Key('shelf-menu-study')), findsOneWidget);

      await unmount(tester);
    });
  });
}
