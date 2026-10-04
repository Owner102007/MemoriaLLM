import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/shelf_archive.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/domain/reading/page_text.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';
import 'package:memoria/sno/literature_archive.dart';
import 'package:memoria/sno/reference_state.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

/// SNO-F-CFG-04, SNO-ALG-CFG-02: эталонное состояние и сброс.
///
/// Полка — настоящая база в памяти; раздел «Тестирование» с кнопкой
/// сброса проверяется в `testing_screen_test.dart`.

/// Хранилище, у которого файлы пропадают по слову теста.
class _Files implements BookStorage {
  /// Источники, у которых файла больше нет.
  final Set<BookSource> gone = <BookSource>{};

  @override
  Future<BookSource> adopt(PickedFile file) async =>
      FilePathSource(file.path ?? file.name);

  @override
  Future<BookHandle> open(BookSource source) async =>
      MemoryBookHandle(const <int>[37, 80, 68, 70]);

  @override
  Future<bool> available(BookSource source) async => !gone.contains(source);

  @override
  Future<void> release(BookSource source) async {}
}

void main() {
  late AppData data;
  late _Files files;
  int seen = 0;

  final DateTime saved = DateTime.utc(2026, 10, 4, 15, 20);

  setUp(() async {
    seen = 0;
    data = await openTestData();
    files = _Files();
  });
  tearDown(() async => data.close());

  ReferenceKeeper keeper({DateTime? now, BookStorage? storage}) {
    return ReferenceKeeper(
      data: data,
      storage: storage ?? files,
      newId: () => 'new-${seen++}',
      now: () => now ?? saved,
    );
  }

  Future<void> category(String id, String title, int position) {
    return data.categories.save(
      BookCategory(
        id: id,
        title: title,
        position: position,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
    );
  }

  Future<Book> book(
    String id, {
    String? categoryId,
    int position = 0,
    String? title,
  }) async {
    final Book made = testBook(
      id: id,
      title: title ?? 'Книга $id',
      hash: 'hash-$id',
    ).copyWith(shelfPosition: position);
    final Book placed = categoryId == null
        ? made
        : made.copyWith(categoryId: categoryId);
    await data.library.save(placed);
    return placed;
  }

  /// Полка словами: «категория: отпечатки по порядку».
  Future<List<String>> shelf() async {
    final ShelfState state = (await keeper().snapshot()).shelf;
    String line(String? title) {
      final List<String> hashes = <String>[
        for (final ShelfBook book in state.books)
          if (book.category == title) book.fingerprint,
      ];
      return '${title ?? '—'}: ${hashes.join(', ')}';
    }

    return <String>[
      line(null),
      for (final String title in state.categories) line(title),
    ];
  }

  /// Полка из двух категорий и книги без категории.
  Future<void> archiveShelf() async {
    await category('lit', 'Литература', 0);
    await category('anat', 'Анатомия', 1);
    await book('l1', categoryId: 'lit');
    await book('a1', categoryId: 'anat');
    await book('a2', categoryId: 'anat', position: 1);
    await book('a3', categoryId: 'anat', position: 2);
  }

  const List<String> archiveOrder = <String>[
    '—: ',
    'Литература: hash-l1',
    'Анатомия: hash-a1, hash-a2, hash-a3',
  ];

  ArchivePlacement laid(String id, String? category, {String? title}) {
    return ArchivePlacement(
      fingerprint: 'hash-$id',
      title: title ?? 'Книга $id',
      category: category,
    );
  }

  /// То, что о той же полке говорит архив: какая книга в какой
  /// категории, в порядке архива.
  final List<ArchivePlacement> archive = <ArchivePlacement>[
    laid('l1', 'Литература'),
    laid('a1', 'Анатомия'),
    laid('a2', 'Анатомия'),
    laid('a3', 'Анатомия'),
  ];

  group('SNO-ALG-CFG-02: полка словами', () {
    Book placedBook(String id, String hash, String categoryId, int position) {
      return testBook(
        id: id,
        hash: hash,
      ).copyWith(categoryId: categoryId, shelfPosition: position);
    }

    test('SNO-ALG-CFG-02: категории по порядку, книги по местам', () {
      final ShelfState state = shelfStateOf(
        categories: <BookCategory>[
          BookCategory(
            id: 'b',
            title: 'Физиология',
            position: 1,
            createdAt: DateTime.utc(2026),
          ),
          BookCategory(
            id: 'a',
            title: 'Анатомия',
            position: 0,
            createdAt: DateTime.utc(2026),
          ),
        ],
        books: <Book>[
          placedBook('2', 'h2', 'a', 7),
          placedBook('1', 'h1', 'a', 3),
          testBook(id: '3', hash: 'h3').copyWith(categoryId: 'b'),
          testBook(id: '4', hash: 'h4'),
          // Категории больше нет — книга стоит в «Без категории».
          testBook(id: '5', hash: 'h5').copyWith(categoryId: 'gone'),
        ],
      );

      expect(state.categories, <String>['Анатомия', 'Физиология']);
      expect(
        <String>[
          for (final ShelfBook book in state.books)
            '${book.category ?? '—'} ${book.position} ${book.fingerprint}',
        ],
        <String>[
          '— 0 h4',
          '— 1 h5',
          'Анатомия 0 h1',
          'Анатомия 1 h2',
          'Физиология 0 h3',
        ],
      );
    });

    ShelfBook at(String hash, String? category, int position) {
      return ShelfBook(
        fingerprint: hash,
        title: hash,
        category: category,
        position: position,
      );
    }

    test('SNO-ALG-CFG-02: тот же порядок другими числами — та же полка', () {
      final ShelfState dense = ShelfState(
        categories: const <String>['А'],
        books: <ShelfBook>[at('x', 'А', 0), at('y', 'А', 1), at('z', null, 0)],
      );
      final ShelfState gaps = ShelfState(
        categories: const <String>['А'],
        books: <ShelfBook>[at('z', null, 4), at('y', 'А', 9), at('x', 'А', 2)],
      );
      expect(dense.sameAs(gaps), isTrue);
      expect(gaps.sameAs(dense), isTrue);
    });

    test('SNO-ALG-CFG-02: другое место, категория или порядок — другая', () {
      final ShelfState base = ShelfState(
        categories: const <String>['А', 'Б'],
        books: <ShelfBook>[at('x', 'А', 0), at('y', 'А', 1)],
      );
      expect(
        base.sameAs(
          ShelfState(
            categories: const <String>['А', 'Б'],
            books: <ShelfBook>[at('y', 'А', 0), at('x', 'А', 1)],
          ),
        ),
        isFalse,
        reason: 'книги поменялись местами',
      );
      expect(
        base.sameAs(
          ShelfState(
            categories: const <String>['А', 'Б'],
            books: <ShelfBook>[at('x', 'А', 0), at('y', 'Б', 0)],
          ),
        ),
        isFalse,
        reason: 'книга в другой категории',
      );
      expect(
        base.sameAs(
          ShelfState(
            categories: const <String>['Б', 'А'],
            books: <ShelfBook>[at('x', 'А', 0), at('y', 'А', 1)],
          ),
        ),
        isFalse,
        reason: 'категории в другом порядке',
      );
      expect(
        base.sameAs(
          ShelfState(
            categories: const <String>['А', 'Б'],
            books: <ShelfBook>[at('x', 'А', 0)],
          ),
        ),
        isFalse,
        reason: 'книги нет',
      );
      expect(
        base.sameAs(
          ShelfState(
            categories: const <String>['А', 'Б', 'В'],
            books: <ShelfBook>[at('x', 'А', 0), at('y', 'А', 1)],
          ),
        ),
        isFalse,
        reason: 'лишняя пустая категория',
      );
    });

    test('SNO-ALG-CFG-02: название книги в сравнение не входит', () {
      const ShelfBook one = ShelfBook(
        fingerprint: 'x',
        title: 'Атлас',
        category: null,
        position: 0,
      );
      const ShelfBook other = ShelfBook(
        fingerprint: 'x',
        title: 'Атлас, 2-е изд.',
        category: null,
        position: 0,
      );
      expect(one, other);
      expect(one.hashCode, other.hashCode);
    });
  });

  group('SNO-ALG-CFG-02: запись эталона', () {
    test('SNO-ALG-CFG-02: эталон читается таким, каким записан', () {
      final ReferenceState reference = ReferenceState(
        shelf: const ShelfState(
          categories: <String>['Литература', 'Анатомия'],
          books: <ShelfBook>[
            ShelfBook(
              fingerprint: 'h1',
              title: 'Словарь',
              category: null,
              position: 0,
            ),
            ShelfBook(
              fingerprint: 'h2',
              title: 'Атлас',
              category: 'Анатомия',
              position: 0,
            ),
          ],
        ),
        savedAt: saved,
      );

      final String text = reference.encode();
      final ReferenceState? read = ReferenceState.decode(text);

      expect(text, contains(kReferenceSchema));
      expect(read!.shelf.sameAs(reference.shelf), isTrue);
      expect(read.shelf.books.last.title, 'Атлас');
      expect(read.savedAt.isAtSameMomentAs(saved), isTrue);
    });

    test('SNO-ALG-CFG-02: испорченная запись — эталона нет', () {
      expect(ReferenceState.decode(null), isNull);
      expect(ReferenceState.decode(''), isNull);
      expect(ReferenceState.decode('не JSON'), isNull);
      expect(ReferenceState.decode('[]'), isNull);
      expect(
        ReferenceState.decode('{"schema":"другая/9","categories":[]}'),
        isNull,
      );
      expect(
        ReferenceState.decode(
          '{"schema":"$kReferenceSchema","saved_at":"2026-10-04T15:20:00Z",'
          '"categories":[],"books":[{"fingerprint":7}]}',
        ),
        isNull,
      );
    });
  });

  group('SNO-ALG-CFG-02: эталон складывается из раскладки архива', () {
    test('SNO-ALG-CFG-02: первый архив — эталон целиком', () {
      final ReferenceState? reference = extendReference(null, archive, saved);

      expect(reference!.shelf.categories, <String>['Литература', 'Анатомия']);
      expect(
        <String>[
          for (final ShelfBook item in reference.shelf.books)
            '${item.category} ${item.position} ${item.fingerprint}',
        ],
        <String>[
          'Литература 0 hash-l1',
          'Анатомия 0 hash-a1',
          'Анатомия 1 hash-a2',
          'Анатомия 2 hash-a3',
        ],
      );
      expect(reference.savedAt.isAtSameMomentAs(saved), isTrue);
    });

    test('SNO-ALG-CFG-02: пустой архив эталоном не становится', () {
      expect(extendReference(null, const <ArchivePlacement>[], saved), isNull);
    });

    test('SNO-ALG-CFG-02: второй архив дополняет, а не заменяет', () {
      final ReferenceState? first = extendReference(null, archive, saved);
      final DateTime later = DateTime.utc(2026, 10, 5);

      final ReferenceState? second = extendReference(first, <ArchivePlacement>[
        // Книга первого архива во втором лежит в другой папке — её
        // место в эталоне прежнее.
        laid('a1', 'Физиология'),
        laid('p1', 'Физиология'),
        laid('a4', 'Анатомия'),
        laid('w1', null),
      ], later);

      expect(second!.shelf.categories, <String>[
        'Литература',
        'Анатомия',
        'Физиология',
      ]);
      expect(
        <String>[
          for (final ShelfBook item in second.shelf.books)
            '${item.category ?? '—'} ${item.position} ${item.fingerprint}',
        ],
        <String>[
          '— 0 hash-w1',
          'Литература 0 hash-l1',
          'Анатомия 0 hash-a1',
          'Анатомия 1 hash-a2',
          'Анатомия 2 hash-a3',
          'Анатомия 3 hash-a4',
          'Физиология 0 hash-p1',
        ],
      );
      expect(second.savedAt.isAtSameMomentAs(later), isTrue);
    });

    test('SNO-ALG-CFG-02: тот же архив ещё раз эталон не меняет', () {
      final ReferenceState? first = extendReference(null, archive, saved);

      final ReferenceState? again = extendReference(
        first,
        archive,
        DateTime.utc(2026, 10, 9),
      );

      expect(identical(again, first), isTrue);
    });

    test('SNO-ALG-CFG-02: название категории — в написании эталона', () {
      final ReferenceState? first = extendReference(null, archive, saved);

      final ReferenceState? second = extendReference(first, <ArchivePlacement>[
        laid('a4', 'АНАТОМИЯ'),
      ], saved);

      expect(second!.shelf.categories, <String>['Литература', 'Анатомия']);
      expect(second.shelf.books.last.category, 'Анатомия');
      expect(second.shelf.books.last.position, 3);
    });

    test('SNO-ALG-CFG-02: одна книга дважды в архиве — одно место', () {
      final ReferenceState? reference = extendReference(
        null,
        <ArchivePlacement>[laid('x', 'А'), laid('x', 'Б'), laid('y', 'Б')],
        saved,
      );

      expect(reference!.shelf.categories, <String>['А', 'Б']);
      expect(reference.shelf.books, hasLength(2));
    });
  });

  group('SNO-F-CFG-04: эталон запоминается, когда архив разложен', () {
    test('SNO-F-CFG-04: без книг архива запоминать нечего', () async {
      expect(await keeper().remember(const <ArchivePlacement>[]), isNull);
      expect(await keeper().reference(), isNull);
    });

    test('SNO-F-CFG-04: эталон лежит в базе и совпадает с полкой', () async {
      await archiveShelf();

      final ReferenceState? reference = await keeper().remember(archive);

      expect(reference!.shelf.books, hasLength(4));
      // Эталон переживает перезапуск: он лежит в базе.
      final ReferenceState? stored = await keeper().reference();
      expect(stored!.shelf.sameAs(reference.shelf), isTrue);
      expect(stored.savedAt.isAtSameMomentAs(saved), isTrue);
      expect((await keeper().snapshot()).matches(stored), isTrue);
    });

    test('SNO-F-CFG-04: перестановка после архива в эталон не идёт', () async {
      await archiveShelf();
      await keeper().remember(archive);
      await placeBook(data, 'a3', 'lit', position: 4);

      // Тот же архив ещё раз: все книги уже стоят на полке.
      final ReferenceState? again = await keeper(now: DateTime.utc(2026, 10, 9))
          .remember(archive);

      expect(again!.savedAt.isAtSameMomentAs(saved), isTrue);
      expect((await keeper().snapshot()).matches(again), isFalse);
    });

    test('SNO-F-CFG-04: полка прежней сборки эталоном не становится', () async {
      // Архив разложили до того, как появился эталон: книга из корня
      // стоит в «Без категории», а книги переставлены.
      await category('anat', 'Анатомия', 0);
      await book('l1');
      await book('a3', categoryId: 'anat');
      await book('a1', categoryId: 'anat', position: 1);
      await book('a2', categoryId: 'anat', position: 2);

      // Тот же архив новой сборкой: книги на полке уже стоят, а эталон
      // — раскладка архива, одна и та же на любом устройстве.
      final ReferenceState? reference = await keeper().remember(archive);
      expect((await keeper().snapshot()).matches(reference!), isFalse);

      final ResetReport report = await keeper().reset();

      expect(report.matches, isTrue);
      expect(await shelf(), archiveOrder);
    });
  });

  group('SNO-F-CFG-04: сброс к эталонному состоянию', () {
    test('SNO-ALG-CFG-02: эталон → следы читателя → сброс → эталон', () async {
      await archiveShelf();
      final ReferenceKeeper first = keeper();
      final ReferenceState? reference = await first.remember(archive);
      final String? node = await data.settings.read(SettingsKeys.nodeId);
      expect(await shelf(), archiveOrder);

      // Тестировщик читал, выделял и переставлял.
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a1', page: 12, progress: 0.4),
      );
      await data.annotations.saveQuote(
        Quote(
          id: 'q1',
          bookId: 'a1',
          page: 12,
          content: 'цитата',
          createdAt: DateTime.utc(2026, 10, 4, 16),
        ),
      );
      await data.annotations.saveNote(
        Note(
          id: 'n1',
          bookId: 'a1',
          page: 12,
          body: 'заметка',
          createdAt: DateTime.utc(2026, 10, 4, 16),
          updatedAt: DateTime.utc(2026, 10, 4, 16),
          quoteId: 'q1',
        ),
      );
      await data.annotations.saveBookmark(
        Bookmark(
          id: 'm1',
          bookId: 'a2',
          page: 3,
          createdAt: DateTime.utc(2026, 10, 4, 16),
        ),
      );
      await data.library.markOpened('a2', DateTime.utc(2026, 10, 4, 17));
      await data.settings.write(SettingsKeys.theme, 'sepia');
      await data.settings.write(SettingsKeys.shelfSort, 'title');
      await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
      await placeBook(data, 'a3', 'lit', position: 0);
      await placeBook(data, 'a1', 'anat', position: 8);
      await category('own', 'Своя', 2);
      await data.categories.save(
        (await data.categories.categoryById('anat'))!.copyWith(title: 'Анат'),
      );
      await data.prompts.deletePrompt(kTranslatePromptId);
      // Выведенное из самих книг — не след читателя.
      const PageTextKey texts = PageTextKey(
        bookId: 'a1',
        fingerprint: 'hash-a1',
      );
      await data.pageTexts.savePageTexts(texts, <int, String>{1: 'текст'});
      await data.reading.saveBookFrame(
        'a1',
        const BookFrame(odd: CropBox.full, fingerprint: 'hash-a1'),
      );
      await data.library.setCoverPath('a1', '/covers/a1.png');
      expect((await first.snapshot()).matches(reference!), isFalse);

      final ResetReport report = await keeper(
        now: DateTime.utc(2026, 10, 4, 18),
      ).reset();

      expect(report.matches, isTrue);
      expect(report.missing, isEmpty);
      expect(await shelf(), archiveOrder);
      final StateSnapshot after = await keeper().snapshot();
      expect(after.matches(reference), isTrue);
      expect(after.traces, 0);
      expect(after.settings, isEmpty);
      // Следов нет.
      expect(await data.reading.position('a1'), isNull);
      expect(await data.annotations.quotes('a1'), isEmpty);
      expect(await data.annotations.notes('a1'), isEmpty);
      expect(await data.annotations.bookmarks('a2'), isEmpty);
      expect(await data.settings.read(SettingsKeys.theme), isNull);
      expect(await data.settings.read(SettingsKeys.shelfSort), isNull);
      expect(await data.settings.read(SettingsKeys.tapZoneHintSeen), isNull);
      final Book? opened = await data.library.bookById('a2');
      expect(opened!.openedAt!.isAtSameMomentAs(opened.addedAt), isTrue);
      // Категории — эталонные: своя ушла, переименованная вернулась.
      expect(
        (await data.categories.categories()).map(
          (BookCategory item) => item.title,
        ),
        <String>['Литература', 'Анатомия'],
      );
      // Функции к выделению — как из коробки.
      expect(
        (await data.prompts.masterPrompts()).map(
          (SelectionPrompt item) => item.id,
        ),
        <String>[kMeaningPromptId, kTranslatePromptId],
      );
      // Текст страниц, посчитанная рамка и обложка — на месте: заново
      // ничего не читается.
      expect(await data.pageTexts.cachedPages(texts), hasLength(1));
      expect(await data.reading.bookFrame('a1'), isNotNull);
      expect((await data.library.bookById('a1'))!.coverPath, '/covers/a1.png');
      // Устройство — то же, эталон и время сброса — на месте.
      expect(await data.settings.read(SettingsKeys.nodeId), node);
      expect(await keeper().reference(), isNotNull);
      expect(
        (await keeper().lastReset())!.isAtSameMomentAs(
          DateTime.utc(2026, 10, 4, 18),
        ),
        isTrue,
      );
    });

    test('SNO-F-CFG-04: второй сброс подряд ничего не меняет', () async {
      await archiveShelf();
      final ReferenceState? reference = await keeper().remember(archive);
      await keeper().reset();
      final List<Book> before = await data.library.books();

      final ResetReport again = await keeper().reset();

      expect(again.matches, isTrue);
      expect(await shelf(), archiveOrder);
      expect((await keeper().snapshot()).matches(reference!), isTrue);
      expect(await data.library.books(), hasLength(before.length));
    });

    test('SNO-F-CFG-04: снятая книга возвращается на своё место', () async {
      await archiveShelf();
      await keeper().remember(archive);
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a2', page: 5),
      );
      await data.library.delete('a2');
      expect(await data.library.bookById('a2'), isNull);

      final ResetReport report = await keeper().reset();

      expect(report.matches, isTrue);
      expect(report.missing, isEmpty);
      expect(await shelf(), archiveOrder);
      // Вернулась та же строка — и без следа читателя.
      expect(await data.library.bookById('a2'), isNotNull);
      expect(await data.reading.position('a2'), isNull);
    });

    test('SNO-F-CFG-04: снятая книга без файла названа', () async {
      await archiveShelf();
      final Book lost = await book(
        'a9',
        categoryId: 'anat',
        position: 3,
        title: 'Атлас',
      );
      await keeper().remember(<ArchivePlacement>[
        ...archive,
        laid('a9', 'Анатомия', title: 'Атлас'),
      ]);
      await data.library.delete('a9');
      files.gone.add(lost.source);

      final ResetReport report = await keeper().reset();

      expect(report.missing, <String>['Атлас']);
      expect(report.matches, isFalse);
      expect(await data.library.bookById('a9'), isNull);
      expect(await shelf(), archiveOrder);
      expect(
        describeReset(report),
        'Сброшено. Нет файла у книг: 1 — «Атлас». '
        'Добавьте архив с литературой ещё раз.',
      );
      // Надгробие осталось — книга вернётся той же строкой (BUG-30).
      expect((await data.library.removedBookByHash('hash-a9'))!.id, 'a9');
    });

    test('SNO-F-CFG-04: книга на полке без файла названа', () async {
      await archiveShelf();
      await keeper().remember(archive);
      files.gone.add(testBook(id: 'l1').source);

      final ResetReport report = await keeper().reset();

      expect(report.missing, <String>['Книга l1']);
      // Книга стоит на своём месте: полка совпадает, файла нет.
      expect(report.matches, isTrue);
      expect(await shelf(), archiveOrder);
    });

    test('SNO-F-CFG-04: книга сверх эталона — в «Без категории»', () async {
      await archiveShelf();
      await keeper().remember(archive);
      await book('x1', categoryId: 'anat', position: 0);

      final ResetReport report = await keeper().reset();

      expect(await shelf(), <String>[
        '—: hash-x1',
        'Литература: hash-l1',
        'Анатомия: hash-a1, hash-a2, hash-a3',
      ]);
      expect(report.matches, isFalse, reason: 'на полке лишняя книга');
    });

    test('SNO-F-CFG-04: надгробие книги не из эталона стирается', () async {
      await archiveShelf();
      await keeper().remember(archive);
      await book('x1');
      await data.library.delete('x1');
      expect(await data.library.removedBookByHash('hash-x1'), isNotNull);

      await keeper().reset();

      expect(await data.library.removedBookByHash('hash-x1'), isNull);
      expect(await shelf(), archiveOrder);
    });

    test('SNO-F-CFG-04: без эталона сбрасывать не к чему', () async {
      await archiveShelf();
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a1', page: 12),
      );

      await expectLater(keeper().reset(), throwsStateError);

      // Отказ ничего не стёр.
      expect((await data.reading.position('a1'))!.page, 12);
    });
  });

  group('SNO-F-CFG-04: слова раздела', () {
    test('SNO-F-CFG-04: итог сброса', () {
      final DateTime at = DateTime.utc(2026, 10, 4, 18);
      expect(
        describeReset(ResetReport(at: at, matches: true)),
        'Сброшено. Состояние совпадает с эталоном.',
      );
      expect(
        describeReset(ResetReport(at: at, matches: false)),
        contains('отличается от эталона'),
      );
      expect(
        describeReset(
          ResetReport(
            at: at,
            matches: false,
            missing: const <String>['А', 'Б', 'В', 'Г', 'Д'],
          ),
        ),
        'Сброшено. Нет файла у книг: 5 — «А», «Б», «В» и ещё 2. '
        'Добавьте архив с литературой ещё раз.',
      );
    });

    test('SNO-F-CFG-04: время и эталон словами', () {
      // Время местное: так его видит экспериментатор.
      final DateTime moment = DateTime(2026, 10, 4, 8, 5);
      expect(describeMoment(moment), '04.10 в 08:05');
      expect(
        describeReference(
          ReferenceState(
            shelf: const ShelfState(
              categories: <String>['А', 'Б'],
              books: <ShelfBook>[
                ShelfBook(
                  fingerprint: 'x',
                  title: 'x',
                  category: 'А',
                  position: 0,
                ),
              ],
            ),
            savedAt: moment,
          ),
        ),
        'Категорий: 2, книг: 1 · запомнено 04.10 в 08:05',
      );
    });
  });

  group('SNO-F-CFG-04: эталон из настоящего архива', () {
    late Directory temp;
    late Directory books;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('memoria-reference');
      books = Directory('${temp.path}/books');
    });
    tearDown(() async => temp.delete(recursive: true));

    const PickedFile archive = PickedFile(
      name: 'Литература.zip',
      path: 'test/fixtures/zip/shelf_stored.zip',
    );

    test('SNO-F-CFG-04: пропавшую книгу архив возвращает на место', () async {
      final LocalBookStorage storage = LocalBookStorage(
        copyInto: () async => books,
      );
      LiteratureArchive unpack() {
        return LiteratureArchive(
          library: data.library,
          categories: data.categories,
          storage: storage,
          opener: FakeDocumentOpener(
            FakeReaderDocument(pages: <String>['текст']),
          ),
          booksDirectory: () async => books,
          newId: () => 'id-${seen++}',
          now: () => DateTime.utc(2026, 10, 4, 12),
        );
      }

      final ArchiveReport first = await unpack().add(archive);
      final ReferenceKeeper keep = keeper(storage: storage);
      expect(first.placed, hasLength(4));
      final ReferenceState? reference = await keep.remember(first.placed);
      expect(reference!.shelf.categories, <String>[
        'Литература',
        'Анатомия',
        'Физиология',
      ]);
      final List<String> laid = await shelf();

      // Книгу сняли с полки, и её копия удалена; остальное переставили.
      final Book atlas = first.added.firstWhere(
        (Book item) => item.title == 'Атлас',
      );
      await data.library.delete(atlas.id);
      File((atlas.source as FilePathSource).path).deleteSync();
      final Book latin = first.added.firstWhere(
        (Book item) => item.title == 'Латинский язык',
      );
      await placeBook(data, latin.id, null);

      final ResetReport report = await keep.reset();
      expect(report.missing, <String>['Атлас']);

      // Тот же архив ещё раз: книга вернулась прежней строкой и стоит
      // там, где её положил архив в первый раз.
      final ArchiveReport again = await unpack().add(archive);
      await keep.remember(again.placed);

      expect(again.added.single.id, atlas.id);
      expect(again.placed, hasLength(4));
      expect(await shelf(), laid);
      expect((await keep.snapshot()).matches(reference), isTrue);
    });
  });
}
