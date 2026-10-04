import 'package:flutter/material.dart';

import '../../domain/library/shelf_caption.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';

/// Подпись под блоком полки на собственной подложке (BUG-14).
///
/// Одна и та же у книги и у блока «+»: обе подписи лежат внутри участка
/// категории, и под обеими прежде проходили линии узора.
class ShelfCaption extends StatelessWidget {
  /// Создаёт подпись.
  const ShelfCaption({required this.text, super.key});

  /// Что написано: название книги или «Добавить книги».
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = AppPaletteScope.of(context);
    final ({int background, int text}) colors = shelfCaptionColors(palette);
    return Padding(
      padding: const EdgeInsets.only(top: kShelfCaptionGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(colors.background),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kShelfCaptionPadX,
            vertical: kShelfCaptionPadY,
          ),
          child: SizedBox(
            height: kShelfCaptionTextHeight,
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: kShelfCaptionFontSize,
                color: Color(colors.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
