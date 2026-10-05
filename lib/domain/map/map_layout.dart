/// Раскладка книг на плоскости (ALG-MAP-06, ALG-MAP-07).
///
/// Близкие по смыслу книги стоят рядом, книги одной категории — одной
/// группой, а один и тот же набор книг даёт одну и ту же карту на любом
/// устройстве. Раскладка — в духе UMAP: притяжение по рёбрам соседей,
/// отталкивание случайной выборкой, шаг убывает линейно. К этому
/// добавлены три силы, без которых на библиотеке в несколько десятков
/// книг карта не читается:
///
/// - **притяжение к центру своей категории** (ALG-MAP-07) и ослабленные
///   рёбра между категориями: группа на карте — это категория полки
///   (решение владельца Э4 от 05.10.2026), и она обязана держаться
///   вместе, даже когда тексты двух категорий похожи;
/// - **тяготение к центру карты**: группы, между которыми нет рёбер,
///   отталкиваются без конца, и карта выходит из двух комков по углам;
/// - **наименьший просвет** между точками в самом конце: каждая книга
///   на карте — отдельная звезда, по которой можно попасть пальцем.
///
/// Арифметика точная (`exact_math.dart`), случайные числа — свои;
/// расчёт сверяется с `tool/make_map_goldens.py` до последнего бита.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'exact_math.dart';
import 'map_vectors.dart';

/// Сколько раз раскладка проходит по всем рёбрам.
const int kLayoutEpochs = 300;

/// Сколько случайных книг отталкивают книгу на каждое её ребро.
const int kLayoutNegatives = 5;

/// Сила притяжения книги к центру своей категории — «слабо».
///
/// Умножается на «единицу плюс сумму весов рёбер книги»: у книги с
/// двадцатью соседями одно ребро к центру с весом 0,3 не значило бы
/// ничего.
const double kCategoryPull = 0.3;

/// Во сколько раз ребро между книгами разных категорий слабее ребра
/// внутри категории.
const double kCrossWeight = 0.25;

/// Сила тяготения к центру карты.
const double kLayoutGravity = 0.2;

/// Наименьший просвет между точками — в долях `1 / √n`, где `n` —
/// число книг, а карта лежит в квадрате от −1 до 1.
const double kGapShare = 0.5;

/// Сколько раз точки раздвигаются до наименьшего просвета.
const int kSpreadRounds = 60;

/// Больше этого числа книг точки не раздвигаются: перебор пар стоит
/// квадрат от числа книг, а на тысячах книг звёзды разводит зум.
const int kSpreadLimit = 1500;

/// Зерно раскладки. Число — дата решения, а не подобранное значение.
const int kLayoutSeed = 20261005;

/// Размах начальной расстановки.
const double kInitialExtent = 10.0;

/// Начальный разброс точки — в долях размаха: без него две одинаковые
/// книги стоят в одной точке, и развести их нечем.
const double kLayoutJitter = 0.01;

/// Меньше этого числа книг карта не считается: из двух точек раскладки
/// не выходит.
const int kMinMapBooks = 3;

/// Координаты книг: `x` и `y` каждой, в квадрате от −1 до 1.
class MapCoordinates {
  /// Создаёт набор координат.
  const MapCoordinates(this.xs, this.ys);

  /// Абсциссы книг.
  final Float64List xs;

  /// Ординаты книг.
  final Float64List ys;

  /// Сколько книг.
  int get length => xs.length;
}

double _clip(double value) {
  if (value > 4.0) {
    return 4.0;
  }
  if (value < -4.0) {
    return -4.0;
  }
  return value;
}

/// Сдвигает точки так, чтобы их центр встал в ноль, и растягивает так,
/// чтобы самая дальняя координата стала равна [size].
void centerAndScale(Float64List xs, Float64List ys, double size) {
  final int n = xs.length;
  if (n == 0) {
    return;
  }
  double mx = 0.0;
  double my = 0.0;
  for (int i = 0; i < n; i++) {
    mx += xs[i];
    my += ys[i];
  }
  mx /= n;
  my /= n;
  double top = 0.0;
  for (int i = 0; i < n; i++) {
    xs[i] -= mx;
    ys[i] -= my;
    if (xs[i].abs() > top) {
      top = xs[i].abs();
    }
    if (ys[i].abs() > top) {
      top = ys[i].abs();
    }
  }
  if (top > 0.0) {
    for (int i = 0; i < n; i++) {
      xs[i] = xs[i] / top * size;
      ys[i] = ys[i] / top * size;
    }
  }
}

/// Раздвигает точки, стоящие ближе наименьшего просвета.
void spreadApart(Float64List xs, Float64List ys) {
  final int n = xs.length;
  if (n < 2 || n > kSpreadLimit) {
    return;
  }
  final double gap = kGapShare / math.sqrt(n.toDouble());
  for (int round = 0; round < kSpreadRounds; round++) {
    bool moved = false;
    for (int i = 0; i < n - 1; i++) {
      for (int j = i + 1; j < n; j++) {
        final double dx = xs[j] - xs[i];
        final double dy = ys[j] - ys[i];
        final double d2 = dx * dx + dy * dy;
        if (d2 >= gap * gap) {
          continue;
        }
        moved = true;
        final double push;
        final double ux;
        final double uy;
        if (d2 > 0.0) {
          final double d = math.sqrt(d2);
          push = (gap - d) * 0.5;
          ux = dx / d;
          uy = dy / d;
        } else {
          push = gap * 0.5;
          ux = 1.0;
          uy = 0.0;
        }
        xs[i] -= ux * push;
        ys[i] -= uy * push;
        xs[j] += ux * push;
        ys[j] += uy * push;
      }
    }
    if (!moved) {
      break;
    }
  }
}

/// Раскладывает книги на плоскости.
///
/// [rows] — книги в пространстве главных компонент, [edges] — рёбра
/// соседей, [groups] — группа каждой книги (название категории; пусто —
/// без категории). Порядок книг во всех трёх один и тот же, и от него
/// зависит результат: его задаёт тот, кто зовёт (`book_map.dart` —
/// по отпечатку файла).
MapCoordinates layoutBooks(
  LatentRows rows,
  MapEdges edges,
  List<String> groups, {
  int epochs = kLayoutEpochs,
}) {
  final int n = rows.count;
  final Float64List xs = Float64List(n);
  final Float64List ys = Float64List(n);
  if (n == 0) {
    return MapCoordinates(xs, ys);
  }
  final MapRandom random = MapRandom(kLayoutSeed);
  final int dims = rows.dimensions;
  // Первая компонента у неотрицательных векторов — общая для всех книг:
  // раскладке она ничего не говорит. Берутся вторая и третья.
  final int cx = dims > 1 ? 1 : 0;
  final int cy = cx + 1;
  for (int i = 0; i < n; i++) {
    if (dims > cx) {
      xs[i] = rows.at(i, cx);
    }
    if (dims > cy) {
      ys[i] = rows.at(i, cy);
    }
  }
  centerAndScale(xs, ys, kInitialExtent);
  for (int i = 0; i < n; i++) {
    xs[i] += (random.unit() * 2.0 - 1.0) * kLayoutJitter * kInitialExtent;
    ys[i] += (random.unit() * 2.0 - 1.0) * kLayoutJitter * kInitialExtent;
  }

  // Рёбра между категориями слабее рёбер внутри категории.
  final int edgeCount = edges.length;
  final Float64List weight = Float64List(edgeCount);
  final Float64List strength = Float64List(n);
  for (int e = 0; e < edgeCount; e++) {
    final int a = edges.from[e];
    final int b = edges.to[e];
    final double w = groups[a] == groups[b]
        ? edges.weight[e]
        : edges.weight[e] * kCrossWeight;
    weight[e] = w;
    strength[a] += w;
    strength[b] += w;
  }

  // Якорь книги — набор книг, к центру которых она тянется: своя
  // категория, если в ней хотя бы две книги; у книги без рёбер и без
  // такой категории — вся библиотека, иначе ей не от чего встать.
  final Map<String, List<int>> members = <String, List<int>>{};
  for (int i = 0; i < n; i++) {
    members.putIfAbsent(groups[i], () => <int>[]).add(i);
  }
  final List<List<int>> anchors = <List<int>>[];
  final Int32List anchor = Int32List(n);
  for (int i = 0; i < n; i++) {
    anchor[i] = -1;
  }
  final List<String> names = members.keys.toList()..sort();
  for (final String name in names) {
    final List<int> found = members[name]!;
    if (name.isNotEmpty && found.length >= 2) {
      anchors.add(found);
      for (final int i in found) {
        anchor[i] = anchors.length - 1;
      }
    }
  }
  int everyone = -1;
  for (int i = 0; i < n; i++) {
    if (anchor[i] < 0 && strength[i] == 0.0) {
      if (everyone < 0) {
        anchors.add(<int>[for (int k = 0; k < n; k++) k]);
        everyone = anchors.length - 1;
      }
      anchor[i] = everyone;
    }
  }
  final Float64List centreX = Float64List(anchors.length);
  final Float64List centreY = Float64List(anchors.length);

  for (int epoch = 0; epoch < epochs; epoch++) {
    final double alpha = 1.0 - epoch.toDouble() / epochs.toDouble();
    for (int e = 0; e < edgeCount; e++) {
      final double w = weight[e];
      for (int side = 0; side < 2; side++) {
        final int i = side == 0 ? edges.from[e] : edges.to[e];
        final int j = side == 0 ? edges.to[e] : edges.from[e];
        final double dx = xs[i] - xs[j];
        final double dy = ys[i] - ys[j];
        final double d2 = dx * dx + dy * dy;
        if (d2 > 0.0) {
          final double g = -2.0 / (1.0 + d2) * w;
          final double mx = _clip(g * dx) * alpha;
          final double my = _clip(g * dy) * alpha;
          xs[i] += mx;
          ys[i] += my;
          xs[j] -= mx;
          ys[j] -= my;
        }
        _repel(xs, ys, i, w, alpha, random);
      }
    }
    for (int a = 0; a < anchors.length; a++) {
      final List<int> found = anchors[a];
      double mx = 0.0;
      double my = 0.0;
      for (final int i in found) {
        mx += xs[i];
        my += ys[i];
      }
      centreX[a] = mx / found.length;
      centreY[a] = my / found.length;
    }
    for (int i = 0; i < n; i++) {
      final int a = anchor[i];
      if (a < 0) {
        continue;
      }
      final double w = kCategoryPull * (1.0 + strength[i]);
      final double dx = xs[i] - centreX[a];
      final double dy = ys[i] - centreY[a];
      final double d2 = dx * dx + dy * dy;
      final double g = -2.0 / (1.0 + d2) * w;
      xs[i] += _clip(g * dx) * alpha;
      ys[i] += _clip(g * dy) * alpha;
      _repel(xs, ys, i, kCategoryPull, alpha, random);
    }
    double mx = 0.0;
    double my = 0.0;
    for (int i = 0; i < n; i++) {
      mx += xs[i];
      my += ys[i];
    }
    mx /= n;
    my /= n;
    for (int i = 0; i < n; i++) {
      xs[i] -= _clip((xs[i] - mx) * kLayoutGravity) * alpha;
      ys[i] -= _clip((ys[i] - my) * kLayoutGravity) * alpha;
    }
  }
  centerAndScale(xs, ys, 1.0);
  spreadApart(xs, ys);
  centerAndScale(xs, ys, 1.0);
  return MapCoordinates(xs, ys);
}

/// Отталкивает книгу [i] от [kLayoutNegatives] случайных книг.
void _repel(
  Float64List xs,
  Float64List ys,
  int i,
  double w,
  double alpha,
  MapRandom random,
) {
  final int n = xs.length;
  for (int k = 0; k < kLayoutNegatives; k++) {
    final int c = random.below(n);
    if (c == i) {
      continue;
    }
    final double dx = xs[i] - xs[c];
    final double dy = ys[i] - ys[c];
    final double d2 = dx * dx + dy * dy;
    if (d2 > 0.0) {
      final double g = 2.0 / ((0.001 + d2) * (1.0 + d2)) * w;
      xs[i] += _clip(g * dx) * alpha;
      ys[i] += _clip(g * dy) * alpha;
    }
  }
}
