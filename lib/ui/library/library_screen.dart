import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/shelf.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import '../reader/reader_screen.dart';
import 'category_shelf.dart';
import 'library_dialogs.dart';

/// Полка книг.
///
/// Полка состоит из категорий: у каждой свой узор и цвет подложки,
/// выведенные из названия, и своя сетка блоков — книга занимает блок,
/// последним блоком стоит кнопка «+». Раздел «Без категории» стоит
/// первым и никогда не удаляется: он не строка в базе, а просто книги,
/// которые никуда не разложили.
class LibraryScreen extends StatefulWidget {
  /// Создаёт экран.
  const LibraryScreen({required this.services, super.key});

  /// Службы приложения.
  final AppServices services;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Сколько секунд книга ждёт, прежде чем её источник будет отпущен.
  ///
  /// Снятие с полки необратимо для источника: своя копия удаляется, а
  /// закреплённая ссылка освобождается. Промах по кнопке стоил бы
  /// повторного выбора файла, поэтому отпускание откладывается ровно на
  /// время, пока внизу висит «Вернуть».
  static const Duration _undoWindow = Duration(seconds: 5);

  ShelfSort _sort = ShelfSort.recent;
  bool _busy = false;
  final Map<String, Timer> _pending = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSort());
  }

  @override
  void dispose() {
    for (final Timer timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    super.dispose();
  }

  Future<void> _restoreSort() async {
    final String? stored = await widget.services.data.settings.read(
      SettingsKeys.shelfSort,
    );
    if (!mounted) {
      return;
    }
    setState(() => _sort = shelfSortFromName(stored));
  }

  Future<void> _chooseSort(ShelfSort sort) async {
    setState(() => _sort = sort);
    await widget.services.data.settings.write(
      SettingsKeys.shelfSort,
      sort.name,
    );
  }

  /// Заводит выбранные книги сразу в нужную категорию.
  Future<void> _addBooks(String? categoryId) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final List<PickedFile> files = await widget.services.picker.pickPdfs();
      if (files.isEmpty) {
        return;
      }
      final BookImporter importer = BookImporter(
        library: widget.services.data.library,
        storage: widget.services.storage,
        opener: widget.services.opener,
      );
      final ImportReport report = await importer.registerAll(
        files,
        categoryId: categoryId,
      );
      if (!mounted) {
        return;
      }
      _say(_describeImport(report));
      // Одну книгу читатель выбирал, чтобы её открыть, а не чтобы
      // полюбоваться полкой. Пачку — наоборот: открывать первую попавшуюся
      // из тридцати было бы наглостью.
      if (report.added.length == 1 && report.isClean) {
        await _openBook(report.added.single);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _describeImport(ImportReport report) {
    if (report.added.isEmpty) {
      return report.failed.length == 1
          ? 'Не удалось добавить: ${report.failed.single.reason}'
          : 'Не удалось добавить ни одной книги из ${report.total}';
    }
    if (report.isClean) {
      return report.added.length == 1
          ? 'Книга добавлена'
          : 'Добавлено книг: ${report.added.length}';
    }
    return 'Добавлено ${report.added.length} из ${report.total}; '
        'не открылось: ${report.failed.length}';
  }

  /// Убирает книгу с полки — с возможностью вернуть.
  ///
  /// Строка в базе получает надгробие сразу: книга обязана исчезнуть с
  /// полки в тот же миг, иначе непонятно, сработало ли нажатие. А вот
  /// источник — своя копия и закреплённая ссылка — отпускается только
  /// после того, как окно отмены закрылось: вернуть их назад нельзя.
  Future<void> _removeBook(Book book) async {
    await widget.services.data.library.delete(book.id);
    if (!mounted) {
      return;
    }
    _pending[book.id]?.cancel();
    _pending[book.id] = Timer(_undoWindow, () {
      _pending.remove(book.id);
      unawaited(_releaseBook(book));
    });
    final SnackBar bar = SnackBar(
      content: Text('«${book.title}» убрана с полки'),
      duration: _undoWindow,
      action: SnackBarAction(
        label: 'Вернуть',
        onPressed: () => unawaited(_restoreBook(book)),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(bar);
  }

  Future<void> _releaseBook(Book book) async {
    await widget.services.covers.forget(book);
    await widget.services.storage.release(book.source);
  }

  Future<void> _restoreBook(Book book) async {
    _pending.remove(book.id)?.cancel();
    await widget.services.data.library.save(book);
  }

  Future<void> _moveBook(Book book, List<BookCategory> categories) async {
    final MoveTarget? target = await askWhereToMove(
      context,
      categories: categories,
      current: book.categoryId,
    );
    if (target == null || !mounted) {
      return;
    }
    String? destination = target.categoryId;
    if (target.isNew) {
      await _afterFrame();
      if (!mounted) {
        return;
      }
      final BookCategory? created = await _createCategory(categories.length);
      if (created == null) {
        return;
      }
      destination = created.id;
    }
    await widget.services.data.library.moveToCategory(book.id, destination);
  }

  Future<BookCategory?> _createCategory(int position) async {
    final String? name = await askCategoryName(context);
    if (name == null) {
      return null;
    }
    final BookCategory category = BookCategory(
      id: newCategoryId(),
      title: normalizeCategoryTitle(name),
      position: position,
      createdAt: DateTime.now(),
    );
    await widget.services.data.categories.save(category);
    return category;
  }

  Future<void> _renameCategory(BookCategory category) async {
    // Меню категории в этот момент ещё уходит с экрана — см. [_afterFrame].
    await _afterFrame();
    if (!mounted) {
      return;
    }
    final String? name = await askCategoryName(
      context,
      initial: category.title,
    );
    if (name == null) {
      return;
    }
    await widget.services.data.categories.save(
      category.copyWith(title: normalizeCategoryTitle(name)),
    );
  }

  Future<void> _deleteCategory(BookCategory category) async {
    await _afterFrame();
    if (!mounted) {
      return;
    }
    final bool confirmed = await confirmCategoryRemoval(context, category);
    if (!confirmed) {
      return;
    }
    await widget.services.data.categories.delete(category.id);
    if (mounted) {
      _say('Категория убрана, книги остались на полке');
    }
  }

  Future<void> _openBook(Book book) async {
    await widget.services.data.library.markOpened(book.id, DateTime.now());
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ReaderScreen(book: book, services: widget.services),
      ),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: <Widget>[
          PopupMenuButton<ShelfSort>(
            key: const Key('library-sort'),
            icon: const Icon(Icons.sort),
            tooltip: 'Порядок книг',
            initialValue: _sort,
            onSelected: (ShelfSort sort) => unawaited(_chooseSort(sort)),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<ShelfSort>>[
              for (final ShelfSort sort in ShelfSort.values)
                PopupMenuItem<ShelfSort>(
                  value: sort,
                  child: Text(shelfSortTitle(sort)),
                ),
            ],
          ),
          IconButton(
            key: const Key('library-new-category'),
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Новая категория',
            onPressed: () => unawaited(_newCategoryFromBar()),
          ),
          IconButton(
            key: const Key('library-open-file'),
            icon: const Icon(Icons.library_add_outlined),
            tooltip: 'Добавить книги',
            onPressed: _busy ? null : () => unawaited(_addBooks(null)),
          ),
        ],
      ),
      body: StreamBuilder<List<BookCategory>>(
        stream: widget.services.data.categories.watchCategories(),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<BookCategory>> categories,
            ) {
              return StreamBuilder<List<Book>>(
                stream: widget.services.data.library.watchBooks(),
                builder:
                    (BuildContext context, AsyncSnapshot<List<Book>> books) {
                      return StreamBuilder<Map<String, ReadingPosition>>(
                        stream: widget.services.data.reading.watchPositions(),
                        builder:
                            (
                              BuildContext context,
                              AsyncSnapshot<Map<String, ReadingPosition>>
                              positions,
                            ) {
                              return _buildShelf(
                                categories:
                                    categories.data ?? const <BookCategory>[],
                                books: books.data ?? const <Book>[],
                                positions:
                                    positions.data ??
                                    const <String, ReadingPosition>{},
                              );
                            },
                      );
                    },
              );
            },
      ),
    );
  }

  Future<void> _newCategoryFromBar() async {
    final List<BookCategory> existing = await widget.services.data.categories
        .categories();
    if (!mounted) {
      return;
    }
    await _createCategory(existing.length);
  }

  Widget _buildShelf({
    required List<BookCategory> categories,
    required List<Book> books,
    required Map<String, ReadingPosition> positions,
  }) {
    final Map<String, double> progress = <String, double>{
      for (final MapEntry<String, ReadingPosition> entry in positions.entries)
        entry.key: entry.value.progress,
    };
    if (books.isEmpty && categories.isEmpty) {
      return _EmptyShelf(busy: _busy, onOpen: () => unawaited(_addBooks(null)));
    }
    final List<ShelfSection> sections = buildShelf(
      categories: categories,
      books: books,
      sort: _sort,
      progress: progress,
    );
    return ListView.builder(
      key: const Key('library-shelf'),
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: sections.length,
      itemBuilder: (BuildContext context, int index) {
        final ShelfSection section = sections[index];
        final BookCategory? category = section.category;
        return CategoryShelf(
          section: section,
          covers: widget.services.covers,
          progress: progress,
          busy: _busy,
          onOpen: (Book book) => unawaited(_openBook(book)),
          onMenu: (Book book) => unawaited(_showBookMenu(book, categories)),
          onAdd: () => unawaited(_addBooks(category?.id)),
          onRename: category == null
              ? null
              : () => unawaited(_renameCategory(category)),
          onDelete: category == null
              ? null
              : () => unawaited(_deleteCategory(category)),
        );
      },
    );
  }

  /// Ждёт, пока закроется то, что закрывается.
  ///
  /// Открывать диалог в тот же миг, когда предыдущая шторка ещё уходит с
  /// экрана, нельзя: две области фокуса накладываются, и Flutter роняет
  /// сборку кадра. Один кадр ожидания стоит меньше, чем сломанное дерево
  /// виджетов.
  Future<void> _afterFrame() => WidgetsBinding.instance.endOfFrame;

  Future<void> _showBookMenu(Book book, List<BookCategory> categories) async {
    final BookAction? action = await askBookAction(context, book);
    if (action == null || !mounted) {
      return;
    }
    await _afterFrame();
    if (!mounted) {
      return;
    }
    switch (action) {
      case BookAction.open:
        await _openBook(book);
      case BookAction.move:
        await _moveBook(book, categories);
      case BookAction.remove:
        await _removeBook(book);
    }
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
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Добавить книги'),
            ),
            const SizedBox(height: 16),
            Text(
              'Можно отметить сразу несколько файлов. Категории заводятся '
              'кнопкой в шапке — у каждой свой узор полки.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
