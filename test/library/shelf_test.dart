import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/shelf.dart';

Book _book({
  required String id,
  String? title,
  String? categoryId,
  DateTime? added,
  DateTime? opened,
  int? pages,
  int size = 1024,
}) {
  return Book(
    id: id,
    title: title ?? id,
    source: FilePathSource('/books/$id.pdf'),
    fileSize: size,
    fileHash: 'hash-$id',
    addedAt: added ?? DateTime.utc(2026, 8, 1),
    openedAt: opened,
    pageCount: pages,
    categoryId: categoryId,
  );
}

BookCategory _category(String id, {int position = 0, String? title}) {
  return BookCategory(
    id: id,
    title: title ?? id,
    position: position,
    createdAt: DateTime.utc(2026, 8, 20),
  );
}

void main() {
  group('раскладка полки по категориям', () {
    test('книги расходятся по своим категориям', () {
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[
          _category('study', position: 0, title: 'Учёба'),
          _category('fiction', position: 1, title: 'Проза'),
        ],
        books: <Book>[
          _book(id: 'a', categoryId: 'study'),
          _book(id: 'b', categoryId: 'fiction'),
          _book(id: 'c', categoryId: 'study'),
          _book(id: 'd'),
        ],
        sort: ShelfSort.title,
      );

      expect(shelf.map((ShelfSection s) => s.title), <String>[
        kUncategorizedTitle,
        'Учёба',
        'Проза',
      ]);
      expect(shelf[0].books.map((Book b) => b.id), <String>['d']);
      expect(shelf[1].books.map((Book b) => b.id), <String>['a', 'c']);
      expect(shelf[2].books.map((Book b) => b.id), <String>['b']);
    });

    test('«Без категории» стоит первым и не удаляется', () {
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[_category('study')],
        books: <Book>[_book(id: 'a')],
        sort: ShelfSort.title,
      );
      expect(shelf.first.isUncategorized, isTrue);
      expect(shelf.first.category, isNull);
      expect(shelf.first.id, kUncategorizedId);
    });

    test('пустой «Без категории» не показывается рядом с категориями', () {
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[_category('study')],
        books: <Book>[_book(id: 'a', categoryId: 'study')],
        sort: ShelfSort.title,
      );
      expect(shelf.length, 1);
      expect(shelf.single.id, 'study');
    });

    test('своя пустая категория с полки не исчезает', () {
      // Её завели руками — значит, ждут, что она никуда не денется, пока
      // в неё не положили книгу.
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[_category('study')],
        books: <Book>[],
        sort: ShelfSort.title,
      );
      expect(shelf.map((ShelfSection s) => s.id), <String>['study']);
      expect(shelf.single.books, isEmpty);
    });

    test('без категорий вовсе остаётся один раздел', () {
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[],
        books: <Book>[],
        sort: ShelfSort.title,
      );
      expect(shelf.length, 1);
      expect(shelf.single.isUncategorized, isTrue);
    });

    test('книга из удалённой категории не пропадает с полки', () {
      // Ссылка осталась, а категории уже нет: потерять книгу из-за
      // строчки в базе нельзя ни при каких обстоятельствах.
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[_category('study')],
        books: <Book>[_book(id: 'a', categoryId: 'исчезнувшая')],
        sort: ShelfSort.title,
      );
      expect(shelf.first.isUncategorized, isTrue);
      expect(shelf.first.books.single.id, 'a');
    });

    test('категории идут в заданном порядке', () {
      final List<ShelfSection> shelf = buildShelf(
        categories: <BookCategory>[
          _category('c', position: 2),
          _category('a', position: 0),
          _category('b', position: 1),
        ],
        books: <Book>[],
        sort: ShelfSort.title,
      );
      expect(shelf.map((ShelfSection s) => s.id), <String>['a', 'b', 'c']);
    });

    test('в категории на блок больше, чем книг: последний — кнопка «+»', () {
      final ShelfSection section = buildShelf(
        categories: <BookCategory>[_category('study')],
        books: <Book>[
          _book(id: 'a', categoryId: 'study'),
          _book(id: 'b', categoryId: 'study'),
        ],
        sort: ShelfSort.title,
      ).single;
      expect(section.books.length, 2);
      expect(section.blockCount, 3);
    });
  });

  group('порядок книг', () {
    final Book old = _book(
      id: 'old',
      title: 'Борис',
      added: DateTime.utc(2026, 1, 1),
      opened: DateTime.utc(2026, 2, 1),
    );
    final Book fresh = _book(
      id: 'fresh',
      title: 'Анна',
      added: DateTime.utc(2026, 8, 1),
      opened: DateTime.utc(2026, 8, 20),
    );
    final Book never = _book(
      id: 'never',
      title: 'Виктор',
      added: DateTime.utc(2026, 5, 1),
    );

    test('«сначала недавние»: неоткрытые уходят в конец', () {
      final List<Book> sorted = sortBooks(<Book>[
        never,
        old,
        fresh,
      ], ShelfSort.recent);
      expect(sorted.map((Book b) => b.id), <String>['fresh', 'old', 'never']);
    });

    test('по названию — без оглядки на регистр', () {
      final List<Book> sorted = sortBooks(<Book>[
        _book(id: '1', title: 'яблоко'),
        _book(id: '2', title: 'Арбуз'),
        _book(id: '3', title: 'банан'),
      ], ShelfSort.title);
      expect(sorted.map((Book b) => b.title), <String>[
        'Арбуз',
        'банан',
        'яблоко',
      ]);
    });

    test('по добавлению — сначала новые', () {
      final List<Book> sorted = sortBooks(<Book>[
        old,
        fresh,
        never,
      ], ShelfSort.added);
      expect(sorted.map((Book b) => b.id), <String>['fresh', 'never', 'old']);
    });

    test('«сначала начатые»: дочитанные и нетронутые уходят назад', () {
      final Book started = _book(id: 'started', title: 'Б');
      final Book done = _book(id: 'done', title: 'В');
      final Book untouched = _book(id: 'untouched', title: 'А');
      final List<Book> sorted = sortBooks(
        <Book>[done, untouched, started],
        ShelfSort.progress,
        progress: <String, double>{
          'started': 0.4,
          'done': 1.0,
          'untouched': 0,
        },
      );
      expect(sorted.first.id, 'started');
      // Дочитанная и нетронутая равноправны — обе «сейчас не читаю», и
      // между собой разводятся названием, а не случаем.
      expect(sorted.map((Book b) => b.id).skip(1), <String>[
        'untouched',
        'done',
      ]);
    });

    test('сортировка не трогает исходный список', () {
      final List<Book> source = <Book>[fresh, old];
      sortBooks(source, ShelfSort.title);
      expect(source.map((Book b) => b.id), <String>['fresh', 'old']);
    });

    test('равные книги не перетасовываются от вызова к вызову', () {
      final List<Book> books = <Book>[
        _book(id: 'z', title: 'Одинаково'),
        _book(id: 'a', title: 'Одинаково'),
      ];
      final List<Book> first = sortBooks(books, ShelfSort.recent);
      final List<Book> second = sortBooks(books.reversed.toList(),
          ShelfSort.recent);
      expect(
        first.map((Book b) => b.id),
        second.map((Book b) => b.id),
      );
    });

    test('неизвестное имя сортировки откатывается к порядку по умолчанию', () {
      expect(shelfSortFromName('recent'), ShelfSort.recent);
      expect(shelfSortFromName('title'), ShelfSort.title);
      expect(shelfSortFromName('невиданный'), ShelfSort.recent);
      expect(shelfSortFromName(null), ShelfSort.recent);
    });
  });

  group('сетка блоков', () {
    test('на телефоне ровно три блока в строке', () {
      // Постановка владельца: строка категории — три блока. Узкий экран
      // не вправе превратить полку в столбик.
      expect(shelfColumnsFor(360), kShelfMinColumns);
      expect(shelfColumnsFor(411), kShelfMinColumns);
      expect(shelfColumnsFor(240), kShelfMinColumns);
    });

    test('на широком окне ПК блоков больше, а размер тот же', () {
      final int wide = shelfColumnsFor(1600);
      expect(wide, greaterThan(kShelfMinColumns));
      // Блок держит размер: ширина, делённая на число колонок, остаётся
      // около опорной. Иначе обложки на ПК раздувались бы в афиши.
      expect(1600 / wide, lessThanOrEqualTo(kShelfTargetBlock * 1.35));
      expect(1600 / wide, greaterThanOrEqualTo(kShelfTargetBlock * 0.8));
    });

    test('очень широкий экран не дробит полку в крошку', () {
      expect(shelfColumnsFor(6000), kShelfMaxColumns);
    });

    test('неизмеренная ширина не роняет раскладку', () {
      // Бесконечная ширина — это не «очень широко», а «ещё не измерено»:
      // так выглядит блок в неограниченном по горизонтали окружении.
      // Отвечать на это десятком колонок нельзя, и `floor` на
      // бесконечности вдобавок бросает исключение.
      expect(shelfColumnsFor(0), kShelfMinColumns);
      expect(shelfColumnsFor(-100), kShelfMinColumns);
      expect(shelfColumnsFor(double.nan), kShelfMinColumns);
      expect(shelfColumnsFor(double.infinity), kShelfMinColumns);
    });

    test('строки считаются с запасом под неполную последнюю', () {
      expect(shelfRowsFor(0, 3), 0);
      expect(shelfRowsFor(1, 3), 1);
      expect(shelfRowsFor(3, 3), 1);
      expect(shelfRowsFor(4, 3), 2);
      expect(shelfRowsFor(9, 3), 3);
      expect(shelfRowsFor(10, 3), 4);
    });

    test('категория растёт ровно на строку каждые три книги', () {
      // Кнопка «+» занимает блок наравне с книгой, поэтому третья книга
      // уже требует второй строки.
      int rowsFor(int books) => shelfRowsFor(books + 1, kShelfMinColumns);
      expect(rowsFor(0), 1);
      expect(rowsFor(2), 1);
      expect(rowsFor(3), 2);
      expect(rowsFor(5), 2);
      expect(rowsFor(6), 3);
    });
  });

  group('толщина корешка', () {
    test('брошюра тоньше тома', () {
      final double thin = spineThickness(_book(id: 'a', pages: 24));
      final double thick = spineThickness(_book(id: 'b', pages: 900));
      expect(thin, lessThan(thick));
      expect(thin, inInclusiveRange(0.0, 1.0));
      expect(thick, inInclusiveRange(0.0, 1.0));
    });

    test('шкала логарифмическая: 2000 и 2200 страниц не различаются', () {
      expect(
        spineThickness(_book(id: 'a', pages: 2000)),
        spineThickness(_book(id: 'b', pages: 2200)),
      );
    });

    test('без числа страниц считается по размеру файла', () {
      final double small = spineThickness(
        _book(id: 'a', size: 400 * 1024),
      );
      final double big = spineThickness(
        _book(id: 'b', size: 60 * 1024 * 1024),
      );
      expect(small, lessThan(big));
    });

    test('пустая книга не даёт вырожденного корешка', () {
      final double none = spineThickness(_book(id: 'a', size: 0));
      expect(none, greaterThan(0));
      expect(none, lessThan(1));
    });
  });
}
