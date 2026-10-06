/// Карта книг на экране: камера, размер точки, попадание и отбор
/// подписей (F-MAP-07, F-MAP-08, ALG-MAP-12, ALG-MAP-13).
///
/// Здесь только правила — без Flutter: где на экране стоит точка карты
/// при данном масштабе, какого она размера, по какой книге попало
/// нажатие и какие подписи встают на кадр. Рисует по этим числам
/// `ui/galaxy/galaxy_painter.dart`.
library;

import 'dart:math' as math;

import 'map_layout.dart';

/// Наименьший масштаб: вся библиотека на экране.
const double kMapMinScale = 1;

/// Наибольший масштаб.
const double kMapMaxScale = 64;

/// Поле вокруг карты при наименьшем масштабе — доля стороны экрана с
/// каждого края: крайняя точка не лежит на кромке, и её подписи есть
/// где встать.
const double kMapMargin = 0.14;

/// Меньше этого половина размаха карты не считается — в единицах
/// карты: книги, сошедшиеся в точку, не растягиваются на весь экран.
const double kMapMinHalf = 0.05;

/// Какую долю просвета между соседними точками занимает радиус точки
/// непрочитанной книги при наименьшем масштабе.
const double kStarGapShare = 0.3;

/// Наименьший радиус точки, в логических пикселях: меньше — не видно.
const double kStarMinRadius = 2.5;

/// Наибольший радиус точки непрочитанной книги при наименьшем масштабе.
const double kStarBaseRadius = 6;

/// Во сколько раз площадь точки книги, на которую ушло всё время
/// чтения, больше площади точки неоткрытой (решение владельца Э3).
const double kStarAreaGain = 5;

/// Во сколько раз, самое большее, точка вырастает от приближения:
/// радиус растёт как корень из масштаба, но не без конца — на
/// шестидесятикратном приближении точка закрыла бы экран.
const double kStarZoomGain = 3;

/// На каком расстоянии от точки нажатие ещё попадает по ней, в
/// логических пикселях (ALG-MAP-13).
const double kHitRadius = 24;

/// Сколько подписей, самое большее, стоит на кадре (ALG-MAP-12).
const int kMaxLabels = 24;

/// С какого просвета между соседними точками, в логических пикселях,
/// у точек появляются названия книг: «вблизи» у библиотеки в десять
/// книг и в триста наступает на разном масштабе.
const double kTitleGap = 44;

/// Во сколько раз приближает двойное нажатие.
const double kDoubleTapZoom = 2;

/// Прямоугольник, в котором лежат точки карты.
class MapExtent {
  /// Создаёт размах.
  const MapExtent({
    required this.cx,
    required this.cy,
    required this.halfWidth,
    required this.halfHeight,
  });

  /// Размах точек с абсциссами [xs] и ординатами [ys].
  ///
  /// Пустой набор даёт квадрат от −1 до 1 — весь лист карты.
  factory MapExtent.of(List<double> xs, List<double> ys) {
    if (xs.isEmpty || xs.length != ys.length) {
      return const MapExtent(cx: 0, cy: 0, halfWidth: 1, halfHeight: 1);
    }
    double minX = xs.first;
    double maxX = xs.first;
    double minY = ys.first;
    double maxY = ys.first;
    for (int i = 1; i < xs.length; i++) {
      minX = math.min(minX, xs[i]);
      maxX = math.max(maxX, xs[i]);
      minY = math.min(minY, ys[i]);
      maxY = math.max(maxY, ys[i]);
    }
    return MapExtent(
      cx: (minX + maxX) / 2,
      cy: (minY + maxY) / 2,
      halfWidth: math.max((maxX - minX) / 2, kMapMinHalf),
      halfHeight: math.max((maxY - minY) / 2, kMapMinHalf),
    );
  }

  /// Абсцисса середины.
  final double cx;

  /// Ордината середины.
  final double cy;

  /// Половина ширины, не меньше [kMapMinHalf].
  final double halfWidth;

  /// Половина высоты, не меньше [kMapMinHalf].
  final double halfHeight;
}

/// Куда смотрит экран: масштаб и точка карты в его середине.
class MapCamera {
  /// Создаёт камеру.
  const MapCamera({required this.scale, required this.cx, required this.cy});

  /// Камера, которая видит всю карту [extent].
  factory MapCamera.home(MapExtent extent) {
    return MapCamera(scale: kMapMinScale, cx: extent.cx, cy: extent.cy);
  }

  /// Масштаб, от [kMapMinScale] до [kMapMaxScale].
  final double scale;

  /// Абсцисса точки карты в середине экрана.
  final double cx;

  /// Ордината точки карты в середине экрана.
  final double cy;

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.scale == scale &&
      other.cx == cx &&
      other.cy == cy;

  @override
  int get hashCode => Object.hash(scale, cx, cy);

  @override
  String toString() => 'MapCamera(×$scale, $cx, $cy)';
}

/// Карта в окне: пересчёт между картой и экраном.
class MapViewport {
  /// Создаёт окно шириной [width] и высотой [height] логических
  /// пикселей, в котором карта [extent] видна камерой [camera].
  const MapViewport({
    required this.width,
    required this.height,
    required this.extent,
    required this.camera,
  });

  /// Ширина окна.
  final double width;

  /// Высота окна.
  final double height;

  /// Размах карты.
  final MapExtent extent;

  /// Камера.
  final MapCamera camera;

  /// Сколько логических пикселей в единице карты при масштабе 1: карта
  /// вписана в окно целиком, с полями [kMapMargin].
  double get base {
    final double usable = 1 - 2 * kMapMargin;
    final double byWidth = width * usable / (2 * extent.halfWidth);
    final double byHeight = height * usable / (2 * extent.halfHeight);
    final double fit = math.min(byWidth, byHeight);
    return fit > 0 ? fit : 1;
  }

  /// Сколько логических пикселей в единице карты сейчас.
  double get unit => base * camera.scale;

  /// Абсцисса на экране точки карты с абсциссой [x].
  double screenX(double x) => width / 2 + (x - camera.cx) * unit;

  /// Ордината на экране точки карты с ординатой [y].
  double screenY(double y) => height / 2 + (y - camera.cy) * unit;

  /// Абсцисса на карте точки экрана с абсциссой [sx].
  double mapX(double sx) => camera.cx + (sx - width / 2) / unit;

  /// Ордината на карте точки экрана с ординатой [sy].
  double mapY(double sy) => camera.cy + (sy - height / 2) / unit;

  /// То же окно с другой камерой.
  MapViewport withCamera(MapCamera next) {
    return MapViewport(
      width: width,
      height: height,
      extent: extent,
      camera: next,
    );
  }

  /// Камера, при которой точка карты ([x], [y]) стоит на экране в
  /// ([sx], [sy]) при масштабе [scale].
  ///
  /// Масштаб зажат между [kMapMinScale] и [kMapMaxScale], а середина
  /// экрана не уходит от середины карты дальше, чем позволяет масштаб:
  /// при наименьшем карта стоит по центру, и увести её за край нельзя.
  MapCamera anchored({
    required double x,
    required double y,
    required double sx,
    required double sy,
    required double scale,
  }) {
    final double target = clampMapScale(scale);
    final double next = base * target;
    return clampCamera(
      MapCamera(
        scale: target,
        cx: x - (sx - width / 2) / next,
        cy: y - (sy - height / 2) / next,
      ),
      extent,
    );
  }

  /// Камера после приближения в [factor] раз к точке экрана ([sx],
  /// [sy]): точка карты под ней остаётся под ней (ALG-MAP-13).
  MapCamera zoomedAt({
    required double sx,
    required double sy,
    required double factor,
  }) {
    return anchored(
      x: mapX(sx),
      y: mapY(sy),
      sx: sx,
      sy: sy,
      scale: camera.scale * factor,
    );
  }
}

/// Масштаб в допустимых пределах; не число — наименьший.
double clampMapScale(double scale) {
  if (!scale.isFinite) {
    return kMapMinScale;
  }
  return scale.clamp(kMapMinScale, kMapMaxScale).toDouble();
}

/// Камера в допустимых пределах.
///
/// Середину экрана можно увести от середины карты на долю половины
/// размаха, равную `1 − 1 / масштаб`: при масштабе 1 — ни на сколько,
/// при большом — до самого края карты.
MapCamera clampCamera(MapCamera camera, MapExtent extent) {
  final double scale = clampMapScale(camera.scale);
  final double free = 1 - 1 / scale;
  final double dx = extent.halfWidth * free;
  final double dy = extent.halfHeight * free;
  final double cx = camera.cx.isFinite ? camera.cx : extent.cx;
  final double cy = camera.cy.isFinite ? camera.cy : extent.cy;
  return MapCamera(
    scale: scale,
    cx: cx.clamp(extent.cx - dx, extent.cx + dx).toDouble(),
    cy: cy.clamp(extent.cy - dy, extent.cy + dy).toDouble(),
  );
}

/// Наименьший просвет между соседними точками карты из [count] книг, в
/// единицах карты, — тот, до которого их раздвигает раскладка
/// ([kGapShare]).
double mapGap(int count) {
  return kGapShare / math.sqrt(count < 1 ? 1 : count);
}

/// Радиус точки неоткрытой книги при масштабе 1, в логических
/// пикселях: доля просвета между соседями, чтобы точки не слипались,
/// но не меньше [kStarMinRadius] и не больше [kStarBaseRadius].
double baseStarRadius({required int count, required double base}) {
  final double byGap = mapGap(count) * base * kStarGapShare;
  return byGap.clamp(kStarMinRadius, kStarBaseRadius).toDouble();
}

/// Радиус точки книги, в логических пикселях.
///
/// [share] — доля времени в этой книге от времени во всех книгах, от 0
/// до 1: площадь точки растёт с ней линейно, до [kStarAreaGain] раз
/// (решение владельца Э3 от 05.10.2026). [scale] — масштаб карты:
/// радиус растёт как корень из него, медленнее самого приближения
/// (ALG-MAP-13), и не больше чем в [kStarZoomGain] раз.
double starRadius({
  required double base,
  required double share,
  required double scale,
}) {
  final double safe = share.isFinite ? share.clamp(0.0, 1.0).toDouble() : 0.0;
  final double byTime = math.sqrt(1 + (kStarAreaGain - 1) * safe);
  final double byZoom = math.min(
    math.sqrt(clampMapScale(scale)),
    kStarZoomGain,
  );
  return base * byTime * byZoom;
}

/// Доли времени чтения по книгам: [times] — миллисекунды в каждой.
///
/// Пока не читали ни одну, все доли нулевые — точки одинаковы.
/// Отрицательное и нулевое время — ноль.
Map<String, double> timeShares(Map<String, int> times) {
  int total = 0;
  for (final int ms in times.values) {
    if (ms > 0) {
      total += ms;
    }
  }
  return <String, double>{
    for (final MapEntry<String, int> entry in times.entries)
      entry.key: total > 0 && entry.value > 0 ? entry.value / total : 0.0,
  };
}

/// Видны ли названия книг у точек: просвет между соседями на экране
/// не меньше [kTitleGap].
bool titlesShown({required int count, required double unit}) {
  return mapGap(count) * unit >= kTitleGap;
}

/// Хеш-решётка по координатам карты: по какой книге попало нажатие
/// (ALG-MAP-13).
class StarGrid {
  /// Раскладывает точки по ячейкам.
  ///
  /// Ячейка — шестьдесят четвёртая часть большей стороны размаха.
  StarGrid(List<double> xs, List<double> ys)
    : assert(xs.length == ys.length, 'у каждой точки две координаты'),
      _xs = List<double>.of(xs),
      _ys = List<double>.of(ys) {
    final MapExtent extent = MapExtent.of(xs, ys);
    _minX = extent.cx - extent.halfWidth;
    _minY = extent.cy - extent.halfHeight;
    _cell = math.max(extent.halfWidth, extent.halfHeight) * 2 / 64;
    for (int i = 0; i < _xs.length; i++) {
      _cells
          .putIfAbsent(_key(_column(_xs[i]), _row(_ys[i])), () => <int>[])
          .add(i);
    }
  }

  /// Больше стольких ячеек в каждую сторону решётка не обходит — точки
  /// перебираются подряд: на дальнем плане круг нажатия накрывает
  /// почти всю карту.
  static const int _maxReach = 6;

  final List<double> _xs;
  final List<double> _ys;
  final Map<int, List<int>> _cells = <int, List<int>>{};
  late final double _minX;
  late final double _minY;
  late final double _cell;

  /// Сколько точек в решётке.
  int get length => _xs.length;

  int _column(double x) => ((x - _minX) / _cell).floor();

  int _row(double y) => ((y - _minY) / _cell).floor();

  int _key(int column, int row) => column * 1048583 + row;

  /// Номер ближайшей к ([x], [y]) точки не дальше [radius] от неё — в
  /// единицах карты; `null` — рядом точек нет.
  ///
  /// [reach] — у каких точек круг попадания свой, больше [radius]:
  /// крупная точка ловит нажатие всей собой. Из равноудалённых
  /// выбирается точка с меньшим номером.
  int? nearest(double x, double y, double radius, {List<double>? reach}) {
    if (_xs.isEmpty || !x.isFinite || !y.isFinite || !(radius > 0)) {
      return null;
    }
    double widest = radius;
    if (reach != null) {
      for (final double own in reach) {
        widest = math.max(widest, own);
      }
    }
    final int span = (widest / _cell).ceil();
    int? best;
    double bestSquare = double.infinity;
    void consider(int index) {
      final double dx = _xs[index] - x;
      final double dy = _ys[index] - y;
      final double square = dx * dx + dy * dy;
      final double limit = reach == null
          ? radius
          : math.max(radius, reach[index]);
      if (square > limit * limit) {
        return;
      }
      if (square < bestSquare ||
          (square == bestSquare && (best == null || index < best!))) {
        best = index;
        bestSquare = square;
      }
    }

    if (span > _maxReach) {
      for (int i = 0; i < _xs.length; i++) {
        consider(i);
      }
      return best;
    }
    final int column = _column(x);
    final int row = _row(y);
    for (int c = column - span; c <= column + span; c++) {
      for (int r = row - span; r <= row + span; r++) {
        final List<int>? cell = _cells[_key(c, r)];
        if (cell == null) {
          continue;
        }
        for (final int index in cell) {
          consider(index);
        }
      }
    }
    return best;
  }
}

/// Подпись, которая просится на кадр: место и вес.
class LabelBox {
  /// Создаёт подпись.
  const LabelBox({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.weight,
  });

  /// Чья подпись — номер в списке того, кто просит.
  final int id;

  /// Левый край на экране.
  final double left;

  /// Верхний край на экране.
  final double top;

  /// Ширина.
  final double width;

  /// Высота.
  final double height;

  /// Вес: тяжёлая подпись встаёт раньше лёгкой.
  final double weight;

  /// Правый край.
  double get right => left + width;

  /// Нижний край.
  double get bottom => top + height;

  /// Пересекается ли с [other]; соприкосновение краями — не
  /// пересечение.
  bool overlaps(LabelBox other) {
    return left < other.right &&
        other.left < right &&
        top < other.bottom &&
        other.top < bottom;
  }
}

/// Отбирает подписи кадра (ALG-MAP-12): жадно по весу, без
/// пересечений, не больше [limit].
///
/// Подпись, которая не умещается в окне шириной [width] и высотой
/// [height] целиком, на кадр не встаёт: обрезанное название хуже
/// отсутствующего. При равном весе раньше встаёт та, что раньше в
/// списке. Порядок ответа — порядок отбора.
List<LabelBox> pickLabels(
  List<LabelBox> wanted, {
  required double width,
  required double height,
  int limit = kMaxLabels,
}) {
  final List<int> order = <int>[for (int i = 0; i < wanted.length; i++) i]
    ..sort((int a, int b) {
      final int byWeight = wanted[b].weight.compareTo(wanted[a].weight);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  final List<LabelBox> placed = <LabelBox>[];
  for (final int index in order) {
    if (placed.length >= limit) {
      break;
    }
    final LabelBox box = wanted[index];
    if (box.left < 0 ||
        box.top < 0 ||
        box.right > width ||
        box.bottom > height) {
      continue;
    }
    bool free = true;
    for (final LabelBox other in placed) {
      if (box.overlaps(other)) {
        free = false;
        break;
      }
    }
    if (free) {
      placed.add(box);
    }
  }
  return placed;
}
