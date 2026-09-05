import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/annotations/markdown_export.dart';

/// Выгрузка цитат и заметок и поиск по ним.
///
/// Выгрузка — обещание, что написанное читателем принадлежит читателю:
/// её проверяем на составе и порядке, а не на красоте.
Quote quote({
  required String id,
  required int page,
  required String content,
}) {
  return Quote(
    id: id,
    bookId: 'book-1',
    page: page,
    content: content,
    createdAt: DateTime.utc(2026, 9, 6),
  );
}

Note note({
  required String id,
  required int page,
  required String body,
  String? quoteId,
}) {
  return Note(
    id: id,
    bookId: 'book-1',
    quoteId: quoteId,
    page: page,
    body: body,
    createdAt: DateTime.utc(2026, 9, 6),
    updatedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('выгрузка', () {
    test('порядок — по страницам, а не по времени', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Пиковая дама',
        quotes: <Quote>[
          quote(id: 'q2', page: 40, content: 'вторая'),
          quote(id: 'q1', page: 7, content: 'первая'),
        ],
        notes: const <Note>[],
      );
      expect(
        markdown.indexOf('Страница 7'),
        lessThan(markdown.indexOf('Страница 40')),
      );
    });

    test('заметка идёт за своей цитатой', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Пиковая дама',
        quotes: <Quote>[quote(id: 'q1', page: 7, content: 'две идеи')],
        notes: <Note>[
          note(id: 'n1', page: 7, body: 'тут автор себе противоречит',
              quoteId: 'q1'),
        ],
      );
      expect(markdown, contains('> две идеи'));
      expect(
        markdown.indexOf('две идеи'),
        lessThan(markdown.indexOf('противоречит')),
      );
    });

    test('заметка сама по себе тоже попадает в выгрузку', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Пиковая дама',
        quotes: const <Quote>[],
        notes: <Note>[note(id: 'n1', page: 12, body: 'просто мысль')],
      );
      expect(markdown, contains('Страница 12'));
      expect(markdown, contains('просто мысль'));
    });

    test('цитата в несколько строк остаётся цитатой целиком', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Книга',
        quotes: <Quote>[
          quote(id: 'q1', page: 3, content: 'первая строка\nвторая строка'),
        ],
        notes: const <Note>[],
      );
      expect(markdown, contains('> первая строка'));
      expect(markdown, contains('> вторая строка'));
    });

    test('автор и дата попадают в шапку', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Пиковая дама',
        author: 'Пушкин',
        quotes: <Quote>[quote(id: 'q1', page: 1, content: 'текст')],
        notes: const <Note>[],
        exportedAt: DateTime.utc(2026, 9, 6),
      );
      expect(markdown, startsWith('# Пиковая дама'));
      expect(markdown, contains('*Пушкин*'));
      expect(markdown, contains('06.09.2026'));
    });

    test('пустая книга выгружается честно, а не пустым файлом', () {
      final String markdown = annotationsToMarkdown(
        bookTitle: 'Книга',
        quotes: const <Quote>[],
        notes: const <Note>[],
      );
      expect(markdown, contains('# Книга'));
      expect(markdown, contains('Пока пусто'));
    });
  });

  group('поиск по цитатам', () {
    test('находит по другой форме слова', () {
      // Нормализация — та же, что у поиска по книгам устройства: своей
      // второй в проекте быть не должно. Короткие слова стеммер не
      // трогает намеренно, поэтому проверяется длинное.
      expect(matchesQuery('две неподвижные идеи', 'неподвижный'), isTrue);
    });

    test('находит, когда в тексте латинские двойники букв', () {
      // `ВОЙНА` с латинскими `В`, `О`, `Н`, `А` выглядит точно так же и
      // совпадает с настоящим нулём символов.
      expect(matchesQuery('BOЙHA и мир', 'война'), isTrue);
    });

    test('ищет по всем словам запроса сразу', () {
      expect(matchesQuery('две неподвижные идеи', 'неподвижные идеи'), isTrue);
      expect(matchesQuery('две неподвижные идеи', 'неподвижные слоны'), isFalse);
    });

    test('пустой запрос подходит всему', () {
      expect(matchesQuery('что угодно', '   '), isTrue);
    });
  });
}
