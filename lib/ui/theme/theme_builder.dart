import 'package:flutter/material.dart';

import '../../domain/theme/app_palette.dart';

/// Превращает доменную палитру в `ThemeData`.
///
/// Доменный слой не знает про Flutter и хранит цвета целыми числами —
/// перевод в `Color` происходит здесь, на границе интерфейса.
ThemeData buildTheme(AppPalette palette) {
  final ColorScheme scheme = ColorScheme(
    brightness: palette.isDark ? Brightness.dark : Brightness.light,
    primary: Color(palette.accent),
    onPrimary: Color(palette.onAccent),
    secondary: Color(palette.accentText),
    onSecondary: Color(palette.background),
    error: Color(palette.accentPressed),
    onError: Color(palette.onAccent),
    surface: Color(palette.surface),
    onSurface: Color(palette.text),
  );

  return ThemeData(
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: Color(palette.background),
    canvasColor: Color(palette.background),
    dividerColor: Color(palette.divider),
    dividerTheme: DividerThemeData(
      color: Color(palette.divider),
      space: 1,
      thickness: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Color(palette.background),
      foregroundColor: Color(palette.text),
      elevation: 0,
      centerTitle: false,
    ),
    listTileTheme: ListTileThemeData(
      textColor: Color(palette.text),
      iconColor: Color(palette.accentText),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Color(palette.surface),
      indicatorColor: Color(palette.accent),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Color(palette.onAccent)
              : Color(palette.textSecondary),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) => TextStyle(
          fontSize: 12,
          color: states.contains(WidgetState.selected)
              ? Color(palette.text)
              : Color(palette.textSecondary),
        ),
      ),
    ),
  );
}
