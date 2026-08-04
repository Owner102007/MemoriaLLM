import 'package:flutter/material.dart';

/// Заглушка библиотеки. Настоящая сетка книг с обложками и прогрессом
/// появляется в сессии S5, чтение — в S3.
class LibraryScreen extends StatelessWidget {
  /// Создаёт экран.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Библиотека')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.auto_stories_outlined,
                size: 72,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 24),
              Text(
                'Memoria LLM HB',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Вернуть электронной книге свойства бумажной '
                'и превзойти их.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                'Полка пока пуста: импорт книг появится в сессии S5, '
                'чтение — в S3.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
