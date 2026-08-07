import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../reader/reader_screen.dart';

/// Полка книг.
///
/// Сетка с обложками, сортировками и «толщиной корешка» — задача S5.
/// Здесь список ровно такой, какой нужен чтению: открыть файл, увидеть
/// уже открывавшиеся книги и вернуться в ту, которую читаешь.
class LibraryScreen extends StatefulWidget {
  /// Создаёт экран.
  const LibraryScreen({required this.services, super.key});

  /// Службы приложения.
  final AppServices services;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;

  Future<void> _openFile() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final PickedFile? file = await widget.services.picker.pickPdf();
      if (file == null) {
        return;
      }
      final BookImporter importer = BookImporter(
        library: widget.services.data.library,
        opener: widget.services.opener,
      );
      final Book book = await importer.register(file);
      if (!mounted) {
        return;
      }
      await _openBook(book);
    } on DocumentOpenException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeDocumentProblem(error.problem))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openBook(Book book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ReaderScreen(book: book, services: widget.services),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: <Widget>[
          IconButton(
            key: const Key('library-open-file'),
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Открыть PDF',
            onPressed: _busy ? null : _openFile,
          ),
        ],
      ),
      body: StreamBuilder<List<Book>>(
        stream: widget.services.data.library.watchBooks(),
        builder: (BuildContext context, AsyncSnapshot<List<Book>> snapshot) {
          final List<Book> books = snapshot.data ?? const <Book>[];
          if (books.isEmpty) {
            return _EmptyShelf(busy: _busy, onOpen: _openFile);
          }
          return ListView.separated(
            key: const Key('library-list'),
            itemCount: books.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Book book = books[index];
              return _BookTile(
                book: book,
                reading: widget.services.data.reading,
                onTap: () => unawaited(_openBook(book)),
                onRemove: () =>
                    widget.services.data.library.delete(book.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.busy, required this.onOpen});

  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
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
            FilledButton.icon(
              key: const Key('library-open-file-empty'),
              onPressed: busy ? null : onOpen,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Открыть PDF'),
            ),
            const SizedBox(height: 16),
            Text(
              'Полка с обложками и импортом целой папки появится '
              'в следующей сессии.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.reading,
    required this.onTap,
    required this.onRemove,
  });

  final Book book;
  final ReadingRepository reading;
  final VoidCallback onTap;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      key: Key('library-book-${book.id}'),
      onTap: onTap,
      leading: const Icon(Icons.picture_as_pdf_outlined),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: StreamBuilder<ReadingPosition?>(
        stream: reading.watchPosition(book.id),
        builder: (
          BuildContext context,
          AsyncSnapshot<ReadingPosition?> snapshot,
        ) {
          final ReadingPosition? position = snapshot.data;
          final int pages = book.pageCount ?? 0;
          final List<String> parts = <String>[
            if (pages > 0) 'страниц: $pages',
            if (position != null && pages > 0)
              'остановились на ${position.page} '
                  '(${progressPercent(position.progress)}%)',
            if (book.hasTextLayer == false) 'скан без текстового слоя',
          ];
          return Text(
            parts.isEmpty ? 'ещё не открывали' : parts.join(' · '),
            style: theme.textTheme.bodySmall,
          );
        },
      ),
      trailing: IconButton(
        key: Key('library-remove-${book.id}'),
        icon: const Icon(Icons.close),
        tooltip: 'Убрать с полки',
        onPressed: () => unawaited(onRemove()),
      ),
    );
  }
}
