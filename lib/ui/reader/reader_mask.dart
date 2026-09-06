import 'package:flutter/material.dart';

/// Насколько маска заходит на лист, закрывая его край.
///
/// Страницы в раскладке просмотрщика стоят вплотную, без полей: край
/// читаемой страницы — это одновременно край соседней. Ровная граница
/// сглаживается, и от соседней страницы остаётся волосок света. Пол-точки
/// нахлёста съедают его целиком, а у страницы отнимают ту часть поля,
/// которой всё равно не видно.
const double kReaderMaskOverlap = 0.5;

/// Маска поверх страницы: два уровня темноты вместо второго виджета.
///
/// Решение владельца от 06.09.2026, по проверке S6.1 на ПК. Читательская
/// рамка перестала быть отдельным листом и стала **позицией плюс маской**:
/// матрица просмотрщика приколочена к нашей раскладке, а всё лишнее
/// закрашивается сверху, в координатах экрана.
///
/// Уровней ровно два, и это не украшение:
///
/// * **За пределами листа** — соседние страницы, промежутки, поля
///   просмотрщика — фон **наглухо**. Полупрозрачная тень соседнюю
///   страницу не прячет, и ровно на этом сломалась S6.1: на широком окне
///   ПК рядом с читаемой страницей было видно соседние.
/// * **На самом листе, вне читаемой полосы** — затемнение по настройке
///   `dimOutside`, как с S4.7. Страница не обрезана: она продолжается в
///   темноте, и, отперев замок, читатель видит её целиком.
class ReaderMask extends StatelessWidget {
  /// Создаёт маску.
  const ReaderMask({
    required this.sheet,
    required this.strip,
    required this.dim,
    required this.background,
    super.key,
  });

  /// Весь лист на экране.
  final Rect sheet;

  /// Читаемая часть листа на экране — она и остаётся светлой.
  final Rect strip;

  /// Сила затемнения листа вне полосы: 0 — не гасить вовсе, 1 — чернота.
  final double dim;

  /// Фон, которым закрашивается всё за пределами листа.
  ///
  /// Тот же цвет, что и под страницей, поэтому шва не видно: экран просто
  /// заканчивается там, где заканчивается лист.
  final Color background;

  @override
  Widget build(BuildContext context) {
    // Нажатия принадлежат странице: маска не должна перехватывать ни
    // переход по фрагментам, ни выделение, ни щипок.
    return IgnorePointer(
      child: CustomPaint(
        painter: ReaderMaskPainter(
          sheet: sheet,
          strip: strip,
          dim: dim,
          background: background,
        ),
      ),
    );
  }
}

/// Путь первого уровня: экран без листа.
///
/// Дырка вырезается правилом «чёт-нечет» — два прямоугольника дешевле
/// вычитания путей и не зависят от того, попал ли лист в экран целиком.
Path outsideSheetPath({
  required Rect screen,
  required Rect sheet,
  double overlap = kReaderMaskOverlap,
}) {
  final Path path = Path()..fillType = PathFillType.evenOdd;
  path.addRect(screen);
  final Rect hole = sheet.deflate(overlap).intersect(screen);
  if (hole.width > 0 && hole.height > 0) {
    path.addRect(hole);
  }
  return path;
}

/// Путь второго уровня: лист без читаемой части.
Path dimOutsidePath({required Rect sheet, required Rect fragment}) {
  final Path path = Path()..fillType = PathFillType.evenOdd;
  path.addRect(sheet);
  final Rect hole = fragment.intersect(sheet);
  if (hole.width > 0 && hole.height > 0) {
    path.addRect(hole);
  }
  return path;
}

/// Рисует оба уровня маски.
class ReaderMaskPainter extends CustomPainter {
  /// Создаёт художника.
  const ReaderMaskPainter({
    required this.sheet,
    required this.strip,
    required this.dim,
    required this.background,
  });

  /// Весь лист на экране.
  final Rect sheet;

  /// Читаемая часть листа на экране.
  final Rect strip;

  /// Сила затемнения листа вне полосы.
  final double dim;

  /// Фон за пределами листа.
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screen = Offset.zero & size;
    if (sheet.isEmpty) {
      // Показывать нечего — но и щели быть не должно: пустой лист значит
      // пустой экран, а не окно в чужие страницы.
      canvas.drawRect(screen, Paint()..color = background);
      return;
    }
    canvas.drawPath(
      outsideSheetPath(screen: screen, sheet: sheet),
      Paint()..color = background,
    );
    if (dim <= 0) {
      return;
    }
    // Своего клипа у второго уровня намеренно нет: тень накрывает весь
    // лист, включая те его части, которые сейчас лежат за краем экрана.
    // Стоит читателю уменьшить страницу щипком — они въезжают в кадр уже
    // затемнёнными.
    canvas.drawPath(
      dimOutsidePath(sheet: sheet, fragment: strip),
      Paint()..color = Color.fromRGBO(0, 0, 0, dim.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(ReaderMaskPainter oldDelegate) {
    return oldDelegate.sheet != sheet ||
        oldDelegate.strip != strip ||
        oldDelegate.dim != dim ||
        oldDelegate.background != background;
  }
}
