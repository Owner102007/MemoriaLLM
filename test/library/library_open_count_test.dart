import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/ui/library/library_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/test_services.dart';

/// Открыватель, который отдаёт книгу, когда скажет тест.
class _GatedOpener implements DocumentOpener {
  _GatedOpener(this.gate);

  /// Книга появится, когда тест завершит это ожидание.
  final Completer<ReaderDocument> gate;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) =>
      gate.future;
}

/// BUG-09: открытие книги засчитывалось дважды — на полке, ещё до
/// открытия, и в чтении. Книга, которая не открылась, всё равно
/// поднималась в «Сначала недавние», а будущий счётчик открытий удвоил
/// бы вес книги на карте.
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

  Future<DateTime?> openedAt() async {
    final Book? book = await data.library.bookById('book-1');
    return book?.openedAt;
  }

  testWidgets('BUG-09: открытие засчитывается, когда книга открылась, '
      'а не по нажатию на полке', (WidgetTester tester) async {
    final Completer<ReaderDocument> gate = Completer<ReaderDocument>();
    await data.library.save(testBook());
    await pumpShelf(
      tester,
      testServices(data: data, opener: _GatedOpener(gate)),
    );

    await tester.tap(find.byKey(const Key('library-book-book-1')));
    // Экран чтения открыт и ждёт книгу. Пока она открывается, на нём
    // крутится индикатор, и «дождаться покоя» нельзя — кадры считаем сами.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('reader-loading')), findsOneWidget);
    expect(
      await openedAt(),
      isNull,
      reason: 'книга ещё не открылась — считать нечего',
    );

    gate.complete(FakeReaderDocument(pages: <String>['текст']));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-loading')), findsNothing);
    expect(await openedAt(), isNotNull, reason: 'открылась — засчитано');

    await unmount(tester);
  });

  testWidgets('BUG-09: книга, которая не открылась, в недавние не '
      'поднимается', (WidgetTester tester) async {
    final Book book = testBook();
    await data.library.save(book);
    await pumpShelf(
      tester,
      testServices(
        data: data,
        opener: FakeDocumentOpener(
          FakeReaderDocument(pages: <String>['текст']),
          failure: DocumentOpenException(DocumentProblem.missing, book.source),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('library-book-book-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(await openedAt(), isNull);

    await unmount(tester);
  });
}
