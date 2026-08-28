import 'package:flutter/material.dart';

import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/category_style.dart';
import '../../domain/library/ids.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';

/// Идентификатор новой категории.
String newCategoryId() => newLibraryId();

/// Что читатель попросил сделать с книгой.
enum BookAction {
  /// Открыть.
  open,

  /// Перенести в другую категорию.
  move,

  /// Убрать с полки.
  remove,
}

/// Куда переносим книгу.
class MoveTarget {
  /// Создаёт цель переноса.
  const MoveTarget({this.categoryId, this.isNew = false});

  /// Категория назначения; `null` — «Без категории».
  final String? categoryId;

  /// Читатель выбрал «Новая категория…»: сначала её надо завести.
  final bool isNew;
}

/// Меню книги.
Future<BookAction?> askBookAction(BuildContext context, Book book) {
  return showModalBottomSheet<BookAction>(
    context: context,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            title: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_describeBook(book)),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('book-action-open'),
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Открыть'),
            onTap: () => Navigator.of(context).pop(BookAction.open),
          ),
          ListTile(
            key: const Key('book-action-move'),
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Перенести в категорию…'),
            onTap: () => Navigator.of(context).pop(BookAction.move),
          ),
          ListTile(
            key: const Key('book-action-remove'),
            leading: const Icon(Icons.close),
            title: const Text('Убрать с полки'),
            subtitle: const Text('Файл на диске останется на месте'),
            onTap: () => Navigator.of(context).pop(BookAction.remove),
          ),
        ],
      ),
    ),
  );
}

String _describeBook(Book book) {
  final List<String> parts = <String>[
    if (book.pageCount != null) 'страниц: ${book.pageCount}',
    if (book.hasTextLayer == false) 'скан без текстового слоя',
  ];
  return parts.isEmpty ? 'книга на полке' : parts.join(' · ');
}

/// Выбор категории, куда переносим книгу.
Future<MoveTarget?> askWhereToMove(
  BuildContext context, {
  required List<BookCategory> categories,
  required String? current,
}) {
  final AppPalette palette = AppPaletteScope.of(context);
  final List<BookCategory> ordered = <BookCategory>[...categories]
    ..sort(compareCategories);
  return showDialog<MoveTarget>(
    context: context,
    builder: (BuildContext context) => SimpleDialog(
      title: const Text('Перенести в категорию'),
      children: <Widget>[
        _MoveOption(
          key: const Key('move-to-loose'),
          title: kUncategorizedTitle,
          colour: Color(
            categoryStyleFor(kUncategorizedTitle).weightOn(palette),
          ),
          selected: current == null,
          onTap: () => Navigator.of(context).pop(const MoveTarget()),
        ),
        for (final BookCategory category in ordered)
          _MoveOption(
            key: Key('move-to-${category.id}'),
            title: category.title,
            colour: Color(
              categoryStyleFor(category.title).backgroundOn(palette),
            ),
            selected: current == category.id,
            onTap: () =>
                Navigator.of(context).pop(MoveTarget(categoryId: category.id)),
          ),
        const Divider(height: 1),
        SimpleDialogOption(
          key: const Key('move-to-new'),
          onPressed: () =>
              Navigator.of(context).pop(const MoveTarget(isNew: true)),
          child: const Row(
            children: <Widget>[
              Icon(Icons.create_new_folder_outlined, size: 20),
              SizedBox(width: 12),
              Text('Новая категория…'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MoveOption extends StatelessWidget {
  const _MoveOption({
    required this.title,
    required this.colour,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: selected ? null : onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (selected) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }
}

/// Спрашивает название категории.
///
/// Возвращает `null`, если читатель передумал. Пустое название до
/// сохранения не доходит: [normalizeCategoryTitle] превратит его в
/// «Новая категория», а безымянного прямоугольника на полке не будет.
Future<String?> askCategoryName(BuildContext context, {String? initial}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _CategoryNameDialog(initial: initial),
  );
}

/// Диалог с полем названия.
///
/// Отдельный виджет с состоянием, а не поле в замыкании: контроллер
/// текста обязан жить ровно столько, сколько живёт поле. Прежний вариант
/// освобождал его в `whenComplete`, то есть **до** того, как диалог
/// доигрывал уход с экрана, — и поле оставалось с мёртвым контроллером.
/// Разбиралось это по падению не самого диалога, а следующей перерисовки
/// полки: сломанный `_FocusInheritedScope` роняет всё дерево целиком.
class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({this.initial});

  final String? initial;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.initial == null;
    return AlertDialog(
      title: Text(isNew ? 'Новая категория' : 'Название категории'),
      content: TextField(
        key: const Key('category-name-field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Название',
          // Название — это ещё и семя узора, и знать об этом полезно:
          // так понятнее, почему полка вдруг перекрасилась.
          helperText: 'Узор и цвет полки выбираются по названию',
        ),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('category-name-ok'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(isNew ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }
}

/// Подтверждение удаления категории.
Future<bool> confirmCategoryRemoval(
  BuildContext context,
  BookCategory category,
) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('Убрать «${category.title}»?'),
      content: const Text(
        'Книги останутся на полке — они вернутся в «Без категории». '
        'С диска ничего не удаляется.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('category-remove-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Убрать'),
        ),
      ],
    ),
  );
  return answer ?? false;
}
