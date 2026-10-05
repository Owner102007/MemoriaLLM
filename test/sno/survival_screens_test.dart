import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/main.dart' show recoverRecords;
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/code_screen.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/journal_check.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/records_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/settings_keys.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-REC-13, SNO-F-REC-14: что видит экспериментатор.
///
/// Экран завершения — «Запись цела» и вторая копия; список записей —
/// две отметки и слова после окна «Поделиться»; раздел «Тестирование» —
/// разрешение на уведомления. Сессия и записи — на памяти; сами
/// правила проверяются в `recording_survival_test.dart` и
/// `record_backup_test.dart`.
void main() {
  late AppData data;
  late SessionKit kit;
  late MemoryDeviceRecords records;

  /// Сегодняшняя запись: ещё никуда не ушла.
  final DeviceRecord fresh = DeviceRecord(
    name: 'sno2026_I_67954332_a91f3c_20261103-1402',
    bytes: 7130317,
    branch: 'I',
    participant: '67954332',
    startedAt: DateTime(2026, 11, 3, 14, 2),
    durationMs: 40 * 60 * 1000,
    events: 4870,
    stoppedBy: 'experimenter',
  );

  /// Код участника, с которым запись начинают без экрана кода.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  setUp(() async {
    data = await openTestData();
    kit = SessionKit(status: FakeDeviceStatus(battery: 84, free: 1288490189));
    records = MemoryDeviceRecords(shares: true, backs: true);
  });

  tearDown(() async {
    kit.session.dispose();
    records.dispose();
    await data.close();
  });

  /// Снимает дерево и даёт drift прибраться: время в widget-тестах
  /// подменено, и оставшийся таймер валит тест.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Держит палец на виджете с ключом [key] дольше, чем нужно кнопке.
  Future<void> holdOn(WidgetTester tester, String key) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key(key))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(kResetHold + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, String key) {
    return tester.widget<Text>(find.byKey(Key(key))).data!;
  }

  /// Открывает экран завершения поверх кнопки-заглушки.
  Future<void> openFinish(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: TextButton(
                key: const Key('open-finish'),
                onPressed: () => unawaited(
                  openSessionFinish(
                    Navigator.of(context),
                    kit.session,
                    records: records,
                  ),
                ),
                child: const Text('завершение'),
              ),
            );
          },
        ),
      ),
    );
    await tap(tester, 'open-finish');
  }

  group('SNO-F-REC-13: экран завершения', () {
    testWidgets('SNO-F-REC-13: под числом событий сказано, что запись '
        'цела', (WidgetTester tester) async {
      await kit.session.start(code);
      kit.run(20 * 60);
      await kit.session.stop(StopReason.experimenter);
      final int lines = kit.session.check!.lines;

      await openFinish(tester);

      expect(
        textOf(tester, 'sno-finish-check'),
        'Запись цела: ${describeLineCount(lines)}, пропусков нет',
      );
      expect(textOf(tester, 'sno-finish-events'), 'Записано событий: $lines');
      // Завершению это не мешает.
      expect(find.byKey(const Key('sno-finish-hold')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: неполная запись названа неполной, а сессия '
        'завершается', (WidgetTester tester) async {
      await kit.session.start(code);
      kit.run(3);
      // Не `kit.settle()`: время в widget-тестах подменено, и диск
      // догоняет запись по слову `pump`.
      await tester.pump();
      kit.store.failAppend = true;
      kit.session.log(SnoEventType.pageShown);
      kit.run(1);
      await tester.pump();
      kit.store.failAppend = false;
      await kit.session.stop(StopReason.experimenter);

      await openFinish(tester);

      expect(
        textOf(tester, 'sno-finish-check'),
        startsWith('Запись неполная: '),
      );
      expect(textOf(tester, 'sno-finish-check'), contains('пропущено строк 1'));

      await holdOn(tester, 'sno-finish-hold');
      expect(kit.session.phase, RecordingPhase.idle);
      expect(find.text('Сессия завершена'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: журнал не перечитался — так и сказано', (
      WidgetTester tester,
    ) async {
      await kit.session.start(code);
      kit.run(5);
      kit.store.failBytes = true;
      await kit.session.stop(StopReason.experimenter);

      await openFinish(tester);

      expect(
        textOf(tester, 'sno-finish-check'),
        'Запись не проверена: журнал не перечитался с диска.',
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: после упаковки сказано, где лежит вторая '
        'копия', (WidgetTester tester) async {
      await kit.session.start(code);
      kit.run(60);
      await kit.session.stop(StopReason.experimenter);
      await openFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(find.text('Архив записи готов'), findsOneWidget);
      expect(
        textOf(tester, 'sno-finish-backup'),
        'Копия: Загрузки/Memoria-SNO2026',
      );
      expect(records.entries.single.copiedAt, isNotNull);
      // Копия отправки не заменяет: «Поделиться» на месте.
      expect(find.byKey(const Key('sno-finish-share')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: копия не легла — сказано, архив остаётся', (
      WidgetTester tester,
    ) async {
      records.backupWorks = false;
      await kit.session.start(code);
      kit.run(60);
      await kit.session.stop(StopReason.experimenter);
      await openFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(
        textOf(tester, 'sno-finish-backup'),
        startsWith('Копии в «Загрузках» нет'),
      );
      expect(find.byKey(const Key('sno-finish-archive')), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-share')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: на ПК о второй копии не говорится', (
      WidgetTester tester,
    ) async {
      records
        ..shares = false
        ..saves = true
        ..backs = false;
      await kit.session.start(code);
      kit.run(60);
      await kit.session.stop(StopReason.experimenter);
      await openFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(find.text('Архив записи готов'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-backup')), findsNothing);
      expect(find.byKey(const Key('sno-finish-save')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-14: окно «Поделиться» закрыли без выбора — '
        'сказано, запись не отправлена', (WidgetTester tester) async {
      records.shareOutcome = ShareOutcome.dismissed;
      await kit.session.start(code);
      kit.run(60);
      await kit.session.stop(StopReason.experimenter);
      await openFinish(tester);
      await holdOn(tester, 'sno-finish-hold');

      await tap(tester, 'sno-finish-share');

      expect(
        textOf(tester, 'sno-finish-notice'),
        'Окно закрыто без выбора — запись не отправлена.',
      );
      expect(records.entries.single.sharedAt, isNull);

      // Вторая попытка: приложение выбрано.
      records.shareOutcome = ShareOutcome.chosen;
      await tap(tester, 'sno-finish-share');
      expect(
        textOf(tester, 'sno-finish-notice'),
        'Запись помечена отправленной.',
      );
      expect(records.entries.single.sharedAt, isNotNull);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-13: список записей на телефоне', () {
    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DeviceRecordsScreen(records: records)),
      );
      await tester.pumpAndSettle();
    }

    String aboutOf(WidgetTester tester, DeviceRecord record) {
      return textOf(tester, 'sno-record-about-${record.rowId}');
    }

    testWidgets('SNO-F-REC-13: у записи две отметки — отправка и копия', (
      WidgetTester tester,
    ) async {
      records.put(
        DeviceRecord(
          name: fresh.name,
          bytes: fresh.bytes,
          startedAt: fresh.startedAt,
          durationMs: fresh.durationMs,
          copiedAt: DateTime(2026, 11, 3, 14, 45),
        ),
      );
      await pumpList(tester);

      expect(
        aboutOf(tester, fresh),
        '40:00 · 6,8 МБ · не отправлена · копия есть',
      );
      // Копия есть, а в неотправленных запись по-прежнему числится.
      expect(find.text('Поделиться неотправленными (1)'), findsOneWidget);

      await tap(tester, 'sno-record-share-${fresh.name}');

      expect(
        aboutOf(tester, fresh),
        '40:00 · 6,8 МБ · отправлена · копия есть',
      );
      expect(find.byKey(const Key('sno-records-share-all')), findsNothing);
    });

    testWidgets('SNO-F-REC-14: окно закрыли без выбора — запись остаётся '
        'неотправленной', (WidgetTester tester) async {
      records
        ..put(fresh)
        ..shareOutcome = ShareOutcome.dismissed;
      await pumpList(tester);

      await tap(tester, 'sno-record-share-${fresh.name}');

      expect(records.shared, hasLength(1));
      expect(
        aboutOf(tester, fresh),
        '40:00 · 6,8 МБ · не отправлена · копии нет',
      );
      expect(
        textOf(tester, 'sno-records-notice'),
        'Окно закрыто без выбора — запись не отправлена.',
      );
      expect(find.text('Поделиться неотправленными (1)'), findsOneWidget);
    });

    testWidgets('SNO-F-REC-13: запись с копией удаляется одним вопросом, '
        'без копии и без отправки — двумя', (WidgetTester tester) async {
      final DeviceRecord copied = DeviceRecord(
        name: 'sno2026_I_94532726_a91f3c_20261102-1130',
        bytes: 7444890,
        startedAt: DateTime(2026, 11, 2, 11, 30),
        durationMs: 40 * 60 * 1000,
        copiedAt: DateTime(2026, 11, 2, 12, 15),
      );
      records
        ..put(fresh)
        ..put(copied);
      await pumpList(tester);

      await tap(tester, 'sno-record-delete-${copied.rowId}');
      // В единственном вопросе сказано, что от записи останется.
      expect(find.textContaining('Запись не отправлена'), findsOneWidget);
      expect(find.textContaining(kBackupFolder), findsOneWidget);
      await tap(tester, 'sno-record-confirm');
      expect(records.deleted, <String>[copied.name]);

      await tap(tester, 'sno-record-delete-${fresh.rowId}');
      await tap(tester, 'sno-record-confirm');
      // Первый вопрос пройден, а запись на месте: нужен второй.
      expect(records.deleted, <String>[copied.name]);
      expect(find.text('Эта запись никуда не отправлена'), findsOneWidget);
      await tap(tester, 'sno-record-confirm');
      expect(records.deleted, <String>[copied.name, fresh.name]);
      // Сверяли только ту, чьё удаление обещало «копия останется».
      expect(records.verified, <String>[copied.name]);
    });

    testWidgets('SNO-F-REC-13: копию убрали из «Загрузок» — запись '
        'удаляется только вторым подтверждением', (WidgetTester tester) async {
      final DeviceRecord copied = DeviceRecord(
        name: fresh.name,
        bytes: fresh.bytes,
        startedAt: fresh.startedAt,
        durationMs: fresh.durationMs,
        copiedAt: DateTime(2026, 11, 3, 14, 45),
      );
      records
        ..put(copied)
        ..copyThere = false;
      await pumpList(tester);
      expect(
        aboutOf(tester, copied),
        '40:00 · 6,8 МБ · не отправлена · копия есть',
      );

      await tap(tester, 'sno-record-delete-${copied.rowId}');

      // Обещания «копия останется» в вопросе нет, а отметка снята.
      expect(find.textContaining('копия останется'), findsNothing);
      expect(
        aboutOf(tester, copied),
        '40:00 · 6,8 МБ · не отправлена · копии нет',
      );
      await tap(tester, 'sno-record-confirm');
      expect(records.deleted, isEmpty);
      expect(find.text('Эта запись никуда не отправлена'), findsOneWidget);
      await tap(tester, 'sno-record-confirm');
      expect(records.deleted, <String>[copied.name]);
    });
  });

  group('SNO-F-REC-13: отметка о копии без сверки', () {
    testWidgets('SNO-F-REC-13: телефон, которому сверить копию нечем, '
        'одним подтверждением запись не удаляет', (WidgetTester tester) async {
      // Общая папка не ответила при запуске: копий устройство «не
      // кладёт», а отметка о прежней копии с диска пришла.
      final MemoryDeviceRecords blind = MemoryDeviceRecords(shares: true);
      addTearDown(blind.dispose);
      final DeviceRecord copied = DeviceRecord(
        name: fresh.name,
        bytes: fresh.bytes,
        startedAt: fresh.startedAt,
        durationMs: fresh.durationMs,
        copiedAt: DateTime(2026, 11, 3, 14, 45),
      );
      blind.put(copied);
      await tester.pumpWidget(
        MaterialApp(home: DeviceRecordsScreen(records: blind)),
      );
      await tester.pumpAndSettle();

      await tap(tester, 'sno-record-delete-${copied.rowId}');
      expect(find.textContaining('копия останется'), findsNothing);
      await tap(tester, 'sno-record-confirm');

      expect(blind.deleted, isEmpty);
      expect(find.text('Эта запись никуда не отправлена'), findsOneWidget);
      await tap(tester, 'sno-record-confirm');
      expect(blind.deleted, <String>[copied.name]);
      expect(blind.verified, isEmpty);
    });
  });

  group('SNO-F-REC-13: «Тестирование» и уведомления', () {
    Future<void> pumpTesting(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(
              data: data,
              recording: kit.session,
              records: records,
            ),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-REC-13: уведомления разрешены — раздел молчит', (
      WidgetTester tester,
    ) async {
      kit.session.dispose();
      kit = SessionKit(guard: FakeRecordingGuard());
      await pumpTesting(tester);

      expect(find.byKey(const Key('sno-record-notifications')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: у устройства без защиты записи раздел '
        'молчит', (WidgetTester tester) async {
      await pumpTesting(tester);

      expect(find.byKey(const Key('sno-record-notifications')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: разрешение спрашивается перед первой '
        'записью, отказ старту не мешает', (WidgetTester tester) async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false)
        ..answer = false;
      kit.session.dispose();
      kit = SessionKit(guard: guard);
      await pumpTesting(tester);
      // До вопроса раздел уже говорит, что уведомления выключены.
      expect(find.byKey(const Key('sno-record-notifications')), findsOneWidget);
      expect(guard.asked, 0);

      await tap(tester, 'sno-record-start');

      expect(guard.asked, 1);
      expect(
        kit.settings.values[SnoSettingsKeys.notificationsAsked],
        isNotNull,
      );
      expect(find.byType(ParticipantCodeScreen), findsOneWidget);

      await tap(tester, 'sno-code-confirm');

      expect(kit.session.recording, isTrue);
      expect(guard.held, isTrue);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-13: разрешили — строки об уведомлениях больше '
        'нет', (WidgetTester tester) async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false);
      kit.session.dispose();
      kit = SessionKit(guard: guard);
      await pumpTesting(tester);
      expect(find.byKey(const Key('sno-record-notifications')), findsOneWidget);

      await tap(tester, 'sno-record-start');
      await tap(tester, 'sno-code-cancel');

      expect(guard.asked, 1);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);
      expect(find.byKey(const Key('sno-record-notifications')), findsNothing);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-13: записи при запуске приложения', () {
    test('SNO-F-REC-13: вторые копии прежних записей докладываются после '
        'упаковки', () async {
      await recoverRecords(
        testServices(data: data, recording: kit.session, records: records),
        restored: true,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(records.pending, 1);
      expect(records.backedUp, 1);
    });

    test('SNO-F-REC-13: сессия не поднялась — копий не докладывают', () async {
      await recoverRecords(
        testServices(data: data, recording: kit.session, records: records),
        restored: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(records.backedUp, 0);
    });
  });
}
