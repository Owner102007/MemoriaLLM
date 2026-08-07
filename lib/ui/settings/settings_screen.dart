import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/build_info.dart';
import '../../application/theme/theme_controller.dart';
import '../../domain/theme/app_palette.dart';

/// Настройки. Пока здесь только выбор темы — остальное появляется
/// по мере роста приложения.
class SettingsScreen extends StatelessWidget {
  /// Создаёт экран настроек.
  const SettingsScreen({required this.themeController, super.key});

  /// Контроллер тем.
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ValueListenableBuilder<AppThemeId>(
        valueListenable: themeController,
        builder: (BuildContext context, AppThemeId current, Widget? child) {
          return ListView(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Оформление', style: theme.textTheme.titleMedium),
              ),
              for (final AppPalette palette in appPalettes.values)
                _ThemeTile(
                  palette: palette,
                  selected: palette.id == current,
                  onTap: () {
                    unawaited(themeController.select(palette.id));
                  },
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Тема сохраняется на этом устройстве и не переносится '
                  'на другие: читать ночью с телефона и днём с ПК удобнее '
                  'в разных палитрах.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              ListTile(
                key: const Key('build-label'),
                dense: true,
                title: Text('Сборка', style: theme.textTheme.bodySmall),
                subtitle: Text(buildLabel, style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      key: Key('theme-${palette.id.name}'),
      onTap: onTap,
      leading: _Swatch(palette: palette),
      title: Text(palette.title),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.secondary)
          : null,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Color(palette.background),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(palette.divider)),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Color(palette.accent),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
