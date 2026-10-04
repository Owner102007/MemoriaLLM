import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/settings/app_settings.dart';
import '../../domain/theme/app_palette.dart';

/// Хранит выбранную тему и оповещает интерфейс о её смене.
///
/// Выбор сохраняется в локальных настройках: тема — свойство устройства,
/// а не библиотеки, поэтому на синхронизацию она не попадает.
class ThemeController extends ValueNotifier<AppThemeId> {
  /// Создаёт контроллер. Без хранилища выбор живёт только в памяти —
  /// так удобно в тестах и превью.
  ThemeController({this.settings}) : super(defaultThemeId);

  /// Читает сохранённую тему и создаёт контроллер с ней.
  static Future<ThemeController> restore(AppSettingsRepository store) async {
    final String? saved = await store.read(SettingsKeys.theme);
    final ThemeController controller = ThemeController(settings: store);
    controller.value = themeIdFromName(saved);
    return controller;
  }

  /// Хранилище настроек. `null` — выбор не сохраняется.
  final AppSettingsRepository? settings;

  /// Перечитывает тему из настроек.
  ///
  /// Нужно, когда настройки изменили мимо контроллера: сброс к
  /// эталонному состоянию в сборке ветви СНО2026 стирает их разом
  /// (SNO-F-CFG-04), и тема обязана вернуться к исходной без
  /// перезапуска. Записи при этом нет: в настройках уже лежит то, что
  /// надо показать.
  Future<void> reload() async {
    final AppSettingsRepository? store = settings;
    value = store == null
        ? defaultThemeId
        : themeIdFromName(await store.read(SettingsKeys.theme));
  }

  /// Палитра текущей темы.
  AppPalette get palette => appPalettes[value]!;

  /// Переключает тему и сохраняет выбор.
  ///
  /// Интерфейс перекрашивается сразу, не дожидаясь записи, но сама запись
  /// возвращается вызывающему: молча потерянная настройка выглядит для
  /// человека как сломанное приложение, поэтому ошибка должна иметь
  /// возможность всплыть, а тест — дождаться.
  Future<void> select(AppThemeId id) async {
    if (id == value) {
      return;
    }
    value = id;
    final AppSettingsRepository? store = settings;
    if (store == null) {
      return;
    }
    await store.write(SettingsKeys.theme, id.name);
  }
}
