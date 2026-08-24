import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';

import 'test_data.dart';

BookCategory _category(String id, {int position = 0, String? title}) {
  return BookCategory(
    id: id,
    title: title ?? 'Категория $id',
    position: position,
    createdAt: DateTime.utc(2026, 8, 20, 10),
  );
}

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<List<String>> columnsOf(String table) async {
    final List<QueryRow> rows = await data.database
        .customSelect('PRAGMA table_info($table)')
        .get();
    return <String>[for (final QueryRow row in rows) row.read<String>('name')];
  }

  group('таблица категорий', () {
    test('у книги есть колонка категории', () async {
      expect(await columnsOf('books'), contains('category_id'));
    });

    test('категории несут поля слияния наравне с книгами', () async {
      expect(
        await columnsOf('book_categories'),
        containsAll(<String>['hlc', 'node_id', 'modified', 'is_deleted']),
      );
    });
  });

  group('чтение и запись', () {
    test('заведённая категория читается обратно', () async {
      await data.categories.save(_category('study', title: 'Учёба'));
      final BookCategory? loaded = await data.categories.categoryById('study');
      expect(loaded!.title, 'Учёба');
      expect(loaded.position, 0);
    });

    test('категории приходят в порядке полки', () async {
      await data.categories.save(_category('c', position: 2));
      await data.categories.save(_category('a', position: 0));
      await data.categories.save(_category('b', position: 1));
      final List<BookCategory> all = await data.categories.categories();
      expect(all.map((BookCategory c) => c.id), <String>['a', 'b', 'c']);
    });

    test('повторное сохранение правит, а не двоит', () async {
      await data.categories.save(_category('study', title: 'Учёба'));
      await data.categories.save(_category('study', title: 'Учебники'));
      final List<BookCategory> all = await data.categories.categories();
      expect(all.length, 1);
      expect(all.single.title, 'Учебники');
    });

    test('живой список откликается на добавление', () async {
      final Future<List<BookCategory>> first = data.categories
          .watchCategories()
          .firstWhere((List<BookCategory> list) => list.isNotEmpty);
      await data.categories.save(_category('study'));
      expect((await first).single.id, 'study');
    });
  });

  group('книга и её категория', () {
    test('перенос меняет только категорию', () async {
      await data.categories.save(_category('study'));
      await data.library.save(testBook());
      await data.library.moveToCategory('book-1', 'study');

      final Book? moved = await data.library.bookById('book-1');
      expect(moved!.categoryId, 'study');
      // Всё остальное осталось на месте: полка правит одно поле, а не
      // переписывает строку, в которую параллельно пишет чтение.
      expect(moved.title, 'Пиковая дама');
      expect(moved.fileHash, 'hash-1');
    });

    test('возврат в «Без категории» — это пустая ссылка', () async {
      await data.categories.save(_category('study'));
      await data.library.save(testBook());
      await data.library.moveToCategory('book-1', 'study');
      await data.library.moveToCategory('book-1', null);
      final Book? loaded = await data.library.bookById('book-1');
      expect(loaded!.categoryId, isNull);
    });

    test('книга, заведённая до категорий, лежит без категории', () async {
      await data.library.save(testBook());
      final Book? loaded = await data.library.bookById('book-1');
      expect(loaded!.categoryId, isNull);
    });
  });

  group('удаление категории', () {
    test('книги остаются на полке и возвращаются в «Без категории»', () async {
      await data.categories.save(_category('study'));
      await data.library.save(testBook());
      await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
      await data.library.moveToCategory('book-1', 'study');
      await data.library.moveToCategory('book-2', 'study');

      await data.categories.delete('study');

      expect(await data.categories.categories(), isEmpty);
      final List<Book> books = await data.library.books();
      expect(books.length, 2, reason: 'книги не удаляются вместе с полкой');
      for (final Book book in books) {
        expect(book.categoryId, isNull);
      }
    });

    test('удалённая категория — надгробие, а не пустая строка', () async {
      // Иначе удаление на телефоне никогда не доедет до ПК: об этом вся
      // схема с S2.
      await data.categories.save(_category('study'));
      await data.categories.delete('study');
      final List<QueryRow> rows = await data.database
          .customSelect('SELECT is_deleted FROM book_categories')
          .get();
      expect(rows.length, 1);
      expect(rows.single.read<bool>('is_deleted'), isTrue);
    });

    test('чистка уносит помеченные удалёнными', () async {
      await data.categories.save(_category('study'));
      await data.categories.save(_category('fiction', position: 1));
      await data.categories.delete('study');
      expect(await data.categories.purgeDeleted(), 1);
      expect(
        (await data.categories.categories()).map((BookCategory c) => c.id),
        <String>['fiction'],
      );
    });

    test('книги чужой категории не трогаются', () async {
      await data.categories.save(_category('study'));
      await data.categories.save(_category('fiction', position: 1));
      await data.library.save(testBook());
      await data.library.moveToCategory('book-1', 'fiction');

      await data.categories.delete('study');
      final Book? loaded = await data.library.bookById('book-1');
      expect(loaded!.categoryId, 'fiction');
    });
  });

  group('обложка', () {
    test('путь записывается и читается', () async {
      await data.library.save(testBook());
      await data.library.setCoverPath('book-1', '/covers/hash-1-w384.png');
      final Book? loaded = await data.library.bookById('book-1');
      expect(loaded!.coverPath, '/covers/hash-1-w384.png');
    });

    test('обложку можно снять', () async {
      await data.library.save(testBook());
      await data.library.setCoverPath('book-1', '/covers/hash-1-w384.png');
      await data.library.setCoverPath('book-1', null);
      final Book? loaded = await data.library.bookById('book-1');
      expect(loaded!.coverPath, isNull);
    });
  });
}
