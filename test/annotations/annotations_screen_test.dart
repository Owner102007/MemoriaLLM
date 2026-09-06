import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/ui/annotations/annotations_screen.dart';

import '../data/test_data.dart';

/// Экран «Цитаты и заметки».
///
/// Живая база в памяти и те же репозитории, что и в приложении: экран
/// проверяется целиком, а не по кускам.
void main() {
  late AppData data;
  late Book book;

  setUp(() async {
    data = await openTestData();
    book = testBook();
    await data.library.save(book);
  });

  tearDown(() async {
    await data.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationsScreen(book: book, annotations: data.annotations),
      ),
    );
    // Списки приезжают потоками из базы, и до экрана они доходят не в
    // тот же кадр.
    await tester.pumpAndSettle();
  }

  /// Снимает дерево и даёт drift прибраться.
  ///
  /// Живые запросы при отписке планируют уборку **обычным таймером**, а в
  /// widget-тестах время подменено: нулевой кадр его не дожидается, и
  /// тест валится сообщением «A Timer is still pending» — а следом висит
  /// до своего десятиминутного предела. На этом сгорел прогон №93.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> addQuote({
    required String id,
    required int page,
    required String content,
    String? note,
  }) async {
    await data.annotations.saveQuote(
      Quote(
        id: id,
        bookId: book.id,
        page: page,
        content: content,
        createdAt: DateTime.utc(2026, 9, 6),
      ),
    );
    if (note != null) {
      await data.annotations.saveNote(
        Note(
          id: 'note-$id',
          bookId: book.id,
          quoteId: id,
          page: page,
          body: note,
          createdAt: DateTime.utc(2026, 9, 6),
          updatedAt: DateTime.utc(2026, 9, 6),
        ),
      );
    }
  }

  testWidgets('пустая книга говорит, откуда берутся цитаты', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('annotations-empty')), findsOneWidget);
    expect(find.textContaining('Выделите текст'), findsOneWidget);
    await close(tester);
  });

  testWidgets('цитата и её заметка стоят в одной карточке', (
    WidgetTester tester,
  ) async {
    await addQuote(
      id: 'q1',
      page: 7,
      content: 'две неподвижные идеи',
      note: 'тут автор себе противоречит',
    );
    await open(tester);

    expect(find.text('две неподвижные идеи'), findsOneWidget);
    expect(find.text('тут автор себе противоречит'), findsOneWidget);
    expect(find.text('Страница 7'), findsOneWidget);
    await close(tester);
  });

  testWidgets('порядок — по страницам', (WidgetTester tester) async {
    await addQuote(id: 'q2', page: 40, content: 'вторая цитата');
    await addQuote(id: 'q1', page: 7, content: 'первая цитата');
    await open(tester);

    final Offset first = tester.getTopLeft(find.text('первая цитата'));
    final Offset second = tester.getTopLeft(find.text('вторая цитата'));
    expect(first.dy, lessThan(second.dy));
    await close(tester);
  });

  testWidgets('поиск отсекает лишнее и переживает другую форму слова', (
    WidgetTester tester,
  ) async {
    await addQuote(id: 'q1', page: 7, content: 'две неподвижные идеи');
    await addQuote(id: 'q2', page: 9, content: 'холодная зима в деревне');
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('annotations-search-field')),
      'неподвижный',
    );
    await tester.pump();

    expect(find.text('две неподвижные идеи'), findsOneWidget);
    expect(find.text('холодная зима в деревне'), findsNothing);
    await close(tester);
  });

  testWidgets('ничего не нашлось — так и говорится', (
    WidgetTester tester,
  ) async {
    await addQuote(id: 'q1', page: 7, content: 'две неподвижные идеи');
    await open(tester);

    await tester.enterText(
      find.byKey(const Key('annotations-search-field')),
      'слоны',
    );
    await tester.pump();

    expect(find.text('Ничего не нашлось.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('удаление уносит и цитату, и её заметку', (
    WidgetTester tester,
  ) async {
    await addQuote(id: 'q1', page: 7, content: 'две идеи', note: 'мысль');
    await open(tester);

    await tester.tap(find.byKey(const Key('annotation-delete-q1')));
    await tester.pumpAndSettle();

    expect(find.text('две идеи'), findsNothing);
    expect(await data.annotations.quotes(book.id), isEmpty);
    expect(await data.annotations.notes(book.id), isEmpty);
    await close(tester);
  });

  testWidgets('выгрузка показывает готовый Markdown', (
    WidgetTester tester,
  ) async {
    await addQuote(id: 'q1', page: 7, content: 'две идеи', note: 'мысль');
    await open(tester);

    await tester.tap(find.byKey(const Key('annotations-export-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('annotations-export-text')), findsOneWidget);
    expect(find.textContaining('> две идеи'), findsOneWidget);
    expect(find.byKey(const Key('annotations-export-copy')), findsOneWidget);
    await close(tester);
  });

  testWidgets('у пустой книги выгружать нечего', (WidgetTester tester) async {
    await open(tester);
    final IconButton button = tester.widget<IconButton>(
      find.byKey(const Key('annotations-export-button')),
    );
    expect(button.onPressed, isNull);
    await close(tester);
  });
}
