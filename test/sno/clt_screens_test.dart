import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/clt/load_test.dart';
import 'package:memoria/sno/clt/scenario.dart';
import 'package:memoria/sno/clt/test_screens.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-CLT-01, SNO-F-CLT-02, SNO-F-CLT-03: экраны теста нагрузки.
///
/// Сессия записи — на памяти и подменённом времени; тест нагрузки
/// получает те же часы. Что тест решает без экрана, проверено в
/// `load_test_test.dart`; здесь — что видит участник, что нажимает
/// экспериментатор и куда экран ведёт дальше.
void main() {
  /// Пароль теста в этих проверках.
  const String password = '2580';

  late SessionKit kit;
  late LoadTest test;

  setUp(() {
    kit = SessionKit(hasTest: true);
    test = LoadTest(
      session: kit.session,
      password: password,
      now: kit.time.now,
      elapsedMs: () => kit.time.monotonic,
    );
  });
  tearDown(() {
    test.dispose();
    kit.session.dispose();
  });

  /// Код участника, с которым запись начинают без экрана кода.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Набирает [digits] кнопками экрана пароля и подтверждает.
  Future<void> typePassword(WidgetTester tester, String digits) async {
    for (final String digit in digits.split('')) {
      await tap(tester, 'sno-clt-key-$digit');
    }
    await tap(tester, 'sno-clt-key-ok');
  }

  /// Текст виджета с ключом [key].
  String? textOf(WidgetTester tester, String key) {
    return tester.widget<Text>(find.byKey(Key(key))).data;
  }

  /// Отвечает на показанный пункт: на полосе — кнопкой «Больше», на
  /// кнопках — четвёркой.
  Future<void> answerShown(WidgetTester tester) async {
    if (find.byKey(const Key('sno-clt-strip')).evaluate().isNotEmpty) {
      await tap(tester, 'sno-clt-more');
    } else {
      await tap(tester, 'sno-clt-value-4');
    }
    await tap(tester, 'sno-clt-next');
  }

  /// Ответы файла [name] папки записи [folder].
  List<Map<String, Object?>> answersOf(String folder, String name) {
    return <Map<String, Object?>>[
      for (final Object? answer
          in kit.store.json(folder, name)['answers']! as List<Object?>)
        answer! as Map<String, Object?>,
    ];
  }

  /// Имя единственного файла части [part] в папке [folder].
  String fileOf(String folder, String part) {
    return kit.store.files[folder]!.keys.singleWhere(
      (String name) => name.contains('_${part}_'),
    );
  }

  group('SNO-F-CLT-01: пароль экспериментатора', () {
    late GlobalKey<NavigatorState> navigator;

    /// Открывает экран пароля; отвечает тем, с чем он закроется.
    Future<Future<bool?>> openPassword(WidgetTester tester) async {
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()),
      );
      final Future<bool?> closed = navigator.currentState!.push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) {
            return LoadTestPasswordScreen(test: test);
          },
        ),
      );
      await tester.pumpAndSettle();
      return closed;
    }

    testWidgets('SNO-F-CLT-01: ввод скрыт, верный пароль закрывает экран', (
      WidgetTester tester,
    ) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      final Future<bool?> closed = await openPassword(tester);

      expect(find.text('Пароль экспериментатора'), findsOneWidget);
      // Мест столько, сколько знаков в пароле; набранное — точками.
      expect(textOf(tester, 'sno-clt-password-slots'), '_ _ _ _');
      await tap(tester, 'sno-clt-key-9');
      await tap(tester, 'sno-clt-key-2');
      expect(textOf(tester, 'sno-clt-password-slots'), '• • _ _');
      expect(find.text('9'), findsOneWidget);
      await tap(tester, 'sno-clt-key-back');
      await tap(tester, 'sno-clt-key-back');
      expect(textOf(tester, 'sno-clt-password-slots'), '_ _ _ _');
      // Пустой ввод подтвердить нельзя.
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('sno-clt-key-ok')))
            .onPressed,
        isNull,
      );

      await typePassword(tester, password);

      expect(await closed, isTrue);
      expect(find.byType(LoadTestPasswordScreen), findsNothing);
      expect(test.unlocked, isTrue);
    });

    testWidgets('SNO-F-CLT-01: три неверных пароля — минута ожидания со '
        'счётом секунд', (WidgetTester tester) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      final Future<bool?> closed = await openPassword(tester);

      await typePassword(tester, '1111');
      expect(find.text('Неверный пароль'), findsOneWidget);
      expect(textOf(tester, 'sno-clt-password-slots'), '_ _ _ _');
      await typePassword(tester, '2222');
      // Набор следующей попытки убирает слова о прошлой.
      await tap(tester, 'sno-clt-key-3');
      expect(find.text('Неверный пароль'), findsNothing);
      await typePassword(tester, '333');

      expect(find.text('Неверный пароль'), findsNothing);
      expect(
        textOf(tester, 'sno-clt-password-locked'),
        'Три неверные попытки. Ввод закрыт ещё на 60 с.',
      );
      OutlinedButton key(String name) {
        return tester.widget(find.byKey(Key('sno-clt-key-$name')));
      }

      expect(key('1').onPressed, isNull);
      expect(key('ok').onPressed, isNull);

      // Счёт идёт на глазах.
      kit.time.pass(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 1));
      expect(
        textOf(tester, 'sno-clt-password-locked'),
        'Три неверные попытки. Ввод закрыт ещё на 45 с.',
      );
      kit.time.pass(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('sno-clt-password-locked')), findsNothing);
      expect(key('1').onPressed, isNotNull);
      expect(find.byType(LoadTestPasswordScreen), findsOneWidget);

      await typePassword(tester, password);
      expect(await closed, isTrue);
    });

    testWidgets('SNO-F-CLT-01: на ПК пароль набирается с клавиатуры', (
      WidgetTester tester,
    ) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      final Future<bool?> closed = await openPassword(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
      await tester.pump();
      expect(textOf(tester, 'sno-clt-password-slots'), '• • _ _');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad8);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(await closed, isTrue);
    });

    testWidgets('SNO-F-CLT-01: «назад» с экрана пароля теста не открывает', (
      WidgetTester tester,
    ) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      final Future<bool?> closed = await openPassword(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(await closed, isNull);
      expect(test.unlocked, isFalse);
    });
  });

  group('SNO-F-CLT-02: пункт теста на экране', () {
    testWidgets('SNO-F-CLT-02: пробный проход — шестнадцать пунктов по '
        'одному, мышью, цифрами и стрелками', (WidgetTester tester) async {
      final LoadTestRun run = (await test.begin(kCltSessionEnd, dry: true))!;
      await tester.pumpWidget(
        MaterialApp(
          home: LoadTestRunScreen(test: test, run: run),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Пробный проход: ответы не сохраняются'),
        findsOneWidget,
      );
      expect(textOf(tester, 'sno-clt-progress'), '1 из 16');
      expect(
        textOf(tester, 'sno-clt-text'),
        'Сколько умственной работы потребовалось — думать, искать, '
        'вспоминать, решать?',
      );
      // Подписи краёв шкалы.
      expect(find.text('очень мало'), findsOneWidget);
      expect(find.text('очень много'), findsOneWidget);
      // Пропустить пункт нельзя: «Дальше» ждёт ответа.
      FilledButton next() {
        return tester.widget(find.byKey(const Key('sno-clt-next')));
      }

      TextButton back() {
        return tester.widget(find.byKey(const Key('sno-clt-back')));
      }

      expect(next().onPressed, isNull);
      expect(back().onPressed, isNull);
      expect(textOf(tester, 'sno-clt-strip-value'), '—');

      // Шкала 0…100 — полоса: нажатие ставит деление под пальцем.
      final Rect strip = tester.getRect(find.byKey(const Key('sno-clt-strip')));
      await tester.tapAt(
        Offset(strip.left + strip.width * 13.5 / 21, strip.center.dy),
      );
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-strip-value'), '65');
      await tester.tapAt(Offset(strip.left + 1, strip.center.dy));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-strip-value'), '0');
      await tester.tapAt(Offset(strip.right - 1, strip.center.dy));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-strip-value'), '100');
      // Кнопки по краям и стрелки сдвигают на одно деление.
      await tap(tester, 'sno-clt-less');
      expect(textOf(tester, 'sno-clt-strip-value'), '95');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-strip-value'), '90');
      expect(next().onPressed, isNotNull);

      // «Дальше» — клавишей ввода.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-progress'), '2 из 16');
      expect(textOf(tester, 'sno-clt-strip-value'), '—');
      expect(back().onPressed, isNotNull);

      // Назад — на один пункт: там прежний ответ, и дальше назад некуда.
      await tap(tester, 'sno-clt-back');
      expect(textOf(tester, 'sno-clt-progress'), '1 из 16');
      expect(textOf(tester, 'sno-clt-strip-value'), '90');
      expect(back().onPressed, isNull);
      await tap(tester, 'sno-clt-next');

      for (int i = 1; i < 6; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 16');
        await answerShown(tester);
      }

      // Шкала 1…7 — кнопки; цифра клавиатуры выбирает деление.
      expect(textOf(tester, 'sno-clt-progress'), '7 из 16');
      expect(find.byKey(const Key('sno-clt-strip')), findsNothing);
      for (int value = 1; value <= 7; value++) {
        expect(find.byKey(Key('sno-clt-value-$value')), findsOneWidget);
      }
      expect(find.text('совершенно неверно'), findsOneWidget);
      expect(find.text('совершенно верно'), findsOneWidget);
      // Цифры, которой на шкале нет, шкала не слушает.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-progress'), '7 из 16');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(run.selected, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad6);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-progress'), '8 из 16');

      for (int i = 7; i < 16; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 16');
        await answerShown(tester);
      }

      // В конце — без баллов, и ничего не записано.
      expect(
        textOf(tester, 'sno-clt-thanks'),
        'Пробный проход окончен: ответы не сохранялись',
      );
      expect(find.byKey(const Key('sno-clt-progress')), findsNothing);
      expect(kit.store.files, isEmpty);
    });
  });

  group('SNO-F-CLT-02: тест на экране завершения сессии', () {
    Future<void> pumpFinish(WidgetTester tester) async {
      // Экран целиком на виду: кнопки теста стоят под итогом записи.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionFinishScreen(session: kit.session, test: test),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-CLT-02: блок без оценки усилия идёт первым и без '
        'пароля, за ним — тест под замком', (WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(60);
      kit.session.startBlock(1);
      kit.run(120);
      // Блок не закрыт: его закрывает остановка записи.
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);

      expect(find.text('Тест нагрузки'), findsOneWidget);
      expect(find.text('Блок 1: оценить усилие'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-test-missing')), findsOneWidget);

      await tap(tester, 'sno-finish-effort');

      // Вопрос об усилии: без пароля, и уйти с него нельзя.
      expect(find.byType(LoadTestPasswordScreen), findsNothing);
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      expect(textOf(tester, 'sno-clt-progress'), 'Блок 1 закончен');
      expect(
        textOf(tester, 'sno-clt-text'),
        'Сколько умственных усилий вы вложили в это задание?',
      );
      expect(find.text('очень-очень мало'), findsOneWidget);
      expect(find.text('ни мало, ни много'), findsOneWidget);
      expect(find.text('очень-очень много'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      // Вопрос один — возвращаться некуда.
      expect(find.byKey(const Key('sno-clt-back')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      for (int value = 1; value <= 9; value++) {
        expect(find.byKey(Key('sno-clt-value-$value')), findsOneWidget);
      }

      await tap(tester, 'sno-clt-value-7');
      await tap(tester, 'sno-clt-next');

      // Ответ дан — экран ушёл сам; теперь очередь теста под замком.
      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(find.byKey(const Key('sno-finish-effort')), findsNothing);
      expect(find.text('Cognitive load test'), findsOneWidget);
      expect(answersOf(folder, fileOf(folder, 'A')).single['value'], 7);

      await tap(tester, 'sno-finish-test');

      expect(find.byType(LoadTestPasswordScreen), findsOneWidget);
      await typePassword(tester, password);
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      expect(textOf(tester, 'sno-clt-progress'), '1 из 16');
      // С итоговой части уйти можно: она продолжится.
      expect(find.byType(BackButton), findsOneWidget);
      for (int i = 0; i < 16; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 16');
        await answerShown(tester);
      }

      // Баллов участник не видит: только «Спасибо».
      expect(textOf(tester, 'sno-clt-thanks'), 'Спасибо, ответы сохранены');
      expect(find.textContaining('балл'), findsNothing);
      expect(find.textContaining('TLX'), findsNothing);
      expect(answersOf(folder, fileOf(folder, 'B')), hasLength(16));
      await tap(tester, 'sno-clt-close');

      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(
        textOf(tester, 'sno-finish-test-done'),
        'Итоговая часть пройдена: 16 из 16',
      );
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-test-missing')), findsNothing);
    });

    testWidgets('SNO-F-CLT-03: начатую часть экран предлагает продолжить — '
        'без пароля, с того же пункта', (WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);
      // Блоков не отмечали: вопроса об усилии нет, сразу тест.
      expect(find.byKey(const Key('sno-finish-effort')), findsNothing);
      await tap(tester, 'sno-finish-test');
      await typePassword(tester, password);
      for (int i = 0; i < 5; i++) {
        await answerShown(tester);
      }
      expect(textOf(tester, 'sno-clt-progress'), '6 из 16');

      // Экспериментатор ушёл с теста посреди него.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Продолжить тест · 5 из 16'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-test-missing')), findsOneWidget);
      await tap(tester, 'sno-finish-test');

      // Замок открыт до завершения сессии; пункт — шестой.
      expect(find.byType(LoadTestPasswordScreen), findsNothing);
      expect(textOf(tester, 'sno-clt-progress'), '6 из 16');
      expect(answersOf(folder, fileOf(folder, 'B')), hasLength(5));
    });

    testWidgets('SNO-F-CLT-02: сценарий не принят — на экране сказано '
        'почему, сессия завершается как прежде', (WidgetTester tester) async {
      test.dispose();
      test = LoadTest(
        session: kit.session,
        password: password,
        override: (String id) async => '{"schema":"sno2026-clt/9"}',
        now: kit.time.now,
      );
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);

      expect(
        textOf(tester, 'sno-finish-test-problem'),
        'Тест нагрузки недоступен: формат сценария «sno2026-clt/9», а '
        'нужен «sno2026-clt/1».',
      );
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-effort')), findsNothing);
      expect(find.byKey(const Key('sno-finish-test-missing')), findsNothing);
      expect(find.byKey(const Key('sno-finish-hold')), findsOneWidget);
    });

    testWidgets('SNO-F-CLT-01: без теста в сборке экран завершения '
        'прежний', (WidgetTester tester) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpWidget(
        MaterialApp(home: SessionFinishScreen(session: kit.session)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-finish-code')), findsOneWidget);
      expect(find.text('Тест нагрузки'), findsNothing);
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-test-missing')), findsNothing);
      expect(find.byKey(const Key('sno-finish-hold')), findsOneWidget);
    });
  });

  group('SNO-F-CLT-01: пункт теста в разделе «Тестирование»', () {
    late AppData data;

    setUp(() async {
      data = await openTestData();
    });
    tearDown(() async {
      await data.close();
    });

    /// Снимает дерево и даёт drift прибраться: время в widget-тестах
    /// подменено, и оставшийся таймер валит тест.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> pumpTesting(
      WidgetTester tester, {
      bool withTest = true,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(
              data: data,
              recording: kit.session,
              loadTest: withTest ? test : null,
            ),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ListTile tile(WidgetTester tester) {
      return tester.widget(find.byKey(const Key('sno-clt')));
    }

    testWidgets('SNO-F-CLT-01: в сборке без пароля теста пункта нет вовсе', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, withTest: false);

      expect(find.byKey(const Key('sno-clt')), findsNothing);
      expect(find.text('Cognitive load test'), findsNothing);
      expect(
        textOf(tester, 'sno-missing'),
        'Теста нагрузки в этой сборке нет: она собрана без пароля теста.',
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-01: пункт говорит, когда тест проходят', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);

      // Записи нет — пробный проход экспериментатора.
      expect(find.text('Cognitive load test'), findsOneWidget);
      expect(find.byKey(const Key('sno-missing')), findsNothing);
      expect(
        textOf(tester, 'sno-clt-about'),
        'Пробный проход: ответы не сохраняются',
      );
      expect(tile(tester).enabled, isTrue);

      // Запись идёт — тест закрыт: его проходят после остановки.
      await kit.session.start(code);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-about'), 'После остановки записи');
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).onTap, isNull);

      // Запись остановлена — пункт ведёт на экран завершения сессии.
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-about'), 'На экране завершения сессии');
      await tap(tester, 'sno-clt');
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-test')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-01: пробный проход спрашивает пароль и ничего не '
        'пишет', (WidgetTester tester) async {
      await pumpTesting(tester);

      await tap(tester, 'sno-clt');

      expect(find.byType(LoadTestPasswordScreen), findsOneWidget);
      await typePassword(tester, password);
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      expect(find.byKey(const Key('sno-clt-dry')), findsOneWidget);
      expect(textOf(tester, 'sno-clt-progress'), '1 из 16');
      // Пароль пробного прохода теста не отпирает.
      expect(test.unlocked, isFalse);
      expect(kit.store.files, isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-03: оценка не легла на диск — экран не уходит и '
        'говорит об этом', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      final String folder = kit.folder;
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-start');
      kit.run(30);
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-end');
      kit.store.failPutPrefix = 'clt/';

      await tap(tester, 'sno-clt-value-5');
      await tap(tester, 'sno-clt-next');

      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      expect(
        textOf(tester, 'sno-clt-save-failed'),
        'Ответ не записался на диск: проверьте свободное место.',
      );
      // Диск ответил — «Дальше» доводит дело до конца.
      kit.store.failPutPrefix = null;
      await tap(tester, 'sno-clt-next');

      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(answersOf(folder, fileOf(folder, 'A')).single['value'], 5);

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-02: сессию завершили — вопрос об усилии без '
        'ответа участника не держит', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-start');
      kit.run(30);
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-end');
      expect(find.byType(LoadTestRunScreen), findsOneWidget);

      // Запись остановили и сессию завершили, не ответив: отвечать
      // больше некуда.
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      await kit.session.finish();
      await tester.pumpAndSettle();

      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(find.byType(TestingScreen), findsOneWidget);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-02: усилие за блок оценили на другом экране — '
        'этот вопрос закрывается сам', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      final String folder = kit.folder;
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-start');
      kit.run(30);
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-end');
      expect(find.byType(LoadTestRunScreen), findsOneWidget);

      // Тот же вопрос задан ещё раз — с экрана завершения сессии,
      // который открылся поверх, — и на него ответили там.
      final LoadTestRun other = (await test.begin(
        kCltBlockEnd,
        block: kit.session.blocks.last,
      ))!;
      other.choose(5);
      await other.next();
      await tester.pumpAndSettle();

      expect(find.byType(LoadTestRunScreen), findsNothing);
      // Вопрос один, файл один, ответ — тот, что дали.
      expect(answersOf(folder, fileOf(folder, 'A')).single['value'], 5);
      other.dispose();

      await unmount(tester);
    });

    testWidgets('SNO-F-CLT-02: «Закончить» у блока задаёт вопрос об усилии и '
        'возвращает в раздел', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      final String folder = kit.folder;
      await tester.pumpAndSettle();
      await tap(tester, 'sno-block-start');
      kit.run(90);
      await tester.pumpAndSettle();

      await tap(tester, 'sno-block-end');

      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      expect(textOf(tester, 'sno-clt-progress'), 'Блок 1 закончен');
      expect(find.byType(BackButton), findsNothing);
      // Запись знает, что участник на экране теста.
      expect(kit.session.context.screen, 'clt');
      await tap(tester, 'sno-clt-value-3');
      await tap(tester, 'sno-clt-next');

      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(find.byType(TestingScreen), findsOneWidget);
      expect(kit.session.context.screen, isNot('clt'));
      expect(answersOf(folder, fileOf(folder, 'A')).single['value'], 3);
      // Запись идёт дальше: следующему блоку предложен второй номер.
      expect(kit.session.phase, RecordingPhase.recording);
      expect(textOf(tester, 'sno-block-number'), '2');

      await unmount(tester);
    });
  });
}
