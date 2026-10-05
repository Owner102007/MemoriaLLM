import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/library/shelf_archive.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/reference_state.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';

/// SNO-F-REC-01, SNO-F-CFG-05, SNO-F-REC-02: сессия записи.
///
/// Время, диск и устройство подменены: секунды записи идут по слову
/// теста. Экраны записи — в `recording_screens_test.dart`.
void main() {
  /// Код участника, с которым начинают запись в этих тестах.
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  const Duration forty = Duration(minutes: 40);

  group('SNO-F-REC-02: вне записи', () {
    test('SNO-F-REC-02: записи нет — ни одна строка не пишется', () async {
      final SessionKit kit = SessionKit();
      kit.session.log(SnoEventType.heartbeat);
      kit.session.tick();
      kit.session.appLeft('paused');
      kit.session.appReturned();
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();
      await kit.settle();

      expect(kit.store.journals, isEmpty);
      expect(kit.store.files, isEmpty);
      expect(kit.store.current, isEmpty);
      expect(kit.settings.values, isEmpty);
      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.session.locked, isFalse);
      expect(kit.session.events, 0);
      expect(kit.ticking, isFalse);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-01: старт записи', () {
    test('SNO-F-REC-01: запись создана — часы, журнал, снимок', () async {
      final SessionKit kit = SessionKit();
      final DateTime startedAt = kit.time.wall;

      expect(await kit.session.start(code), isTrue);

      expect(kit.session.phase, RecordingPhase.recording);
      expect(kit.session.recording, isTrue);
      expect(kit.session.participant, code);
      expect(kit.ticking, isTrue);
      expect(kit.status.screen, <bool>[true]);

      // Папка названа так же, как будет назван архив.
      final String folder = kit.folder;
      expect(
        folder,
        recordingFolderName(
          branch: 'I',
          code: kTestCode,
          device: 'a91f3c',
          startedAt: startedAt,
        ),
      );
      expect(folder, startsWith('sno2026_I_67954332_a91f3c_'));
      expect(kit.store.current, <String>{folder});

      final List<Map<String, Object?>> events = kit.store.events(folder);
      expect(events, hasLength(1));
      final Map<String, Object?> first = events.single;
      expect(first['seq'], 1);
      expect(first['t'], 0);
      expect(first['type'], 'recording.start');
      expect(first['wall'], isoWithOffset(startedAt));
      final Map<String, Object?> data = first['data']! as Map<String, Object?>;
      expect(data['participant'], kTestCode);
      expect(data['code_generated'], isTrue);
      expect(data['planned_s'], 2400);
      expect(data['clock_anchor'], isoWithOffset(startedAt));
      expect(data['recording'], kit.session.state!.id);
      expect(data['matches_reference'], isTrue);
      expect(data['shelf_sort'], 'default');
      expect(data['shelf_sort_forced'], isFalse);

      // Снимок начала — тот, что отдал хранитель эталона.
      expect(kit.store.json(folder, kSnapshotStartFile), kit.snapshot);

      // Сведения записи: участник, устройство, сборка, часы.
      final Map<String, Object?> info = kit.store.json(folder, kRecordingFile);
      expect(info['schema'], kRecordingSchema);
      expect(info['branch'], 'I');
      expect(info['app'], <String, Object?>{'version': 'test'});
      expect(info['device'], <String, Object?>{
        'node_id': kTestNode,
        'code': 'a91f3c',
      });
      final Map<String, Object?> participant =
          info['participant']! as Map<String, Object?>;
      expect(participant['code'], kTestCode);
      expect(participant['generated'], isTrue);
      expect(participant['generator'], kCodeGenerator);
      final Map<String, Object?> recording =
          info['recording']! as Map<String, Object?>;
      expect(recording['planned_s'], 2400);
      expect(recording['stopped_by'], isNull);
      expect(recording['finished'], isFalse);

      kit.session.dispose();
    });

    test('SNO-F-LIB-02: запись началась — полка под замком', () async {
      final SessionKit kit = SessionKit();
      int changes = 0;
      kit.session.addListener(() => changes++);
      expect(kit.session.locked, isFalse);

      await kit.session.start(code);

      expect(kit.session.locked, isTrue);
      expect(changes, 1);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: сброс к эталону перед записью попадает в '
        'журнал', () async {
      final SessionKit kit = SessionKit();
      kit.settings.values[SnoSettingsKeys.lastReset] =
          '2026-11-03T10:55:00.000Z';

      await kit.session.start(code);

      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      expect(kit.store.types(kit.folder), <String>[
        'recording.start',
        'state.reset',
      ]);
      expect(events.last['data'], <String, Object?>{
        'at': '2026-11-03T10:55:00.000Z',
      });
      expect(events.last['seq'], 2);
      kit.session.dispose();
    });

    test('SNO-F-LIB-02: выбранный до старта порядок полки записан', () async {
      final SessionKit kit = SessionKit();
      kit.settings.values[SettingsKeys.shelfSort] = 'recent';

      await kit.session.start(code);

      final Map<String, Object?> data =
          kit.store.events(kit.folder).first['data']! as Map<String, Object?>;
      expect(data['shelf_sort'], 'recent');
      expect(data['shelf_sort_forced'], isTrue);
      kit.session.dispose();
    });

    test('SNO-F-LIB-02: порядок «Как расставил» замком не меняется', () async {
      final SessionKit kit = SessionKit();
      kit.settings.values[SettingsKeys.shelfSort] = 'manual';

      await kit.session.start(code);

      final Map<String, Object?> data =
          kit.store.events(kit.folder).first['data']! as Map<String, Object?>;
      expect(data['shelf_sort'], 'manual');
      expect(data['shelf_sort_forced'], isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: вторая запись поверх идущей не начинается', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;

      expect(await kit.session.start(code), isFalse);
      await kit.settle();

      expect(kit.store.current, <String>{folder});
      expect(kit.store.events(folder), hasLength(1));
      kit.session.dispose();
    });

    test('SNO-F-REC-01: папка записи не завелась — записи нет', () async {
      final SessionKit kit = SessionKit();
      kit.store.failCreate = true;

      expect(await kit.session.start(code), isFalse);

      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.session.locked, isFalse);
      expect(kit.settings.values.containsKey(SnoSettingsKeys.session), isFalse);
      expect(kit.ticking, isFalse);
      expect(kit.status.screen, isEmpty);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: настройки не пишутся — записи нет', () async {
      final SessionKit kit = SessionKit();
      kit.settings.failWrites = true;

      expect(await kit.session.start(code), isFalse);

      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.ticking, isFalse);
      // Открытый было журнал закрыт.
      expect(kit.store.open, 0);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: две записи в одну минуту — две папки', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String first = kit.folder;
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();

      await kit.session.start(code);

      expect(kit.folder, '$first-2');
      expect(kit.store.finished, <String>{first});
      // Новая запись — номера событий с единицы.
      expect(kit.store.events(kit.folder).single['seq'], 1);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-02: журнал записи', () {
    test('SNO-ALG-REC-01: сердцебиение — раз в десять секунд', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);

      kit.run(35);
      await kit.settle();

      expect(kit.store.types(kit.folder), <String>[
        'recording.start',
        'session.heartbeat',
        'session.heartbeat',
        'session.heartbeat',
      ]);
      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      final List<Object?> times = <Object?>[
        for (final Map<String, Object?> event in events) event['t'],
      ];
      expect(times, <int>[0, 10000, 20000, 30000]);
      expect(kit.session.events, 4);
      kit.session.dispose();
    });

    test('SNO-F-REC-02: номера событий сквозные, время не убывает', () async {
      final SessionKit kit = SessionKit();
      kit.settings.values[SnoSettingsKeys.lastReset] =
          '2026-11-03T10:55:00.000Z';
      await kit.session.start(code);
      kit.run(12);
      kit.session.log(
        SnoEventType.heartbeat,
        data: const <String, Object?>{'by': 'тест'},
      );
      kit.session.appLeft('inactive');
      kit.time.pass(const Duration(seconds: 3));
      kit.session.appReturned();
      kit.run(9);
      await kit.session.stop(StopReason.experimenter);

      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      for (int i = 0; i < events.length; i++) {
        expect(events[i]['seq'], i + 1);
        if (i > 0) {
          expect(
            events[i]['t']! as int,
            greaterThanOrEqualTo(events[i - 1]['t']! as int),
          );
        }
      }
      expect(events.first['type'], 'recording.start');
      expect(events.last['type'], 'recording.stop');
      kit.session.dispose();
    });

    test('SNO-F-REC-02: в событии — экран, на котором участник', () async {
      final SessionKit kit = SessionKit();
      kit.session.context.screen = 'testing';
      await kit.session.start(code);
      kit.session.context.screen = 'reader';
      kit.run(10);
      await kit.settle();

      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      expect(events.first['screen'], 'testing');
      expect(events.last['screen'], 'reader');
      kit.session.dispose();
    });

    test('SNO-F-REC-02: на диск журнал уходит каждую секунду', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.log(SnoEventType.heartbeat);
      // Событие принято, но диск его ещё не видел.
      expect(kit.store.events(kit.folder), hasLength(1));

      kit.run(1);
      await kit.settle();

      expect(kit.store.events(kit.folder), hasLength(2));
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-01: сорок минут и остановка', () {
    test('SNO-F-REC-01: через 40:00 запись останавливается сама', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      int changes = 0;
      kit.session.addListener(() => changes++);

      kit.run(forty.inSeconds - 1);
      expect(kit.session.recording, isTrue);
      expect(kit.session.remainingMs, 1000);
      kit.run(1);
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.auto);
      expect(kit.session.state!.durationMs, forty.inMilliseconds);
      expect(kit.session.elapsedMs, forty.inMilliseconds);
      expect(changes, 1);
      // Счёт остановлен, экран снова гаснет сам.
      expect(kit.ticking, isFalse);
      expect(kit.status.screen, <bool>[true, false]);
      // Сессия не завершена: замок остаётся.
      expect(kit.session.locked, isTrue);

      final Map<String, Object?> last = kit.store.events(kit.folder).last;
      expect(last['type'], 'recording.stop');
      expect(last['t'], forty.inMilliseconds);
      expect(last['data'], <String, Object?>{
        'stopped_by': 'auto',
        'duration_ms': forty.inMilliseconds,
      });
      // 239 сердцебиений, старт и остановка.
      expect(kit.session.events, 241);
      expect(kit.session.state!.events, 241);

      final Map<String, Object?> recording =
          kit.store.json(kit.folder, kRecordingFile)['recording']!
              as Map<String, Object?>;
      expect(recording['stopped_by'], 'auto');
      expect(recording['duration_s'], 2400);
      expect(recording['events'], 241);
      expect(recording['finished'], isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: сорок минут — по настенным часам: сон устройства '
        'запись не растягивает', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(600);

      // Устройство уснуло на сорок одну минуту: монотонные часы стояли.
      kit.session.appLeft('inactive');
      kit.session.appLeft('paused');
      kit.time.sleep(const Duration(minutes: 41));
      kit.session.appReturned();
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.auto);
      // Запись длилась столько, сколько положено, а не до возвращения.
      expect(kit.session.state!.durationMs, forty.inMilliseconds);

      final List<String> types = kit.store.types(kit.folder);
      expect(types.sublist(types.length - 4), <String>[
        'app.background',
        'app.foreground',
        'clock.resync',
        'recording.stop',
      ]);
      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      final Map<String, Object?> left = events[events.length - 4];
      expect(left['data'], <String, Object?>{'state': 'inactive'});
      final Map<String, Object?> back = events[events.length - 3];
      expect(back['data'], <String, Object?>{
        'away_ms': 41 * 60 * 1000,
        'deepest': 'paused',
      });
      final Map<String, Object?> resync = events[events.length - 2];
      expect(resync['data'], <String, Object?>{
        'drift_ms': 41 * 60 * 1000,
        'applied': true,
      });
      final Map<String, Object?> stop = events.last;
      // t — монотонный: сон в него не вошёл; сдвиг применяет разбор.
      expect(stop['t'], 600000);
      expect(stop['data'], <String, Object?>{
        'stopped_by': 'auto',
        'duration_ms': forty.inMilliseconds,
        'late_ms': 11 * 60 * 1000,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-01: часы перевели назад — запись всё равно кончается '
        'через сорок минут', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(60);
      kit.time.wall = kit.time.wall.subtract(const Duration(hours: 2));

      kit.run(forty.inSeconds - 60);
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.auto);
      expect(kit.session.state!.durationMs, forty.inMilliseconds);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: экспериментатор останавливает раньше', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(23 * 60 + 10);

      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.experimenter);
      expect(kit.session.state!.durationMs, 1390000);
      expect(describeRecordingTime(kit.session.elapsedMs), '23:10');
      expect(kit.store.events(kit.folder).last['data'], <String, Object?>{
        'stopped_by': 'experimenter',
        'duration_ms': 1390000,
      });
      // После остановки время не идёт и события записи не пишутся.
      final int written = kit.store.events(kit.folder).length;
      kit.run(30);
      kit.session.log(SnoEventType.heartbeat);
      kit.session.appLeft('paused');
      kit.session.appReturned();
      await kit.settle();
      expect(kit.session.elapsedMs, 1390000);
      expect(kit.store.events(kit.folder), hasLength(written));
      kit.session.dispose();
    });

    test('SNO-F-REC-01: остановка дважды — одна', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(5);

      final Future<void> first = kit.session.stop(StopReason.experimenter);
      final Future<void> second = kit.session.stop(StopReason.auto);
      await first;
      await second;

      expect(
        kit.store
            .types(kit.folder)
            .where((String type) => type == 'recording.stop'),
        hasLength(1),
      );
      expect(kit.session.state!.stoppedBy, StopReason.experimenter);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: уход в фон и возврат — пара событий и сверка '
        'часов', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(5);

      kit.session.appLeft('inactive');
      kit.session.appLeft('hidden');
      kit.time.pass(const Duration(seconds: 4));
      // Вернулось не с самого дна: «скрыто» → «не в фокусе» → «на
      // экране».
      kit.session.appLeft('inactive');
      kit.session.appReturned();
      // Возвращение без ухода ничего не пишет.
      kit.session.appReturned();
      await kit.settle();

      expect(kit.session.recording, isTrue);
      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      expect(kit.store.types(kit.folder), <String>[
        'recording.start',
        'app.background',
        'app.foreground',
        'clock.resync',
      ]);
      expect(events[1]['t'], 5000);
      expect(events[1]['data'], <String, Object?>{'state': 'inactive'});
      expect(events[2]['t'], 9000);
      expect(events[2]['data'], <String, Object?>{
        'away_ms': 4000,
        'deepest': 'hidden',
      });
      // Часы шли: расхождения нет, якорь на месте.
      expect(events[3]['data'], <String, Object?>{
        'drift_ms': 0,
        'applied': false,
      });
      kit.session.dispose();
    });
  });

  group('SNO-F-CFG-05: завершение сессии', () {
    test('SNO-F-CFG-05: сессия завершена — замок снят, код забыт', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final String folder = kit.folder;
      kit.run(100);
      await kit.session.stop(StopReason.experimenter);
      int changes = 0;
      kit.session.addListener(() => changes++);

      await kit.session.finish();

      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.session.locked, isFalse);
      expect(kit.session.participant, isNull);
      expect(kit.session.state, isNull);
      expect(changes, 1);
      expect(kit.settings.values.containsKey(SnoSettingsKeys.session), isFalse);
      // Папка записи переехала к завершённым, журнал закрыт.
      expect(kit.store.current, isEmpty);
      expect(kit.store.finished, <String>{folder});
      expect(kit.store.open, 0);

      final Map<String, Object?> last = kit.store.events(folder).last;
      expect(last['type'], 'session.finish');
      // Случилось после остановки: в метрики чтения не входит.
      expect(last['phase'], 'post');
      final Map<String, Object?> recording =
          kit.store.json(folder, kRecordingFile)['recording']!
              as Map<String, Object?>;
      expect(recording['finished'], isTrue);
      expect(recording['stopped_by'], 'experimenter');
      expect(recording['events'], kit.store.events(folder).length);
      kit.session.dispose();
    });

    test('SNO-F-CFG-05: пока запись идёт, сессию не завершить', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);

      await kit.session.finish();

      expect(kit.session.recording, isTrue);
      expect(kit.store.finished, isEmpty);
      kit.session.dispose();
    });

    test('SNO-F-CFG-05: завершение дожидается остановки', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(5);

      final Future<void> stopping = kit.session.stop(StopReason.experimenter);
      final Future<void> finishing = kit.session.finish();
      await stopping;
      await finishing;

      // Отметка сессии не воскресла после завершения.
      expect(kit.settings.values.containsKey(SnoSettingsKeys.session), isFalse);
      expect(kit.session.phase, RecordingPhase.idle);
      kit.session.dispose();
    });

    test('SNO-F-CFG-05: следующий старт выдаёт новый код', () async {
      final SessionKit kit = SessionKit();
      final ParticipantCode first = await kit.session.proposeCode();
      expect(first.code, kTestCode);
      expect(first.generated, isTrue);
      // Код, который не подтвердили, выданным не считается.
      expect((await kit.session.proposeCode()).code, kTestCode);

      await kit.session.start(first);
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();

      // Тот же узел, тот же миг — а код другой: первый уже был.
      final ParticipantCode second = await kit.session.proposeCode();
      expect(second.code, '42213535');
      expect(second.attempt, 1);
      expect(
        decodeKnownCodes(kit.settings.values[SnoSettingsKeys.knownCodes]),
        <String>{first.base},
      );
      kit.session.dispose();
    });

    test('SNO-F-CFG-05: введённый код записан как введённый', () async {
      final SessionKit kit = SessionKit();
      expect(kit.session.enteredCode('6795-4333'), isNull);
      final ParticipantCode entered = kit.session.enteredCode('4221-3535')!;
      expect(entered.generated, isFalse);

      await kit.session.start(entered);

      final Map<String, Object?> participant =
          kit.store.json(kit.folder, kRecordingFile)['participant']!
              as Map<String, Object?>;
      expect(participant['code'], '42213535');
      expect(participant['generated'], isFalse);
      expect(participant['generator'], isNull);
      final Map<String, Object?> data =
          kit.store.events(kit.folder).first['data']! as Map<String, Object?>;
      expect(data['code_generated'], isFalse);
      // И этот код на устройстве больше не выдастся.
      expect(
        decodeKnownCodes(kit.settings.values[SnoSettingsKeys.knownCodes]),
        <String>{'4221353'},
      );
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-01: перезапуск приложения', () {
    test('SNO-F-REC-01: запись, которую застал перезапуск, закрыта как '
        'оборванная', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.run(25);
      await first.settle();
      // Приложение умерло посреди строки: в журнале обрывок.
      first.store.journals[folder]!.write('{"seq": 99, "t": 250');
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      first.time.pass(const Duration(minutes: 3));
      await second.session.restore();

      expect(second.session.phase, RecordingPhase.stopped);
      expect(second.session.locked, isTrue);
      expect(second.session.participant, code);
      final SessionState state = second.session.state!;
      expect(state.stoppedBy, StopReason.crash);
      // Длительность — по последнему целому событию: сердцебиению 20 с.
      expect(state.durationMs, 20000);
      expect(state.events, 4);
      // Счёт не заведён: запись не продолжается.
      expect(second.ticking, isFalse);

      final List<Map<String, Object?>> events = second.store.events(folder);
      expect(second.store.types(folder), <String>[
        'recording.start',
        'session.heartbeat',
        'session.heartbeat',
        'recording.stop',
      ]);
      expect(events.last['seq'], 4);
      expect(events.last['t'], 20000);
      expect(events.last['data'], <String, Object?>{
        'stopped_by': 'crash',
        'duration_ms': 20000,
        'late': true,
      });
      final Map<String, Object?> recording =
          second.store.json(folder, kRecordingFile)['recording']!
              as Map<String, Object?>;
      expect(recording['stopped_by'], 'crash');
      expect(recording['duration_s'], 20);

      // Завершается такая сессия как любая другая.
      await second.session.finish();
      expect(second.session.phase, RecordingPhase.idle);
      expect(second.store.finished, <String>{folder});
      expect(second.store.types(folder).last, 'session.finish');
      expect(second.store.events(folder).last['seq'], 5);
      second.session.dispose();
    });

    test('SNO-F-CFG-03: остановленная сессия переживает перезапуск', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.run(90);
      await first.session.stop(StopReason.experimenter);
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      int changes = 0;
      second.session.addListener(() => changes++);
      await second.session.restore();

      expect(changes, 1);
      expect(second.session.phase, RecordingPhase.stopped);
      expect(second.session.state!.stoppedBy, StopReason.experimenter);
      expect(second.session.elapsedMs, 90000);
      expect(second.session.participant, code);
      // Журнал при этом не тронут.
      expect(second.store.types(folder).last, 'recording.stop');

      await second.session.finish();
      final Map<String, Object?> last = second.store.events(folder).last;
      expect(last['type'], 'session.finish');
      expect(last['phase'], 'post');
      // Номер продолжает журнал, а не начинает его заново.
      expect(last['seq'], second.store.events(folder).length);
      second.session.dispose();
    });

    test('SNO-F-REC-01: сессии нет — поднимать нечего', () async {
      final SessionKit kit = SessionKit();
      int changes = 0;
      kit.session.addListener(() => changes++);

      await kit.session.restore();

      expect(kit.session.phase, RecordingPhase.idle);
      expect(changes, 0);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: испорченная отметка замка не оставляет', () async {
      final SessionKit kit = SessionKit();
      kit.settings.values[SnoSettingsKeys.session] = '{"phase": "recor';

      await kit.session.restore();

      expect(kit.session.phase, RecordingPhase.idle);
      expect(kit.session.locked, isFalse);
      expect(kit.settings.values.containsKey(SnoSettingsKeys.session), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: журнал оборванной записи пропал — сессия всё равно '
        'закрывается', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.session.dispose();
      first.store.journals.remove(folder);

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(second.session.phase, RecordingPhase.stopped);
      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(second.session.state!.durationMs, 0);
      await second.session.finish();
      expect(second.session.locked, isFalse);
      second.session.dispose();
    });
  });

  group('SNO-F-REC-01: готовность устройства', () {
    test('SNO-F-REC-01: мало заряда и места — предупреждение', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 24, free: 150 * 1024 * 1024),
      );
      final Readiness readiness = await kit.session.readiness();
      expect(readiness.batteryPercent, 24);
      expect(readiness.lowBattery, isTrue);
      expect(readiness.lowSpace, isTrue);
      // Место спрашивается там, где лежат записи.
      expect(kit.status.asked, '/records');
      kit.session.dispose();
    });

    test('SNO-F-REC-01: хватает — предупреждать не о чем', () async {
      final SessionKit kit = SessionKit(
        status: FakeDeviceStatus(battery: 30, free: 200 * 1024 * 1024),
      );
      final Readiness readiness = await kit.session.readiness();
      expect(readiness.lowBattery, isFalse);
      expect(readiness.lowSpace, isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-01: устройство молчит — это не «мало»', () async {
      final SessionKit kit = SessionKit();
      final Readiness readiness = await kit.session.readiness();
      expect(readiness.batteryPercent, isNull);
      expect(readiness.freeBytes, isNull);
      expect(readiness.lowBattery, isFalse);
      expect(readiness.lowSpace, isFalse);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-01: имена и запись состояния', () {
    test('SNO-F-REC-01: папка записи названа ветвью, кодом, устройством и '
        'временем', () {
      expect(
        recordingFolderName(
          branch: 'I',
          code: '67954332',
          device: 'a91f3c',
          startedAt: DateTime(2026, 11, 3, 14, 2, 59),
        ),
        'sno2026_I_67954332_a91f3c_20261103-1402',
      );
      expect(
        recordingFolderName(
          branch: 'II',
          code: '42213535',
          device: '0b7d2e',
          startedAt: DateTime(2027, 1, 9, 8, 5),
        ),
        'sno2026_II_42213535_0b7d2e_20270109-0805',
      );
    });

    test('SNO-F-REC-01: время записи словами', () {
      expect(describeRecordingTime(0), '00:00');
      expect(describeRecordingTime(999), '00:00');
      expect(describeRecordingTime(1390000), '23:10');
      expect(describeRecordingTime(2400000), '40:00');
      expect(describeRecordingTime(-5), '00:00');
    });

    test('SNO-F-REC-01: идентификатор записи растёт со временем', () {
      final Random random = Random(1);
      final String early = newRecordingId(
        DateTime.utc(2026, 11, 3, 11),
        random,
      );
      final String later = newRecordingId(
        DateTime.utc(2026, 11, 3, 11, 0, 1),
        random,
      );
      expect(early, hasLength(26));
      expect(early, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
      expect(later.compareTo(early), greaterThan(0));
      expect(early.substring(0, 10), isNot(later.substring(0, 10)));
    });

    test('SNO-F-REC-01: состояние сессии читается обратно', () {
      final SessionState state = SessionState(
        id: '01JBTEST',
        folder: 'sno2026_I_67954332_a91f3c_20261103-1402',
        participant: code,
        startedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
        plannedSeconds: 2400,
        phase: RecordingPhase.recording,
      );
      final SessionState back = SessionState.decode(state.encode())!;
      expect(back.id, state.id);
      expect(back.folder, state.folder);
      expect(back.participant, code);
      expect(back.startedAt.isAtSameMomentAs(state.startedAt), isTrue);
      expect(back.plannedSeconds, 2400);
      expect(back.phase, RecordingPhase.recording);
      expect(back.stoppedBy, isNull);
      expect(back.durationMs, isNull);

      final SessionState stopped = SessionState.decode(
        state
            .stopped(by: StopReason.auto, durationMs: 2400000, events: 241)
            .encode(),
      )!;
      expect(stopped.phase, RecordingPhase.stopped);
      expect(stopped.stoppedBy, StopReason.auto);
      expect(stopped.durationMs, 2400000);
      expect(stopped.events, 241);

      expect(SessionState.decode(null), isNull);
      expect(SessionState.decode(''), isNull);
      expect(SessionState.decode('[]'), isNull);
      expect(SessionState.decode('{"id": "x"}'), isNull);
    });
  });

  group('SNO-F-CFG-05: сброс к эталону и запись', () {
    late AppData data;

    setUp(() async => data = await openTestData());
    tearDown(() async => data.close());

    ReferenceKeeper keeper() {
      return ReferenceKeeper(data: data, storage: MemoryBookStorage());
    }

    test('SNO-ALG-CFG-03: сброс не трогает список выданных кодов', () async {
      await data.library.save(testBook(hash: 'hash-a'));
      await keeper().remember(const <ArchivePlacement>[
        ArchivePlacement(fingerprint: 'hash-a', title: 'Аа', category: null),
      ]);
      await data.settings.write(
        SnoSettingsKeys.knownCodes,
        encodeKnownCodes(<String>{'6795433'}),
      );
      await data.settings.write(SettingsKeys.theme, 'sepia');

      await keeper().reset();

      expect(await data.settings.read(SettingsKeys.theme), isNull);
      expect(await data.settings.read(SnoSettingsKeys.knownCodes), '6795433');
    });

    test('SNO-F-REC-01: отметки записи — не след читателя: снимок с '
        'эталоном совпадает', () async {
      await data.library.save(testBook(hash: 'hash-a'));
      final ReferenceState reference = (await keeper().remember(
        const <ArchivePlacement>[
          ArchivePlacement(fingerprint: 'hash-a', title: 'Аа', category: null),
        ],
      ))!;
      await data.settings.write(SnoSettingsKeys.knownCodes, '6795433');
      await data.settings.write(SnoSettingsKeys.session, '{}');

      final StateSnapshot snapshot = await keeper().snapshot();
      expect(snapshot.settings, isEmpty);
      expect(snapshot.matches(reference), isTrue);

      final Map<String, Object?> json = await keeper().recordingSnapshot();
      expect(json['schema'], kSnapshotSchema);
      expect(json['traces'], 0);
      expect(json['settings'], isEmpty);
      expect(json['books'], hasLength(1));
      final Map<String, Object?> known =
          json['reference']! as Map<String, Object?>;
      expect(known['matches'], isTrue);
      expect(json['last_reset'], isNull);
    });

    test('SNO-F-REC-01: снимок без эталона так и говорит', () async {
      final Map<String, Object?> json = await keeper().recordingSnapshot();
      expect(json['reference'], isNull);
      expect(json.containsKey('reference'), isTrue);
    });
  });
}
