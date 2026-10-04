import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

const PickedFile _picked = PickedFile(
  path: 'test/fixtures/basic_text.pdf',
  name: 'voyna_i_mir.pdf',
);

/// Открыватель, у которого каждая третья книга оказывается битой.
///
/// Ровно то, что бывает в настоящей папке: часть файлов оборвалась при
/// скачивании, а по имени этого не видно.
class _EveryThirdBroken implements DocumentOpener {
  int _seen = 0;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    _seen++;
    if (_seen % 3 == 0) {
      throw DocumentOpenException(DocumentProblem.damaged, source);
    }
    return FakeReaderDocument(pages: <String>['раз', 'два']);
  }
}

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  BookImporter importer(
    FakeReaderDocument document, {
    DocumentOpenException? failure,
    String hash = 'hash-fixture',
    String id = 'id-1',
    BookStorage? storage,
  }) {
    return BookImporter(
      library: data.library,
      storage: storage ?? const LocalBookStorage(),
      opener: FakeDocumentOpener(document, failure: failure),
      fingerprint: (BookHandle book) async => hash,
      newId: () => id,
      now: () => DateTime.utc(2026, 8, 7, 12),
    );
  }

  group('импорт файла', () {
    test('книга заводится с числом страниц и признаком текста', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['раз', 'два', 'три']),
      ).register(_picked);

      expect(book.id, 'id-1');
      expect(book.title, 'voyna i mir');
      expect(book.pageCount, 3);
      expect(book.hasTextLayer, isTrue);
      expect(book.fileSize, greaterThan(0));
      expect(await data.library.bookById('id-1'), isNotNull);
    });

    test('файл не копируется: источник указывает на него самого', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);

      final BookSource source = book.source;
      expect(source, isA<FilePathSource>());
      expect((source as FilePathSource).path, _picked.path);
      // Копии не делали — значит, и удалять при снятии с полки нечего.
      expect(source.owned, isFalse);
    });

    test('размер книги берётся из самого файла', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);
      expect(book.fileSize, File(_picked.path!).lengthSync());
    });

    test('скан помечается как книга без текстового слоя', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['', '', '']),
      ).register(_picked);
      expect(book.hasTextLayer, isFalse);
    });

    test('документ закрывается после разбора', () async {
      final FakeReaderDocument document = FakeReaderDocument(
        pages: <String>['текст'],
      );
      await importer(document).register(_picked);
      expect(document.closed, isTrue);
    });

    test('тот же файл не заводит вторую книгу', () async {
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);

      final Book second =
          await importer(
            FakeReaderDocument(pages: <String>['текст', 'ещё']),
            id: 'id-2',
          ).register(
            const PickedFile(
              path: 'test/fixtures/basic_text.pdf',
              name: 'other-name.pdf',
            ),
          );

      // Идентификатор книги остаётся прежним — иначе место, на котором
      // её оставили, потерялось бы при повторном импорте.
      expect(second.id, first.id);
      expect(second.title, first.title);
      expect(second.pageCount, 2);
      expect((await data.library.books()).length, 1);
    });

    test('нечитаемый файл в библиотеку не попадает', () async {
      await expectLater(
        importer(
          FakeReaderDocument.blank(1),
          failure: const DocumentOpenException(
            DocumentProblem.damaged,
            FilePathSource('test/fixtures/truncated.pdf'),
          ),
        ).register(_picked),
        throwsA(isA<DocumentOpenException>()),
      );
      expect(await data.library.books(), isEmpty);
    });

    test('нечитаемая книга отпускает принятый источник', () async {
      final RecordingStorage storage = RecordingStorage();
      await expectLater(
        importer(
          FakeReaderDocument.blank(1),
          storage: storage,
          failure: const DocumentOpenException(
            DocumentProblem.damaged,
            FilePathSource('test/fixtures/truncated.pdf'),
          ),
        ).register(_picked),
        throwsA(isA<DocumentOpenException>()),
      );
      // Иначе в папке приложения копились бы копии нечитаемых книг, а на
      // Android — ещё и закреплённые ссылки в никуда.
      expect(storage.released, <BookSource>[FilePathSource(_picked.path!)]);
    });

    test('BUG-45: отказ открыть файл не трогает книгу на полке', () async {
      final RecordingStorage storage = RecordingStorage();
      // Книга уже стоит на полке, и источник у неё — этот самый файл.
      final Book shelved = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);
      expect(storage.released, isEmpty);

      // Тот же файл выбрали снова, а открыть его на этот раз не вышло.
      await expectLater(
        importer(
          FakeReaderDocument.blank(1),
          storage: storage,
          failure: DocumentOpenException(
            DocumentProblem.missing,
            shelved.source,
          ),
        ).register(_picked),
        throwsA(isA<DocumentOpenException>()),
      );

      // Источник принадлежит книге на полке: отпустить его — значит
      // удалить её копию или отозвать её закреплённую ссылку.
      expect(storage.released, isEmpty);
      final Book? still = await data.library.bookById(shelved.id);
      expect(still?.source, shelved.source);
    });

    test('BUG-17: книга переехала — прежний источник отпущен', () async {
      final RecordingStorage storage = RecordingStorage();
      final Book shelved = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);

      // Ту же книгу (отпечаток тот же) выбрали из другого места.
      const PickedFile moved = PickedFile(
        path: 'test/fixtures/two_columns.pdf',
        name: 'переехала.pdf',
      );
      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(moved);

      expect(again.id, shelved.id, reason: 'книга та же, второй не завелось');
      expect(again.source, FilePathSource(moved.path!));
      // Прежняя копия и прежняя закреплённая ссылка больше ничьи: не
      // отпустить их — значит копить мусор и ссылки в никуда.
      expect(storage.released, <BookSource>[shelved.source]);
    });

    test('BUG-17: тот же источник повторно — отпускать нечего', () async {
      final RecordingStorage storage = RecordingStorage();
      for (int i = 0; i < 2; i++) {
        await importer(
          FakeReaderDocument(pages: <String>['текст']),
          storage: storage,
        ).register(_picked);
      }
      expect(storage.released, isEmpty);
      expect(await data.library.books(), hasLength(1));
    });
  });

  group('BUG-30: снятая и добавленная снова книга', () {
    test('BUG-30: книга получает прежнюю строку, а не новую', () async {
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);
      await data.library.delete(first.id);
      expect(await data.library.books(), isEmpty);

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        id: 'id-2',
      ).register(_picked);

      // Прежде книга заводилась второй строкой с новым идентификатором:
      // надгробие оставалось, а место чтения и цитаты — при нём.
      expect(again.id, first.id);
      expect((await data.library.books()).single.id, first.id);
      expect(await data.library.bookById('id-2'), isNull);
    });

    test('BUG-30: место чтения возвращается вместе с книгой', () async {
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['раз', 'два', 'три']),
      ).register(_picked);
      await data.reading.savePosition(
        ReadingPosition(bookId: first.id, page: 3, progress: 0.9),
      );
      await data.library.delete(first.id);

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['раз', 'два', 'три']),
        id: 'id-2',
      ).register(_picked);

      final ReadingPosition? kept = await data.reading.position(again.id);
      expect(kept!.page, 3);
    });

    test('BUG-30: в прежней категории книга встаёт на прежнее место', () async {
      await data.library.save(testBook(id: 'a', title: 'Аа', hash: 'hash-a'));
      await data.library.save(testBook(id: 'b', title: 'Яя', hash: 'hash-b'));
      await placeBook(data, 'a', 'study');
      await placeBook(data, 'b', 'study', position: 2);
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked, categoryId: 'study');
      await placeBook(data, first.id, 'study', position: 1);
      await data.library.delete(first.id);

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        id: 'id-2',
      ).register(_picked, categoryId: 'study');

      expect(again.id, first.id);
      expect(again.categoryId, 'study');
      expect(again.shelfPosition, 1);
    });

    test('BUG-30: в другой категории книга встаёт последней', () async {
      await data.library.save(testBook(id: 'a', title: 'Аа', hash: 'hash-a'));
      await placeBook(data, 'a', 'fiction', position: 4);
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked, categoryId: 'study');
      await data.library.delete(first.id);

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        id: 'id-2',
      ).register(_picked, categoryId: 'fiction');

      expect(again.id, first.id);
      expect(again.categoryId, 'fiction');
      expect(again.shelfPosition, 5);
    });

    test('BUG-30: без названной категории книга встаёт, где стояла', () async {
      final Book first = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked, categoryId: 'study');
      await placeBook(data, first.id, 'study', position: 3);
      await data.library.delete(first.id);

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        id: 'id-2',
      ).register(_picked);

      expect(again.categoryId, 'study');
      expect(again.shelfPosition, 3);
    });

    test('BUG-30: живая книга с тем же файлом главнее снятой', () async {
      // Надгробие прежней версии и живая книга с одним отпечатком:
      // повторный выбор файла относится к живой.
      await data.library.save(testBook(id: 'old', hash: 'hash-fixture'));
      await data.library.delete('old');
      final Book live = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);
      expect(live.id, 'id-1');

      final Book again = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        id: 'id-2',
      ).register(_picked);

      expect(again.id, 'id-1');
      expect((await data.library.books()).single.id, 'id-1');
    });
  });

  group('импорт пачкой', () {
    /// Импортёр, у которого каждый файл получает свой отпечаток и свой
    /// идентификатор: иначе пачка схлопнется в одну книгу.
    BookImporter batchImporter(
      FakeReaderDocument document, {
      DocumentOpenException? failure,
    }) {
      int seen = 0;
      return BookImporter(
        library: data.library,
        storage: const LocalBookStorage(),
        opener: FakeDocumentOpener(document, failure: failure),
        fingerprint: (BookHandle book) async => 'hash-${seen++}',
        newId: () => 'id-$seen',
        now: () => DateTime.utc(2026, 8, 24, 12),
      );
    }

    List<PickedFile> files(int count) => <PickedFile>[
      for (int i = 0; i < count; i++)
        PickedFile(path: 'test/fixtures/basic_text.pdf', name: 'книга_$i.pdf'),
    ];

    test('все выбранные книги встают на полку', () async {
      final ImportReport report = await batchImporter(
        FakeReaderDocument(pages: <String>['раз', 'два']),
      ).registerAll(files(4));

      expect(report.added.length, 4);
      expect(report.failed, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.total, 4);
      expect((await data.library.books()).length, 4);
    });

    test('книги ложатся в ту категорию, из которой нажали «+»', () async {
      final ImportReport report = await batchImporter(
        FakeReaderDocument(pages: <String>['раз']),
      ).registerAll(files(3), categoryId: 'study');

      for (final Book book in report.added) {
        expect(book.categoryId, 'study');
      }
      for (final Book book in await data.library.books()) {
        expect(book.categoryId, 'study');
      }
    });

    test('без категории книги остаются в «Без категории»', () async {
      final ImportReport report = await batchImporter(
        FakeReaderDocument(pages: <String>['раз']),
      ).registerAll(files(2));
      for (final Book book in report.added) {
        expect(book.categoryId, isNull);
      }
    });

    test('одна битая книга не отменяет остальные двадцать девять', () async {
      // В папке с учебниками обязательно попадётся оборванный файл.
      // Читателю важнее, чтобы встали остальные, чем чтобы импорт
      // провалился целиком.
      int seen = 0;
      final BookImporter mixed = BookImporter(
        library: data.library,
        storage: const LocalBookStorage(),
        opener: _EveryThirdBroken(),
        fingerprint: (BookHandle book) async => 'hash-${seen++}',
        newId: () => 'id-$seen',
        now: () => DateTime.utc(2026, 8, 24, 12),
      );
      final ImportReport report = await mixed.registerAll(files(6));

      expect(report.added.length, 4);
      expect(report.failed.length, 2);
      expect(report.isClean, isFalse);
      // Причина названа человеческими словами и привязана к имени файла.
      expect(report.failed.first.name, 'книга_2.pdf');
      expect(report.failed.first.reason, contains('повреждён'));
    });

    test('о ходе импорта сообщается по файлу за раз', () async {
      final List<String> steps = <String>[];
      await batchImporter(FakeReaderDocument(pages: <String>['раз']))
          .registerAll(
            files(3),
            onProgress: (int done, int total) => steps.add('$done/$total'),
          );
      expect(steps, <String>['1/3', '2/3', '3/3']);
    });

    test('пустой выбор — пустой отчёт, а не ошибка', () async {
      final ImportReport report = await batchImporter(
        FakeReaderDocument(pages: <String>['раз']),
      ).registerAll(const <PickedFile>[]);
      expect(report.total, 0);
      expect(report.isClean, isTrue);
    });

    test('повторный выбор книги не переставляет её с полки', () async {
      // Читатель мог унести книгу в другую категорию руками; повторный
      // импорт того же файла — не повод отменять это решение.
      final BookImporter same = importer(
        FakeReaderDocument(pages: <String>['раз']),
      );
      final Book first = await same.register(_picked, categoryId: 'study');
      expect(first.categoryId, 'study');
      await placeBook(data, first.id, 'fiction');

      await same.register(_picked, categoryId: 'study');
      final Book? again = await data.library.bookById(first.id);
      expect(again!.categoryId, 'fiction');
      expect((await data.library.books()).length, 1);
    });
  });

  group('BUG-20: место новой книги на полке', () {
    /// Импортёр, у которого каждый файл — своя книга.
    BookImporter placing() {
      int seen = 0;
      return BookImporter(
        library: data.library,
        storage: const LocalBookStorage(),
        opener: FakeDocumentOpener(FakeReaderDocument(pages: <String>['раз'])),
        fingerprint: (BookHandle book) async => 'hash-new-${seen++}',
        newId: () => 'new-$seen',
        now: () => DateTime.utc(2026, 10, 4, 12),
      );
    }

    PickedFile named(String name) {
      return PickedFile(path: 'test/fixtures/basic_text.pdf', name: name);
    }

    /// Книги категории в порядке «Как расставил».
    Future<List<String>> manualOrder(String? categoryId) async {
      final List<Book> books = <Book>[
        for (final Book book in await data.library.books())
          if (book.categoryId == categoryId) book,
      ];
      return <String>[
        for (final Book book in sortBooks(books, ShelfSort.manual)) book.title,
      ];
    }

    test('BUG-20: новая книга встаёт последней в своей категории', () async {
      await data.library.save(testBook(id: 'a', title: 'Аа', hash: 'hash-a'));
      await data.library.save(testBook(id: 'b', title: 'Яя', hash: 'hash-b'));
      await placeBook(data, 'a', 'study');
      await placeBook(data, 'b', 'study', position: 1);

      await placing().register(named('Мм.pdf'), categoryId: 'study');

      // Читатель расставил «Аа» и «Яя» руками; новая книга не вправе
      // встать между ними или перед ними.
      expect(await manualOrder('study'), <String>['Аа', 'Яя', 'Мм']);
    });

    test('BUG-20: пачка встаёт в том порядке, в каком выбрана', () async {
      await placing().registerAll(<PickedFile>[
        named('В.pdf'),
        named('А.pdf'),
        named('Б.pdf'),
      ]);

      expect(await manualOrder(null), <String>['В', 'А', 'Б']);
    });

    test('BUG-20: место считается в своей категории', () async {
      await data.library.save(testBook(id: 'a', title: 'Аа', hash: 'hash-a'));
      await placeBook(data, 'a', 'study', position: 7);

      final Book book = await placing().register(
        named('Мм.pdf'),
        categoryId: 'fiction',
      );

      // В «fiction» книг нет — новая встаёт первой, а не восьмой.
      expect(book.shelfPosition, 0);
    });
  });

  group('SNO-F-LIT-01: книга, которая уже лежит на месте', () {
    test('SNO-F-LIT-01: заводится без приёма хранилищем', () async {
      final RecordingStorage storage = RecordingStorage();
      const FilePathSource source = FilePathSource(
        'test/fixtures/basic_text.pdf',
      );
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['раз', 'два']),
        storage: storage,
      ).registerSource(source, title: 'Анатомия', categoryId: 'study');

      expect(book.title, 'Анатомия');
      expect(book.source, source);
      expect(book.categoryId, 'study');
      expect(book.pageCount, 2);
      expect(await data.library.bookById(book.id), isNotNull);
    });

    test('SNO-F-LIT-01: категория спрашивается у открывшейся книги', () async {
      const FilePathSource source = FilePathSource(
        'test/fixtures/basic_text.pdf',
      );
      int asked = 0;
      Future<String?> category() async {
        asked++;
        return 'study';
      }

      // Книга не открылась — категорию не спрашивали: заводить её
      // было бы не под что.
      await expectLater(
        importer(
          FakeReaderDocument.blank(1),
          failure: const DocumentOpenException(DocumentProblem.damaged, source),
        ).registerSource(source, title: 'Битая', categoryFor: category),
        throwsA(isA<DocumentOpenException>()),
      );
      expect(asked, 0);

      await data.library.save(testBook(id: 'a', hash: 'hash-a'));
      await placeBook(data, 'a', 'study', position: 3);
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['раз']),
      ).registerSource(source, title: 'Анатомия', categoryFor: category);
      expect(asked, 1);
      expect(book.categoryId, 'study');
      // И встаёт в названной категории последней (BUG-20).
      expect(book.shelfPosition, 4);

      // Стоящую на полке книгу не переставляют — и не спрашивают куда.
      await importer(FakeReaderDocument(pages: <String>['раз']))
          .registerSource(source, title: 'Анатомия', categoryFor: category);
      expect(asked, 1);
    });

    test('SNO-F-LIT-01: не открылась — источник отпущен', () async {
      final RecordingStorage storage = RecordingStorage();
      const FilePathSource source = FilePathSource(
        'test/fixtures/truncated.pdf',
        owned: true,
      );
      await expectLater(
        importer(
          FakeReaderDocument.blank(1),
          failure: const DocumentOpenException(DocumentProblem.damaged, source),
          storage: storage,
        ).registerSource(source, title: 'Битая'),
        throwsA(isA<DocumentOpenException>()),
      );
      expect(storage.released, <BookSource>[source]);
      expect(await data.library.books(), isEmpty);
    });
  });

  group('перевыбор файла', () {
    test('книга остаётся той же, а источник меняется', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);

      // Отпечаток тот же: файл переехал, а не подменён.
      final Book relinked =
          await importer(
            FakeReaderDocument(pages: <String>['текст', 'ещё']),
            id: 'id-2',
          ).relink(
            book,
            const PickedFile(
              path: 'test/fixtures/two_columns.pdf',
              name: 'воскресшая.pdf',
            ),
          );

      // Идентификатор прежний: место чтения, цитаты и заметки
      // принадлежат книге, а не файлу.
      expect(relinked.id, book.id);
      expect(relinked.title, book.title);
      expect(
        (relinked.source as FilePathSource).path,
        'test/fixtures/two_columns.pdf',
      );
      expect(relinked.pageCount, 2);
      expect((await data.library.books()).length, 1);
    });

    test('прежний источник отпускается', () async {
      final RecordingStorage storage = RecordingStorage();
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);

      await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).relink(
        book,
        const PickedFile(
          path: 'test/fixtures/two_columns.pdf',
          name: 'другая.pdf',
        ),
      );

      expect(storage.released, <BookSource>[FilePathSource(_picked.path!)]);
    });
  });

  group('BUG-45: источник другой книги при перепривязке', () {
    const PickedFile other = PickedFile(
      path: 'test/fixtures/two_columns.pdf',
      name: 'чужая.pdf',
    );

    test('BUG-45: отказ не отнимает файл у другой книги', () async {
      final RecordingStorage storage = RecordingStorage();
      // На полке две книги, у каждой свой файл.
      final Book mine = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);
      final Book theirs = await importer(
        FakeReaderDocument(pages: <String>['чужой', 'текст']),
        hash: 'hash-чужой',
        id: 'id-2',
        storage: storage,
      ).register(other);
      expect(storage.released, isEmpty);

      // Свою книгу по ошибке привязывают к файлу чужой — и отказываются.
      await expectLater(
        importer(
          FakeReaderDocument(pages: <String>['чужой', 'текст']),
          hash: 'hash-чужой',
          storage: storage,
        ).relink(mine, other),
        throwsA(isA<RelinkRefused>()),
      );

      // Принятый файл — источник второй книги: отпустить его значило
      // бы удалить её копию или отозвать её ссылку.
      expect(storage.released, isEmpty);
      final Book? still = await data.library.bookById(theirs.id);
      expect(still?.source, theirs.source);
    });

    test('BUG-45: общий файл остаётся у книги, к которой привязан', () async {
      final RecordingStorage storage = RecordingStorage();
      final Book mine = await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);
      final Book theirs = await importer(
        FakeReaderDocument(pages: <String>['чужой', 'текст']),
        hash: 'hash-чужой',
        id: 'id-2',
        storage: storage,
      ).register(other);

      // Читатель согласился: теперь у двух книг один файл.
      final Book shared = await importer(
        FakeReaderDocument(pages: <String>['чужой', 'текст']),
        hash: 'hash-чужой',
        storage: storage,
      ).relink(mine, other, onMismatch: (RelinkMismatch _) async => true);
      expect(shared.source, theirs.source);
      // Отпущен прежний файл первой книги — он больше ничей.
      expect(storage.released, <BookSource>[mine.source]);

      // Первую привязывают обратно: общий файл нужен второй книге.
      await importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).relink(shared, _picked, onMismatch: (RelinkMismatch _) async => true);
      expect(storage.released, <BookSource>[mine.source]);
    });
  });

  group('BUG-19: перепривязка к другому файлу', () {
    const PickedFile other = PickedFile(
      path: 'test/fixtures/two_columns.pdf',
      name: 'чужая.pdf',
    );

    Future<Book> shelved({RecordingStorage? storage}) {
      return importer(
        FakeReaderDocument(pages: <String>['текст']),
        storage: storage,
      ).register(_picked);
    }

    BookImporter stranger({RecordingStorage? storage}) {
      return importer(
        FakeReaderDocument(pages: <String>['чужой', 'текст', 'совсем']),
        hash: 'hash-чужой',
        storage: storage,
      );
    }

    test('BUG-19: чужой файл без согласия книгу не меняет', () async {
      final RecordingStorage storage = RecordingStorage();
      final Book book = await shelved(storage: storage);

      // Прежде отпечаток считался и ни с чем не сравнивался: место
      // чтения, цитаты и заметки молча уезжали к чужому файлу.
      await expectLater(
        stranger(storage: storage).relink(book, other),
        throwsA(isA<RelinkRefused>()),
      );

      final Book? saved = await data.library.bookById(book.id);
      expect(saved!.fileHash, 'hash-fixture');
      expect((saved.source as FilePathSource).path, _picked.path);
      expect(saved.pageCount, 1);
      // Принятый было файл отпущен, а прежний источник книги — нет.
      expect(storage.released, <BookSource>[FilePathSource(other.path!)]);
    });

    test('BUG-19: читатель спрошен и отказался — книга прежняя', () async {
      final Book book = await shelved();
      final List<RelinkMismatch> asked = <RelinkMismatch>[];

      await expectLater(
        stranger().relink(
          book,
          other,
          onMismatch: (RelinkMismatch mismatch) async {
            asked.add(mismatch);
            return false;
          },
        ),
        throwsA(isA<RelinkRefused>()),
      );

      expect(asked.single.fileName, 'чужая.pdf');
      expect(asked.single.pagesBefore, 1);
      expect(asked.single.pagesNow, 3);
      final Book? saved = await data.library.bookById(book.id);
      expect(saved!.fileHash, 'hash-fixture');
    });

    test('BUG-19: с согласия книга привязывается, и она та же', () async {
      final RecordingStorage storage = RecordingStorage();
      final Book book = await shelved(storage: storage);

      // Другое издание или файл после распознавания: та же книга с
      // другим отпечатком. Запретить это нельзя — можно только спросить.
      final Book relinked = await stranger(storage: storage)
          .relink(book, other, onMismatch: (RelinkMismatch _) async => true);

      expect(relinked.id, book.id);
      expect(relinked.title, book.title);
      expect(relinked.fileHash, 'hash-чужой');
      expect(relinked.pageCount, 3);
      expect((relinked.source as FilePathSource).path, other.path);
      expect(storage.released, <BookSource>[FilePathSource(_picked.path!)]);
      expect((await data.library.books()).length, 1);
    });

    test('BUG-19: тот же файл читателя не спрашивает', () async {
      final Book book = await shelved();
      bool asked = false;

      await importer(FakeReaderDocument(pages: <String>['текст'])).relink(
        book,
        other,
        onMismatch: (RelinkMismatch _) async {
          asked = true;
          return false;
        },
      );

      expect(asked, isFalse);
    });

    test('BUG-19: отказ не отнимает у книги прежний источник', () async {
      // Файл выбрали по прежнему пути, а внутри он другой. Отказ не
      // должен отпускать источник, который у книги был.
      final RecordingStorage storage = RecordingStorage();
      final Book book = await shelved(storage: storage);

      await expectLater(
        stranger(storage: storage).relink(book, _picked),
        throwsA(isA<RelinkRefused>()),
      );

      expect(storage.released, isEmpty);
    });

    test('BUG-19: книга без отпечатка привязывается, как прежде', () async {
      final Book loose = testBook(hash: '');
      await data.library.save(loose);

      final Book relinked = await stranger(storage: RecordingStorage())
          .relink(loose, other);

      expect(relinked.id, loose.id);
      expect(relinked.fileHash, 'hash-чужой');
    });

    test('BUG-19: вопрос называет обе книги числом страниц', () {
      final String text = describeRelinkMismatch(
        RelinkMismatch(
          book: testBook().copyWith(pageCount: 412),
          fileName: 'чужая.pdf',
          pagesNow: 398,
        ),
      );

      expect(text, contains('Пиковая дама'));
      expect(text, contains('страниц: 412'));
      expect(text, contains('чужая.pdf'));
      expect(text, contains('страниц: 398'));
      expect(text, contains('могут указывать не туда'));
    });
  });

  group('titleFromFileName', () {
    test('убирает расширение и разделители', () {
      expect(titleFromFileName('voyna_i_mir.pdf'), 'voyna i mir');
      expect(titleFromFileName('Пиковая дама.PDF'), 'Пиковая дама');
      expect(titleFromFileName('doc.name.v2.pdf'), 'doc name v2');
    });

    test('отрезает путь, если он приехал вместе с именем', () {
      expect(titleFromFileName('/books/sub/Онегин.pdf'), 'Онегин');
      expect(titleFromFileName(r'C:\books\Онегин.pdf'), 'Онегин');
    });

    test('пустое имя не оставляет пустую строку на полке', () {
      expect(titleFromFileName('.pdf'), 'Без названия');
      expect(titleFromFileName('   '), 'Без названия');
    });
  });

  group('bookFingerprint', () {
    test('одинаков для одного файла и различает разные', () async {
      final String basic = await fileFingerprint(
        'test/fixtures/basic_text.pdf',
      );
      final String again = await fileFingerprint(
        'test/fixtures/basic_text.pdf',
      );
      final String other = await fileFingerprint(
        'test/fixtures/two_columns.pdf',
      );
      expect(basic, again);
      expect(basic, isNot(other));
      // Формат отпечатка: длина файла и sha256 от его краёв.
      expect(basic, matches(RegExp(r'^\d+-[0-9a-f]{64}$')));
    });

    test('пустой файл тоже имеет отпечаток', () async {
      expect(
        await fileFingerprint('test/fixtures/empty_file.pdf'),
        startsWith('0-'),
      );
    });

    test('книга длиннее пробы: отпечаток берёт и начало, и конец', () async {
      final Directory dir = await Directory.systemTemp.createTemp('memoria-fp');
      addTearDown(() => dir.delete(recursive: true));
      final File head = File('${dir.path}/head.bin');
      final File tail = File('${dir.path}/tail.bin');
      // Файлы длиннее 128 КБ и различаются только последним байтом:
      // отпечаток, читающий одно начало, их не различил бы.
      final List<int> body = List<int>.filled(200 * 1024, 7);
      head.writeAsBytesSync(<int>[...body, 1]);
      tail.writeAsBytesSync(<int>[...body, 2]);

      expect(
        await fileFingerprint(head.path),
        isNot(await fileFingerprint(tail.path)),
      );
    });
  });
}

/// Хранилище, которое помнит, что у него отпускали.
class RecordingStorage implements BookStorage {
  final LocalBookStorage _files = const LocalBookStorage();

  /// Источники, переданные в [release].
  final List<BookSource> released = <BookSource>[];

  @override
  Future<BookSource> adopt(PickedFile file) => _files.adopt(file);

  @override
  Future<BookHandle> open(BookSource source) => _files.open(source);

  @override
  Future<bool> available(BookSource source) => _files.available(source);

  @override
  Future<void> release(BookSource source) async => released.add(source);
}
