import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/recording_fakes.dart';

/// SNO-F-EYE-01: сорок минут записи идут от начала изучения — после
/// калибровки взгляда, а не от старта записи. Запись — на памяти и
/// подменённом времени; айтрекера нет — его место держит
/// [RecordingSession.holdStudy] и [RecordingSession.beginStudy].
void main() {
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  Map<String, Object?> dataOf(Map<String, Object?> event) =>
      (event['data'] as Map<String, Object?>?) ?? const <String, Object?>{};

  Map<String, Object?> only(SessionKit kit, String type) {
    return kit.store
        .events(kit.folder)
        .singleWhere((Map<String, Object?> e) => e['type'] == type);
  }

  test('SNO-F-EYE-01: без айтрекера изучение начинается с записью — '
      'строки study.start нет', () async {
    final SessionKit kit = SessionKit();
    expect(await kit.session.start(code), isTrue);
    expect(kit.session.studyPending, isFalse);
    expect(kit.session.beginStudy(const <String, Object?>{}), isFalse);
    kit.run(60);
    await kit.settle();
    expect(kit.store.types(kit.folder), isNot(contains('study.start')));
    expect(kit.session.elapsedMs, 60000);
    await kit.session.stop(StopReason.experimenter);
    await kit.settle();
    final Map<String, Object?> stop = dataOf(only(kit, 'recording.stop'));
    expect(stop.containsKey('study_ms'), isFalse);
    final Map<String, Object?> recording =
        kit.store.json(kit.folder, kRecordingFile)['recording']!
            as Map<String, Object?>;
    expect(recording.containsKey('study_t'), isFalse);
    kit.session.dispose();
  });

  test('SNO-F-EYE-01: сорок минут — от study.start; запись кончается сама '
      'через сорок минут изучения', () async {
    final SessionKit kit = SessionKit();
    kit.session.holdStudy = true;
    expect(await kit.session.start(code), isTrue);
    expect(kit.session.studyPending, isTrue);
    // Калибровка — три минуты: изучение ещё не идёт.
    kit.run(180);
    expect(kit.session.elapsedMs, 0);
    expect(kit.session.remainingMs, kRecordingLength.inMilliseconds);
    expect(
      kit.session.beginStudy(const <String, Object?>{
        'gaze': true,
        'quality': 'ok',
      }),
      isTrue,
    );
    // Второй раз изучение не начинается.
    expect(
      kit.session.beginStudy(const <String, Object?>{'gaze': false}),
      isFalse,
    );
    expect(kit.session.studyPending, isFalse);
    await kit.settle();
    // Начало изучения помнится в отметке сессии.
    expect(
      SessionState.decode(kit.settings.values[SnoSettingsKeys.session])!
          .studyT,
      180000,
    );
    kit.run(40 * 60 - 1);
    expect(kit.session.recording, isTrue);
    expect(kit.session.elapsedMs, 40 * 60 * 1000 - 1000);
    kit.run(1);
    await kit.settle();
    await kit.settle();
    expect(kit.session.recording, isFalse);

    final Map<String, Object?> study = only(kit, 'study.start');
    expect(study['t'], 180000);
    expect(dataOf(study), <String, Object?>{'gaze': true, 'quality': 'ok'});
    final Map<String, Object?> stop = dataOf(only(kit, 'recording.stop'));
    expect(stop['stopped_by'], 'auto');
    expect(stop['duration_ms'], 180000 + 40 * 60 * 1000);
    expect(stop['study_ms'], 40 * 60 * 1000);
    expect(kit.session.elapsedMs, 40 * 60 * 1000);
    final Map<String, Object?> recording =
        kit.store.json(kit.folder, kRecordingFile)['recording']!
            as Map<String, Object?>;
    expect(recording['study_t'], 180000);
    expect(recording['duration_ms'], 180000 + 40 * 60 * 1000);
    kit.session.dispose();
  });

  test('SNO-F-EYE-01: остановлена во время калибровки — ничто не '
      'ограничивает, изучения ноль', () async {
    final SessionKit kit = SessionKit();
    kit.session.holdStudy = true;
    expect(await kit.session.start(code), isTrue);
    kit.run(90);
    await kit.session.stop(StopReason.experimenter);
    await kit.settle();
    final Map<String, Object?> stop = dataOf(only(kit, 'recording.stop'));
    expect(stop['duration_ms'], 90000);
    expect(stop['study_ms'], 0);
    expect(stop.containsKey('late_ms'), isFalse);
    expect(kit.session.elapsedMs, 0);
    final Map<String, Object?> recording =
        kit.store.json(kit.folder, kRecordingFile)['recording']!
            as Map<String, Object?>;
    expect(recording.containsKey('study_t'), isTrue);
    expect(recording['study_t'], isNull);
    kit.session.dispose();
  });

  test('SNO-F-EYE-01: калибровка ждёт дольше 15 минут — изучение '
      'начинается само, без взгляда', () async {
    final SessionKit kit = SessionKit();
    kit.session.holdStudy = true;
    expect(await kit.session.start(code), isTrue);
    kit.run(kStudyHoldLimit.inSeconds - 1);
    expect(kit.session.studyPending, isTrue);
    kit.run(1);
    expect(kit.session.studyPending, isFalse);
    await kit.settle();
    final Map<String, Object?> study = only(kit, 'study.start');
    expect(dataOf(study), <String, Object?>{'gaze': false, 'by': 'limit'});
    expect(study['t'], kStudyHoldLimit.inMilliseconds);
    kit.session.dispose();
  });

  test('SNO-F-EYE-01: оборванная запись — начало изучения из отметки, '
      'изучение после перезапуска считается от него', () async {
    final SessionKit kit = SessionKit();
    kit.session.holdStudy = true;
    expect(await kit.session.start(code), isTrue);
    kit.run(120);
    kit.session.beginStudy(const <String, Object?>{'gaze': true});
    kit.run(61);
    await kit.settle();
    final String folder = kit.folder;
    // «Перезапуск»: приложение умерло посреди изучения.
    final SessionKit again = SessionKit(
      settings: kit.settings,
      store: kit.store,
      time: kit.time,
    );
    await again.session.restore();
    final SessionState state = again.session.state!;
    expect(state.stoppedBy, StopReason.crash);
    expect(state.studyT, 120000);
    final int duration = state.durationMs!;
    expect(duration, greaterThanOrEqualTo(120000));
    expect(again.session.elapsedMs, duration - 120000);
    final Map<String, Object?> recording =
        kit.store.json(folder, kRecordingFile)['recording']!
            as Map<String, Object?>;
    expect(recording['study_t'], 120000);
    kit.session.dispose();
    again.session.dispose();
  });
}
