import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
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

  test('новая база создаётся сразу текущей версией', () async {
    final AppData data = await launch();
    expect(await versionOf(data), appSchemaVersion);
    expect(await columnsOf(data, 'book_settings'), contains('strip_fit'));
    await data.close();
  });

  test('база версии 1 доезжает до 2 и не теряет настройки книги', () async {
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

    // Откат к версии 1: колонки запаса по краям тогда не было.
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN strip_fit',
    );
    await first.database.customStatement('PRAGMA user_version = 1');
    expect(
      await columnsOf(first, 'book_settings'),
      isNot(contains('strip_fit')),
    );
    await first.close();

    final AppData second = await launch();
    expect(await versionOf(second), appSchemaVersion);
    expect(await columnsOf(second, 'book_settings'), contains('strip_fit'));

    final BookReadingSettings loaded = await second.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    // Настройки читателя обязаны пережить обновление приложения целиком.
    expect(loaded.displayMode, PageDisplayMode.half);
    expect(loaded.filter, ReadingFilter.nightRed);
    expect(loaded.filterIntensity, 0.5);
    expect(loaded.brightness, 0.6);
    // А новая настройка приходит со значением по умолчанию: книга, которую
    // читали до обновления, открывается точно так же, как открывалась.
    expect(loaded.stripFit, 1);
    await second.close();
  });

  test('после миграции запас по краям пишется и читается', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.database.customStatement(
      'ALTER TABLE book_settings DROP COLUMN strip_fit',
    );
    await first.database.customStatement('PRAGMA user_version = 1');
    await first.close();

    final AppData second = await launch();
    await second.reading.saveSettings(
      const BookReadingSettings(
        bookId: 'book-1',
        orientation: ScreenOrientation.portrait,
        stripFit: 0.8,
      ),
    );
    final BookReadingSettings loaded = await second.reading.settings(
      'book-1',
      ScreenOrientation.portrait,
    );
    expect(loaded.stripFit, closeTo(0.8, 1e-9));
    await second.close();
  });
}
