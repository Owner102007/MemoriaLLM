import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';

void main() {
  group('источник книги туда и обратно', () {
    test('путь', () {
      const BookSource source = FilePathSource('/books/onegin.pdf');
      expect(BookSource.decode(source.encode()), source);
    });

    test('наша копия отличается от чужого файла', () {
      const BookSource copy = FilePathSource('/data/books/x.pdf', owned: true);
      const BookSource alien = FilePathSource('/data/books/x.pdf');
      expect(copy.encode(), isNot(alien.encode()));
      expect(BookSource.decode(copy.encode()), copy);
      expect(BookSource.decode(alien.encode()), alien);
    });

    test('ссылка на документ', () {
      const BookSource source = DocumentUriSource(
        'content://com.android.providers.downloads.documents/document/42',
      );
      expect(BookSource.decode(source.encode()), source);
    });
  });

  group('строки из базы прошлых версий', () {
    // До S5.1 в колонке лежал голый путь. Книги живых читателей никуда
    // не делись, и прочитаться они обязаны без миграции.
    test('голый путь Android читается как файл', () {
      expect(
        BookSource.decode('/data/user/0/io.github.x.memoria/cache/kniga.pdf'),
        const FilePathSource(
          '/data/user/0/io.github.x.memoria/cache/kniga.pdf',
        ),
      );
    });

    test('буква диска Windows не путается с видом источника', () {
      // `C:` выглядит как вид ровно до того, как посмотреть на список
      // видов: `C` в него не входит.
      expect(
        BookSource.decode(r'C:\books\Онегин.pdf'),
        const FilePathSource(r'C:\books\Онегин.pdf'),
      );
      expect(
        BookSource.decode(r'D:\Книги\война и мир.pdf'),
        const FilePathSource(r'D:\Книги\война и мир.pdf'),
      );
    });

    test('относительный путь тоже читается', () {
      expect(
        BookSource.decode('test/fixtures/basic_text.pdf'),
        const FilePathSource('test/fixtures/basic_text.pdf'),
      );
    });
  });

  test('двоеточия внутри ссылки не ломают разбор', () {
    const BookSource source = DocumentUriSource(
      'content://media/external/file/1?a=b:c:d',
    );
    expect(BookSource.decode(source.encode()), source);
  });
}
