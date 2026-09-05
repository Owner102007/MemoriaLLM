import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/library/cover_service.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/category_style.dart';
import '../../domain/library/cover.dart';
import '../../domain/library/device_files.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';
import 'shelf_pattern.dart';

/// Карточка книги, найденной на устройстве.
///
/// Обложка рисуется **только пока карточка на экране**. Задание ставится
/// в очередь при появлении и снимается при уходе: прокрутка по тысяче
/// файлов иначе поставила бы тысячу рендеров, и обложка книги, на которую
/// читатель смотрит сейчас, ждала бы за девятьюстами чужими.
///
/// До готовности карточка показывает не пустоту, а подложку из имени
/// файла — тем же кодом `category_style.dart`, которым красятся категории
/// полки. Пустая заливка цветом темы в роли «ещё не готово» — ровно та
/// ловушка, на которой проект уже потерял итерацию проверки в S4.3.
class DeviceBookCard extends StatefulWidget {
  /// Создаёт карточку.
  const DeviceBookCard({
    required this.entry,
    required this.covers,
    required this.selected,
    required this.onShelf,
    required this.onTap,
    super.key,
  });

  /// Книга и её копии.
  final DeviceBookEntry entry;

  /// Служба обложек.
  final CoverService covers;

  /// Отмечена ли карточка для добавления.
  final bool selected;

  /// Такая книга уже стоит на полке.
  final bool onShelf;

  /// Нажатие: отметить или снять отметку.
  final VoidCallback onTap;

  @override
  State<DeviceBookCard> createState() => _DeviceBookCardState();
}

class _DeviceBookCardState extends State<DeviceBookCard> {
  late String _key;
  Future<String?>? _cover;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(DeviceBookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Отпечаток мог посчитаться уже после того, как карточка появилась:
    // ключ кэша тогда становится другим, и обложку надо просить заново.
    if (_keyFor(widget.entry) != _key) {
      widget.covers.cancel(_key);
      _request();
    }
  }

  @override
  void dispose() {
    widget.covers.cancel(_key);
    super.dispose();
  }

  void _request() {
    _key = _keyFor(widget.entry);
    _cover = widget.covers.coverForSource(
      key: _key,
      source: FilePathSource(widget.entry.primary.path),
    );
  }

  /// Ключ кэша: по отпечатку, если он есть, иначе по пути.
  ///
  /// Отпечаток даёт общий кэш с полкой — книга, поставленная на полку,
  /// получает уже нарисованную картинку. Пока его нет, ключом служит
  /// путь: другой обложки у этого файла всё равно быть не может.
  static String _keyFor(DeviceBookEntry entry) {
    final String? hash = entry.fingerprint;
    final bool known = hash != null && hash.isNotEmpty;
    return coverKeyForHash(known ? hash : entry.primary.path);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      key: Key('device-card-${widget.entry.primary.path}'),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _CoverOrBackdrop(
                    title: widget.entry.title,
                    cover: _cover,
                  ),
                  if (widget.onShelf)
                    Align(
                      alignment: Alignment.topLeft,
                      child: _Badge(
                        icon: Icons.check,
                        label: 'на полке',
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  if (widget.selected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  if (widget.selected)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          Text(
            _subtitle(widget.entry),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(DeviceBookEntry entry) {
    final String duplicates = entry.duplicatesLabel;
    if (duplicates.isNotEmpty) {
      return duplicates;
    }
    final String folder = entry.primary.folder;
    return folder.isEmpty ? '' : folder;
  }
}

/// Обложка, а пока её нет — подложка с названием.
class _CoverOrBackdrop extends StatelessWidget {
  const _CoverOrBackdrop({required this.title, required this.cover});

  final String title;
  final Future<String?>? cover;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: cover,
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final String? path = snapshot.data;
        if (path == null) {
          return _NameBackdrop(title: title);
        }
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  _NameBackdrop(title: title),
        );
      },
    );
  }
}

/// Подложка из имени файла — тем же кодом, что и узоры категорий.
///
/// Одинаковое имя всегда даёт одинаковый вид, поэтому список файлов не
/// мерцает при прокрутке, а глаз находит нужную книгу по пятну ещё до
/// того, как прочитает подпись.
class _NameBackdrop extends StatelessWidget {
  const _NameBackdrop({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPaletteScope.of(context);
    final CategoryStyle style = categoryStyleFor(title);
    final ThemeData theme = Theme.of(context);
    return CustomPaint(
      painter: ShelfPatternPainter(
        style: style,
        background: Color(style.backgroundOn(palette)),
        ink: Color(style.inkOn(palette)),
        step: 26,
        stroke: style.strokeOn(palette, 26),
        glow: style.acidOn(palette),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        child: Text(
          title,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.25,
            color: Color(palette.text),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
