import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/domain/theme/app_palette.dart';

import 'test_data.dart';

void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
  });

  tearDown(() async {
    await data.close();
  });

  test('значение пишется, читается и удаляется', () async {
    expect(await data.settings.read('demo'), isNull);

    await data.settings.write('demo', 'первое');
    expect(await data.settings.read('demo'), 'первое');

    await data.settings.write('demo', 'второе');
    expect(await data.settings.read('demo'), 'второе');

    await data.settings.remove('demo');
    expect(await data.settings.read('demo'), isNull);
  });

  test('живое значение обновляется само', () async {
    final Stream<String?> values = data.settings.watch('demo');
    expect(await values.first, isNull);

    await data.settings.write('demo', 'есть');
    expect(await values.first, 'есть');
  });

  test('идентификатор узла рождается один раз', () async {
    final String? first = await data.settings.read(SettingsKeys.nodeId);
    expect(first, isNotNull);
    expect(first, hasLength(32));
    expect(data.clock.nodeId, first);
  });

  test('часы продолжают прошлый запуск того же устройства', () async {
    await data.settings.write('demo', 'чтобы часы тикнули');
    await data.library.save(testBook());
    final String? stored = await data.settings.read(SettingsKeys.lastHlc);
    expect(stored, isNotNull);
  });

  test('тема сохраняется и восстанавливается', () async {
    final ThemeController first = await ThemeController.restore(data.settings);
    expect(first.value, defaultThemeId);

    first.select(AppThemeId.sepia);
    await pumpEventQueue();
    expect(await data.settings.read(SettingsKeys.theme), 'sepia');

    final ThemeController second = await ThemeController.restore(data.settings);
    expect(second.value, AppThemeId.sepia);
  });

  test('неизвестное имя темы не мешает запуску', () async {
    await data.settings.write(SettingsKeys.theme, 'бирюзовая-в-горошек');
    final ThemeController controller = await ThemeController.restore(
      data.settings,
    );
    expect(controller.value, defaultThemeId);
  });
}
