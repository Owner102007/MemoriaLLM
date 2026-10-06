import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/builtin_scenario.dart';
import 'package:memoria/sno/clt/scenario.dart';

/// SNO-F-CLT-02: сценарий теста нагрузки как данные.
///
/// Чистые правила: разбор и отказ сценария, порядок пунктов по коду
/// участника. Порядок перемешанного раздела и зёрна сверяются с числами,
/// посчитанными **другой** реализацией — на Python (FNV-1a, Mulberry32,
/// тасование Фишера — Йетса): своя проверяла бы себя своими же ошибками.
void main() {
  /// Встроенный сценарий, прошедший через JSON, — копия, которую тест
  /// вправе портить.
  Map<String, Object?> builtin() {
    return jsonDecode(jsonEncode(kBuiltinCltScenario)) as Map<String, Object?>;
  }

  /// Часть сценария [scenario] с идентификатором [id].
  Map<String, Object?> partOf(Map<String, Object?> scenario, String id) {
    for (final Object? part in scenario['parts']! as List<Object?>) {
      final Map<String, Object?> one = part! as Map<String, Object?>;
      if (one['id'] == id) {
        return one;
      }
    }
    throw StateError('части $id нет');
  }

  /// Раздел итоговой части с идентификатором [id].
  Map<String, Object?> sectionOf(Map<String, Object?> scenario, String id) {
    for (final Object? section
        in partOf(scenario, 'B')['sections']! as List<Object?>) {
      final Map<String, Object?> one = section! as Map<String, Object?>;
      if (one['id'] == id) {
        return one;
      }
    }
    throw StateError('раздела $id нет');
  }

  /// Причина, по которой сценарий [raw] не принят.
  String refusal(Object? raw) {
    try {
      parseCltScenario(raw);
    } on CltScenarioException catch (refused) {
      return refused.reason;
    }
    fail('сценарий принят, а не должен был');
  }

  group('SNO-F-CLT-02: встроенный сценарий', () {
    test('SNO-F-CLT-02: принят — и такой, как записан, и прошедший через '
        'JSON', () {
      final CltScenario direct = parseCltScenario(kBuiltinCltScenario);
      final CltScenario decoded = parseCltScenario(builtin());

      for (final CltScenario scenario in <CltScenario>[direct, decoded]) {
        expect(scenario.id, 'sno-clt-main');
        expect(scenario.version, 1);
        expect(scenario.lang, 'ru');
        expect(scenario.parts, hasLength(2));
      }
    });

    test('SNO-F-CLT-02: после блока — один вопрос об усилии, девять '
        'делений, без пароля', () {
      final CltPart part = parseCltScenario(
        kBuiltinCltScenario,
      ).partFor(kCltBlockEnd)!;

      expect(part.id, 'A');
      expect(part.password, isFalse);
      expect(part.length, 1);
      final CltItem item = part.sections.single.items.single;
      expect(item.id, 'paas.effort');
      expect(item.text, 'Сколько умственных усилий вы вложили в это задание?');
      expect(item.scale.values, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(item.scale.labels, <int, String>{
        1: 'очень-очень мало',
        5: 'ни мало, ни много',
        9: 'очень-очень много',
      });
      expect(item.group, 'paas');
    });

    test('SNO-F-CLT-02: в конце сессии — шестнадцать пунктов по паролю: '
        'шесть шкал нагрузки, семь о задании, три о полке', () {
      final CltPart part = parseCltScenario(
        kBuiltinCltScenario,
      ).partFor(kCltSessionEnd)!;

      expect(part.id, 'B');
      expect(part.password, isTrue);
      expect(part.length, 16);
      expect(
        <String>[for (final CltSection section in part.sections) section.id],
        <String>['tlx', 'types', 'orient'],
      );
      expect(
        <bool>[
          for (final CltSection section in part.sections) section.shuffle,
        ],
        <bool>[false, true, false],
      );
      final CltSection tlx = part.sections[0];
      expect(tlx.items, hasLength(6));
      for (final CltItem item in tlx.items) {
        expect(item.scale.min, 0, reason: item.id);
        expect(item.scale.max, 100, reason: item.id);
        expect(item.scale.step, 5, reason: item.id);
        expect(item.scale.divisions, 21, reason: item.id);
        expect(item.group, 'tlx');
      }
      // У шкалы успешности больше — хуже, как у остальных пяти.
      final CltItem performance = tlx.items[3];
      expect(performance.id, 'tlx.performance');
      expect(performance.scale.labels, <int, String>{
        0: 'отлично',
        100: 'провал',
      });
      expect(part.sections[1].items, hasLength(7));
      for (final CltItem item in <CltItem>[
        ...part.sections[1].items,
        ...part.sections[2].items,
      ]) {
        expect(item.scale.values, <int>[1, 2, 3, 4, 5, 6, 7], reason: item.id);
        expect(item.scale.labels, <int, String>{
          1: 'совершенно неверно',
          7: 'совершенно верно',
        }, reason: item.id);
      }
      // Обратный счёт — у одного пункта.
      expect(
        <String>[
          for (final CltSection section in part.sections)
            for (final CltItem item in section.items)
              if (item.reverse) item.id,
        ],
        <String>['orient.3'],
      );
    });

    test('SNO-F-CLT-02: группа пункта — идентификатор до последней точки', () {
      expect(cltGroupOf('tlx.mental'), 'tlx');
      expect(cltGroupOf('a.b.c'), 'a.b');
      expect(cltGroupOf('одно'), 'одно');
      expect(cltGroupOf('.точка'), '.точка');
    });

    test('SNO-F-CLT-02: шкала знает свои деления и переворот', () {
      const CltScale scale = CltScale(min: 0, max: 100, step: 5);

      expect(scale.divisions, 21);
      expect(scale.holds(65), isTrue);
      expect(scale.holds(63), isFalse);
      expect(scale.holds(105), isFalse);
      expect(scale.holds(-5), isFalse);
      expect(scale.mirrored(0), 100);
      expect(const CltScale(min: 1, max: 7, step: 1).mirrored(2), 6);
    });
  });

  group('SNO-F-CLT-02: сценарий с ошибкой не принимается', () {
    test('SNO-F-CLT-02: чужая версия формата', () {
      final Map<String, Object?> scenario = builtin()
        ..['schema'] = 'sno2026-clt/2';

      expect(refusal(scenario), contains('sno2026-clt/1'));
      expect(refusal('не объект'), contains('не объект'));
      expect(refusal(null), contains('не объект'));
    });

    test('SNO-F-CLT-02: неизвестный вид пункта', () {
      final Map<String, Object?> scenario = builtin();
      final List<Object?> items =
          partOf(scenario, 'A')['items']! as List<Object?>;
      (items.single! as Map<String, Object?>)['type'] = 'choice';

      expect(refusal(scenario), contains('неизвестный вид пункта «choice»'));

      final Map<String, Object?> shared = builtin();
      (sectionOf(shared, 'tlx')['scale']! as Map<String, Object?>)['type'] =
          'text';
      expect(refusal(shared), contains('неизвестный вид пункта «text»'));
    });

    test('SNO-F-CLT-02: вид пункта не назван', () {
      final Map<String, Object?> scenario = builtin();
      (sectionOf(scenario, 'tlx')['scale']! as Map<String, Object?>).remove(
        'type',
      );

      expect(refusal(scenario), contains('не назван вид пункта'));
    });

    test('SNO-F-CLT-02: шкала, которая не складывается', () {
      Map<String, Object?> scaleWith(String key, Object? value) {
        final Map<String, Object?> scenario = builtin();
        (sectionOf(scenario, 'tlx')['scale']! as Map<String, Object?>)[key] =
            value;
        return scenario;
      }

      expect(refusal(scaleWith('step', 30)), contains('не складывается'));
      expect(refusal(scaleWith('step', 0)), contains('не складывается'));
      expect(refusal(scaleWith('max', 0)), contains('не складывается'));
      expect(refusal(scaleWith('max', '100')), contains('не целые числа'));
      expect(refusal(scaleWith('max', 1000)), contains('делений'));
    });

    test('SNO-F-CLT-02: подпись не на делении шкалы', () {
      final Map<String, Object?> scenario = builtin();
      final List<Object?> items =
          sectionOf(scenario, 'tlx')['items']! as List<Object?>;
      (items.first! as Map<String, Object?>)['labels'] = <String, Object?>{
        '0': 'мало',
        '52': 'середина',
      };

      expect(refusal(scenario), contains('«52»'));
    });

    test('SNO-F-CLT-02: повтор пункта, части и раздела', () {
      final Map<String, Object?> twice = builtin();
      final List<Object?> items =
          sectionOf(twice, 'orient')['items']! as List<Object?>;
      (items.last! as Map<String, Object?>)['id'] = 'tlx.mental';
      expect(refusal(twice), contains('«tlx.mental» встречается дважды'));

      final Map<String, Object?> parts = builtin();
      partOf(parts, 'B')['id'] = 'A';
      expect(refusal(parts), contains('часть «A» встречается дважды'));

      final Map<String, Object?> sections = builtin();
      sectionOf(sections, 'orient')['id'] = 'tlx';
      expect(refusal(sections), contains('раздел «tlx» встречается дважды'));
    });

    test('SNO-F-CLT-02: две части в один миг и часть без мига', () {
      final Map<String, Object?> same = builtin();
      partOf(same, 'A')['when'] = kCltSessionEnd;
      expect(refusal(same), contains('в один миг'));

      final Map<String, Object?> never = builtin();
      partOf(never, 'A')['when'] = 'иногда';
      expect(refusal(never), contains('«иногда»'));
    });

    test('SNO-F-CLT-02: пустые части, пункты и текст', () {
      expect(
        refusal(builtin()..['parts'] = <Object?>[]),
        contains('список пуст'),
      );

      final Map<String, Object?> empty = builtin();
      sectionOf(empty, 'orient')['items'] = <Object?>[];
      expect(refusal(empty), contains('список пуст'));

      final Map<String, Object?> wordless = builtin();
      final List<Object?> items =
          partOf(wordless, 'A')['items']! as List<Object?>;
      (items.single! as Map<String, Object?>)['text'] = '  ';
      expect(refusal(wordless), contains('текст'));

      expect(refusal(builtin()..['version'] = 0), contains('версия'));
      expect(refusal(builtin()..['id'] = ''), contains('идентификатор'));
    });
  });

  group('SNO-F-CLT-02: порядок пунктов по коду участника', () {
    /// Идентификаторы пунктов итоговой части для участника [code].
    List<String> orderFor(String code) {
      final CltScenario scenario = parseCltScenario(kBuiltinCltScenario);
      return <String>[
        for (final CltItem item in orderedCltItems(
          scenario.partFor(kCltSessionEnd)!,
          scenario: scenario.id,
          participant: code,
        ))
          item.id,
      ];
    }

    const List<String> tlx = <String>[
      'tlx.mental',
      'tlx.physical',
      'tlx.temporal',
      'tlx.performance',
      'tlx.effort',
      'tlx.frustration',
    ];
    const List<String> orient = <String>['orient.1', 'orient.2', 'orient.3'];

    test('SNO-F-CLT-02: зерно и перестановка сходятся со второй '
        'реализацией', () {
      // Числа посчитаны на Python.
      expect(cltSeedOf(''), 2166136261);
      expect(cltSeedOf('абв'), 3105333784);
      expect(cltSeedOf('67954332/sno-clt-main/B/types'), 1978284370);
      expect(cltPermutation(0, 7), isEmpty);
      expect(cltPermutation(1, 7), <int>[0]);
      expect(cltPermutation(5, 1), <int>[0, 3, 4, 1, 2]);
      expect(cltPermutation(10, 123456789), <int>[
        5,
        1,
        8,
        6,
        0,
        3,
        9,
        2,
        7,
        4,
      ]);
      expect(cltPermutation(21, 0xFFFFFFFF), <int>[
        14,
        10,
        4,
        1,
        15,
        0,
        17,
        13,
        6,
        8,
        11,
        9,
        2,
        5,
        3,
        19,
        18,
        12,
        7,
        16,
        20,
      ]);
    });

    test('SNO-F-CLT-02: раздел без перемешивания стоит как записан, '
        'перемешанный — по коду участника', () {
      // Порядки раздела «О задании» посчитаны на Python.
      expect(orderFor('67954332'), <String>[
        ...tlx,
        'gcl.2',
        'icl.2',
        'icl.1',
        'ecl.1',
        'ecl.3',
        'ecl.2',
        'gcl.1',
        ...orient,
      ]);
      expect(orderFor('38848228'), <String>[
        ...tlx,
        'icl.2',
        'ecl.1',
        'gcl.2',
        'ecl.3',
        'ecl.2',
        'icl.1',
        'gcl.1',
        ...orient,
      ]);
      expect(orderFor('00000000'), <String>[
        ...tlx,
        'gcl.1',
        'ecl.2',
        'ecl.3',
        'ecl.1',
        'icl.1',
        'gcl.2',
        'icl.2',
        ...orient,
      ]);
    });

    test('SNO-F-CLT-02: один код — один порядок, сколько бы раз часть ни '
        'начинали', () {
      expect(orderFor('61311465'), orderFor('61311465'));
      expect(orderFor('61311465'), isNot(orderFor('12345670')));
      // Каждый пункт показан ровно один раз.
      expect(orderFor('61311465').toSet(), hasLength(16));
    });

    test('SNO-F-CLT-02: у части после блока порядок один для всех', () {
      final CltScenario scenario = parseCltScenario(kBuiltinCltScenario);
      for (final String code in <String>['67954332', '00000000']) {
        expect(
          orderedCltItems(
            scenario.partFor(kCltBlockEnd)!,
            scenario: scenario.id,
            participant: code,
          ).single.id,
          'paas.effort',
        );
      }
    });
  });
}
