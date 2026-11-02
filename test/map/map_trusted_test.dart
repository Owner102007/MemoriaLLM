/// Созвездия с учётом доверия тексту (F-MAP-18) на придуманных
/// матрицах Грама: кто строит созвездия, контраст, краевые случаи.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/map_categories.dart';
import 'package:memoria/domain/map/map_trusted.dart';

/// Матрица Грама двух тем по [perTopic] книг: внутри темы косинус
/// [inside], между темами [across]; дальше — книги [extra] со своими
/// косинусами к темам (`(к теме 0, к теме 1)`).
Float64List _gram(
  int perTopic, {
  double inside = 0.6,
  double across = 0.05,
  List<(double, double)> extra = const <(double, double)>[],
}) {
  final int base = 2 * perTopic;
  final int n = base + extra.length;
  final Float64List g = Float64List(n * n);
  int topicOf(int i) => i < perTopic ? 0 : 1;
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      double value;
      if (i == j) {
        value = 1.0;
      } else if (i < base && j < base) {
        value = topicOf(i) == topicOf(j) ? inside : across;
      } else if (i >= base && j >= base) {
        value = 0.02;
      } else {
        final int book = i >= base ? i : j;
        final int other = i >= base ? j : i;
        final (double, double) to = extra[book - base];
        value = topicOf(other) == 0 ? to.$1 : to.$2;
      }
      g[i * n + j] = value;
    }
  }
  return g;
}

void main() {
  test('F-MAP-18: книга с ненадёжным текстом не заводит категорию', () {
    // Шумная книга похожа на тему 0 слабо (0,2) — резонанс по
    // абсолютному сходству её бы отверг, и она открыла бы своё созвездие.
    final Float64List g = _gram(4, extra: <(double, double)>[(0.2, 0.03)]);
    final List<BookTrust> trust = <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.of(0.5),
    ];
    final List<int> plain = artCategories(g, 9).labels;
    expect(plain.toSet(), hasLength(3), reason: 'без доверия — своё созвездие');
    final TrustedCategories result = trustedCategories(g, 9, trust);
    expect(result.labels[8], result.labels[0]);
    expect(result.labels.toSet(), hasLength(2));
    expect(result.reasons[8], MapReason.none);
    expect(result.builders, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test('F-MAP-18: без явного контраста — «не уверены», без созвездия', () {
    // Одинаково близка к обеим темам: 0,2 и 0,18 — меньше чем в 1,5 раза.
    final Float64List g = _gram(4, extra: <(double, double)>[(0.2, 0.18)]);
    final TrustedCategories result = trustedCategories(g, 9, <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.of(0.6),
    ]);
    expect(result.labels[8], kNoCategory);
    expect(result.reasons[8], MapReason.unsure);
  });

  test('F-MAP-18: сходство ниже φ·c₀·T — без созвездия', () {
    // c₀ = 0,6 (ближайшая соседка в теме), φ = 0,4, T = 0,79: порог
    // 0,19; сходство 0,15 ниже, хотя контраст есть.
    final Float64List g = _gram(4, extra: <(double, double)>[(0.15, 0.01)]);
    final TrustedCategories result = trustedCategories(g, 9, <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.of(0.79),
    ]);
    expect(result.labels[8], kNoCategory);
    expect(result.reasons[8], MapReason.unsure);
  });

  test('F-MAP-18: скан без слоя — без категории, «мало надёжного текста»', () {
    // Слова названия похожи на тему 0 явно, но книга без надёжного
    // текста в созвездие не встаёт никогда: место на карте — да,
    // созвездие — нет.
    final Float64List g = _gram(4, extra: <(double, double)>[(0.5, 0.01)]);
    final TrustedCategories result = trustedCategories(g, 9, <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.littleText(),
    ]);
    expect(result.labels[8], kNoCategory);
    expect(result.reasons[8], MapReason.littleText);
  });

  test('F-MAP-18: сломанный слой — без категории', () {
    // Сломанный слой (чужая таблица букв): после отсева слов у книги
    // почти ничего общего ни с кем — сходство около нуля.
    final Float64List g = _gram(4, extra: <(double, double)>[(0.01, 0.01)]);
    final TrustedCategories result = trustedCategories(g, 9, <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.of(0.01),
    ]);
    expect(result.labels[8], kNoCategory);
    expect(result.labels.where((int l) => l >= 0).toSet(), hasLength(2));
  });

  test('F-MAP-18: шумный слой встаёт в свою категорию', () {
    // Слой с 5–10 % ошибок: сходство с темой ниже обычного (0,35 против
    // 0,6), но контраст явный.
    final Float64List g = _gram(
      4,
      extra: <(double, double)>[(0.35, 0.04), (0.03, 0.3)],
    );
    final TrustedCategories result = trustedCategories(g, 10, <BookTrust>[
      for (int i = 0; i < 8; i++) const BookTrust.asIs(),
      const BookTrust.of(0.7),
      const BookTrust.of(0.65),
    ]);
    expect(result.labels[8], result.labels[0]);
    expect(result.labels[9], result.labels[4]);
  });

  test('F-MAP-18: библиотека из сканов получает категории', () {
    // Надёжных книг две — меньше трёх: созвездия строят все, как без
    // доверия, причин нет.
    final Float64List g = _gram(3);
    final List<BookTrust> trust = <BookTrust>[
      const BookTrust.asIs(),
      const BookTrust.asIs(),
      for (int i = 0; i < 4; i++) const BookTrust.of(0.4),
    ];
    final TrustedCategories result = trustedCategories(g, 6, trust);
    expect(result.labels, artCategories(g, 6).labels);
    expect(result.reasons, everyElement(MapReason.none));
    expect(result.builders, hasLength(6));
  });

  test('F-MAP-18: одно созвездие — сравнивать не с чем, без созвездия', () {
    final Float64List g = _gram(
      2,
      across: 0.6,
      extra: <(double, double)>[(0.5, 0.5)],
    );
    final TrustedCategories result = trustedCategories(g, 5, <BookTrust>[
      for (int i = 0; i < 4; i++) const BookTrust.asIs(),
      const BookTrust.of(0.6),
    ]);
    expect(result.labels.take(4).toSet(), hasLength(1));
    expect(result.labels[4], kNoCategory);
    expect(result.reasons[4], MapReason.unsure);
  });
}
