import 'package:flutter/material.dart';

/// Объяснение доступа ко всем файлам — до системного перехода.
///
/// Три строки, и порядок в них не случаен: **что ищем, что делаем, чего
/// не делаем**. Читатель соглашается не на «разрешение», а на понятную
/// работу, и сказать об этом надо до того, как система покажет свой экран
/// с пугающей формулировкой «Разрешить доступ ко всем файлам».
///
/// Четвёртая строка — про отказ, и она обязательна. Приложение, которое
/// продаёт приватность, не имеет права делать вид, что без разрешения оно
/// не работает: работает, и полностью.
class StoragePermissionView extends StatelessWidget {
  /// Создаёт экран объяснения.
  const StoragePermissionView({
    required this.onRequest,
    required this.onPickManually,
    this.denied = false,
    super.key,
  });

  /// Перейти к системному экрану выдачи разрешения.
  final VoidCallback onRequest;

  /// Выбрать книги по одной системным диалогом — путь без разрешения.
  final VoidCallback onPickManually;

  /// Разрешение уже просили и не дали.
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.folder_open_outlined,
              size: 56,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 20),
            Text(
              'Найти книги на устройстве',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            const _Line(
              icon: Icons.search,
              text: 'Ищем: файлы PDF там, где они у вас лежат.',
            ),
            const _Line(
              icon: Icons.image_outlined,
              text:
                  'Делаем: показываем их списком с обложками и поиском. '
                  'Всё найденное остаётся на устройстве.',
            ),
            const _Line(
              icon: Icons.block,
              text:
                  'Не делаем: не копируем книги к себе, ничего не удаляем '
                  'и не отправляем содержимое файлов наружу.',
            ),
            const SizedBox(height: 12),
            Text(
              'Отказ ничего не ломает: книги по-прежнему добавляются по '
              'одной через системный диалог. Разрешение можно отозвать в '
              'настройках Android в любой момент.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            if (denied)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Разрешения пока нет. Если системный экран не открылся, '
                  'его можно найти сами: Настройки → Приложения → '
                  'Memoria → Доступ ко всем файлам.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            Row(
              children: <Widget>[
                FilledButton(
                  key: const Key('device-grant'),
                  onPressed: onRequest,
                  child: const Text('Разрешить доступ'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  key: const Key('device-pick-manually'),
                  onPressed: onPickManually,
                  child: const Text('Выбрать файлы'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
