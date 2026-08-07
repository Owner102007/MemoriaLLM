import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/domain/sync/hlc.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:path/path.dart' as p;

import 'test_data.dart';

/// Перезапуск приложения: новый экземпляр слоя данных поверх того же файла.
///
/// Все остальные тесты работают с базой в памяти и поэтому в принципе не
/// могут поймать поломку записи на диск. Этот файл — про то, что данные
/// переживают закрытие приложения.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('memoria-restart');
    file = File(p.join(dir.path, 'memoria.sqlite'));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<AppData> launch() async {
    return AppData.open(executor: NativeDatabase(file));
  }

  test('выбранная тема переживает перезапуск', () async {
    final AppData first = await launch();
    final ThemeController controller = await ThemeController.restore(
      first.settings,
    );
    expect(controller.value, defaultThemeId);
    await controller.select(AppThemeId.sepia);
    await first.close();

    expect(file.existsSync(), isTrue, reason: 'файл базы не создан');

    final AppData second = await launch();
    final ThemeController restored = await ThemeController.restore(
      second.settings,
    );
    expect(restored.value, AppThemeId.sepia);
    await second.close();
  });

  test('тема переживает перезапуск и без закрытия базы', () async {
    final AppData first = await launch();
    final ThemeController controller = await ThemeController.restore(
      first.settings,
    );
    await controller.select(AppThemeId.nightRed);
    // Приложение убито системой: close() никто не вызвал.

    final AppData second = await launch();
    final ThemeController restored = await ThemeController.restore(
      second.settings,
    );
    expect(restored.value, AppThemeId.nightRed);
    await second.close();
  });

  test('идентификатор устройства рождается один раз', () async {
    final AppData first = await launch();
    final String firstNode = first.clock.nodeId;
    await first.close();

    final AppData second = await launch();
    expect(second.clock.nodeId, firstNode);
    await second.close();
  });

  test('часы не идут назад после перезапуска', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    final Hlc before = first.clock.last;
    await first.close();

    final AppData second = await launch();
    await second.library.save(testBook(id: 'book-2', hash: 'hash-2'));
    expect(second.clock.last.compareTo(before), greaterThan(0));
    await second.close();
  });

  test('книги и цитаты переживают перезапуск', () async {
    final AppData first = await launch();
    await first.library.save(testBook());
    await first.close();

    final AppData second = await launch();
    final Book? book = await second.library.bookById('book-1');
    expect(book?.title, 'Пиковая дама');
    await second.close();
  });

  test('ключ настроек не теряется между запусками', () async {
    final AppData first = await launch();
    await first.settings.write(SettingsKeys.targetLanguage, 'ru');
    await first.close();

    final AppData second = await launch();
    expect(await second.settings.read(SettingsKeys.targetLanguage), 'ru');
    await second.close();
  });
}
