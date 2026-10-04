import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/library/shelf_archive.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/files/file_fingerprint.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';
import 'package:memoria/infrastructure/files/zip_reader.dart';
import 'package:memoria/sno/literature_archive.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// SNO-F-LIT-01: архив с книгами встаёт полкой.
///
/// Архивы — те же образцы от других реализаций, что у читателя ZIP
/// (`tool/make_zip_fixtures.py`); книги распаковываются в настоящую
/// временную папку, полка — настоящая база в памяти.
const String _fixtures = 'test/fixtures/zip';

/// Содержимое файла архива — то же правило, что в генераторе образцов.
List<int> contentOf(String path) => utf8.encode('%PDF-1.4\n${'$path\n' * 40}');

/// Имя, под которым архив видит экспериментатор, — одно на все
/// образцы: по нему названа категория книг из корня (SNO-F-LIT-04).
const String _archiveName = 'Литература.zip';

PickedFile fixture(String name, {String shown = _archiveName}) {
  return PickedFile(name: shown, path: '$_fixtures/$name');
}

/// Открыватель, у которого книга с заданным содержимым не открывается.
class _RefusingOpener implements DocumentOpener {
  _RefusingOpener(this.refused, this.problem);

  /// Отпечатки книг, которые не откроются.
  final Set<String> refused;

  /// Чем отказывать.
  final DocumentProblem problem;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    final String path = (source as FilePathSource).path;
    if (refused.contains(await fileFingerprint(path))) {
      throw DocumentOpenException(problem, source);
    }
    return FakeReaderDocument(pages: <String>['текст']);
  }
}

/// Хранилище, у которого архив лежит по ссылке, как документ Android.
///
/// Книги — обычные файлы; архив по ссылке отдаётся из памяти. Если
/// [seekable] выключен, по ссылке нельзя перескакивать — так отвечает
/// облачный провайдер, — и архив приходится переносить к себе.
class _UriArchiveStorage implements BookStorage {
  _UriArchiveStorage(this.bytes, this.books, {this.seekable = true});

  final List<int> bytes;
  final Directory books;
  final bool seekable;
  final LocalBookStorage _files = const LocalBookStorage();

  /// Что переносили к себе и что отпускали.
  final List<String> adopted = <String>[];
  final List<BookSource> released = <BookSource>[];

  @override
  Future<BookSource> adopt(PickedFile file) async {
    adopted.add(file.name);
    final File copy = File('${books.path}/перенесённый-архив.bin');
    await copy.parent.create(recursive: true);
    await copy.writeAsBytes(bytes);
    return FilePathSource(copy.path, owned: true);
  }

  @override
  Future<BookHandle> open(BookSource source) async {
    if (source is DocumentUriSource) {
      return seekable ? MemoryBookHandle(bytes) : _Pipe(bytes.length);
    }
    return _files.open(source);
  }

  @override
  Future<bool> available(BookSource source) => _files.available(source);

  @override
  Future<void> release(BookSource source) async {
    released.add(source);
    await _files.release(source);
  }
}

/// Хранилище, где выбранное по ссылке всегда переносится в папку книг
/// и называется по содержимому — как в сборке ветви на телефоне, когда
/// по ссылке нельзя перескакивать.
class _SameFileStorage implements BookStorage {
  _SameFileStorage(this.bytes, this.books);

  final List<int> bytes;
  final Directory books;
  final LocalBookStorage _files = const LocalBookStorage();

  @override
  Future<BookSource> adopt(PickedFile file) async {
    await books.create(recursive: true);
    final File scratch = File('${books.path}/incoming-scratch.part');
    await scratch.writeAsBytes(bytes);
    final String hash = await fileFingerprint(scratch.path);
    final File copy = await scratch.rename('${books.path}/$hash.pdf');
    return FilePathSource(copy.path, owned: true);
  }

  @override
  Future<BookHandle> open(BookSource source) async {
    return source is DocumentUriSource
        ? _Pipe(bytes.length)
        : await _files.open(source);
  }

  @override
  Future<bool> available(BookSource source) => _files.available(source);

  @override
  Future<void> release(BookSource source) => _files.release(source);
}

/// Документ, по которому нельзя перескакивать: чтение отказывает.
class _Pipe implements BookHandle {
  _Pipe(this.length);

  @override
  final int length;

  @override
  String? get path => null;

  @override
  int read(Uint8List buffer, int position, int size) => -1;

  @override
  Future<void> close() async {}
}

void main() {
  late AppData data;
  late Directory temp;
  late Directory books;

  /// Счётчик идентификаторов — один на тест, а не на сценарий: второй
  /// архив в том же тесте не должен выдать книге занятый идентификатор.
  int seen = 0;

  setUp(() async {
    seen = 0;
    data = await openTestData();
    temp = await Directory.systemTemp.createTemp('memoria-archive');
    books = Directory('${temp.path}/books');
  });
  tearDown(() async {
    await data.close();
    await temp.delete(recursive: true);
  });

  LiteratureArchive archiveOn({BookStorage? storage, DocumentOpener? opener}) {
    return LiteratureArchive(
      library: data.library,
      categories: data.categories,
      storage: storage ?? LocalBookStorage(copyInto: () async => books),
      opener:
          opener ??
          FakeDocumentOpener(FakeReaderDocument(pages: <String>['текст'])),
      booksDirectory: () async => books,
      newId: () => 'id-${seen++}',
      now: () => DateTime.utc(2026, 10, 4, 12),
    );
  }

  /// Полка словами: категории по порядку, в каждой — книги в порядке
  /// «Как расставил».
  Future<List<String>> shelf() async {
    final List<Book> all = await data.library.books();
    final List<BookCategory> categories = await data.categories.categories();
    List<String> titles(String? categoryId) => <String>[
      for (final Book book in sortBooks(<Book>[
        for (final Book item in all)
          if (item.categoryId == categoryId) item,
      ], ShelfSort.manual))
        book.title,
    ];
    return <String>[
      '—: ${titles(null).join(', ')}',
      for (final BookCategory category in categories)
        '${category.title}: ${titles(category.id).join(', ')}',
    ];
  }

  /// Имена файлов в папке книг.
  List<String> copies() {
    if (!books.existsSync()) {
      return <String>[];
    }
    return <String>[
      for (final FileSystemEntity entry in books.listSync())
        entry.uri.pathSegments.last,
    ]..sort();
  }

  const List<String> fullShelf = <String>[
    '—: ',
    'Литература: Латинский язык',
    'Анатомия: Анатомия человека, т 1, Атлас',
    'Физиология: Нормальная физиология',
  ];

  group('SNO-F-LIT-01: архив встаёт полкой', () {
    test('SNO-F-LIT-01: папки — категории, книги — по порядку имён', () async {
      final List<String> steps = <String>[];
      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_stored.zip'),
        onProgress: (ArchiveProgress progress) {
          steps.add(
            '${progress.number}/${progress.total} '
            '${progress.category ?? '—'} · ${progress.title}',
          );
        },
      );

      expect(report.refusal, isNull);
      expect(report.stopped, isNull);
      expect(report.failed, isEmpty);
      expect(report.total, 4);
      expect(report.added, hasLength(4));
      expect(report.already, 0);
      expect(report.categories, 3);
      expect(await shelf(), fullShelf);
      expect(steps, <String>[
        '1/4 Литература · Латинский язык',
        '2/4 Анатомия · Анатомия человека, т 1',
        '3/4 Анатомия · Атлас',
        '4/4 Физиология · Нормальная физиология',
      ]);
      // SNO-F-CFG-04: архив называет место каждой вставшей книги — из
      // этого складывается эталон.
      expect(
        <String>[
          for (final ArchivePlacement item in report.placed)
            '${item.category} · ${item.title}',
        ],
        <String>[
          'Литература · Латинский язык',
          'Анатомия · Анатомия человека, т 1',
          'Анатомия · Атлас',
          'Физиология · Нормальная физиология',
        ],
      );
      expect(
        report.placed.map((ArchivePlacement item) => item.fingerprint),
        report.added.map((Book book) => book.fileHash),
      );
    });

    test('SNO-F-LIT-01: книги — копии с верными отпечатками', () async {
      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );

      for (final Book book in report.added) {
        final BookSource source = book.source;
        expect(source, isA<FilePathSource>());
        final FilePathSource copy = source as FilePathSource;
        expect(copy.owned, isTrue, reason: 'копию делали мы');
        expect(copy.encode(), startsWith('copy:'));
        // Копия названа по отпечатку содержимого, и отпечаток книги —
        // он же.
        expect(copy.path, '${books.path}/${book.fileHash}.pdf');
        expect(await fileFingerprint(copy.path), book.fileHash);
      }
      final Book atlas = report.added.firstWhere(
        (Book book) => book.title == 'Атлас',
      );
      expect(
        File((atlas.source as FilePathSource).path).readAsBytesSync(),
        contentOf('01 Анатомия/02 Атлас.pdf'),
      );
      // Недописанных файлов не осталось.
      expect(copies(), hasLength(4));
      expect(copies().every((String name) => name.endsWith('.pdf')), isTrue);
    });

    test('SNO-F-LIT-01: Deflate и 866-я страница — та же полка', () async {
      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_deflate_cp866.zip'),
      );

      expect(report.added, hasLength(4));
      // «Заметки.txt» и «обложка.JPG» сосчитаны; служебные файлы систем
      // пропущены молча.
      expect(report.skipped, 2);
      expect(await shelf(), fullShelf);
    });

    test('SNO-F-LIT-01: ZIP64 и архив, записанный потоком', () async {
      expect(
        (await archiveOn().add(fixture('zip64_infozip.zip'))).added,
        hasLength(4),
      );
      expect(await shelf(), fullShelf);
      // Те же книги из другого архива — уже на полке.
      final ArchiveReport again = await archiveOn().add(
        fixture('descriptor_python.zip'),
      );
      expect(again.added, isEmpty);
      expect(again.already, 2);
    });

    test('SNO-F-LIT-01: папка-обёртка снимается, числа — по порядку', () async {
      final ArchiveReport report = await archiveOn().add(
        fixture('wrapped_infozip.zip'),
      );

      expect(report.added, hasLength(5));
      expect(report.skipped, 1);
      expect(await shelf(), <String>[
        '—: ',
        'Литература: Словарь',
        'Анатомия: Анатомия, Синельников',
        'Биохимия: Биохимия',
        'Гистология: Гистология',
      ]);
    });

    test('SNO-F-LIT-01: та же книга в двух папках встаёт один раз', () async {
      final ArchiveReport report = await archiveOn().add(
        fixture('twins_python.zip'),
      );

      expect(report.total, 3);
      expect(report.added, hasLength(2));
      expect(report.repeats, 1);
      expect(report.already, 0, reason: 'на полке до архива не было ничего');
      expect(await shelf(), <String>[
        '—: ',
        'Блок 1: Анатомия',
        'Блок 2: Гистология',
      ]);
      expect(copies(), hasLength(2));
    });

    test('SNO-F-LIT-01: категория с таким названием не дублируется', () async {
      await data.categories.save(
        BookCategory(
          id: 'old',
          title: 'анатомия',
          position: 5,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      );

      await archiveOn().add(fixture('shelf_stored.zip'));

      final List<BookCategory> categories = await data.categories.categories();
      expect(
        categories.map((BookCategory category) => category.title),
        <String>['анатомия', 'Литература', 'Физиология'],
      );
      // Новые категории встают в конец полки.
      expect(categories.last.position, 7);
      final List<Book> all = await data.library.books();
      expect(all.where((Book book) => book.categoryId == 'old'), hasLength(2));
    });
  });

  group('SNO-F-LIT-01: повторное добавление', () {
    for (final String name in <String>[
      'shelf_stored.zip',
      'shelf_deflate_cp866.zip',
    ]) {
      test('SNO-F-LIT-01: $name второй раз ничего не дублирует', () async {
        final ArchiveReport first = await archiveOn().add(fixture(name));
        // Читатель переставил книгу и унёс её в другую категорию.
        final Book atlas = first.added.firstWhere(
          (Book book) => book.title == 'Атлас',
        );
        await placeBook(data, atlas.id, null, position: 9);
        // Книгу после добавления открывали, и чтение узнало, что это
        // скан.
        final DateTime read = DateTime.utc(2026, 10, 5, 9);
        await data.library.markOpened(atlas.id, read);
        await data.library.setTextLayer(atlas.id, false);
        final List<String> before = await shelf();
        final List<String> files = copies();

        final ArchiveReport again = await archiveOn().add(fixture(name));

        expect(again.added, isEmpty);
        expect(again.already, 4);
        expect(again.failed, isEmpty);
        // SNO-F-CFG-04: место названо и книгам, стоявшим раньше, — и
        // это место архива, а не то, куда книгу унёс читатель.
        expect(again.placed, hasLength(4));
        expect(
          again.placed
              .firstWhere((ArchivePlacement item) => item.title == 'Атлас')
              .category,
          'Анатомия',
        );
        expect(await data.library.books(), hasLength(4));
        expect(await data.categories.categories(), hasLength(3));
        // И не переставляет: полка — как её оставил читатель.
        expect(await shelf(), before);
        expect(before.first, '—: Атлас');
        expect(copies(), files);
        // Повторное добавление — не открытие книги: порядок «недавние»
        // и то, что о книге узнало чтение, остаются как были.
        final Book? kept = await data.library.bookById(atlas.id);
        expect(kept!.openedAt!.isAtSameMomentAs(read), isTrue);
        expect(kept.hasTextLayer, isFalse);
      });
    }

    test('SNO-F-LIT-01: оборванная распаковка доводится до конца', () async {
      // Приложение закрыли посреди архива: две книги на полке, от третьей
      // остался недописанный файл.
      await archiveOn().add(fixture('descriptor_python.zip'));
      File('${books.path}/incoming-0123456789abcdef.part')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);
      expect(await data.library.books(), hasLength(2));

      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_deflate_cp866.zip'),
      );

      expect(report.added, hasLength(2));
      expect(report.already, 2);
      // Категории стоят в том порядке, в каком получили первую книгу.
      expect(await shelf(), <String>[
        '—: ',
        'Анатомия: Анатомия человека, т 1, Атлас',
        'Литература: Латинский язык',
        'Физиология: Нормальная физиология',
      ]);
      expect(copies(), hasLength(4));
      expect(copies().any((String name) => name.endsWith('.part')), isFalse);
    });

    test('SNO-F-LIT-01: пропавшая копия книги возвращается', () async {
      final ArchiveReport first = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );
      final Book lost = first.added.first;
      File((lost.source as FilePathSource).path).deleteSync();

      final ArchiveReport again = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );

      expect(again.added, isEmpty);
      expect(again.already, 4);
      expect(File((lost.source as FilePathSource).path).existsSync(), isTrue);
      expect(await data.library.books(), hasLength(4));
    });
  });

  group('SNO-F-LIT-01: отказы названы', () {
    Future<void> expectRefused(String name, String words) async {
      final ArchiveReport report = await archiveOn().add(fixture(name));
      expect(report.refusal, contains(words), reason: name);
      expect(report.added, isEmpty);
      expect(await data.library.books(), isEmpty, reason: name);
      expect(await data.categories.categories(), isEmpty, reason: name);
      expect(copies(), isEmpty, reason: name);
    }

    test('SNO-F-LIT-01: архив с паролем', () async {
      await expectRefused('encrypted_infozip.zip', 'защищён паролем');
    });

    test('SNO-F-LIT-01: сжатие не ZIP-овское', () async {
      await expectRefused('bzip2_python.zip', 'пересоберите обычным ZIP');
    });

    test('SNO-F-LIT-01: оборванный архив', () async {
      await expectRefused('truncated.zip', 'оборван');
    });

    test('SNO-F-LIT-01: не архив', () async {
      await expectRefused('not_a_zip.zip', 'не ZIP-архив');
    });

    test('SNO-F-LIT-01: в архиве нет книг', () async {
      await expectRefused('empty.zip', 'нет ни одного PDF');
    });

    test('SNO-F-LIT-01: до архива не добраться', () async {
      await expectRefused('такого-нет.zip', 'не удалось прочесть');
    });

    test('SNO-F-LIT-01: неверная сумма — остальные на полке', () async {
      final ArchiveReport report = await archiveOn().add(
        fixture('bad_crc.zip'),
      );

      expect(report.refusal, isNull);
      expect(report.added, hasLength(3));
      expect(report.failed, hasLength(1));
      expect(report.failed.single.name, '02 Атлас.pdf');
      expect(report.failed.single.reason, contains('контрольная сумма'));
      // Книге, которая не встала, места в эталоне нет.
      expect(report.placed, hasLength(3));
      expect(await shelf(), <String>[
        '—: ',
        'Литература: Латинский язык',
        'Анатомия: Анатомия человека, т 1',
        'Физиология: Нормальная физиология',
      ]);
      // Испорченная книга не лежит в папке ни под каким именем.
      expect(copies(), hasLength(3));
    });

    test('SNO-F-LIT-01: PDF, который не открылся, назван с причиной', () async {
      // Содержимое — по правилу образцов; отпечаток короткого файла —
      // его длина и сумма целиком.
      final Directory scratch = Directory('${temp.path}/scratch')..createSync();
      final File probe = File('${scratch.path}/probe.pdf')
        ..writeAsBytesSync(contentOf('01 Анатомия/02 Атлас.pdf'));
      final ArchiveReport report = await archiveOn(
        opener: _RefusingOpener(<String>{
          await fileFingerprint(probe.path),
        }, DocumentProblem.passwordRequired),
      ).add(fixture('shelf_stored.zip'));

      expect(report.added, hasLength(3));
      expect(report.failed.single.name, '02 Атлас.pdf');
      expect(report.failed.single.problem, DocumentProblem.passwordRequired);
      // Копия книги, которая не открылась, не остаётся в приложении.
      expect(copies(), hasLength(3));
    });

    test('SNO-F-LIT-01: папка из одних отказов — не категория', () async {
      // Категория заводится под книгу, которая открылась.
      final Directory scratch = Directory('${temp.path}/scratch')..createSync();
      final File probe = File(
        '${scratch.path}/probe.pdf',
      )..writeAsBytesSync(contentOf('02 Физиология/Нормальная физиология.pdf'));
      await archiveOn(
        opener: _RefusingOpener(<String>{
          await fileFingerprint(probe.path),
        }, DocumentProblem.damaged),
      ).add(fixture('shelf_stored.zip'));

      final List<BookCategory> categories = await data.categories.categories();
      expect(
        categories.map((BookCategory category) => category.title),
        <String>['Литература', 'Анатомия'],
      );
    });

    test('SNO-F-LIT-01: писать некуда — сказано, полка цела', () async {
      // На месте папки книг лежит файл: создать её нельзя.
      File(books.path).writeAsBytesSync(<int>[0]);

      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );

      expect(report.refusal, isNull);
      expect(report.stopped, isNotNull);
      expect(report.added, isEmpty);
      expect(await data.library.books(), isEmpty);
    });
  });

  group('SNO-F-LIT-01: архив по ссылке, как на телефоне', () {
    const PickedFile picked = PickedFile(
      name: 'Литература.zip',
      uri: 'content://downloads/literature',
    );

    test('SNO-F-LIT-01: архив читается на месте, без копии', () async {
      final _UriArchiveStorage storage = _UriArchiveStorage(
        File('$_fixtures/shelf_deflate_cp866.zip').readAsBytesSync(),
        books,
      );

      final ArchiveReport report = await archiveOn(storage: storage)
          .add(picked);

      expect(report.added, hasLength(4));
      expect(await shelf(), fullShelf);
      expect(storage.adopted, isEmpty, reason: 'архив к себе не переносили');
      expect(copies(), hasLength(4));
    });

    test('SNO-F-LIT-01: по потоку без перескоков — через перенос', () async {
      final _UriArchiveStorage storage = _UriArchiveStorage(
        File('$_fixtures/shelf_deflate_cp866.zip').readAsBytesSync(),
        books,
        seekable: false,
      );

      final ArchiveReport report = await archiveOn(storage: storage)
          .add(picked);

      expect(report.added, hasLength(4));
      expect(storage.adopted, <String>['Литература.zip']);
      // Перенесённый архив лежал под своим именем, а не как книга, и
      // после распаковки убран: в папке только книги.
      expect(storage.released, <BookSource>[
        FilePathSource('${books.path}/archive-borrowed.tmp', owned: true),
      ]);
      expect(copies(), hasLength(4));
      expect(copies().every((String name) => name.endsWith('.pdf')), isTrue);
    });
  });

  group('SNO-F-LIT-04: категория с названием архива', () {
    test('SNO-F-LIT-04: хвост повторной загрузки в название не идёт', () async {
      await archiveOn().add(
        fixture('shelf_stored.zip', shown: '01 Курс анатомии (1).zip'),
      );

      expect(await shelf(), <String>[
        '—: ',
        'Курс анатомии: Латинский язык',
        'Анатомия: Анатомия человека, т 1, Атлас',
        'Физиология: Нормальная физиология',
      ]);
    });

    test('SNO-F-LIT-04: архив под другим именем книг не двигает', () async {
      await archiveOn().add(fixture('shelf_stored.zip'));

      final ArchiveReport again = await archiveOn().add(
        fixture('shelf_stored.zip', shown: 'Литература (1).zip'),
      );

      expect(again.added, isEmpty);
      expect(again.already, 4);
      expect(await shelf(), fullShelf);
    });

    test('SNO-F-LIT-04: архив без имени — категория «Литература»', () async {
      await archiveOn().add(fixture('shelf_stored.zip', shown: ''));

      expect((await shelf())[1], 'Литература: Латинский язык');
    });

    test('SNO-F-LIT-04: из архива без папок все книги — в одной', () async {
      await archiveOn().add(fixture('unicode_extra.zip', shown: 'Блок 1.zip'));

      final List<String> shelved = await shelf();
      expect(shelved.first, '—: ');
      expect(shelved, hasLength(2));
      expect(shelved.last, startsWith('Блок 1: '));
      expect(await data.library.books(), hasLength(2));
    });
  });

  group('SNO-F-LIT-01: архив, оставшийся с прошлого раза', () {
    test('SNO-F-LIT-01: перенесённый и не убранный архив выметается', () async {
      // Приложение закрыли посреди распаковки архива, перенесённого из
      // облака: файл размером с весь архив остался в папке книг.
      final File orphan = File('${books.path}/archive-borrowed.tmp')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.filled(1024, 7));

      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );

      expect(report.added, hasLength(4));
      expect(orphan.existsSync(), isFalse);
      expect(copies(), hasLength(4));
    });

    test('SNO-F-LIT-01: книга под видом архива файла не теряет', () async {
      // По потоку без перескоков «архивом» выбрали PDF, который уже
      // стоит на полке: перенос кладёт его в тот же файл, что у книги.
      final List<int> bytes = contentOf('Анатомия.pdf');
      final _SameFileStorage storage = _SameFileStorage(bytes, books);
      final Book shelved = await BookImporter(
        library: data.library,
        storage: storage,
        opener: FakeDocumentOpener(FakeReaderDocument(pages: <String>['т'])),
      ).register(const PickedFile(name: 'Анатомия.pdf', uri: 'content://a'));
      final String path = (shelved.source as FilePathSource).path;
      expect(File(path).existsSync(), isTrue);

      final ArchiveReport report = await archiveOn(storage: storage)
          .add(const PickedFile(name: 'Анатомия.zip', uri: 'content://a'));

      expect(report.refusal, contains('не ZIP-архив'));
      expect(File(path).existsSync(), isTrue, reason: 'файл книги цел');
      expect(await data.library.books(), hasLength(1));
    });
  });

  group('SNO-F-LIT-01: причины словами', () {
    test('SNO-F-LIT-01: у каждой причины архива свои слова', () {
      final Set<String> words = <String>{
        for (final ZipProblem problem in ZipProblem.values)
          describeZipProblem(problem),
      };
      expect(words, hasLength(ZipProblem.values.length));
      expect(words.every((String text) => text.isNotEmpty), isTrue);
    });

    test('SNO-F-LIT-01: нехватка места названа прямо', () {
      const FileSystemException full = FileSystemException(
        'запись не удалась',
        '/books/x.part',
        OSError('No space left on device', 28),
      );
      expect(describeWriteFailure(full), contains('кончилось место'));
      const FileSystemException other = FileSystemException(
        'запись не удалась',
        '/books/x.part',
        OSError('Permission denied', 13),
      );
      expect(describeWriteFailure(other), isNot(contains('место')));
    });
  });

  group('SNO-F-LIT-01: архив и книга файлом — одна и та же книга', () {
    test('SNO-F-LIT-01: добавленная файлом — из архива не вторая', () async {
      final File single = File('${temp.path}/Атлас.pdf')
        ..writeAsBytesSync(contentOf('01 Анатомия/02 Атлас.pdf'));
      int files = 0;
      final Book byFile = await BookImporter(
        library: data.library,
        storage: LocalBookStorage(copyInto: () async => books),
        opener: FakeDocumentOpener(FakeReaderDocument(pages: <String>['т'])),
        newId: () => 'file-${files++}',
      ).register(PickedFile(name: 'Атлас.pdf', path: single.path));

      final ArchiveReport report = await archiveOn().add(
        fixture('shelf_stored.zip'),
      );

      expect(report.added, hasLength(3));
      expect(report.already, 1);
      // Книга осталась там, куда её поставили: в «Без категории».
      expect((await data.library.bookById(byFile.id))!.categoryId, isNull);
      expect(await data.library.books(), hasLength(4));
      expect(copies(), hasLength(4));
    });
  });
}
