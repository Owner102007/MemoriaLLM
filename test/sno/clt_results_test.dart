import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/results.dart';
import 'package:memoria/sno/recording/records.dart';

/// SNO-F-CLT-03: файл ответов, итог для манифеста и показатели.
///
/// Чистые правила на придуманных ответах. Показатели сверяются с
/// числами, посчитанными **другой** реализацией — на Python: суммы и
/// средние по группам пунктов, с переворотом пункта с обратным счётом.
void main() {
  /// Ответ на пункт [item] шкалы 1…7 (у `tlx.*` — 0…100).
  CltAnswer answer(String item, int value, int order, {bool reverse = false}) {
    final bool tlx = item.startsWith('tlx.');
    return CltAnswer(
      item: item,
      value: value,
      rtMs: 3000 + order,
      order: order,
      min: tlx ? 0 : 1,
      max: tlx ? 100 : 7,
      t: 2400000 + order * 4000,
      reverse: reverse,
    );
  }

  /// Порядок итоговой части у участника 67954332.
  const List<String> order = <String>[
    'tlx.mental',
    'tlx.physical',
    'tlx.temporal',
    'tlx.performance',
    'tlx.effort',
    'tlx.frustration',
    'gcl.2',
    'icl.2',
    'icl.1',
    'ecl.1',
    'ecl.3',
    'ecl.2',
    'gcl.1',
    'orient.1',
    'orient.2',
    'orient.3',
  ];

  const Map<String, int> values = <String, int>{
    'tlx.mental': 65,
    'tlx.physical': 20,
    'tlx.temporal': 40,
    'tlx.performance': 35,
    'tlx.effort': 70,
    'tlx.frustration': 25,
    'icl.1': 5,
    'icl.2': 4,
    'ecl.1': 3,
    'ecl.2': 2,
    'ecl.3': 4,
    'gcl.1': 6,
    'gcl.2': 7,
    'orient.1': 5,
    'orient.2': 6,
    'orient.3': 2,
  };

  /// Итоговая часть с первыми [count] ответами.
  CltResult finalPart({int count = 16, int tStart = 2400000}) {
    return CltResult(
      scenario: 'sno-clt-main',
      version: 1,
      participant: '67954332',
      part: 'B',
      tStart: tStart,
      tEnd: count == order.length ? tStart + 180000 : null,
      order: order,
      answers: <CltAnswer>[
        for (int i = 0; i < count; i++)
          answer(
            order[i],
            values[order[i]]!,
            i + 1,
            reverse: order[i] == 'orient.3',
          ),
      ],
      complete: count == order.length,
    );
  }

  /// Оценка усилия [value] за блок [block].
  CltResult effort(int block, int value, {bool complete = true}) {
    return CltResult(
      scenario: 'sno-clt-main',
      version: 1,
      participant: '67954332',
      part: 'A',
      block: block,
      blockStartMs: block * 600000,
      tStart: block * 1200000,
      tEnd: complete ? block * 1200000 + 5000 : null,
      order: const <String>['paas.effort'],
      answers: <CltAnswer>[
        if (complete)
          CltAnswer(
            item: 'paas.effort',
            value: value,
            rtMs: 4200,
            order: 1,
            min: 1,
            max: 9,
          ),
      ],
      complete: complete,
    );
  }

  group('SNO-F-CLT-03: файл ответов', () {
    test('SNO-F-CLT-03: имя файла — сценарий, часть и время начала', () {
      expect(
        cltResultName('sno-clt-main', 'B', 2461200),
        'clt/sno-clt-main_B_2461200.json',
      );
      expect(finalPart().name, 'clt/sno-clt-main_B_2400000.json');
      expect(kCltScoresFile, 'clt/scores.json');
      expect(kCltScenarioFile, 'clt/scenario.json');
    });

    test('SNO-F-CLT-03: файл читается таким, каким записан', () {
      final CltResult written = finalPart();
      final CltResult read = CltResult.decode(written.encode())!;

      expect(read.toJson(), written.toJson());
      expect(read.complete, isTrue);
      expect(read.order, order);
      expect(read.answers, hasLength(16));
      final CltAnswer last = read.answers.last;
      expect(last.item, 'orient.3');
      expect(last.value, 2);
      expect(last.reverse, isTrue);
      // Значение в файле — как на экране; переворачивается оно при счёте.
      expect(last.scored, 6);
      expect(read.answers.first.scored, 65);
    });

    test('SNO-F-CLT-03: в файле — всё, что названо в формате', () {
      final Map<String, Object?> json =
          jsonDecode(effort(2, 7).encode()) as Map<String, Object?>;

      expect(json, <String, Object?>{
        'schema': 'sno2026-clt-result/1',
        'scenario': 'sno-clt-main',
        'version': 1,
        'participant': '67954332',
        'part': 'A',
        'block': 2,
        'block_start_ms': 1200000,
        't_start': 2400000,
        't_end': 2405000,
        'complete': true,
        'order': <String>['paas.effort'],
        'answers': <Object?>[
          <String, Object?>{
            'item': 'paas.effort',
            'value': 7,
            'rt_ms': 4200,
            'order': 1,
            'min': 1,
            'max': 9,
          },
        ],
      });
      // У части не о блоке номер блока — `null`, как в формате.
      final Map<String, Object?> whole =
          jsonDecode(finalPart().encode()) as Map<String, Object?>;
      expect(whole.containsKey('block'), isTrue);
      expect(whole['block'], isNull);
    });

    test('SNO-F-CLT-03: чужое и нечитаемое файлом ответов не считается', () {
      final Map<String, String> files = <String, String>{
        'clt/b.json': finalPart().encode(),
        'clt/a.json': effort(1, 6).encode(),
        kCltScenarioFile: '{"schema":"sno2026-clt/1","id":"sno-clt-main"}',
        kCltScoresFile: '{"schema":"sno2026-clt-scores/1"}',
        'clt/мусор.json': '{"schema":"sno2026-clt-result/1"',
        'clt/пусто.json': '',
        'clt/без-времени.json': '{"schema":"sno2026-clt-result/1"}',
      };

      final List<CltResult> results = readCltResults(files);

      // По времени начала части: сначала блок, потом итоговая.
      expect(<String>[for (final CltResult result in results) result.part], [
        'A',
        'B',
      ]);
      expect(CltResult.decode('не JSON'), isNull);
      expect(CltResult.decode('[]'), isNull);
    });
  });

  group('SNO-F-CLT-03: итог для манифеста', () {
    test('SNO-F-CLT-03: теста не было', () {
      expect(summarizeClt(const <CltResult>[]), <String, Object?>{
        'effort_answers': 0,
        'final': 'none',
        'files': <String>[],
      });
    });

    test('SNO-F-CLT-03: усилие оценено, итоговая часть не начата', () {
      final Map<String, Object?> summary = summarizeClt(<CltResult>[
        effort(1, 6),
        effort(2, 7, complete: false),
      ]);

      // Блок, на вопрос о котором не ответили, оценённым не считается.
      expect(summary['effort_answers'], 1);
      expect(summary['final'], 'none');
      expect(summary.containsKey('final_answers'), isFalse);
    });

    test('SNO-F-CLT-03: итоговая часть начата и не окончена', () {
      final Map<String, Object?> summary = summarizeClt(<CltResult>[
        effort(1, 6),
        finalPart(count: 9),
      ]);

      expect(summary['final'], 'partial');
      expect(summary['final_answers'], 9);
      expect(summary['final_items'], 16);
    });

    test('SNO-F-CLT-03: тест пройден', () {
      expect(
        summarizeClt(<CltResult>[effort(1, 6), effort(2, 7), finalPart()]),
        <String, Object?>{
          'effort_answers': 2,
          'final': 'complete',
          'final_answers': 16,
          'final_items': 16,
          'files': <String>[
            'clt/sno-clt-main_A_1200000.json',
            'clt/sno-clt-main_A_2400000.json',
            'clt/sno-clt-main_B_2400000.json',
          ],
        },
      );
    });

    test('SNO-F-CLT-03: из двух файлов итоговой части берётся тот, где '
        'ответов больше', () {
      final List<CltResult> results = <CltResult>[
        finalPart(count: 9),
        finalPart(count: 3, tStart: 2500000),
      ];

      expect(finalCltResult(results)!.answers, hasLength(9));
      // При равенстве — начатый позже.
      expect(
        finalCltResult(<CltResult>[
          finalPart(count: 3),
          finalPart(count: 3, tStart: 2500000),
        ])!.tStart,
        2500000,
      );
      expect(finalCltResult(<CltResult>[effort(1, 6)]), isNull);
    });

    test('SNO-F-CLT-03: запись без пройденного теста так и названа в '
        'списке', () {
      DeviceRecord record(Map<String, Object?>? clt) {
        return recordFrom(
          name: 'sno2026_I_67954332_a91f3c_20261103-1402',
          bytes: 412 * 1024,
          packed: true,
          info: <String, Object?>{
            'recording': <String, Object?>{'duration_ms': 2400000},
            if (clt != null) 'clt': clt,
          },
        );
      }

      String line(DeviceRecord record) {
        return describeRecord(record, shares: true);
      }

      final DeviceRecord none = record(<String, Object?>{'final': 'none'});
      expect(none.withoutTest, isTrue);
      expect(line(none), contains('без теста нагрузки'));
      expect(
        line(record(<String, Object?>{'final': 'partial'})),
        contains('без теста нагрузки'),
      );
      expect(
        line(record(<String, Object?>{'final': 'complete'})),
        isNot(contains('теста')),
      );
      // Файлы теста не прочитались — о тесте не сказано ничего.
      expect(
        line(record(<String, Object?>{'final': 'unknown'})),
        isNot(contains('теста')),
      );
      // Запись прежней сборки и сборки без теста о тесте молчит.
      expect(record(null).test, isNull);
      expect(line(record(null)), isNot(contains('теста')));
    });
  });

  group('SNO-F-CLT-03: показатели', () {
    Map<String, Object?> group(Object? scores, String name) {
      return (scores! as Map<String, Object?>)[name]! as Map<String, Object?>;
    }

    test('SNO-F-CLT-03: средние по группам сходятся со второй '
        'реализацией', () {
      // Числа посчитаны на Python.
      final Map<String, Object?> scores = cltScores(<CltResult>[
        effort(1, 6),
        effort(2, 7),
        finalPart(),
      ]);

      expect(scores['schema'], 'sno2026-clt-scores/1');
      expect(scores['scenario'], 'sno-clt-main');
      expect(scores['version'], 1);
      expect(scores['participant'], '67954332');
      final Map<String, Object?> last =
          scores['final']! as Map<String, Object?>;
      expect(last['complete'], isTrue);
      expect(last['answers'], 16);
      expect(last['items'], 16);
      expect(last['file'], 'clt/sno-clt-main_B_2400000.json');
      final Object? groups = last['scores'];
      // Raw TLX — среднее шести шкал.
      expect(group(groups, 'tlx'), <String, Object?>{
        'mean': 42.5,
        'sum': 255,
        'n': 6,
        'of': 6,
        'min': 0,
        'max': 100,
      });
      expect(group(groups, 'icl'), <String, Object?>{
        'mean': 4.5,
        'sum': 9,
        'n': 2,
        'of': 2,
        'min': 1,
        'max': 7,
      });
      expect(group(groups, 'ecl'), <String, Object?>{
        'mean': 3.0,
        'sum': 9,
        'n': 3,
        'of': 3,
        'min': 1,
        'max': 7,
      });
      expect(group(groups, 'gcl'), <String, Object?>{
        'mean': 6.5,
        'sum': 13,
        'n': 2,
        'of': 2,
        'min': 1,
        'max': 7,
      });
      // Ориентация: пункт с обратным счётом перевёрнут — 5, 6 и 8 − 2.
      expect(group(groups, 'orient'), <String, Object?>{
        'mean': 5.667,
        'sum': 17,
        'n': 3,
        'of': 3,
        'min': 1,
        'max': 7,
      });
      expect((groups! as Map<String, Object?>).keys, <String>[
        'tlx',
        'gcl',
        'icl',
        'ecl',
        'orient',
      ]);
    });

    test('SNO-F-CLT-03: усилие — по блокам, отдельно на каждый', () {
      final Map<String, Object?> scores = cltScores(<CltResult>[
        effort(1, 6),
        effort(2, 7),
        effort(3, 0, complete: false),
      ]);

      final List<Object?> blocks = scores['blocks']! as List<Object?>;
      // Блок без ответа в показатели не идёт.
      expect(blocks, hasLength(2));
      final Map<String, Object?> first = blocks[0]! as Map<String, Object?>;
      expect(first['block'], 1);
      expect(first['block_start_ms'], 600000);
      expect(first['complete'], isTrue);
      expect(group(first['scores'], 'paas'), <String, Object?>{
        'mean': 6.0,
        'sum': 6,
        'n': 1,
        'of': 1,
        'min': 1,
        'max': 9,
      });
      final Map<String, Object?> second = blocks[1]! as Map<String, Object?>;
      expect(group(second['scores'], 'paas')['sum'], 7);
      // Итоговой части не было.
      expect(scores['final'], isNull);
    });

    test('SNO-F-CLT-03: неоконченная часть считается по данным ответам и '
        'говорит, на сколько пунктов ответили', () {
      // Числа посчитаны на Python: девять первых пунктов участника.
      final Map<String, Object?> scores = cltScores(<CltResult>[
        finalPart(count: 9),
      ]);

      final Map<String, Object?> last =
          scores['final']! as Map<String, Object?>;
      expect(last['complete'], isFalse);
      expect(last['answers'], 9);
      final Object? groups = last['scores'];
      expect(group(groups, 'tlx')['mean'], 42.5);
      expect(group(groups, 'gcl'), <String, Object?>{
        'mean': 7.0,
        'sum': 7,
        'n': 1,
        'of': 2,
        'min': 1,
        'max': 7,
      });
      expect(group(groups, 'icl')['n'], 2);
      expect((groups! as Map<String, Object?>).containsKey('ecl'), isFalse);
      expect((groups as Map<String, Object?>).containsKey('orient'), isFalse);
    });

    test('SNO-F-CLT-03: показатели пишутся в JSON и читаются обратно', () {
      final Map<String, Object?> scores = cltScores(<CltResult>[finalPart()]);

      expect(jsonDecode(jsonEncode(scores)), scores);
      expect(cltScores(const <CltResult>[])['final'], isNull);
    });
  });
}
