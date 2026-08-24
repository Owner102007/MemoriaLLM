import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/ui/library/book_card.dart';
import 'package:memoria/ui/library/library_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// Файл, который «выбирает человек» в системном диалоге.
const PickedFile onePicked = PickedFile(
  path: 'test/fixtures/basic_text.pdf',
  name: 'Онегин.pdf',
);

BookCategory _category(String id, String title, {int position = 0}) {
  return BookCategory(
    id: id,
    title: title,
    position: position,
    createdAt: DateTime.utc(2026, 8, 20),
  );
}

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpShelf(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    await tester.pumpAndSettle();
  }

  /// Снимает дерево и даёт drift прибраться: живые запросы при отписке
  /// планируют уборку обычным таймером, а в widget-тестах время
  /// подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('полка из категорий', () {
    testWidgets('книги без категории лежат в постоянном разделе', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      expect(
        find.byKey(const Key('shelf-title-')),
        findsOneWidget,
        reason: 'раздел «Без категории» имеет пустой идентификатор',
      );
      expect(find.text(kUncategorizedTitle), findsOneWidget);
      expect(find.byKey(const Key('library-book-book-1')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('у категории свой заголовок и своя сетка', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      await data.library.save(testBook());
      await data.library.moveToCategory('book-1', 'study');
      await pumpShelf(tester, testServices(data: data));

      expect(find.text('Учёба'), findsOneWidget);
      expect(find.byKey(const Key('shelf-grid-study')), findsOneWidget);
      // Пустой «Без категории» рядом с настоящей категорией не показывается.
      expect(find.text(kUncategorizedTitle), findsNothing);

      await unmount(tester);
    });

    testWidgets('кнопка «+» стоит после последней книги', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      await data.library.save(testBook());
      await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
      await data.library.moveToCategory('book-1', 'study');
      await data.library.moveToCategory('book-2', 'study');
      await pumpShelf(tester, testServices(data: data));

      expect(find.byType(AddBookCard), findsOneWidget);
      expect(find.byKey(const Key('library-add-study')), findsOneWidget);

      // «Последняя» — не фигура речи: кнопка обязана быть правее и ниже
      // всех книг, иначе она встанет в середину полки.
      final double plus = tester
          .getTopLeft(find.byKey(const Key('library-add-study')))
          .dx;
      final double lastBook = tester
          .getTopLeft(find.byKey(const Key('library-book-book-2')))
          .dx;
      expect(plus, greaterThan(lastBook));

      await unmount(tester);
    });

    testWidgets('пустая категория показывает одну кнопку «+»', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      await pumpShelf(tester, testServices(data: data));

      expect(find.byType(AddBookCard), findsOneWidget);
      expect(find.byType(BookCard), findsNothing);

      await unmount(tester);
    });

    testWidgets('пока обложки нет, на её месте название книги', (
      WidgetTester tester,
    ) async {
      // Пустая заливка цветом темы в роли «ещё не готово» — та самая
      // ловушка, на которой проект потерял итерацию проверки в S4.3.
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      expect(find.text('Пиковая дама'), findsWidgets);

      await unmount(tester);
    });
  });

  group('добавление книг', () {
    testWidgets('«+» в категории заводит книги именно в неё', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      final AppServices services = testServices(
        data: data,
        picked: onePicked,
        batch: const <PickedFile>[onePicked],
      );
      await pumpShelf(tester, services);

      await tester.tap(find.byKey(const Key('library-add-study')));
      await tester.pumpAndSettle();

      final List<Book> books = await data.library.books();
      expect(books.length, 1);
      expect(books.single.categoryId, 'study');

      await unmount(tester);
    });

    testWidgets('кнопка в шапке кладёт книги в «Без категории»', (
      WidgetTester tester,
    ) async {
      final AppServices services = testServices(
        data: data,
        picked: onePicked,
        batch: const <PickedFile>[onePicked],
      );
      await pumpShelf(tester, services);

      await tester.tap(find.byKey(const Key('library-open-file')));
      await tester.pumpAndSettle();

      final List<Book> books = await data.library.books();
      expect(books.single.categoryId, isNull);

      await unmount(tester);
    });

    testWidgets('закрытый диалог не заводит пустых книг', (
      WidgetTester tester,
    ) async {
      final AppServices services = testServices(
        data: data,
        batch: const <PickedFile>[],
      );
      await pumpShelf(tester, services);

      await tester.tap(find.byKey(const Key('library-open-file')));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);

      await unmount(tester);
    });
  });

  group('порядок книг', () {
    testWidgets('выбранный порядок переживает перезапуск экрана', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(shelfSortTitle(ShelfSort.title)).last);
      await tester.pumpAndSettle();

      expect(
        await data.settings.read(SettingsKeys.shelfSort),
        ShelfSort.title.name,
      );

      await unmount(tester);
    });
  });

  group('снятие книги с полки', () {
    testWidgets('книга исчезает сразу, а вернуть её можно', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      final MemoryBookStorage storage = MemoryBookStorage();
      await pumpShelf(tester, testServices(data: data, storage: storage));

      await tester.tap(find.byKey(const Key('library-menu-book-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-action-remove')));
      await tester.pumpAndSettle();

      // Исчезла с полки в тот же миг — иначе непонятно, сработало ли
      // нажатие.
      expect(await data.library.books(), isEmpty);
      expect(find.text('Вернуть'), findsOneWidget);

      await tester.tap(find.text('Вернуть'));
      await tester.pumpAndSettle();

      expect((await data.library.books()).single.id, 'book-1');
      // Источник при этом не отпускался: своя копия удалена безвозвратно,
      // а закреплённую ссылку заново не выдать — «Вернуть» стало бы
      // обманом.
      await tester.pump(const Duration(seconds: 6));
      expect(storage.released, isEmpty);

      await unmount(tester);
    });

    testWidgets('без отмены источник отпускается, а файл остаётся', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      final MemoryBookStorage storage = MemoryBookStorage();
      await pumpShelf(tester, testServices(data: data, storage: storage));

      await tester.tap(find.byKey(const Key('library-menu-book-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-action-remove')));
      await tester.pumpAndSettle();

      // Окно отмены закрылось — только теперь отпускается закреплённая
      // ссылка и удаляется наша копия. Чужой файл не трогается никогда:
      // об этом заботится само хранилище.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(await data.library.books(), isEmpty);
      expect(storage.released.single, testBook().source);

      await unmount(tester);
    });
  });

  group('категории', () {
    testWidgets('новая категория заводится из шапки', (
      WidgetTester tester,
    ) async {
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-new-category')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category-name-field')),
        'Справочники',
      );
      await tester.tap(find.byKey(const Key('category-name-ok')));
      await tester.pumpAndSettle();

      final List<BookCategory> all = await data.categories.categories();
      expect(all.single.title, 'Справочники');
      expect(find.text('Справочники'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('книга переносится в другую категорию', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('library-menu-book-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-action-move')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move-to-study')));
      await tester.pumpAndSettle();

      expect((await data.library.bookById('book-1'))!.categoryId, 'study');

      await unmount(tester);
    });

    testWidgets('убранная категория не уносит книги с собой', (
      WidgetTester tester,
    ) async {
      await data.categories.save(_category('study', 'Учёба'));
      await data.library.save(testBook());
      await data.library.moveToCategory('book-1', 'study');
      await pumpShelf(tester, testServices(data: data));

      await tester.tap(find.byKey(const Key('shelf-menu-study')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Убрать категорию'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category-remove-ok')));
      await tester.pumpAndSettle();

      expect(await data.categories.categories(), isEmpty);
      final List<Book> books = await data.library.books();
      expect(books.single.id, 'book-1');
      expect(books.single.categoryId, isNull);

      await unmount(tester);
    });

    testWidgets('у раздела «Без категории» меню нет вовсе', (
      WidgetTester tester,
    ) async {
      // Его нельзя ни переименовать, ни убрать: полка обязана
      // открываться всегда.
      await data.library.save(testBook());
      await pumpShelf(tester, testServices(data: data));

      expect(find.byKey(const Key('shelf-menu-')), findsNothing);

      await unmount(tester);
    });
  });
}
