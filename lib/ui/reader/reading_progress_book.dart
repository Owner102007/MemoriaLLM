import 'package:flutter/material.dart';

import '../../domain/reading/progress_slot.dart';

/// Указатель места в книге — сама книга, вид с торца.
///
/// Две стопки страниц по сторонам корешка: слева прочитанное, справа
/// оставшееся. По мере чтения левая толстеет, правая тает — ровно как у
/// бумажной книги в руках. Общая толщина зависит от объёма файла, поэтому
/// брошюра и том в тысячу страниц выглядят по-разному. Это то самое
/// ощущение толщины, которого электронной книге не хватает больше всего.
///
/// Указатель живёт в поле вокруг страницы и **не исчезает вместе с
/// панелями**: без него, спрятав интерфейс, читатель теряет всякое
/// представление о том, где он.
class ReadingProgressBook extends StatelessWidget {
  /// Создаёт указатель.
  const ReadingProgressBook({
    required this.slot,
    required this.page,
    required this.pageCount,
    super.key,
  });

  /// Наибольшая ширина рисунка книги.
  static const double maxBookWidth = 64;

  /// Наименьшая ширина рисунка книги.
  ///
  /// Уже этого рисунок не читается, но и рисовать его всё равно надо:
  /// цифры отвечают на вопрос «сколько страниц», а толщина — на вопрос
  /// «сколько осталось», и второй ответ важнее.
  static const double minBookWidth = 28;

  /// Высота рисунка книги.
  static const double bookHeight = 22;

  /// Место, отданное указателю.
  final ProgressSlot slot;

  /// Текущая страница, начиная с единицы.
  final int page;

  /// Всего страниц.
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    if (!slot.isVisible || pageCount < 1) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final Color ink = theme.colorScheme.onSurface;
    // Опорный акцент отвечает в палитре только за заливку: к тёмному фону
    // он даёт 2.86:1, и стопка прочитанного на нём была бы еле видна.
    // Поэтому прочитанное рисуется акцентным цветом текста.
    final Color read = theme.colorScheme.secondary;
    final double width = _bookWidth(slot.width);

    return Positioned(
      left: slot.left,
      top: slot.top,
      width: slot.width,
      height: slot.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Поверх страницы указателю нужна подложка, иначе он
            // потеряется в тексте; в свободном поле она лишняя.
            color: slot.overlaps
                ? theme.colorScheme.surface.withValues(alpha: 0.72)
                : Colors.transparent,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: width,
                    height: bookHeight,
                    child: CustomPaint(
                      key: const Key('reader-progress-book'),
                      painter: OpenBookPainter(
                        share: (page / pageCount).clamp(0.0, 1.0),
                        pageCount: pageCount,
                        read: read,
                        rest: ink.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$page / $pageCount',
                    key: const Key('reader-progress-label'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.75),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ширина рисунка в поле шириной [slotWidth].
  ///
  /// Отдельная функция потому, что это единственное место, где рисунок
  /// может исчезнуть совсем: узкое поле однажды уже съело его целиком, и
  /// читатель видел одни цифры.
  static double _bookWidth(double slotWidth) {
    final double free = slotWidth - 8;
    if (free >= maxBookWidth) {
      return maxBookWidth;
    }
    return free < minBookWidth ? minBookWidth : free;
  }
}

/// Раскрытая книга с торца: две стопки страниц по сторонам корешка.
///
/// Открыт для тестов: геометрию стопок проверяет обычный тест на числах,
/// а не глаз на скриншоте.
class OpenBookPainter extends CustomPainter {
  /// Создаёт рисовальщика.
  const OpenBookPainter({
    required this.share,
    required this.pageCount,
    required this.read,
    required this.rest,
  });

  /// С какого объёма книга считается толстой.
  static const int fullVolume = 800;

  /// Какая доля книги прочитана.
  final double share;

  /// Объём книги: от него зависит толщина стопки.
  final int pageCount;

  /// Цвет прочитанного.
  final Color read;

  /// Цвет оставшегося.
  final Color rest;

  /// Толщина всей книги при такой высоте рисунка.
  ///
  /// Тонкая брошюра и том в тысячу страниц не должны выглядеть одинаково,
  /// но и брошюра обязана быть видна: отсюда не «доля от объёма», а
  /// «минимум плюс доля».
  static double thicknessFor({required double height, required int pageCount}) {
    final int volume = pageCount < 1 ? 1 : pageCount;
    final double fullness = volume >= fullVolume ? 1 : volume / fullVolume;
    return (height - 3) * (0.45 + 0.45 * fullness);
  }

  /// Высота левой стопки — прочитанного.
  static double readHeight({
    required double height,
    required int pageCount,
    required double share,
  }) {
    return thicknessFor(height: height, pageCount: pageCount) *
        share.clamp(0.0, 1.0);
  }

  /// Высота правой стопки — оставшегося.
  static double restHeight({
    required double height,
    required int pageCount,
    required double share,
  }) {
    return thicknessFor(height: height, pageCount: pageCount) *
        (1 - share.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 8 || size.height <= 6) {
      return;
    }
    final double base = size.height - 1.5;
    final double spine = size.width / 2;
    final double left = readHeight(
      height: size.height,
      pageCount: pageCount,
      share: share,
    );
    final double right = restHeight(
      height: size.height,
      pageCount: pageCount,
      share: share,
    );

    // Обложка: тонкая черта во всю ширину. Без неё в самом начале книги
    // левая половина рисунка пустует, и указатель выглядит сломанным, а не
    // «прочитано нисколько».
    canvas.drawLine(
      Offset(0, base + 1),
      Offset(size.width, base + 1),
      Paint()
        ..color = rest
        ..strokeWidth = 1.2,
    );

    void stack(double from, double to, double height, Color color) {
      if (height < 0.6) {
        return;
      }
      canvas.drawRect(
        Rect.fromLTRB(from, base - height, to, base),
        Paint()..color = color,
      );
    }

    stack(0, spine - 0.6, left, read);
    stack(spine + 0.6, size.width, right, rest);

    // Корешок: без него две стопки выглядят как две отдельные книги.
    final double tallest = left > right ? left : right;
    canvas.drawLine(
      Offset(spine, base),
      Offset(spine, base - tallest - 2),
      Paint()
        ..color = rest
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(OpenBookPainter oldDelegate) =>
      oldDelegate.share != share ||
      oldDelegate.pageCount != pageCount ||
      oldDelegate.read != read ||
      oldDelegate.rest != rest;
}
