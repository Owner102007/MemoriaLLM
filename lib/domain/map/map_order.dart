/// Порядок звёзд внутри созвездия — от типичной книги к особенной
/// (F-MAP-17, ALG-MAP-17, решения D-030 и D-044).
///
/// Раскладка (`map_layout.dart`) ставит группу книг в одно место карты,
/// но какая книга займёт какую звезду внутри группы, у неё выпадает
/// случайно и меняется от малой правки текста. Здесь это задаётся
/// правилом: группа сохраняет свою форму — то же множество точек, — а
/// книги пересаживаются по точкам. Самая типичная книга встаёт на
/// звезду, ближайшую к центру созвездия, самая особенная — на дальнюю.
///
/// Кто зовёт: `buildBookMap` (`book_map.dart`) — сразу после раскладки,
/// до отпечатка карты. Список созвездия «от типичной к особенной»
/// (по нажатию на имя, вкладка S59) берёт порядок из готовой карты —
/// [constellationOrder].
///
/// Арифметика — только + × ÷ √ и сравнения, как во всём расчёте
/// карты; эталон — `tool/make_map_goldens.py`, до бита.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'book_map.dart';
import 'map_layout.dart';

/// Типичность каждой книги в своей группе (ALG-MAP-17).
///
/// Типичность — косинус строки BM25 книги со средним строк её группы.
/// Строки единичные, поэтому косинус считается по матрице Грама
/// [gram] (`n × n`) без самих строк: если `s_i` — сумма `G[i][j]` по
/// книгам `j` группы, а `S` — сумма всех `s_i`, то косинус со средним
/// равен `s_i / √S` (деление на число книг сокращается). Складываем
/// по возрастанию номера книги — так же, как эталон на Python.
///
/// [labels] — группа каждой книги (номер созвездия, −1 — без
/// созвездия; это тоже группа). У группы, где ни у одной книги нет
/// слов, `S = 0` — типичность всех её книг 0.
Float64List typicalities(Float64List gram, int n, List<int> labels) {
  final Map<int, List<int>> members = _membersOf(labels);
  final Float64List result = Float64List(n);
  for (final List<int> group in members.values) {
    double total = 0.0;
    final Float64List sums = Float64List(group.length);
    for (int a = 0; a < group.length; a++) {
      double sum = 0.0;
      for (final int j in group) {
        sum += gram[group[a] * n + j];
      }
      sums[a] = sum;
      total += sum;
    }
    if (!(total > 0.0)) {
      continue;
    }
    final double length = math.sqrt(total);
    for (int a = 0; a < group.length; a++) {
      result[group[a]] = sums[a] / length;
    }
  }
  return result;
}

/// Пересаживает книги каждой группы по её же точкам (F-MAP-17).
///
/// Вход: места после раскладки [place], типичности [typical] (из
/// [typicalities]), группы [labels]. Номер книги — её место в списке,
/// отсортированном по отпечатку файла, как везде в расчёте карты.
///
/// Точки группы идут от центра группы к краю: по квадрату расстояния
/// до среднего точек группы, при равенстве — выше (`y` меньше), затем
/// левее. Книги — по убыванию типичности, при равной — по отпечатку
/// (меньший номер). k-я книга встаёт на k-ю точку. Возвращает новые
/// координаты; множество точек каждой группы то же.
MapCoordinates orderWithinGroups(
  MapCoordinates place,
  Float64List typical,
  List<int> labels,
) {
  final int n = labels.length;
  final Float64List xs = Float64List(n);
  final Float64List ys = Float64List(n);
  for (final List<int> group in _membersOf(labels).values) {
    final List<int> spots = _fromCenter(place.xs, place.ys, group);
    final List<int> books = List<int>.of(group)
      ..sort((int a, int b) {
        final int byTypical = _compare(typical[b], typical[a]);
        return byTypical != 0 ? byTypical : a.compareTo(b);
      });
    for (int k = 0; k < books.length; k++) {
      xs[books[k]] = place.xs[spots[k]];
      ys[books[k]] = place.ys[spots[k]];
    }
  }
  return MapCoordinates(xs, ys);
}

/// Книги созвездия [constellation] от типичной к особенной — для списка
/// по нажатию на имя созвездия (D-044).
///
/// Порядок читается с самой карты: на ней типичная книга стоит ближе
/// всех к центру созвездия (см. [orderWithinGroups]), так что новой
/// колонки в базе не нужно — сортировка точек от центра к краю даёт
/// тот же порядок. −1 — книги без созвездия.
List<MapPoint> constellationOrder(
  Iterable<MapPoint> points,
  int constellation,
) {
  final List<MapPoint> group = <MapPoint>[
    for (final MapPoint point in points)
      if (point.constellation == constellation) point,
  ]..sort((MapPoint a, MapPoint b) => a.key.compareTo(b.key));
  final Float64List xs = Float64List.fromList(<double>[
    for (final MapPoint point in group) point.x,
  ]);
  final Float64List ys = Float64List.fromList(<double>[
    for (final MapPoint point in group) point.y,
  ]);
  return <MapPoint>[
    for (final int i in _fromCenter(xs, ys, <int>[
      for (int i = 0; i < group.length; i++) i,
    ]))
      group[i],
  ];
}

/// Номера книг каждой группы, по возрастанию; группы — по возрастанию
/// номера (−1 первой). Порядок групп на результат не влияет, но так
/// обход один и тот же везде.
Map<int, List<int>> _membersOf(List<int> labels) {
  final Map<int, List<int>> members = <int, List<int>>{};
  final List<int> keys = labels.toSet().toList()..sort();
  for (final int key in keys) {
    members[key] = <int>[];
  }
  for (int i = 0; i < labels.length; i++) {
    members[labels[i]]!.add(i);
  }
  return members;
}

/// Точки [group] от центра группы к краю.
///
/// Центр — среднее точек (сумма по возрастанию номера, затем деление).
/// Квадрат расстояния, без корня: порядок тот же, а операций меньше.
/// При равном расстоянии — выше (`y` меньше), затем левее (`x` меньше),
/// затем меньший номер.
List<int> _fromCenter(Float64List xs, Float64List ys, List<int> group) {
  double sumX = 0.0;
  double sumY = 0.0;
  for (final int i in group) {
    sumX += xs[i];
    sumY += ys[i];
  }
  final double cx = sumX / group.length;
  final double cy = sumY / group.length;
  final Map<int, double> far = <int, double>{
    for (final int i in group)
      i: (xs[i] - cx) * (xs[i] - cx) + (ys[i] - cy) * (ys[i] - cy),
  };
  return List<int>.of(group)..sort((int a, int b) {
    int order = _compare(far[a]!, far[b]!);
    if (order != 0) return order;
    order = _compare(ys[a], ys[b]);
    if (order != 0) return order;
    order = _compare(xs[a], xs[b]);
    return order != 0 ? order : a.compareTo(b);
  });
}

/// Сравнение двух чисел знаками `<` и `>`.
///
/// Не `compareTo`: у него −0,0 меньше 0,0, а у Python (эталон) и у
/// знаков сравнения они равны — порядок разошёлся бы на нуле.
int _compare(double a, double b) => a < b ? -1 : (a > b ? 1 : 0);
