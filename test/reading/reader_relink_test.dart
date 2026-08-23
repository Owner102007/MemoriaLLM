import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// Файл, который переехал: книга ведёт на несуществующий путь.
const BookSource _gone = FilePathSource('/нет/такой/книги.pdf');

/// Файл, который читатель показывает заново.
const String _foundPath = '/книги/Онегин.pdf';
const PickedFile _found = PickedFile(name: 'Онегин.pdf', path: _foundPath);

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  /// Снимает дерево виджетов и даёт базе прибраться: живые запросы drift
  /// при отписке планируют уборку обычным таймером, а в widget-тестах
  /// время подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('файл недоступен — книга ждёт, а не пропадает', (
    WidgetTester tester,
  ) async {
    final Book book = testBook().copyWith(source: _gone);
    await data.library.save(book);

    final _MissingThenFound opener = _MissingThenFound();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: AppServices(
            data: data,
            opener: opener,
            picker: FakeBookFilePicker(_found),
            storage: MemoryBookStorage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Не тупик с кнопкой «назад»: сказано, что случилось, и предложено
    // показать файл заново.
    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(find.byKey(const Key('reader-relink')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-relink')));
    await tester.pumpAndSettle();

    // Книга открылась, и путь у неё теперь новый.
    expect(find.byKey(const Key('reader-relink')), findsNothing);
    final Book? saved = await data.library.bookById(book.id);
    expect(saved!.source, const FilePathSource(_foundPath));
    // Идентификатор прежний — значит, место чтения, цитаты и заметки на
    // месте: они принадлежат книге, а не файлу.
    expect(saved.id, book.id);

    await unmount(tester);
  });

  testWidgets('повреждённый файл перевыбором не лечится', (
    WidgetTester tester,
  ) async {
    final Book book = testBook().copyWith(source: _gone);
    await data.library.save(book);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: AppServices(
            data: data,
            opener: FakeDocumentOpener(
              FakeReaderDocument.blank(1),
              failure: const DocumentOpenException(
                DocumentProblem.damaged,
                _gone,
              ),
            ),
            picker: FakeBookFilePicker(_found),
            storage: MemoryBookStorage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(find.byKey(const Key('reader-relink')), findsNothing);

    await unmount(tester);
  });
}

/// Открыватель, который в первый раз не находит файл, а потом находит.
class _MissingThenFound implements DocumentOpener {
  int calls = 0;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    calls++;
    if (calls == 1) {
      throw const DocumentOpenException(DocumentProblem.missing, _gone);
    }
    return FakeReaderDocument(pages: <String>['страница один']);
  }
}
