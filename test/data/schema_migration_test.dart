import 'dart:io';

// `isNull` и `isNotNull` есть и у drift (условия запроса), и у matcher
// (проверки теста). Здесь нужны вторые.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/infrastructure/database/app_database.dart';
import 'package:path/path.dart' as p;

import 'test_data.dart';

/// Миграции схемы на настоящем файле базы.
///
/// Проверять миграцию в памяти нельзя в принципе: база живёт ровно одно
/// подключение, а миграция — это про **второе** открытие того же файла.
/// Здесь база откатывается к прошлой версии теми же средствами, какими
/// её создавал drift, и открывается заново — так же, как откроется база
/// читателя, обновившего приложение.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('memoria-migration');
    file = File(p.join(dir.path, 'memoria.sqlite'));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<AppData> launch() async {
    return AppData.open(executor: NativeDatabase(file));
  }

  Future<List<String>> columnsOf(AppData data, String table) async {
    final List<QueryRow> rows = await data.database
        .customSelect('PRAGMA table_info($table)')
        .get();
    return <String>[for (final QueryRow row in rows) row.read<String>('name')];
  }

  Future<int> versionOf(AppData data) async {
    final QueryRow row = await data.database
        .customSelect('PRAGMA user_version')
        .getSingle();
    return row.read<int>('user_version');
  }

  /// Откатывает базу к версии 3: категорий тогда не было.
  Future<void> undoCategories(AppData data) async {
    await data.database.customStatement('DROP TABLE book_categories');
    await data.database.customStatement(
      'ALTER TABLE books DROP COLUMN category_id',
    );
  }

  test('новая база создаётся сразу текущей версией', () async {
    final AppData data = await launch();
    expect(await versionOf(data), appSchemaVersion);
    expect(
      await columnsOf(data, 'book_settings'),
      containsAll(<String>['strip_fit', 'dim_outside']),
    );
    expect(await columnsOf(data, 'books'), contains('category_id'));
    await data.close();
  });

  test('база версии 3 доезжает до 4 и получает категории', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await undoCategories(first);
    await first.database.customStatement('PRAGMA user_version = 3');
    expect(await columnsOf(first, 'books'), isNot(contains('category_id')));
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(await columnsOf(second, 'books'), contains('category_id'));

    // Книга читателя, обновившего приложение, обязана оказаться на полке
    // в разделе «Без категории» — и никуда не пропасть по дороге.
    final Book? book = await second.library.bookById('book-1');
    expect(book, isNotNull);
    expect(book!.categoryId, isNull);
    expect(book.title, 'Пиковая дама');

    // И категории после миграции сразу работают.
    await second.categories.save(
      BookCategory(
        id: 'study',
        title: 'Учёба',
        position: 0,
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    );
    await second.library.moveToCategory('book-1', 'study');
    expect((await second.library.bookById('book-1'))!.categoryId, 'study');
    await second.close();
  });

  test('база версии 1 доезжает до конца и не теряет настройки книги', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.half,
        filter: ReadingFilter.nightRed,
        filterIntensity: 0.5,
        brightness: 0.6,
      ),
    );

    // Откат к версии 1: ни запаса по краям, ни затемнения тогда не было.
    // База читателя может приехать с любой прошлой версии, а не только
    // с соседней, — поэтому проверяется самый дальний путь.
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN strip_fit',
    );
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN dim_outside',
    );
    await undoCategories(first);
    await first.database.customStatement('PRAGMA user_version = 1');
    expect(
      await columnsOf(first, 'book_settings'),
      isNot(contains('strip_fit')),
    );
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(
      await columnsOf(second, 'book_settings'),
      containsAll(<String>['strip_fit', 'dim_outside']),
    );
    expect(await columnsOf(second, 'books'), contains('category_id'));

    final BookReadingSettings loaded = await second.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    // Настройки читателя обязаны пережить обновление приложения целиком.
    expect(loaded.displayMode, PageDisplayMode.half);
    expect(loaded.filter, ReadingFilter.nightRed);
    expect(loaded.filterIntensity, 0.5);
    expect(loaded.brightness, 0.6);
    // А новые настройки приходят со значениями по умолчанию: книга,
    // которую читали до обновления, открывается точно так же, как
    // открывалась.
    expect(loaded.stripFit, 1);
    expect(loaded.dimOutside, kDefaultDimOutside);
    await second.close();
  });

  test('база версии 2 доезжает до 3 и получает затемнение', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        displayMode: PageDisplayMode.third,
        stripFit: 0.9,
      ),
    );
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN dim_outside',
    );
    await undoCategories(first);
    await first.database.customStatement('PRAGMA user_version = 2');
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    final BookReadingSettings loaded = await second.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.displayMode, PageDisplayMode.third);
    expect(loaded.stripFit, closeTo(0.9, 1e-9));
    expect(loaded.dimOutside, kDefaultDimOutside);
    await second.close();
  });

  test('после миграции новые настройки пишутся и читаются', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN strip_fit',
    );
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN dim_outside',
    );
    await undoCategories(first);
    await first.database.customStatement('PRAGMA user_version = 1');
    await first.close();

    final AppData second = await launch();
    await second.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        stripFit: 0.8,
        dimOutside: 0.4,
      ),
    );
    final BookReadingSettings loaded = await second.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.stripFit, closeTo(0.8, 1e-9));
    expect(loaded.dimOutside, closeTo(0.4, 1e-9));
    await second.close();
  });
}
