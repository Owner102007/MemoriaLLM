import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/main.dart' show recoverRecords;
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/records_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-REC-07, SNO-F-REC-06, SNO-F-REC-05: экраны записей.
///
/// Записи — на памяти (`MemoryDeviceRecords`): что показано, что отдано
/// окну «Поделиться», что помечено и что удалено. Настоящие архивы и
/// настоящий диск проверяются в `device_records_test.dart` и
/// `recording_archive_test.dart`.
void main() {
  late AppData data;
  late SessionKit kit;
  late MemoryDeviceRecords records;

  /// Вчерашняя запись, уже отправленная.
  final DeviceRecord sent = DeviceRecord(
    name: 'sno2026_I_94532726_a91f3c_20261102-1130',
    bytes: 7444890,
    branch: 'I',
    participant: '94532726',
    startedAt: DateTime(2026, 11, 2, 11, 30),
    durationMs: 40 * 60 * 1000,
    events: 5123,
    stoppedBy: 'auto',
    sharedAt: DateTime(2026, 11, 2, 12, 15),
  );

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

  /// Запись, оборванная закрытием приложения.
  final DeviceRecord broken = DeviceRecord(
    name: 'sno2026_I_94532726_a91f3c_20261101-1712',
    bytes: 3145728,
    branch: 'I',
    participant: '94532726',
    startedAt: DateTime(2026, 11, 1, 17, 12),
    durationMs: 17 * 60 * 1000 + 42 * 1000,
    events: 1877,
    stoppedBy: 'crash',
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
    records = MemoryDeviceRecords(shares: true);
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

  /// Строка под именем записи [record].
  String aboutOf(WidgetTester tester, DeviceRecord record) {
    return textOf(tester, 'sno-record-about-${record.rowId}');
  }

  group('SNO-F-REC-07: список записей', () {
    Future<void> pumpList(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DeviceRecordsScreen(records: records)),
      );
      await tester.pumpAndSettle();
    }

    /// Имена записей на экране, сверху вниз.
    List<String> shownNames(WidgetTester tester) {
      double top(DeviceRecord record) {
        return tester
            .getTopLeft(find.byKey(Key('sno-record-${record.rowId}')))
            .dy;
      }

      final List<DeviceRecord> rows = records.entries.toList()
        ..sort((DeviceRecord a, DeviceRecord b) => top(a).compareTo(top(b)));
      return <String>[for (final DeviceRecord record in rows) record.name];
    }

    testWidgets('SNO-F-REC-07: записей нет — честное пустое состояние', (
      WidgetTester tester,
    ) async {
      await pumpList(tester);

      expect(records.refreshed, 1);
      expect(find.text('Записи на устройстве'), findsOneWidget);
      expect(
        find.text('Записей нет. Старт — в «Тестировании».'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sno-records-share-all')), findsNothing);
      expect(find.byKey(const Key('sno-records-reveal')), findsNothing);
    });

    testWidgets('SNO-F-REC-07: записи стоят от новых к старым, у каждой — '
        'длительность, размер и что с ней', (WidgetTester tester) async {
      records
        ..put(broken)
        ..put(fresh)
        ..put(sent);
      await pumpList(tester);

      expect(shownNames(tester), <String>[fresh.name, sent.name, broken.name]);
      expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · не отправлена');
      expect(aboutOf(tester, sent), '40:00 · 7,1 МБ · отправлена');
      expect(
        aboutOf(tester, broken),
        '17:42 · 3,0 МБ · прервана · не отправлена',
      );
      expect(find.byKey(const Key('sno-records-empty')), findsNothing);
      expect(find.text('Поделиться неотправленными (2)'), findsOneWidget);
    });

    testWidgets('SNO-F-REC-06: «Поделиться» отдаёт архив окну и помечает '
        'запись', (WidgetTester tester) async {
      records
        ..put(broken)
        ..put(fresh)
        ..put(sent);
      await pumpList(tester);

      await tap(tester, 'sno-record-share-${fresh.name}');

      expect(records.shared, <List<String>>[
        <String>[fresh.name],
      ]);
      expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · отправлена');
      expect(
        textOf(tester, 'sno-records-notice'),
        'Запись помечена отправленной.',
      );
      // Неотправленной осталась одна.
      expect(find.text('Поделиться неотправленными (1)'), findsOneWidget);
    });

    testWidgets('SNO-F-REC-06: «Поделиться неотправленными» отдаёт все '
        'разом', (WidgetTester tester) async {
      records
        ..put(broken)
        ..put(fresh)
        ..put(sent);
      await pumpList(tester);

      await tap(tester, 'sno-records-share-all');

      // Одно окно на обе записи; отправленная в него не идёт.
      expect(records.shared, <List<String>>[
        <String>[fresh.name, broken.name],
      ]);
      expect(
        textOf(tester, 'sno-records-notice'),
        'Записи помечены отправленными: 2.',
      );
      expect(find.byKey(const Key('sno-records-share-all')), findsNothing);
      expect(aboutOf(tester, broken), '17:42 · 3,0 МБ · прервана · отправлена');
    });

    testWidgets('SNO-F-REC-06: окно не открылось — запись не помечена, об '
        'этом сказано', (WidgetTester tester) async {
      records
        ..put(fresh)
        ..shareOpens = false;
      await pumpList(tester);

      await tap(tester, 'sno-record-share-${fresh.name}');

      expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · не отправлена');
      expect(
        textOf(tester, 'sno-records-notice'),
        'Поделиться не получилось: окно не открылось или архива уже нет '
        'на устройстве.',
      );
    });

    testWidgets('SNO-F-REC-06: большой архив — сначала предупреждение', (
      WidgetTester tester,
    ) async {
      final DeviceRecord large = DeviceRecord(
        name: 'sno2026_II_11112222_a91f3c_20261105-1000',
        bytes: 25 * 1024 * 1024,
        startedAt: DateTime(2026, 11, 5, 10),
        durationMs: 40 * 60 * 1000,
      );
      records.put(large);
      await pumpList(tester);

      await tap(tester, 'sno-record-share-${large.name}');

      expect(find.text('Большой архив'), findsOneWidget);
      expect(find.textContaining('Архив большой — 25,0 МБ'), findsOneWidget);
      expect(records.shared, isEmpty);

      await tap(tester, 'sno-share-cancel');
      expect(records.shared, isEmpty);

      await tap(tester, 'sno-record-share-${large.name}');
      await tap(tester, 'sno-share-anyway');
      expect(records.shared, <List<String>>[
        <String>[large.name],
      ]);
    });

    testWidgets('SNO-F-REC-07: отправленная запись удаляется одним '
        'подтверждением', (WidgetTester tester) async {
      records
        ..put(fresh)
        ..put(sent);
      await pumpList(tester);

      await tap(tester, 'sno-record-delete-${sent.name}');

      expect(find.text('Удалить запись с устройства?'), findsOneWidget);
      expect(find.text('${sent.name}.zip'), findsOneWidget);
      expect(records.deleted, isEmpty);

      await tap(tester, 'sno-record-confirm');

      expect(records.deleted, <String>[sent.name]);
      expect(find.byKey(Key('sno-record-${sent.name}')), findsNothing);
      expect(find.byKey(Key('sno-record-${fresh.name}')), findsOneWidget);
      expect(textOf(tester, 'sno-records-notice'), 'Запись удалена.');
    });

    testWidgets('SNO-F-REC-07: неотправленная запись удаляется только '
        'вторым подтверждением', (WidgetTester tester) async {
      records.put(fresh);
      await pumpList(tester);

      await tap(tester, 'sno-record-delete-${fresh.name}');
      await tap(tester, 'sno-record-confirm');

      // Первого «да» мало: запись никуда не ушла.
      expect(records.deleted, isEmpty);
      expect(find.text('Эта запись никуда не отправлена'), findsOneWidget);
      expect(find.text('Удалить безвозвратно'), findsOneWidget);

      // Отказ на втором вопросе запись оставляет.
      await tap(tester, 'sno-record-cancel');
      expect(records.deleted, isEmpty);
      expect(find.byKey(Key('sno-record-${fresh.name}')), findsOneWidget);

      await tap(tester, 'sno-record-delete-${fresh.name}');
      await tap(tester, 'sno-record-confirm');
      await tap(tester, 'sno-record-confirm');

      expect(records.deleted, <String>[fresh.name]);
      expect(
        find.text('Записей нет. Старт — в «Тестировании».'),
        findsOneWidget,
      );
    });

    testWidgets('SNO-F-REC-07: отказ на первом вопросе ничего не удаляет', (
      WidgetTester tester,
    ) async {
      records.put(sent);
      await pumpList(tester);

      await tap(tester, 'sno-record-delete-${sent.name}');
      await tap(tester, 'sno-record-cancel');

      expect(records.deleted, isEmpty);
      expect(find.byKey(Key('sno-record-${sent.name}')), findsOneWidget);
    });

    testWidgets('SNO-F-REC-07: запись не удалилась — об этом сказано', (
      WidgetTester tester,
    ) async {
      records
        ..put(sent)
        ..deleteWorks = false;
      await pumpList(tester);

      await tap(tester, 'sno-record-delete-${sent.name}');
      await tap(tester, 'sno-record-confirm');

      expect(textOf(tester, 'sno-records-notice'), 'Запись не удалилась.');
      expect(find.byKey(Key('sno-record-${sent.name}')), findsOneWidget);
    });

    testWidgets('SNO-F-REC-07: неупакованная и повреждённая записи '
        'помечены', (WidgetTester tester) async {
      final DeviceRecord folder = DeviceRecord(
        name: 'sno2026_I_33334444_a91f3c_20261106-0900',
        bytes: 512 * 1024,
        packed: false,
        startedAt: DateTime(2026, 11, 6, 9),
        durationMs: 5 * 60 * 1000,
      );
      final DeviceRecord damaged = DeviceRecord(
        name: 'sno2026_I_55556666_a91f3c_20261105-0900',
        bytes: 2048,
        damaged: true,
        startedAt: DateTime(2026, 11, 5, 9),
      );
      records
        ..put(folder)
        ..put(damaged);
      await pumpList(tester);

      expect(
        aboutOf(tester, folder),
        '05:00 · 512 КБ · не упакована · не отправлена',
      );
      expect(
        aboutOf(tester, damaged),
        '2,0 КБ · архив повреждён · не отправлена',
      );
      // Папку окну «Поделиться» не отдать; повреждённый архив — можно:
      // разбор решит, что с ним делать.
      expect(find.byKey(Key('sno-record-share-${folder.rowId}')), findsNothing);
      expect(
        find.byKey(Key('sno-record-share-${damaged.rowId}')),
        findsOneWidget,
      );
      // «Все неотправленные» — только то, что можно отдать.
      expect(find.text('Поделиться неотправленными (1)'), findsOneWidget);
    });

    testWidgets('SNO-F-REC-07: архив положили руками — он появляется в '
        'открытом списке', (WidgetTester tester) async {
      await pumpList(tester);
      expect(find.byKey(const Key('sno-records-empty')), findsOneWidget);

      records.put(fresh);
      await tester.pumpAndSettle();

      expect(find.byKey(Key('sno-record-${fresh.name}')), findsOneWidget);
      expect(find.byKey(const Key('sno-records-empty')), findsNothing);
    });

    group('SNO-F-REC-06: на ПК', () {
      setUp(() {
        records
          ..shares = false
          ..saves = true;
      });

      testWidgets('SNO-F-REC-06: вместо «Поделиться» — «Сохранить как…» и '
          '«Открыть папку»', (WidgetTester tester) async {
        records
          ..put(fresh)
          ..put(sent);
        await pumpList(tester);

        expect(find.byKey(Key('sno-record-share-${fresh.name}')), findsNothing);
        expect(find.byKey(const Key('sno-records-share-all')), findsNothing);
        expect(
          find.byKey(Key('sno-record-save-${fresh.name}')),
          findsOneWidget,
        );
        expect(find.text('Открыть папку'), findsOneWidget);
        expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · копии нет');
      });

      testWidgets('SNO-F-REC-06: копия сохранена — запись помечена «копия '
          'есть»', (WidgetTester tester) async {
        records.put(fresh);
        await pumpList(tester);

        await tap(tester, 'sno-record-save-${fresh.name}');

        expect(records.saved, <String>[fresh.name]);
        expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · копия есть');
        expect(
          textOf(tester, 'sno-records-notice'),
          'Копия сохранена и сверена с архивом.',
        );
      });

      testWidgets('SNO-F-REC-06: папку не выбрали — молча; выбрали папку '
          'записей или копия не легла — сказано', (WidgetTester tester) async {
        records
          ..put(fresh)
          ..copyOutcome = CopyOutcome.cancelled;
        await pumpList(tester);

        await tap(tester, 'sno-record-save-${fresh.name}');
        expect(find.byKey(const Key('sno-records-notice')), findsNothing);

        records.copyOutcome = CopyOutcome.inside;
        await tap(tester, 'sno-record-save-${fresh.name}');
        expect(
          textOf(tester, 'sno-records-notice'),
          startsWith('Это папка самих записей'),
        );

        records.copyOutcome = CopyOutcome.failed;
        await tap(tester, 'sno-record-save-${fresh.name}');
        expect(
          textOf(tester, 'sno-records-notice'),
          startsWith('Копия не сохранилась'),
        );
        expect(aboutOf(tester, fresh), '40:00 · 6,8 МБ · копии нет');
      });

      testWidgets('SNO-ALG-REC-04: «Открыть папку» открывает папку '
          'записей', (WidgetTester tester) async {
        records.put(fresh);
        await pumpList(tester);

        await tap(tester, 'sno-records-reveal');

        expect(records.revealed, <String?>[null]);
        expect(find.byKey(const Key('sno-records-notice')), findsNothing);

        records.revealOpens = false;
        await tap(tester, 'sno-records-reveal');
        expect(
          textOf(tester, 'sno-records-notice'),
          'Папка записей не открылась.',
        );
      });

      testWidgets('SNO-F-REC-07: запись без копии удаляется вторым '
          'подтверждением', (WidgetTester tester) async {
        records.put(fresh);
        await pumpList(tester);

        await tap(tester, 'sno-record-delete-${fresh.name}');
        await tap(tester, 'sno-record-confirm');

        expect(find.text('Копии этой записи нет'), findsOneWidget);
        expect(records.deleted, isEmpty);

        await tap(tester, 'sno-record-confirm');
        expect(records.deleted, <String>[fresh.name]);
      });
    });
  });

  group('SNO-F-REC-05: завершение сессии с архивом', () {
    /// Останавливает запись на двадцатой минуте и открывает экран
    /// завершения.
    Future<String> pumpFinish(WidgetTester tester) async {
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(20 * 60);
      await kit.session.stop(StopReason.experimenter);
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
      return folder;
    }

    testWidgets('SNO-F-REC-05: до завершения сказано, что запись соберётся '
        'в архив', (WidgetTester tester) async {
      await pumpFinish(tester);

      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(textOf(tester, 'sno-finish-code'), '6795-4332');
      expect(find.textContaining('собирается в архив'), findsOneWidget);
      expect(records.packed, isEmpty);
      expect(find.byKey(const Key('sno-finish-done')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-05: сессия завершена — запись упакована, экран '
        'показывает архив', (WidgetTester tester) async {
      final String folder = await pumpFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(records.packed, <String>[folder]);
      // Экран не закрылся: на нём архив, а не код.
      expect(find.byType(SessionFinishScreen), findsOneWidget);
      expect(find.text('Сессия завершена'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-code')), findsNothing);
      expect(find.byKey(const Key('sno-finish-hold')), findsNothing);
      expect(find.text('Архив записи готов'), findsOneWidget);
      expect(textOf(tester, 'sno-finish-archive'), '$folder.zip');
      expect(
        textOf(tester, 'sno-finish-archive-about'),
        '20:00 · 1482 события · 412 КБ',
      );
      expect(
        find.text('Архив лежит в «Записях на устройстве».'),
        findsOneWidget,
      );

      await tap(tester, 'sno-finish-close');
      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(kit.session.finishOpen.value, isFalse);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-05: пока архив собирается, об этом сказано, а '
        '«Готово» ждёт', (WidgetTester tester) async {
      records.packGate = Completer<void>();
      await pumpFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(find.text('Собираю архив…'), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-archive')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('sno-finish-close')))
            .onPressed,
        isNull,
      );

      records.packGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Собираю архив…'), findsNothing);
      expect(find.byKey(const Key('sno-finish-archive')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('sno-finish-close')))
            .onPressed,
        isNotNull,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-06: с телефона архив уходит кнопкой '
        '«Поделиться»', (WidgetTester tester) async {
      final String folder = await pumpFinish(tester);
      await holdOn(tester, 'sno-finish-hold');

      expect(find.byKey(const Key('sno-finish-save')), findsNothing);
      expect(find.byKey(const Key('sno-finish-reveal')), findsNothing);

      await tap(tester, 'sno-finish-share');

      expect(records.shared, <List<String>>[
        <String>[folder],
      ]);
      expect(
        textOf(tester, 'sno-finish-notice'),
        'Запись помечена отправленной.',
      );
      expect(records.entries.single.sharedAt, isNotNull);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-06: окно «Поделиться» не открылось — сказано, '
        'архив остаётся', (WidgetTester tester) async {
      records.shareOpens = false;
      await pumpFinish(tester);
      await holdOn(tester, 'sno-finish-hold');

      await tap(tester, 'sno-finish-share');

      expect(
        textOf(tester, 'sno-finish-notice'),
        'Поделиться не получилось: окно не открылось или архива уже нет '
        'на устройстве.',
      );
      expect(records.entries.single.taken, isFalse);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-06: на ПК — «Сохранить архив как…» и «Открыть '
        'папку»', (WidgetTester tester) async {
      records
        ..shares = false
        ..saves = true;
      final String folder = await pumpFinish(tester);
      await holdOn(tester, 'sno-finish-hold');

      expect(find.byKey(const Key('sno-finish-share')), findsNothing);
      expect(find.text('Сохранить архив как…'), findsOneWidget);

      await tap(tester, 'sno-finish-save');

      expect(records.saved, <String>[folder]);
      expect(
        textOf(tester, 'sno-finish-notice'),
        'Копия сохранена и сверена с архивом.',
      );
      expect(records.entries.single.copiedAt, isNotNull);

      await tap(tester, 'sno-finish-reveal');

      // Папка открывается на файле записи; сказать после этого нечего.
      expect(records.revealed, <String?>[folder]);
      expect(find.byKey(const Key('sno-finish-notice')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-05: архив не собрался — запись цела, об этом '
        'сказано', (WidgetTester tester) async {
      records.onPack = (String folder) {
        return DeviceRecord(name: folder, bytes: 1024, packed: false);
      };
      await pumpFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(kit.session.phase, RecordingPhase.idle);
      expect(
        textOf(tester, 'sno-finish-unpacked'),
        startsWith('Архив не собран: запись цела'),
      );
      expect(find.byKey(const Key('sno-finish-share')), findsNothing);
      expect(find.byKey(const Key('sno-finish-archive')), findsNothing);

      await tap(tester, 'sno-finish-close');
      expect(find.byType(SessionFinishScreen), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-05: записи с таким именем не нашлось — то же '
        'сообщение, экран не падает', (WidgetTester tester) async {
      records.onPack = (String folder) => null;
      await pumpFinish(tester);

      await holdOn(tester, 'sno-finish-hold');

      expect(find.byKey(const Key('sno-finish-unpacked')), findsOneWidget);
      expect(find.byKey(const Key('sno-finish-close')), findsOneWidget);

      await unmount(tester);
    });
  });

  group('SNO-F-CFG-03: строка записей в «Тестировании»', () {
    Future<void> pumpTesting(WidgetTester tester, {bool visible = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(
              data: data,
              recording: kit.session,
              records: records,
            ),
            flags: BranchFlags.of('I'),
            visible: visible,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-REC-07: сессии нет — строка есть, и на ней счёт '
        'записей', (WidgetTester tester) async {
      records
        ..put(broken)
        ..put(fresh)
        ..put(sent);
      await pumpTesting(tester);

      expect(find.text('Записи на устройстве'), findsOneWidget);
      expect(textOf(tester, 'sno-records-count'), '3 · не отправлено 2');
      // Заглушки про записи в разделе больше нет.
      expect(
        find.textContaining('записи на устройстве появятся'),
        findsNothing,
      );
      expect(
        find.text('Тест появится здесь следующей сборкой.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-07: записей нет — так и сказано; на ПК счёт — '
        'записи без копии', (WidgetTester tester) async {
      await pumpTesting(tester);
      expect(textOf(tester, 'sno-records-count'), 'нет');

      records
        ..shares = false
        ..saves = true
        ..put(fresh)
        ..put(sent);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'sno-records-count'), '2 · без копии 1');

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-07: во время записи и до завершения сессии строки '
        'нет', (WidgetTester tester) async {
      records.put(sent);
      await pumpTesting(tester);
      expect(find.byKey(const Key('sno-records')), findsOneWidget);

      await kit.session.start(code);
      await tester.pumpAndSettle();
      // Участнику чужие записи не показываются.
      expect(find.byKey(const Key('sno-records')), findsNothing);

      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-records')), findsNothing);

      await kit.session.finish();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-records')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-07: пока идёт старт записи, строки тоже нет', (
      WidgetTester tester,
    ) async {
      records.put(sent);
      await pumpTesting(tester);

      await tap(tester, 'sno-record-start');

      // Открыт экран кода; под ним в разделе строки записей уже нет —
      // список, открытый в этот миг, остался бы поверх записи.
      expect(find.text('Ваш код'), findsOneWidget);
      expect(
        find.byKey(const Key('sno-records'), skipOffstage: false),
        findsNothing,
      );

      await tap(tester, 'sno-code-cancel');
      expect(find.byKey(const Key('sno-records')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-07: строка ведёт к списку, а счёт на ней следует '
        'за списком', (WidgetTester tester) async {
      records
        ..put(fresh)
        ..put(sent);
      await pumpTesting(tester);

      await tap(tester, 'sno-records');

      expect(find.byType(DeviceRecordsScreen), findsOneWidget);

      await tap(tester, 'sno-record-share-${fresh.name}');
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(DeviceRecordsScreen), findsNothing);
      expect(textOf(tester, 'sno-records-count'), '2');

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-05: завершение сессии из раздела оставляет архив '
        'в счёте записей', (WidgetTester tester) async {
      await pumpTesting(tester);
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(60);
      await kit.session.stop(StopReason.experimenter);
      await tester.pumpAndSettle();

      await tap(tester, 'sno-session-finish');
      await holdOn(tester, 'sno-finish-hold');

      expect(records.packed, <String>[folder]);
      expect(textOf(tester, 'sno-finish-archive'), '$folder.zip');

      await tap(tester, 'sno-finish-close');

      expect(find.byType(SessionFinishScreen), findsNothing);
      expect(textOf(tester, 'sno-records-count'), '1 · не отправлено 1');
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-07: раздел вернулся на экран — список '
        'перечитан', (WidgetTester tester) async {
      await pumpTesting(tester, visible: false);
      final int before = records.refreshed;

      await pumpTesting(tester);

      expect(records.refreshed, before + 1);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-08: записи при запуске приложения', () {
    test('SNO-F-REC-08: сессия поднялась — папки без сессии подбираются, '
        'оставшееся упаковывается', () async {
      await recoverRecords(
        testServices(data: data, recording: kit.session, records: records),
        restored: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(records.adopted, 1);
      expect(records.pending, 1);
    });

    test('SNO-F-REC-08: сессия не поднялась — папки среди незавершённых '
        'не трогают', () async {
      // Чья папка лежит среди незавершённых, неизвестно: это может
      // быть запись, которую ещё предстоит закрыть.
      await recoverRecords(
        testServices(data: data, recording: kit.session, records: records),
        restored: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(records.adopted, 0);
      expect(records.pending, 1);
    });

    test('SNO-F-REC-08: записей в сборке нет — делать нечего', () async {
      await recoverRecords(testServices(data: data), restored: true);

      expect(records.adopted, 0);
      expect(records.pending, 0);
    });
  });

  group('SNO-F-REC-07: слова о записях', () {
    test('SNO-F-REC-07: «событие» согласуется с числом', () {
      expect(describeEventCount(1), '1 событие');
      expect(describeEventCount(2), '2 события');
      expect(describeEventCount(5), '5 событий');
      expect(describeEventCount(11), '11 событий');
      expect(describeEventCount(12), '12 событий');
      expect(describeEventCount(21), '21 событие');
      expect(describeEventCount(22), '22 события');
      expect(describeEventCount(111), '111 событий');
      expect(describeEventCount(1482), '1482 события');
      expect(describeEventCount(0), '0 событий');
    });

    test('SNO-F-REC-07: счёт записей — сколько всего и сколько не ушло', () {
      expect(describeRecordsCount(const <DeviceRecord>[], shares: true), 'нет');
      expect(describeRecordsCount(<DeviceRecord>[sent], shares: true), '1');
      expect(
        describeRecordsCount(<DeviceRecord>[sent, fresh, broken], shares: true),
        '3 · не отправлено 2',
      );
      expect(
        describeRecordsCount(<DeviceRecord>[sent, fresh], shares: false),
        '2 · без копии 1',
      );
    });

    test('SNO-F-REC-07: записи без времени старта стоят в конце списка', () {
      const DeviceRecord nameless = DeviceRecord(name: 'б', bytes: 1);
      const DeviceRecord other = DeviceRecord(name: 'а', bytes: 1);

      expect(
        <String>[
          for (final DeviceRecord record in orderRecords(<DeviceRecord>[
            other,
            sent,
            nameless,
            fresh,
          ]))
            record.name,
        ],
        <String>[fresh.name, sent.name, 'б', 'а'],
      );
    });

    test('SNO-F-REC-06: предупреждение о размере — по сумме архивов', () {
      expect(describeLargeShare(<DeviceRecord>[fresh, sent]), isNull);
      expect(
        describeLargeShare(<DeviceRecord>[fresh, sent, sent]),
        contains('21,0 МБ'),
      );
    });

    test('SNO-F-REC-07: сведения записи читаются из манифеста', () {
      final DeviceRecord record = recordFrom(
        name: fresh.name,
        bytes: 100,
        packed: true,
        info: <String, Object?>{
          'branch': 'II',
          'participant': <String, Object?>{'code': '67954332'},
          'recording': <String, Object?>{
            'clock_anchor': '2026-11-03T14:02:11.482+03:00',
            'duration_ms': 1000,
            'events': 7,
            'stopped_by': 'crash',
          },
        },
        state: <String, Object?>{'shared_at': '2026-11-03T15:00:00.000+03:00'},
      );

      expect(record.branch, 'II');
      expect(record.participant, '67954332');
      expect(record.durationMs, 1000);
      expect(record.events, 7);
      expect(record.interrupted, isTrue);
      expect(record.sharedAt, isNotNull);
      expect(record.copiedAt, isNull);
      expect(record.taken, isTrue);
    });

    test('SNO-F-REC-07: манифеста нет — строка есть, сведений нет', () {
      final DeviceRecord record = recordFrom(
        name: fresh.name,
        bytes: 100,
        packed: true,
        info: null,
        damaged: true,
      );

      expect(record.damaged, isTrue);
      expect(record.durationMs, isNull);
      expect(record.startedAt, isNull);
      expect(record.interrupted, isFalse);
      expect(record.taken, isFalse);
    });
  });
}
