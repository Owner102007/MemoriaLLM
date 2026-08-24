import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/library/cover_service.dart';
import '../../domain/library/book.dart';
import '../../domain/library/shelf.dart';
import '../../domain/reading/navigation.dart';

/// Один блок полки: книга.
///
/// Блок — это обложка и подпись под ней. Всё, что о книге нужно знать не
/// читая, нарисовано на самой обложке: толщина корешка слева, полоска
/// прочитанного снизу. Подпись под обложкой отвечает на вопрос «какая это
/// книга», а не «что с ней происходит».
class BookCard extends StatelessWidget {
  /// Создаёт блок.
  const BookCard({
    required this.book,
    required this.covers,
    required this.progress,
    required this.onOpen,
    required this.onMenu,
    super.key,
  });

  /// Книга.
  final Book book;

  /// Служба обложек.
  final CoverService covers;

  /// Доля прочитанного, от 0 до 1.
  final double progress;

  /// Открыть книгу.
  final VoidCallback onOpen;

  /// Показать меню книги: перенести, убрать с полки.
  ///
  /// Открывается кнопкой «…» в углу обложки и правой кнопкой мыши.
  /// Долгое нажатие меню не открывает — оно поднимает книгу.
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      label: book.title,
      child: InkWell(
        key: Key('library-book-${book.id}'),
        onTap: onOpen,
        // Долгое нажатие целиком отдано перетаскиванию (решение
        // владельца, 24.08.2026): меню живёт на кнопке «…» в углу
        // обложки — она видна всегда, и угадывать длительность
        // удержания читателю не приходится. Правая кнопка мыши меню
        // по-прежнему открывает: на ПК это привычно и перетаскиванию
        // не мешает.
        onSecondaryTap: onMenu,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _CoverFrame(
                book: book,
                covers: covers,
                progress: progress,
                onMenu: onMenu,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFrame extends StatelessWidget {
  const _CoverFrame({
    required this.book,
    required this.covers,
    required this.progress,
    required this.onMenu,
  });

  final Book book;
  final CoverService covers;
  final double progress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: theme.colorScheme.surface),
          FutureBuilder<String?>(
            future: covers.coverFor(book),
            builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
              final String? path = snapshot.data;
              if (path == null) {
                // Пока обложка считается — и навсегда, если книгу не
                // удалось открыть, — на месте картинки стоит название.
                // Пустая заливка цветом темы в роли «ещё не готово» —
                // ровно та ловушка, на которой проект уже потерял
                // итерацию проверки в S4.3.
                return _CoverPlaceholder(
                  book: book,
                  waiting: snapshot.connectionState == ConnectionState.waiting,
                );
              }
              return Image.file(
                File(path),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        _CoverPlaceholder(book: book, waiting: false),
              );
            },
          ),
          _Spine(thickness: spineThickness(book)),
          if (progress > 0)
            Align(
              alignment: Alignment.bottomCenter,
              child: _ProgressBar(progress: progress),
            ),
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              key: Key('library-menu-${book.id}'),
              icon: const Icon(Icons.more_vert, size: 18),
              tooltip: 'Что сделать с книгой',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.72,
                ),
                minimumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
              ),
              onPressed: onMenu,
            ),
          ),
        ],
      ),
    );
  }
}

/// Обложка, которой ещё нет: название на подложке.
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.book, required this.waiting});

  final Book book;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      alignment: Alignment.topLeft,
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              book.title,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.25),
            ),
          ),
          // Полоска-намёк, что обложка ещё считается. Намеренно не
          // крутящийся индикатор: бесконечная анимация на полке из
          // тридцати карточек не даёт кадру успокоиться никогда — ни
          // на устройстве, ни в widget-тесте.
          if (waiting)
            Container(height: 2, width: 28, color: theme.colorScheme.secondary),
        ],
      ),
    );
  }
}

/// Корешок книги: чем толще, тем толще том.
class _Spine extends StatelessWidget {
  const _Spine({required this.thickness});

  final double thickness;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 3 + 7 * thickness.clamp(0.0, 1.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              theme.colorScheme.primary.withValues(alpha: 0.85),
              theme.colorScheme.primary.withValues(alpha: 0.35),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоска прочитанного вдоль нижнего края обложки.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: 'Прочитано ${progressPercent(progress)}%',
      child: Container(
        height: 4,
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: ColoredBox(color: theme.colorScheme.secondary),
        ),
      ),
    );
  }
}

/// Последний блок категории: кнопка «добавить книги сюда».
///
/// Стоит именно в конце и занимает ровно одно место — как книга, которую
/// ещё не поставили. Так у категории всегда есть очевидное место, куда
/// класть новое, и не нужно искать кнопку в шапке.
class AddBookCard extends StatelessWidget {
  /// Создаёт блок.
  const AddBookCard({
    required this.sectionId,
    required this.onAdd,
    required this.busy,
    super.key,
  });

  /// Категория, в которую добавляем. Нужен ключу — и только ему.
  final String sectionId;

  /// Открыть выбор файлов.
  final VoidCallback onAdd;

  /// Идёт ли импорт прямо сейчас.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: InkWell(
            key: Key('library-add-$sectionId'),
            onTap: busy ? null : onAdd,
            borderRadius: BorderRadius.circular(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.dividerColor, width: 1.5),
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.add,
                        size: 28,
                        color: theme.colorScheme.secondary,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: Text(
            'Добавить книги',
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
