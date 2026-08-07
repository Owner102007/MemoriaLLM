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
    expect(settings.autoCrop, isTrue);
    expect(settings.manualCrop, isNull);
    expect(settings.brightness, 1);
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
