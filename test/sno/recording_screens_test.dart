import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/library/archive_scan.dart';
import 'package:memoria/domain/library/shelf_archive.dart';
import 'package:memoria/domain/reading/reader_gestures.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/code_screen.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/recording_overlay.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/reference_state.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/library/library_screen.dart';
import 'package:memoria/ui/reader/quick_tap.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-REC-01, SNO-F-CFG-05, SNO-F-LIB-02, SNO-F-CFG-03: экраны записи.
///
/// Сессия — на памяти и подменённом времени: секунды записи идут по
/// слову теста, таймеров нет. Сама сессия проверяется в
/// `recording_session_test.dart`; здесь — что видит участник и что
/// делает экспериментатор.
void main() {
  const String branchOnly =
      'основной прогон: проверяется прогонами ветвей '
      '(--dart-define=SNO_BRANCH=I и II)';

  late AppData data;
  late SessionKit kit;

  setUp(() async {
    data = await openTestData();
    kit = SessionKit(status: FakeDeviceStatus(battery: 84, free: 1288490189));
  });
  tearDown(() async {
    kit.session.dispose();
    await data.close();
  });

  /// Код участника, с которым запись начинают без экрана кода.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  /// Снимает дерево и даёт drift прибраться: время в widget-тестах
  /// подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
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

  group('SNO-F-CFG-03: раздел «Тестирование» с записью', () {
    int started = 0;

    setUp(() => started = 0);

    Future<void> pumpTesting(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, recording: kit.session),
            flags: BranchFlags.of('I'),
            onRecordingStarted: () => started++,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-CFG-03: запись не идёт — «Старт записи» на месте', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);

      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);
      expect(find.text('Старт записи · 40 мин'), findsOneWidget);
      // Место и заряд — одной строкой под кнопкой.
      expect(
        find.text('место ${describeFileSize(1288490189)} · заряд 84 %'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sno-participant')), findsNothing);
      expect(find.byKey(const Key('sno-recording')), findsNothing);
      expect(find.byKey(const Key('sno-session-finish')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: мало заряда и места — сказано словами', (
      WidgetTester tester,
    ) async {
      kit.status
        ..battery = 24
        ..free = 150 * 1024 * 1024;
      await pumpTesting(tester);

      expect(
        find.text('мало места: 150 МБ · низкий заряд: 24 %'),
        findsOneWidget,
      );
      // Предупреждение, не запрет: кнопка работает.
      final FilledButton start = tester.widget(
        find.byKey(const Key('sno-record-start')),
      );
      expect(start.onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: старт выдаёт код, запись — после «Код '
        'записан»', (WidgetTester tester) async {
      await pumpTesting(tester);

      await tap(tester, 'sno-record-start');

      // Код — крупно, запись ещё не идёт.
      expect(find.byType(ParticipantCodeScreen), findsOneWidget);
      expect(find.text('Ваш код'), findsOneWidget);
      expect(find.text('6795-4332'), findsOneWidget);
      expect(find.text('Впишите его в бланк'), findsOneWidget);
      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.store.current, isEmpty);

      await tap(tester, 'sno-code-confirm');

      expect(find.byType(ParticipantCodeScreen), findsNothing);
      expect(kit.session.recording, isTrue);
      expect(kit.session.participant!.code, kTestCode);
      expect(started, 1);
      // В разделе — участник и ход записи; старта больше нет.
      expect(find.byKey(const Key('sno-record-start')), findsNothing);
      expect(find.byKey(const Key('sno-participant')), findsOneWidget);
      expect(find.text('6795-4332'), findsOneWidget);
      expect(find.text('Идёт запись · осталось 40:00'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: «✕» на экране кода записи не начинает', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      await tap(tester, 'sno-record-start');

      await tap(tester, 'sno-code-cancel');

      expect(find.byType(ParticipantCodeScreen), findsNothing);
      expect(kit.session.phase, RecordingPhase.idle);
      expect(started, 0);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);
      // Код, который не подтвердили, выданным не считается.
      expect(
        kit.settings.values.containsKey(SnoSettingsKeys.knownCodes),
        isFalse,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: системное «назад» на экране кода записи не '
        'начинает', (WidgetTester tester) async {
      await pumpTesting(tester);
      await tap(tester, 'sno-record-start');
      expect(find.byType(ParticipantCodeScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ParticipantCodeScreen), findsNothing);
      expect(kit.session.phase, RecordingPhase.idle);
      expect(started, 0);
      // Кнопка старта снова работает.
      final FilledButton start = tester.widget(
        find.byKey(const Key('sno-record-start')),
      );
      expect(start.onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: прежний код принимается только с верной '
        'контрольной цифрой', (WidgetTester tester) async {
      await pumpTesting(tester);
      await tap(tester, 'sno-record-start');
      await tap(tester, 'sno-code-enter');

      await tester.enterText(
        find.byKey(const Key('sno-code-field')),
        '6795-4333',
      );
      await tap(tester, 'sno-code-accept');

      expect(find.text('Код не сходится — проверьте цифры'), findsOneWidget);
      expect(find.byType(ParticipantCodeScreen), findsOneWidget);
      expect(kit.session.phase, RecordingPhase.idle);

      await tester.enterText(
        find.byKey(const Key('sno-code-field')),
        '4221-3535',
      );
      await tester.pump();
      // Начали править — замечание ушло.
      expect(find.text('Код не сходится — проверьте цифры'), findsNothing);
      await tap(tester, 'sno-code-accept');

      expect(find.byType(ParticipantCodeScreen), findsNothing);
      expect(kit.session.recording, isTrue);
      expect(kit.session.participant!.code, '42213535');
      expect(kit.session.participant!.generated, isFalse);
      expect(find.text('4221-3535'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: от ввода можно вернуться к выданному коду', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      await tap(tester, 'sno-record-start');
      await tap(tester, 'sno-code-enter');
      expect(find.byKey(const Key('sno-code')), findsNothing);

      await tap(tester, 'sno-code-new');

      expect(find.text('6795-4332'), findsOneWidget);
      await tap(tester, 'sno-code-confirm');
      expect(kit.session.participant!.generated, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: предупреждение о заряде стоит и на экране '
        'кода', (WidgetTester tester) async {
      kit.status.battery = 24;
      await pumpTesting(tester);

      await tap(tester, 'sno-record-start');

      expect(
        find.text('Заряд 24 % — поставьте устройство на зарядку.'),
        findsOneWidget,
      );
      expect(find.textContaining('Свободного места'), findsNothing);
      // И с ним запись начинается.
      await tap(tester, 'sno-code-confirm');
      expect(kit.session.recording, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: оставшееся время идёт в разделе', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      await tester.pump();

      kit.run(60);
      await tester.pump();
      expect(find.text('Идёт запись · осталось 39:00'), findsOneWidget);

      kit.run(16 * 60 + 10);
      await tester.pump();
      expect(find.text('Идёт запись · осталось 22:50'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: запись не началась — причина названа', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      kit.store.failCreate = true;

      await tap(tester, 'sno-record-start');
      await tap(tester, 'sno-code-confirm');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(started, 0);
      expect(find.byKey(const Key('sno-record-failure')), findsOneWidget);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: остановленная сессия ведёт на завершение', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      kit.run(23 * 60 + 10);
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-recording')), findsNothing);
      expect(find.byKey(const Key('sno-record-start')), findsNothing);
      expect(find.text('Завершить сессию'), findsOneWidget);
      expect(find.text('Запись остановлена · 23:10'), findsOneWidget);

      await tap(tester, 'sno-session-finish');

      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('sno-finish-title'))).data,
        'Запись остановлена · 23:10',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sno-finish-code'))).data,
        '6795-4332',
      );
      expect(find.text('Впишите код в бланк'), findsOneWidget);
      // Старт, 139 сердцебиений и остановка.
      expect(find.text('Записано событий: 141'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-failed')), findsNothing);
      // За сорок минут заряд изменился.
      kit.status.battery = 61;

      // Сессию завершают удержанием; пока экран уходит с глаз, на нём
      // по-прежнему стоят код и итог записи, а не пустые строки.
      final TestGesture finger = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('sno-finish-hold'))),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(kResetHold + const Duration(milliseconds: 100));
      await finger.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(kit.session.phase, RecordingPhase.idle);
      expect(
        tester.widget<Text>(find.byKey(const Key('sno-finish-code'))).data,
        '6795-4332',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sno-finish-title'))).data,
        'Запись остановлена · 23:10',
      );
      await tester.pumpAndSettle();

      // Сессия завершена: экран закрыт, в разделе снова старт.
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);
      expect(find.byKey(const Key('sno-participant')), findsNothing);
      // Готовность под кнопкой — нынешняя, а не сорокаминутной давности.
      expect(find.textContaining('заряд 61 %'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-05: сессия завершается только удержанием', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      await tap(tester, 'sno-session-finish');

      // Короткое нажатие ничего не завершает.
      await tap(tester, 'sno-finish-hold');

      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(kit.session.phase, RecordingPhase.stopped);

      // «Назад» с экрана завершения сессию не завершает.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(kit.session.locked, isTrue);
      expect(find.byKey(const Key('sno-session-finish')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: пока сессия не завершена, нет ни сброса, ни '
        'архива', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Эталон есть: кнопка сброса на экране.
      await data.library.save(testBook(hash: 'hash-a'));
      await ReferenceKeeper(data: data, storage: MemoryBookStorage()).remember(
        const <ArchivePlacement>[
          ArchivePlacement(fingerprint: 'hash-a', title: 'Аа', category: null),
        ],
      );
      await pumpTesting(tester);
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();

      HoldToConfirmButton reset() {
        return tester.widget(find.byKey(const Key('sno-reset-hold')));
      }

      TextButton pick() {
        return tester.widget(find.byKey(const Key('sno-add-archive')));
      }

      expect(reset().onConfirmed, isNotNull);
      expect(pick().onPressed, isNotNull);

      await kit.session.start(code);
      await tester.pumpAndSettle();

      expect(reset().onConfirmed, isNull);
      expect(pick().onPressed, isNull);
      expect(
        find.text('Сброс недоступен, пока сессия записи не завершена.'),
        findsOneWidget,
      );

      // Остановка записи сессию не завершает: замок остаётся.
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(reset().onConfirmed, isNull);

      await kit.session.finish();
      await tester.pumpAndSettle();
      expect(reset().onConfirmed, isNotNull);
      expect(pick().onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: без записи в сборке раздел прежний', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-device')), findsOneWidget);
      expect(find.byKey(const Key('sno-record-start')), findsNothing);
      expect(find.byKey(const Key('sno-participant')), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-01: слой записи поверх приложения', () {
    int underTaps = 0;

    setUp(() => underTaps = 0);

    /// Сколько раз экран под слоем принял нажатие за долгое — так
    /// экран чтения начинает выделение.
    int pageHolds = 0;

    setUp(() => pageHolds = 0);

    /// Экран с кнопкой в левом углу — там, где стоит точка записи.
    Widget withCornerButton() {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('under-dot'),
            icon: const Icon(Icons.menu),
            onPressed: () => underTaps++,
          ),
        ),
        body: const Center(child: Text('страница книги')),
      );
    }

    /// Экран, который, как экран чтения, принимает долгое нажатие за
    /// начало выделения — через четверть секунды.
    Widget likeReader() {
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 250),
                ),
                (LongPressGestureRecognizer instance) {
                  instance.onLongPressStart = (LongPressStartDetails details) {
                    pageHolds++;
                  };
                },
              ),
        },
        child: const Center(child: Text('страница книги')),
      );
    }

    Future<void> pumpOverlay(WidgetTester tester, {Widget? home}) async {
      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (BuildContext context, Widget? page) {
            return RecordingOverlay(
              session: kit.session,
              navigator: navigator,
              child: page!,
            );
          },
          home: home ?? withCornerButton(),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Держит палец в точке [at] всего [held].
    Future<void> holdAt(WidgetTester tester, Offset at, Duration held) async {
      final TestGesture gesture = await tester.startGesture(at);
      await tester.pump();
      // Сначала точка узнаёт удержание, потом растёт кольцо: его счёт
      // начинается с кадра после распознавания.
      const Duration recognised = Duration(milliseconds: 250);
      await tester.pump(recognised);
      await tester.pump(held - recognised);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// Держит палец на точке записи всего [held].
    Future<void> holdDot(WidgetTester tester, Duration held) {
      return holdAt(
        tester,
        tester.getCenter(find.byKey(const Key('sno-recording-dot'))),
        held,
      );
    }

    const Duration enough = Duration(milliseconds: 2100);

    testWidgets('SNO-F-REC-01: точка горит, только пока запись идёт', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);
      expect(find.byKey(const Key('sno-recording-dot')), findsNothing);

      await kit.session.start(code);
      await tester.pump();
      expect(find.byKey(const Key('sno-recording-dot')), findsOneWidget);
      // Страница под слоем на месте.
      expect(find.text('страница книги'), findsOneWidget);
      // На узком экране точка — в левом верхнем углу.
      final Offset corner = tester.getTopLeft(
        find.byKey(const Key('sno-recording-dot')),
      );
      expect(corner, Offset.zero);

      await kit.session.stop(StopReason.experimenter);
      await tester.pump();
      expect(find.byKey(const Key('sno-recording-dot')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: в широком окне точка — в правом углу', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();

      final Offset corner = tester.getTopRight(
        find.byKey(const Key('sno-recording-dot')),
      );
      expect(corner, const Offset(1200, 0));

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: точка нажатий у экрана не отбирает', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('sno-recording-dot'))),
      );
      await tester.pumpAndSettle();

      // Кнопка под точкой сработала, а вопроса об остановке нет.
      expect(underTaps, 1);
      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.recording, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: короткого удержания точки мало', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();

      await holdDot(tester, const Duration(milliseconds: 1500));

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.recording, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: удержание точки спрашивает об остановке', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      kit.run(5);
      await tester.pump();

      await holdDot(tester, enough);

      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);
      expect(find.text('Остановить запись?'), findsOneWidget);
      expect(find.text('Прошло 00:05 из 40:00'), findsOneWidget);
      // Додержанное нажатие кнопке под точкой не досталось: отпущенный
      // палец её не нажал.
      expect(underTaps, 0);
      // Пока вопрос открыт, запись идёт, и время в нём тоже.
      expect(kit.session.recording, isTrue);
      kit.run(3);
      await tester.pump();
      expect(find.text('Прошло 00:08 из 40:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sno-stop-continue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.recording, isTrue);
      expect(find.byType(SessionFinishScreen), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: удержание точки страница под ней за своё не '
        'принимает', (WidgetTester tester) async {
      await pumpOverlay(tester, home: likeReader());
      await kit.session.start(code);
      await tester.pump();

      // Без точки под пальцем страница долгое нажатие узнаёт.
      await holdAt(
        tester,
        const Offset(300, 300),
        const Duration(milliseconds: 600),
      );
      expect(pageHolds, 1);

      // На точке — нет: слово под пальцем не выделится.
      await holdDot(tester, enough);
      expect(pageHolds, 1);
      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: сорванное удержание точки страницу не '
        'листает', (WidgetTester tester) async {
      // Страница, как в книге, узнаёт нажатие по сырым событиям
      // указателя — мимо спора жестов.
      int pageTaps = 0;
      await pumpOverlay(
        tester,
        home: QuickTap(
          watch: TapWatch(),
          onTap: (Offset at) => pageTaps++,
          child: likeReader(),
        ),
      );
      await kit.session.start(code);
      await tester.pump();
      final Offset dot = tester.getCenter(
        find.byKey(const Key('sno-recording-dot')),
      );

      // Короткое нажатие на точке достаётся странице: она листает.
      await tester.tapAt(dot);
      await tester.pump();
      expect(pageTaps, 1);

      // Точку начали держать и отпустили через треть секунды: нажатие
      // уже её, и страница его нажатием не считает.
      final TestGesture gesture = await tester.startGesture(dot);
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pageTaps, 1);
      expect(pageHolds, 0);
      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);

      // Следующее короткое нажатие — снова страницы.
      await tester.tapAt(dot);
      await tester.pump();
      expect(pageTaps, 2);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: окно с идущей записью не закрывается', (
      WidgetTester tester,
    ) async {
      /// Система просит приложение закрыться — крестик окна на ПК;
      /// отвечает, что приложение сказало: `exit` или `cancel`.
      Future<Object?> askToExit() async {
        const JSONMethodCodec codec = JSONMethodCodec();
        ByteData? reply;
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/platform',
          codec.encodeMethodCall(
            const MethodCall('System.requestAppExit', <Object?>[
              <String, Object?>{'type': 'cancelable'},
            ]),
          ),
          (ByteData? data) => reply = data,
        );
        final Object? answer = codec.decodeEnvelope(reply!);
        return (answer! as Map<String, Object?>)['response'];
      }

      await pumpOverlay(tester);
      // Записи нет — приложение закрывается как обычно.
      expect(await askToExit(), 'exit');

      await kit.session.start(code);
      await tester.pump();
      expect(await askToExit(), 'cancel');
      await tester.pump();
      expect(find.byKey(const Key('sno-exit-refused')), findsOneWidget);
      expect(kit.session.recording, isTrue);
      // Сообщение уходит само: срок считается с того мига, как оно
      // встало на место, поэтому время идёт двумя кадрами.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-exit-refused')), findsNothing);

      // Запись остановлена — окно можно закрыть, но не раньше, чем
      // остановка допишет своё на диск: иначе следующий запуск принял
      // бы запись за оборванную.
      final Future<void> stopping = kit.session.stop(StopReason.experimenter);
      expect(await askToExit(), 'exit');
      final SessionState marked = SessionState.decode(
        kit.settings.values[SnoSettingsKeys.session],
      )!;
      expect(marked.phase, RecordingPhase.stopped);
      await stopping;
      await tester.pump();

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: палец, который повёл по экрану, запись не '
        'останавливает', (WidgetTester tester) async {
      await pumpOverlay(tester, home: likeReader());
      await kit.session.start(code);
      await tester.pump();

      // Протяжка из угла, длиннее двух секунд.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('sno-recording-dot'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(120, 160));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 2000));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.recording, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: вопрос, закрытый нажатием мимо, записи не '
        'останавливает', (WidgetTester tester) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();
      await holdDot(tester, enough);
      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);

      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.recording, isTrue);
      // И автостоп после этого снимает только точку, а не экран.
      kit.run(40 * 60);
      await tester.pumpAndSettle();
      expect(find.text('страница книги'), findsOneWidget);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: остановка — удержанием, за ней завершение '
        'сессии', (WidgetTester tester) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      kit.run(70);
      await tester.pump();
      await holdDot(tester, enough);

      // Короткое нажатие на «остановить» ничего не останавливает.
      await tester.tap(find.byKey(const Key('sno-stop-hold')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);
      expect(kit.session.recording, isTrue);

      await holdOn(tester, 'sno-stop-hold');

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.experimenter);
      // Экспериментатора сразу ведут на завершение сессии.
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.text('Запись остановлена · 01:10'), findsOneWidget);
      // Пока экран завершения открыт, плашки под ним нет.
      expect(find.byKey(const Key('sno-recording-ended')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: автостоп страницу не прерывает', (
      WidgetTester tester,
    ) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      await tester.pump();

      kit.run(40 * 60);
      await tester.pumpAndSettle();

      expect(kit.session.state!.stoppedBy, StopReason.auto);
      // Страница на месте, точки нет, внизу плашка.
      expect(find.text('страница книги'), findsOneWidget);
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(find.byKey(const Key('sno-recording-dot')), findsNothing);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);
      expect(find.text('Запись завершена'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sno-recording-ended')));
      await tester.pumpAndSettle();

      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.text('Запись завершена · 40:00'), findsOneWidget);
      expect(find.byKey(const Key('sno-recording-ended')), findsNothing);

      // Ушли с экрана завершения — плашка снова ведёт на него.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);

      // Сессия завершена — плашки нет.
      await kit.session.finish();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-recording-ended')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: запись кончилась при открытом вопросе — '
        'вопрос закрыт, страница на месте', (WidgetTester tester) async {
      await pumpOverlay(tester);
      await kit.session.start(code);
      kit.run(5);
      await tester.pump();
      await holdDot(tester, enough);
      expect(find.byKey(const Key('sno-stop-dialog')), findsOneWidget);

      kit.run(40 * 60);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-stop-dialog')), findsNothing);
      expect(kit.session.state!.stoppedBy, StopReason.auto);
      // Закрылся только вопрос: экран под ним не снят.
      expect(find.text('страница книги'), findsOneWidget);
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: уход приложения в фон и возврат попадают в '
        'журнал', (WidgetTester tester) async {
      Future<void> lifecycle(String state) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage('AppLifecycleState.$state'),
          (_) {},
        );
      }

      await pumpOverlay(tester);
      // С какого состояния начинает привязка тестов, не важно: сначала
      // приложение на экране.
      await lifecycle('resumed');
      await kit.session.start(code);
      kit.run(5);

      await lifecycle('paused');
      kit.time.pass(const Duration(seconds: 7));
      await lifecycle('resumed');
      await tester.pumpAndSettle();

      expect(kit.session.recording, isTrue);
      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      expect(kit.store.types(kit.folder), <String>[
        'recording.start',
        'app.background',
        'app.foreground',
        'clock.resync',
      ]);
      expect(events[1]['data'], <String, Object?>{'state': 'inactive'});
      expect(events[2]['data'], <String, Object?>{
        'away_ms': 7000,
        'deepest': 'paused',
      });

      await unmount(tester);
    });
  });

  group('SNO-F-LIB-02: приложение в сборе', () {
    Future<void> pumpApp(WidgetTester tester, AppServices services) async {
      await tester.pumpWidget(
        MemoriaApp(themeController: ThemeController(), services: services),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    LibraryScreen shelf(WidgetTester tester) {
      return tester.widget(find.byType(LibraryScreen));
    }

    /// Закрывает ли «назад» приложение с этого экрана.
    bool backCloses(WidgetTester tester) {
      final PopScope<Object?> scope = tester.widget(
        find
            .ancestor(
              of: find.byType(LibraryScreen),
              matching: find.byWidgetPredicate(
                (Widget widget) => widget is PopScope<Object?>,
              ),
            )
            .first,
      );
      return scope.canPop;
    }

    testWidgets('SNO-F-REC-01: записи в сборке нет — слоя записи нет', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data));

      expect(find.byType(RecordingOverlay), findsNothing);
      expect(shelf(tester).locked, isFalse);
      expect(backCloses(tester), isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-LIB-02: замок полки включает старт записи и снимает '
        'завершение сессии', (WidgetTester tester) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data, recording: kit.session));

      expect(find.byType(RecordingOverlay), findsOneWidget);
      expect(shelf(tester).locked, isFalse);
      expect(find.byKey(const Key('sno-recording-dot')), findsNothing);

      await kit.session.start(code);
      await settle(tester);

      expect(shelf(tester).locked, isTrue);
      expect(find.byKey(const Key('sno-recording-dot')), findsOneWidget);
      // Книга под замком открывается: участник читает.
      expect(find.byKey(const Key('library-book-book-1')), findsOneWidget);

      // Запись остановлена — участник заполняет бланк: замок остаётся.
      await kit.session.stop(StopReason.experimenter);
      await settle(tester);
      expect(shelf(tester).locked, isTrue);
      expect(find.byKey(const Key('sno-recording-dot')), findsNothing);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);

      await kit.session.finish();
      await settle(tester);
      expect(shelf(tester).locked, isFalse);
      expect(find.byKey(const Key('sno-recording-ended')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: пока запись идёт, «назад» на полке приложение '
        'не закрывает', (WidgetTester tester) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data, recording: kit.session));
      expect(backCloses(tester), isTrue);

      await kit.session.start(code);
      await settle(tester);
      expect(backCloses(tester), isFalse);
      await tester.binding.handlePopRoute();
      await settle(tester);
      // Приложение на месте, запись идёт.
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(kit.session.recording, isTrue);

      await kit.session.stop(StopReason.experimenter);
      await settle(tester);
      expect(backCloses(tester), isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-03: приложение открыли с незавершённой сессией '
        '— замок и плашка с первого кадра', (WidgetTester tester) async {
      await data.library.save(testBook());
      await kit.session.start(code);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);

      await pumpApp(tester, testServices(data: data, recording: kit.session));

      expect(shelf(tester).locked, isTrue);
      expect(find.byKey(const Key('sno-recording-ended')), findsOneWidget);
      expect(find.text('Запись остановлена'), findsOneWidget);

      // Плашка ведёт на завершение сессии.
      await tester.tap(find.byKey(const Key('sno-recording-ended')));
      await settle(tester);
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.text('Запись остановлена · 00:30'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-01: «назад» из другого раздела во время записи '
        'ведёт на полку', (WidgetTester tester) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data, recording: kit.session));
      await kit.session.start(code);
      await tester.tap(find.byKey(const Key('nav-settings')));
      await settle(tester);
      expect(kit.session.context.screen, 'settings');

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(kit.session.context.screen, 'shelf');
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(kit.session.recording, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-02: запись знает, на каком экране участник', (
      WidgetTester tester,
    ) async {
      await data.library.save(testBook());
      await pumpApp(tester, testServices(data: data, recording: kit.session));
      expect(kit.session.context.screen, 'shelf');

      await tester.tap(find.byKey(const Key('nav-settings')));
      await settle(tester);
      expect(kit.session.context.screen, 'settings');

      await tester.tap(find.byKey(const Key('nav-library')));
      await settle(tester);
      expect(kit.session.context.screen, 'shelf');

      await unmount(tester);
    });
  });

  group('SNO-F-REC-01: запись в собранной ветви', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-REC-01: после «Код записан» участник снова на полке, '
        'и она под замком', (WidgetTester tester) async {
      await data.library.save(testBook());
      await tester.pumpWidget(
        MemoriaApp(
          themeController: ThemeController(),
          services: testServices(data: data, recording: kit.session),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('nav-testing')));
      await settle(tester);
      expect(find.byKey(const Key('library-shelf')), findsNothing);
      await tester.tap(find.byKey(const Key('sno-record-start')));
      await settle(tester);
      expect(find.text('6795-4332'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sno-code-confirm')));
      await settle(tester);

      expect(kit.session.recording, isTrue);
      expect(find.byKey(const Key('library-shelf')), findsOneWidget);
      final LibraryScreen shelf = tester.widget(find.byType(LibraryScreen));
      expect(shelf.locked, isTrue);
      expect(find.byKey(const Key('sno-recording-dot')), findsOneWidget);
      expect(kit.session.context.screen, 'shelf');
      // Старт записан с экрана, где его нажали.
      expect(kit.store.events(kit.folder).first['screen'], 'testing');

      await unmount(tester);
    });
  }, skip: Sno.recording ? false : branchOnly);
}
