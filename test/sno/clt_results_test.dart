import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/builtin_scenario.dart';
import 'package:memoria/sno/clt/results.dart';
import 'package:memoria/sno/clt/scenario.dart';
import 'package:memoria/sno/recording/records.dart';

/// SNO-F-CLT-03, SNO-F-CLT-04: файл ответов, итог для манифеста,
/// показатели и маркеры честности.
///
/// Чистые правила на придуманных ответах. Показатели и раздел `checks`
/// сверяются с числами, посчитанными **другой** реализацией — на
/// Python: суммы и средние по группам пунктов с переворотом пункта с
/// обратным счётом; отметки маркеров, сверка с записью, быстрые и
/// одинаковые ответы.
void main() {
  /// Ответ на пункт [item] шкалы 1…7 (у `tlx.*` — 0…100).
  CltAnswer answer(
    String item,
    int value,
    int order, {
    bool reverse = false,
    int? rtMs,
  }) {
    final bool tlx = item.startsWith('tlx.');
    return CltAnswer(
      item: item,
      value: value,
      rtMs: rtMs ?? 3000 + order,
      order: order,
      min: tlx ? 0 : 1,
      max: tlx ? 100 : 7,
      t: 2400000 + order * 4000,
      reverse: reverse,
      check: item.startsWith('chk.') || item.startsWith('lie.'),
    );
  }

  /// Порядок итоговой части у участника 67954332: раздел «О задании» —
  /// семь пунктов и маркер — перемешан по его коду; пункты шкалы лжи
  /// стоят на своих местах у всех — седьмым и предпоследним.
  const List<String> order = <String>[
    'tlx.mental',
    'tlx.physical',
    'tlx.temporal',
    'tlx.performance',
    'tlx.effort',
    'tlx.frustration',
    'lie.defer',
    'gcl.2',
    'chk.focus',
    'ecl.3',
    'gcl.1',
    'icl.1',
    'ecl.2',
    'ecl.1',
    'icl.2',
    'orient.1',
    'chk.books',
    'orient.2',
    'lie.late',
    'orient.3',
  ];

  /// Маркеры честности среди пунктов части — в порядке показа: два
  /// сверяются с записью, два — шкала лжи.
  const List<String> markers = <String>[
    'lie.defer',
    'chk.focus',
    'chk.books',
    'lie.late',
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
    // Маркеры: «не отвлёкся» — скорее нет, «не открыл ни одной книги»
    // — совершенно неверно.
    'chk.focus': 3,
    'chk.books': 1,
    // Шкала лжи: «случалось откладывать» — да, «ни разу не опоздал» —
    // совершенно неверно.
    'lie.defer': 6,
    'lie.late': 1,
  };

  /// Итоговая часть с первыми [count] ответами. [answered] подменяет
  /// ответы отдельных пунктов, [rt] — время ответа на них.
  CltResult finalPart({
    int count = 20,
    int tStart = 2400000,
    Map<String, int> answered = const <String, int>{},
    Map<String, int> rt = const <String, int>{},
  }) {
    return CltResult(
      scenario: 'sno-clt-main',
      version: 3,
      participant: '67954332',
      part: 'B',
      tStart: tStart,
      tEnd: count == order.length ? tStart + 180000 : null,
      order: order,
      answers: <CltAnswer>[
        for (int i = 0; i < count; i++)
          answer(
            order[i],
            answered[order[i]] ?? values[order[i]]!,
            i + 1,
            reverse: order[i] == 'orient.3',
            rtMs: rt[order[i]],
          ),
      ],
      complete: count == order.length,
      checks: markers,
    );
  }

  /// Оценка усилия [value] за блок [block] — файл записи прежней
  /// сборки: с шага 25 блоков нет (SNO-F-REC-15), но такие файлы
  /// читаются и считаются как раньше.
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
      expect(read.checks, markers);
      expect(read.answers, hasLength(20));
      // SNO-F-CLT-04: ответ на маркер помечен в самом файле.
      expect(<String>[
        for (final CltAnswer answer in read.answers)
          if (answer.check) answer.item,
      ], markers);
      final Map<String, Object?> json =
          jsonDecode(written.encode()) as Map<String, Object?>;
      expect(json['checks'], markers);
      final Map<String, Object?> marker =
          (json['answers']! as List<Object?>)[8]! as Map<String, Object?>;
      expect(marker['item'], 'chk.focus');
      expect(marker['role'], 'check');
      expect(
        ((json['answers']! as List<Object?>)[7]! as Map<String, Object?>)
            .containsKey('role'),
        isFalse,
      );
      final CltAnswer last = read.answers.last;
      expect(last.item, 'orient.3');
      expect(last.value, 2);
      expect(last.reverse, isTrue);
      // Значение в файле — как на экране; переворачивается оно при счёте.
      expect(last.scored, 6);
      expect(read.answers.first.scored, 65);
    });

    test('SNO-F-REC-15: файл прежней сборки с оценкой усилия за блок '
        'читается как записан', () {
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
      expect(
        <String>[for (final CltResult result in results) result.part],
        ['A', 'B'],
      );
      expect(CltResult.decode('не JSON'), isNull);
      expect(CltResult.decode('[]'), isNull);
    });
  });

  group('SNO-F-CLT-03: итог для манифеста', () {
    test('SNO-F-CLT-03: теста не было', () {
      // SNO-F-REC-15: об усилии по блокам итог новой записи молчит.
      expect(summarizeClt(const <CltResult>[]), <String, Object?>{
        'final': 'none',
        'files': <String>[],
      });
    });

    test('SNO-F-REC-15: у записи прежней сборки — усилие оценено, '
        'итоговая часть не начата', () {
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
        finalPart(count: 10),
      ]);

      expect(summary['final'], 'partial');
      expect(summary['final_answers'], 10);
      expect(summary['final_items'], 20);
    });

    test('SNO-F-CLT-03: тест пройден', () {
      expect(summarizeClt(<CltResult>[finalPart()]), <String, Object?>{
        'final': 'complete',
        'final_answers': 20,
        'final_items': 20,
        'files': <String>['clt/sno-clt-main_B_2400000.json'],
      });
    });

    test('SNO-F-CLT-04: в итог идёт одно число — сколько отметок', () {
      final Map<String, Object?> summary = summarizeClt(
        <CltResult>[finalPart()],
        checks: <String, Object?>{'flags': 2, 'verdict': 'doubt'},
      );

      expect(summary['checks_flags'], 2);
      expect(summary['final'], 'complete');
      // Раздела нет — и числа нет.
      expect(
        summarizeClt(<CltResult>[finalPart()]).containsKey('checks_flags'),
        isFalse,
      );
    });

    test('SNO-F-REC-15: у записи прежней сборки с блоками тест пройден', () {
      expect(
        summarizeClt(<CltResult>[effort(1, 6), effort(2, 7), finalPart()]),
        <String, Object?>{
          'effort_answers': 2,
          'final': 'complete',
          'final_answers': 20,
          'final_items': 20,
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
        finalPart(count: 10),
        finalPart(count: 3, tStart: 2500000),
      ];

      expect(finalCltResult(results)!.answers, hasLength(10));
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
      final Map<String, Object?> scores = cltScores(<CltResult>[finalPart()]);

      expect(scores['schema'], 'sno2026-clt-scores/1');
      expect(scores['scenario'], 'sno-clt-main');
      expect(scores['version'], 3);
      expect(scores['participant'], '67954332');
      // SNO-F-REC-15: раздела об усилии по блокам у новой записи нет.
      expect(scores.containsKey('blocks'), isFalse);
      final Map<String, Object?> last =
          scores['final']! as Map<String, Object?>;
      expect(last['complete'], isTrue);
      expect(last['answers'], 20);
      expect(last['items'], 20);
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
      // SNO-F-CLT-04: маркеры и шкала лжи в показатели не входят —
      // групп `chk` и `lie` нет, а пунктов в показателях прежние
      // шестнадцать.
      final Map<String, Object?> byGroup = groups! as Map<String, Object?>;
      expect(byGroup.keys, <String>['tlx', 'gcl', 'ecl', 'icl', 'orient']);
      int counted = 0;
      for (final Object? one in byGroup.values) {
        counted += (one! as Map<String, Object?>)['n']! as int;
      }
      expect(counted, 16);
    });

    test('SNO-F-CLT-04: маркер в показатели не входит, как бы на него ни '
        'ответили', () {
      Object? groupsOf(Map<String, int> answered) {
        final Map<String, Object?> scores = cltScores(<CltResult>[
          finalPart(answered: answered),
        ]);
        return (scores['final']! as Map<String, Object?>)['scores'];
      }

      expect(
        groupsOf(const <String, int>{
          'chk.focus': 7,
          'chk.books': 7,
          'lie.defer': 7,
          'lie.late': 7,
        }),
        groupsOf(const <String, int>{
          'chk.focus': 1,
          'chk.books': 1,
          'lie.defer': 1,
          'lie.late': 1,
        }),
      );
    });

    test('SNO-F-REC-15: у записи прежней сборки усилие — по блокам, '
        'отдельно на каждый', () {
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
      // Числа посчитаны на Python: десять первых пунктов участника —
      // шесть шкал, пункт шкалы лжи, `gcl.2`, маркер и `ecl.3`.
      final Map<String, Object?> scores = cltScores(<CltResult>[
        finalPart(count: 10),
      ]);

      final Map<String, Object?> last =
          scores['final']! as Map<String, Object?>;
      expect(last['complete'], isFalse);
      expect(last['answers'], 10);
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
      expect(group(groups, 'ecl'), <String, Object?>{
        'mean': 4.0,
        'sum': 4,
        'n': 1,
        'of': 3,
        'min': 1,
        'max': 7,
      });
      final Map<String, Object?> byGroup = groups! as Map<String, Object?>;
      expect(byGroup.containsKey('icl'), isFalse);
      expect(byGroup.containsKey('orient'), isFalse);
      expect(byGroup.containsKey('chk'), isFalse);
      expect(byGroup.containsKey('lie'), isFalse);
    });

    test('SNO-F-CLT-03: показатели пишутся в JSON и читаются обратно', () {
      final Map<String, Object?> scores = cltScores(<CltResult>[finalPart()]);

      expect(jsonDecode(jsonEncode(scores)), scores);
      expect(cltScores(const <CltResult>[])['final'], isNull);
    });
  });

  group('SNO-F-CLT-04: маркеры честности', () {
    final CltPart part = parseCltScenario(kBuiltinCltScenario)
        .partFor(kCltSessionEnd)!;

    /// Числа из записи: отлучек [away], открытий книг [opens].
    Map<String, int?> facts(int? away, int? opens) {
      return <String, int?>{kCltFactAwayCount: away, kCltFactBookOpens: opens};
    }

    Map<String, Object?> marker(Map<String, Object?> checks, String id) {
      return (checks['items']! as Map<String, Object?>)[id]!
          as Map<String, Object?>;
    }

    /// Раздел `checks` без слов о правиле.
    Map<String, Object?> told(Map<String, Object?> checks) {
      return <String, Object?>{
        for (final MapEntry<String, Object?> entry in checks.entries)
          if (entry.key != 'rule') entry.key: entry.value,
      };
    }

    test('SNO-F-CLT-04: честные ответы — ни одной отметки', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> checks = cltChecks(
        finalPart(),
        part,
        facts: facts(2, 14),
      );

      expect(told(checks), <String, Object?>{
        'items': <String, Object?>{
          'chk.focus': <String, Object?>{
            'value': 3,
            'flag': false,
            'record': <String, Object?>{'away_count': 2},
            'contradicts_record': false,
          },
          'chk.books': <String, Object?>{
            'value': 1,
            'flag': false,
            'record': <String, Object?>{'book_opens': 14},
            'contradicts_record': false,
          },
          // Шкала лжи с записью не сверяется: ни числа, ни расхождения.
          'lie.defer': <String, Object?>{'value': 6, 'flag': false},
          'lie.late': <String, Object?>{'value': 1, 'flag': false},
        },
        'fast_answers': 0,
        'longest_same': 1,
        'flags': 0,
        'verdict': 'ok',
      });
      expect(checks['rule'], contains('1000 мс'));
    });

    test('SNO-F-CLT-04: «ни разу не отвлёкся» при отлучках в записи — '
        'отметка и расхождение с записью', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> checks = cltChecks(
        finalPart(answered: const <String, int>{'chk.focus': 7}),
        part,
        facts: facts(2, 14),
      );

      expect(marker(checks, 'chk.focus'), <String, Object?>{
        'value': 7,
        'flag': true,
        'record': <String, Object?>{'away_count': 2},
        'contradicts_record': true,
      });
      expect(marker(checks, 'chk.books')['flag'], isFalse);
      expect(checks['flags'], 1);
      expect(checks['verdict'], 'review');
      // Соседний пункт тоже получил 7: цепочка из двух.
      expect(checks['longest_same'], 2);
    });

    test('SNO-F-CLT-04: ответ 6 — без отметки, но с записью расходится', () {
      final Map<String, Object?> checks = cltChecks(
        finalPart(answered: const <String, int>{'chk.focus': 6}),
        part,
        facts: facts(1, 3),
      );

      expect(marker(checks, 'chk.focus'), <String, Object?>{
        'value': 6,
        'flag': false,
        'record': <String, Object?>{'away_count': 1},
        'contradicts_record': true,
      });
      // Расхождение с записью отдельной отметкой не считается.
      expect(checks['flags'], 0);
      expect(checks['verdict'], 'ok');
    });

    test('SNO-F-CLT-04: оба маркера отмечены — ответам нельзя верить без '
        'разбора', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> checks = cltChecks(
        finalPart(
          answered: const <String, int>{'chk.focus': 7, 'chk.books': 5},
        ),
        part,
        facts: facts(0, 14),
      );

      // Отлучек в записи нет: отметка стоит, расхождения нет.
      expect(marker(checks, 'chk.focus'), <String, Object?>{
        'value': 7,
        'flag': true,
        'record': <String, Object?>{'away_count': 0},
        'contradicts_record': false,
      });
      expect(marker(checks, 'chk.books'), <String, Object?>{
        'value': 5,
        'flag': true,
        'record': <String, Object?>{'book_opens': 14},
        'contradicts_record': true,
      });
      expect(checks['flags'], 2);
      expect(checks['verdict'], 'doubt');
    });

    test('SNO-F-CLT-04: «книг не открывал» сверяется с записью в обе '
        'стороны', () {
      // Ни одной открытой книги в записи, а участник говорит, что
      // открывал: отметки нет, расхождение есть.
      final Map<String, Object?> none = cltChecks(
        finalPart(answered: const <String, int>{'chk.books': 2}),
        part,
        facts: facts(0, 0),
      );
      expect(marker(none, 'chk.books'), <String, Object?>{
        'value': 2,
        'flag': false,
        'record': <String, Object?>{'book_opens': 0},
        'contradicts_record': true,
      });
      expect(none['flags'], 0);

      // Ни одной открытой книги, и участник это подтверждает: отметка
      // по ответу стоит, но с записью он сходится.
      final Map<String, Object?> agreed = cltChecks(
        finalPart(answered: const <String, int>{'chk.books': 4}),
        part,
        facts: facts(0, 0),
      );
      expect(marker(agreed, 'chk.books'), <String, Object?>{
        'value': 4,
        'flag': true,
        'record': <String, Object?>{'book_opens': 0},
        'contradicts_record': false,
      });
      expect(agreed['flags'], 1);
      expect(agreed['verdict'], 'review');
    });

    test('SNO-F-CLT-04: быстрые ответы и один ответ подряд — по отметке '
        'без единого вопроса', () {
      // Эталон посчитан на Python: весь раздел «О задании» — четвёрки,
      // три ответа быстрее секунды.
      final Map<String, Object?> checks = cltChecks(
        finalPart(
          answered: const <String, int>{
            'icl.1': 4,
            'icl.2': 4,
            'ecl.1': 4,
            'ecl.2': 4,
            'ecl.3': 4,
            'gcl.1': 4,
            'gcl.2': 4,
            'chk.focus': 4,
          },
          rt: const <String, int>{
            'tlx.mental': 400,
            'tlx.physical': 999,
            'orient.3': 0,
          },
        ),
        part,
        facts: facts(0, 2),
      );

      expect(checks['fast_answers'], 3);
      expect(checks['longest_same'], 8);
      expect(marker(checks, 'chk.focus')['flag'], isFalse);
      expect(checks['flags'], 2);
      expect(checks['verdict'], 'doubt');
    });

    test('SNO-F-CLT-04: пороги — ровно секунда не быстрая, пять подряд не '
        'отметка, шесть — отметка', () {
      final Map<String, Object?> edge = cltChecks(
        finalPart(
          rt: const <String, int>{
            'tlx.mental': 1000,
            'tlx.physical': 999,
            'tlx.temporal': 999,
          },
        ),
        part,
        facts: facts(0, 2),
      );
      expect(edge['fast_answers'], 2);
      expect(edge['flags'], 0);

      // Эталон посчитан на Python: шесть четвёрок подряд в порядке
      // показа — `ecl.3`, `gcl.1`, `icl.1`, `ecl.2`, `ecl.1`, `icl.2`.
      final Map<String, Object?> six = cltChecks(
        finalPart(
          answered: const <String, int>{
            'icl.1': 4,
            'ecl.2': 4,
            'ecl.1': 4,
            'icl.2': 4,
            'gcl.1': 4,
          },
        ),
        part,
      );
      expect(six['longest_same'], 6);
      expect(six['flags'], 1);
      expect(six['verdict'], 'review');

      final Map<String, Object?> five = cltChecks(
        finalPart(
          answered: const <String, int>{
            'icl.1': 4,
            'ecl.2': 4,
            'ecl.1': 4,
            'icl.2': 5,
            'gcl.1': 4,
          },
        ),
        part,
      );
      expect(five['longest_same'], 5);
      expect(five['flags'], 0);
    });

    test('SNO-F-CLT-04: числа из записи неизвестны — сверка «не знаю», а '
        'не «расхождений нет»', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> checks = cltChecks(
        finalPart(answered: const <String, int>{'chk.focus': 7}),
        part,
        facts: facts(null, null),
      );

      expect(marker(checks, 'chk.focus'), <String, Object?>{
        'value': 7,
        'flag': true,
        'record': <String, Object?>{'away_count': null},
        'contradicts_record': null,
      });
      expect(marker(checks, 'chk.books'), <String, Object?>{
        'value': 1,
        'flag': false,
        'record': <String, Object?>{'book_opens': null},
        'contradicts_record': null,
      });
      // Отметка по самому ответу от записи не зависит.
      expect(checks['flags'], 1);
    });

    test('SNO-F-CLT-04: на маркер ещё не ответили — ни отметки, ни '
        'сверки', () {
      // Эталон посчитан на Python: десять первых пунктов.
      final Map<String, Object?> checks = cltChecks(
        finalPart(count: 10),
        part,
        facts: facts(2, 14),
      );

      expect(marker(checks, 'chk.focus')['value'], 3);
      expect(marker(checks, 'chk.books'), <String, Object?>{
        'value': null,
        'flag': null,
        'record': <String, Object?>{'book_opens': 14},
        'contradicts_record': null,
      });
      expect(marker(checks, 'lie.defer'), <String, Object?>{
        'value': 6,
        'flag': false,
      });
      expect(marker(checks, 'lie.late'), <String, Object?>{
        'value': null,
        'flag': null,
      });
      expect(checks['flags'], 0);
      expect(checks['verdict'], 'ok');
    });

    test('SNO-F-CLT-04: шкала лжи — отрицает слабость, которая есть у '
        'каждого, и приписывает себе достоинство, которого нет ни у '
        'кого', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> checks = cltChecks(
        finalPart(answered: const <String, int>{'lie.defer': 2, 'lie.late': 6}),
        part,
        facts: facts(2, 14),
      );

      expect(marker(checks, 'lie.defer'), <String, Object?>{
        'value': 2,
        'flag': true,
      });
      expect(marker(checks, 'lie.late'), <String, Object?>{
        'value': 6,
        'flag': true,
      });
      // Маркеры, которые сверяются с записью, тут ни при чём.
      expect(marker(checks, 'chk.focus')['flag'], isFalse);
      expect(marker(checks, 'chk.books')['flag'], isFalse);
      expect(checks['flags'], 2);
      expect(checks['verdict'], 'doubt');
    });

    test('SNO-F-CLT-04: шкала лжи — отметка с несогласия у первого пункта '
        'и с согласия у второго, середина шкалы не отметка', () {
      // Эталон посчитан на Python.
      final Map<String, Object?> flagged = cltChecks(
        finalPart(answered: const <String, int>{'lie.defer': 3, 'lie.late': 5}),
        part,
      );
      expect(marker(flagged, 'lie.defer')['flag'], isTrue);
      expect(marker(flagged, 'lie.late')['flag'], isTrue);
      expect(flagged['flags'], 2);

      final Map<String, Object?> middle = cltChecks(
        finalPart(answered: const <String, int>{'lie.defer': 4, 'lie.late': 4}),
        part,
      );
      expect(marker(middle, 'lie.defer')['flag'], isFalse);
      expect(marker(middle, 'lie.late')['flag'], isFalse);
      expect(middle['flags'], 0);
      expect(middle['verdict'], 'ok');
    });

    test('SNO-F-CLT-04: шкала лжи — ключи у пунктов противоположные: одна '
        'кнопка подряд даёт ровно одну отметку шкалы', () {
      // Эталон посчитан на Python: на всё, кроме шкал нагрузки, — один
      // и тот же ответ.
      Map<String, Object?> pressed(int value) {
        return cltChecks(
          finalPart(
            answered: <String, int>{
              for (final String item in order)
                if (!item.startsWith('tlx.')) item: value,
            },
          ),
          part,
          facts: facts(2, 14),
        );
      }

      final Map<String, Object?> sevens = pressed(7);
      expect(marker(sevens, 'lie.defer')['flag'], isFalse);
      expect(marker(sevens, 'lie.late')['flag'], isTrue);
      // Плюс оба маркера записи и восемь одинаковых подряд.
      expect(sevens['longest_same'], 8);
      expect(sevens['flags'], 4);

      final Map<String, Object?> ones = pressed(1);
      expect(marker(ones, 'lie.defer')['flag'], isTrue);
      expect(marker(ones, 'lie.late')['flag'], isFalse);
      // Плюс восемь одинаковых подряд.
      expect(ones['flags'], 2);
      expect(ones['verdict'], 'doubt');
    });

    test('SNO-F-CLT-04: раздел ложится в показатели рядом с ними и '
        'пишется в JSON', () {
      final Map<String, Object?> checks = cltChecks(
        finalPart(),
        part,
        facts: facts(2, 14),
      );
      final Map<String, Object?> scores = cltScores(<CltResult>[
        finalPart(),
      ], checks: checks);

      expect(scores['checks'], checks);
      expect(jsonDecode(jsonEncode(scores)), scores);
      expect(scores['rule'], contains('role: check'));
      final Map<String, Object?> bare = cltScores(<CltResult>[finalPart()]);
      expect(bare.containsKey('checks'), isFalse);
    });

    test('SNO-F-CLT-04: правила маркеров берутся из сценария, каким его '
        'видел участник', () {
      final String scenario = jsonEncode(kBuiltinCltScenario);

      final Map<String, Object?>? checks = cltChecksFor(
        <CltResult>[
          finalPart(answered: const <String, int>{'chk.focus': 7}),
        ],
        scenario: scenario,
        facts: facts(2, 14),
      );
      expect(checks!['flags'], 1);
      expect(marker(checks, 'chk.focus')['contradicts_record'], isTrue);

      // Считать не по чему: теста не начинали, сценария рядом нет, он
      // не читается или в нём нет маркеров.
      expect(cltChecksFor(const <CltResult>[], scenario: scenario), isNull);
      expect(cltChecksFor(<CltResult>[finalPart()], scenario: null), isNull);
      expect(
        cltChecksFor(<CltResult>[finalPart()], scenario: 'не JSON'),
        isNull,
      );
      expect(
        cltChecksFor(<CltResult>[finalPart()], scenario: '{"schema":"x"}'),
        isNull,
      );
      final Map<String, Object?> plain =
          jsonDecode(scenario) as Map<String, Object?>;
      for (final Object? one in plain['parts']! as List<Object?>) {
        final Map<String, Object?> piece = one! as Map<String, Object?>;
        final List<Object?> sections = piece['sections']! as List<Object?>;
        for (final Object? section in sections) {
          final Map<String, Object?> entry = section! as Map<String, Object?>;
          (entry['items']! as List<Object?>).removeWhere((Object? item) {
            return (item! as Map<String, Object?>)['role'] == 'check';
          });
        }
        // Раздел, в котором стоял один пункт шкалы лжи, остался пустым:
        // сценарий с пустым разделом не принимается вовсе.
        sections.removeWhere((Object? section) {
          final Map<String, Object?> entry = section! as Map<String, Object?>;
          return (entry['items']! as List<Object?>).isEmpty;
        });
      }
      // Сценарий без маркеров читается — просто сверять в нём нечего.
      expect(
        parseCltScenario(plain).partFor(kCltSessionEnd)!.length,
        16,
      );
      expect(
        cltChecksFor(<CltResult>[finalPart()], scenario: jsonEncode(plain)),
        isNull,
      );
    });
  });
}
