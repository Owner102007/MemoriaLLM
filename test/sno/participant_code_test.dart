import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';

/// SNO-ALG-CFG-03: процедурный код участника.
///
/// Эталонные значения посчитаны другой реализацией — `hashlib` из
/// Python: свой же код в тесте проверял бы себя своими ошибками.
void main() {
  const String node = 'a91f3c0b';
  const int moment = 1793612000111;

  /// Код из семёрки: с контрольной цифрой.
  String withCheck(String base) => '$base${dammCheckDigit(base)}';

  group('SNO-ALG-CFG-03: код из входов', () {
    test('SNO-ALG-CFG-03: эталонные значения', () {
      expect(
        participantCodeBase(nodeId: node, timeMs: moment, attempt: 0),
        '6795433',
      );
      expect(
        participantCodeBase(nodeId: node, timeMs: moment, attempt: 1),
        '4221353',
      );
      expect(
        participantCodeBase(nodeId: node, timeMs: moment, attempt: 2),
        '4422033',
      );
      expect(
        participantCodeBase(nodeId: '00000000', timeMs: 0, attempt: 0),
        '7133348',
      );
      expect(
        participantCodeBase(
          nodeId: 'ffffffffffffffff',
          timeMs: moment,
          attempt: 7,
        ),
        '4212753',
      );
    });

    test('SNO-ALG-CFG-03: контрольная цифра — по Дамму', () {
      // Пример из описания алгоритма: 572 → 4.
      expect(dammCheckDigit('572'), 4);
      expect(dammCheckDigit('5724'), 0);
      expect(withCheck('6795433'), '67954332');
      expect(withCheck('4221353'), '42213535');
      expect(withCheck('4422033'), '44220334');
      expect(withCheck('7133348'), '71333483');
      expect(withCheck('4212753'), '42127535');
      expect(() => dammCheckDigit('12a'), throwsArgumentError);
    });

    test('SNO-ALG-CFG-03: выданный код — восемь цифр, показ группами', () {
      final ParticipantCode code = generateParticipantCode(
        nodeId: node,
        now: DateTime.fromMillisecondsSinceEpoch(moment),
      );
      expect(code.code, '67954332');
      expect(code.display, '6795-4332');
      expect(code.base, '6795433');
      expect(code.generated, isTrue);
      expect(code.attempt, 0);
      expect(isValidParticipantCode(code.code), isTrue);
    });

    test('SNO-ALG-CFG-03: повтор на устройстве невозможен', () {
      final DateTime now = DateTime.fromMillisecondsSinceEpoch(moment);
      final ParticipantCode second = generateParticipantCode(
        nodeId: node,
        now: now,
        known: <String>{'6795433'},
      );
      expect(second.code, '42213535');
      expect(second.attempt, 1);

      final ParticipantCode third = generateParticipantCode(
        nodeId: node,
        now: now,
        known: <String>{'6795433', '4221353'},
      );
      expect(third.code, '44220334');
      expect(third.attempt, 2);
    });

    test('SNO-ALG-CFG-03: первая цифра не ноль, цифр всегда семь', () {
      for (int i = 0; i < 10000; i++) {
        final String base = participantCodeBase(
          nodeId: node,
          timeMs: moment + i,
          attempt: i % 3,
        );
        expect(base, hasLength(kCodeBaseLength));
        expect(base.startsWith('0'), isFalse, reason: base);
      }
    });
  });

  group('SNO-ALG-CFG-03: ошибки почерка', () {
    test('SNO-ALG-CFG-03: одна неверная цифра и перестановка соседних '
        'ловятся на 10 000 кодов', () {
      for (int i = 0; i < 10000; i++) {
        final String code = withCheck(
          participantCodeBase(nodeId: node, timeMs: moment + i, attempt: 0),
        );
        expect(isValidParticipantCode(code), isTrue, reason: code);
        for (int place = 0; place < kCodeLength; place++) {
          final String was = code[place];
          // Любая другая цифра на этом месте.
          for (int digit = 0; digit < 10; digit++) {
            if ('$digit' == was) {
              continue;
            }
            final String wrong = code.replaceRange(place, place + 1, '$digit');
            if (isValidParticipantCode(wrong)) {
              fail('ошибка в одной цифре не поймана: $code → $wrong');
            }
          }
          // Две соседние цифры поменялись местами.
          if (place + 1 < kCodeLength && code[place + 1] != was) {
            final String swapped = code.replaceRange(
              place,
              place + 2,
              '${code[place + 1]}$was',
            );
            if (isValidParticipantCode(swapped)) {
              fail('перестановка соседних не поймана: $code → $swapped');
            }
          }
        }
      }
    });
  });

  group('SNO-F-CFG-05: введённый код', () {
    final DateTime now = DateTime.utc(2026, 11, 3, 11);

    test('SNO-F-CFG-05: прежний код принимается, как он написан в '
        'бланке', () {
      final ParticipantCode? code = enteredParticipantCode('6795-4332', now);
      expect(code, isNotNull);
      expect(code!.code, '67954332');
      expect(code.generated, isFalse);
      expect(code.generatedAt, now);
      expect(enteredParticipantCode(' 6795 4332 ', now)?.code, '67954332');
      expect(enteredParticipantCode('67954332', now)?.code, '67954332');
    });

    test('SNO-F-CFG-05: код с неверной контрольной цифрой отвергается', () {
      // Ошибка в одной цифре.
      expect(enteredParticipantCode('6795-4333', now), isNull);
      expect(enteredParticipantCode('6785-4332', now), isNull);
      // Соседние цифры переставлены.
      expect(enteredParticipantCode('6759-4332', now), isNull);
      // Цифр не восемь.
      expect(enteredParticipantCode('6795-433', now), isNull);
      expect(enteredParticipantCode('6795-43321', now), isNull);
      expect(enteredParticipantCode('', now), isNull);
      // Ведущий ноль: таких кодов приложение не выдаёт.
      expect(isValidParticipantCode('0${'0' * 7}'), isFalse);
    });

    test('SNO-F-CFG-05: цифры из набранного и показ группами', () {
      expect(normalizeParticipantCode('6795-4332'), '67954332');
      expect(normalizeParticipantCode('код 67 95 – 43 32'), '67954332');
      expect(formatParticipantCode('67954332'), '6795-4332');
      // Не восемь знаков — показывается как есть.
      expect(formatParticipantCode('123'), '123');
    });
  });

  group('SNO-F-CFG-05: запись кода', () {
    test('SNO-F-CFG-05: рядом с кодом лежат входы генератора', () {
      final DateTime at = DateTime.fromMillisecondsSinceEpoch(moment);
      final ParticipantCode code = generateParticipantCode(
        nodeId: node,
        now: at,
        known: <String>{'6795433'},
      );
      final Map<String, Object?> json = code.toJson();
      expect(json['code'], '42213535');
      expect(json['generated'], isTrue);
      expect(json['generator'], kCodeGenerator);
      expect(json['generated_at'], at.toUtc().toIso8601String());
      expect(json['attempt'], 1);

      final ParticipantCode? back = ParticipantCode.fromJson(json);
      expect(back, isNotNull);
      expect(back!.code, code.code);
      expect(back.generated, isTrue);
      expect(back.attempt, 1);
      expect(back.generatedAt.isAtSameMomentAs(at), isTrue);
    });

    test('SNO-F-CFG-05: у введённого кода генератора нет', () {
      final ParticipantCode code = enteredParticipantCode(
        '6795-4332',
        DateTime.utc(2026, 11, 3),
      )!;
      final Map<String, Object?> json = code.toJson();
      expect(json['generated'], isFalse);
      expect(json['generator'], isNull);
      expect(ParticipantCode.fromJson(json)?.generated, isFalse);
    });

    test('SNO-F-CFG-05: испорченная запись кода не читается', () {
      expect(ParticipantCode.fromJson(null), isNull);
      expect(ParticipantCode.fromJson('67954332'), isNull);
      expect(
        ParticipantCode.fromJson(<String, Object?>{
          'code': '67954333',
          'generated': true,
          'generated_at': '2026-11-03T11:00:00.000Z',
        }),
        isNull,
      );
      expect(
        ParticipantCode.fromJson(<String, Object?>{
          'code': '67954332',
          'generated': true,
          'generated_at': 'вчера',
        }),
        isNull,
      );
    });

    test('SNO-ALG-CFG-03: список выданных кодов читается обратно', () {
      final Set<String> known = <String>{'6795433', '4221353'};
      final String stored = encodeKnownCodes(known);
      expect(stored, '4221353 6795433');
      expect(decodeKnownCodes(stored), known);
      expect(decodeKnownCodes(null), isEmpty);
      expect(decodeKnownCodes(''), isEmpty);
      // Чужое в строке пропускается.
      expect(decodeKnownCodes('6795433 мусор 12 4221353x'), <String>{
        '6795433',
      });
    });

    test('SNO-F-CFG-05: код устройства — шесть знаков узла', () {
      expect(deviceCodeOf('a91f3c0b7d2e'), 'a91f3c');
      expect(deviceCodeOf('a91f3c0b7d2e'), hasLength(kDeviceCodeLength));
      expect(deviceCodeOf('ab'), 'ab');
    });
  });
}
