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
  ThemeController({this.settings, AppThemeId initial = defaultThemeId})
    : super(initial);

  /// Читает сохранённую тему и создаёт контроллер с ней.
  static Future<ThemeController> restore(AppSettingsRepository store) async {
    final String? saved = await store.read(SettingsKeys.theme);
    return ThemeController(settings: store, initial: themeIdFromName(saved));
  }

  /// Хранилище настроек. `null` — выбор не сохраняется.
  final AppSettingsRepository? settings;

  /// Палитра текущей темы.
  AppPalette get palette => appPalettes[value]!;

  /// Переключает тему. Повторный выбор той же темы ничего не делает.
  void select(AppThemeId id) {
    if (id == value) {
      return;
    }
    value = id;
    final AppSettingsRepository? store = settings;
    if (store != null) {
      unawaited(store.write(SettingsKeys.theme, id.name));
    }
  }
}
