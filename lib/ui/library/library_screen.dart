import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/drag_scroll.dart';
import '../../domain/library/shelf.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import '../reader/reader_screen.dart';
import 'book_drag.dart';
import 'category_shelf.dart';
import 'device_books_screen.dart';
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

  /// Как часто полка сдвигается, пока книгу держат у края.
  ///
  /// Шаг считается **из скорости и прошедшего времени**, а не задаётся
  /// в точках за тик: сама скорость живёт в `domain/library/drag_scroll.dart`
  /// и проверяется там же, а здесь остаётся только перевод в пиксели.
  static const Duration _autoScrollTick = Duration(milliseconds: 16);

  ShelfSort _sort = ShelfSort.recent;
  final Map<String, Timer> _pending = <String, Timer>{};
  final ScrollController _shelf = ScrollController();

  /// Ключ на сам список категорий.
  ///
  /// Зона самопрокрутки отсчитывается от **полки**, а не от экрана:
  /// сверху стоит панель приложения, и зона, отсчитанная от экрана,
  /// уходила бы под неё.
  final GlobalKey _shelfViewport = GlobalKey();

  Timer? _autoScroll;
  double _scrollSpeed = 0;
  DragScrollGate _gate = DragScrollGate();

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
    _autoScroll?.cancel();
    _shelf.dispose();
    super.dispose();
  }

  /// Книгу подняли: полка готовится ехать под пальцем.
  void _dragStarted() {
    _scrollSpeed = 0;
    // Предохранитель заводится заново на каждое поднятие книги: книга,
    // взятая из верхнего ряда, не имеет права увезти полку сама собой.
    _gate = DragScrollGate();
    _autoScroll?.cancel();
    // Один таймер на всё перетаскивание, а не по таймеру на движение:
    // книгу ведут десятками событий в секунду, и заводить на каждое своё
    // ожидание значило бы дёргать полку рывками.
    _autoScroll = Timer.periodic(_autoScrollTick, (Timer _) {
      if (_scrollSpeed == 0 || !_shelf.hasClients) {
        return;
      }
      final ScrollPosition position = _shelf.position;
      final double step =
          _scrollSpeed * _autoScrollTick.inMicroseconds / 1000000;
      final double next = (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) {
        position.jumpTo(next);
      }
    });
  }

  /// Книгу отпустили — где угодно, в том числе мимо полки.
  void _dragEnded() {
    _scrollSpeed = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  /// Книгу ведут над полкой: у её краёв список едет сам.
  ///
  /// Без этого книгу нельзя перенести в категорию, которой не видно, —
  /// а на полке из десятка категорий это обычный случай. Зон две:
  /// у самого края полка едет быстро, чуть дальше от него — медленно.
  /// Вся арифметика — в [DragScrollGate], и одна и та же на телефоне и
  /// на ПК: мышь колесом полку прокрутит, но вести книгу и крутить колесо
  /// одновременно — не то, чего стоит требовать от читателя.
  ///
  /// Мерить надо от **списка**, а не от экрана. Прежде здесь стоял
  /// `context.findRenderObject()`, то есть коробка всего экрана вместе с
  /// панелью приложения: зона в 22 % высоты начиналась выше самой полки,
  /// и быстрая её половина целиком пряталась под панелью — вверх полка
  /// умела ехать только медленно, а книга, поднятая из верхнего ряда,
  /// сразу оказывалась в зоне и уезжала вместе с полкой.
  void _dragOver(Offset globalPosition) {
    final RenderObject? object = _shelfViewport.currentContext
        ?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return;
    }
    _scrollSpeed = _gate.speedAt(
      y: object.globalToLocal(globalPosition).dy,
      height: object.size.height,
    );
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

  /// Открывает экран книг, лежащих на устройстве.
  ///
  /// С S5.5 «+» ведёт сюда, а не в системный диалог. Разница в том, кто
  /// ищет книгу: прежде — читатель, вспоминая, в какой папке она лежит;
  /// теперь — приложение, показывая всё, что нашлось, с обложками и
  /// поиском. Системный диалог никуда не делся и стоит на том же экране
  /// кнопкой в шапке: разрешения может не быть, а книгу добавить надо.
  Future<void> _addBooks(String? categoryId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DeviceBooksScreen(
          services: widget.services,
          categoryId: categoryId,
        ),
      ),
    );
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

  Future<void> _moveBook(
    Book book,
    List<BookCategory> categories,
    List<ShelfSection> sections,
  ) async {
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
    // Через меню книга встаёт в конец выбранной категории: места
    // назначения читатель не выбирал, а совать её в середину чужого
    // порядка — значит решать за него.
    await _place(
      target: _booksOf(sections, destination),
      moved: book,
      before: null,
      categoryId: destination,
    );
  }

  /// Книга легла в участок [into] перед книгой [before]; `null` — в конец.
  Future<void> _dropBook(
    DraggedBook dragged,
    ShelfSection into,
    Book? before,
  ) async {
    await _place(
      target: into.books,
      moved: dragged.book,
      before: before,
      categoryId: into.category?.id,
    );
  }

  /// Записывает расстановку и, если надо, переводит полку в ручной порядок.
  Future<void> _place({
    required List<Book> target,
    required Book moved,
    required Book? before,
    required String? categoryId,
  }) async {
    final List<BookPlacement> placements = placeBefore(
      target: target,
      moved: moved,
      before: before,
      categoryId: categoryId,
    );
    if (placementChangesNothing(target, placements)) {
      return;
    }
    // Книга, ушедшая в другую категорию, оставляет в прежней дыру в
    // нумерации — 0, 1, 3. Заделывать её незачем: порядок задают не сами
    // числа, а то, как они идут, и от дыры он не меняется.
    await widget.services.data.library.placeBooks(placements);
    if (!mounted || _sort == ShelfSort.manual) {
      return;
    }
    // Перетаскивание при включённой сортировке было бы обманом: книга
    // вернулась бы на место в тот же миг. Поэтому первый же перенос
    // переводит полку в ручной порядок — и говорит об этом.
    await _chooseSort(ShelfSort.manual);
    if (mounted) {
      _say('Порядок теперь ручной — книги стоят так, как вы их расставили');
    }
  }

  /// Книги категории в том порядке, в каком их видит читатель.
  List<Book> _booksOf(List<ShelfSection> sections, String? categoryId) {
    for (final ShelfSection section in sections) {
      final String? id = section.category?.id;
      if (id == categoryId) {
        return section.books;
      }
    }
    // Категория есть, но пуста и на полке её сейчас нет — например,
    // «Без категории», из которой всё разложили.
    return const <Book>[];
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
    // Палец, ведущий книгу, слушается здесь, а не в блоках полки.
    // События указателя после нажатия идут по тому пути, который был
    // определён в момент нажатия, поэтому этот слушатель получает их все —
    // и над блоком, и над заголовком категории, и над пустотой под
    // последней категорией, и над панелью приложения. Прежде положение
    // пальца приходило из `DragTarget.onMove` самих блоков, а между
    // блоками таких целей нет вовсе: стоило пальцу замереть в промежутке,
    // и полка продолжала ехать с той скоростью, которая была в последний
    // раз, — то есть не останавливалась там, где читатель её остановил.
    return Listener(
      onPointerMove: (PointerMoveEvent event) {
        if (_autoScroll != null) {
          _dragOver(event.position);
        }
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
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
            tooltip: 'Книги на устройстве',
            onPressed: () => unawaited(_addBooks(null)),
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
      return _EmptyShelf(onOpen: () => unawaited(_addBooks(null)));
    }
    final List<ShelfSection> sections = buildShelf(
      categories: categories,
      books: books,
      sort: _sort,
      progress: progress,
    );
    // `KeyedSubtree` не рисует ничего сам, поэтому его коробка — это
    // коробка списка. Так у полки появляется ключ, не отнимая у неё
    // прежний, по которому её находят тесты.
    return KeyedSubtree(
      key: _shelfViewport,
      child: _shelfList(
        sections: sections,
        categories: categories,
        progress: progress,
      ),
    );
  }

  Widget _shelfList({
    required List<ShelfSection> sections,
    required List<BookCategory> categories,
    required Map<String, double> progress,
  }) {
    return ListView.builder(
      key: const Key('library-shelf'),
      controller: _shelf,
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: sections.length,
      itemBuilder: (BuildContext context, int index) {
        final ShelfSection section = sections[index];
        final BookCategory? category = section.category;
        return CategoryShelf(
          section: section,
          covers: widget.services.covers,
          progress: progress,
          // Импорт больше не идёт на этом экране: «+» открывает экран
          // книг устройства, и ждать здесь нечего.
          busy: false,
          onOpen: (Book book) => unawaited(_openBook(book)),
          onMenu: (Book book) =>
              unawaited(_showBookMenu(book, categories, sections)),
          onAdd: () => unawaited(_addBooks(category?.id)),
          onDropBook: (DraggedBook dragged, ShelfSection into, Book? before) =>
              unawaited(_dropBook(dragged, into, before)),
          onDragStarted: _dragStarted,
          onDragEnded: _dragEnded,
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

  Future<void> _showBookMenu(
    Book book,
    List<BookCategory> categories,
    List<ShelfSection> sections,
  ) async {
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
        await _moveBook(book, categories, sections);
      case BookAction.remove:
        await _removeBook(book);
    }
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onOpen});

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
              onPressed: onOpen,
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Найти книги на устройстве'),
            ),
            const SizedBox(height: 16),
            Text(
              'Приложение покажет все PDF, которые лежат на устройстве, — '
              'с обложками и поиском. Можно и выбрать файлы вручную.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
