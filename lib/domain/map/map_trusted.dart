/// Созвездия с учётом доверия тексту (F-MAP-18, ALG-MAP-16 шаг 6,
/// ALG-MAP-19; шаг S58).
///
/// Книга с ненадёжным текстом (скан со шумным распознаванием, сломанный
/// слой, мало текста) не заводит созвездий: шум снижает её сходство со
/// всеми книгами почти поровну, и резонанс по абсолютному сходству её
/// отвергает — она открывала бы своё созвездие из одной книги.
///
/// Правило — перенос `categorize` и `place` из `устойчивость_46.py`
/// (шаг 46):
///
/// 1. Созвездия строит адаптивный резонанс (`map_categories.dart`) по
///    книгам с надёжным текстом.
/// 2. Книга с ненадёжным текстом встаёт в созвездие, к книгам которого
///    она в среднем ближе, чем к книгам любого другого, не меньше чем в
///    [kTrustContrast] раз (контраст — вторая половина «семейного
///    сходства», Rosch, Mervis, 1975), и не ниже нижней границы
///    резонанса φ·c₀, уменьшенной в меру её доверия T. Иначе — без
///    созвездия: «Не уверены — поставьте сами».
/// 3. Книга без надёжного текста — без созвездия: «Мало надёжного
///    текста»; место на карте ей дают слова названия и автора.
/// 4. Надёжных книг меньше трёх — созвездия строят все, как без доверия.
///
/// Кто зовёт: `book_map.dart` (`buildBookMap`). Арифметика — как у
/// резонанса: + × ÷ √ и сравнения; эталон — `tool/make_map_goldens.py`.
library;

import 'dart:typed_data';

import 'map_categories.dart';

/// Во сколько раз своё созвездие должно быть ближе соседнего (κ).
const double kTrustContrast = 1.5;

/// Меньше этого числа надёжных книг — созвездия строят все.
const int kMinTrustedBuilders = 3;

/// Почему книга без созвездия — для карточки книги.
enum MapReason {
  /// Причины нет: книга в созвездии или без слов вовсе.
  none,

  /// Надёжного текста нет: «Мало надёжного текста».
  littleText,

  /// Текст ненадёжен, и ни одно созвездие не ближе явно: «Не уверены —
  /// поставьте сами».
  unsure,

  /// Книгу досадили к готовой карте, и ни одно прежнее созвездие её не
  /// приняло (ALG-MAP-08, D-049): своё созвездие она получит, когда
  /// карту перестроят. Номер — по порядку: значения лежат в базе
  /// числом, новое — только в конец.
  awaiting,
}

/// Доверие тексту одной книги — вход правила.
class BookTrust {
  /// Текст не судили: книга идёт в резонанс как есть (нет словаря её
  /// языка или паспорта ещё нет).
  const BookTrust.asIs() : trust = null, littleText = false;

  /// Доверие T посчитано.
  const BookTrust.of(double this.trust) : littleText = false;

  /// Надёжного текста нет.
  const BookTrust.littleText() : trust = null, littleText = true;

  /// Доверие T; `null` — не судили или текста нет.
  final double? trust;

  /// Надёжного текста нет вовсе.
  final bool littleText;

  /// Книга не строит созвездий.
  bool get unreliable => littleText || (trust != null && trust! < 0.8);
}

/// Итог: созвездие и причина у каждой книги.
class TrustedCategories {
  /// Создаёт итог.
  const TrustedCategories({
    required this.labels,
    required this.reasons,
    required this.builders,
  });

  /// Созвездие каждой книги; −1 — без созвездия.
  final List<int> labels;

  /// Причина «без созвездия» у каждой книги.
  final List<MapReason> reasons;

  /// Номера книг, которые строили созвездия, по возрастанию.
  final List<int> builders;
}

/// Какие книги строят созвездия: все, кроме ненадёжных, — если таких
/// остаётся не меньше [kMinTrustedBuilders]; иначе все.
List<int> buildersOf(List<BookTrust> trust) {
  final List<int> hi = <int>[
    for (int i = 0; i < trust.length; i++)
      if (!trust[i].unreliable) i,
  ];
  if (hi.length < kMinTrustedBuilders) {
    return <int>[for (int i = 0; i < trust.length; i++) i];
  }
  return hi;
}

/// Созвездия по матрице Грама [gram] (`n × n`) с учётом доверия [trust].
TrustedCategories trustedCategories(
  Float64List gram,
  int n,
  List<BookTrust> trust,
) {
  final List<int> hi = buildersOf(trust);
  final List<int> labels = List<int>.filled(n, kNoCategory);
  final List<MapReason> reasons = List<MapReason>.filled(n, MapReason.none);
  if (hi.length == n) {
    final List<int> all = artCategories(gram, n).labels;
    return TrustedCategories(labels: all, reasons: reasons, builders: hi);
  }
  // Резонанс по надёжным книгам: своя матрица Грама — строки и столбцы
  // только их; мерка c₀ — тоже по ним.
  final int m = hi.length;
  final Float64List sub = Float64List(m * m);
  for (int a = 0; a < m; a++) {
    for (int b = 0; b < m; b++) {
      sub[a * m + b] = gram[hi[a] * n + hi[b]];
    }
  }
  final ArtResult art = artCategories(sub, m);
  for (int a = 0; a < m; a++) {
    labels[hi[a]] = art.labels[a];
  }
  final List<int> built = List<int>.of(labels);
  final Set<int> builders = hi.toSet();
  for (int i = 0; i < n; i++) {
    if (builders.contains(i)) continue;
    if (trust[i].littleText) {
      reasons[i] = MapReason.littleText;
      continue;
    }
    labels[i] = _place(gram, n, i, built, art.measure, trust[i].trust ?? 0);
    if (labels[i] == kNoCategory && gram[i * n + i] > 0.0) {
      reasons[i] = MapReason.unsure;
    }
  }
  return TrustedCategories(labels: labels, reasons: reasons, builders: hi);
}

/// Куда встаёт книга [i] с ненадёжным текстом — снаружи (досадка,
/// ALG-MAP-08): то же правило, что при полном расчёте. [built] —
/// созвездие каждой книги (−1 — не в созвездии), [trust] — доверие T.
int placeUnreliable(
  Float64List gram,
  int n,
  int i,
  List<int> built,
  double c0,
  double trust,
) => _place(gram, n, i, built, c0, trust);

/// Куда встаёт книга [i] с ненадёжным текстом (`place` шага 46).
///
/// Сходство с созвездием — средний косинус книги с его книгами (по
/// созвездиям, построенным надёжными книгами, [built]). Лучшее должно
/// быть не ниже φ·c₀·T и не меньше чем в κ раз больше второго; одно
/// созвездие — сравнивать не с чем: без созвездия.
int _place(
  Float64List gram,
  int n,
  int i,
  List<int> built,
  double c0,
  double trust,
) {
  if (!(gram[i * n + i] > 0.0)) return kNoCategory;
  final List<int> cats = <int>{
    for (final int label in built)
      if (label >= 0) label,
  }.toList()..sort();
  if (cats.isEmpty) return kNoCategory;
  final List<double> close = <double>[];
  for (final int c in cats) {
    double sum = 0.0;
    int count = 0;
    for (int j = 0; j < n; j++) {
      if (built[j] == c) {
        sum += gram[i * n + j];
        count++;
      }
    }
    close.add(sum / count);
  }
  // Лучшее и второе; при равенстве — меньший номер (сортировка
  // устойчива в шаге 46).
  int best = 0;
  for (int k = 1; k < cats.length; k++) {
    if (close[k] > close[best]) best = k;
  }
  if (cats.length == 1 || close[best] < kArtFloor * c0 * trust) {
    return kNoCategory;
  }
  int second = best == 0 ? 1 : 0;
  for (int k = 0; k < cats.length; k++) {
    if (k != best && close[k] > close[second]) second = k;
  }
  return close[best] >= kTrustContrast * close[second]
      ? cats[best]
      : kNoCategory;
}
