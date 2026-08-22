import 'package:flutter/material.dart';

/// Тень поверх той части страницы, которую сейчас не читают.
///
/// В режимах половины и трети страница **не обрезается**: она видна
/// целиком, а всё за пределами читаемой полосы уходит в тень. Прежде
/// соседние полосы просто исчезали, и вместе с ними исчезало ощущение
/// страницы — сколько на ней осталось, где проходит граница, что будет
/// на следующем экране. Тень возвращает это ощущение, ничего не отнимая
/// у кегля: читаемая полоса по-прежнему занимает столько экрана,
/// сколько может.
class DimOutside extends StatelessWidget {
  /// Создаёт тень.
  const DimOutside({
    required this.sheet,
    required this.fragment,
    required this.dim,
    super.key,
  });

  /// Весь лист на экране.
  final Rect sheet;

  /// Читаемая часть листа на экране — она и остаётся светлой.
  final Rect fragment;

  /// Сила затемнения: 0 — не гасить вовсе, 1 — чернота.
  final double dim;

  @override
  Widget build(BuildContext context) {
    if (dim <= 0 || sheet.isEmpty) {
      return const SizedBox.shrink();
    }
    // Нажатия принадлежат странице: тень не должна перехватывать ни
    // переход по фрагментам, ни щипок.
    //
    // Своего клипа здесь намеренно нет. Тень накрывает **весь лист**, в
    // том числе те его части, которые сейчас лежат за краем экрана:
    // стоит читателю уменьшить страницу щипком, как они въезжают в кадр
    // уже затемнёнными. Клип по краю экрана делает просмотрщик, и делает
    // его после преобразования — там ему и место.
    return IgnorePointer(
      child: CustomPaint(
        painter: DimOutsidePainter(sheet: sheet, fragment: fragment, dim: dim),
      ),
    );
  }
}

/// Путь тени: лист без читаемой части.
///
/// Дырка вырезается правилом «чёт-нечет», а не вычитанием путей: два
/// вложенных прямоугольника — самый дешёвый способ получить рамку, и он
/// не зависит от того, попал ли фрагмент внутрь листа целиком.
Path dimOutsidePath({required Rect sheet, required Rect fragment}) {
  final Path path = Path()..fillType = PathFillType.evenOdd;
  path.addRect(sheet);
  final Rect hole = fragment.intersect(sheet);
  if (hole.width > 0 && hole.height > 0) {
    path.addRect(hole);
  }
  return path;
}

/// Рисует тень вокруг читаемой части листа.
class DimOutsidePainter extends CustomPainter {
  /// Создаёт художника.
  const DimOutsidePainter({
    required this.sheet,
    required this.fragment,
    required this.dim,
  });

  /// Весь лист на экране.
  final Rect sheet;

  /// Читаемая часть листа на экране.
  final Rect fragment;

  /// Сила затемнения.
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dimOutsidePath(sheet: sheet, fragment: fragment),
      Paint()..color = Color.fromRGBO(0, 0, 0, dim.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(DimOutsidePainter oldDelegate) {
    return oldDelegate.sheet != sheet ||
        oldDelegate.fragment != fragment ||
        oldDelegate.dim != dim;
  }
}
