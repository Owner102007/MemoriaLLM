import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/map/galaxy.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/category_style.dart';
import '../../domain/map/map_view.dart';
import '../../domain/theme/app_palette.dart';

/// Наибольшая ширина названия книги у точки, в логических пикселях.
const double kGalaxyTitleWidth = 180;

/// Наибольшая ширина названия группы.
const double kGalaxyGroupWidth = 240;

/// Просвет между точкой и её названием.
const double kGalaxyLabelGap = 6;

/// Отступ названия группы от края окна.
const double kGalaxyEdge = 6;

/// Вес названия группы при отборе подписей: группа встаёт раньше любой
/// книги.
const double kGalaxyGroupWeight = 1000;

/// Цвет точки книги из группы [group] на теме [palette] (F-MAP-02).
///
/// Оттенок — тот же, что у категории на полке: он выведен из её
/// названия (`CategoryStyle.starOn`). Книги без категории — вторичным
/// цветом текста.
int starArgbOf(String group, AppPalette palette) {
  if (group == kUncategorizedTitle) {
    return palette.textSecondary;
  }
  return categoryStyleFor(group).starOn(palette);
}

/// Подпись, вставшая на кадр.
class GalaxyLabel {
  /// Создаёт подпись.
  const GalaxyLabel({
    required this.text,
    required this.painter,
    required this.rect,
    required this.group,
  });

  /// Что написано: название группы или книги.
  final String text;

  /// Разложенный текст.
  final TextPainter painter;

  /// Место на экране.
  final Rect rect;

  /// Название группы (`true`) или книги (`false`).
  final bool group;
}

/// Всё, что нужно кадру карты: окно, звёзды, их радиусы и подписи.
class GalaxyScene {
  /// Собирает кадр (ALG-MAP-12).
  ///
  /// [selected] — номер выбранной звезды в [stars]; `null` — выбранной
  /// нет. Подписи раскладываются здесь же: они зависят от окна и
  /// масштаба, а не от полотна.
  factory GalaxyScene({
    required List<GalaxyStar> stars,
    required MapViewport viewport,
    required AppPalette palette,
    required TextStyle groupStyle,
    required TextStyle titleStyle,
    TextScaler textScaler = TextScaler.noScaling,
    int? selected,
  }) {
    final Map<String, int> times = <String, int>{
      for (final GalaxyStar star in stars) star.book.id: star.ms,
    };
    final Map<String, double> shares = timeShares(times);
    final double base = baseStarRadius(
      count: stars.length,
      base: viewport.base,
    );
    final List<double> radii = <double>[
      for (final GalaxyStar star in stars)
        starRadius(
          base: base,
          share: shares[star.book.id] ?? 0,
          scale: viewport.camera.scale,
        ),
    ];
    final List<Color> colours = <Color>[
      for (final GalaxyStar star in stars)
        Color(starArgbOf(star.group, palette)),
    ];
    return GalaxyScene._(
      stars: stars,
      viewport: viewport,
      palette: palette,
      radii: radii,
      colours: colours,
      selected: selected,
      labels: _layoutLabels(
        stars: stars,
        viewport: viewport,
        radii: radii,
        shares: shares,
        groupStyle: groupStyle,
        titleStyle: titleStyle,
        textScaler: textScaler,
        selected: selected,
      ),
    );
  }

  const GalaxyScene._({
    required this.stars,
    required this.viewport,
    required this.palette,
    required this.radii,
    required this.colours,
    required this.labels,
    required this.selected,
  });

  /// Звёзды.
  final List<GalaxyStar> stars;

  /// Окно карты.
  final MapViewport viewport;

  /// Тема.
  final AppPalette palette;

  /// Радиусы звёзд на экране, по порядку [stars].
  final List<double> radii;

  /// Цвета звёзд, по порядку [stars].
  final List<Color> colours;

  /// Подписи кадра: не больше [kMaxLabels], без пересечений.
  final List<GalaxyLabel> labels;

  /// Номер выбранной звезды; `null` — выбранной нет.
  final int? selected;

  /// Место звезды номер [index] на экране.
  Offset placeOf(int index) {
    return Offset(
      viewport.screenX(stars[index].x),
      viewport.screenY(stars[index].y),
    );
  }

  static TextPainter _painterOf(
    String text,
    TextStyle style,
    TextScaler textScaler,
    double maxWidth,
  ) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  /// Раскладывает подписи: названия групп всегда, названия книг — когда
  /// между точками есть место ([titlesShown]).
  static List<GalaxyLabel> _layoutLabels({
    required List<GalaxyStar> stars,
    required MapViewport viewport,
    required List<double> radii,
    required Map<String, double> shares,
    required TextStyle groupStyle,
    required TextStyle titleStyle,
    required TextScaler textScaler,
    required int? selected,
  }) {
    final double width = viewport.width;
    final double height = viewport.height;
    final List<LabelBox> wanted = <LabelBox>[];
    final List<String> texts = <String>[];
    final List<TextPainter> painters = <TextPainter>[];
    final List<bool> kinds = <bool>[];

    void want(String text, TextPainter painter, Offset at, double weight) {
      wanted.add(
        LabelBox(
          id: texts.length,
          left: at.dx,
          top: at.dy,
          width: painter.width,
          height: painter.height,
          weight: weight,
        ),
      );
      texts.add(text);
      painters.add(painter);
    }

    // Группы: название стоит над своими точками и не уходит за край
    // окна, пока на экране видна хотя бы одна точка группы, — при
    // приближении оно остаётся ответом на вопрос «где я».
    final Map<String, List<int>> groups = <String, List<int>>{};
    for (int i = 0; i < stars.length; i++) {
      groups.putIfAbsent(stars[i].group, () => <int>[]).add(i);
    }
    final List<String> names = groups.keys.toList()..sort();
    for (final String name in names) {
      double sum = 0;
      double top = double.infinity;
      int seen = 0;
      for (final int index in groups[name]!) {
        final double sx = viewport.screenX(stars[index].x);
        final double sy = viewport.screenY(stars[index].y);
        final double r = radii[index];
        if (sx + r < 0 || sx - r > width || sy + r < 0 || sy - r > height) {
          continue;
        }
        seen++;
        sum += sx;
        top = math.min(top, sy - r);
      }
      if (seen == 0) {
        continue;
      }
      final TextPainter painter = _painterOf(
        name,
        groupStyle,
        textScaler,
        math.min(kGalaxyGroupWidth, math.max(0, width - 2 * kGalaxyEdge)),
      );
      if (painter.width + 2 * kGalaxyEdge > width ||
          painter.height + 2 * kGalaxyEdge > height) {
        continue;
      }
      final double left = (sum / seen - painter.width / 2)
          .clamp(kGalaxyEdge, width - painter.width - kGalaxyEdge)
          .toDouble();
      final double place = (top - painter.height - kGalaxyLabelGap)
          .clamp(kGalaxyEdge, height - painter.height - kGalaxyEdge)
          .toDouble();
      want(name, painter, Offset(left, place), kGalaxyGroupWeight);
      kinds.add(true);
    }

    // Книги: название справа от точки. Тяжелее та, в которой провели
    // больше времени; выбранная — тяжелее всех книг.
    if (titlesShown(count: stars.length, unit: viewport.unit)) {
      for (int i = 0; i < stars.length; i++) {
        final double sx = viewport.screenX(stars[i].x);
        final double sy = viewport.screenY(stars[i].y);
        if (sx < 0 || sx > width || sy < 0 || sy > height) {
          continue;
        }
        final TextPainter painter = _painterOf(
          stars[i].book.title,
          titleStyle,
          textScaler,
          kGalaxyTitleWidth,
        );
        want(
          stars[i].book.title,
          painter,
          Offset(sx + radii[i] + kGalaxyLabelGap, sy - painter.height / 2),
          i == selected ? 2 : (shares[stars[i].book.id] ?? 0),
        );
        kinds.add(false);
      }
    }

    return <GalaxyLabel>[
      for (final LabelBox box in pickLabels(
        wanted,
        width: width,
        height: height,
      ))
        GalaxyLabel(
          text: texts[box.id],
          painter: painters[box.id],
          rect: Rect.fromLTWH(box.left, box.top, box.width, box.height),
          group: kinds[box.id],
        ),
    ];
  }
}

/// Рисует карту книг (ALG-MAP-12): точки и подписи.
///
/// Слоёв два — точки и текст поверх них. Каждая точка — ореол и ядро:
/// два круга на книгу. На трёхстах книгах, больше которых расчёт карты
/// пока не берёт (`kExactBooksLimit`), это сотни примитивов на кадр, и
/// атлас спрайтов из алгоритма здесь ещё не нужен — он придёт с картой
/// на тысячи книг. Туманности нет: групп — категории полки, и поле
/// плотности для них не считается.
///
/// Светофильтр чтения на карту не ложится: он накрывает только
/// картинку страницы.
class GalaxyPainter extends CustomPainter {
  /// Создаёт художника кадра [scene].
  const GalaxyPainter(this.scene);

  /// Кадр.
  final GalaxyScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final Paint halo = Paint()..style = PaintingStyle.fill;
    final Paint core = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < scene.stars.length; i++) {
      final Offset at = scene.placeOf(i);
      final double r = scene.radii[i];
      if (at.dx + r * 2.4 < 0 ||
          at.dx - r * 2.4 > size.width ||
          at.dy + r * 2.4 < 0 ||
          at.dy - r * 2.4 > size.height) {
        continue;
      }
      final Color colour = scene.colours[i];
      halo.color = colour.withValues(
        alpha: scene.palette.isDark ? 0.22 : 0.16,
      );
      core.color = colour;
      canvas
        ..drawCircle(at, r * 2.2, halo)
        ..drawCircle(at, r, core);
    }
    final int? selected = scene.selected;
    if (selected != null && selected < scene.stars.length) {
      // Выбранная звезда обведена основным цветом текста: кольцо видно
      // на любой теме и не зависит от оттенка группы.
      canvas.drawCircle(
        scene.placeOf(selected),
        scene.radii[selected] + 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color(scene.palette.text),
      );
    }
    for (final GalaxyLabel label in scene.labels) {
      label.painter.paint(canvas, label.rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(GalaxyPainter oldDelegate) {
    return !identical(oldDelegate.scene, scene);
  }
}
