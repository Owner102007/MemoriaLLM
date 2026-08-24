import 'package:flutter/material.dart';

import '../../application/library/cover_service.dart';
import '../../domain/library/book.dart';
import '../../domain/library/category_style.dart';
import '../../domain/library/shelf.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';
import 'book_card.dart';
import 'shelf_pattern.dart';

/// Один участок полки: категория со своим узором и своими книгами.
///
/// Устройство участка задано постановкой владельца (24.08.2026): сетка из
/// блоков, один блок — одна книга, кнопка «+» стоит последним блоком, а
/// сама категория растёт вниз по мере того, как книг становится больше.
/// Три блока в строке — на телефоне; на широком окне ПК блок держит
/// размер, а в строку их встаёт больше (см. [shelfColumnsFor]).
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
    this.onRename,
    this.onDelete,
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

  /// Переименовать категорию. `null` у раздела «Без категории».
  final VoidCallback? onRename;

  /// Убрать категорию. `null` у раздела «Без категории».
  final VoidCallback? onDelete;

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
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: gap,
                            childAspectRatio: 1 / kShelfBlockAspect,
                          ),
                      itemCount: section.blockCount,
                      itemBuilder: (BuildContext context, int index) {
                        // Кнопка «+» — последний блок, ровно на месте
                        // книги, которую ещё не поставили.
                        if (index == section.books.length) {
                          return AddBookCard(
                            sectionId: section.id.isEmpty
                                ? 'loose'
                                : section.id,
                            onAdd: onAdd,
                            busy: busy,
                          );
                        }
                        final Book book = section.books[index];
                        return BookCard(
                          book: book,
                          covers: covers,
                          progress: progress[book.id] ?? 0,
                          onOpen: () => onOpen(book),
                          onMenu: () => onMenu(book),
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
        Text(
          _booksWord(section.books.length),
          style: theme.textTheme.bodySmall,
        ),
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
