import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/reading/reader_document.dart';
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
        PickedFile(
          path: 'test/fixtures/basic_text.pdf',
          name: 'книга_$i.pdf',
        ),
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
      await batchImporter(
        FakeReaderDocument(pages: <String>['раз']),
      ).registerAll(
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
      await data.library.moveToCategory(first.id, 'fiction');

      await same.register(_picked, categoryId: 'study');
      final Book? again = await data.library.bookById(first.id);
      expect(again!.categoryId, 'fiction');
      expect((await data.library.books()).length, 1);
    });
  });

  group('перевыбор файла', () {
    test('книга остаётся той же, а источник меняется', () async {
      final Book book = await importer(
        FakeReaderDocument(pages: <String>['текст']),
      ).register(_picked);

      final Book relinked =
          await importer(
            FakeReaderDocument(pages: <String>['текст', 'ещё']),
            hash: 'hash-другой',
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
