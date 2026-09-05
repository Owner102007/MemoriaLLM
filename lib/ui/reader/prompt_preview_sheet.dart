import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/prompts/selection_prompt.dart';

/// Что покажет нажатие на промпт, пока модели ещё нет.
///
/// Ответы появятся в S8, и до тех пор кнопка обязана говорить правду:
/// вот запрос, который уйдёт модели, вот когда она появится. Молчащая
/// кнопка хуже отсутствующей, а кнопка, показывающая готовый запрос,
/// вдобавок отвечает на главный вопрос этой сессии — попал ли контекст
/// в тот абзац, в который надо, или уехал в соседнюю колонку.
class PromptPreviewSheet extends StatelessWidget {
  /// Создаёт лист предпросмотра.
  const PromptPreviewSheet({
    required this.prompt,
    required this.request,
    super.key,
  });

  /// Промпт, на который нажали.
  final SelectionPrompt prompt;

  /// Готовый текст запроса — с подставленным выделением и контекстом.
  final String request;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(prompt.name, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: const Key('prompt-preview-close'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ответы модели появятся в следующей сессии. Пока вот запрос, '
              'который к ней уйдёт.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    request,
                    key: const Key('prompt-preview-text'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: const Key('prompt-preview-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: request));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Скопировать запрос'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
