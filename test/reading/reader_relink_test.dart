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
import '../support/test_services.dart';

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

  Future<void> pumpGone(WidgetTester tester, Book book) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          services: AppServices(
            data: data,
            opener: _MissingThenFound(),
            picker: FakeBookFilePicker(_found),
            storage: MemoryBookStorage(),
            coverStore: MemoryCoverStore(),
            access: FakeStorageAccess(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('BUG-19: чужой файл — вопрос, и отказ книгу не меняет', (
    WidgetTester tester,
  ) async {
    // Отпечаток книги выдуман — выбранный файл для неё чужой.
    final Book book = testBook().copyWith(source: _gone, pageCount: 412);
    await data.library.save(book);
    await pumpGone(tester, book);

    await tester.tap(find.byKey(const Key('reader-relink')));
    await tester.pumpAndSettle();

    // Прежде книга молча привязывалась к чему угодно.
    expect(find.byKey(const Key('relink-mismatch')), findsOneWidget);
    expect(find.textContaining('страниц: 412'), findsOneWidget);

    await tester.tap(find.byKey(const Key('relink-pick-other')));
    await tester.pumpAndSettle();

    // Книга осталась как была, и файл можно показать ещё раз.
    expect(find.byKey(const Key('relink-mismatch')), findsNothing);
    expect(find.byKey(const Key('reader-relink')), findsOneWidget);
    final Book? saved = await data.library.bookById(book.id);
    expect(saved!.source, _gone);
    expect(saved.fileHash, book.fileHash);

    await unmount(tester);
  });

  testWidgets('BUG-19: «Привязать всё равно» привязывает и открывает', (
    WidgetTester tester,
  ) async {
    final Book book = testBook().copyWith(source: _gone);
    await data.library.save(book);
    await pumpGone(tester, book);

    await tester.tap(find.byKey(const Key('reader-relink')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relink-force')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-relink')), findsNothing);
    expect(find.byKey(const Key('reader-failure-message')), findsNothing);
    final Book? saved = await data.library.bookById(book.id);
    expect(saved!.id, book.id);
    expect(saved.source, const FilePathSource(_foundPath));
    expect(saved.fileHash, await memoryBookHash());

    await unmount(tester);
  });

  testWidgets('файл недоступен — книга ждёт, а не пропадает', (
    WidgetTester tester,
  ) async {
    // Отпечаток книги — тот же, что у файла, который покажут заново:
    // файл переехал, а не подменён (BUG-19).
    final Book book = testBook(hash: await memoryBookHash())
        .copyWith(source: _gone);
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
            coverStore: MemoryCoverStore(),
            access: FakeStorageAccess(),
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
            coverStore: MemoryCoverStore(),
            access: FakeStorageAccess(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(find.byKey(const Key('reader-relink')), findsNothing);

    await unmount(tester);
  });

  testWidgets('BUG-46: где файл не выбирают, сказано, откуда книга вернётся', (
    WidgetTester tester,
  ) async {
    // Так экран чтения открывает полка сборки ветви СНО2026: свои PDF
    // там не добавляются, и книгу к своему файлу привязать нельзя.
    final Book book = testBook().copyWith(source: _gone);
    await data.library.save(book);
    final _MissingThenFound opener = _MissingThenFound();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          canRelink: false,
          services: AppServices(
            data: data,
            opener: opener,
            picker: FakeBookFilePicker(_found),
            storage: MemoryBookStorage(),
            coverStore: MemoryCoverStore(),
            access: FakeStorageAccess(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-failure-message')), findsOneWidget);
    expect(find.byKey(const Key('reader-relink')), findsNothing);
    expect(find.text('Выбрать файл заново'), findsNothing);
    expect(find.byKey(const Key('reader-readd-archive')), findsOneWidget);
    expect(
      find.textContaining('Добавьте архив с литературой ещё раз'),
      findsOneWidget,
    );
    // Книга осталась как была, и файл никто не спрашивал.
    expect(opener.calls, 1);
    expect((await data.library.bookById(book.id))!.source, _gone);

    await unmount(tester);
  });

  testWidgets('BUG-46: в основном приложении выбор файла на месте', (
    WidgetTester tester,
  ) async {
    final Book book = testBook().copyWith(source: _gone);
    await data.library.save(book);
    await pumpGone(tester, book);

    expect(find.byKey(const Key('reader-relink')), findsOneWidget);
    expect(find.byKey(const Key('reader-readd-archive')), findsNothing);

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
