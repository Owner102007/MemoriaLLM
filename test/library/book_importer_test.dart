import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

const PickedFile _picked = PickedFile(
  path: 'test/fixtures/basic_text.pdf',
  name: 'voyna_i_mir.pdf',
);

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  BookImporter importer(
    FakeReaderDocument document, {
    DocumentOpenException? failure,
    String hash = 'hash-fixture',
    String id = 'id-1',
  }) {
    return BookImporter(
      library: data.library,
      opener: FakeDocumentOpener(document, failure: failure),
      fingerprint: (String path) async => hash,
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
            'test/fixtures/truncated.pdf',
          ),
        ).register(_picked),
        throwsA(isA<DocumentOpenException>()),
      );
      expect(await data.library.books(), isEmpty);
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

  group('fileFingerprint', () {
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
  });
}
