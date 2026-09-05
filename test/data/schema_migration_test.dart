import 'dart:io';

// `isNull` и `isNotNull` есть и у drift (условия запроса), и у matcher
// (проверки теста). Здесь нужны вторые.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/annotations/annotations.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/device_files.dart';
import 'package:memoria/domain/prompts/selection_prompt.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/settings/app_settings.dart';
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

  /// Откатывает базу к версии 6: промптов к выделению тогда не было.
  ///
  /// Вместе с таблицей снимается и отметка «промпты заведены»: у читателя,
  /// который обновляется, её и не могло быть — она появилась в этой же
  /// версии. Без этого проверка мерила бы не то: заведение промптов
  /// случилось бы при первом открытии, а не после миграции.
  Future<void> undoPrompts(AppData data) async {
    await data.database.customStatement('DROP TABLE selection_prompts');
    await data.settings.remove(SettingsKeys.promptsSeeded);
  }

  /// Откатывает базу к версии 5: файлов устройства тогда не было.
  Future<void> undoDeviceFiles(AppData data) async {
    await undoPrompts(data);
    await data.database.customStatement('DROP TABLE device_files');
    await data.database.customStatement('DROP TABLE IF EXISTS device_search');
  }

  /// Откатывает базу к версии 4: мест на полке тогда не было.
  Future<void> undoPositions(AppData data) async {
    await undoDeviceFiles(data);
    await data.database.customStatement(
      'ALTER TABLE books DROP COLUMN shelf_position',
    );
  }

  /// Откатывает базу к версии 3: не было ни категорий, ни мест.
  Future<void> undoCategories(AppData data) async {
    await undoPositions(data);
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
    expect(await columnsOf(data, 'device_files'), contains('fingerprint'));
    expect(
      await columnsOf(data, 'selection_prompts'),
      containsAll(<String>['book_id', 'is_primary', 'hlc', 'node_id']),
    );
    expect(data.searchIndexed, isTrue);
    await data.close();
  });

  test('база версии 6 доезжает до 7 и получает промпты', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.annotations.saveQuote(
      Quote(
        id: 'quote-1',
        bookId: 'book-1',
        page: 7,
        content: 'Две неподвижные идеи',
        createdAt: DateTime.utc(2026, 9, 6),
      ),
    );
    await undoPrompts(first);
    await first.database.customStatement('PRAGMA user_version = 6');
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(await columnsOf(second, 'selection_prompts'), contains('body'));

    // Цитата читателя, обновившего приложение, обязана остаться на месте.
    expect((await second.annotations.quotes('book-1')).single.id, 'quote-1');

    // А промпты из коробки заводятся сразу: обновившийся читатель видит
    // те же две кнопки, что и поставивший приложение впервые.
    final List<SelectionPrompt> master = await second.prompts.masterPrompts();
    expect(master.map((SelectionPrompt p) => p.id), <String>[
      kMeaningPromptId,
      kTranslatePromptId,
    ]);
    expect(master.first.check.isValid, isTrue);
    await second.close();
  });

  test('база версии 5 доезжает до 6 и получает файлы устройства', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.deviceFiles.saveFile(
      DeviceFileRecord(
        path: '/device/Онегин.pdf',
        size: 1000,
        modifiedAt: DateTime.utc(2026, 9, 1),
        seenAt: DateTime.utc(2026, 9, 5),
      ),
    );
    await undoDeviceFiles(first);
    await first.database.customStatement('PRAGMA user_version = 5');
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(await columnsOf(second, 'device_files'), contains('fingerprint'));

    // Список файлов заводится **пустым**: он не переносится ниоткуда, а
    // собирается обходом при первом заходе на экран. А книга читателя,
    // обновившего приложение, обязана остаться на полке.
    expect(await second.deviceFiles.files(), isEmpty);
    expect((await second.library.bookById('book-1'))!.title, 'Пиковая дама');

    // И поиск после миграции сразу работает.
    expect(second.searchIndexed, isTrue);
    await second.deviceFiles.saveFile(
      DeviceFileRecord(
        path: '/device/Пиковая дама.pdf',
        size: 1000,
        modifiedAt: DateTime.utc(2026, 9, 1),
        seenAt: DateTime.utc(2026, 9, 5),
      ),
    );
    expect(await second.deviceFiles.search('пиковая'), <String>[
      '/device/Пиковая дама.pdf',
    ]);
    await second.close();
  });

  test('база версии 4 доезжает до 5 и получает места на полке', () async {
    final AppData first = await launch();
    await first.categories.save(
      BookCategory(
        id: 'study',
        title: 'Учёба',
        position: 0,
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    );
    await first.library.save(testBook());
    await placeBook(first, 'book-1', 'study');
    await undoPositions(first);
    await first.database.customStatement('PRAGMA user_version = 4');
    expect(await columnsOf(first, 'books'), isNot(contains('shelf_position')));
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(await columnsOf(second, 'books'), contains('shelf_position'));

    // Книга и её категория на месте, а место на полке пришло нулевым:
    // читатель ещё ничего не переставлял.
    final Book? book = await second.library.bookById('book-1');
    expect(book!.categoryId, 'study');
    expect(book.shelfPosition, 0);

    // И расстановка сразу работает.
    await placeBook(second, 'book-1', 'study', position: 4);
    expect((await second.library.bookById('book-1'))!.shelfPosition, 4);
    await second.close();
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
    await placeBook(second, 'book-1', 'study');
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
