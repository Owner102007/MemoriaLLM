/// От слов книг к соседям по смыслу (ALG-MAP-02 … ALG-MAP-05).
///
/// Четыре шага, каждый — чистая функция:
///
/// 1. **Словарь корпуса** ([vocabularyOf]): какие слова значимы для
///    библиотеки в целом.
/// 2. **BM25** ([bm25Rows]): вес слова в книге с поправкой на длину
///    книги и редкость слова, строка нормирована к единичной длине.
/// 3. **Главные компоненты** ([latentRows]): матрица Грама и её
///    собственные векторы вращениями Якоби.
/// 4. **Соседи** ([neighboursOf], [edgesOf]): кто кому близок по
///    косинусу и какие рёбра из этого выходят.
///
/// Вся арифметика — точная (`exact_math.dart`), порядок сложений
/// записан циклами: расчёт сверяется с другой реализацией
/// (`tool/make_map_goldens.py`) до последнего бита, и карта на телефоне
/// и на ПК выходит одна.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'book_bag.dart';
import 'exact_math.dart';

/// Слово, которое стоит больше чем в стольких процентах книг, из
/// расчёта выбрасывается (ALG-MAP-02).
///
/// Стоп-слова не списком, а порогом: «Москва», «издательство», «глава»
/// стоят в каждой книге и ни одну не отличают. В плане стояло 40 %, но
/// на библиотеке из двух-трёх категорий это срезает словарь целой
/// категории: «артерия» и «сосуд» стоят в половине книг — во всей
/// «Ангиологии». Порог поднят, а слова, которые стоят в половине книг,
/// глушит вес BM25: чем слово чаще, тем он меньше.
const int kStopPercent = 85;

/// Слово, которое стоит меньше чем в стольких книгах, из расчёта
/// выбрасывается: оно не роднит книгу ни с какой другой.
const int kMinBooks = 2;

/// Насыщение частоты слова в BM25.
const double kBm25K1 = 1.2;

/// Поправка BM25 на длину книги.
const double kBm25B = 0.75;

/// Сколько главных компонент остаётся у книги (ALG-MAP-04).
const int kLatentDimensions = 48;

/// Сколько ближайших соседей у книги (ALG-MAP-05).
const int kNeighbours = 15;

/// Больше этого числа книг точное разложение не считается.
///
/// Вращения Якоби стоят куб от числа книг: на трёх сотнях это секунды,
/// на тысячах — минуты. Библиотеке в тысячи книг нужен рандомизированный
/// путь по разреженной матрице; он придёт вместе с картой основного
/// приложения (ALG-MAP-04).
const int kExactBooksLimit = 300;

/// Словарь корпуса: значимые слова и в скольких книгах стоит каждое.
class MapVocabulary {
  /// Создаёт словарь. [terms] стоят по возрастанию.
  const MapVocabulary({required this.terms, required this.bookCounts});

  /// Значимые слова по возрастанию.
  final List<String> terms;

  /// В скольких книгах стоит каждое из [terms].
  final List<int> bookCounts;
}

/// Словарь корпуса по мешкам книг (ALG-MAP-02).
///
/// Слово остаётся, если стоит хотя бы в [kMinBooks] книгах и не больше
/// чем в [kStopPercent] процентах книг.
MapVocabulary vocabularyOf(List<BookBag> bags) {
  final int n = bags.length;
  final Map<String, int> counts = <String, int>{};
  for (final BookBag bag in bags) {
    for (final String term in bag.terms) {
      counts[term] = (counts[term] ?? 0) + 1;
    }
  }
  final List<String> kept = <String>[
    for (final MapEntry<String, int> entry in counts.entries)
      if (entry.value >= kMinBooks && entry.value * 100 <= kStopPercent * n)
        entry.key,
  ]..sort();
  return MapVocabulary(
    terms: kept,
    bookCounts: <int>[for (final String term in kept) counts[term]!],
  );
}

/// Разреженная строка: номера слов по возрастанию и их веса.
class SparseRow {
  /// Создаёт строку.
  const SparseRow(this.index, this.weight);

  /// Номера слов словаря, по возрастанию.
  final Int32List index;

  /// Веса слов — в пару к [index].
  final Float64List weight;

  /// Сколько слов в строке.
  int get length => index.length;
}

/// Веса BM25 по книгам, каждая строка — единичной длины (ALG-MAP-03).
///
/// Книга, в которой значимых слов нет вовсе, получает пустую строку.
List<SparseRow> bm25Rows(List<BookBag> bags, MapVocabulary vocabulary) {
  final int n = bags.length;
  final Map<String, int> place = <String, int>{
    for (int i = 0; i < vocabulary.terms.length; i++) vocabulary.terms[i]: i,
  };
  int total = 0;
  for (final BookBag bag in bags) {
    total += bag.length;
  }
  final double average = n > 0 ? total / n : 0.0;
  final Float64List idf = Float64List(vocabulary.terms.length);
  for (int i = 0; i < idf.length; i++) {
    final int books = vocabulary.bookCounts[i];
    idf[i] = lnExact(1.0 + (n - books + 0.5) / (books + 0.5));
  }
  final List<SparseRow> rows = <SparseRow>[];
  for (final BookBag bag in bags) {
    final double scale = average > 0.0
        ? 1.0 - kBm25B + kBm25B * (bag.length / average)
        : 1.0;
    final List<int> index = <int>[];
    final List<double> weight = <double>[];
    for (int t = 0; t < bag.terms.length; t++) {
      final int? i = place[bag.terms[t]];
      if (i == null) {
        continue;
      }
      final double tf = bag.counts[t].toDouble();
      index.add(i);
      weight.add(idf[i] * tf * (kBm25K1 + 1.0) / (tf + kBm25K1 * scale));
    }
    rows.add(_unitRow(index, weight));
  }
  return rows;
}

/// Строка по возрастанию номеров, нормированная к единичной длине.
SparseRow _unitRow(List<int> index, List<double> weight) {
  final List<int> order = <int>[for (int i = 0; i < index.length; i++) i];
  bool sorted = true;
  for (int i = 1; i < index.length; i++) {
    if (index[i - 1] > index[i]) {
      sorted = false;
      break;
    }
  }
  if (!sorted) {
    order.sort((int a, int b) => index[a].compareTo(index[b]));
  }
  final Int32List outIndex = Int32List(order.length);
  final Float64List outWeight = Float64List(order.length);
  double square = 0.0;
  for (int i = 0; i < order.length; i++) {
    outIndex[i] = index[order[i]];
    outWeight[i] = weight[order[i]];
    square += outWeight[i] * outWeight[i];
  }
  if (square > 0.0) {
    final double root = math.sqrt(square);
    for (int i = 0; i < outWeight.length; i++) {
      outWeight[i] = outWeight[i] / root;
    }
  }
  return SparseRow(outIndex, outWeight);
}

/// Скалярное произведение двух разреженных строк.
double sparseDot(SparseRow a, SparseRow b) {
  int i = 0;
  int j = 0;
  double total = 0.0;
  while (i < a.length && j < b.length) {
    final int left = a.index[i];
    final int right = b.index[j];
    if (left == right) {
      total += a.weight[i] * b.weight[j];
      i++;
      j++;
    } else if (left < right) {
      i++;
    } else {
      j++;
    }
  }
  return total;
}

/// Матрица Грама строк: `n × n`, по строкам.
Float64List gramOf(List<SparseRow> rows) {
  final int n = rows.length;
  final Float64List gram = Float64List(n * n);
  for (int i = 0; i < n; i++) {
    for (int j = i; j < n; j++) {
      final double value = sparseDot(rows[i], rows[j]);
      gram[i * n + j] = value;
      gram[j * n + i] = value;
    }
  }
  return gram;
}

/// Собственные значения и векторы симметричной матрицы.
class EigenSystem {
  /// Создаёт разложение.
  const EigenSystem({required this.values, required this.vectors});

  /// Собственные значения, в порядке столбцов [vectors].
  final Float64List values;

  /// Собственные векторы столбцами: `n × n`, по строкам.
  final Float64List vectors;
}

/// Разложение симметричной матрицы [matrix] (`n × n`, по строкам)
/// циклическими вращениями Якоби.
///
/// Метод выбран не за скорость, а за то, что в нём одни точные
/// операции и порядок действий задан жёстко: два устройства получают
/// одни и те же числа.
EigenSystem jacobiEigen(
  Float64List matrix,
  int n, {
  int maxSweeps = 60,
  double tolerance = 1e-24,
}) {
  final Float64List a = Float64List.fromList(matrix);
  final Float64List v = Float64List(n * n);
  for (int i = 0; i < n; i++) {
    v[i * n + i] = 1.0;
  }
  for (int sweep = 0; sweep < maxSweeps; sweep++) {
    double off = 0.0;
    double total = 0.0;
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final double square = a[i * n + j] * a[i * n + j];
        total += square;
        if (i != j) {
          off += square;
        }
      }
    }
    if (off <= tolerance * total) {
      break;
    }
    for (int p = 0; p < n - 1; p++) {
      for (int q = p + 1; q < n; q++) {
        final double apq = a[p * n + q];
        if (apq == 0.0) {
          continue;
        }
        final double theta = (a[q * n + q] - a[p * n + p]) / (2.0 * apq);
        final double t = theta >= 0.0
            ? 1.0 / (theta + math.sqrt(theta * theta + 1.0))
            : -1.0 / (-theta + math.sqrt(theta * theta + 1.0));
        final double c = 1.0 / math.sqrt(t * t + 1.0);
        final double s = t * c;
        for (int k = 0; k < n; k++) {
          final double akp = a[k * n + p];
          final double akq = a[k * n + q];
          a[k * n + p] = c * akp - s * akq;
          a[k * n + q] = s * akp + c * akq;
        }
        for (int k = 0; k < n; k++) {
          final double apk = a[p * n + k];
          final double aqk = a[q * n + k];
          a[p * n + k] = c * apk - s * aqk;
          a[q * n + k] = s * apk + c * aqk;
        }
        for (int k = 0; k < n; k++) {
          final double vkp = v[k * n + p];
          final double vkq = v[k * n + q];
          v[k * n + p] = c * vkp - s * vkq;
          v[k * n + q] = s * vkp + c * vkq;
        }
      }
    }
  }
  final Float64List values = Float64List(n);
  for (int i = 0; i < n; i++) {
    values[i] = a[i * n + i];
  }
  return EigenSystem(values: values, vectors: v);
}

/// Книги в пространстве главных компонент.
class LatentRows {
  /// Создаёт набор строк.
  const LatentRows({
    required this.count,
    required this.dimensions,
    required this.cells,
    required this.values,
  });

  /// Сколько книг.
  final int count;

  /// Сколько компонент у каждой.
  final int dimensions;

  /// Координаты: `count × dimensions`, по строкам.
  final Float64List cells;

  /// Собственные значения оставленных компонент, по убыванию.
  final Float64List values;

  /// Координата книги [row] по компоненте [column].
  double at(int row, int column) => cells[row * dimensions + column];
}

/// Главные компоненты по матрице Грама [gram] (ALG-MAP-04).
///
/// Остаётся не больше [kLatentDimensions] компонент и не больше чем
/// «книг минус одна». Знак компоненты выбирается так, чтобы её самая
/// большая по модулю координата была положительной: у собственного
/// вектора знака нет, а карте нужен один и тот же.
LatentRows latentRows(Float64List gram, int n) {
  final EigenSystem system = jacobiEigen(gram, n);
  final List<int> order = <int>[for (int i = 0; i < n; i++) i]
    ..sort((int a, int b) {
      final int byValue = system.values[b].compareTo(system.values[a]);
      return byValue != 0 ? byValue : a.compareTo(b);
    });
  final int limit = math.min(kLatentDimensions, n - 1);
  final List<int> columns = <int>[
    for (int i = 0; i < limit; i++)
      if (system.values[order[i]] > 1e-12) order[i],
  ];
  final int dimensions = columns.length;
  final Float64List cells = Float64List(n * dimensions);
  final Float64List values = Float64List(dimensions);
  for (int place = 0; place < dimensions; place++) {
    final int c = columns[place];
    int best = 0;
    for (int i = 1; i < n; i++) {
      if (system.vectors[i * n + c].abs() >
          system.vectors[best * n + c].abs()) {
        best = i;
      }
    }
    final double sign = system.vectors[best * n + c] < 0.0 ? -1.0 : 1.0;
    final double root = math.sqrt(system.values[c]);
    values[place] = system.values[c];
    for (int i = 0; i < n; i++) {
      cells[i * dimensions + place] = sign * system.vectors[i * n + c] * root;
    }
  }
  return LatentRows(
    count: n,
    dimensions: dimensions,
    cells: cells,
    values: values,
  );
}

/// Соседи книг и сходство каждой пары.
class Neighbours {
  /// Создаёт набор.
  const Neighbours({required this.near, required this.similarity});

  /// Ближайшие соседи каждой книги, от самого близкого.
  final List<List<int>> near;

  /// Косинусное сходство пар: `n × n`, по строкам.
  final Float64List similarity;
}

/// Ближайшие соседи по косинусу (ALG-MAP-05): точный перебор.
///
/// У книги не больше [kNeighbours] соседей, и только с положительным
/// сходством. Книга без значимых слов соседей не имеет.
Neighbours neighboursOf(LatentRows rows) {
  final int n = rows.count;
  final int d = rows.dimensions;
  final Float64List unit = Float64List(n * d);
  final List<bool> empty = List<bool>.filled(n, true);
  for (int i = 0; i < n; i++) {
    double square = 0.0;
    for (int k = 0; k < d; k++) {
      final double value = rows.cells[i * d + k];
      square += value * value;
    }
    if (square > 1e-24) {
      final double root = math.sqrt(square);
      for (int k = 0; k < d; k++) {
        unit[i * d + k] = rows.cells[i * d + k] / root;
      }
      empty[i] = false;
    }
  }
  final Float64List sims = Float64List(n * n);
  for (int i = 0; i < n; i++) {
    if (empty[i]) {
      continue;
    }
    for (int j = i + 1; j < n; j++) {
      if (empty[j]) {
        continue;
      }
      double total = 0.0;
      for (int k = 0; k < d; k++) {
        total += unit[i * d + k] * unit[j * d + k];
      }
      sims[i * n + j] = total;
      sims[j * n + i] = total;
    }
  }
  final int limit = math.min(kNeighbours, n - 1);
  final List<List<int>> near = <List<int>>[];
  for (int i = 0; i < n; i++) {
    final List<int> found = <int>[
      for (int j = 0; j < n; j++)
        if (j != i && sims[i * n + j] > 0.0) j,
    ];
    found.sort((int a, int b) {
      final int bySim = sims[i * n + b].compareTo(sims[i * n + a]);
      return bySim != 0 ? bySim : a.compareTo(b);
    });
    near.add(found.length > limit ? found.sublist(0, limit) : found);
  }
  return Neighbours(near: near, similarity: sims);
}

/// Рёбра раскладки: пары книг и вес каждой.
class MapEdges {
  /// Создаёт набор рёбер.
  const MapEdges({required this.from, required this.to, required this.weight});

  /// Первая книга ребра; её номер меньше.
  final Int32List from;

  /// Вторая книга ребра.
  final Int32List to;

  /// Вес ребра от нуля до единицы.
  final Float64List weight;

  /// Сколько рёбер.
  int get length => from.length;
}

/// Рёбра по соседям: пара связана, если хотя бы одна книга числит
/// другую соседом. Вес — сходство пары, поделённое на самое большое.
MapEdges edgesOf(Neighbours neighbours) {
  final int n = neighbours.near.length;
  final List<Set<int>> sets = <Set<int>>[
    for (final List<int> found in neighbours.near) found.toSet(),
  ];
  final List<int> from = <int>[];
  final List<int> to = <int>[];
  final List<double> weight = <double>[];
  double top = 0.0;
  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      if (sets[i].contains(j) || sets[j].contains(i)) {
        final double value = neighbours.similarity[i * n + j];
        from.add(i);
        to.add(j);
        weight.add(value);
        if (value > top) {
          top = value;
        }
      }
    }
  }
  final Float64List scaled = Float64List(weight.length);
  for (int i = 0; i < weight.length; i++) {
    scaled[i] = top > 0.0 ? weight[i] / top : weight[i];
  }
  return MapEdges(
    from: Int32List.fromList(from),
    to: Int32List.fromList(to),
    weight: scaled,
  );
}
