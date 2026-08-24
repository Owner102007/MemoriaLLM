import 'package:flutter/widgets.dart';

import '../../domain/theme/app_palette.dart';

/// Текущая палитра, доступная вглубь дерева.
///
/// `ThemeData` для полки не годится: категории красятся по доменной
/// палитре — тем же набором чисел, на котором проверяется контраст, — а в
/// `ColorScheme` попадает не всё, и обратно из него палитру не собрать.
/// Отдельная область избавляет от протаскивания палитры через
/// конструкторы половины экранов.
class AppPaletteScope extends InheritedWidget {
  /// Создаёт область.
  const AppPaletteScope({
    required this.palette,
    required super.child,
    super.key,
  });

  /// Палитра, действующая ниже по дереву.
  final AppPalette palette;

  /// Палитра из ближайшей области.
  ///
  /// Без области возвращается палитра по умолчанию: виджет-тест, который
  /// проверяет одну карточку, не обязан поднимать всё приложение.
  static AppPalette of(BuildContext context) {
    final AppPaletteScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppPaletteScope>();
    return scope?.palette ?? appPalettes[defaultThemeId]!;
  }

  @override
  bool updateShouldNotify(AppPaletteScope oldWidget) =>
      oldWidget.palette.id != palette.id;
}
