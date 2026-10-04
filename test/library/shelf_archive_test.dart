import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/shelf_archive.dart';

/// SNO-ALG-LIT-01: раскладка архива с книгами — чистое правило над
/// списком имён.
void main() {
  List<String> shelfOf(ArchiveLayout layout) => <String>[
    for (final ArchiveBook book in layout.books)
      '${book.category ?? '—'} · ${book.title}',
  ];

  group('SNO-ALG-LIT-01: папка — категория, порядок — по именам', () {
    test('SNO-ALG-LIT-01: папка верхнего уровня — категория', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        '01 Анатомия/',
        '01 Анатомия/02 Атлас.pdf',
        '02 Физиология/Нормальная физиология.pdf',
        'Латинский язык.pdf',
        '01 Анатомия/01 Анатомия человека, т. 1.pdf',
      ]);

      expect(layout.categories, <String>['Анатомия', 'Физиология']);
      // Сначала «Без категории», затем папки по порядку имён; цифр
      // порядка в названиях нет.
      expect(shelfOf(layout), <String>[
        '— · Латинский язык',
        'Анатомия · Анатомия человека, т 1',
        'Анатомия · Атлас',
        'Физиология · Нормальная физиология',
      ]);
      expect(layout.skipped, 0);
    });

    test('SNO-ALG-LIT-01: запись книги — номер в исходном списке', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Б.pdf',
        'папка/',
        'А.pdf',
      ]);
      expect(layout.books.map((ArchiveBook book) => book.entry), <int>[2, 0]);
      expect(layout.books.first.path, 'А.pdf');
      expect(layout.books.first.fileName, 'А.pdf');
    });

    test('SNO-ALG-LIT-01: числа сравниваются как числа', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        '10 Гистология/Г.pdf',
        '2 Биохимия/Б.pdf',
        '1 Анатомия/Том 10.pdf',
        '1 Анатомия/Том 2.pdf',
      ]);
      expect(layout.categories, <String>['Анатомия', 'Биохимия', 'Гистология']);
      expect(shelfOf(layout).take(2), <String>[
        'Анатомия · Том 2',
        'Анатомия · Том 10',
      ]);
    });

    test('SNO-ALG-LIT-01: папки глубже первой категорий не заводят', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Анатомия/Атласы/Синельников.pdf',
        'Анатомия/Анатомия.pdf',
        'Физиология/Ф.pdf',
      ]);
      expect(layout.categories, <String>['Анатомия', 'Физиология']);
      expect(shelfOf(layout), <String>[
        'Анатомия · Анатомия',
        'Анатомия · Синельников',
        'Физиология · Ф',
      ]);
      expect(layout.books[1].fileName, 'Синельников.pdf');
    });

    test('SNO-ALG-LIT-01: папки с одним названием — одна категория', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        '02 анатомия/Б.pdf',
        '01 Анатомия/А.pdf',
      ]);
      expect(layout.categories, <String>['Анатомия']);
      expect(layout.books.map((ArchiveBook book) => book.title), <String>[
        'А',
        'Б',
      ]);
    });

    test('SNO-ALG-LIT-01: обратная черта — тоже разделитель', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        r'Папка\Книга.pdf',
      ]);
      expect(shelfOf(layout), <String>['Папка · Книга']);
    });
  });

  group('SNO-ALG-LIT-01: папка-обёртка', () {
    test('SNO-ALG-LIT-01: обёртка с подпапками снимается', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Литература/2 Биохимия/Биохимия.pdf',
        'Литература/10 Гистология/Гистология.pdf',
        'Литература/1 Анатомия/Атласы/Синельников.pdf',
        'Литература/1 Анатомия/Анатомия.pdf',
        'Литература/Словарь.pdf',
        'Литература/список.docx',
      ]);
      expect(layout.categories, <String>['Анатомия', 'Биохимия', 'Гистология']);
      expect(shelfOf(layout), <String>[
        '— · Словарь',
        'Анатомия · Анатомия',
        'Анатомия · Синельников',
        'Биохимия · Биохимия',
        'Гистология · Гистология',
      ]);
      expect(layout.skipped, 1);
      // Путь остаётся таким, каким записан в архиве.
      expect(layout.books.first.path, 'Литература/Словарь.pdf');
    });

    test('SNO-ALG-LIT-01: одна папка без подпапок — категория', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Анатомия/А.pdf',
        'Анатомия/Б.pdf',
      ]);
      expect(layout.categories, <String>['Анатомия']);
    });

    test('SNO-ALG-LIT-01: файл в корне — обёртки нет', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Литература/Анатомия/А.pdf',
        'Б.pdf',
      ]);
      expect(shelfOf(layout), <String>['— · Б', 'Литература · А']);
    });

    test('SNO-ALG-LIT-01: служебное обёртке не мешает', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Литература/Анатомия/А.pdf',
        'Литература/Физиология/Ф.pdf',
        '__MACOSX/Литература/Анатомия/._А.pdf',
        '.DS_Store',
      ]);
      expect(layout.categories, <String>['Анатомия', 'Физиология']);
      expect(layout.skipped, 0);
    });
  });

  group('SNO-ALG-LIT-01: что в архиве не книга', () {
    test('SNO-ALG-LIT-01: не-PDF сосчитаны, служебное — молча', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        'Книга.PDF',
        'Заметки.txt',
        'Анатомия/обложка.jpg',
        'Thumbs.db',
        'Анатомия/desktop.ini',
        '__MACOSX/._Книга.pdf',
        '.DS_Store',
        'Анатомия/.скрытое/Тайна.pdf',
      ]);
      expect(shelfOf(layout), <String>['— · Книга']);
      expect(layout.skipped, 2);
      expect(layout.categories, isEmpty);
    });

    test('SNO-ALG-LIT-01: пустой архив — пустая раскладка', () {
      final ArchiveLayout layout = layoutShelfArchive(const <String>[]);
      expect(layout.books, isEmpty);
      expect(layout.categories, isEmpty);
      expect(layout.skipped, 0);
    });
  });

  group('SNO-ALG-LIT-01: цифры порядка', () {
    test('SNO-ALG-LIT-01: цифры с разделителем — порядок, а не название', () {
      expect(stripOrderPrefix('01 Анатомия'), 'Анатомия');
      expect(stripOrderPrefix('1. Анатомия'), 'Анатомия');
      expect(stripOrderPrefix('2) Физиология'), 'Физиология');
      expect(stripOrderPrefix('03_Гистология'), 'Гистология');
      expect(stripOrderPrefix('04 - Биохимия'), 'Биохимия');
      expect(stripOrderPrefix('10 Анатомия т. 2'), 'Анатомия т. 2');
    });

    test('SNO-ALG-LIT-01: цифры в названии остаются', () {
      expect(stripOrderPrefix('1984'), '1984');
      expect(stripOrderPrefix('3D-атлас'), '3D-атлас');
      expect(stripOrderPrefix('2-е издание'), '2-е издание');
      expect(stripOrderPrefix('Анатомия 2'), 'Анатомия 2');
      // От имени из одних цифр порядка ничего бы не осталось.
      expect(stripOrderPrefix('01 '), '01');
    });

    test('SNO-ALG-LIT-01: у книги расширение снимается раньше цифр', () {
      final ArchiveLayout layout = layoutShelfArchive(<String>[
        '1984.pdf',
        '02 Атлас.pdf',
      ]);
      expect(layout.books.map((ArchiveBook book) => book.title), <String>[
        'Атлас',
        '1984',
      ]);
    });
  });

  group('SNO-ALG-LIT-01: порядок имён', () {
    test('SNO-ALG-LIT-01: как в «Проводнике»', () {
      final List<String> names = <String>[
        'Том 10',
        'том 2',
        'Том 1',
        'Атлас',
        'Том 02 часть 3',
      ]..sort(compareNatural);
      expect(names, <String>[
        'Атлас',
        'Том 1',
        'том 2',
        'Том 02 часть 3',
        'Том 10',
      ]);
    });

    test('SNO-ALG-LIT-01: порядок один и тот же при каждом добавлении', () {
      expect(compareNatural('Том 2', 'том 2'), isNot(0));
      expect(compareNatural('Том 2', 'Том 2'), 0);
      expect(compareNatural('a', 'b').sign, -compareNatural('b', 'a').sign);
    });
  });

  test('SNO-F-LIT-02: архив узнаётся по имени файла', () {
    expect(isArchiveName('Литература.zip'), isTrue);
    expect(isArchiveName('ЛИТЕРАТУРА.ZIP'), isTrue);
    expect(isArchiveName('Анатомия.pdf'), isFalse);
    expect(isArchiveName('zip'), isFalse);
  });
}
