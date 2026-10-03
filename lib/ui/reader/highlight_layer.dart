import 'package:flutter/material.dart';

/// Подсветка найденного поиском.
///
/// Долг, честно отложенный в S3: список результатов с фрагментами был
/// сделан тогда же, а подсветить совпадение на странице было нечем —
/// координаты символов появились только в S4, а перевод «место в тексте →
/// прямоугольник на странице» написан в этой сессии вместе с выделением.
///
/// Рисуется поверх страницы и **не** трогает файл: это тот же приём, что
/// и у светофильтров. Цвет — акцент темы вполсилы: подсветка обязана
/// оставаться читаемой поверх текста, а не закрашивать его.
///
/// **Подсветка — картинка, а не кнопка** (BUG-43, ALG-UI-17): нажатий
/// слой не ловит нигде, ни мимо найденного, ни по нему самому. Он лежит
/// во весь лист, и прежде, пока подсветка была на странице, забирал
/// каждое нажатие: панели не показывались, края не листали.
class HighlightLayer extends StatelessWidget {
  /// Создаёт слой подсветки.
  const HighlightLayer({required this.rects, required this.color, super.key});

  /// Прямоугольники в координатах экрана.
  final List<Rect> rects;

  /// Цвет подсветки.
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (rects.isEmpty) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      key: const Key('reader-highlight'),
      painter: _HighlightPainter(rects: rects, color: color),
      size: Size.infinite,
    );
  }
}

class _HighlightPainter extends CustomPainter {
  const _HighlightPainter({required this.rects, required this.color});

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (final Rect rect in rects) {
      if (rect.isEmpty) {
        continue;
      }
      // Скруглением подсветка отличается от выделения, которое рисует
      // просмотрщик прямыми углами: два разных смысла не должны выглядеть
      // одинаково.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)),
        paint,
      );
    }
  }

  /// BUG-43: `CustomPaint` с отрисовщиком считает попаданием любую
  /// точку своей площади, пока отрисовщик не скажет обратного
  /// (`RenderCustomPaint.hitTestSelf`). Слой подсветки лежит во весь лист
  /// — отвечаем «нет» всегда.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) {
    return oldDelegate.color != color || !_sameRects(oldDelegate.rects, rects);
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
