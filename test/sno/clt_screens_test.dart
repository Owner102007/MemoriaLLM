import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/clt/load_test.dart';
import 'package:memoria/sno/clt/test_screens.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-CLT-01 … SNO-F-CLT-05: экраны теста нагрузки.
///
/// Третья версия теста (правка шага 25): вступление и двадцать пунктов,
/// из них два маркера честности и два пункта шкалы лжи; сессия
/// завершается только после теста, а когда его пройти нельзя — выходом
/// организатора.
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

  /// Держит палец на виджете с ключом [key] дольше, чем нужно кнопке.
  Future<void> holdOn(WidgetTester tester, String key) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key(key))),
    );
    // Нажатие узнаётся не сразу: рядом может быть прокрутка списка.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(kResetHold + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
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

    testWidgets('SNO-F-CLT-05: тем же экраном открывается выход «без '
        'теста» — под своим заголовком', (WidgetTester tester) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      final GlobalKey<NavigatorState> other = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: other, home: const SizedBox.shrink()),
      );
      final Future<bool?> closed = other.currentState!.push<bool>(
        MaterialPageRoute<bool>(
          builder: (BuildContext context) {
            return LoadTestPasswordScreen(
              test: test,
              title: 'Завершить без теста',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Завершить без теста'), findsOneWidget);
      expect(find.text('Cognitive load test'), findsNothing);
      await typePassword(tester, password);
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
    testWidgets('SNO-F-CLT-02: пробный проход — вступление и двадцать '
        'пунктов по одному, мышью, цифрами и стрелками', (
      WidgetTester tester,
    ) async {
      final LoadTestRun run = (await test.begin(dry: true))!;
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
      // SNO-F-CLT-04: перед первым пунктом — вступление без шкалы.
      expect(
        textOf(tester, 'sno-clt-intro'),
        startsWith('Сейчас — короткий опрос о том, как прошла работа'),
      );
      expect(find.byKey(const Key('sno-clt-progress')), findsNothing);
      expect(find.byKey(const Key('sno-clt-next')), findsNothing);
      expect(find.byKey(const Key('sno-clt-strip')), findsNothing);
      // Цифры и стрелки вступление не слушает.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      expect(run.selected, isNull);
      expect(find.byKey(const Key('sno-clt-intro')), findsOneWidget);

      await tap(tester, 'sno-clt-begin');

      expect(find.byKey(const Key('sno-clt-intro')), findsNothing);
      expect(textOf(tester, 'sno-clt-progress'), '1 из 20');
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
      expect(textOf(tester, 'sno-clt-progress'), '2 из 20');
      expect(textOf(tester, 'sno-clt-strip-value'), '—');
      expect(back().onPressed, isNotNull);

      // Назад — на один пункт: там прежний ответ, и дальше назад некуда.
      await tap(tester, 'sno-clt-back');
      expect(textOf(tester, 'sno-clt-progress'), '1 из 20');
      expect(textOf(tester, 'sno-clt-strip-value'), '90');
      expect(back().onPressed, isNull);
      await tap(tester, 'sno-clt-next');

      for (int i = 1; i < 6; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 20');
        await answerShown(tester);
      }

      // Шкала 1…7 — кнопки; цифра клавиатуры выбирает деление. Седьмым
      // у всех стоит первый пункт шкалы лжи: на экране он ничем не
      // отличается от соседей.
      expect(textOf(tester, 'sno-clt-progress'), '7 из 20');
      expect(run.item.id, 'lie.defer');
      expect(
        textOf(tester, 'sno-clt-text'),
        'Мне случалось откладывать на потом дело, которое нужно было '
        'сделать сразу.',
      );
      expect(find.textContaining('провер'), findsNothing);
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
      expect(textOf(tester, 'sno-clt-progress'), '7 из 20');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(run.selected, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad6);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-progress'), '8 из 20');
      await answerShown(tester);
      expect(textOf(tester, 'sno-clt-progress'), '9 из 20');

      // SNO-F-CLT-04: девятый пункт пробного прохода — маркер: на экране
      // он ничем не отличается от соседей.
      expect(run.item.id, 'chk.focus');
      expect(
        textOf(tester, 'sno-clt-text'),
        'За всё время работы я ни разу не отвлёкся — ни на секунду.',
      );
      for (int value = 1; value <= 7; value++) {
        expect(find.byKey(Key('sno-clt-value-$value')), findsOneWidget);
      }
      expect(find.text('совершенно неверно'), findsOneWidget);
      expect(back().onPressed, isNotNull);
      expect(find.textContaining('провер'), findsNothing);

      for (int i = 8; i < 20; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 20');
        if (i == 18) {
          // Предпоследний — второй пункт шкалы лжи.
          expect(run.item.id, 'lie.late');
          expect(
            textOf(tester, 'sno-clt-text'),
            'Я ни разу в жизни никуда не опоздал.',
          );
        }
        await answerShown(tester);
      }

      // В конце — без баллов, и ничего не записано.
      expect(
        textOf(tester, 'sno-clt-thanks'),
        'Пробный проход окончен: ответы не сохранялись',
      );
      expect(find.byKey(const Key('sno-clt-call')), findsNothing);
      expect(find.byKey(const Key('sno-clt-progress')), findsNothing);
      expect(kit.store.files, isEmpty);
    });

    testWidgets('SNO-F-CLT-04: на ПК вступление проходят клавишей ввода', (
      WidgetTester tester,
    ) async {
      final LoadTestRun run = (await test.begin(dry: true))!;
      await tester.pumpWidget(
        MaterialApp(
          home: LoadTestRunScreen(test: test, run: run),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-clt-intro')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-clt-intro')), findsNothing);
      expect(textOf(tester, 'sno-clt-progress'), '1 из 20');
    });
  });

  group('SNO-F-CLT-05: тест на экране завершения сессии', () {
    late GlobalKey<NavigatorState> navigator;

    /// Открывает экран завершения так, как его открывает приложение, —
    /// поверх главного экрана.
    Future<void> pumpFinish(WidgetTester tester) async {
      // Экран целиком на виду: кнопки теста стоят под кодом участника.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('главный экран')),
        ),
      );
      unawaited(
        openSessionFinish(navigator.currentState!, kit.session, test: test),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-CLT-05: пока тест не пройден, сессию не завершить; '
        'пройден — кнопка появилась', (WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(180);
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);

      // Сверху — то, что нужно участнику: код и два шага словами.
      expect(textOf(tester, 'sno-finish-code'), '6795-4332');
      expect(find.text('Впишите код в бланк'), findsOneWidget);
      expect(
        textOf(tester, 'sno-finish-step-1'),
        '1. Сообщите организатору, что закончили, — получите бланк.',
      );
      expect(
        textOf(tester, 'sno-finish-step-2'),
        '2. После письменной части позовите организатора снова.',
      );
      expect(find.text('Cognitive load test'), findsOneWidget);
      expect(find.text('Открывает организатор'), findsOneWidget);
      // Кнопки завершения нет: на её месте — что осталось.
      expect(find.byKey(const Key('sno-finish-hold')), findsNothing);
      expect(
        textOf(tester, 'sno-finish-waits'),
        'Сессия завершится после теста нагрузки.',
      );
      // SNO-F-REC-15: ни строки о блоках, ни вопроса об усилии.
      expect(find.textContaining('Блок'), findsNothing);
      expect(find.byKey(const Key('sno-finish-effort')), findsNothing);
      expect(kit.session.phase, RecordingPhase.stopped);

      await tap(tester, 'sno-finish-test');

      expect(find.byType(LoadTestPasswordScreen), findsOneWidget);
      await typePassword(tester, password);
      expect(find.byType(LoadTestRunScreen), findsOneWidget);
      // SNO-F-CLT-04: первым — вступление; в счёт пунктов оно не входит.
      expect(
        textOf(tester, 'sno-clt-intro'),
        contains('и письменную часть'),
      );
      expect(find.byKey(const Key('sno-clt-progress')), findsNothing);
      await tap(tester, 'sno-clt-begin');
      expect(textOf(tester, 'sno-clt-progress'), '1 из 20');
      // С теста уйти можно: он продолжится с того же пункта.
      expect(find.byType(BackButton), findsOneWidget);
      for (int i = 0; i < 20; i++) {
        expect(textOf(tester, 'sno-clt-progress'), '${i + 1} из 20');
        if (i == 8) {
          // У участника 67954332 девятым стоит маркер.
          expect(
            textOf(tester, 'sno-clt-text'),
            'За всё время работы я ни разу не отвлёкся — ни на секунду.',
          );
        }
        await answerShown(tester);
      }

      // Баллов участник не видит: только «Спасибо» и что делать дальше.
      expect(textOf(tester, 'sno-clt-thanks'), 'Спасибо, ответы сохранены');
      expect(textOf(tester, 'sno-clt-call'), 'Позовите организатора');
      expect(find.textContaining('балл'), findsNothing);
      expect(find.textContaining('TLX'), findsNothing);
      expect(find.textContaining('отмет'), findsNothing);
      expect(answersOf(folder, fileOf(folder, 'B')), hasLength(20));
      await tap(tester, 'sno-clt-close');

      expect(find.byType(LoadTestRunScreen), findsNothing);
      expect(textOf(tester, 'sno-finish-test-done'), 'Тест пройден: 20 из 20');
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-waits')), findsNothing);
      expect(find.byKey(const Key('sno-finish-skip')), findsNothing);
      expect(find.byKey(const Key('sno-finish-step-1')), findsNothing);
      // Теперь — и только теперь — сессию можно завершить.
      expect(find.byKey(const Key('sno-finish-hold')), findsOneWidget);

      await holdOn(tester, 'sno-finish-hold');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(find.text('главный экран'), findsOneWidget);
      // Запись и тест — в одной папке: журнал, ответы и показатели.
      expect(kit.store.finished, contains(folder));
      final Map<String, Object?> clt =
          kit.store.json(folder, 'recording.json')['clt']!
              as Map<String, Object?>;
      expect(clt['final'], 'complete');
      expect(kit.store.files[folder]!.keys, contains('clt/scores.json'));
      expect(kit.store.files[folder]!.keys, contains('clt/scenario.json'));
      final List<String> types = kit.store.types(folder);
      expect(types.last, 'session.finish');
      expect(types, contains('clt.finish'));
    });

    testWidgets('SNO-F-CLT-03: начатый тест экран предлагает продолжить — '
        'без пароля, без вступления, с того же пункта', (
      WidgetTester tester,
    ) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);
      await tap(tester, 'sno-finish-test');
      await typePassword(tester, password);
      await tap(tester, 'sno-clt-begin');
      for (int i = 0; i < 5; i++) {
        await answerShown(tester);
      }
      expect(textOf(tester, 'sno-clt-progress'), '6 из 20');

      // Участник ушёл с теста посреди него.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Продолжить тест · 5 из 20'), findsOneWidget);
      // Завершить сессию по-прежнему нельзя.
      expect(find.byKey(const Key('sno-finish-hold')), findsNothing);
      expect(
        textOf(tester, 'sno-finish-waits'),
        'Тест начат: 5 из 20. Сессия завершится после него.',
      );
      await tap(tester, 'sno-finish-test');

      // Замок открыт до завершения сессии; пункт — шестой.
      expect(find.byType(LoadTestPasswordScreen), findsNothing);
      expect(find.byKey(const Key('sno-clt-intro')), findsNothing);
      expect(textOf(tester, 'sno-clt-progress'), '6 из 20');
      expect(answersOf(folder, fileOf(folder, 'B')), hasLength(5));
    });

    testWidgets('SNO-F-CLT-05: тест пройти нельзя — выход организатора: '
        'пароль, удержание, подтверждение', (WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);
      // Участник начал тест и ушёл.
      await tap(tester, 'sno-finish-test');
      await typePassword(tester, password);
      await tap(tester, 'sno-clt-begin');
      await answerShown(tester);
      await answerShown(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(test.unlocked, isTrue);

      await tap(tester, 'sno-finish-skip');

      // Пароль спрашивается и тогда, когда тест уже открыт: открытый
      // замок — не разрешение уйти без теста.
      expect(find.byType(LoadTestPasswordScreen), findsOneWidget);
      expect(find.text('Завершить без теста'), findsOneWidget);
      // Ушли с экрана пароля — ничего не случилось.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(kit.session.phase, RecordingPhase.stopped);

      await tap(tester, 'sno-finish-skip');
      await typePassword(tester, password);

      expect(find.byType(SkipTestScreen), findsOneWidget);
      // Короткое нажатие ничего не завершает.
      await tap(tester, 'sno-skip-hold');
      expect(find.byKey(const Key('sno-skip-dialog')), findsNothing);
      await holdOn(tester, 'sno-skip-hold');
      expect(find.byKey(const Key('sno-skip-dialog')), findsOneWidget);
      // «Отмена» оставляет всё как было.
      await tap(tester, 'sno-skip-cancel');
      expect(find.byType(SkipTestScreen), findsOneWidget);
      expect(kit.session.phase, RecordingPhase.stopped);

      await holdOn(tester, 'sno-skip-hold');
      await tap(tester, 'sno-skip-confirm');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.byType(SkipTestScreen), findsNothing);
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(find.text('главный экран'), findsOneWidget);
      // Запись помечена: тест начат и не окончен; в строке завершения
      // сказано, чьим выходом сессия завершена.
      final Map<String, Object?> clt =
          kit.store.json(folder, 'recording.json')['clt']!
              as Map<String, Object?>;
      expect(clt['final'], 'partial');
      expect(clt['final_answers'], 2);
      final Map<String, Object?> finish = kit.store.events(folder).last;
      expect(finish['type'], 'session.finish');
      expect(finish['data'], <String, Object?>{'without_test': true});
      // Попытки пароля — в журнале, обе.
      expect(
        kit.store.types(folder).where((String type) {
          return type == 'clt.password.attempt';
        }),
        hasLength(2),
      );
    });

    testWidgets('SNO-F-CLT-05: сценарий не принят — тест недоступен, '
        'остаётся выход организатора', (WidgetTester tester) async {
      test.dispose();
      test = LoadTest(
        session: kit.session,
        password: password,
        override: (String id) async => '{"schema":"sno2026-clt/9"}',
        now: kit.time.now,
      );
      await kit.session.start(code);
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);

      expect(
        textOf(tester, 'sno-finish-test-problem'),
        'Тест нагрузки недоступен: формат сценария «sno2026-clt/9», а '
        'нужен «sno2026-clt/1».',
      );
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      // Сессия без теста обычным путём не завершается.
      expect(find.byKey(const Key('sno-finish-hold')), findsNothing);
      expect(find.byKey(const Key('sno-finish-waits')), findsOneWidget);

      await tap(tester, 'sno-finish-skip');
      await typePassword(tester, password);
      await holdOn(tester, 'sno-skip-hold');
      await tap(tester, 'sno-skip-confirm');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.byType(SessionFinishScreen), findsNothing);
      final Map<String, Object?> clt =
          kit.store.json(folder, 'recording.json')['clt']!
              as Map<String, Object?>;
      expect(clt['final'], 'none');
    });

    testWidgets('SNO-F-CLT-05: пароль сборки с экрана не набрать — выход '
        'организатора пароля не спрашивает', (WidgetTester tester) async {
      test.dispose();
      test = LoadTest(session: kit.session, password: '25a0');
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      await pumpFinish(tester);
      expect(textOf(tester, 'sno-finish-test-problem'), contains('не набрать'));

      await tap(tester, 'sno-finish-skip');

      // Иначе выхода не было бы вовсе.
      expect(find.byType(LoadTestPasswordScreen), findsNothing);
      expect(find.byType(SkipTestScreen), findsOneWidget);
      await holdOn(tester, 'sno-skip-hold');
      await tap(tester, 'sno-skip-confirm');
      expect(kit.session.phase, RecordingPhase.idle);
    });

    testWidgets('SNO-F-CLT-05: без теста в сборке сессия завершается '
        'сразу', (WidgetTester tester) async {
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('главный экран')),
        ),
      );
      unawaited(openSessionFinish(navigator.currentState!, kit.session));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-finish-code')), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-test')), findsNothing);
      expect(find.byKey(const Key('sno-finish-waits')), findsNothing);
      expect(find.byKey(const Key('sno-finish-skip')), findsNothing);
      expect(
        textOf(tester, 'sno-finish-step-2'),
        '2. После письменной части организатор завершит сессию.',
      );
      expect(find.byKey(const Key('sno-finish-hold')), findsOneWidget);

      await holdOn(tester, 'sno-finish-hold');
      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.byType(SessionFinishScreen), findsNothing);
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

      // Запись идёт — тест закрыт: его проходят после остановки и
      // письменной части.
      await kit.session.start(code);
      await tester.pumpAndSettle();
      expect(
        textOf(tester, 'sno-clt-about'),
        'После записи и письменной части',
      );
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).onTap, isNull);
      // SNO-F-REC-15: строки «Блок №» в разделе нет.
      expect(find.byKey(const Key('sno-block')), findsNothing);
      expect(find.byKey(const Key('sno-block-start')), findsNothing);
      expect(find.textContaining('Блок'), findsNothing);

      // Запись остановлена: пункт никуда не ведёт — тест стоит на
      // экране завершения сессии, которым закрыто приложение.
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-clt-about'), 'На экране завершения сессии');
      expect(tile(tester).enabled, isFalse);
      expect(tile(tester).onTap, isNull);
      expect(find.byKey(const Key('sno-session-finish')), findsNothing);

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
      // Вступление показано и пробному проходу.
      expect(find.byKey(const Key('sno-clt-intro')), findsOneWidget);
      await tap(tester, 'sno-clt-begin');
      expect(textOf(tester, 'sno-clt-progress'), '1 из 20');
      // Пароль пробного прохода теста не отпирает.
      expect(test.unlocked, isFalse);
      expect(kit.store.files, isEmpty);

      await unmount(tester);
    });
  });

  group('SNO-F-CLT-03: ответ не лёг на диск', () {
    testWidgets('SNO-F-CLT-03: экран говорит об этом, а последний ответ не '
        'даёт «Спасибо», пока не записан', (WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await test.enter(password);
      final LoadTestRun run = (await test.begin())!;
      await tester.pumpWidget(
        MaterialApp(
          home: LoadTestRunScreen(test: test, run: run),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'sno-clt-begin');
      // Запись знает, что участник на экране теста.
      expect(kit.session.context.screen, 'clt');
      for (int i = 0; i < 19; i++) {
        await answerShown(tester);
      }
      expect(textOf(tester, 'sno-clt-progress'), '20 из 20');
      kit.store.failPutPrefix = 'clt/';

      await answerShown(tester);

      expect(find.byKey(const Key('sno-clt-thanks')), findsNothing);
      expect(
        textOf(tester, 'sno-clt-save-failed'),
        'Ответ не записался на диск: проверьте свободное место.',
      );
      expect(test.finalDone, isFalse);
      // Диск ответил — «Дальше» доводит дело до конца.
      kit.store.failPutPrefix = null;
      await tap(tester, 'sno-clt-next');

      expect(textOf(tester, 'sno-clt-thanks'), 'Спасибо, ответы сохранены');
      expect(test.finalDone, isTrue);
      expect(answersOf(folder, fileOf(folder, 'B')), hasLength(20));
    });
  });
}
