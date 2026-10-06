import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/clt/builtin_scenario.dart';
import 'package:memoria/sno/clt/load_test.dart';
import 'package:memoria/sno/clt/results.dart';
import 'package:memoria/sno/clt/scenario.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/recording/summary.dart';

import '../support/recording_fakes.dart';

/// SNO-F-CLT-01, SNO-F-CLT-02, SNO-F-CLT-03: тест нагрузки без экрана.
///
/// Сессия записи — на памяти и подменённом времени, как в
/// `recording_session_test.dart`; тест нагрузки получает те же часы.
/// Проверяется, что о тесте решает код: пароль и пауза после неверных
/// попыток, порядок пунктов, что и когда ложится на диск и в журнал,
/// продолжение после перезапуска, итог и показатели при завершении
/// сессии. Экраны — в `clt_screens_test.dart`.
void main() {
  /// Пароль теста в этих проверках: двенадцать цифр — столько в
  /// журнале подряд случайно не встретится, и след пароля в нём не
  /// спутать с числом.
  const String password = '904172650318';

  /// Код участника, с которым начинают запись.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  /// Порядок итоговой части у участника [kTestCode] — посчитан на
  /// Python (`clt_scenario_test.dart`).
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

  /// Что участник отвечает на каждый пункт.
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

  /// Тест нагрузки поверх сессии [kit] — на её часах.
  LoadTest testOn(SessionKit kit, {ScenarioOverride? override}) {
    return LoadTest(
      session: kit.session,
      password: password,
      override: override,
      now: kit.time.now,
      elapsedMs: () => kit.time.monotonic,
    );
  }

  /// Файл [name] папки записи [folder].
  Map<String, Object?> fileOf(SessionKit kit, String folder, String name) {
    return kit.store.json(folder, name);
  }

  /// Ответы файла [file].
  List<Map<String, Object?>> answersOf(Map<String, Object?> file) {
    return <Map<String, Object?>>[
      for (final Object? answer in file['answers']! as List<Object?>)
        answer! as Map<String, Object?>,
    ];
  }

  /// События вида [type] в журнале папки [folder].
  List<Map<String, Object?>> eventsOf(
    SessionKit kit,
    String folder,
    String type,
  ) {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(folder))
        if (event['type'] == type) event,
    ];
  }

  /// Данные события [event].
  Map<String, Object?> dataOf(Map<String, Object?> event) {
    return event['data']! as Map<String, Object?>;
  }

  /// Отвечает на показанный пункт значением из [values]: участник
  /// думает [think] и ещё полсекунды тянется к «Дальше».
  Future<void> answerShown(
    SessionKit kit,
    LoadTestRun run, {
    Duration think = const Duration(seconds: 3),
  }) async {
    kit.time.pass(think);
    run.choose(values[run.item.id]!);
    kit.time.pass(const Duration(milliseconds: 500));
    await run.next();
  }

  /// Запись на [seconds] секунд, остановленная экспериментатором.
  Future<SessionKit> stoppedKit({int seconds = 600}) async {
    final SessionKit kit = SessionKit(hasTest: true);
    await kit.session.start(code);
    kit.run(seconds);
    await kit.session.stop(StopReason.experimenter);
    return kit;
  }

  /// «Приложение перезапущено»: новая сессия на том, что оставила
  /// [first].
  Future<SessionKit> restarted(SessionKit first) async {
    final SessionKit second = SessionKit(
      settings: first.settings,
      store: first.store,
      time: first.time,
      hasTest: true,
    );
    await second.session.restore();
    return second;
  }

  group('SNO-F-CLT-01: пароль', () {
    test('SNO-F-CLT-01: верный пароль открывает тест до завершения '
        'сессии', () async {
      final SessionKit kit = await stoppedKit();
      final LoadTest test = testOn(kit);
      await test.load();

      expect(test.passwordLength, password.length);
      expect(test.unlocked, isFalse);
      // Под замком итоговая часть не начинается.
      expect(await test.begin(kCltSessionEnd), isNull);

      expect(await test.enter(password), PasswordOutcome.accepted);

      expect(test.unlocked, isTrue);
      final LoadTestRun? run = await test.begin(kCltSessionEnd);
      expect(run, isNotNull);
      // Повторный вход пароля не требует — и после того, как экран
      // теста закрыли.
      run!.dispose();
      expect(test.unlocked, isTrue);
      expect(await test.begin(kCltSessionEnd), isNotNull);

      await kit.session.finish();

      // Сессия завершена: замок закрыт, и следующей сессии он закрыт.
      expect(test.unlocked, isFalse);
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      expect(test.unlocked, isFalse);
      test.dispose();
      kit.session.dispose();
    });

    test(
      'SNO-F-CLT-01: три неверные попытки закрывают ввод на минуту',
      () async {
        final SessionKit kit = await stoppedKit();
        final String folder = kit.folder;
        final LoadTest test = testOn(kit);

        expect(await test.enter('нет-1'), PasswordOutcome.wrong);
        expect(await test.enter('нет-2'), PasswordOutcome.wrong);
        expect(test.lockedSeconds, 0);
        expect(await test.enter('нет-3'), PasswordOutcome.locked);

        expect(test.lockedSeconds, 60);
        // Пока ввод закрыт, не проходит и верный пароль.
        expect(await test.enter(password), PasswordOutcome.locked);
        expect(test.unlocked, isFalse);
        kit.time.pass(const Duration(seconds: 59));
        expect(test.lockedSeconds, 1);
        kit.time.pass(const Duration(milliseconds: 500));
        expect(test.lockedSeconds, 1);
        kit.time.pass(const Duration(milliseconds: 500));
        expect(test.lockedSeconds, 0);

        expect(await test.enter(password), PasswordOutcome.accepted);
        expect(test.unlocked, isTrue);

        // В журнале — попытки: удалась или нет, без самого ввода. Попытка
        // при закрытом вводе попыткой не считается.
        final List<Map<String, Object?>> attempts = eventsOf(
          kit,
          folder,
          'clt.password.attempt',
        );
        expect(
          <Object?>[for (final attempt in attempts) attempt['data']],
          [
            <String, Object?>{'ok': false, 'n': 1},
            <String, Object?>{'ok': false, 'n': 2},
            <String, Object?>{'ok': false, 'n': 3, 'locked_s': 60},
            <String, Object?>{'ok': true, 'n': 4},
          ],
        );
        for (final Map<String, Object?> attempt in attempts) {
          expect(attempt['phase'], 'post');
        }
        final String journal = kit.store.lines(folder).join('\n');
        expect(journal, isNot(contains(password)));
        expect(journal, isNot(contains('нет-')));
        test.dispose();
        kit.session.dispose();
      },
    );

    test('SNO-F-CLT-01: счёт неверных попыток начинается заново после '
        'верной и после паузы', () async {
      final SessionKit kit = await stoppedKit();
      final LoadTest test = testOn(kit);

      expect(await test.enter('а'), PasswordOutcome.wrong);
      expect(await test.enter('б'), PasswordOutcome.wrong);
      expect(await test.enter(password), PasswordOutcome.accepted);
      expect(await test.enter('в'), PasswordOutcome.wrong);
      expect(await test.enter('г'), PasswordOutcome.wrong);
      expect(await test.enter('д'), PasswordOutcome.locked);
      kit.time.pass(const Duration(seconds: 60));
      expect(await test.enter('е'), PasswordOutcome.wrong);
      expect(test.lockedSeconds, 0);
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-01: пароль, который на экране не набрать, — теста '
        'нет, и причина названа', () async {
      expect(isEnterablePassword('2580'), isTrue);
      expect(isEnterablePassword('0'), isTrue);
      expect(isEnterablePassword('123456789012'), isTrue);
      expect(isEnterablePassword('1234567890123'), isFalse);
      expect(isEnterablePassword(''), isFalse);
      expect(isEnterablePassword('25a0'), isFalse);
      expect(isEnterablePassword('2580\n'), isFalse);
      expect(isEnterablePassword(' 2580'), isFalse);

      // В секрет сборки попала буква: такой пароль запер бы тест
      // навсегда — и молча.
      final SessionKit kit = await stoppedKit();
      final LoadTest test = LoadTest(session: kit.session, password: '25a0');
      await test.load();

      expect(test.scenario, isNull);
      expect(test.problem, contains('не набрать'));
      expect(test.finalItems, 0);
      expect(await test.begin(kCltSessionEnd, dry: true), isNull);
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-01: без остановленной сессии пароль теста не '
        'отпирает', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      final LoadTest test = testOn(kit);

      // Записи нет — пробный проход: пароль спрашивается каждый раз.
      expect(await test.enter(password), PasswordOutcome.accepted);
      expect(test.unlocked, isFalse);

      // Запись идёт — итоговая часть закрыта.
      await kit.session.start(code);
      expect(await test.enter(password), PasswordOutcome.accepted);
      expect(test.unlocked, isFalse);
      expect(await test.begin(kCltSessionEnd), isNull);
      test.dispose();
      kit.session.dispose();
    });
  });

  group('SNO-F-CLT-02: сценарий', () {
    /// Встроенный сценарий, прошедший через JSON.
    Map<String, Object?> builtin() {
      return jsonDecode(jsonEncode(kBuiltinCltScenario))
          as Map<String, Object?>;
    }

    test(
      'SNO-F-CLT-02: без файла в папке приложения берётся встроенный',
      () async {
        final SessionKit kit = SessionKit(hasTest: true);
        final List<String> asked = <String>[];
        final LoadTest test = testOn(
          kit,
          override: (String id) async {
            asked.add(id);
            return null;
          },
        );

        expect(test.loaded, isFalse);
        await test.load();
        await test.load();

        expect(test.loaded, isTrue);
        expect(test.problem, isNull);
        expect(test.overridden, isFalse);
        expect(test.scenario!.id, 'sno-clt-main');
        expect(test.finalItems, 16);
        // Файл ищут по идентификатору сценария — и один раз.
        expect(asked, <String>['sno-clt-main']);
        test.dispose();
        kit.session.dispose();
      },
    );

    test('SNO-F-CLT-02: файл с тем же id подменяет встроенный', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final Map<String, Object?> changed = builtin()..['version'] = 2;
      final List<Object?> parts = changed['parts']! as List<Object?>;
      final List<Object?> items =
          (parts.first! as Map<String, Object?>)['items']! as List<Object?>;
      (items.single! as Map<String, Object?>)['text'] =
          'Насколько было трудно?';
      final String text = jsonEncode(changed);
      final LoadTest test = testOn(kit, override: (String id) async => text);
      await test.load();

      expect(test.problem, isNull);
      expect(test.overridden, isTrue);
      expect(test.scenario!.version, 2);

      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;

      // Сценарий, каким его видел участник, лежит рядом с ответами, а
      // событие начала говорит, что он подменён.
      expect(kit.store.files[folder]![kCltScenarioFile], text);
      expect(fileOf(kit, folder, run.fileName)['version'], 2);
      expect(
        dataOf(eventsOf(kit, folder, 'clt.start').single)['override'],
        isTrue,
      );
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: сценарий с ошибкой — причина названа, тест не '
        'начинается', () async {
      Future<String?> problemOf(ScenarioOverride override) async {
        final SessionKit kit = await stoppedKit();
        final LoadTest test = testOn(kit, override: override);
        await test.load();
        expect(test.loaded, isTrue);
        expect(test.scenario, isNull);
        expect(test.finalItems, 0);
        expect(test.pendingEfforts, isEmpty);
        await test.enter(password);
        expect(await test.begin(kCltSessionEnd), isNull);
        expect(await test.begin(kCltSessionEnd, dry: true), isNull);
        // Ни одного файла теста на диск не легло.
        expect(await kit.session.testFiles(), isEmpty);
        final String? problem = test.problem;
        test.dispose();
        kit.session.dispose();
        return problem;
      }

      expect(
        await problemOf((String id) async => '{"schema":'),
        'файл сценария — не JSON',
      );
      final Map<String, Object?> unknown = builtin();
      final List<Object?> parts = unknown['parts']! as List<Object?>;
      final List<Object?> items =
          (parts.first! as Map<String, Object?>)['items']! as List<Object?>;
      (items.single! as Map<String, Object?>)['type'] = 'choice';
      expect(
        await problemOf((String id) async => jsonEncode(unknown)),
        contains('неизвестный вид пункта «choice»'),
      );
      expect(
        await problemOf(
          (String id) async => jsonEncode(builtin()..['id'] = 'other-test'),
        ),
        'в файле сценарий «other-test», а нужен «sno-clt-main»',
      );
      expect(
        await problemOf((String id) => throw StateError('диск')),
        'файл сценария не прочитался',
      );
    });
  });

  group('SNO-F-CLT-02: усилие после блока', () {
    test('SNO-F-CLT-02: блок закрыт — один вопрос без пароля, ответ сразу '
        'на диске', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.load();
      kit.run(60);
      kit.session.startBlock(1);
      kit.run(120);
      kit.session.endBlock();
      final BlockMark block = kit.session.blocks.last;

      expect(test.unlocked, isFalse);
      expect(test.pendingEfforts.single.number, 1);
      final LoadTestRun run = (await test.begin(kCltBlockEnd, block: block))!;

      expect(run.dry, isFalse);
      expect(run.length, 1);
      expect(run.item.id, 'paas.effort');
      expect(run.block!.number, 1);
      // Ответ обязателен: без выбранного значения дальше не пройти.
      expect(run.canNext, isFalse);
      expect(run.canBack, isFalse);
      await run.next();
      expect(run.finished, isFalse);
      expect(run.fileName, matches(RegExp(r'^clt/sno-clt-main_A_\d+\.json$')));
      // Файл части лежит с первого мига — пока без ответов.
      final Map<String, Object?> begun = fileOf(kit, folder, run.fileName);
      expect(begun['complete'], isFalse);
      expect(begun['answers'], isEmpty);
      expect(begun['t_start'], 180000);

      kit.time.pass(const Duration(milliseconds: 4200));
      // Значения мимо шкалы не принимаются.
      run.choose(0);
      run.choose(10);
      expect(run.selected, isNull);
      run.choose(4);
      run.choose(6);
      kit.time.pass(const Duration(milliseconds: 800));
      await run.next();

      expect(run.finished, isTrue);
      expect(test.pendingEfforts, isEmpty);
      expect(fileOf(kit, folder, run.fileName), <String, Object?>{
        'schema': 'sno2026-clt-result/1',
        'scenario': 'sno-clt-main',
        'version': 1,
        'participant': kTestCode,
        'part': 'A',
        'block': 1,
        'block_start_ms': 60000,
        't_start': 180000,
        't_end': 185000,
        'complete': true,
        'order': <String>['paas.effort'],
        'answers': <Object?>[
          <String, Object?>{
            'item': 'paas.effort',
            'value': 6,
            // Время ответа — до выбора значения, а не до «Дальше».
            'rt_ms': 4200,
            'order': 1,
            't': 185000,
            'min': 1,
            'max': 9,
          },
        ],
      });
      // Сценарий, каким его видел участник, — рядом, и он разбирается.
      expect(
        parseCltScenario(
          jsonDecode(kit.store.files[folder]![kCltScenarioFile]!),
        ).id,
        'sno-clt-main',
      );

      // Запись идёт: события теста — обычные строки журнала.
      kit.session.tick();
      await kit.settle();
      final List<String> types = kit.store.types(folder);
      expect(
        types.sublist(types.indexOf('block.end')),
        containsAllInOrder(<String>['block.end', 'clt.start', 'clt.finish']),
      );
      final Map<String, Object?> start = eventsOf(
        kit,
        folder,
        'clt.start',
      ).single;
      expect(start.containsKey('phase'), isFalse);
      expect(dataOf(start), <String, Object?>{
        'part': 'A',
        'block': 1,
        'file': run.fileName,
        'scenario': 'sno-clt-main',
        'version': 1,
        'items': 1,
      });
      expect(dataOf(eventsOf(kit, folder, 'clt.finish').single), {
        'part': 'A',
        'block': 1,
        'file': run.fileName,
        'answers': 1,
        'duration_ms': 5000,
      });
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: блок, который закрыла остановка записи, ждёт '
        'оценки на экране завершения', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.load();
      kit.run(30);
      kit.session.startBlock(1);
      kit.run(60);
      kit.session.endBlock();
      final LoadTestRun first = (await test.begin(
        kCltBlockEnd,
        block: kit.session.blocks.last,
      ))!;
      first.choose(5);
      await first.next();
      kit.session.startBlock(2);
      kit.run(45);

      await kit.session.stop(StopReason.experimenter);

      // Оценён только первый блок; второй закрыла остановка.
      final BlockMark open = test.pendingEfforts.single;
      expect(open.number, 2);
      expect(open.closedBy, 'stop');
      final LoadTestRun second = (await test.begin(kCltBlockEnd, block: open))!;
      second.choose(7);
      await second.next();

      expect(test.pendingEfforts, isEmpty);
      final Map<String, Object?> file = fileOf(kit, folder, second.fileName);
      expect(file['block'], 2);
      expect(file['block_start_ms'], open.startMs);
      expect(answersOf(file).single['value'], 7);
      // После остановки события теста помечены и лежат на диске сразу.
      final List<Map<String, Object?>> finishes = eventsOf(
        kit,
        folder,
        'clt.finish',
      );
      expect(finishes, hasLength(2));
      expect(finishes.first.containsKey('phase'), isFalse);
      expect(finishes.last['phase'], 'post');
      first.dispose();
      second.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: за оценённый блок второй раз не спрашивают', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final LoadTest test = testOn(kit);
      kit.session.startBlock(1);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);
      await test.load();
      final BlockMark block = test.pendingEfforts.single;
      final LoadTestRun run = (await test.begin(kCltBlockEnd, block: block))!;
      run.choose(4);
      await run.next();

      // Кнопку могли нажать второй раз, пока экран уходил.
      expect(test.effortGiven(block), isTrue);
      expect(await test.begin(kCltBlockEnd, block: block), isNull);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: оценка не легла на диск — блок не оценён, '
        '«Дальше» пробует ещё раз', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      kit.session.startBlock(1);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);
      await test.load();
      final BlockMark block = test.pendingEfforts.single;
      final LoadTestRun run = (await test.begin(kCltBlockEnd, block: block))!;
      kit.store.failPutPrefix = 'clt/';
      run.choose(7);

      await run.next();

      // Ответ единственный и последний: пока он не на диске, часть не
      // окончена, экран не уходит, блок ждёт оценки.
      expect(run.finished, isFalse);
      expect(run.saveFailed, isTrue);
      expect(run.canNext, isTrue);
      expect(test.pendingEfforts.single.number, 1);
      expect(eventsOf(kit, folder, 'clt.finish'), isEmpty);
      expect(fileOf(kit, folder, run.fileName)['complete'], isFalse);

      kit.store.failPutPrefix = null;
      await run.next();

      expect(run.finished, isTrue);
      expect(run.saveFailed, isFalse);
      expect(test.pendingEfforts, isEmpty);
      final Map<String, Object?> file = fileOf(kit, folder, run.fileName);
      expect(file['complete'], isTrue);
      expect(answersOf(file).single['value'], 7);
      expect(eventsOf(kit, folder, 'clt.finish'), hasLength(1));
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: две оценки подряд в один миг ложатся в два '
        'файла', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      // Первый блок закрыт, но вопрос о нём не задан; второй закрыла
      // остановка.
      kit.session.startBlock(1);
      kit.run(30);
      kit.session.endBlock();
      kit.session.startBlock(2);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);
      await test.load();
      expect(test.pendingEfforts, hasLength(2));

      // Часы между ответами не идут: имя файла различает части по
      // времени начала, и вторая не должна затереть первую.
      final LoadTestRun first = (await test.begin(
        kCltBlockEnd,
        block: test.pendingEfforts.first,
      ))!;
      first.choose(3);
      await first.next();
      final LoadTestRun second = (await test.begin(
        kCltBlockEnd,
        block: test.pendingEfforts.single,
      ))!;
      second.choose(8);
      await second.next();

      expect(second.fileName, isNot(first.fileName));
      expect(test.pendingEfforts, isEmpty);
      expect(answersOf(fileOf(kit, folder, first.fileName)).single['value'], 3);
      expect(
        answersOf(fileOf(kit, folder, second.fileName)).single['value'],
        8,
      );
      expect(fileOf(kit, folder, first.fileName)['block'], 1);
      expect(fileOf(kit, folder, second.fileName)['block'], 2);
      first.dispose();
      second.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: два блока с одним номером — два вопроса', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final LoadTest test = testOn(kit);
      await test.load();
      kit.session.startBlock(1);
      kit.run(30);
      kit.session.endBlock();
      kit.session.startBlock(1);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);

      expect(test.pendingEfforts, hasLength(2));
      final LoadTestRun run = (await test.begin(
        kCltBlockEnd,
        block: test.pendingEfforts.first,
      ))!;
      run.choose(3);
      await run.next();

      // Оценён первый из двух: второй, с тем же номером, ещё ждёт.
      expect(test.pendingEfforts.single.startMs, 30000);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: вопрос, на который не успели ответить, задаётся '
        'снова — в том же файле', () async {
      final SessionKit first = SessionKit(hasTest: true);
      await first.session.start(code);
      final String folder = first.folder;
      final LoadTest before = testOn(first);
      first.session.startBlock(1);
      first.run(30);
      first.session.endBlock();
      final LoadTestRun asked = (await before.begin(
        kCltBlockEnd,
        block: first.session.blocks.last,
      ))!;
      first.session.tick();
      await first.settle();
      // Приложение закрыли, пока вопрос стоял на экране.
      asked.dispose();
      before.dispose();
      first.session.dispose();

      final SessionKit second = await restarted(first);
      final LoadTest after = testOn(second);
      await after.load();
      await after.refresh();

      final BlockMark open = after.pendingEfforts.single;
      expect(open.number, 1);
      final LoadTestRun again = (await after.begin(kCltBlockEnd, block: open))!;
      expect(again.fileName, asked.fileName);
      again.choose(8);
      await again.next();

      expect(after.pendingEfforts, isEmpty);
      expect(
        second.store.files[folder]!.keys.where(
          (String name) => name.contains('_A_'),
        ),
        hasLength(1),
      );
      again.dispose();
      after.dispose();
      second.session.dispose();
    });
  });

  group('SNO-F-CLT-02, SNO-F-CLT-03: итоговая часть', () {
    test('SNO-F-CLT-02: шестнадцать пунктов в порядке участника, каждый '
        'ответ сразу на диске', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;

      expect(run.length, 16);
      expect(<String>[for (final CltItem item in run.items) item.id], order);
      expect(run.block, isNull);
      expect(test.finalDone, isFalse);
      for (int i = 0; i < 16; i++) {
        expect(run.index, i);
        expect(run.item.id, order[i]);
        expect(run.selected, isNull);
        await answerShown(kit, run, think: Duration(milliseconds: 3000 + i));
        // Ответ лёг в файл сразу, а не в конце части.
        final Map<String, Object?> file = fileOf(kit, folder, run.fileName);
        expect(answersOf(file), hasLength(i + 1));
        expect(file['complete'], i == 15);
        expect(test.finalResult!.answers, hasLength(i + 1));
      }

      expect(run.finished, isTrue);
      expect(run.answered, 16);
      expect(run.canNext, isFalse);
      expect(run.canBack, isFalse);
      expect(test.finalDone, isTrue);
      final Map<String, Object?> file = fileOf(kit, folder, run.fileName);
      expect(file['part'], 'B');
      expect(file['block'], isNull);
      expect(file['order'], order);
      final List<Map<String, Object?>> answers = answersOf(file);
      expect(<Object?>[for (final answer in answers) answer['item']], order);
      expect(
        <Object?>[for (final answer in answers) answer['value']],
        [for (final String id in order) values[id]],
      );
      expect(
        <Object?>[for (final answer in answers) answer['order']],
        [for (int i = 1; i <= 16; i++) i],
      );
      expect(
        <Object?>[for (final answer in answers) answer['rt_ms']],
        [for (int i = 0; i < 16; i++) 3000 + i],
      );
      expect(answers[6], <String, Object?>{
        'item': 'gcl.2',
        'value': 7,
        'rt_ms': 3006,
        'order': 7,
        't': answers[6]['t'],
        'min': 1,
        'max': 7,
      });
      expect(answers.first['min'], 0);
      expect(answers.first['max'], 100);
      // Обратный счёт помечен у ответа: файл понимается без сценария.
      expect(answers.last['reverse'], isTrue);
      expect(answers[14].containsKey('reverse'), isFalse);

      final Map<String, Object?> start = eventsOf(
        kit,
        folder,
        'clt.start',
      ).single;
      expect(start['phase'], 'post');
      expect(dataOf(start)['items'], 16);
      expect(dataOf(start).containsKey('block'), isFalse);
      final Map<String, Object?> finish = eventsOf(
        kit,
        folder,
        'clt.finish',
      ).single;
      expect(dataOf(finish)['answers'], 16);
      expect(
        dataOf(finish)['duration_ms'],
        (file['t_end']! as int) - (file['t_start']! as int),
      );
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: вернуться можно на один пункт, пропустить — '
        'нельзя', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;

      // Без ответа дальше не пройти.
      await run.next();
      expect(run.index, 0);
      run.choose(65);
      await run.next();
      expect(run.index, 1);
      run.choose(20);

      // Назад — на один пункт: там стоит прежний ответ.
      expect(run.canBack, isTrue);
      run.back();
      expect(run.index, 0);
      expect(run.selected, 65);
      expect(run.canBack, isFalse);
      run.back();
      expect(run.index, 0);
      kit.time.pass(const Duration(milliseconds: 1500));
      run.choose(60);
      await run.next();

      // Выбранное на втором пункте до возврата не принято: его не
      // подтверждали.
      expect(run.index, 1);
      expect(run.selected, isNull);
      run.choose(25);
      await run.next();
      expect(run.index, 2);
      // Со второго на первый вернуться уже нельзя — только на один назад.
      run.back();
      expect(run.index, 1);
      expect(run.selected, 25);
      expect(run.canBack, isFalse);
      // Вернулся и ничего не поменял — ответ остаётся прежним.
      await run.next();

      final List<Map<String, Object?>> answers = answersOf(
        fileOf(kit, folder, run.fileName),
      );
      expect(answers, hasLength(2));
      expect(answers[0]['value'], 60);
      expect(answers[0]['revised'], isTrue);
      expect(answers[0]['rt_ms'], 1500);
      expect(answers[0]['order'], 1);
      expect(answers[1]['value'], 25);
      expect(answers[1].containsKey('revised'), isFalse);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-02: значение сдвигается на деление и не уходит за '
        'края шкалы', () async {
      final SessionKit kit = await stoppedKit();
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;

      // Без выбранного сдвиг ставит на середину шкалы 0…100.
      run.nudge(1);
      expect(run.selected, 50);
      run.nudge(1);
      expect(run.selected, 55);
      run.nudge(-3);
      expect(run.selected, 40);
      run.nudge(-20);
      expect(run.selected, 0);
      run.nudge(40);
      expect(run.selected, 100);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: тест, оборванный перезапуском, продолжается с '
        'первого неотвеченного пункта в том же файле', () async {
      final SessionKit first = await stoppedKit();
      final String folder = first.folder;
      final LoadTest before = testOn(first);
      await before.enter(password);
      final LoadTestRun begun = (await before.begin(kCltSessionEnd))!;
      for (int i = 0; i < 5; i++) {
        await answerShown(first, begun);
      }
      // Шестой пункт выбран, но «Дальше» не нажато — и приложение
      // закрыли.
      begun.choose(25);
      begun.dispose();
      before.dispose();
      first.session.dispose();

      final SessionKit second = await restarted(first);
      final LoadTest after = testOn(second);
      await after.load();
      await after.refresh();

      // Пять данных ответов целы.
      expect(after.finalResult!.answers, hasLength(5));
      expect(after.finalDone, isFalse);
      // Замок после перезапуска закрыт.
      expect(after.unlocked, isFalse);
      expect(await after.begin(kCltSessionEnd), isNull);
      await after.enter(password);
      final LoadTestRun resumed = (await after.begin(kCltSessionEnd))!;

      expect(resumed.fileName, begun.fileName);
      expect(resumed.index, 5);
      expect(resumed.item.id, 'tlx.frustration');
      expect(resumed.selected, isNull);
      expect(resumed.answered, 5);
      // К пятому пункту, отвеченному до перезапуска, вернуться можно.
      expect(resumed.canBack, isTrue);
      while (!resumed.finished) {
        await answerShown(second, resumed);
      }

      expect(after.finalDone, isTrue);
      final Map<String, Object?> file = fileOf(second, folder, begun.fileName);
      expect(file['complete'], isTrue);
      expect(
        <Object?>[
          for (final Map<String, Object?> answer in answersOf(file))
            answer['value'],
        ],
        <int?>[for (final String id in order) values[id]],
      );
      // Файл итоговой части — один.
      expect(
        second.store.files[folder]!.keys.where(
          (String name) => name.contains('_B_'),
        ),
        hasLength(1),
      );
      final List<Map<String, Object?>> starts = eventsOf(
        second,
        folder,
        'clt.start',
      );
      expect(starts, hasLength(2));
      expect(dataOf(starts.first).containsKey('resumed_at'), isFalse);
      expect(dataOf(starts.last)['resumed_at'], 6);
      // Номера событий после перезапуска продолжают журнал.
      final List<Object?> numbers = <Object?>[
        for (final Map<String, Object?> event in second.store.events(folder))
          event['seq'],
      ];
      expect(numbers, <int>[for (int i = 1; i <= numbers.length; i++) i]);
      resumed.dispose();
      after.dispose();
      second.session.dispose();
    });

    test('SNO-F-CLT-03: ответ не лёг на диск — сказано, следующий ответ '
        'приносит и его', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;
      expect(run.saveFailed, isFalse);
      expect(kit.session.writeFailed, isFalse);

      kit.store.failPutPrefix = 'clt/';
      await answerShown(kit, run);

      expect(run.saveFailed, isTrue);
      expect(kit.session.writeFailed, isTrue);
      expect(run.index, 1);
      expect(answersOf(fileOf(kit, folder, run.fileName)), isEmpty);

      kit.store.failPutPrefix = null;
      await answerShown(kit, run);

      expect(run.saveFailed, isFalse);
      expect(answersOf(fileOf(kit, folder, run.fileName)), hasLength(2));
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: пробный проход ничего не пишет', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      final LoadTest test = testOn(kit);
      final LoadTestRun run = (await test.begin(kCltSessionEnd, dry: true))!;

      expect(run.dry, isTrue);
      expect(run.length, 16);
      while (!run.finished) {
        run.nudge(1);
        await run.next();
      }

      expect(run.saveFailed, isFalse);
      expect(kit.store.files, isEmpty);
      expect(kit.store.journals, isEmpty);
      expect(test.results, isEmpty);
      expect(test.finalDone, isFalse);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });
  });

  group('SNO-F-CLT-03: тест в записи при завершении сессии', () {
    /// Сведения записи папки [folder].
    Map<String, Object?> infoOf(SessionKit kit, String folder) {
      return kit.store.json(folder, kRecordingFile);
    }

    test('SNO-F-CLT-03: показатели посчитаны, итог — в сведениях записи, '
        'журнал проверен весь', () async {
      final SessionKit kit = SessionKit(hasTest: true);
      await kit.session.start(code);
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.load();
      // Два блока: первый закрыл экспериментатор, второй — остановка.
      kit.run(60);
      kit.session.startBlock(1);
      kit.run(600);
      kit.session.endBlock();
      final LoadTestRun first = (await test.begin(
        kCltBlockEnd,
        block: kit.session.blocks.last,
      ))!;
      first.choose(6);
      await first.next();
      kit.session.startBlock(2);
      kit.run(600);
      await kit.session.stop(StopReason.experimenter);
      final LoadTestRun second = (await test.begin(
        kCltBlockEnd,
        block: test.pendingEfforts.single,
      ))!;
      second.choose(7);
      await second.next();
      await test.enter(password);
      final LoadTestRun last = (await test.begin(kCltSessionEnd))!;
      while (!last.finished) {
        await answerShown(kit, last);
      }

      await kit.session.finish();

      final Map<String, Object?> info = infoOf(kit, folder);
      expect(info['clt'], <String, Object?>{
        'effort_answers': 2,
        'final': 'complete',
        'final_answers': 16,
        'final_items': 16,
        'files': <String>[first.fileName, second.fileName, last.fileName],
      });
      // Показатели — те же, что считает правило по файлам ответов; сами
      // числа сверены со второй реализацией в `clt_results_test.dart`.
      final Map<String, Object?> scores = fileOf(kit, folder, kCltScoresFile);
      expect(
        scores,
        jsonDecode(
          jsonEncode(
            cltScores(readCltResults(await kit.store.texts(folder, 'clt'))),
          ),
        ),
      );
      final Map<String, Object?> groups =
          (scores['final']! as Map<String, Object?>)['scores']!
              as Map<String, Object?>;
      expect((groups['tlx']! as Map<String, Object?>)['mean'], 42.5);
      expect((groups['ecl']! as Map<String, Object?>)['mean'], 3.0);
      expect((groups['orient']! as Map<String, Object?>)['mean'], 5.667);
      final List<Object?> blocks = scores['blocks']! as List<Object?>;
      expect(
        <Object?>[
          for (final Object? block in blocks)
            ((((block! as Map<String, Object?>)['scores']!
                    as Map<String, Object?>)['paas']!)
                as Map<String, Object?>)['sum'],
        ],
        <int>[6, 7],
      );

      // Самопроверка повторена при завершении: она покрывает события
      // теста и само завершение.
      final List<String> lines = kit.store.lines(folder);
      expect(lines.last, contains('"session.finish"'));
      expect(lines.join(), contains('"clt.finish"'));
      final Map<String, Object?> recording =
          info['recording']! as Map<String, Object?>;
      expect(recording['check'], <String, Object?>{
        'lines': lines.length,
        'gaps': 0,
        'torn': false,
      });
      expect(recording['events'], lines.length);
      first.dispose();
      second.dispose();
      last.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: сессию завершили без теста — так и записано', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;

      await kit.session.finish();

      expect(infoOf(kit, folder)['clt'], <String, Object?>{
        'effort_answers': 0,
        'final': 'none',
        'files': <String>[],
      });
      // Показателей нет: считать не по чему.
      expect(kit.store.files[folder]!.containsKey(kCltScoresFile), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: итоговая часть не окончена — так и записано, а '
        'данные ответы посчитаны', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;
      for (int i = 0; i < 9; i++) {
        await answerShown(kit, run);
      }

      await kit.session.finish();

      final Map<String, Object?> clt =
          infoOf(kit, folder)['clt']! as Map<String, Object?>;
      expect(clt['final'], 'partial');
      expect(clt['final_answers'], 9);
      expect(clt['final_items'], 16);
      final Map<String, Object?> last =
          fileOf(kit, folder, kCltScoresFile)['final']! as Map<String, Object?>;
      expect(last['complete'], isFalse);
      expect(last['answers'], 9);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });

    test(
      'SNO-F-CLT-03: в сборке без теста о тесте в записи ни слова',
      () async {
        final SessionKit kit = SessionKit();
        await kit.session.start(code);
        final String folder = kit.folder;
        kit.run(30);
        await kit.session.stop(StopReason.experimenter);

        await kit.session.finish();

        expect(infoOf(kit, folder).containsKey('clt'), isFalse);
        kit.session.dispose();
      },
    );

    test('SNO-F-CLT-03: файлы теста не прочитались — итог неизвестен, '
        'сессия завершена', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      kit.store.failTexts = true;

      await kit.session.finish();

      expect(kit.session.phase, RecordingPhase.idle);
      expect(infoOf(kit, folder)['clt'], <String, Object?>{'final': 'unknown'});
      kit.session.dispose();
    });

    test('SNO-F-CLT-03: строка теста, оборванная закрытием приложения, не '
        'делает запись целой', () async {
      final SessionKit first = await stoppedKit();
      final String folder = first.folder;
      expect(first.session.check!.intact, isTrue);
      final LoadTest before = testOn(first);
      await before.enter(password);
      // Приложение умерло посреди строки события теста.
      first.store.journals[folder]!.write('{"seq":999,"t":6000');
      before.dispose();
      first.session.dispose();

      final SessionKit second = await restarted(first);

      // Оборванный хвост виден при запуске — до того, как чтение
      // журнала его отрежет.
      expect(second.session.check!.torn, isTrue);
      expect(second.session.check!.intact, isFalse);
      await second.session.finish();

      // К повторной проверке хвост уже отрезан, но итог о нём помнит.
      final Map<String, Object?> check =
          (infoOf(second, folder)['recording']!
                  as Map<String, Object?>)['check']!
              as Map<String, Object?>;
      expect(check['torn'], isTrue);
      expect(check['lines'], second.store.lines(folder).length);
      expect(second.store.lines(folder).join(), isNot(contains('"seq":999')));
      second.session.dispose();
    });

    test('SNO-F-CLT-03: после завершения сессии тест в её папку не '
        'пишет', () async {
      final SessionKit kit = await stoppedKit();
      final String folder = kit.folder;
      final LoadTest test = testOn(kit);
      await test.enter(password);
      final LoadTestRun run = (await test.begin(kCltSessionEnd))!;
      await answerShown(kit, run);
      final int lines = kit.store.lines(folder).length;

      await kit.session.finish();
      final Map<String, Object?> before = fileOf(kit, folder, run.fileName);
      run.choose(40);
      await run.next();

      // Ни файла, ни строки журнала: сессии, в чью папку писать, нет.
      expect(fileOf(kit, folder, run.fileName), before);
      expect(kit.store.lines(folder).length, lines + 1);
      expect(test.results, isEmpty);
      expect(await test.begin(kCltSessionEnd), isNull);
      run.dispose();
      test.dispose();
      kit.session.dispose();
    });
  });
}
