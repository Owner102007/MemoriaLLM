import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/reading/reading.dart';

import 'test_data.dart';

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    await data.library.save(testBook());
  });

  tearDown(() async {
    await data.close();
  });

  test('позиции нет, пока книгу не открывали', () async {
    expect(await data.reading.position('book-1'), isNull);
  });

  test('позиция сохраняется вместе со смещением и прогрессом', () async {
    const ReadingPosition position = ReadingPosition(
      bookId: 'book-1',
      page: 42,
      fragment: 1,
      offset: 0.25,
      progress: 0.13,
    );
    await data.reading.savePosition(position);

    final ReadingPosition? loaded = await data.reading.position('book-1');
    expect(loaded, position);
    expect(loaded?.updatedAt, isNotNull);
  });

  test('повторное сохранение сдвигает позицию, а не плодит строки', () async {
    await data.reading.savePosition(
      const ReadingPosition(bookId: 'book-1', page: 10),
    );
    await data.reading.savePosition(
      const ReadingPosition(bookId: 'book-1', page: 11),
    );

    expect((await data.reading.position('book-1'))?.page, 11);
  });

  test('живая позиция обновляется сама', () async {
    final Stream<ReadingPosition?> positions = data.reading.watchPosition(
      'book-1',
    );
    expect(await positions.first, isNull);

    await data.reading.savePosition(
      const ReadingPosition(bookId: 'book-1', page: 5),
    );
    expect((await positions.first)?.page, 5);
  });

  test('настройки чтения по умолчанию валидны и без строки в базе', () async {
    final BookReadingSettings settings = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );

    expect(settings.displayMode, PageDisplayMode.full);
    expect(settings.filter, ReadingFilter.none);
    // Поля по умолчанию не режутся: страница показывается как свёрстана.
    expect(settings.autoCrop, isFalse);
    expect(settings.manualCrop, isNull);
    expect(settings.brightness, 1);
    // Полоса вписана вплотную: запас по краям читатель просит сам.
    expect(settings.stripFit, 1);
    // А нечитаемая часть страницы гаснет сразу: в этом весь смысл
    // режимов половины и трети — страница видна, читается полоса.
    expect(settings.dimOutside, kDefaultDimOutside);
  });

  test('сила затемнения запоминается для книги', () async {
    await data.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.third,
        dimOutside: 0.35,
      ),
    );

    final BookReadingSettings loaded = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.dimOutside, closeTo(0.35, 1e-9));
  });

  test('запас по краям полосы запоминается для книги', () async {
    await data.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.half,
        stripFit: 0.86,
      ),
    );

    final BookReadingSettings loaded = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.stripFit, closeTo(0.86, 1e-9));
  });

  test('F-READ-12: нахлёст и полоска соседа запоминаются для книги', () async {
    final BookReadingSettings fresh = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    // Книга, открытая впервые: нахлёст и полоска соседней страницы — по
    // умолчанию.
    expect(fresh.stripOverlap, kDefaultStripOverlap);
    expect(fresh.neighbourShare, kDefaultNeighbourShare);

    await data.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.half,
        stripOverlap: 0.11,
        neighbourShare: 0,
      ),
    );

    final BookReadingSettings loaded = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.stripOverlap, closeTo(0.11, 1e-9));
    // Ноль — тоже выбор читателя, а не «не задано».
    expect(loaded.neighbourShare, 0);
  });

  test('настройки сохраняются вместе с ручной рамкой', () async {
    const CropBox crop = CropBox(
      left: 0.08,
      top: 0.05,
      right: 0.92,
      bottom: 0.95,
    );
    const BookReadingSettings settings = BookReadingSettings(
      bookId: 'book-1',
      orientation: ScreenOrientation.landscape,
      displayMode: PageDisplayMode.half,
      manualCrop: crop,
      filter: ReadingFilter.nightRed,
      filterIntensity: 0.7,
      brightness: 0.4,
    );
    await data.reading.saveSettings(settings);

    final BookReadingSettings loaded = await data.reading.settings(
      'book-1',
      ScreenOrientation.landscape,
    );
    expect(loaded.displayMode, PageDisplayMode.half);
    expect(loaded.filter, ReadingFilter.nightRed);
    expect(loaded.filterIntensity, 0.7);
    expect(loaded.brightness, 0.4);
    expect(loaded.manualCrop, crop);
    expect(crop.isValid, isTrue);
  });

  test('ориентации не мешают друг другу', () async {
    await data.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.full,
      ),
    );
    await data.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.landscape,
        displayMode: PageDisplayMode.spread,
      ),
    );

    final BookReadingSettings portrait = await data.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    final BookReadingSettings landscape = await data.reading.settings(
      'book-1',
      ScreenOrientation.landscape,
    );
    expect(portrait.displayMode, PageDisplayMode.full);
    expect(landscape.displayMode, PageDisplayMode.spread);
  });

  test('F-READ-15: рамки книги нет, пока её не считали', () async {
    expect(await data.reading.bookFrame('book-1'), isNull);
  });

  test('F-READ-15: рамка книги сохраняется и читается', () async {
    const BookFrame frame = BookFrame(
      odd: CropBox(left: 0.14, top: 0.1, right: 0.93, bottom: 0.9),
      evenShift: -0.07,
      samples: 16,
      ignoreRunningHeads: false,
    );
    await data.reading.saveBookFrame('book-1', frame);

    final BookFrame? loaded = await data.reading.bookFrame('book-1');
    expect(loaded, frame);
    expect(loaded?.version, kBookFrameVersion);
    expect(loaded?.isMirrored, isTrue);
  });

  test('F-READ-15: новая рамка заменяет прежнюю, а не плодит строки', () async {
    await data.reading.saveBookFrame(
      'book-1',
      const BookFrame(odd: CropBox.full, version: kBookFrameVersion - 1),
    );
    const BookFrame fresh = BookFrame(
      odd: CropBox(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
      samples: 12,
    );
    await data.reading.saveBookFrame('book-1', fresh);

    expect(await data.reading.bookFrame('book-1'), fresh);
    final QueryRow count = await data.database
        .customSelect('SELECT COUNT(*) AS c FROM book_frames')
        .getSingle();
    expect(count.read<int>('c'), 1);
  });

  test('F-READ-15: рамка книги уходит вместе с книгой', () async {
    await data.reading.saveBookFrame(
      'book-1',
      const BookFrame(odd: CropBox.full),
    );
    await data.library.delete('book-1');
    expect(await data.library.purgeDeleted(), 1);
    expect(await data.reading.bookFrame('book-1'), isNull);
  });

  test('вывернутая рамка не считается валидной', () {
    const CropBox inverted = CropBox(
      left: 0.9,
      top: 0.9,
      right: 0.1,
      bottom: 0.1,
    );
    expect(inverted.isValid, isFalse);
    expect(CropBox.full.isValid, isTrue);
  });
}
