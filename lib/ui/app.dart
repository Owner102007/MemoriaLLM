import 'package:flutter/material.dart';

import '../application/theme/theme_controller.dart';
import '../domain/theme/app_palette.dart';
import 'library/library_screen.dart';
import 'settings/settings_screen.dart';
import 'theme/theme_builder.dart';

/// Корневой виджет приложения.
class MemoriaApp extends StatelessWidget {
  /// Создаёт приложение с готовым контроллером тем.
  const MemoriaApp({required this.themeController, super.key});

  /// Источник текущей темы.
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeId>(
      valueListenable: themeController,
      builder: (BuildContext context, AppThemeId themeId, Widget? child) {
        return MaterialApp(
          title: 'Memoria LLM HB',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(appPalettes[themeId]!),
          home: HomeShell(themeController: themeController),
        );
      },
    );
  }
}

/// Оболочка с нижней навигацией. Экраны — заглушки: чтение появляется
/// в сессии S3, библиотека — в S5.
class HomeShell extends StatefulWidget {
  /// Создаёт оболочку.
  const HomeShell({required this.themeController, super.key});

  /// Контроллер тем, нужен экрану настроек.
  final ThemeController themeController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          const LibraryScreen(),
          SettingsScreen(themeController: widget.themeController),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <Widget>[
          NavigationDestination(
            key: Key('nav-library'),
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Библиотека',
          ),
          NavigationDestination(
            key: Key('nav-settings'),
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
