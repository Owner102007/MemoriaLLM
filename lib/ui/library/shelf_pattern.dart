import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/library/category_style.dart';

/// Узор подложки категории.
///
/// Рисуется **под** обложками и только под ними: заголовок категории и
/// подписи книг остаются на обычном фоне темы. Смысл узора — дать глазу
/// зацепку, по которой участок полки узнаётся до чтения названия.
///
/// Узоры абстрактные и «машинные»: сетки, трассы, потоки данных, сбои
/// развёртки. Спокойный узор красится почти в цвет подложки, и его
/// контраст закреплён тестом. Кислотный светится в полную силу — но
/// рисуется тонкой линией, и вес участка от этого остаётся в тех же
/// границах (см. `kCategoryAcidCoverage`).
///
/// Рисунок **не случаен от кадра к кадру**: генератор шума заводится от
/// хеша названия категории, поэтому одна и та же категория выглядит
/// одинаково при каждой отрисовке, на телефоне и на ПК.
class ShelfPatternPainter extends CustomPainter {
  /// Создаёт художника.
  const ShelfPatternPainter({
    required this.style,
    required this.background,
    required this.ink,
    required this.step,
    required this.stroke,
    required this.glow,
  });

  /// Вид категории: узор, сдвиг рисунка и хеш названия.
  final CategoryStyle style;

  /// Цвет подложки.
  final Color background;

  /// Цвет самого узора.
  final Color ink;

  /// Шаг рисунка в точках. Зависит от размера блока, а не от экрана:
  /// полка обязана выглядеть одной и той же полкой на телефоне и на ПК.
  final double step;

  /// Толщина линии узора в точках.
  final double stroke;

  /// Светится ли узор.
  ///
  /// Свечение — вторая отрисовка того же рисунка размытой кистью. Оно
  /// стоит ровно вдвое дороже обычного узора, и потому достаётся только
  /// кислотным категориям: их на полке одна из семи.
  final bool glow;

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

    if (glow) {
      final Paint halo = Paint()
        ..color = ink.withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 3
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, step / 6);
      _draw(canvas, size, shift, halo, halo);
    }

    final Paint line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;
    final Paint solid = Paint()..color = ink;
    _draw(canvas, size, shift, line, solid);
    canvas.restore();
  }

  /// Один проход рисунка.
  ///
  /// Генератор шума заводится здесь, а не в поле: свечение и сам узор —
  /// два прохода одной и той же геометрии, и оба обязаны получить
  /// одинаковую последовательность случайных чисел.
  void _draw(Canvas canvas, Size size, double shift, Paint line, Paint fill) {
    final _Noise noise = _Noise(style.seed);
    switch (style.pattern) {
      case ShelfPattern.circuit:
        _circuit(canvas, size, shift, line, fill, noise);
      case ShelfPattern.hexGrid:
        _hexGrid(canvas, size, shift, line);
      case ShelfPattern.dataStream:
        _dataStream(canvas, size, shift, line, noise);
      case ShelfPattern.scanlines:
        _scanlines(canvas, size, shift, line, noise);
      case ShelfPattern.glitchBlocks:
        _glitchBlocks(canvas, size, shift, line, fill, noise);
      case ShelfPattern.triangles:
        _triangles(canvas, size, shift, line);
      case ShelfPattern.isoGrid:
        _isoGrid(canvas, size, shift, line);
      case ShelfPattern.nodes:
        _nodes(canvas, size, shift, line, fill, noise);
      case ShelfPattern.barcode:
        _barcode(canvas, size, shift, fill, noise);
      case ShelfPattern.pulse:
        _pulse(canvas, size, shift, line, noise);
      case ShelfPattern.crosshatch:
        _crosshatch(canvas, size, shift, line);
      case ShelfPattern.contour:
        _contour(canvas, size, shift, line, noise);
      case ShelfPattern.maze:
        _maze(canvas, size, shift, line, noise);
      case ShelfPattern.pixelRain:
        _pixelRain(canvas, size, shift, fill, noise);
      case ShelfPattern.waveform:
        _waveform(canvas, size, shift, line, noise);
      case ShelfPattern.chevron:
        _chevron(canvas, size, shift, line);
    }
  }

  // --- Узоры ---------------------------------------------------------

  /// Печатная плата: трассы с прямыми углами и контактные площадки.
  void _circuit(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    Paint fill,
    _Noise noise,
  ) {
    final double cell = step;
    final double pad = math.max(1.0, cell / 12);
    for (double y = shift - cell; y < size.height + cell; y += cell) {
      for (double x = shift - cell; x < size.width + cell; x += cell) {
        // Трасса всегда выходит из середины клетки и ломается ровно один
        // раз: так рисунок остаётся связным, а не рассыпается штрихами.
        final double cx = x + cell / 2;
        final double cy = y + cell / 2;
        switch (noise.range(4)) {
          case 0:
            canvas
              ..drawLine(Offset(x, cy), Offset(cx, cy), line)
              ..drawLine(Offset(cx, cy), Offset(cx, y), line);
          case 1:
            canvas
              ..drawLine(Offset(cx, y), Offset(cx, cy), line)
              ..drawLine(Offset(cx, cy), Offset(x + cell, cy), line);
          case 2:
            canvas
              ..drawLine(Offset(x + cell, cy), Offset(cx, cy), line)
              ..drawLine(Offset(cx, cy), Offset(cx, y + cell), line);
          default:
            canvas
              ..drawLine(Offset(cx, y + cell), Offset(cx, cy), line)
              ..drawLine(Offset(cx, cy), Offset(x, cy), line);
        }
        if (noise.chance(0.35)) {
          canvas.drawCircle(Offset(cx, cy), pad, fill);
        }
      }
    }
  }

  /// Соты.
  void _hexGrid(Canvas canvas, Size size, double shift, Paint line) {
    final double r = step / 2;
    final double dx = r * math.sqrt(3);
    final double dy = r * 1.5;
    int row = 0;
    for (double y = shift - dy * 2; y < size.height + dy * 2; y += dy) {
      final double offset = row.isEven ? 0.0 : dx / 2;
      for (double x = shift - dx + offset; x < size.width + dx; x += dx) {
        canvas.drawPath(_hexagon(Offset(x, y), r), line);
      }
      row++;
    }
  }

  Path _hexagon(Offset centre, double r) {
    final Path path = Path();
    for (int i = 0; i < 6; i++) {
      final double a = math.pi / 180 * (60 * i - 90);
      final Offset p = centre + Offset(r * math.cos(a), r * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// Поток данных: вертикальные штрихи разной длины.
  void _dataStream(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    _Noise noise,
  ) {
    final double column = step / 2;
    for (double x = shift - column; x < size.width + column; x += column) {
      double y = shift - step * noise.unit() * 3;
      while (y < size.height + step) {
        final double length = step * (0.3 + noise.unit() * 1.4);
        canvas.drawLine(Offset(x, y), Offset(x, y + length), line);
        y += length + step * (0.4 + noise.unit());
      }
    }
  }

  /// Строчная развёртка с редким сбоем.
  void _scanlines(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    _Noise noise,
  ) {
    final double gap = step / 3;
    for (double y = shift - gap; y < size.height + gap; y += gap) {
      if (noise.chance(0.12)) {
        // Сбитая строка: разорвана и сдвинута вбок. Ради него узор и
        // существует — ровная развёртка была бы просто полосками.
        final double cut = size.width * (0.2 + noise.unit() * 0.5);
        final double jump = step * (noise.unit() - 0.5);
        final Offset tail = Offset(cut + step / 3, y + jump);
        canvas
          ..drawLine(Offset(0, y), Offset(cut, y), line)
          ..drawLine(tail, Offset(size.width, y + jump), line);
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
  }

  /// Смещённые прямоугольные блоки.
  void _glitchBlocks(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    Paint fill,
    _Noise noise,
  ) {
    final double band = step * 0.7;
    for (double y = shift - band; y < size.height + band; y += band) {
      double x = shift - step * noise.unit() * 2;
      while (x < size.width + step) {
        final double w = step * (0.4 + noise.unit() * 1.8);
        final Rect r = Rect.fromLTWH(x, y, w, band * 0.62);
        canvas.drawRect(r, noise.chance(0.3) ? fill : line);
        x += w + step * (0.3 + noise.unit() * 0.9);
      }
    }
  }

  /// Треугольная сетка.
  void _triangles(Canvas canvas, Size size, double shift, Paint line) {
    final double w = step;
    final double h = step * math.sqrt(3) / 2;
    int row = 0;
    for (double y = shift - h; y < size.height + h; y += h) {
      final double offset = row.isEven ? 0.0 : w / 2;
      for (double x = shift - w + offset; x < size.width + w; x += w) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y + h)
            ..lineTo(x + w / 2, y)
            ..lineTo(x + w, y + h)
            ..close(),
          line,
        );
      }
      row++;
    }
  }

  /// Изометрическая сетка: город, снятый сверху.
  void _isoGrid(Canvas canvas, Size size, double shift, Paint line) {
    final double span = size.width + size.height;
    final double slope = math.tan(math.pi / 6);
    for (double x = shift - span; x < span; x += step) {
      canvas
        ..drawLine(
          Offset(x, 0),
          Offset(x + size.height / slope, size.height),
          line,
        )
        ..drawLine(
          Offset(x, 0),
          Offset(x - size.height / slope, size.height),
          line,
        );
    }
    for (double x = shift - step; x < size.width + step; x += step * 2) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  /// Узлы, соединённые линиями, — карта сети.
  void _nodes(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    Paint fill,
    _Noise noise,
  ) {
    final double cell = step * 1.2;
    final int cols = (size.width / cell).ceil() + 2;
    final int rows = (size.height / cell).ceil() + 2;
    final List<List<Offset>> grid = <List<Offset>>[
      for (int r = 0; r < rows; r++)
        <Offset>[
          for (int c = 0; c < cols; c++)
            Offset(
              shift - cell + c * cell + (noise.unit() - 0.5) * cell * 0.6,
              shift - cell + r * cell + (noise.unit() - 0.5) * cell * 0.6,
            ),
        ],
    ];
    final double dot = math.max(1.0, cell / 16);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final Offset p = grid[r][c];
        if (c + 1 < cols && noise.chance(0.72)) {
          canvas.drawLine(p, grid[r][c + 1], line);
        }
        if (r + 1 < rows && noise.chance(0.55)) {
          canvas.drawLine(p, grid[r + 1][c], line);
        }
        canvas.drawCircle(p, dot, fill);
      }
    }
  }

  /// Штрихкод: вертикальные полосы разной ширины.
  void _barcode(
    Canvas canvas,
    Size size,
    double shift,
    Paint fill,
    _Noise noise,
  ) {
    double x = shift - step;
    while (x < size.width + step) {
      final double w = step * (0.06 + noise.unit() * 0.22);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), fill);
      x += w + step * (0.12 + noise.unit() * 0.4);
    }
  }

  /// Концентрические дуги — расходящийся сигнал.
  void _pulse(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    _Noise noise,
  ) {
    final double grid = step * 3;
    for (double cy = shift - grid; cy < size.height + grid; cy += grid) {
      for (double cx = shift - grid; cx < size.width + grid; cx += grid) {
        final Offset centre = Offset(
          cx + (noise.unit() - 0.5) * grid * 0.5,
          cy + (noise.unit() - 0.5) * grid * 0.5,
        );
        final int rings = 2 + noise.range(3);
        for (int i = 1; i <= rings; i++) {
          canvas.drawCircle(centre, step * 0.45 * i, line);
        }
      }
    }
  }

  /// Перекрёстная диагональная штриховка.
  void _crosshatch(Canvas canvas, Size size, double shift, Paint line) {
    final double span = size.width + size.height;
    for (double x = shift - span; x < span; x += step) {
      canvas
        ..drawLine(Offset(x, 0), Offset(x + size.height, size.height), line)
        ..drawLine(Offset(x, 0), Offset(x - size.height, size.height), line);
    }
  }

  /// Ступенчатые горизонтали — рельеф на карте.
  void _contour(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    _Noise noise,
  ) {
    final double gap = step * 0.75;
    final double stepX = math.max(4.0, step / 3);
    for (double y = shift - gap; y < size.height + gap; y += gap) {
      final Path path = Path()..moveTo(0, y);
      double level = y;
      for (double x = stepX; x < size.width + stepX; x += stepX) {
        // Случайное блуждание с возвратом: без притяжения к своей линии
        // горизонтали расползлись бы и слиплись через пару экранов.
        final double drift = (noise.unit() - 0.5) * gap * 0.7;
        final double next = level + drift + (y - level) * 0.35;
        // Ступенька, а не наклон: горизонталь на карте идёт уступами.
        path
          ..lineTo(x, level)
          ..lineTo(x, next);
        level = next;
      }
      canvas.drawPath(path, line);
    }
  }

  /// Короткие сегменты, сложенные в лабиринт.
  void _maze(Canvas canvas, Size size, double shift, Paint line, _Noise noise) {
    final double cell = step * 0.8;
    for (double y = shift - cell; y < size.height + cell; y += cell) {
      for (double x = shift - cell; x < size.width + cell; x += cell) {
        if (noise.chance(0.55)) {
          canvas.drawLine(Offset(x, y), Offset(x + cell, y), line);
        }
        if (noise.chance(0.55)) {
          canvas.drawLine(Offset(x, y), Offset(x, y + cell), line);
        }
      }
    }
  }

  /// Редкие квадратные пиксели, осыпающиеся вниз.
  void _pixelRain(
    Canvas canvas,
    Size size,
    double shift,
    Paint fill,
    _Noise noise,
  ) {
    final double cell = step / 2.5;
    final int rows = (size.height / cell).ceil() + 1;
    for (double x = shift - cell; x < size.width + cell; x += cell) {
      // Чем ниже, тем реже: столбец должен таять книзу, а не рябить
      // ровным шумом по всему блоку.
      for (int r = 0; r < rows; r++) {
        final double density = 0.42 * (1 - r / rows) + 0.04;
        if (noise.chance(density)) {
          final double top = shift - cell + r * cell;
          final double side = cell * 0.62;
          canvas.drawRect(Rect.fromLTWH(x, top, side, side), fill);
        }
      }
    }
  }

  /// Ломаная осциллограммы.
  void _waveform(
    Canvas canvas,
    Size size,
    double shift,
    Paint line,
    _Noise noise,
  ) {
    final double band = step * 1.4;
    final double stepX = math.max(3.0, step / 4);
    for (double y = shift - band; y < size.height + band; y += band) {
      final Path path = Path()..moveTo(0, y);
      for (double x = stepX; x < size.width + stepX; x += stepX) {
        final double amp = noise.chance(0.18) ? band * 0.42 : band * 0.12;
        path.lineTo(x, y + (noise.unit() - 0.5) * 2 * amp);
      }
      canvas.drawPath(path, line);
    }
  }

  /// Шевроны.
  void _chevron(Canvas canvas, Size size, double shift, Paint line) {
    final double w = step;
    final double h = step * 0.6;
    for (double y = shift - h; y < size.height + h; y += h) {
      final Path path = Path();
      for (double x = shift - w; x < size.width + w; x += w) {
        path
          ..moveTo(x, y + h)
          ..lineTo(x + w / 2, y)
          ..lineTo(x + w, y + h);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(ShelfPatternPainter old) {
    return old.style != style ||
        old.background != background ||
        old.ink != ink ||
        old.step != step ||
        old.stroke != stroke ||
        old.glow != glow;
  }
}

/// Постоянный от запуска к запуску генератор случайных чисел.
///
/// Узор обязан выглядеть одинаково при каждой отрисовке — иначе полка
/// мерцала бы при прокрутке, — и одинаково на телефоне и на ПК. Обычный
/// `Random` без зерна не годится вовсе, а `Random(seed)` не обещает
/// одинаковой последовательности между версиями Dart. Здесь xorshift на
/// 32 битах: пять строк, которые никогда не изменятся.
class _Noise {
  _Noise(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed;

  int _state;

  int _next() {
    int x = _state & 0xFFFFFFFF;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// Число от 0 (включительно) до 1 (не включая).
  double unit() => _next() / 4294967296.0;

  /// Целое от 0 до [bound] - 1.
  int range(int bound) => bound <= 0 ? 0 : _next() % bound;

  /// Выпало ли событие с вероятностью [probability].
  bool chance(double probability) => unit() < probability;
}
