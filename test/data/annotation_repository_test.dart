import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';

import 'test_data.dart';

Quote _quote({String id = 'quote-1', int page = 7}) {
  return Quote(
    id: id,
    bookId: 'book-1',
    page: page,
    content: 'Две неподвижные идеи не могут вместе существовать',
    createdAt: DateTime.utc(2026, 8, 2, page),
    context: 'Абзац вокруг выделения',
    color: 0xFFA32F35,
  );
}

Note _note({String id = 'note-1', String body = 'Проверить перевод'}) {
  return Note(
    id: id,
    bookId: 'book-1',
    page: 7,
    body: body,
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    quoteId: 'quote-1',
  );
}

Bookmark _bookmark({String id = 'mark-1', int page = 3}) {
  return Bookmark(
    id: id,
    bookId: 'book-1',
    page: page,
    createdAt: DateTime.utc(2026, 8, 3),
    fragment: 1,
    label: 'Начало главы',
  );
}

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    await data.library.save(testBook());
  });

  tearDown(() async {
    await data.close();
  });

  test('цитата сохраняется вместе с контекстом и цветом', () async {
    await data.annotations.saveQuote(_quote());
    final List<Quote> quotes = await data.annotations.quotes('book-1');

    expect(quotes, hasLength(1));
    expect(quotes.single.content, startsWith('Две неподвижные'));
    expect(quotes.single.context, 'Абзац вокруг выделения');
    expect(quotes.single.color, 0xFFA32F35);
    expect(quotes.single.page, 7);
  });

  test('цитаты идут свежими сверху', () async {
    await data.annotations.saveQuote(_quote(id: 'q-early', page: 1));
    await data.annotations.saveQuote(_quote(id: 'q-late', page: 9));

    final List<Quote> quotes = await data.annotations.quotes('book-1');
    expect(quotes.map((Quote q) => q.id), <String>['q-late', 'q-early']);
  });

  test('удалённая цитата исчезает из выдачи', () async {
    await data.annotations.saveQuote(_quote());
    await data.annotations.deleteQuote('quote-1');

    expect(await data.annotations.quotes('book-1'), isEmpty);
  });

  test('заметка правится, а не дублируется', () async {
    await data.annotations.saveQuote(_quote());
    await data.annotations.saveNote(_note());
    await data.annotations.saveNote(_note(body: 'Перевод точный'));

    final List<Note> notes = await data.annotations.notes('book-1');
    expect(notes, hasLength(1));
    expect(notes.single.body, 'Перевод точный');
    expect(notes.single.quoteId, 'quote-1');
  });

  test('заметка без цитаты тоже допустима', () async {
    final Note loose = Note(
      id: 'note-loose',
      bookId: 'book-1',
      page: 12,
      body: 'Пометка на полях',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
    );
    await data.annotations.saveNote(loose);

    final List<Note> notes = await data.annotations.notes('book-1');
    expect(notes.single.quoteId, isNull);
  });

  test('удалённая заметка исчезает из выдачи', () async {
    await data.annotations.saveQuote(_quote());
    await data.annotations.saveNote(_note());
    await data.annotations.deleteNote('note-1');

    expect(await data.annotations.notes('book-1'), isEmpty);
  });

  test('закладки идут по возрастанию страниц', () async {
    await data.annotations.saveBookmark(_bookmark(id: 'm-9', page: 9));
    await data.annotations.saveBookmark(_bookmark(id: 'm-2', page: 2));

    final List<Bookmark> marks = await data.annotations.bookmarks('book-1');
    expect(marks.map((Bookmark m) => m.id), <String>['m-2', 'm-9']);
    expect(marks.first.fragment, 1);
    expect(marks.first.label, 'Начало главы');
  });

  test('удалённая закладка исчезает из выдачи', () async {
    await data.annotations.saveBookmark(_bookmark());
    await data.annotations.deleteBookmark('mark-1');

    expect(await data.annotations.bookmarks('book-1'), isEmpty);
  });

  test('живой список цитат обновляется сам', () async {
    final Stream<List<Quote>> quotes = data.annotations.watchQuotes('book-1');
    expect(await quotes.first, isEmpty);

    await data.annotations.saveQuote(_quote());
    expect(await quotes.first, hasLength(1));
  });

  test('аннотации соседней книги не подмешиваются', () async {
    await data.library.save(testBook(id: 'book-2', hash: 'hash-2'));
    await data.annotations.saveQuote(_quote());

    expect(await data.annotations.quotes('book-2'), isEmpty);
    expect(await data.annotations.notes('book-2'), isEmpty);
    expect(await data.annotations.bookmarks('book-2'), isEmpty);
  });
}
