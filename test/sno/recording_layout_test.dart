import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/journal_check.dart';
import 'package:memoria/sno/recording/layout_frames.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';

import '../support/recording_fakes.dart';

/// Шаг 30, SNO-F-REC-03: поток кадров раскладки в записи сессии.
///
/// Правила сессии на памяти и подменённом времени: когда поток
/// существует, что ставит в кадр запись (номер, время, экран, книга,
/// страница), что о потоке сказано в сведениях записи и что остаётся
/// после отказа диска и обрыва. Сами кадры снимает слой записи —
/// `layout_layer_test`.
void main() {
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  SessionKit restarted(SessionKit first) {
    return SessionKit(
      settings: first.settings,
      store: first.store,
      time: first.time,
    );
  }

  Future<void> written(SessionKit kit) async {
    kit.session.tick();
    await kit.settle();
  }

  final LayoutSnapshot shot = LayoutSnapshot(
    viewport: const LayoutViewport(width: 1920, height: 1080, dpr: 1.25),
    regions: const <LayoutRegion>[
      LayoutRegion(kind: LayoutKind.page, rect: LayoutRect(0, 0, 1920, 1080)),
    ],
  );

  /// Слой записи снял кадр.
  void frame(SessionKit kit, {bool moving = false}) {
    kit.session.layout!.frame(
      shot,
      t: kit.session.layoutNow,
      moving: moving,
    );
  }

  Map<String, Object?> infoOf(SessionKit kit, String folder) {
    return kit.store.json(folder, kRecordingFile);
  }

  group('SNO-F-REC-03: поток есть только во время записи', () {
    test('SNO-F-REC-03: запись не идёт — сборщика нет и файла нет', () {
      final SessionKit kit = SessionKit();

      expect(kit.session.layout, isNull);
      expect(kit.store.layouts, isEmpty);
      expect(kit.store.openLayouts, 0);
      kit.session.dispose();
    });

    test('SNO-F-REC-03: старт заводит поток, остановка закрывает его; '
        'после остановки кадры не пишутся', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);

      expect(kit.session.layout, isNotNull);
      expect(kit.store.openLayouts, 1);
      final LayoutTracker tracker = kit.session.layout!;
      frame(kit);
      await written(kit);
      expect(kit.store.layoutLines(kit.folder), hasLength(1));

      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.layout, isNull);
      expect(kit.store.openLayouts, 0);
      // Слой, который ещё держит сборщик, после остановки не пишет.
      tracker.frame(shot, t: 99999, moving: false);
      expect(kit.store.layoutLines(kit.folder), hasLength(1));
      kit.session.dispose();
    });

    test('SNO-F-REC-03: в кадре — номер, время по часам записи, экран, '
        'книга, страница, полоса и режим, как у событий журнала', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.session.context.book = 'f00d';
      kit.session.place(page: 12, strip: 2, mode: 'third');
      kit.time.pass(const Duration(seconds: 7));
      frame(kit, moving: true);
      await written(kit);

      final Map<String, Object?> line = kit.store
          .layoutLines(kit.folder)
          .single;
      expect(line['n'], 1);
      expect(line['t'], 7000);
      expect(line['screen'], 'reader');
      expect(line['book'], 'f00d');
      expect(line['page'], 12);
      expect(line['strip'], 2);
      expect(line['mode'], 'third');
      expect(line['moving'], isTrue);
      expect(line['viewport'], containsPair('dpr', 1.25));
      expect(
        (line['regions']! as List<Object?>).single,
        containsPair('kind', 'page'),
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-03: остановка дописывает кадр, который не успел '
        'устояться, — раньше, чем поток закроется', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final LayoutTracker tracker = kit.session.layout!;
      tracker.beforeFinish = () => tracker.frame(shot, t: 1, moving: false);

      await kit.session.stop(StopReason.experimenter);

      expect(kit.store.layoutLines(kit.folder), hasLength(1));
      expect(kit.session.layouts, 1);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-03: поток в сведениях записи', () {
    test('SNO-F-REC-03: после остановки — сколько кадров и цел ли поток',
        () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      for (int i = 0; i < 4; i++) {
        frame(kit);
      }
      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.layouts, 4);
      expect(kit.session.layoutCheck!.intact, isTrue);
      expect(infoOf(kit, kit.folder)['layout'], <String, Object?>{
        'file': kLayoutFile,
        'lines': 4,
        'check': <String, Object?>{'lines': 4, 'gaps': 0, 'torn': false},
        'units': 'logical_px',
      });
      expect(kit.session.check!.intact, isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-03: кадры не легли на диск — поток неполон, и запись '
        'помечена', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      frame(kit);
      await written(kit);
      kit.store.failLayoutAppend = true;
      frame(kit);
      frame(kit);
      await kit.session.stop(StopReason.experimenter);

      final JournalCheck check = kit.session.layoutCheck!;
      expect(check.lines, 1);
      expect(check.gaps, 2);
      expect(kit.session.writeFailed, isTrue);
      expect(
        describeLayoutCheck(check),
        'Кадры раскладки неполны: 1 кадр, пропущено кадров 2',
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-03: поток кадров не открылся — запись идёт без него, '
        'отказ диска сказан', () async {
      final SessionKit kit = SessionKit();
      kit.store.failLayoutOpen = true;

      expect(await kit.session.start(code), isTrue);
      expect(kit.session.layout, isNull);
      expect(kit.session.writeFailed, isTrue);
      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.layouts, isNull);
      expect(kit.session.layoutCheck, isNull);
      expect(infoOf(kit, kit.folder).containsKey('layout'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-03: итог потока помнится между запусками', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      frame(first);
      frame(first);
      await first.session.stop(StopReason.experimenter);
      first.session.dispose();

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.layouts, 2);
      expect(second.session.layoutCheck!.intact, isTrue);
      await second.session.finish();
      expect(
        (second.store.json(folder, kRecordingFile)['layout']!
            as Map<String, Object?>)['lines'],
        2,
      );
      second.session.dispose();
    });

    test('SNO-F-REC-03: запись оборвалась — поток сверен таким, каким '
        'остался', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      frame(first);
      frame(first);
      await written(first);
      first.session.dispose();
      // Приложение умерло посреди строки кадра.
      first.store.layouts[folder]!.write('{"n":3,"t":900,"mov');

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(second.session.layouts, isNull);
      final JournalCheck check = second.session.layoutCheck!;
      expect(check.late, isTrue);
      expect(check.torn, isTrue);
      expect(check.lines, 2);
      expect(
        (infoOf(second, folder)['layout']! as Map<String, Object?>)['lines'],
        isNull,
      );
      second.session.dispose();
    });

    test('SNO-F-REC-03: запись прежней сборки, без потока кадров, — о '
        'потоке ничего не сказано', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.run(2);
      await written(first);
      first.session.dispose();
      first.store.layouts.remove(folder);

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.layoutCheck, isNull);
      expect(infoOf(second, folder).containsKey('layout'), isFalse);
      second.session.dispose();
    });
  });
}
