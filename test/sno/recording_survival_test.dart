import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/code_screen.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/journal_check.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/mini_schema.dart';
import '../support/recording_fakes.dart';

/// SNO-F-REC-13: запись не теряется — правила сессии.
///
/// Служба переднего плана, самопроверка журнала, паспорт устройства,
/// заряд и место в сердцебиении. Время, диск и устройство подменены;
/// родной код службы проверяется сборкой и руками.
void main() {
  /// Код участника, с которым начинают запись в этих тестах.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  /// Сведения о записи из `recording.json` папки [folder].
  Map<String, Object?> recordingOf(SessionKit kit, String folder) {
    return kit.store.json(folder, kRecordingFile)['recording']!
        as Map<String, Object?>;
  }

  /// События вида [type] в журнале папки [folder].
  List<Map<String, Object?>> eventsOf(
    SessionKit kit,
    String folder,
    SnoEventType type,
  ) {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(folder))
        if (event['type'] == type.wire) event,
    ];
  }

  Map<String, Object?> dataOf(Map<String, Object?> event) {
    return event['data']! as Map<String, Object?>;
  }

  /// «Приложение перезапущено»: новая сессия на том, что оставила
  /// прежняя.
  SessionKit restarted(SessionKit first, {FakeRecordingGuard? guard}) {
    return SessionKit(
      settings: first.settings,
      store: first.store,
      time: first.time,
      status: first.status,
      guard: guard,
    );
  }

  group('SNO-F-REC-13: служба переднего плана', () {
    test('SNO-F-REC-13: служба заведена стартом и снята остановкой', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit kit = SessionKit(guard: guard);

      await kit.session.start(code);
      await kit.settle();

      expect(guard.calls, <String>['hold']);
      expect(guard.held, isTrue);
      // Ни времени, ни кода участника в уведомлении нет.
      expect(guard.words, (title: 'Идёт запись', text: kGuardText));
      expect(guard.words!.text, isNot(contains(kTestCode)));

      kit.run(30);
      await kit.session.stop(StopReason.experimenter);
      await kit.settle();

      expect(guard.calls, <String>['hold', 'release']);
      expect(guard.held, isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: запись, которая кончилась сама, службу тоже '
        'снимает', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit kit = SessionKit(
        guard: guard,
        planned: const Duration(seconds: 20),
      );
      await kit.session.start(code);
      await kit.settle();

      kit.run(20);
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(guard.held, isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: в журнале сказано, заведена ли служба и видно ли '
        'уведомление', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false);
      final SessionKit kit = SessionKit(guard: guard);
      await kit.session.start(code);
      await kit.settle();
      kit.run(1);
      await kit.settle();

      final List<Map<String, Object?>> said = eventsOf(
        kit,
        kit.folder,
        SnoEventType.recordingGuard,
      );
      expect(said, hasLength(1));
      expect(dataOf(said.single), <String, Object?>{
        'service': true,
        'notifications': false,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-13: служба не завелась — запись идёт, и об этом '
        'сказано', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(holds: false);
      final SessionKit kit = SessionKit(guard: guard);

      expect(await kit.session.start(code), isTrue);
      await kit.settle();
      kit.run(1);
      await kit.settle();

      expect(kit.session.recording, isTrue);
      expect(
        dataOf(
          eventsOf(kit, kit.folder, SnoEventType.recordingGuard).single,
        )['service'],
        isFalse,
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-13: запись остановили, пока служба заводилась, — '
        'служба не остаётся висеть', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard()
        ..holdGate = Completer<void>();
      final SessionKit kit = SessionKit(guard: guard);
      await kit.session.start(code);
      kit.run(2);

      await kit.session.stop(StopReason.experimenter);
      expect(guard.calls, <String>['hold', 'release']);
      // Служба ответила уже после остановки: её снимают ещё раз, а в
      // журнал остановленной записи о ней не пишут.
      guard.holdGate!.complete();
      await kit.settle();

      expect(guard.calls, <String>['hold', 'release', 'release']);
      expect(guard.held, isFalse);
      expect(eventsOf(kit, kit.folder, SnoEventType.recordingGuard), isEmpty);
      expect(kit.store.types(kit.folder).last, 'recording.stop');
      kit.session.dispose();
    });

    test('SNO-F-REC-13: у устройства без защиты в журнале о службе ни '
        'слова', () async {
      // ПК и тесты: свёрнутое окно никто не выгружает.
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(1);
      await kit.settle();

      expect(eventsOf(kit, kit.folder, SnoEventType.recordingGuard), isEmpty);
      expect(await kit.session.notificationsAllowed(), isNull);
      expect(await kit.session.prepareGuard(), isNull);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: после сбоя служба не висит — запуск её '
        'снимает', () async {
      final SessionKit first = SessionKit(guard: FakeRecordingGuard());
      await first.session.start(code);
      first.run(5);
      await first.settle();
      first.session.dispose();

      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit second = restarted(first, guard: guard);
      await second.session.restore();
      await second.settle();

      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(guard.calls, <String>['release']);
      second.session.dispose();
    });

    test('SNO-F-REC-13: запуск без сессии службу снимает тоже', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit kit = SessionKit(guard: guard);

      await kit.session.restore();
      await kit.settle();

      expect(guard.calls, <String>['release']);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-13: разрешение на уведомления', () {
    test('SNO-F-REC-13: уведомления разрешены — спрашивать не о чем', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit kit = SessionKit(guard: guard);

      expect(await kit.session.prepareGuard(), isTrue);

      expect(guard.asked, 0);
      expect(
        kit.settings.values.containsKey(SnoSettingsKeys.notificationsAsked),
        isFalse,
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-13: не разрешены — спрашивают один раз за всё '
        'время', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false)
        ..answer = false;
      final SessionKit kit = SessionKit(guard: guard);

      expect(await kit.session.prepareGuard(), isFalse);
      expect(guard.asked, 1);
      expect(
        kit.settings.values[SnoSettingsKeys.notificationsAsked],
        isNotNull,
      );

      // Следующий участник: вопроса больше нет, запись всё равно идёт.
      expect(await kit.session.prepareGuard(), isFalse);
      expect(guard.asked, 1);
      expect(await kit.session.start(code), isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: разрешили в ответ на вопрос — так и сказано', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false);
      final SessionKit kit = SessionKit(guard: guard);

      expect(await kit.session.prepareGuard(), isTrue);
      expect(await kit.session.notificationsAllowed(), isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: система на вопрос не ответила — спросят ещё '
        'раз', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false)
        ..answer = null;
      final SessionKit kit = SessionKit(guard: guard);

      expect(await kit.session.prepareGuard(), isFalse);

      // Окно могло и не показаться: отметки «спрашивали» нет.
      expect(guard.asked, 1);
      expect(
        kit.settings.values.containsKey(SnoSettingsKeys.notificationsAsked),
        isFalse,
      );
      guard
        ..allowed = false
        ..answer = true;
      expect(await kit.session.prepareGuard(), isTrue);
      expect(guard.asked, 2);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: настройки не ответили — второго вопроса подряд '
        'нет', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard(allowed: false);
      final SessionKit kit = SessionKit(guard: guard);
      kit.settings.failReads = true;

      expect(await kit.session.prepareGuard(), isFalse);

      expect(guard.asked, 0);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-13: самопроверка журнала после остановки', () {
    test('SNO-F-REC-13: журнал перечитан с диска — запись цела', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(30);
      expect(kit.session.checked.value, isFalse);
      expect(kit.session.check, isNull);

      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.checked.value, isTrue);
      final JournalCheck check = kit.session.check!;
      expect(check.intact, isTrue);
      expect(check.lines, kit.session.events);
      expect(check.lines, kit.store.lines(folder).length);
      expect(check.late, isFalse);
      expect(recordingOf(kit, folder)['check'], <String, Object?>{
        'lines': check.lines,
        'gaps': 0,
        'torn': false,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-13: строки, не дошедшие до диска, найдены', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(3);
      await kit.settle();
      // Диск отказал на несколько секунд записи.
      kit.store.failAppend = true;
      kit.session.log(SnoEventType.pageShown);
      kit.session.log(SnoEventType.pageShown);
      kit.run(1);
      await kit.settle();
      kit.store.failAppend = false;
      kit.run(3);

      await kit.session.stop(StopReason.experimenter);

      final JournalCheck check = kit.session.check!;
      expect(check.intact, isFalse);
      expect(check.gaps, 2);
      expect(check.torn, isFalse);
      expect(recordingOf(kit, folder)['check'], <String, Object?>{
        'lines': check.lines,
        'gaps': 2,
        'torn': false,
      });
      // Отказ диска помнится и сам по себе.
      expect(kit.session.writeFailed, isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: журнал не перечитался — проверки нет, запись '
        'остановлена', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(5);
      kit.store.failBytes = true;

      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.checked.value, isTrue);
      expect(kit.session.check, isNull);
      expect(recordingOf(kit, folder).containsKey('check'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: итог проверки доживает до завершения сессии', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(10);
      await kit.session.stop(StopReason.experimenter);
      final int lines = kit.session.check!.lines;

      await kit.session.finish();

      // Событие завершения дописано после проверки: в ней его нет.
      expect(kit.store.lines(folder).length, lines + 1);
      final Map<String, Object?> recording = recordingOf(kit, folder);
      expect(recording['finished'], isTrue);
      expect(recording['check'], <String, Object?>{
        'lines': lines,
        'gaps': 0,
        'torn': false,
      });
      expect(kit.session.checked.value, isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: у оборванной записи журнал сверен до того, как '
        'отрезан его хвост', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.run(5);
      await first.settle();
      first.session.dispose();
      final int whole = first.store.lines(folder).length;
      // Приложение умерло посреди записи строки.
      first.store.journals[folder]!.write('{"seq":${whole + 1},"t":61');

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.checked.value, isTrue);
      final JournalCheck check = second.session.check!;
      expect(check.torn, isTrue);
      expect(check.late, isTrue);
      expect(check.lines, whole);
      expect(check.gaps, 0);
      expect(recordingOf(second, folder)['check'], <String, Object?>{
        'lines': whole,
        'gaps': 0,
        'torn': true,
        'late': true,
      });
      second.session.dispose();
    });

    test('SNO-F-REC-13: запись, остановленная прежней сборкой, проверяется '
        'при запуске', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(10);
      await first.session.stop(StopReason.experimenter);
      // Прежняя сборка журнала не перечитывала: итога в отметке нет.
      final SessionState old = first.session.state!.withCheck(null);
      first.settings.values[SnoSettingsKeys.session] = old.encode();
      first.session.dispose();

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.phase, RecordingPhase.stopped);
      expect(second.session.checked.value, isTrue);
      final JournalCheck check = second.session.check!;
      expect(check.intact, isTrue);
      // Сколько событий посчитала запись, известно: проверка полная.
      expect(check.late, isFalse);
      expect(check.lines, old.events);
      second.session.dispose();
    });

    test('SNO-F-REC-13: сессию сняли, пока остановка дописывала своё, — '
        'остановка доходит до конца', () async {
      final FakeRecordingGuard guard = FakeRecordingGuard();
      final SessionKit kit = SessionKit(guard: guard);
      await kit.session.start(code);
      kit.run(5);

      final Future<void> stopping = kit.session.stop(StopReason.experimenter);
      kit.session.dispose();
      await stopping;

      // Отметка об остановке легла, служба снята, экран отпущен.
      final SessionState? marked = SessionState.decode(
        kit.settings.values[SnoSettingsKeys.session],
      );
      expect(marked!.phase, RecordingPhase.stopped);
      expect(marked.check, isNotNull);
      expect(guard.held, isFalse);
      expect(kit.status.screen.last, isFalse);
    });

    test('SNO-F-REC-13: оборванная запись, не сверенная при первом '
        'запуске, и при втором «целой» не названа', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(5);
      await first.settle();
      first.session.dispose();

      // Первый запуск после сбоя журнала не прочитал.
      first.store.failBytes = true;
      final SessionKit second = restarted(first);
      await second.session.restore();
      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(second.session.check, isNull);
      second.session.dispose();

      first.store.failBytes = false;
      final SessionKit third = restarted(first);
      await third.session.restore();

      final JournalCheck check = third.session.check!;
      expect(check.intact, isTrue);
      expect(check.late, isTrue);
      expect(
        describeJournalCheck(check),
        startsWith('Журнал цел до обрыва записи'),
      );
      third.session.dispose();
    });

    test('SNO-F-REC-13: итог проверки переживает перезапуск '
        'приложения', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(10);
      await first.session.stop(StopReason.experimenter);
      final JournalCheck told = first.session.check!;
      first.session.dispose();

      final SessionKit second = restarted(first);
      await second.session.restore();

      final JournalCheck check = second.session.check!;
      expect(check.lines, told.lines);
      expect(check.intact, isTrue);
      // Проверено в миг остановки, а не сейчас.
      expect(check.late, isFalse);
      second.session.dispose();
    });
  });

  group('SNO-F-REC-13: паспорт устройства', () {
    test('SNO-F-REC-13: паспорт лежит в сведениях записи с её '
        'начала', () async {
      final SessionKit kit = SessionKit(
        passport: const <String, Object?>{
          'os': 'Android',
          'os_version': '14',
          'sdk': 34,
          'manufacturer': 'Google',
          'model': 'Pixel 7',
          'screen': <String, Object?>{
            'width_px': 1080,
            'height_px': 2400,
            'density': 2.625,
          },
          'font_scale': 1.15,
        },
      );

      await kit.session.start(code);

      expect(
        kit.store.json(kit.folder, kRecordingFile)['device'],
        <String, Object?>{
          'os': 'Android',
          'os_version': '14',
          'sdk': 34,
          'manufacturer': 'Google',
          'model': 'Pixel 7',
          'screen': <String, Object?>{
            'width_px': 1080,
            'height_px': 2400,
            'density': 2.625,
          },
          'font_scale': 1.15,
          'node_id': kTestNode,
          'code': 'a91f3c',
        },
      );
      kit.session.dispose();
    });

    test('SNO-ALG-REC-03: паспорт и итог самопроверки проходят схему '
        'манифеста', () async {
      final SessionKit kit = SessionKit(
        passport: const <String, Object?>{
          'os': 'Android',
          'os_version': '14',
          'sdk': 34,
          'manufacturer': 'Google',
          'brand': 'google',
          'model': 'Pixel 7',
          'screen': <String, Object?>{
            'width_px': 1080,
            'height_px': 2400,
            'density': 2.625,
          },
          'font_scale': 1.15,
        },
      );
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(5);
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();

      // Манифест — то же, что сведения записи, плюс перечень файлов.
      final Map<String, Object?> manifest = jsonDecode(
        jsonEncode(
          buildManifest(
            info: kit.store.json(folder, kRecordingFile),
            archiveName: '$folder.zip',
            packedAt: kit.time.now(),
            files: const <PackedFile>[],
          ),
        ),
      ) as Map<String, Object?>;
      final Map<String, Object?> schema = jsonDecode(
        await File('tool/sno_manifest.schema.json').readAsString(),
      ) as Map<String, Object?>;

      expect(schemaProblems(manifest, schema), isEmpty);
      expect((manifest['device']! as Map<String, Object?>)['model'], 'Pixel 7');
      expect(
        (manifest['recording']! as Map<String, Object?>)['check'],
        isNotNull,
      );
    });

    test('SNO-F-REC-13: паспорт не подменяет узел и код устройства', () async {
      final SessionKit kit = SessionKit(
        passport: const <String, Object?>{'code': 'чужой', 'node_id': 'x'},
      );

      await kit.session.start(code);

      final Map<String, Object?> device =
          kit.store.json(kit.folder, kRecordingFile)['device']!
              as Map<String, Object?>;
      expect(device['node_id'], kTestNode);
      expect(device['code'], 'a91f3c');
      kit.session.dispose();
    });

    test('SNO-F-REC-13: паспорт снят в миг старта и переживает '
        'перезапуск', () async {
      final SessionKit first = SessionKit(
        passport: const <String, Object?>{
          'model': 'Pixel 7',
          'screen': <String, Object?>{
            'width_px': 1080,
            'height_px': 2400,
            'density': 2.625,
          },
        },
      );
      await first.session.start(code);
      final String folder = first.folder;
      first.run(5);
      await first.settle();
      first.session.dispose();

      // После перезапуска окна ещё нет: устройство о себе молчит.
      final SessionKit second = restarted(first);
      await second.session.restore();
      await second.session.finish();

      expect(
        second.store.json(folder, kRecordingFile)['device'],
        <String, Object?>{
          'model': 'Pixel 7',
          'screen': <String, Object?>{
            'width_px': 1080,
            'height_px': 2400,
            'density': 2.625,
          },
          'node_id': kTestNode,
          'code': 'a91f3c',
        },
      );
      second.session.dispose();
    });

    test('SNO-F-REC-13: устройство ничего о себе не сказало — узел и код '
        'на месте', () async {
      final SessionKit kit = SessionKit();

      await kit.session.start(code);
      await kit.session.stop(StopReason.experimenter);

      expect(
        kit.store.json(kit.folder, kRecordingFile)['device'],
        <String, Object?>{'node_id': kTestNode, 'code': 'a91f3c'},
      );
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-13: заряд и место по ходу записи', () {
    test('SNO-F-REC-13: сердцебиение несёт заряд и свободное место', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 84, free: 1288490189),
      );
      await kit.session.start(code);
      await kit.settle();

      kit.run(kHeartbeatTicks);
      await kit.settle();

      final List<Map<String, Object?>> beats = eventsOf(
        kit,
        kit.folder,
        SnoEventType.heartbeat,
      );
      expect(beats, hasLength(1));
      expect(dataOf(beats.single), <String, Object?>{
        'battery': 84,
        'free_mb': 1228,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-13: устройство молчит — сердцебиение без данных', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      await kit.settle();

      kit.run(kHeartbeatTicks);
      await kit.settle();

      final Map<String, Object?> beat = eventsOf(
        kit,
        kit.folder,
        SnoEventType.heartbeat,
      ).single;
      expect(beat.containsKey('data'), isFalse);
      expect(eventsOf(kit, kit.folder, SnoEventType.deviceLow), isEmpty);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: заряд ниже пяти процентов — строка о причине, и '
        'один раз', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 40, free: 1288490189),
      );
      await kit.session.start(code);
      await kit.settle();
      kit.run(kHeartbeatTicks);
      await kit.settle();
      expect(eventsOf(kit, kit.folder, SnoEventType.deviceLow), isEmpty);

      kit.status.battery = kCriticalBatteryPercent - 1;
      // Об изменении запись узнаёт со следующим вопросом к устройству.
      kit.run(kHeartbeatTicks);
      await kit.settle();
      kit.run(1);
      await kit.settle();

      final List<Map<String, Object?>> low = eventsOf(
        kit,
        kit.folder,
        SnoEventType.deviceLow,
      );
      expect(low, hasLength(1));
      expect(dataOf(low.single), <String, Object?>{
        'what': <String>['battery'],
        'battery': 4,
        'free_mb': 1228,
      });

      // Заряд так и лежит: второй строки нет.
      kit.run(kHeartbeatTicks * 3);
      await kit.settle();
      expect(eventsOf(kit, kit.folder, SnoEventType.deviceLow), hasLength(1));

      // Поставили на зарядку и снова уронили — строка новая.
      kit.status.battery = 30;
      kit.run(kHeartbeatTicks);
      await kit.settle();
      kit.status.battery = 3;
      kit.run(kHeartbeatTicks);
      await kit.settle();
      kit.run(1);
      await kit.settle();
      expect(eventsOf(kit, kit.folder, SnoEventType.deviceLow), hasLength(2));
      kit.session.dispose();
    });

    test('SNO-F-REC-13: место на исходе — строка о причине', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 84, free: kCriticalSpaceBytes - 1),
      );

      await kit.session.start(code);
      await kit.settle();
      kit.run(1);
      await kit.settle();

      final Map<String, Object?> low = eventsOf(
        kit,
        kit.folder,
        SnoEventType.deviceLow,
      ).single;
      expect(dataOf(low)['what'], <String>['space']);
      expect(dataOf(low)['free_mb'], 19);
      kit.session.dispose();
    });

    test('SNO-F-REC-13: после остановки о заряде больше не пишут', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 84, free: 1288490189),
      );
      await kit.session.start(code);
      await kit.settle();
      // Вопрос к устройству уходит с сердцебиением и ответить не
      // успевает: запись остановлена раньше.
      kit.status.battery = 2;
      kit.run(kHeartbeatTicks);

      await kit.session.stop(StopReason.experimenter);
      await kit.settle();

      expect(eventsOf(kit, kit.folder, SnoEventType.deviceLow), isEmpty);
      expect(kit.store.types(kit.folder).last, 'recording.stop');
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-13: предупреждения перед стартом', () {
    test('SNO-F-REC-13: устройство отличается от эталона — сказано '
        'словами', () {
      const Readiness ready = Readiness(batteryPercent: 84, freeBytes: 1 << 30);

      expect(describeReadinessWarnings(ready), isEmpty);
      expect(describeReadinessWarnings(ready.withReference(true)), isEmpty);
      expect(describeReadinessWarnings(ready.withReference(false)), <String>[
        'Устройство отличается от эталона — сбросьте его перед записью.',
      ]);
      // Сверить не удалось — предупреждать не о чем.
      expect(describeReadinessWarnings(ready.withReference(null)), isEmpty);
    });

    test('SNO-F-REC-13: замечания об эталоне, заряде и месте стоят '
        'вместе', () {
      final List<String> warnings = describeReadinessWarnings(
        const Readiness(
          batteryPercent: 24,
          freeBytes: 50 * 1024 * 1024,
          matchesReference: false,
        ),
      );

      expect(warnings, hasLength(3));
      expect(warnings.first, startsWith('Устройство отличается от эталона'));
      expect(warnings[1], startsWith('Заряд 24 %'));
    });
  });
}
