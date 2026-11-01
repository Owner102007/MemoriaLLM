/// Созвездия карты: книги сами раскладываются по категориям адаптивным
/// резонансом (F-MAP-16, ALG-MAP-16).
///
/// Что это. Правило, которое решает, в какое созвездие встаёт книга.
/// Вход — строки BM25 книг (`map_vectors.dart`, `bm25Rows`), выход —
/// номер категории у каждой книги или −1 «без категории» (у книги нет
/// значимых слов).
///
/// Как устроено. Модель памяти «адаптивный резонанс» (ART; Carpenter,
/// Grossberg 1987; ART 2-A 1991) с поправкой проекта: проверка
/// бдительности относительная (D-029):
///
/// 1. **День** ([_artDay]) — книги приходят по одной. Каждая примеряется
///    к категориям от самой похожей; первая, что её «принимает»
///    (резонанс), забирает книгу; не принял никто — книга открывает
///    новую категорию.
/// 2. **Повтор** ([_consolidate]) — каждая книга выбирает категорию
///    заново, близкие категории сливаются ([_merge]); круги идут, пока
///    разбиение не перестанет меняться. После повтора разбиение не
///    зависит от того, в каком порядке книги пришли.
///
/// Кто зовёт: `book_map.dart` (`buildBookMap`). Кого зовёт: никого —
/// только арифметику.
///
/// Точность. Только сложение, вычитание, умножение, деление, корень и
/// сравнения; при равенстве решает меньший номер. Порядок сложений
/// записан циклами и повторён дословно во второй реализации
/// (`tool/make_map_goldens.py`): категории на телефоне и на ПК выходят
/// одни и те же до бита.
///
/// Эталон правила — `резонанс.py` шага 45 (описание проекта,
/// `Ответвления/…/Распределение по категориям/`). Понятия ART сверены с
/// AdaptiveResonanceLib (artlib, MIT) по разведке RS-01; код не копировался.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'map_vectors.dart';

/// Бдительность ρ: книга встаёт в категорию, если похожа на её книги не
/// меньше этой доли того, насколько они похожи между собой (D-029).
const double kArtVigilance = 0.6;

/// Нижняя граница φ: доля мерки библиотеки c₀, ниже которой книга не
/// встаёт никуда — рыхлая категория не принимает что попало.
const double kArtFloor = 0.4;

/// С какого числа книг у категории своя сплочённость; у меньшей вместо
/// неё — мерка библиотеки c₀.
const int kArtCohesionBooks = 3;

/// Сколько кругов в каждой из двух фаз повтора.
const int kArtRounds = 10;

/// Номер «без категории».
const int kNoCategory = -1;

/// Категории книг по их строкам BM25.
///
/// [rows] — строки единичной длины в порядке расчёта (по отпечатку
/// файла), [dimensions] — размер словаря корпуса. [order] — порядок, в
/// котором книги «приходят» днём (по умолчанию — порядок строк): после
/// повтора он на результат не влияет, параметр нужен тестам.
/// [pinned] — книги, которые читатель поставил сам: номер книги → его
/// группа. Такие книги остаются в своей категории, а их категория не
/// сливается с другими и не отдаёт книг (новые принимать может).
///
/// Возвращает номер категории у каждой книги: 0, 1, 2 … по первому
/// появлению в порядке строк; −1 — у книги без значимых слов.
List<int> artCategories(
  List<SparseRow> rows,
  int dimensions, {
  List<int>? order,
  Map<int, int> pinned = const <int, int>{},
}) {
  final int n = rows.length;
  final List<int> arrival = order ?? <int>[for (int i = 0; i < n; i++) i];
  final List<int> present = <int>[
    for (int i = 0; i < n; i++)
      if (rows[i].length > 0) i,
  ];
  // Меньше трёх книг со словами — делить нечего: одна категория.
  if (present.length < kArtCohesionBooks) {
    return <int>[
      for (int i = 0; i < n; i++) rows[i].length > 0 ? 0 : kNoCategory,
    ];
  }
  final double c0 = libraryMeasure(rows);
  final double floor = kArtFloor * c0;
  List<int> labels = _artDay(rows, arrival, c0, dimensions, floor).labels;
  // Книги, поставленные читателем: у каждой его группы — своя категория.
  final Set<int> held = <int>{};
  if (pinned.isNotEmpty) {
    int next = 0;
    for (final int label in labels) {
      if (label >= next) {
        next = label + 1;
      }
    }
    final Map<int, int> ofGroup = <int, int>{};
    for (int i = 0; i < n; i++) {
      final int? group = pinned[i];
      if (group == null || rows[i].length == 0) {
        continue;
      }
      labels[i] = ofGroup.putIfAbsent(group, () => next++);
      held.add(i);
    }
  }
  labels = _consolidate(rows, labels, c0, dimensions, arrival, held, floor);
  return _canon(labels);
}

/// Мерка библиотеки c₀: медиана косинуса книги с ближайшей другой книгой.
///
/// Книги без слов не считаются; при чётном числе книг — середина двух
/// средних. Меньше двух книг со словами — ноль.
double libraryMeasure(List<SparseRow> rows) {
  final List<int> present = <int>[
    for (int i = 0; i < rows.length; i++)
      if (rows[i].length > 0) i,
  ];
  if (present.length < 2) {
    return 0.0;
  }
  final List<double> best = <double>[];
  for (final int i in present) {
    double top = double.negativeInfinity;
    for (final int j in present) {
      if (i == j) {
        continue;
      }
      final double value = sparseDot(rows[i], rows[j]);
      if (value > top) {
        top = value;
      }
    }
    best.add(top);
  }
  best.sort();
  final int m = best.length;
  if (m.isOdd) {
    return best[m ~/ 2];
  }
  return (best[m ~/ 2 - 1] + best[m ~/ 2]) / 2.0;
}

/// Квадрат длины строки — сумма квадратов весов по порядку.
double _selfDot(SparseRow x) {
  double total = 0.0;
  for (int i = 0; i < x.length; i++) {
    total += x.weight[i] * x.weight[i];
  }
  return total;
}

/// Категории библиотеки: у каждой — сумма векторов её книг S, число книг
/// n и квадрат длины суммы |S|².
///
/// Векторы книг единичной длины, поэтому:
/// - похожесть книги на категорию c = x·S / n — средний косинус книги с
///   книгами категории;
/// - сплочённость категории q = (|S|² − n) / (n(n − 1)) — средний косинус
///   между её книгами (у категории меньше трёх книг — c₀).
class _Categories {
  _Categories(this.dimensions, this.c0, this.floor);

  final int dimensions;
  final double c0;
  final double floor;
  final List<Float64List> sums = <Float64List>[];
  final List<int> counts = <int>[];
  final List<double> squares = <double>[];

  int get length => counts.length;

  /// Сплочённость категории [j].
  double cohesion(int j) {
    final int n = counts[j];
    if (n < kArtCohesionBooks) {
      return c0;
    }
    return (squares[j] - n) / (n * (n - 1));
  }

  /// x·S для категории [j] — по словам книги, по порядку.
  double dot(int j, SparseRow x) {
    final Float64List sum = sums[j];
    double total = 0.0;
    for (int i = 0; i < x.length; i++) {
      total += sum[x.index[i]] * x.weight[i];
    }
    return total;
  }

  /// Книга [x] входит в категорию [j].
  void add(int j, SparseRow x) {
    // |S + x|² = |S|² + 2·x·S + |x|² — считается до того, как S изменится.
    squares[j] += 2.0 * dot(j, x) + _selfDot(x);
    final Float64List sum = sums[j];
    for (int i = 0; i < x.length; i++) {
      sum[x.index[i]] += x.weight[i];
    }
    counts[j]++;
  }

  /// Книга [x] открывает новую категорию; возвращает её номер.
  int open(SparseRow x) {
    final Float64List sum = Float64List(dimensions);
    for (int i = 0; i < x.length; i++) {
      sum[x.index[i]] = x.weight[i];
    }
    sums.add(sum);
    counts.add(1);
    squares.add(_selfDot(x));
    return counts.length - 1;
  }

  /// Категории по готовой разметке. [labels] должны быть приведены
  /// [_canon]: номера 0, 1, 2 … без пропусков.
  static _Categories of(
    List<SparseRow> rows,
    List<int> labels,
    int dimensions,
    double c0,
    double floor,
  ) {
    final _Categories out = _Categories(dimensions, c0, floor);
    int k = 0;
    for (final int label in labels) {
      if (label + 1 > k) {
        k = label + 1;
      }
    }
    for (int j = 0; j < k; j++) {
      out.sums.add(Float64List(dimensions));
      out.counts.add(0);
      out.squares.add(0.0);
    }
    for (int i = 0; i < rows.length; i++) {
      final int label = labels[i];
      if (label < 0) {
        continue;
      }
      final SparseRow x = rows[i];
      final Float64List sum = out.sums[label];
      for (int t = 0; t < x.length; t++) {
        sum[x.index[t]] += x.weight[t];
      }
      out.counts[label]++;
    }
    for (int j = 0; j < k; j++) {
      out.squares[j] = _denseDot(out.sums[j], out.sums[j]);
    }
    return out;
  }
}

/// Скалярное произведение двух плотных векторов по порядку координат.
double _denseDot(Float64List a, Float64List b) {
  double total = 0.0;
  for (int d = 0; d < a.length; d++) {
    total += a[d] * b[d];
  }
  return total;
}

/// Номера категорий по первому появлению: 0, 1, 2 …; −1 остаётся −1.
List<int> _canon(List<int> labels) {
  final Map<int, int> seen = <int, int>{};
  return <int>[
    for (final int label in labels)
      label < 0 ? kNoCategory : seen.putIfAbsent(label, () => seen.length),
  ];
}

/// Выбор категории для книги [x] — поиск, как в теории адаптивного
/// резонанса.
///
/// Категории перебираются от самой похожей (c по убыванию, при равенстве
/// — меньший номер); первая, где c ≥ ρ·q, принимает книгу. Ни одна —
/// `null`: книга открывает новую категорию. [own] — категория, где книга
/// уже стоит (при повторе): с ней книга сравнивается без себя самой, а
/// одна в категории — не сравнивается. [sticky] — книга остаётся в своей
/// категории, пока та её принимает.
int? _choose(_Categories cats, SparseRow x, {int? own, bool sticky = false}) {
  final int k = cats.length;
  if (k == 0) {
    return null;
  }
  final List<double> dots = <double>[
    for (int j = 0; j < k; j++) cats.dot(j, x),
  ];
  final List<double> c = <double>[
    for (int j = 0; j < k; j++) dots[j] / cats.counts[j],
  ];
  final List<double> q = <double>[for (int j = 0; j < k; j++) cats.cohesion(j)];
  int? skip;
  if (own != null) {
    final int m = cats.counts[own];
    if (m == 1) {
      skip = own;
    } else {
      // Без себя: из суммы вычитается сам вектор книги, x·x = 1.
      c[own] = (dots[own] - 1.0) / (m - 1);
      final int rest = m - 1;
      if (rest >= kArtCohesionBooks) {
        final double square = cats.squares[own] - 2.0 * dots[own] + 1.0;
        q[own] = (square - rest) / (rest * (rest - 1));
      } else {
        q[own] = cats.c0;
      }
    }
  }
  if (own != null && skip == null && sticky) {
    if (c[own] >= cats.floor &&
        q[own] > 0.0 &&
        c[own] >= kArtVigilance * q[own]) {
      return own;
    }
  }
  final List<int> byLikeness = <int>[for (int j = 0; j < k; j++) j]
    ..sort((int a, int b) {
      final int byC = c[b].compareTo(c[a]);
      return byC != 0 ? byC : a.compareTo(b);
    });
  for (final int j in byLikeness) {
    if (j == skip) {
      continue;
    }
    if (c[j] < cats.floor) {
      break;
    }
    if (q[j] > 0.0 && c[j] >= kArtVigilance * q[j]) {
      return j;
    }
  }
  return null;
}

/// Итог дня: разметка и категории, в которые она легла.
class _Day {
  _Day(this.labels, this.cats);

  final List<int> labels;
  final _Categories cats;
}

/// День: книги встраиваются по одной в порядке [order]. Книга без слов
/// категории не получает: −1.
_Day _artDay(
  List<SparseRow> rows,
  List<int> order,
  double c0,
  int dimensions,
  double floor,
) {
  final _Categories cats = _Categories(dimensions, c0, floor);
  final List<int> labels = List<int>.filled(rows.length, kNoCategory);
  for (final int i in order) {
    final SparseRow x = rows[i];
    if (x.length == 0) {
      continue;
    }
    final int? chosen = _choose(cats, x);
    if (chosen == null) {
      labels[i] = cats.open(x);
    } else {
      cats.add(chosen, x);
      labels[i] = chosen;
    }
  }
  return _Day(labels, cats);
}

/// Слияние категорий.
///
/// У пары резонанс r = c(A, B) / √(q(A)·q(B)), где c(A, B) =
/// S_A·S_B / (n_A·n_B) — средний косинус между их книгами. Сливается пара
/// с наибольшим r ≥ ρ (при равенстве — меньшие номера), затем перебор
/// заново. Категории с книгами из [heldBooks] не сливаются.
List<int> _merge(
  List<SparseRow> rows,
  List<int> rawLabels,
  double c0,
  int dimensions,
  Set<int> heldBooks,
  double floor,
) {
  final List<int> labels = _canon(rawLabels);
  final _Categories sch = _Categories.of(rows, labels, dimensions, c0, floor);
  final int k = sch.length;
  if (k < 2) {
    return labels;
  }
  final Set<int> held = <int>{
    for (final int i in heldBooks)
      if (labels[i] >= 0) labels[i],
  };
  final List<bool> alive = List<bool>.filled(k, true);
  final List<List<int>> members = <List<int>>[
    for (int j = 0; j < k; j++)
      <int>[
        for (int i = 0; i < labels.length; i++)
          if (labels[i] == j) i,
      ],
  ];
  final List<Float64List> g = <Float64List>[
    for (int a = 0; a < k; a++)
      Float64List.fromList(<double>[
        for (int b = 0; b < k; b++) _denseDot(sch.sums[a], sch.sums[b]),
      ]),
  ];
  while (true) {
    final List<int> live = <int>[
      for (int j = 0; j < k; j++)
        if (alive[j] && !held.contains(j)) j,
    ];
    final Map<int, double> q = <int, double>{
      for (final int j in live) j: sch.cohesion(j),
    };
    double? bestR;
    int bestA = -1;
    int bestB = -1;
    for (int ai = 0; ai < live.length; ai++) {
      final int a = live[ai];
      for (int bi = ai + 1; bi < live.length; bi++) {
        final int b = live[bi];
        final double cab = g[a][b] / (sch.counts[a] * sch.counts[b]);
        if (cab < floor || q[a]! * q[b]! <= 0.0) {
          continue;
        }
        final double r = cab / math.sqrt(q[a]! * q[b]!);
        if (r >= kArtVigilance && (bestR == null || r > bestR)) {
          bestR = r;
          bestA = a;
          bestB = b;
        }
      }
    }
    if (bestR == null) {
      break;
    }
    final Float64List sa = sch.sums[bestA];
    final Float64List sb = sch.sums[bestB];
    for (int d = 0; d < sa.length; d++) {
      sa[d] += sb[d];
    }
    sch.counts[bestA] += sch.counts[bestB];
    sch.squares[bestA] = _denseDot(sa, sa);
    members[bestA] = <int>[...members[bestA], ...members[bestB]]..sort();
    alive[bestB] = false;
    for (int j = 0; j < k; j++) {
      final double value = _denseDot(sch.sums[j], sa);
      g[bestA][j] = value;
      g[j][bestA] = value;
    }
  }
  final List<int> out = List<int>.of(labels);
  for (int j = 0; j < k; j++) {
    if (alive[j]) {
      for (final int i in members[j]) {
        out[i] = j;
      }
    }
  }
  return _canon(out);
}

/// Повтор: книги выбирают категории заново, близкие категории сливаются.
///
/// Круг: (1) каждая книга заново выбирает категорию по категориям начала
/// круга — со своей она сравнивается без себя; (2) книги, которых не
/// принимает ни одна категория, открывают новые между собой дневным
/// правилом в порядке [order]; (3) слияние. Книги из [pinned] остаются в
/// своей категории, а их категория не сливается и не теряет книг.
///
/// Две фазы: сначала до [kArtRounds] кругов, где книга берёт лучшую из
/// принимающих её категорий; не устоялось — ещё до [kArtRounds] кругов,
/// где книга остаётся в своей категории, пока та её принимает: книга на
/// стыке двух тем иначе переходила бы туда и обратно.
List<int> _consolidate(
  List<SparseRow> rows,
  List<int> start,
  double c0,
  int dimensions,
  List<int> order,
  Set<int> pinned,
  double floor,
) {
  List<int> labels = _canon(start);
  final int n = rows.length;
  for (final bool sticky in <bool>[false, true]) {
    for (int round = 0; round < kArtRounds; round++) {
      labels = _canon(labels);
      final _Categories sch = _Categories.of(
        rows,
        labels,
        dimensions,
        c0,
        floor,
      );
      final Set<int> held = <int>{
        for (final int i in pinned)
          if (labels[i] >= 0) labels[i],
      };
      final List<int> next = List<int>.of(labels);
      final List<int> low = <int>[];
      for (int i = 0; i < n; i++) {
        final SparseRow x = rows[i];
        if (x.length == 0 || pinned.contains(i) || held.contains(labels[i])) {
          continue;
        }
        final int? chosen = _choose(sch, x, own: labels[i], sticky: sticky);
        if (chosen == null) {
          low.add(i);
        } else {
          next[i] = chosen;
        }
      }
      if (low.isNotEmpty) {
        final Set<int> waiting = low.toSet();
        final _Day seeds = _artDay(
          rows,
          <int>[
            for (final int i in order)
              if (waiting.contains(i)) i,
          ],
          c0,
          dimensions,
          floor,
        );
        for (final int i in low) {
          next[i] = sch.length + seeds.labels[i];
        }
      }
      final List<int> merged = _merge(
        rows,
        next,
        c0,
        dimensions,
        pinned,
        floor,
      );
      if (_same(merged, labels)) {
        return labels;
      }
      labels = merged;
    }
  }
  return labels;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
