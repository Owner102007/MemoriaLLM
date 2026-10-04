import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/library/cover_service.dart';
import '../../domain/library/book.dart';
import '../../domain/library/shelf_title_search.dart';

/// Ширина поля поиска в шапке полки на широком окне — и списка
/// найденного под ним.
const double kShelfSearchWidth = 420;

/// Насколько плотна подложка под совпавшим куском названия.
///
/// Буквы на ней остаются основного цвета текста; при этой плотности он
/// держит 4,5:1 на всех темах — проверяется автотестом.
const double kShelfMarkOpacity = 0.35;

/// Место под слово «Полка» в шапке широкого окна.
///
/// Ширина задана числом, а не текстом: по ней список найденного встаёт
/// ровно под полем, и мерить для этого шапку не приходится.
const double kShelfTitleWidth = 96;

/// Поле поиска по названию в шапке полки (SNO-F-LIB-01).
///
/// На телефоне оно встаёт на место заголовка, когда нажали значок
/// поиска; на широком окне стоит в шапке всегда. `Esc` в поле закрывает
/// поиск: узел стоит вокруг поля, и разбирается ровно одна клавиша — та,
/// которой поле ввода всё равно не пользуется.
class ShelfSearchField extends StatelessWidget {
  /// Создаёт поле.
  const ShelfSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    this.framed = false,
    this.showClose = true,
    super.key,
  });

  /// Набранное.
  final TextEditingController controller;

  /// Узел поля: указатель ввода в него ставит полка.
  final FocusNode focusNode;

  /// Набранное изменилось.
  final ValueChanged<String> onChanged;

  /// Закрыть поиск: `✕` и `Esc`.
  final VoidCallback onClose;

  /// В рамке ли поле: на широком окне оно стоит в шапке всегда и должно
  /// быть видно пустым.
  final bool framed;

  /// Показывать ли `✕`.
  final bool showClose;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    onClose();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final Widget? close = showClose
        ? IconButton(
            key: const Key('shelf-search-close'),
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть поиск',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          )
        : null;
    return Focus(
      onKeyEvent: _onKey,
      child: TextField(
        key: const Key('shelf-search-field'),
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        // На широком окне `Enter` указатель ввода из поля не уводит:
        // список уже на экране, а без указателя `Esc` перестал бы
        // закрывать поиск. Экранная клавиатура — другое дело: её кнопка
        // «Найти» клавиатуру прячет, на телефоне и на планшете, — так
        // список виден целиком.
        onEditingComplete: framed
            ? () {
                if (MediaQuery.viewInsetsOf(context).bottom > 0) {
                  focusNode.unfocus();
                }
              }
            : null,
        decoration: InputDecoration(
          hintText: 'Название книги',
          isDense: true,
          border: framed ? const OutlineInputBorder() : InputBorder.none,
          prefixIcon: framed ? const Icon(Icons.search, size: 20) : null,
          suffixIcon: close,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Найденное по названию: список книг с подсветкой совпавшего
/// (SNO-F-LIB-01).
///
/// Под названием стоит категория книги — то место, где она стоит на
/// полке. Нажатие открывает книгу; ни меню, ни переноса здесь нет.
class ShelfSearchResults extends StatelessWidget {
  /// Создаёт список.
  const ShelfSearchResults({
    required this.hits,
    required this.categories,
    required this.covers,
    required this.onOpen,
    this.shrinkWrap = false,
    super.key,
  });

  /// Найденные книги, лучшие первыми.
  final List<ShelfTitleHit> hits;

  /// Название категории по идентификатору книги.
  final Map<String, String> categories;

  /// Служба обложек.
  final CoverService covers;

  /// Открыть книгу.
  final void Function(Book book) onOpen;

  /// По высоте ли найденного список: так он стоит под полем на широком
  /// окне. Иначе занимает всё отведённое место.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (hits.isEmpty) {
      final Widget empty = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Ничего не найдено по названию',
          key: const Key('shelf-search-empty'),
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
      // Под полем строка занимает всю ширину списка: иначе подложка
      // сжалась бы до ширины слов.
      return shrinkWrap
          ? SizedBox(width: double.infinity, child: empty)
          : Center(child: empty);
    }
    // Совпавшее отмечено подложкой и жирностью, а не цветом букв: цвет
    // текста остаётся основным и держит контраст на любой теме.
    final TextStyle mark = TextStyle(
      fontWeight: FontWeight.w700,
      backgroundColor: theme.colorScheme.secondary.withValues(
        alpha: kShelfMarkOpacity,
      ),
    );
    return ListView.builder(
      key: const Key('shelf-search-results'),
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: hits.length,
      itemBuilder: (BuildContext context, int index) {
        final ShelfTitleHit hit = hits[index];
        final Book book = hit.book;
        final String? category = categories[book.id];
        return ListTile(
          key: Key('shelf-search-hit-${book.id}'),
          leading: SizedBox(
            width: 36,
            height: 50,
            child: _ResultCover(book: book, covers: covers),
          ),
          title: Text.rich(
            highlightedTitle(book.title, hit.spans, mark),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: category == null
              ? null
              : Text(category, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onOpen(book),
        );
      },
    );
  }
}

/// Название с отмеченными кусками [spans].
///
/// Куски приходят по порядку и без наложений; кусок за краем названия
/// обрезается по краю, а не роняет список.
TextSpan highlightedTitle(String title, List<TitleSpan> spans, TextStyle mark) {
  final List<InlineSpan> parts = <InlineSpan>[];
  int at = 0;
  for (final TitleSpan span in spans) {
    final int start = _within(span.start, at, title.length);
    final int end = _within(span.end, start, title.length);
    if (start > at) {
      parts.add(TextSpan(text: title.substring(at, start)));
    }
    if (end > start) {
      parts.add(TextSpan(text: title.substring(start, end), style: mark));
    }
    at = end;
  }
  if (at < title.length) {
    parts.add(TextSpan(text: title.substring(at)));
  }
  return TextSpan(children: parts);
}

int _within(int value, int low, int high) {
  if (value < low) {
    return low;
  }
  return value > high ? high : value;
}

/// Обложка в строке найденного: маленькая, без корешка и меток.
class _ResultCover extends StatelessWidget {
  const _ResultCover({required this.book, required this.covers});

  final Book book;
  final CoverService covers;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget blank = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.menu_book_outlined,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: FutureBuilder<String?>(
        future: covers.coverFor(book),
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String? path = snapshot.data;
          if (path == null) {
            return blank;
          }
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) => blank,
          );
        },
      ),
    );
  }
}
