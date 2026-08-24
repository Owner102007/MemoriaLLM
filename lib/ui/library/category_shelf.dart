import 'package:flutter/material.dart';

import '../../application/library/cover_service.dart';
import '../../domain/library/book.dart';
import '../../domain/library/category_style.dart';
import '../../domain/library/shelf.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';
import 'book_card.dart';
import 'book_drag.dart';
import 'shelf_pattern.dart';

/// Один участок полки: категория со своим узором и своими книгами.
///
/// Устройство участка задано постановкой владельца (24.08.2026): сетка из
/// блоков, один блок — одна книга, кнопка «+» стоит последним блоком, а
/// сама категория растёт вниз по мере того, как книг становится больше.
/// Три блока в строке — на телефоне; на широком окне ПК блок держит
/// размер, а в строку их встаёт больше (см. [shelfColumnsFor]).
///
/// Книги переставляются руками: блок можно взять и положить между любыми
/// двумя книгами — своей категории или чужой.
class CategoryShelf extends StatelessWidget {
  /// Создаёт участок.
  const CategoryShelf({
    required this.section,
    required this.covers,
    required this.progress,
    required this.onOpen,
    required this.onMenu,
    required this.onAdd,
    required this.busy,
    required this.onDropBook,
    this.onRename,
    this.onDelete,
    this.onDragStarted,
    this.onDragEnded,
    this.onDragOver,
    super.key,
  });

  /// Категория и её книги в выбранном порядке.
  final ShelfSection section;

  /// Служба обложек.
  final CoverService covers;

  /// Доли прочитанного по книгам.
  final Map<String, double> progress;

  /// Открыть книгу.
  final void Function(Book book) onOpen;

  /// Показать меню книги.
  final void Function(Book book) onMenu;

  /// Добавить книги в эту категорию.
  final VoidCallback onAdd;

  /// Идёт ли импорт прямо сейчас.
  final bool busy;

  /// Книгу положили в этот участок перед книгой [before]; `null` —
  /// в конец.
  final void Function(DraggedBook dragged, ShelfSection into, Book? before)
  onDropBook;

  /// Переименовать категорию. `null` у раздела «Без категории».
  final VoidCallback? onRename;

  /// Убрать категорию. `null` у раздела «Без категории».
  final VoidCallback? onDelete;

  /// Книгу подняли.
  final VoidCallback? onDragStarted;

  /// Книгу отпустили.
  final VoidCallback? onDragEnded;

  /// Книгу ведут над полкой: нужно для прокрутки у краёв экрана.
  final void Function(Offset globalPosition)? onDragOver;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = AppPaletteScope.of(context);
    final CategoryStyle style = categoryStyleFor(section.title);
    final Color background = Color(style.backgroundOn(palette));
    final Color ink = Color(style.inkOn(palette));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            section: section,
            onRename: onRename,
            onDelete: onDelete,
            marker: background,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double inset = 10;
              final double inner = constraints.maxWidth - inset * 2;
              final int columns = shelfColumnsFor(inner);
              const double gap = 10;
              final double block = (inner - gap * (columns - 1)) / columns;
              final Size blockSize = Size(block, block * kShelfBlockAspect);
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: ShelfPatternPainter(
                    style: style,
                    background: background,
                    ink: ink,
                    step: patternStepFor(block),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(inset),
                    child: GridView.builder(
                      key: Key('shelf-grid-${section.id}'),
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        childAspectRatio: 1 / kShelfBlockAspect,
                      ),
                      itemCount: section.blockCount,
                      itemBuilder: (BuildContext context, int index) {
                        // Кнопка «+» — последний блок, ровно на месте
                        // книги, которую ещё не поставили. Она же —
                        // единственное место, куда книгу можно положить
                        // «в самый конец».
                        if (index == section.books.length) {
                          return _TailSlot(
                            section: section,
                            onDropBook: onDropBook,
                            onDragOver: onDragOver,
                            child: AddBookCard(
                              sectionId: section.id.isEmpty
                                  ? 'loose'
                                  : section.id,
                              onAdd: onAdd,
                              busy: busy,
                            ),
                          );
                        }
                        final Book book = section.books[index];
                        return _BookSlot(
                          section: section,
                          index: index,
                          onDropBook: onDropBook,
                          onDragOver: onDragOver,
                          child: BookDragHandle(
                            payload: DraggedBook(
                              book: book,
                              fromCategoryId: book.categoryId,
                            ),
                            feedbackSize: blockSize,
                            onDragStarted: onDragStarted,
                            onDragEnded: onDragEnded,
                            child: BookCard(
                              book: book,
                              covers: covers,
                              progress: progress[book.id] ?? 0,
                              onOpen: () => onOpen(book),
                              onMenu: () => onMenu(book),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          if (section.books.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Пока пусто. Нажмите «+», чтобы выбрать книги.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Блок с книгой, принимающий другую книгу слева или справа от себя.
///
/// Сторона выбирается по тому, где палец: в левой половине блока книга
/// встанет перед этой, в правой — после. Иначе положить книгу последней
/// в ряду было бы нечем, а «перед следующей» на переносе строки означает
/// совсем не то, что видит глаз.
class _BookSlot extends StatefulWidget {
  const _BookSlot({
    required this.section,
    required this.index,
    required this.onDropBook,
    required this.onDragOver,
    required this.child,
  });

  final ShelfSection section;
  final int index;
  final void Function(DraggedBook dragged, ShelfSection into, Book? before)
  onDropBook;
  final void Function(Offset globalPosition)? onDragOver;
  final Widget child;

  @override
  State<_BookSlot> createState() => _BookSlotState();
}

class _BookSlotState extends State<_BookSlot> {
  bool _hovered = false;
  bool _after = false;

  Book get _book => widget.section.books[widget.index];

  /// Перед какой книгой встанет груз при текущей стороне.
  Book? get _before {
    final int target = _after ? widget.index + 1 : widget.index;
    final List<Book> books = widget.section.books;
    return target < books.length ? books[target] : null;
  }

  bool _accepts(DraggedBook? dragged) {
    // На саму себя книгу не кладут: это не перестановка, а промах.
    return dragged != null && dragged.book.id != _book.id;
  }

  void _track(DragTargetDetails<DraggedBook> details) {
    widget.onDragOver?.call(details.offset);
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final double x = box.globalToLocal(details.offset).dx;
    final bool after = x > box.size.width / 2;
    if (!_hovered || after != _after) {
      setState(() {
        _hovered = true;
        _after = after;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<DraggedBook>(
      onWillAcceptWithDetails: (DragTargetDetails<DraggedBook> details) =>
          _accepts(details.data),
      onMove: _track,
      onLeave: (DraggedBook? dragged) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      onAcceptWithDetails: (DragTargetDetails<DraggedBook> details) {
        setState(() => _hovered = false);
        widget.onDropBook(details.data, widget.section, _before);
      },
      builder:
          (
            BuildContext context,
            List<DraggedBook?> candidates,
            List<dynamic> rejected,
          ) {
            return Row(
              children: <Widget>[
                DropSlot(active: _hovered && !_after),
                Expanded(child: widget.child),
                DropSlot(active: _hovered && _after),
              ],
            );
          },
    );
  }
}

/// Последний блок: сюда книга кладётся в самый конец категории.
class _TailSlot extends StatefulWidget {
  const _TailSlot({
    required this.section,
    required this.onDropBook,
    required this.onDragOver,
    required this.child,
  });

  final ShelfSection section;
  final void Function(DraggedBook dragged, ShelfSection into, Book? before)
  onDropBook;
  final void Function(Offset globalPosition)? onDragOver;
  final Widget child;

  @override
  State<_TailSlot> createState() => _TailSlotState();
}

class _TailSlotState extends State<_TailSlot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<DraggedBook>(
      onWillAcceptWithDetails: (DragTargetDetails<DraggedBook> details) => true,
      onMove: (DragTargetDetails<DraggedBook> details) {
        widget.onDragOver?.call(details.offset);
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onLeave: (DraggedBook? dragged) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      onAcceptWithDetails: (DragTargetDetails<DraggedBook> details) {
        setState(() => _hovered = false);
        widget.onDropBook(details.data, widget.section, null);
      },
      builder:
          (
            BuildContext context,
            List<DraggedBook?> candidates,
            List<dynamic> rejected,
          ) {
            return Row(
              children: <Widget>[
                DropSlot(active: _hovered),
                Expanded(child: widget.child),
              ],
            );
          },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.section,
    required this.onRename,
    required this.onDelete,
    required this.marker,
  });

  final ShelfSection section;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final Color marker;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        // Тот же цвет, что у подложки: заголовок и участок должны читаться
        // как одно целое даже когда полку прокрутили и подложки не видно.
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: marker, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            section.title,
            key: Key('shelf-title-${section.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ),
        Text(_booksWord(section.books.length), style: theme.textTheme.bodySmall),
        if (onRename != null || onDelete != null)
          PopupMenuButton<String>(
            key: Key('shelf-menu-${section.id}'),
            icon: const Icon(Icons.more_horiz, size: 20),
            tooltip: 'Что сделать с категорией',
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              if (onRename != null)
                const PopupMenuItem<String>(
                  value: 'rename',
                  child: Text('Переименовать'),
                ),
              if (onDelete != null)
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Убрать категорию'),
                ),
            ],
            onSelected: (String value) {
              if (value == 'rename') {
                onRename?.call();
              } else {
                onDelete?.call();
              }
            },
          ),
      ],
    );
  }
}

/// «5 книг» — с правильным окончанием.
///
/// Мелочь, но полка показывает это число у каждой категории, и «1 книг»
/// бросается в глаза сильнее, чем кажется при написании кода.
String _booksWord(int count) {
  final int tail = count % 100;
  if (tail >= 11 && tail <= 14) {
    return '$count книг';
  }
  switch (count % 10) {
    case 1:
      return '$count книга';
    case 2:
    case 3:
    case 4:
      return '$count книги';
    default:
      return '$count книг';
  }
}
