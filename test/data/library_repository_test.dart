import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/sync/hlc.dart';

import 'test_data.dart';

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
  });

  tearDown(() async {
    await data.close();
  });

  test('книга сохраняется и читается целиком', () async {
    await data.library.save(testBook());
    final Book? loaded = await data.library.bookById('book-1');

    expect(loaded, isNotNull);
    expect(loaded!.title, 'Пиковая дама');
    expect(loaded.author, 'Пушкин');
    expect(loaded.fileSize, 1024);
    expect(loaded.fileHash, 'hash-1');
    expect(loaded.addedAt, DateTime.utc(2026, 8, 1, 12));
    expect(loaded.pageCount, isNull);
    expect(loaded.openedAt, isNull);
  });

  test('повторное сохранение обновляет, а не двоит', () async {
    await data.library.save(testBook());
    await data.library.save(testBook().copyWith(pageCount: 320));

    final List<Book> all = await data.library.books();
    expect(all, hasLength(1));
    expect(all.single.pageCount, 320);
  });

  test('книга ищется по отпечатку файла', () async {
    await data.library.save(testBook());
    expect(await data.library.bookByHash('hash-1'), isNotNull);
    expect(await data.library.bookByHash('другой'), isNull);
  });

  test('открытие книги отмечается', () async {
    await data.library.save(testBook());
    final DateTime when = DateTime.utc(2026, 8, 5, 21, 30);
    await data.library.markOpened('book-1', when);

    final Book? loaded = await data.library.bookById('book-1');
    expect(loaded?.openedAt, when);
  });

  test('удаление оставляет надгробие, а не стирает строку', () async {
    await data.library.save(testBook());
    await data.library.delete('book-1');

    expect(await data.library.bookById('book-1'), isNull);
    expect(await data.library.books(), isEmpty);
    expect(await data.library.bookByHash('hash-1'), isNull);
    expect(await data.library.purgeDeleted(), 1);
  });

  test('список отсортирован: свежие книги сверху', () async {
    await data.library.save(testBook(id: 'old', hash: 'h-old'));
    final Book fresh = testBook(id: 'new', hash: 'h-new');
    await data.library.save(fresh.copyWith(addedAt: DateTime.utc(2026, 8, 6)));

    final List<Book> all = await data.library.books();
    expect(all.map((Book b) => b.id), <String>['new', 'old']);
  });

  test('живой список обновляется сам', () async {
    final Stream<List<Book>> stream = data.library.watchBooks();
    expect(await stream.first, isEmpty);

    await data.library.save(testBook());
    expect(await stream.first, hasLength(1));
  });

  test('каждая запись получает растущую метку HLC', () async {
    await data.library.save(testBook());
    final Hlc first = data.clock.last;

    await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
    final Hlc second = data.clock.last;

    expect(second.compareTo(first), greaterThan(0));
    expect(second.nodeId, first.nodeId);
  });
}
