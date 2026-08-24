import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/library/category_style.dart';

/// Узор подложки категории.
///
/// Рисуется **под** обложками и только под ними: заголовок категории и
/// подписи книг остаются на обычном фоне темы. Смысл узора — дать глазу
/// зацепку, по которой участок полки узнаётся до чтения названия, поэтому
/// он намеренно бледный: контраст узора к подложке закреплён тестом и
/// держится в узком коридоре.
class ShelfPatternPainter extends CustomPainter {
  /// Создаёт художника.
  const ShelfPatternPainter({
    required this.style,
    required this.background,
    required this.ink,
    required this.step,
  });

  /// Вид категории: узор и сдвиг рисунка.
  final CategoryStyle style;

  /// Цвет подложки.
  final Color background;

  /// Цвет самого узора.
  final Color ink;

  /// Шаг рисунка в точках. Зависит от размера блока, а не от экрана:
  /// полка обязана выглядеть одной и той же полкой на телефоне и на ПК.
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = background);
    if (size.width <= 0 || size.height <= 0 || step <= 0) {
      return;
    }
    canvas.save();
    canvas.clipRect(area);
    final double shift = style.phase * step;
    final Paint stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, step / 14);
    final Paint fill = Paint()..color = ink;

    switch (style.pattern) {
      case ShelfPattern.planks:
        _planks(canvas, size, shift, stroke);
      case ShelfPattern.diagonal:
        _diagonal(canvas, size, shift, stroke);
      case ShelfPattern.checker:
        _checker(canvas, size, shift, fill);
      case ShelfPattern.dots:
        _dots(canvas, size, shift, fill);
      case ShelfPattern.herringbone:
        _herringbone(canvas, size, shift, stroke);
      case ShelfPattern.weave:
        _weave(canvas, size, shift, stroke);
    }
    canvas.restore();
  }

  void _planks(Canvas canvas, Size size, double shift, Paint paint) {
    for (double y = shift - step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _diagonal(Canvas canvas, Size size, double shift, Paint paint) {
    final double span = size.width + size.height;
    for (double x = shift - span; x < span; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  void _checker(Canvas canvas, Size size, double shift, Paint paint) {
    final double cell = step;
    int row = 0;
    for (double y = shift - cell; y < size.height; y += cell) {
      int col = 0;
      for (double x = shift - cell; x < size.width; x += cell) {
        if ((row + col).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
        col++;
      }
      row++;
    }
  }

  void _dots(Canvas canvas, Size size, double shift, Paint paint) {
    final double radius = math.max(1.0, step / 7);
    int row = 0;
    for (double y = shift; y < size.height + step; y += step) {
      final double offset = row.isEven ? 0 : step / 2;
      for (double x = shift + offset; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
      row++;
    }
  }

  void _herringbone(Canvas canvas, Size size, double shift, Paint paint) {
    final double cell = step;
    int row = 0;
    for (double y = shift - cell; y < size.height + cell; y += cell) {
      final bool up = row.isEven;
      for (double x = shift - cell; x < size.width + cell; x += cell) {
        canvas.drawLine(
          Offset(x, up ? y + cell : y),
          Offset(x + cell, up ? y : y + cell),
          paint,
        );
      }
      row++;
    }
  }

  void _weave(Canvas canvas, Size size, double shift, Paint paint) {
    for (double y = shift - step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = shift - step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(ShelfPatternPainter old) {
    return old.style != style ||
        old.background != background ||
        old.ink != ink ||
        old.step != step;
  }
}
