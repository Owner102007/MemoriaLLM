/// Созвездия карты: книги сами раскладываются по категориям адаптивным
/// резонансом (F-MAP-16, ALG-MAP-16).
///
/// Что это. Правило, которое решает, в какое созвездие встаёт книга.
/// Вход — матрица Грама книг: попарные косинусы их строк BM25
/// (`map_vectors.dart`, `gramOf`). Выход — номер созвездия у каждой книги
/// или −1 «без созвездия» (у книги нет значимых слов).
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
///    разбиение не перестанет меняться.
///
/// Почему через матрицу Грама. Категория — сумма векторов её книг S, но
/// хранить S незачем: всё, что правилу нужно, — скалярные произведения,
/// а они складываются из косинусов книг. x·S — сумма косинусов книги с
/// книгами категории, |S|² — сумма всех косинусов внутри категории. Так
/// расчёт не зависит от размера словаря (их десятки тысяч слов) и на 300
/// книгах занимает миллисекунды и сотни килобайт.
///
/// Кто зовёт: `book_map.dart` (`buildBookMap`). Кого зовёт: никого.
///
/// Точность. Только сложение, вычитание, умножение, деление, корень и
/// сравнения; при равенстве решает меньший номер. Порядок сложений
/// записан циклами и повторён дословно во второй реализации
/// (`tool/make_map_goldens.py`): созвездия на телефоне и на ПК выходят
/// одни и те же до бита.
///
/// Эталон правила — `резонанс.py` шага 45 (описание проекта,
/// `Ответвления/…/Распределение по категориям/`). Понятия ART сверены с
/// AdaptiveResonanceLib (artlib, MIT) по разведке RS-01; код не копировался.
library;

import 'dart:math' as math;
import 'dart:typed_data';

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

/// Номер «без созвездия».
const int kNoCategory = -1;

/// Итог правила: созвездие каждой книги и числа, по которым его сверяют
/// с другой реализацией.
class ArtResult {
  /// Создаёт итог.
  const ArtResult({
    required this.labels,
    required this.measure,
    required this.cohesions,
  });

  /// Созвездие каждой книги: 0, 1, 2 … по первому появлению; −1 — без
  /// созвездия.
  final List<int> labels;

  /// Мерка библиотеки c₀.
  final double measure;

  /// Сплочённость каждого созвездия q — дробные числа, на которых
  /// расхождение реализаций видно сразу, а не только на пороге.
  final List<double> cohesions;
}

/// Созвездия книг по матрице Грама [gram] (`n × n`, по строкам).
///
/// [order] — порядок, в котором книги «приходят» днём (по умолчанию —
/// порядок книг, то есть по отпечатку файла); параметр нужен тестам.
/// [pinned] — книги, которые читатель поставил сам: номер книги → его
/// группа. Такие книги остаются в своей категории, а их категория не
/// сливается с другими и не отдаёт книг (новые принимать может).
ArtResult artCategories(
  Float64List gram,
  int n, {
  List<int>? order,
  Map<int, int> pinned = const <int, int>{},
}) {
  final _Gram g = _Gram(gram, n);
  final List<int> arrival = order ?? <int>[for (int i = 0; i < n; i++) i];
  final List<int> present = <int>[
    for (int i = 0; i < n; i++)
      if (g.has(i)) i,
  ];
  final double c0 = libraryMeasure(gram, n);
  // Меньше трёх книг со словами — делить нечего: одно созвездие.
  if (present.length < kArtCohesionBooks) {
    final List<int> labels = <int>[
      for (int i = 0; i < n; i++) g.has(i) ? 0 : kNoCategory,
    ];
    return ArtResult(
      labels: labels,
      measure: c0,
      cohesions: _cohesionsOf(g, labels, c0),
    );
  }
  final double floor = kArtFloor * c0;
  List<int> labels = _artDay(g, arrival, c0, floor).labels;
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
      if (group == null || !g.has(i)) {
        continue;
      }
      labels[i] = ofGroup.putIfAbsent(group, () => next++);
      held.add(i);
    }
  }
  labels = _canon(_consolidate(g, labels, c0, arrival, held, floor));
  return ArtResult(
    labels: labels,
    measure: c0,
    cohesions: _cohesionsOf(g, labels, c0),
  );
}

/// Готовые созвездия, к которым примеряются новые книги (досадка,
/// ALG-MAP-08, D-049).
///
/// Новая книга встаёт в созвездие по тому же правилу, по какому книги
/// встают днём ([_choose]): от самого похожего, первое, где c ≥ ρ·q и
/// c ≥ φ·c₀. Созвездия от этого не меняются: каждая новая книга судится
/// по прежним, и порядок, в котором новые пришли, ничего не решает.
class ArtJoin {
  /// Созвездия по разметке [labels] (номера 0, 1, 2 … без пропусков,
  /// −1 — книга не в созвездии) поверх матрицы Грама [gram] (`n × n`);
  /// [c0] — мерка библиотеки.
  ArtJoin(Float64List gram, int n, List<int> labels, double c0)
    : _cats = _Categories.of(_Gram(gram, n), labels, c0, kArtFloor * c0);

  final _Categories _cats;

  /// Созвездие, которое принимает книгу [i]; `null` — ни одно.
  int? choose(int i) => _cats.g.has(i) ? _choose(_cats, i) : null;
}

/// Мерка библиотеки c₀: медиана косинуса книги с ближайшей другой книгой.
///
/// Книги без слов не считаются; при чётном числе книг — середина двух
/// средних. Меньше двух книг со словами — ноль.
double libraryMeasure(Float64List gram, int n) {
  final _Gram g = _Gram(gram, n);
  final List<int> present = <int>[
    for (int i = 0; i < n; i++)
      if (g.has(i)) i,
  ];
  if (present.length < 2) {
    return 0.0;
  }
  final List<double> best = <double>[];
  for (final int i in present) {
    double top = double.negativeInfinity;
    for (final int j in present) {
      if (i != j && g.at(i, j) > top) {
        top = g.at(i, j);
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

/// Матрица Грама с доступом по двум номерам.
class _Gram {
  _Gram(this.values, this.n);

  final Float64List values;
  final int n;

  double at(int i, int j) => values[i * n + j];

  /// Есть ли у книги значимые слова: её строка не пуста.
  bool has(int i) => values[i * n + i] > 0.0;
}

/// Категории библиотеки: у каждой — книги (по возрастанию номера), их
/// число n и квадрат длины суммы векторов |S|².
///
/// Векторы книг единичной длины, поэтому:
/// - похожесть книги на категорию c = x·S / n — средний косинус книги с
///   книгами категории;
/// - сплочённость категории q = (|S|² − n) / (n(n − 1)) — средний косинус
///   между её книгами (у категории меньше трёх книг — c₀).
class _Categories {
  _Categories(this.g, this.c0, this.floor);

  final _Gram g;
  final double c0;
  final double floor;
  final List<List<int>> members = <List<int>>[];
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

  /// x·S для книги [i] и категории [j] — сумма косинусов по книгам
  /// категории, по возрастанию номера.
  double dot(int j, int i) {
    double total = 0.0;
    for (final int m in members[j]) {
      total += g.at(i, m);
    }
    return total;
  }

  /// Книга [i] входит в категорию [j].
  void add(int j, int i) {
    // |S + x|² = |S|² + 2·x·S + |x|² — считается до того, как S изменится.
    squares[j] += 2.0 * dot(j, i) + g.at(i, i);
    final List<int> list = members[j];
    int at = list.length;
    while (at > 0 && list[at - 1] > i) {
      at--;
    }
    list.insert(at, i);
    counts[j]++;
  }

  /// Книга [i] открывает новую категорию; возвращает её номер.
  int open(int i) {
    members.add(<int>[i]);
    counts.add(1);
    squares.add(g.at(i, i));
    return counts.length - 1;
  }

  /// Категории по готовой разметке. [labels] должны быть приведены
  /// [_canon]: номера 0, 1, 2 … без пропусков.
  static _Categories of(_Gram g, List<int> labels, double c0, double floor) {
    final _Categories out = _Categories(g, c0, floor);
    int k = 0;
    for (final int label in labels) {
      if (label + 1 > k) {
        k = label + 1;
      }
    }
    for (int j = 0; j < k; j++) {
      out.members.add(<int>[]);
      out.counts.add(0);
      out.squares.add(0.0);
    }
    for (int i = 0; i < labels.length; i++) {
      if (labels[i] >= 0) {
        out.members[labels[i]].add(i);
        out.counts[labels[i]]++;
      }
    }
    for (int j = 0; j < k; j++) {
      out.squares[j] = _within(g, out.members[j], out.members[j]);
    }
    return out;
  }
}

/// S_A·S_B — сумма косинусов книг [a] с книгами [b]: внешний цикл по [a],
/// внутренний по [b], оба по возрастанию номера.
double _within(_Gram g, List<int> a, List<int> b) {
  double total = 0.0;
  for (final int i in a) {
    for (final int j in b) {
      total += g.at(i, j);
    }
  }
  return total;
}

/// Сплочённость каждого созвездия итоговой разметки.
List<double> _cohesionsOf(_Gram g, List<int> labels, double c0) {
  final _Categories cats = _Categories.of(g, labels, c0, 0.0);
  return <double>[for (int j = 0; j < cats.length; j++) cats.cohesion(j)];
}

/// Номера категорий по первому появлению: 0, 1, 2 …; −1 остаётся −1.
List<int> _canon(List<int> labels) {
  final Map<int, int> seen = <int, int>{};
  return <int>[
    for (final int label in labels)
      label < 0 ? kNoCategory : seen.putIfAbsent(label, () => seen.length),
  ];
}

/// Выбор категории для книги [i] — поиск, как в теории адаптивного
/// резонанса.
///
/// Категории перебираются от самой похожей (c по убыванию, при равенстве
/// — меньший номер); первая, где c ≥ ρ·q, принимает книгу. Ни одна —
/// `null`: книга открывает новую категорию. [own] — категория, где книга
/// уже стоит (при повторе): с ней книга сравнивается без себя самой, а
/// одна в категории — не сравнивается. [sticky] — книга остаётся в своей
/// категории, пока та её принимает.
int? _choose(_Categories cats, int i, {int? own, bool sticky = false}) {
  final int k = cats.length;
  if (k == 0) {
    return null;
  }
  final List<double> dots = <double>[
    for (int j = 0; j < k; j++) cats.dot(j, i),
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
      // Без себя: из суммы вычитается косинус книги с самой собой.
      final double self = cats.g.at(i, i);
      c[own] = (dots[own] - self) / (m - 1);
      final int rest = m - 1;
      if (rest >= kArtCohesionBooks) {
        final double square = cats.squares[own] - 2.0 * dots[own] + self;
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
_Day _artDay(_Gram g, List<int> order, double c0, double floor) {
  final _Categories cats = _Categories(g, c0, floor);
  final List<int> labels = List<int>.filled(g.n, kNoCategory);
  for (final int i in order) {
    if (!g.has(i)) {
      continue;
    }
    final int? chosen = _choose(cats, i);
    if (chosen == null) {
      labels[i] = cats.open(i);
    } else {
      cats.add(chosen, i);
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
///
/// Скалярные произведения сумм категорий считаются один раз; после
/// слияния B в A они обновляются сложением строк: (S_A+S_B)·S_j —
/// это S_A·S_j + S_B·S_j, без нового прохода по книгам.
List<int> _merge(
  _Gram g,
  List<int> rawLabels,
  double c0,
  Set<int> heldBooks,
  double floor,
) {
  final List<int> labels = _canon(rawLabels);
  final _Categories sch = _Categories.of(g, labels, c0, floor);
  final int k = sch.length;
  if (k < 2) {
    return labels;
  }
  final Set<int> held = <int>{
    for (final int i in heldBooks)
      if (labels[i] >= 0) labels[i],
  };
  final List<bool> alive = List<bool>.filled(k, true);
  final List<Float64List> cross = <Float64List>[
    for (int a = 0; a < k; a++)
      Float64List.fromList(<double>[
        for (int b = 0; b < k; b++)
          a == b ? sch.squares[a] : _within(g, sch.members[a], sch.members[b]),
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
        final double cab = cross[a][b] / (sch.counts[a] * sch.counts[b]);
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
    final int a = bestA;
    final int b = bestB;
    // |S_A + S_B|² = |S_A|² + 2·S_A·S_B + |S_B|².
    final double square = cross[a][a] + 2.0 * cross[a][b] + cross[b][b];
    for (int j = 0; j < k; j++) {
      if (j != a && j != b) {
        final double value = cross[a][j] + cross[b][j];
        cross[a][j] = value;
        cross[j][a] = value;
      }
    }
    cross[a][a] = square;
    sch.squares[a] = square;
    sch.counts[a] += sch.counts[b];
    sch.members[a] = <int>[...sch.members[a], ...sch.members[b]]..sort();
    alive[b] = false;
  }
  final List<int> out = List<int>.of(labels);
  for (int j = 0; j < k; j++) {
    if (alive[j]) {
      for (final int i in sch.members[j]) {
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
  _Gram g,
  List<int> start,
  double c0,
  List<int> order,
  Set<int> pinned,
  double floor,
) {
  List<int> labels = _canon(start);
  for (final bool sticky in <bool>[false, true]) {
    for (int round = 0; round < kArtRounds; round++) {
      labels = _canon(labels);
      final _Categories sch = _Categories.of(g, labels, c0, floor);
      final Set<int> held = <int>{
        for (final int i in pinned)
          if (labels[i] >= 0) labels[i],
      };
      final List<int> next = List<int>.of(labels);
      final List<int> low = <int>[];
      for (int i = 0; i < g.n; i++) {
        if (!g.has(i) || pinned.contains(i) || held.contains(labels[i])) {
          continue;
        }
        final int? chosen = _choose(sch, i, own: labels[i], sticky: sticky);
        if (chosen == null) {
          low.add(i);
        } else {
          next[i] = chosen;
        }
      }
      if (low.isNotEmpty) {
        final Set<int> waiting = low.toSet();
        final _Day seeds = _artDay(
          g,
          <int>[
            for (final int i in order)
              if (waiting.contains(i)) i,
          ],
          c0,
          floor,
        );
        for (final int i in low) {
          next[i] = sch.length + seeds.labels[i];
        }
      }
      final List<int> merged = _merge(g, next, c0, pinned, floor);
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
