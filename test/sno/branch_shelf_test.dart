import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/ui/library/book_card.dart';
import 'package:memoria/ui/library/library_screen.dart';

import '../data/test_data.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-02: полка сборки ветви — без добавления книг.
///
/// Полка получает признак параметром, поэтому проверяется одним
/// прогоном, без флагов сборки.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpShelf(
    WidgetTester tester,
    AppServices services, {
    required bool canAddBooks,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(services: services, canAddBooks: canAddBooks),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('SNO-F-CFG-02: полка без добавления', () {
    testWidgets('SNO-F-CFG-02: пустая полка говорит, откуда берутся книги', (
      WidgetTester tester,
    ) async {
      await pumpShelf(tester, testServices(data: data), canAddBooks: false);

      expect(find.byKey(const Key('library-empty-branch')), findsOneWidget);
      expect(find.textContaining('Добавить книги или архив'), findsOneWidget);
      // Ни одной кнопки, которая вела бы к книгам устройства.
      expect(find.byKey(const Key('library-open-file-empty')), findsNothing);
      expect(find.byKey(const Key('library-open-file')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-02: в участке нет «+», в шапке нет кнопки', (
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
      await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
      await placeBook(data, 'book-1', 'study');
      await pumpShelf(tester, testServices(data: data), canAddBooks: false);

      // Книги на месте — и в категории, и без неё.
      expect(find.byKey(const Key('library-book-book-1')), findsOneWidget);
      expect(find.byKey(const Key('library-book-book-2')), findsOneWidget);
      expect(find.byType(AddBookCard), findsNothing);
      expect(find.byKey(const Key('library-add-study')), findsNothing);
      expect(find.byKey(const Key('library-add-loose')), findsNothing);
      expect(find.byKey(const Key('library-open-file')), findsNothing);
      // Остальное в шапке на месте: полка остаётся полкой.
      expect(find.byKey(const Key('library-sort')), findsOneWidget);
      expect(find.byKey(const Key('library-new-category')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-02: пустая категория не зовёт нажать «+»', (
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
      await pumpShelf(tester, testServices(data: data), canAddBooks: false);

      expect(find.text('Учёба'), findsOneWidget);
      expect(find.text('Пока пусто.'), findsOneWidget);
      expect(find.textContaining('Нажмите «+»'), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-02: с признаком добавления полка прежняя', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data), canAddBooks: true);

      expect(find.byType(AddBookCard), findsOneWidget);
      expect(find.byKey(const Key('library-open-file')), findsOneWidget);

      await unmount(tester);
    });
  });
}
