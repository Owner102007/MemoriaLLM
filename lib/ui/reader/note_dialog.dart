import 'package:flutter/material.dart';

/// Окно заметки к выделенному месту.
///
/// Заметка всегда пишется **к чему-то**: сверху видно, о каком куске
/// книги речь. Пометка на полях без самого места на полях — это просто
/// строчка неизвестно о чём, и через месяц она бесполезна.
class NoteDialog extends StatefulWidget {
  /// Создаёт окно.
  const NoteDialog({required this.quote, this.initial = '', super.key});

  /// Выделенный текст, к которому пишется заметка.
  final String quote;

  /// Прежний текст заметки, если её правят.
  final String initial;

  @override
  State<NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<NoteDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Заметка'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.quote,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('note-field'),
            controller: _field,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Что вы об этом думаете',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('note-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('note-save'),
          onPressed: () {
            final String body = _field.text.trim();
            Navigator.of(context).pop(body.isEmpty ? null : body);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
