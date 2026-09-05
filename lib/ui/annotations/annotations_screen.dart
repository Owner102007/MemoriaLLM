import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/annotations/annotations.dart';
import '../../domain/annotations/markdown_export.dart';
import '../../domain/library/book.dart';
import '../../domain/library/ids.dart';
import '../reader/note_dialog.dart';

/// Экран «Цитаты и заметки» одной книги.
///
/// Всё, что читатель отметил в книге, собрано в одном месте и в порядке
/// чтения — по страницам, а не по времени. Поиск нужен ровно затем, зачем
/// он нужен в бумажной тетради: найти ту самую мысль, помня из неё два
/// слова. Нормализация у него та же, что у поиска по книгам устройства,
/// — своей второй в проекте не заводится.
class AnnotationsScreen extends StatefulWidget {
  /// Создаёт экран.
  const AnnotationsScreen({
    required this.book,
    required this.annotations,
    super.key,
  });

  /// Книга.
  final Book book;

  /// Хранилище цитат и заметок.
  final AnnotationRepository annotations;

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  final TextEditingController _query = TextEditingController();

  List<Quote> _quotes = const <Quote>[];
  List<Note> _notes = const <Note>[];
  StreamSubscription<List<Quote>>? _quotesWatch;
  StreamSubscription<List<Note>>? _notesWatch;

  @override
  void initState() {
    super.initState();
    _quotesWatch = widget.annotations.watchQuotes(widget.book.id).listen((
      List<Quote> quotes,
    ) {
      if (mounted) {
        setState(() => _quotes = quotes);
      }
    });
    _notesWatch = widget.annotations.watchNotes(widget.book.id).listen((
      List<Note> notes,
    ) {
      if (mounted) {
        setState(() => _notes = notes);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_quotesWatch?.cancel());
    unawaited(_notesWatch?.cancel());
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<_Entry> entries = _entries();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Цитаты и заметки'),
        actions: <Widget>[
          IconButton(
            key: const Key('annotations-export-button'),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Выгрузить в Markdown',
            onPressed: entries.isEmpty ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              key: const Key('annotations-search-field'),
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Найти в цитатах и заметках',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('annotations-search-clear'),
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? _EmptyState(searching: _query.text.trim().isNotEmpty)
                : ListView.builder(
                    key: const Key('annotations-list'),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: entries.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _EntryCard(
                        entry: entries[index],
                        onDelete: () => unawaited(_delete(entries[index])),
                        onNote: () => unawaited(_editNote(entries[index])),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Цитаты и заметки, сложенные в порядке чтения.
  ///
  /// Заметка, привязанная к цитате, живёт внутри её карточки: две
  /// отдельные карточки об одном и том же месте книги — это не список, а
  /// его пересказ.
  List<_Entry> _entries() {
    final String query = _query.text.trim();
    final Map<String, List<Note>> byQuote = <String, List<Note>>{};
    final List<Note> loose = <Note>[];
    for (final Note note in _notes) {
      final String? quoteId = note.quoteId;
      if (quoteId == null) {
        loose.add(note);
      } else {
        byQuote.putIfAbsent(quoteId, () => <Note>[]).add(note);
      }
    }
    final List<_Entry> entries = <_Entry>[
      for (final Quote quote in _quotes)
        _Entry(
          page: quote.page,
          quote: quote,
          notes: byQuote[quote.id] ?? const <Note>[],
        ),
      for (final Note note in loose)
        _Entry(page: note.page, notes: <Note>[note]),
    ];
    entries.sort((_Entry a, _Entry b) => a.page.compareTo(b.page));
    if (query.isEmpty) {
      return entries;
    }
    return <_Entry>[
      for (final _Entry entry in entries)
        if (matchesQuery(entry.searchable, query)) entry,
    ];
  }

  Future<void> _delete(_Entry entry) async {
    final Quote? quote = entry.quote;
    for (final Note note in entry.notes) {
      await widget.annotations.deleteNote(note.id);
    }
    if (quote != null) {
      await widget.annotations.deleteQuote(quote.id);
    }
  }

  Future<void> _editNote(_Entry entry) async {
    final Note? existing = entry.notes.isEmpty ? null : entry.notes.first;
    final String? body = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => NoteDialog(
        quote: entry.quote?.content ?? existing?.body ?? '',
        initial: existing?.body ?? '',
      ),
    );
    if (body == null) {
      return;
    }
    final DateTime now = DateTime.now();
    if (existing != null) {
      await widget.annotations.saveNote(
        existing.copyWith(body: body, updatedAt: now),
      );
      return;
    }
    final Quote? quote = entry.quote;
    if (quote == null) {
      return;
    }
    await widget.annotations.saveNote(
      Note(
        id: newLibraryId(),
        bookId: widget.book.id,
        quoteId: quote.id,
        page: quote.page,
        body: body,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _export() async {
    final String markdown = annotationsToMarkdown(
      bookTitle: widget.book.title,
      author: widget.book.author,
      quotes: _quotes,
      notes: _notes,
      exportedAt: DateTime.now(),
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _ExportSheet(markdown: markdown),
    );
  }
}

/// Одна строка списка: цитата с её заметками или заметка сама по себе.
class _Entry {
  const _Entry({required this.page, this.quote, this.notes = const <Note>[]});

  final int page;
  final Quote? quote;
  final List<Note> notes;

  /// Текст, по которому ищут.
  String get searchable {
    final StringBuffer buffer = StringBuffer();
    final Quote? quote = this.quote;
    if (quote != null) {
      buffer.write(quote.content);
      buffer.write(' ');
    }
    for (final Note note in notes) {
      buffer.write(note.body);
      buffer.write(' ');
    }
    return buffer.toString();
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.onDelete,
    required this.onNote,
  });

  final _Entry entry;
  final VoidCallback onDelete;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Quote? quote = entry.quote;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Страница ${entry.page}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (quote != null)
              Text(quote.content, style: theme.textTheme.bodyMedium),
            for (final Note note in entry.notes) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.edit_note,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(note.body, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  key: Key('annotation-note-${quote?.id ?? entry.page}'),
                  onPressed: onNote,
                  child: Text(entry.notes.isEmpty ? 'Заметка' : 'Правка'),
                ),
                IconButton(
                  key: Key('annotation-delete-${quote?.id ?? entry.page}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Удалить',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          searching
              ? 'Ничего не нашлось.'
              : 'Пока пусто. Выделите текст в книге и нажмите «В цитаты».',
          key: const Key('annotations-empty'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Готовая выгрузка: её видно целиком и её можно забрать.
///
/// Показывается текстом, а не сохраняется молча в неизвестное место: на
/// Android «сохранённый файл» без общего экрана выбора папки — это файл,
/// который читатель больше не найдёт.
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.markdown});

  final String markdown;

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
            Text('Выгрузка в Markdown', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  markdown,
                  key: const Key('annotations-export-text'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                FilledButton.tonalIcon(
                  key: const Key('annotations-export-copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: markdown));
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Выгрузка скопирована в буфер обмена'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(
                    defaultTargetPlatform == TargetPlatform.android
                        ? 'Скопировать'
                        : 'Скопировать в буфер',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
