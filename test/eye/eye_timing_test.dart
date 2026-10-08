import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_timing.dart';
import 'package:memoria/sno/eye/qpc_clock.dart';

/// SNO-ALG-EYE-03: сверка часов и признак «спутник молчит».
void main() {
  group('SNO-ALG-EYE-03: сверка часов', () {
    test('SNO-ALG-EYE-03: смещение — метка спутника минус середина', () {
      const SyncRound round = SyncRound(
        sentUs: 1000,
        eyeUs: 8345,
        receivedUs: 1200,
      );
      expect(round.rttUs, 200);
      expect(round.offsetUs, 7245);
    });

    test('SNO-ALG-EYE-03: берётся обмен с наименьшим временем ответа', () {
      final SyncResult result = SyncResult.best(const <SyncRound>[
        SyncRound(sentUs: 0, eyeUs: 900, receivedUs: 1000),
        SyncRound(sentUs: 2000, eyeUs: 7050, receivedUs: 2100),
        SyncRound(sentUs: 3000, eyeUs: 9000, receivedUs: 3100),
        SyncRound(sentUs: 5000, eyeUs: 0, receivedUs: 4000),
      ])!;
      // У второго и третьего время ответа одно — берётся первый из них;
      // обмен с ответом «раньше запроса» в счёт не идёт.
      expect(result.rttUs, 100);
      expect(result.offsetUs, 7050 - 2050);
      expect(result.atUs, 2050);
      expect(result.errorUs, 50);
      expect(result.rounds, 4);
      expect(SyncResult.best(const <SyncRound>[]), isNull);
    });

    test('SNO-ALG-EYE-03: тики QPC в микросекунды — без переполнения', () {
      // 10 МГц — обычная частота QPC на Windows 10 и 11.
      expect(qpcTicksToUs(10000000, 10000000), 1000000);
      expect(qpcTicksToUs(123456789, 10000000), 12345678);
      // Месяц работы ПК на частоте 3 ГГц: произведение тиков на миллион
      // не помещалось бы в 63 бита.
      const int month = 3000000000 * 60 * 60 * 24 * 30;
      expect(qpcTicksToUs(month, 3000000000), 60 * 60 * 24 * 30 * 1000000);
      expect(qpcTicksToUs(month + 2999, 3000000000), 2592000000000);
      expect(qpcTicksToUs(month + 3000, 3000000000), 2592000000001);
    });
  });

  group('SNO-ALG-EYE-03: спутник молчит', () {
    test('SNO-ALG-EYE-03: тики опаздывают на миллисекунды — молчание '
        'всё равно замечено', () {
      // Таймер Windows шагает по ~16 мс: тики приходят то на 1010-й,
      // то на 1995-й миллисекунде. Подвисанием это не считается.
      final SilenceWatch watch = SilenceWatch(0);
      const List<int> late = <int>[
        1016, 1995, 3020, 4001, 5016, 5998, 7031, 8000, 9016,
      ];
      for (final int at in late) {
        expect(watch.tick(at), isFalse, reason: '$at мс');
      }
      expect(watch.tick(10016), isTrue);
    });

    test('SNO-ALG-EYE-03: тик позже двух секунд — подвисание', () {
      final SilenceWatch watch = SilenceWatch(0);
      for (int s = 1; s <= 8; s++) {
        watch.tick(s * 1000);
      }
      // Между тиками 2001 мс: приложение стояло, ожидание — с начала.
      expect(watch.tick(10001), isFalse);
      for (int s = 11; s <= 19; s++) {
        expect(watch.tick(s * 1000 + 1), isFalse, reason: '$s с');
      }
      expect(watch.tick(20001), isTrue);
    });

    test('SNO-ALG-EYE-03: десять секунд без сердцебиения — молчит', () {
      final SilenceWatch watch = SilenceWatch(0);
      for (int s = 1; s < 10; s++) {
        expect(watch.tick(s * 1000), isFalse, reason: '$s с');
      }
      expect(watch.tick(10000), isTrue);
    });

    test('SNO-ALG-EYE-03: сердцебиение начинает ожидание заново', () {
      final SilenceWatch watch = SilenceWatch(0);
      for (int s = 1; s <= 9; s++) {
        watch.tick(s * 1000);
      }
      watch.beat(9500);
      expect(watch.tick(10000), isFalse);
      for (int s = 11; s <= 19; s++) {
        expect(watch.tick(s * 1000), isFalse, reason: '$s с');
      }
      expect(watch.tick(19500), isTrue);
    });

    test('SNO-ALG-EYE-03: подвисало приложение — молчание не в счёт', () {
      final SilenceWatch watch = SilenceWatch(0);
      for (int s = 1; s <= 5; s++) {
        expect(watch.tick(s * 1000), isFalse);
      }
      // Книга открывалась шесть секунд: таймер стоял, сердцебиения
      // лежат непрочитанными.
      expect(watch.tick(11000), isFalse);
      for (int s = 12; s <= 20; s++) {
        expect(watch.tick(s * 1000), isFalse, reason: '$s с');
      }
      expect(watch.tick(21000), isTrue);
    });
  });
}
