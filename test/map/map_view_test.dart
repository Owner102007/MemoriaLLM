import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/map_layout.dart';
import 'package:memoria/domain/map/map_view.dart';

/// Точки для проверок: [count] штук в квадрате от −1 до 1, одни и те
/// же при каждом прогоне.
({List<double> xs, List<double> ys}) scatter(int count, {int seed = 7}) {
  final math.Random random = math.Random(seed);
  return (
    xs: <double>[for (int i = 0; i < count; i++) random.nextDouble() * 2 - 1],
    ys: <double>[for (int i = 0; i < count; i++) random.nextDouble() * 2 - 1],
  );
}

/// Ближайшая точка перебором — то, с чем сверяется решётка.
int? bruteNearest(
  List<double> xs,
  List<double> ys,
  double x,
  double y,
  double radius,
) {
  int? best;
  double bestSquare = double.infinity;
  for (int i = 0; i < xs.length; i++) {
    final double dx = xs[i] - x;
    final double dy = ys[i] - y;
    final double square = dx * dx + dy * dy;
    if (square <= radius * radius && square < bestSquare) {
      best = i;
      bestSquare = square;
    }
  }
  return best;
}

/// F-MAP-07, F-MAP-08, ALG-MAP-12, ALG-MAP-13: вид карты на экране —
/// правила без виджетов.
void main() {
  const MapExtent square = MapExtent(cx: 0, cy: 0, halfWidth: 1, halfHeight: 1);

  MapViewport phone({MapCamera? camera, MapExtent extent = square}) {
    return MapViewport(
      width: 360,
      height: 640,
      extent: extent,
      camera: camera ?? MapCamera.home(extent),
    );
  }

  group('F-MAP-07: размах карты', () {
    test('F-MAP-07: размах — прямоугольник вокруг всех точек', () {
      final MapExtent extent = MapExtent.of(
        <double>[-0.5, 0.25, 0.75],
        <double>[0.1, -0.3, 0.5],
      );
      expect(extent.cx, closeTo(0.125, 1e-12));
      expect(extent.cy, closeTo(0.1, 1e-12));
      expect(extent.halfWidth, closeTo(0.625, 1e-12));
      expect(extent.halfHeight, closeTo(0.4, 1e-12));
    });

    test('F-MAP-07: книги, сошедшиеся в точку, экран не растягивают', () {
      final MapExtent extent = MapExtent.of(
        <double>[0.3, 0.3, 0.3],
        <double>[-0.2, -0.2, -0.2],
      );
      expect(extent.halfWidth, kMapMinHalf);
      expect(extent.halfHeight, kMapMinHalf);
      expect(extent.cx, 0.3);
      expect(extent.cy, -0.2);
    });

    test('F-MAP-07: без точек размах — весь лист карты', () {
      final MapExtent extent = MapExtent.of(<double>[], <double>[]);
      expect(extent.halfWidth, 1);
      expect(extent.halfHeight, 1);
      expect(extent.cx, 0);
      expect(extent.cy, 0);
    });
  });

  group('ALG-MAP-13: окно карты', () {
    test('ALG-MAP-13: при наименьшем масштабе вся карта в окне, с '
        'полями', () {
      final MapViewport view = phone();
      // Узкая сторона — ширина: по ней карта и вписана.
      expect(view.screenX(-1), closeTo(360 * kMapMargin, 1e-9));
      expect(view.screenX(1), closeTo(360 * (1 - kMapMargin), 1e-9));
      expect(view.screenY(-1), greaterThan(640 * kMapMargin));
      expect(view.screenY(1), lessThan(640 * (1 - kMapMargin)));
      // Середина карты — в середине окна.
      expect(view.screenX(0), 180);
      expect(view.screenY(0), 320);
    });

    test('ALG-MAP-13: экран и карта пересчитываются туда и обратно', () {
      final MapViewport view = phone(
        camera: const MapCamera(scale: 6, cx: 0.2, cy: -0.4),
      );
      for (final double x in <double>[-1, -0.3, 0, 0.2, 0.9]) {
        expect(view.mapX(view.screenX(x)), closeTo(x, 1e-12));
        expect(view.mapY(view.screenY(x)), closeTo(x, 1e-12));
      }
      expect(view.unit, closeTo(view.base * 6, 1e-9));
    });

    test('ALG-MAP-13: приближение держит точку под курсором', () {
      final MapViewport view = phone();
      for (final double factor in <double>[1.4, 2, 8, 40]) {
        for (final List<double> at in <List<double>>[
          <double>[180, 320],
          <double>[90, 200],
          <double>[300, 500],
        ]) {
          final double x = view.mapX(at[0]);
          final double y = view.mapY(at[1]);
          final MapViewport zoomed = view.withCamera(
            view.zoomedAt(sx: at[0], sy: at[1], factor: factor),
          );
          final String reason = '×$factor в (${at[0]}, ${at[1]})';
          expect(zoomed.camera.scale, closeTo(factor, 1e-9), reason: reason);
          expect(zoomed.screenX(x), closeTo(at[0], 1e-6), reason: reason);
          // По высоте у окна запас: карта вписана по ширине, и точка
          // под курсором вне размаха карты может упереться в край.
          if (y.abs() <= 1) {
            expect(zoomed.screenY(y), closeTo(at[1], 1e-6), reason: reason);
          }
        }
      }
    });

    test('ALG-MAP-13: масштаб — от 1 до 64, и не дальше', () {
      final MapViewport view = phone();
      expect(view.zoomedAt(sx: 180, sy: 320, factor: 0.25).scale, kMapMinScale);
      expect(view.zoomedAt(sx: 180, sy: 320, factor: 1000).scale, kMapMaxScale);
      expect(clampMapScale(double.nan), kMapMinScale);
      expect(clampMapScale(double.infinity), kMapMinScale);
      expect(clampMapScale(3), 3);
    });

    test('ALG-MAP-13: при наименьшем масштабе карту не увести', () {
      final MapCamera moved = clampCamera(
        const MapCamera(scale: 1, cx: 0.7, cy: -0.9),
        square,
      );
      expect(moved, const MapCamera(scale: 1, cx: 0, cy: 0));
    });

    test('ALG-MAP-13: вблизи середина экрана доходит до края карты, но '
        'не дальше', () {
      final MapCamera far = clampCamera(
        const MapCamera(scale: 4, cx: 5, cy: -5),
        square,
      );
      expect(far.cx, closeTo(0.75, 1e-12));
      expect(far.cy, closeTo(-0.75, 1e-12));
      final MapCamera inside = clampCamera(
        const MapCamera(scale: 4, cx: 0.3, cy: 0.1),
        square,
      );
      expect(inside, const MapCamera(scale: 4, cx: 0.3, cy: 0.1));
      // Не число — середина карты.
      final MapCamera broken = clampCamera(
        const MapCamera(scale: 4, cx: double.nan, cy: double.infinity),
        square,
      );
      expect(broken.cx, 0);
      expect(broken.cy, 0);
    });

    test('ALG-MAP-13: щипок ведёт взятую точку за пальцами', () {
      final MapViewport view = phone();
      final double x = view.mapX(120);
      final double y = view.mapY(300);
      final MapViewport moved = view.withCamera(
        view.anchored(x: x, y: y, sx: 150, sy: 340, scale: 5),
      );
      expect(moved.camera.scale, 5);
      expect(moved.screenX(x), closeTo(150, 1e-6));
      expect(moved.screenY(y), closeTo(340, 1e-6));
    });

    test('ALG-MAP-13: окно без размера не делит на ноль', () {
      const MapViewport view = MapViewport(
        width: 0,
        height: 0,
        extent: square,
        camera: MapCamera(scale: 1, cx: 0, cy: 0),
      );
      expect(view.base, 1);
      expect(view.screenX(0.5).isFinite, isTrue);
      expect(view.mapX(10).isFinite, isTrue);
    });
  });

  group('SNO-F-MAP-01: размер точки', () {
    test('SNO-F-MAP-01: доли времени в сумме дают единицу', () {
      final Map<String, double> shares = timeShares(<String, int>{
        'a': 30000,
        'b': 90000,
        'c': 0,
        'd': -5,
      });
      expect(shares['a'], closeTo(0.25, 1e-12));
      expect(shares['b'], closeTo(0.75, 1e-12));
      expect(shares['c'], 0);
      expect(shares['d'], 0);
    });

    test('SNO-F-MAP-01: пока не читали ни одну, точки одинаковы', () {
      final Map<String, double> shares = timeShares(<String, int>{
        'a': 0,
        'b': 0,
      });
      expect(shares.values.toSet(), <double>{0});
      expect(timeShares(<String, int>{}), isEmpty);
    });

    test('SNO-F-MAP-01: площадь точки растёт с долей времени линейно', () {
      final double none = starRadius(base: 5, share: 0, scale: 1);
      final double half = starRadius(base: 5, share: 0.5, scale: 1);
      final double all = starRadius(base: 5, share: 1, scale: 1);
      expect(none, 5);
      expect(half, greaterThan(none));
      expect(all, greaterThan(half));
      expect((all * all) / (none * none), closeTo(kStarAreaGain, 1e-9));
      expect(
        (half * half) / (none * none),
        closeTo(1 + (kStarAreaGain - 1) / 2, 1e-9),
      );
      // Доля вне пределов и не число — как край.
      expect(starRadius(base: 5, share: 7, scale: 1), all);
      expect(starRadius(base: 5, share: -1, scale: 1), none);
      expect(starRadius(base: 5, share: double.nan, scale: 1), none);
    });

    test('ALG-MAP-13: радиус растёт медленнее приближения и не без '
        'конца', () {
      final double near = starRadius(base: 5, share: 0, scale: 4);
      expect(near, closeTo(10, 1e-9), reason: 'корень из масштаба');
      expect(
        starRadius(base: 5, share: 0, scale: 64),
        closeTo(5 * kStarZoomGain, 1e-9),
      );
      expect(
        starRadius(base: 5, share: 0, scale: 9),
        closeTo(5 * kStarZoomGain, 1e-9),
      );
    });

    test('F-MAP-07: точки не слипаются при наименьшем масштабе', () {
      // Просвет между соседями — тот, до которого раздвигает раскладка.
      expect(mapGap(16), closeTo(kGapShare / 4, 1e-12));
      for (final int count in <int>[3, 14, 40, 300]) {
        final double base = phone().base;
        final double radius = baseStarRadius(count: count, base: base);
        expect(radius, greaterThanOrEqualTo(kStarMinRadius));
        expect(radius, lessThanOrEqualTo(kStarBaseRadius));
        if (radius > kStarMinRadius) {
          expect(
            radius * 2,
            lessThan(mapGap(count) * base),
            reason: '$count книг: две точки шире просвета',
          );
        }
      }
    });

    test('F-MAP-07: названия книг появляются, когда между точками есть '
        'место', () {
      final double base = phone().base;
      expect(titlesShown(count: 14, unit: base), isFalse);
      expect(titlesShown(count: 14, unit: base * 64), isTrue);
      // У большой библиотеки «вблизи» наступает позже.
      double first(int count) {
        for (double scale = 1; scale <= 64; scale += 0.25) {
          if (titlesShown(count: count, unit: base * scale)) {
            return scale;
          }
        }
        return double.infinity;
      }

      expect(first(14), lessThan(first(300)));
      expect(first(300), lessThanOrEqualTo(64));
    });
  });

  group('ALG-MAP-13: попадание по точке', () {
    test('F-MAP-08: попадание находит ту самую книгу на трёх уровнях '
        'зума', () {
      final ({List<double> xs, List<double> ys}) points = scatter(300);
      final StarGrid grid = StarGrid(points.xs, points.ys);
      final MapExtent extent = MapExtent.of(points.xs, points.ys);
      final math.Random random = math.Random(11);
      for (final double scale in <double>[1, 8, 64]) {
        final MapViewport view = phone(
          extent: extent,
          camera: MapCamera(scale: scale, cx: extent.cx, cy: extent.cy),
        );
        final double radius = kHitRadius / view.unit;
        int hits = 0;
        for (int i = 0; i < 400; i++) {
          final double x = random.nextDouble() * 2.4 - 1.2;
          final double y = random.nextDouble() * 2.4 - 1.2;
          final int? found = grid.nearest(x, y, radius);
          expect(
            found,
            bruteNearest(points.xs, points.ys, x, y, radius),
            reason: 'масштаб $scale, точка ($x, $y)',
          );
          if (found != null) {
            hits++;
          }
        }
        // Нажатие точно по книге находит её саму.
        for (int i = 0; i < points.xs.length; i += 7) {
          expect(
            grid.nearest(points.xs[i], points.ys[i], radius),
            i,
            reason: 'масштаб $scale, книга $i',
          );
        }
        if (scale == 1) {
          expect(hits, greaterThan(0), reason: 'вдали попадают почти всегда');
        }
      }
      expect(grid.length, 300);
    });

    test('ALG-MAP-13: дальше радиуса — мимо', () {
      final StarGrid grid = StarGrid(<double>[0, 0.5], <double>[0, 0.5]);
      expect(grid.nearest(0.05, 0, 0.1), 0);
      expect(grid.nearest(0.2, 0, 0.1), isNull);
      expect(grid.nearest(0.45, 0.5, 0.1), 1);
      expect(grid.nearest(double.nan, 0, 0.1), isNull);
      expect(grid.nearest(0, 0, 0), isNull);
      expect(StarGrid(<double>[], <double>[]).nearest(0, 0, 1), isNull);
    });

    test('ALG-MAP-13: из равноудалённых — книга с меньшим номером', () {
      final StarGrid grid = StarGrid(<double>[-0.1, 0.1], <double>[0, 0]);
      expect(grid.nearest(0, 0, 0.5), 0);
    });

    test('F-MAP-08: крупная точка ловит нажатие всей собой', () {
      final StarGrid grid = StarGrid(<double>[0, 1], <double>[0, 0]);
      // Обычный круг попадания — 0,05; у первой книги точка радиусом 0,3.
      expect(grid.nearest(0.25, 0, 0.05), isNull);
      expect(grid.nearest(0.25, 0, 0.05, reach: <double>[0.3, 0.01]), 0);
      expect(grid.nearest(0.75, 0, 0.05, reach: <double>[0.3, 0.01]), isNull);
      // Ближняя по расстоянию выигрывает у крупной.
      expect(grid.nearest(0.97, 0, 0.05, reach: <double>[2, 0.01]), 1);
    });
  });

  group('ALG-MAP-12: отбор подписей', () {
    LabelBox box(int id, double left, double top, {double weight = 0}) {
      return LabelBox(
        id: id,
        left: left,
        top: top,
        width: 100,
        height: 20,
        weight: weight,
      );
    }

    test('ALG-MAP-12: подписей на кадре не больше двадцати четырёх', () {
      final List<LabelBox> wanted = <LabelBox>[
        for (int i = 0; i < 60; i++)
          box(i, 10 + (i % 6) * 110, 10 + (i ~/ 6) * 30),
      ];
      final List<LabelBox> placed = pickLabels(wanted, width: 700, height: 400);
      expect(placed, hasLength(kMaxLabels));
      expect(kMaxLabels, 24);
    });

    test('ALG-MAP-12: подписи не пересекаются, тяжёлая встаёт первой', () {
      final List<LabelBox> placed = pickLabels(
        <LabelBox>[
          box(0, 10, 10, weight: 1),
          box(1, 60, 20, weight: 5),
          box(2, 300, 10, weight: 2),
          box(3, 350, 25, weight: 2),
        ],
        width: 700,
        height: 400,
      );
      expect(placed.map((LabelBox item) => item.id), <int>[1, 2]);
      for (final LabelBox a in placed) {
        for (final LabelBox b in placed) {
          if (!identical(a, b)) {
            expect(a.overlaps(b), isFalse);
          }
        }
      }
    });

    test('ALG-MAP-12: при равном весе раньше та, что раньше в списке', () {
      final List<LabelBox> placed = pickLabels(
        <LabelBox>[box(0, 10, 10), box(1, 50, 15), box(2, 10, 40)],
        width: 700,
        height: 400,
      );
      expect(placed.map((LabelBox item) => item.id), <int>[0, 2]);
    });

    test('ALG-MAP-12: подпись, не уместившаяся в окне, не встаёт', () {
      final List<LabelBox> placed = pickLabels(
        <LabelBox>[
          box(0, -5, 10, weight: 9),
          box(1, 650, 10, weight: 9),
          box(2, 10, 390, weight: 9),
          box(3, 10, -1, weight: 9),
          box(4, 200, 200),
        ],
        width: 700,
        height: 400,
      );
      expect(placed.map((LabelBox item) => item.id), <int>[4]);
    });

    test('ALG-MAP-12: соприкосновение краями — не пересечение', () {
      expect(box(0, 10, 10).overlaps(box(1, 110, 10)), isFalse);
      expect(box(0, 10, 10).overlaps(box(1, 10, 30)), isFalse);
      expect(box(0, 10, 10).overlaps(box(1, 109, 29)), isTrue);
    });

    test('ALG-MAP-12: отбор трёхсот подписей укладывается в бюджет', () {
      final math.Random random = math.Random(3);
      final List<LabelBox> wanted = <LabelBox>[
        for (int i = 0; i < 300; i++)
          box(
            i,
            random.nextDouble() * 900,
            random.nextDouble() * 600,
            weight: random.nextDouble(),
          ),
      ];
      final Stopwatch watch = Stopwatch()..start();
      List<LabelBox> placed = const <LabelBox>[];
      for (int round = 0; round < 100; round++) {
        placed = pickLabels(wanted, width: 1000, height: 620);
      }
      watch.stop();
      final double perFrame = watch.elapsedMicroseconds / 100 / 1000;
      stdout.writeln(
        'ЗАМЕР ALG-MAP-12 | отбор подписей из 300 | бюджет 4 мс | '
        'встало ${placed.length} | ${perFrame.toStringAsFixed(3)} мс на кадр',
      );
      expect(placed.length, lessThanOrEqualTo(kMaxLabels));
      expect(perFrame, lessThan(4), reason: 'четверть кадра в 60 Гц');
    });
  });
}
