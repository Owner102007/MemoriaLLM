import 'package:flutter/material.dart';

import '../../domain/library/scan_mark.dart';
import '../../domain/theme/app_palette.dart';
import '../theme/palette_scope.dart';

/// Метка «скан» на обложке (F-DEV-13).
///
/// У книги без текстового слоя не работают выделение, поиск и функции —
/// и узнавать об этом в меню книги поздно: читатель уже открыл её и
/// пытается выделить слово. Метка стоит на самой обложке, на полке и в
/// «Устройстве» одинаково.
///
/// Подложка у метки своя и непрозрачная: обложка под ней бывает любой.
class ScanTag extends StatelessWidget {
  /// Создаёт метку.
  const ScanTag({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPaletteScope.of(context);
    final ({int background, int text}) colors = scanMarkColors(palette);
    return Tooltip(
      message: 'Скан: $kScanExplanation',
      child: Semantics(
        label: kScanLong,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(colors.background),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Color(palette.divider)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                kScanMark,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: Color(colors.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
