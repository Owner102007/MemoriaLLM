import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/exact_math.dart';

/// Эталон: посчитан `tool/make_map_goldens.py` — другой реализацией.
const String _goldenPath = 'test/goldens/book_map.json';

/// ALG-MAP-06: точная арифметика карты — свой генератор случайных
/// чисел и свой логарифм.
///
/// Обе функции обязаны давать одни и те же числа на любом устройстве:
/// на них стоит обещание «один набор книг — одна карта».
void main() {
  late Map<String, Object?> golden;

  setUpAll(() {
    golden = jsonDecode(
      File(_goldenPath).readAsStringSync(),
    ) as Map<String, Object?>;
  });

  group('ALG-MAP-06: генератор случайных чисел', () {
    test('ALG-MAP-06: первые числа совпадают с другой реализацией', () {
      final Map<String, Object?> expected =
          golden['random']! as Map<String, Object?>;
      final MapRandom random = MapRandom(expected['seed']! as int);
      final List<int> first = (expected['first']! as List<Object?>).cast<int>();
      expect(first.length, greaterThanOrEqualTo(8));
      expect(<int>[
        for (int i = 0; i < first.length; i++) random.next(),
      ], first);
    });

    test('ALG-MAP-06: известные значения Mulberry32 с зерном 1', () {
      // Те же три числа даёт исходная реализация на JavaScript.
      final MapRandom random = MapRandom(1);
      expect(random.next(), 2693262067);
      expect(random.next(), 11749833);
      expect(random.next(), 2265367787);
    });

    test('ALG-MAP-06: одно зерно — одна последовательность', () {
      final MapRandom a = MapRandom(20261005);
      final MapRandom b = MapRandom(20261005);
      for (int i = 0; i < 1000; i++) {
        expect(a.next(), b.next());
      }
    });

    test('ALG-MAP-06: числа лежат в своих границах', () {
      final MapRandom random = MapRandom(42);
      for (int i = 0; i < 2000; i++) {
        final int whole = random.next();
        expect(whole, inInclusiveRange(0, 0xFFFFFFFF));
        final double unit = random.unit();
        expect(unit, greaterThanOrEqualTo(0));
        expect(unit, lessThan(1));
        expect(random.below(7), inInclusiveRange(0, 6));
      }
    });
  });

  group('ALG-MAP-03: логарифм точными операциями', () {
    test('ALG-MAP-03: совпадает с другой реализацией до последнего бита', () {
      final List<Object?> pairs = golden['ln']! as List<Object?>;
      expect(pairs.length, greaterThanOrEqualTo(8));
      for (final Object? pair in pairs) {
        final List<Object?> values = pair! as List<Object?>;
        final double x = (values[0]! as num).toDouble();
        final double expected = (values[1]! as num).toDouble();
        expect(lnExact(x), expected, reason: 'ln($x)');
      }
    });

    test('ALG-MAP-03: расходится с библиотечным не больше чем на 1e-13', () {
      final MapRandom random = MapRandom(3);
      for (int i = 0; i < 500; i++) {
        // От тысячных до миллионов: в расчёте карты аргумент — от
        // единицы до числа книг.
        final double x = 0.001 + random.unit() * (i.isEven ? 3 : 2000000);
        final double scale = math.max(1, math.log(x).abs()).toDouble();
        expect(lnExact(x), closeTo(math.log(x), 1e-13 * scale), reason: '$x');
      }
    });

    test('ALG-MAP-03: единица даёт ноль, а негодный аргумент — тоже', () {
      expect(lnExact(1), 0);
      expect(lnExact(0), 0);
      expect(lnExact(-5), 0);
      expect(lnExact(double.infinity), 0);
      expect(lnExact(double.nan), 0);
    });
  });
}
