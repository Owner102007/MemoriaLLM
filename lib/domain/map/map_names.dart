/// Имена созвездий карты: два слова, характерных для созвездия против
/// остальных (F-MAP-03, ALG-MAP-10).
///
/// Что это. Созвездия складывает сама система (`map_categories.dart`), и
/// у них нет названий, как у полок. Имя берётся из слов его книг —
/// «аневризма · сосуды».
///
/// Как устроено — c-TF-IDF, как в BERTopic (MIT; разведка RS-01):
/// 1. tf — сколько раз слово встретилось во всех книгах созвездия;
/// 2. доля слова tf / (все слова созвездия) умножается на
///    ln(1 + A / f), где f — счёт слова по всем созвездиям, A — среднее
///    число слов на созвездие. Частое везде слово («глава») получает
///    маленький множитель, частое только здесь — большой;
/// 3. два слова с наибольшим весом, при равенстве — раньше по словарю.
///
/// Слово показывается целым — в форме, которая чаще всего встретилась в
/// книге, где слово стоит больше всего раз ([BookBag.formAt]).
/// Одинаковые имена различаются номером: «… 2», «… 3».
///
/// Кто зовёт: `book_map.dart`. Точность — как у всей карты: логарифм свой
/// ([lnExact]), порядок сложений повторён в `tool/make_map_goldens.py`.
library;

import 'book_bag.dart';
import 'exact_math.dart';
import 'map_vectors.dart';

/// Имена созвездий по номерам: имя созвездия `k` — элемент `k`.
///
/// [bags] — мешки книг в порядке расчёта, [vocabulary] — словарь корпуса
/// (слова вне словаря в имя не идут), [labels] — созвездие каждой книги,
/// −1 — без созвездия.
List<String> constellationNames(
  List<BookBag> bags,
  MapVocabulary vocabulary,
  List<int> labels,
) {
  final Map<String, int> index = <String, int>{
    for (int i = 0; i < vocabulary.terms.length; i++) vocabulary.terms[i]: i,
  };
  int k = 0;
  for (final int label in labels) {
    if (label + 1 > k) {
      k = label + 1;
    }
  }
  final List<Map<int, int>> tf = <Map<int, int>>[
    for (int j = 0; j < k; j++) <int, int>{},
  ];
  // Слово → (счёт в лучшей книге, целая форма из неё).
  final List<Map<int, (int, String)>> form = <Map<int, (int, String)>>[
    for (int j = 0; j < k; j++) <int, (int, String)>{},
  ];
  final List<int> totals = List<int>.filled(k, 0);
  for (int b = 0; b < bags.length; b++) {
    final int label = labels[b];
    if (label < 0) {
      continue;
    }
    final BookBag bag = bags[b];
    for (int t = 0; t < bag.terms.length; t++) {
      final int? i = index[bag.terms[t]];
      if (i == null) {
        continue;
      }
      final int count = bag.counts[t];
      tf[label][i] = (tf[label][i] ?? 0) + count;
      totals[label] += count;
      final (int, String)? current = form[label][i];
      if (current == null || count > current.$1) {
        form[label][i] = (count, bag.formAt(t));
      }
    }
  }
  final Map<int, int> f = <int, int>{};
  for (int j = 0; j < k; j++) {
    for (final int i in tf[j].keys.toList()..sort()) {
      f[i] = (f[i] ?? 0) + tf[j][i]!;
    }
  }
  int totalAll = 0;
  for (final int value in totals) {
    totalAll += value;
  }
  final double average = k > 0 ? totalAll / k : 0.0;
  final List<String> names = <String>[];
  for (int j = 0; j < k; j++) {
    final List<(double, int)> scored = <(double, int)>[];
    for (final int i in tf[j].keys.toList()..sort()) {
      final double share = tf[j][i]! / totals[j];
      scored.add((share * lnExact(1.0 + average / f[i]!), i));
    }
    scored.sort(((double, int) a, (double, int) b) {
      final int byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });
    names.add(
      <String>[
        for (final (double, int) item in scored.take(2)) form[j][item.$2]!.$2,
      ].join(' · '),
    );
  }
  // Повтор имени получает номер; номер берётся такой, чтобы и с ним имя
  // не совпало ни с одним уже выданным.
  final Set<String> used = <String>{};
  final List<String> out = <String>[];
  for (final String name in names) {
    String candidate = name;
    int number = 2;
    while (used.contains(candidate)) {
      candidate = '$name $number';
      number++;
    }
    used.add(candidate);
    out.add(candidate);
  }
  return out;
}
