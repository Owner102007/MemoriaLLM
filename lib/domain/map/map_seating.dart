/// Досадка новых книг к готовой карте (ALG-MAP-08, F-MAP-04, D-049).
///
/// Что это. Читатель добавил книгу — карта не пересчитывается целиком:
/// прежние звёзды стоят ровно там, где стояли (сдвиг ноль), а новая
/// встаёт рядом с похожими на неё. Полный пересчёт — кнопкой
/// «Перестроить» или когда изменилось больше четверти книг
/// ([seatingFits]).
///
/// Как устроено — приём `transform` из umap-js (RS-01; взята идея, код
/// не копировался):
///
/// 1. Книги готовятся так же, как для полной карты ([MapGround]):
///    словарь, BM25, матрица Грама, главные компоненты — по всем книгам,
///    старым и новым.
/// 2. **Созвездие** новой книги — прежнее, если оно её принимает: книга
///    с надёжным текстом — по правилу резонанса ([ArtJoin], D-029),
///    с ненадёжным — по правилу сканов ([placeUnreliable], F-MAP-18).
///    Не принимает ни одно — книга без созвездия, «ждёт перестройки»
///    ([MapReason.awaiting]): новые созвездия заводит только полный
///    расчёт.
/// 3. **Место** — среднее мест её ближайших старых соседей по смыслу
///    (в своём созвездии, если оно есть), с весом сходства; плюс малый
///    сдвиг от отпечатка её файла — две одинаковые книги не встают в
///    одну точку.
/// 4. **Просвет**: раздвигаются только новые звёзды — от старых и друг
///    от друга, до того же наименьшего просвета, что у полной карты.
///
/// Кто зовёт: `application/map/map_builder.dart`. Арифметика — та же,
/// что у полной карты: + − × ÷ √ и сравнения; вторая реализация —
/// `seat` в `tool/make_map_goldens.py`, сверка до бита.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../library/stable_hash.dart';
import 'book_bag.dart';
import 'book_map.dart';
import 'exact_math.dart';
import 'map_categories.dart';
import 'map_layout.dart';
import 'map_trusted.dart';
import 'map_vectors.dart';

/// Во сколько раз книг на карте должно быть больше, чем изменившихся,
/// чтобы карта досаживалась, а не считалась заново: изменилось больше
/// четверти — пересчёт (D-049, ответ владельца на В-025).
const int kSeatShare = 4;

/// Можно ли досадить книги, а не считать карту заново (D-049).
///
/// [kept] — сколько книг сохраняют свои места, [changed] — сколько
/// новых или изменившихся. Старых звёзд должно быть не меньше
/// [kMinMapBooks] (иначе карты, к которой досаживать, по сути нет), а
/// изменившихся — не больше четверти всех.
bool seatingFits({required int kept, required int changed}) =>
    kept >= kMinMapBooks && changed * kSeatShare <= kept + changed;

/// Досаживает книги к готовой карте.
///
/// [bags] — мешки всех книг новой карты, в любом порядке; [kept] —
/// прежние места книг, которые свои места сохраняют: отпечаток файла →
/// точка. Книги из [bags], которых нет в [kept], — новые: им ищется
/// место. Точки [kept] переходят в карту как есть, до бита.
///
/// `null` — карты нет: книг меньше [kMinMapBooks] или больше
/// [kExactBooksLimit].
BookMap? seatBooks(List<BookBag> bags, Map<String, MapPoint> kept) {
  if (bags.length < kMinMapBooks || bags.length > kExactBooksLimit) {
    return null;
  }
  final MapGround ground = MapGround.of(bags);
  final List<BookBag> books = ground.books;
  final int n = books.length;
  final Float64List gram = ground.gram;
  final List<bool> old = <bool>[
    for (final BookBag book in books) kept.containsKey(book.key),
  ];

  final Set<int> building = ground.builders.toSet();
  // [was] — прежнее созвездие старой книги (−1 — без него или книга
  // новая): по нему ищутся соседи по месту. Принимают новую книгу только
  // книги, которые строят созвездия (F-MAP-18) и у которых есть слова, —
  // как при полном расчёте; их номера идут подряд — 0, 1, 2 … по первому
  // появлению ([labels]): так их ждут правила резонанса и сканов.
  // [original] — обратно, от номера подряд к прежнему.
  final List<int> was = List<int>.filled(n, kNoCategory);
  final List<int> labels = List<int>.filled(n, kNoCategory);
  final Map<int, int> canonOf = <int, int>{};
  final List<int> original = <int>[];
  final Map<int, String> names = <int, String>{};
  final Float64List xs = Float64List(n);
  final Float64List ys = Float64List(n);
  for (int i = 0; i < n; i++) {
    if (!old[i]) {
      continue;
    }
    final MapPoint point = kept[books[i].key]!;
    xs[i] = point.x;
    ys[i] = point.y;
    final int c = point.constellation;
    if (c < 0) {
      continue;
    }
    was[i] = c;
    names.putIfAbsent(c, () => point.name);
    if (building.contains(i) && gram[i * n + i] > 0.0) {
      labels[i] = canonOf.putIfAbsent(c, () {
        original.add(c);
        return original.length - 1;
      });
    }
  }

  final double c0 = _measureOf(ground);
  final ArtJoin join = ArtJoin(gram, n, labels, c0);
  final List<int> fresh = <int>[
    for (int i = 0; i < n; i++)
      if (!old[i]) i,
  ];
  // Созвездие новой книги — прежним номером; −1 — без созвездия.
  final List<int> joined = List<int>.filled(n, kNoCategory);
  final List<MapReason> reasons = List<MapReason>.filled(n, MapReason.none);
  final double gap = kGapShare / math.sqrt(n.toDouble());
  for (final int i in fresh) {
    final BookTrust trust = ground.trust[i];
    final bool words = gram[i * n + i] > 0.0;
    int? chosen;
    if (building.contains(i)) {
      // Строит созвездия — значит, и в чужое встаёт по правилу резонанса.
      // Сюда же книга «мало текста», когда надёжных книг меньше трёх и
      // строят все (`buildersOf`), — как при полном расчёте.
      if (words) {
        chosen = join.choose(i);
        if (chosen == null) {
          reasons[i] = MapReason.awaiting;
        }
      }
    } else if (trust.littleText) {
      reasons[i] = MapReason.littleText;
    } else if (words) {
      final int placed = placeUnreliable(
        gram,
        n,
        i,
        labels,
        c0,
        trust.trust ?? 0.0,
      );
      chosen = placed < 0 ? null : placed;
      if (chosen == null) {
        reasons[i] = MapReason.unsure;
      }
    }
    if (chosen != null) {
      joined[i] = original[chosen];
    }
    _spot(ground, i, old, was, joined[i], xs, ys);
    // Малый сдвиг от отпечатка файла: книга с теми же словами, что у
    // соседки, не встаёт в её точку, и сдвиг один на любом устройстве.
    final MapRandom random = MapRandom(stableHash(books[i].key));
    xs[i] += (random.unit() * 2.0 - 1.0) * gap * 0.5;
    ys[i] += (random.unit() * 2.0 - 1.0) * gap * 0.5;
  }
  _spreadFresh(xs, ys, old, fresh, gap);

  final List<MapPoint> points = <MapPoint>[
    for (int i = 0; i < n; i++)
      if (old[i])
        kept[books[i].key]!
      else
        MapPoint(
          key: books[i].key,
          x: _unitClamp(xs[i]),
          y: _unitClamp(ys[i]),
          constellation: joined[i],
          name: joined[i] < 0 ? '' : names[joined[i]]!,
          reason: reasons[i],
          seated: true,
        ),
  ];
  return BookMap(
    points: points,
    fingerprint: mapFingerprint(points),
    words: ground.vocabulary.terms.length,
    edges: edgesOf(ground.neighbours).length,
    groups: <int>{for (final MapPoint point in points) point.constellation}
        .length,
  );
}

/// Мерка библиотеки c₀ — по книгам, которые строят созвездия, как у
/// полного расчёта (`trustedCategories`).
double _measureOf(MapGround ground) {
  final int n = ground.books.length;
  final List<int> hi = ground.builders;
  if (hi.length == n) {
    return libraryMeasure(ground.gram, n);
  }
  final int m = hi.length;
  final Float64List sub = Float64List(m * m);
  for (int a = 0; a < m; a++) {
    for (int b = 0; b < m; b++) {
      sub[a * m + b] = ground.gram[hi[a] * n + hi[b]];
    }
  }
  return libraryMeasure(sub, m);
}

/// Место новой книги [i] — в [xs], [ys]: среднее мест её ближайших
/// старых соседей с весом сходства по смыслу.
///
/// Соседи — старые книги её созвездия [label] (прежний номер; у старых
/// книг он в [was]) или все старые, если созвездия нет; не больше
/// [kNeighbours], от самого похожего. Похожих
/// нет (у книги нет значимых слов) — середина её созвездия или всех
/// старых звёзд.
void _spot(
  MapGround ground,
  int i,
  List<bool> old,
  List<int> was,
  int label,
  Float64List xs,
  Float64List ys,
) {
  final int n = old.length;
  final Float64List sims = ground.neighbours.similarity;
  List<int> candidates = <int>[
    for (int j = 0; j < n; j++)
      if (old[j] && (label < 0 || was[j] == label)) j,
  ];
  if (candidates.isEmpty) {
    candidates = <int>[
      for (int j = 0; j < n; j++)
        if (old[j]) j,
    ];
  }
  final List<int> near = <int>[
    for (final int j in candidates)
      if (sims[i * n + j] > 0.0) j,
  ];
  near.sort((int a, int b) {
    final int bySim = sims[i * n + b].compareTo(sims[i * n + a]);
    return bySim != 0 ? bySim : a.compareTo(b);
  });
  final List<int> used = near.length > kNeighbours
      ? near.sublist(0, kNeighbours)
      : near;
  if (used.isNotEmpty) {
    double weight = 0.0;
    double x = 0.0;
    double y = 0.0;
    for (final int j in used) {
      final double w = sims[i * n + j];
      weight += w;
      x += w * xs[j];
      y += w * ys[j];
    }
    xs[i] = x / weight;
    ys[i] = y / weight;
    return;
  }
  double x = 0.0;
  double y = 0.0;
  for (final int j in candidates) {
    x += xs[j];
    y += ys[j];
  }
  xs[i] = x / candidates.length;
  ys[i] = y / candidates.length;
}

/// Раздвигает новые звёзды [fresh] до наименьшего просвета [gap]: от
/// старой звезды новая отходит сама, две новые расходятся поровну.
/// Старые не двигаются.
void _spreadFresh(
  Float64List xs,
  Float64List ys,
  List<bool> old,
  List<int> fresh,
  double gap,
) {
  final int n = xs.length;
  if (n > kSpreadLimit) {
    return;
  }
  for (int round = 0; round < kSpreadRounds; round++) {
    bool moved = false;
    for (final int i in fresh) {
      for (int j = 0; j < n; j++) {
        // Пара двух новых разводится один раз — когда первая меньше.
        if (j == i || (!old[j] && j < i)) {
          continue;
        }
        final double dx = xs[j] - xs[i];
        final double dy = ys[j] - ys[i];
        final double d2 = dx * dx + dy * dy;
        if (d2 >= gap * gap) {
          continue;
        }
        moved = true;
        double d = 0.0;
        double ux = 1.0;
        double uy = 0.0;
        if (d2 > 0.0) {
          d = math.sqrt(d2);
          ux = dx / d;
          uy = dy / d;
        }
        // Звезда не выходит за край карты (−1…1) сразу же: обрезка после
        // раздвигания снова сблизила бы звёзды у края.
        if (old[j]) {
          final double push = gap - d;
          xs[i] = _unitClamp(xs[i] - ux * push);
          ys[i] = _unitClamp(ys[i] - uy * push);
        } else {
          final double push = (gap - d) * 0.5;
          xs[i] = _unitClamp(xs[i] - ux * push);
          ys[i] = _unitClamp(ys[i] - uy * push);
          xs[j] = _unitClamp(xs[j] + ux * push);
          ys[j] = _unitClamp(ys[j] + uy * push);
        }
      }
    }
    if (!moved) {
      break;
    }
  }
}

/// Координата в пределах карты — от −1 до 1.
double _unitClamp(double value) {
  if (value > 1.0) {
    return 1.0;
  }
  if (value < -1.0) {
    return -1.0;
  }
  return value;
}
