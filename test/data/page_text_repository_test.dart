import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/reading/page_text.dart';

import 'test_data.dart';

/// F-TEXT-04, ALG-TXT-09: текст страниц книги в базе устройства.
///
/// Настоящая база в памяти: здесь проверяется то, чего хранилище в
/// памяти из тестов кэша не покажет, — запрос, ключ строки и каскад.
void main() {
  late AppData data;

  const PageTextKey key = PageTextKey(bookId: 'book-1', fingerprint: 'hash-1');

  setUp(() async {
    data = await openTestData();
    await data.library.save(testBook());
  });

  tearDown(() async {
    await data.close();
  });

  Future<int> rowsOf(String bookId) async {
    final row = await data.database
        .customSelect(
          "SELECT COUNT(*) AS c FROM page_texts WHERE book_id = '$bookId'",
        )
        .getSingle();
    return row.read<int>('c');
  }

  test('F-TEXT-04: у книги, которую не читали, запомненного нет', () async {
    expect(await data.pageTexts.cachedPages(key), isEmpty);
    expect(await data.pageTexts.pageTexts(key, from: 1, to: 100), isEmpty);
  });

  test('F-TEXT-04: текст страниц пишется и читается тем же', () async {
    // Текст движка — как есть: с переносами строк, мягкими переносами и
    // знаками за пределами основной плоскости. Места найденного считаются
    // по нему, и база не вправе поменять в нём ни знака.
    const Map<int, String> texts = <int, String>{
      1: 'Пиковая\r\nдама',
      2: '',
      3: 'мягкий­перенос и неразрывный пробел',
      4: 'редкий знак 𝔘 и эмодзи 📖',
    };
    await data.pageTexts.savePageTexts(key, texts);

    expect(await data.pageTexts.pageTexts(key, from: 1, to: 4), texts);
    expect(await data.pageTexts.cachedPages(key), <int, int>{
      1: 13,
      2: 0,
      3: 35,
      // Длину считает SQLite — в знаках, а не в кодовых единицах: два
      // знака за пределами основной плоскости здесь два, а не четыре.
      4: 24,
    });
  });

  test('F-TEXT-04: отдаётся только запрошенный отрезок страниц', () async {
    await data.pageTexts.savePageTexts(key, <int, String>{
      for (int page = 1; page <= 20; page++) page: 'страница $page',
    });

    final Map<int, String> part = await data.pageTexts.pageTexts(
      key,
      from: 7,
      to: 9,
    );

    expect(part.keys.toSet(), <int>{7, 8, 9});
    expect(part[8], 'страница 8');
  });

  test('F-TEXT-04: другая версия алгоритма — страницы как не бывало', () async {
    await data.pageTexts.savePageTexts(key, <int, String>{1: 'старый текст'});
    const PageTextKey next = PageTextKey(
      bookId: 'book-1',
      fingerprint: 'hash-1',
      version: kPageTextVersion + 1,
    );

    expect(await data.pageTexts.cachedPages(next), isEmpty);
    expect(await data.pageTexts.pageTexts(next, from: 1, to: 1), isEmpty);

    // Новая запись ложится поверх старой: строка у страницы одна.
    await data.pageTexts.savePageTexts(next, <int, String>{1: 'новый текст'});
    expect(await rowsOf('book-1'), 1);
    expect(await data.pageTexts.pageTexts(next, from: 1, to: 1), <int, String>{
      1: 'новый текст',
    });
    expect(await data.pageTexts.cachedPages(key), isEmpty);
  });

  test('F-TEXT-04: другой отпечаток файла — страницы как не бывало', () async {
    await data.pageTexts.savePageTexts(key, <int, String>{1: 'прежний файл'});
    const PageTextKey other = PageTextKey(
      bookId: 'book-1',
      fingerprint: 'hash-2',
    );

    expect(await data.pageTexts.cachedPages(other), isEmpty);
    expect(await data.pageTexts.pageTexts(other, from: 1, to: 1), isEmpty);
  });

  test('F-TEXT-04: у каждой книги свой текст', () async {
    await data.library.save(testBook(id: 'book-2', hash: 'hash-9'));
    const PageTextKey second = PageTextKey(
      bookId: 'book-2',
      fingerprint: 'hash-9',
    );
    await data.pageTexts.savePageTexts(key, <int, String>{1: 'первая'});
    await data.pageTexts.savePageTexts(second, <int, String>{1: 'вторая'});

    expect(await data.pageTexts.pageTexts(key, from: 1, to: 1), <int, String>{
      1: 'первая',
    });
    expect(
      await data.pageTexts.pageTexts(second, from: 1, to: 1),
      <int, String>{1: 'вторая'},
    );
  });

  test('F-TEXT-04: вычищенная книга уносит свой текст', () async {
    await data.pageTexts.savePageTexts(key, <int, String>{
      1: 'первая',
      2: 'вторая',
    });
    expect(await rowsOf('book-1'), 2);

    await data.library.delete('book-1');
    expect(await data.library.purgeDeleted(), 1);

    expect(await rowsOf('book-1'), 0);
  });

  test('F-TEXT-04: пустая запись базу не трогает', () async {
    await data.pageTexts.savePageTexts(key, const <int, String>{});
    expect(await rowsOf('book-1'), 0);
  });

  test('F-TEXT-04: текст книги, которой нет на полке, не пишется', () async {
    // Внешний ключ: текст без книги — мусор, который некому убрать.
    const PageTextKey stray = PageTextKey(
      bookId: 'нет-такой',
      fingerprint: 'hash-1',
    );
    await expectLater(
      data.pageTexts.savePageTexts(stray, <int, String>{1: 'текст'}),
      throwsA(anything),
    );
  });
}
