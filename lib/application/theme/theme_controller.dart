import 'package:flutter/foundation.dart';

import '../../domain/theme/app_palette.dart';

/// Хранит выбранную тему и оповещает интерфейс о её смене.
///
/// Сейчас выбор живёт только в памяти: слой данных появляется в сессии S2,
/// тогда же тема начнёт сохраняться между запусками.
class ThemeController extends ValueNotifier<AppThemeId> {
  /// Создаёт контроллер. По умолчанию — тёмно-красная тема.
  ThemeController({AppThemeId initial = defaultThemeId}) : super(initial);

  /// Палитра текущей темы.
  AppPalette get palette => appPalettes[value]!;

  /// Переключает тему. Повторный выбор той же темы ничего не делает.
  void select(AppThemeId id) => value = id;
}
