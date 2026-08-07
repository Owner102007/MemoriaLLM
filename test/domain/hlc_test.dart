import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/sync/hlc.dart';

void main() {
  group('Hlc', () {
    test('строка разбирается обратно без потерь', () {
      const Hlc source = Hlc(1786000000000, 42, 'abc123');
      expect(Hlc.parse(source.toString()), source);
    });

    test('счётчик записан четырьмя hex-знаками', () {
      const Hlc stamp = Hlc(0, 255, 'node');
      expect(stamp.toString(), endsWith('-00ff-node'));
    });

    test('время пишется в UTC', () {
      const Hlc stamp = Hlc(0, 0, 'node');
      expect(stamp.toString(), startsWith('1970-01-01T00:00:00.000Z'));
    });

    test('мусор не принимается за метку', () {
      expect(() => Hlc.parse('не метка'), throwsFormatException);
    });

    test('порядок: сначала время, потом счётчик, потом узел', () {
      const Hlc early = Hlc(10, 5, 'b');
      const Hlc later = Hlc(11, 0, 'a');
      const Hlc sameTime = Hlc(10, 6, 'a');
      const Hlc sameCounter = Hlc(10, 5, 'c');
      expect(early.compareTo(later), lessThan(0));
      expect(early.compareTo(sameTime), lessThan(0));
      expect(early.compareTo(sameCounter), lessThan(0));
    });

    test('часы стоят — растёт счётчик', () {
      const Hlc start = Hlc(100, 0, 'node');
      final Hlc next = start.issue(100);
      expect(next.millis, 100);
      expect(next.counter, 1);
    });

    test('часы ушли назад — метка всё равно растёт', () {
      const Hlc start = Hlc(100, 3, 'node');
      final Hlc next = start.issue(50);
      expect(next.compareTo(start), greaterThan(0));
      expect(next.millis, 100);
      expect(next.counter, 4);
    });

    test('часы ушли вперёд — счётчик обнуляется', () {
      const Hlc start = Hlc(100, 7, 'node');
      final Hlc next = start.issue(200);
      expect(next.millis, 200);
      expect(next.counter, 0);
    });

    test('приём метки из будущего подтягивает часы', () {
      const Hlc local = Hlc(100, 0, 'local');
      const Hlc remote = Hlc(500, 2, 'remote');
      final Hlc merged = local.receive(remote, 100);
      expect(merged.millis, 500);
      expect(merged.counter, 3);
      expect(merged.nodeId, 'local');
    });

    test('приём метки той же миллисекунды берёт больший счётчик', () {
      const Hlc local = Hlc(100, 1, 'local');
      const Hlc remote = Hlc(100, 9, 'remote');
      final Hlc merged = local.receive(remote, 100);
      expect(merged.millis, 100);
      expect(merged.counter, 10);
    });

    test('переполнение счётчика — ошибка, а не тихая порча меток', () {
      const Hlc full = Hlc(100, Hlc.maxCounter, 'node');
      expect(() => full.issue(100), throwsStateError);
    });
  });

  group('HlcClock', () {
    test('метки строго растут при стоящих часах', () {
      final HlcClock clock = HlcClock(
        nodeId: 'node',
        now: () => DateTime.utc(2026, 8, 7),
      );
      final Hlc first = clock.issue();
      final Hlc second = clock.issue();
      final Hlc third = clock.issue();
      expect(second.compareTo(first), greaterThan(0));
      expect(third.compareTo(second), greaterThan(0));
    });

    test('часы продолжают прошлый запуск, а не начинают заново', () {
      const Hlc stored = Hlc(9000000000000, 4, 'node');
      final HlcClock clock = HlcClock(
        nodeId: 'node',
        last: stored,
        now: () => DateTime.utc(2026, 8, 7),
      );
      expect(clock.issue().compareTo(stored), greaterThan(0));
    });

    test('о каждой выданной метке сообщается наружу', () {
      final List<Hlc> seen = <Hlc>[];
      final HlcClock clock = HlcClock(
        nodeId: 'node',
        now: () => DateTime.utc(2026, 8, 7),
        onIssued: seen.add,
      );
      clock.issue();
      clock.issue();
      expect(seen, hasLength(2));
      expect(seen.last, clock.last);
    });
  });

  group('generateNodeId', () {
    test('32 шестнадцатеричных знака без разделителей', () {
      final String id = generateNodeId(Random(1));
      expect(id, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });

    test('идентификатор попадает в метку и читается обратно', () {
      final String id = generateNodeId(Random(2));
      final Hlc stamp = Hlc(1786000000000, 1, id);
      expect(Hlc.parse(stamp.toString()).nodeId, id);
    });
  });
}
