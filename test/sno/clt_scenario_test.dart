import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/builtin_scenario.dart';
import 'package:memoria/sno/clt/scenario.dart';

/// SNO-F-CLT-02, SNO-F-CLT-04: сценарий теста нагрузки как данные.
///
/// Третья версия встроенного сценария (правка шага 25): одна часть,
/// вступление, двадцать пунктов — среди них два маркера честности,
/// которые сверяются с записью, и два пункта шкалы лжи. Части «после
/// блока» в нём нет (SNO-F-REC-15), но вид такой части формат читает
/// по-прежнему.
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

  /// Встроенный сценарий с частью «после блока» впереди — какой она
  /// была в первой версии: формат её по-прежнему читает.
  Map<String, Object?> withBlockPart() {
    final Map<String, Object?> scenario = builtin();
    (scenario['parts']! as List<Object?>).insert(0, <String, Object?>{
      'id': 'A',
      'when': kCltBlockEnd,
      'password': false,
      'items': <Object?>[
        <String, Object?>{
          'id': 'paas.effort',
          'type': kCltScaleType,
          'min': 1,
          'max': 9,
          'step': 1,
          'text': 'Сколько умственных усилий вы вложили в это задание?',
        },
      ],
    });
    return scenario;
  }

  /// Пункт [id] итоговой части.
  Map<String, Object?> itemOf(Map<String, Object?> scenario, String id) {
    for (final Object? section
        in partOf(scenario, 'B')['sections']! as List<Object?>) {
      final Map<String, Object?> one = section! as Map<String, Object?>;
      for (final Object? item in one['items']! as List<Object?>) {
        final Map<String, Object?> entry = item! as Map<String, Object?>;
        if (entry['id'] == id) {
          return entry;
        }
      }
    }
    throw StateError('пункта $id нет');
  }

  /// Сверка маркера [id] с записью.
  Map<String, Object?> verifyOf(Map<String, Object?> scenario, String id) {
    return itemOf(scenario, id)['verify']! as Map<String, Object?>;
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
        expect(scenario.version, 3);
        expect(scenario.lang, 'ru');
        expect(scenario.parts, hasLength(1));
      }
    });

    test('SNO-F-REC-15: части «после блока» во встроенном сценарии нет — '
        'но формат её читает', () {
      final CltScenario scenario = parseCltScenario(kBuiltinCltScenario);
      expect(scenario.partFor(kCltBlockEnd), isNull);
      expect(<String>[
        for (final CltPart part in scenario.parts)
          for (final CltItem item in part.items) item.group,
      ], isNot(contains('paas')));

      final CltScenario old = parseCltScenario(withBlockPart());
      final CltPart block = old.partFor(kCltBlockEnd)!;
      expect(block.id, 'A');
      expect(block.password, isFalse);
      expect(block.items.single.id, 'paas.effort');
      expect(old.partFor(kCltSessionEnd)!.length, kBuiltinCltItems);
    });

    test('SNO-F-CLT-02: в конце сессии — двадцать пунктов по паролю: '
        'шесть шкал нагрузки, пункт о себе, восемь о задании, пять о '
        'полке', () {
      final CltPart part = parseCltScenario(kBuiltinCltScenario)
          .partFor(kCltSessionEnd)!;

      expect(part.id, 'B');
      expect(part.password, isTrue);
      expect(part.length, 20);
      expect(part.length, kBuiltinCltItems);
      expect(part.items, hasLength(20));
      expect(
        <String>[for (final CltSection section in part.sections) section.id],
        <String>['tlx', 'self', 'types', 'orient'],
      );
      expect(
        <bool>[for (final CltSection section in part.sections) section.shuffle],
        <bool>[false, false, true, false],
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
      expect(part.sections[1].items, hasLength(1));
      expect(part.sections[2].items, hasLength(8));
      expect(part.sections[3].items, hasLength(5));
      for (final CltItem item in <CltItem>[
        ...part.sections[1].items,
        ...part.sections[2].items,
        ...part.sections[3].items,
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
          for (final CltItem item in part.items)
            if (item.reverse) item.id,
        ],
        <String>['orient.3'],
      );
    });

    test('SNO-F-CLT-04: перед первым пунктом — вступление: оценивается вся '
        'работа, и изучение материала, и письменная часть', () {
      final CltPart part = parseCltScenario(kBuiltinCltScenario)
          .partFor(kCltSessionEnd)!;

      expect(
        part.intro,
        'Сейчас — короткий опрос о том, как прошла работа. Оценивайте её '
        'целиком: и то время, когда вы искали и читали материал в '
        'приложении, и письменную часть. Правильных и неправильных '
        'ответов здесь нет.',
      );
      // К честности вступление впрямую не призывает (решение владельца
      // АЗ): на неё отвечают пункты шкалы лжи.
      expect(part.intro, isNot(contains('честн')));
      expect(part.intro, isNot(contains('на самом деле')));
      // Сценарий без вступления читается как раньше.
      final Map<String, Object?> bare = builtin();
      partOf(bare, 'B').remove('intro');
      expect(parseCltScenario(bare).partFor(kCltSessionEnd)!.intro, isNull);
    });

    test('SNO-F-CLT-04: два маркера, которые сверяются с записью, — в '
        'перемешанном разделе и вторым в разделе о полке', () {
      final CltPart part = parseCltScenario(kBuiltinCltScenario)
          .partFor(kCltSessionEnd)!;

      expect(
        <String>[
          for (final CltItem item in part.items)
            if (item.isCheck) item.id,
        ],
        <String>['lie.defer', 'chk.focus', 'chk.books', 'lie.late'],
      );
      expect(part.sections[2].items.last.id, 'chk.focus');
      expect(part.sections[3].items[1].id, 'chk.books');

      final CltItem focus = part.sections[2].items.last;
      expect(
        focus.text,
        'За всё время работы я ни разу не отвлёкся — ни на секунду.',
      );
      final CltCheck first = focus.check!;
      // Отметка — ответ 7 из 7.
      expect(first.flag.holds(7), isTrue);
      expect(first.flag.holds(6), isFalse);
      // Расхождение с записью — 6–7 при отлучках.
      expect(first.fact, kCltFactAwayCount);
      expect(first.contradicts(6, 1), isTrue);
      expect(first.contradicts(7, 3), isTrue);
      expect(first.contradicts(5, 3), isFalse);
      expect(first.contradicts(7, 0), isFalse);

      final CltItem books = part.sections[3].items[1];
      expect(books.text, 'За время работы я не открыл ни одной книги.');
      final CltCheck second = books.check!;
      // Отметка — ответ 4 и больше.
      expect(second.flag.holds(4), isTrue);
      expect(second.flag.holds(3), isFalse);
      // Расхождение — «не открыл» при открытых книгах и «открывал» при
      // нуле открытых.
      expect(second.fact, kCltFactBookOpens);
      expect(second.contradicts(4, 1), isTrue);
      expect(second.contradicts(7, 14), isTrue);
      expect(second.contradicts(1, 14), isFalse);
      expect(second.contradicts(3, 0), isFalse);
      expect(second.contradicts(2, 0), isTrue);
      expect(second.contradicts(1, 0), isTrue);
      expect(second.contradicts(4, 0), isFalse);
      // Маркер на экране — та же шкала, что у соседей.
      expect(focus.scale.values, part.sections[2].items.first.scale.values);
      expect(books.scale.values, part.sections[3].items.first.scale.values);
    });

    test('SNO-F-CLT-04: шкала лжи — два пункта с противоположными ключами, '
        'с записью не сверяются', () {
      final CltPart part = parseCltScenario(kBuiltinCltScenario)
          .partFor(kCltSessionEnd)!;

      // Первый — слабость, которая есть у каждого: один в своём разделе,
      // первым на шкале согласия.
      final CltItem weakness = part.sections[1].items.single;
      expect(weakness.id, 'lie.defer');
      expect(
        weakness.text,
        'Мне случалось откладывать на потом дело, которое нужно было '
        'сделать сразу.',
      );
      // Отметка — несогласие: 1–3.
      expect(
        <int>[
          for (int value = 1; value <= 7; value++)
            if (weakness.check!.flag.holds(value)) value,
        ],
        <int>[1, 2, 3],
      );

      // Второй — достоинство, которого нет ни у кого: предпоследним в
      // разделе о полке.
      final CltItem virtue = part.sections[3].items[3];
      expect(virtue.id, 'lie.late');
      expect(virtue.text, 'Я ни разу в жизни никуда не опоздал.');
      // Отметка — согласие: 5–7.
      expect(
        <int>[
          for (int value = 1; value <= 7; value++)
            if (virtue.check!.flag.holds(value)) value,
        ],
        <int>[5, 6, 7],
      );

      for (final CltItem item in <CltItem>[weakness, virtue]) {
        expect(item.isCheck, isTrue, reason: item.id);
        expect(item.reverse, isFalse, reason: item.id);
        // Они не о сессии: сверять с журналом нечего.
        expect(item.check!.fact, isNull, reason: item.id);
        expect(item.check!.contradictions, isEmpty, reason: item.id);
        expect(item.check!.contradicts(7, 5), isFalse, reason: item.id);
        // Шкала — та же, что у соседей.
        expect(item.scale.values, <int>[1, 2, 3, 4, 5, 6, 7]);
      }
      // Какой бы ответ ни дали на оба сразу одной кнопкой, отметка
      // шкалы — ровно одна; середина шкалы — ни одной.
      for (int value = 1; value <= 7; value++) {
        final int flags =
            (weakness.check!.flag.holds(value) ? 1 : 0) +
            (virtue.check!.flag.holds(value) ? 1 : 0);
        expect(flags, value == 4 ? 0 : 1, reason: 'ответ $value');
      }
    });

    test('SNO-F-CLT-04: обычный пункт — не маркер', () {
      final CltPart part = parseCltScenario(kBuiltinCltScenario)
          .partFor(kCltSessionEnd)!;

      expect(<CltItem>[
        for (final CltItem item in part.items)
          if (!item.isCheck) item,
      ], hasLength(16));
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
      itemOf(scenario, 'orient.1')['type'] = 'choice';

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

      final Map<String, Object?> parts = withBlockPart();
      partOf(parts, 'B')['id'] = 'A';
      expect(refusal(parts), contains('часть «A» встречается дважды'));

      final Map<String, Object?> sections = builtin();
      sectionOf(sections, 'orient')['id'] = 'tlx';
      expect(refusal(sections), contains('раздел «tlx» встречается дважды'));
    });

    test('SNO-F-CLT-02: идентификатор, который не годится в имя файла', () {
      // По идентификаторам сценария и части называется файл ответов.
      expect(
        refusal(builtin()..['id'] = 'мой сценарий'),
        contains('идентификатор сценария «мой сценарий»'),
      );
      final Map<String, Object?> nested = builtin();
      partOf(nested, 'B')['id'] = 'B/2';
      expect(refusal(nested), contains('идентификатор части «B/2»'));
      final Map<String, Object?> hidden = builtin();
      partOf(hidden, 'B')['id'] = '.B';
      expect(refusal(hidden), contains('идентификатор части «.B»'));
      final Map<String, Object?> windows = builtin();
      partOf(windows, 'B')['id'] = r'B\2';
      expect(refusal(windows), contains('идентификатор части'));
      // Обычные имена проходят.
      final Map<String, Object?> fine = builtin();
      partOf(fine, 'B')['id'] = 'final_2.b-1';
      expect(parseCltScenario(fine).partFor(kCltSessionEnd)!.id, 'final_2.b-1');
    });

    test('SNO-F-CLT-02: вопрос после блока не может быть под паролем', () {
      final Map<String, Object?> locked = withBlockPart();
      partOf(locked, 'A')['password'] = true;

      expect(refusal(locked), contains('не может быть под паролем'));
    });

    test('SNO-F-CLT-02: две части в один миг и часть без мига', () {
      final Map<String, Object?> same = withBlockPart();
      partOf(same, 'A')['when'] = kCltSessionEnd;
      expect(refusal(same), contains('в один миг'));

      final Map<String, Object?> never = withBlockPart();
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
      itemOf(wordless, 'orient.1')['text'] = '  ';
      expect(refusal(wordless), contains('текст'));

      expect(refusal(builtin()..['version'] = 0), contains('версия'));
      expect(refusal(builtin()..['id'] = ''), contains('идентификатор'));
    });

    test('SNO-F-CLT-04: вступление — не строка или пустое', () {
      final Map<String, Object?> number = builtin();
      partOf(number, 'B')['intro'] = 7;
      expect(refusal(number), contains('вступление'));

      final Map<String, Object?> blank = builtin();
      partOf(blank, 'B')['intro'] = '   ';
      expect(refusal(blank), contains('вступление'));
    });

    test('SNO-F-CLT-04: маркер с неизвестной ролью, без отметки, с '
        'неизвестной сверкой', () {
      final Map<String, Object?> role = builtin();
      itemOf(role, 'chk.focus')['role'] = 'trap';
      expect(refusal(role), contains('неизвестная роль «trap»'));

      final Map<String, Object?> unflagged = builtin();
      itemOf(unflagged, 'chk.focus').remove('flag');
      expect(refusal(unflagged), contains('отметка'));

      final Map<String, Object?> boundless = builtin();
      itemOf(boundless, 'chk.focus')['flag'] = <String, Object?>{};
      expect(refusal(boundless), contains('не названа ни одна граница'));

      final Map<String, Object?> words = builtin();
      itemOf(words, 'chk.focus')['flag'] = <String, Object?>{'min': 'семь'};
      expect(refusal(words), contains('не целые числа'));

      final Map<String, Object?> upside = builtin();
      itemOf(upside, 'chk.focus')['flag'] = <String, Object?>{
        'min': 7,
        'max': 2,
      };
      expect(refusal(upside), contains('нижняя граница больше верхней'));

      // Маркер с неизвестным `verify.fact` — отказ сценария словами.
      final Map<String, Object?> fact = builtin();
      verifyOf(fact, 'chk.books')['fact'] = 'pages_read';
      expect(refusal(fact), contains('«pages_read»'));

      final Map<String, Object?> silent = builtin();
      verifyOf(silent, 'chk.books')['contradiction'] = <Object?>[];
      expect(refusal(silent), contains('расходится с записью'));

      final Map<String, Object?> none = builtin();
      verifyOf(none, 'chk.focus').remove('contradiction');
      expect(refusal(none), contains('не объект'));
    });

    test('SNO-F-CLT-04: отметка и сверка — только у маркера', () {
      final Map<String, Object?> flagged = builtin();
      itemOf(flagged, 'orient.1')['flag'] = <String, Object?>{'min': 7};
      expect(refusal(flagged), contains('только у маркера'));

      final Map<String, Object?> verified = builtin();
      itemOf(verified, 'orient.1')['verify'] = <String, Object?>{
        'fact': kCltFactBookOpens,
      };
      expect(refusal(verified), contains('только у маркера'));
    });

    test('SNO-F-CLT-04: маркер без сверки с записью принимается', () {
      final Map<String, Object?> scenario = builtin();
      itemOf(scenario, 'chk.focus').remove('verify');

      final CltCheck check = parseCltScenario(scenario)
          .partFor(kCltSessionEnd)!
          .sections[2]
          .items
          .last
          .check!;
      expect(check.fact, isNull);
      expect(check.contradictions, isEmpty);
      expect(check.contradicts(7, 5), isFalse);
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
    const List<String> orient = <String>[
      'orient.1',
      'chk.books',
      'orient.2',
      'lie.late',
      'orient.3',
    ];

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
      // Порядки раздела «О задании» — восемь пунктов, семь о нагрузке и
      // маркер, — посчитаны на Python.
      expect(orderFor('67954332'), <String>[
        ...tlx,
        'lie.defer',
        'gcl.2',
        'chk.focus',
        'ecl.3',
        'gcl.1',
        'icl.1',
        'ecl.2',
        'ecl.1',
        'icl.2',
        ...orient,
      ]);
      expect(orderFor('38848228'), <String>[
        ...tlx,
        'lie.defer',
        'icl.1',
        'ecl.1',
        'gcl.1',
        'chk.focus',
        'ecl.2',
        'gcl.2',
        'ecl.3',
        'icl.2',
        ...orient,
      ]);
      expect(orderFor('00000000'), <String>[
        ...tlx,
        'lie.defer',
        'icl.1',
        'chk.focus',
        'ecl.2',
        'gcl.2',
        'gcl.1',
        'ecl.1',
        'ecl.3',
        'icl.2',
        ...orient,
      ]);
    });

    test('SNO-F-CLT-02: один код — один порядок, сколько бы раз часть ни '
        'начинали', () {
      expect(orderFor('61311465'), orderFor('61311465'));
      expect(orderFor('61311465'), isNot(orderFor('12345670')));
      // Каждый пункт показан ровно один раз.
      expect(orderFor('61311465').toSet(), hasLength(20));
    });

    test('SNO-F-CLT-04: маркер перемешан с соседями — у разных участников '
        'он стоит на разных местах', () {
      // Места маркера М1 посчитаны на Python.
      expect(orderFor('67954332').indexOf('chk.focus'), 8);
      expect(orderFor('38848228').indexOf('chk.focus'), 10);
      expect(orderFor('61311465').indexOf('chk.focus'), 14);
      // Маркер М2 и оба пункта шкалы лжи стоят на своих местах у всех:
      // шкала лжи — седьмым и предпоследним.
      for (final String code in <String>['67954332', '38848228', '61311465']) {
        expect(orderFor(code).indexOf('lie.defer'), 6, reason: code);
        expect(orderFor(code).indexOf('chk.books'), 16, reason: code);
        expect(orderFor(code).indexOf('lie.late'), 18, reason: code);
      }
    });
  });
}
