import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/layout_frames.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

/// SNO-F-RES-03: «Разбор записи» на архиве, который собрало само
/// приложение.
///
/// Разбор (`eye/sno_eye/report/`) проверяется pytest на синтетической
/// записи, собранной по формату на Python (`eye/tests/test_step34.py`).
/// Здесь — стык: журнал пишет настоящий `encodeEvent`, кадры раскладки —
/// настоящий `LayoutTracker` из настоящих зон, архив пакует настоящий
/// `packRecording`, а читает разбор, как у организатора. Расхождение
/// формата — поля журнала, зоны кадра, отпечаток книги в зоне и в
/// `book.open` — здесь видно сразу: поход на полку не найдётся или
/// взгляд ляжет не в ту категорию.
///
/// Разбор — на Python без зависимостей; в CI Python есть всегда, и там
/// его отсутствие — отказ теста, а не пропуск.
void main() {
  late Directory temp;
  late Directory records;

  const String name = 'sno2026_I_93461318_d10708_20261010-0900';
  const double width = 1280;
  const double height = 800;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-report-');
    records = Directory(p.join(temp.path, 'Записи'));
    await records.create(recursive: true);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Полка: две категории по три книги, как в `report_scenario.py`.
  LayoutSnapshot shelf() {
    final List<LayoutRegion> regions = <LayoutRegion>[
      const LayoutRegion(
        kind: LayoutKind.screen,
        id: 'shelf',
        rect: LayoutRect(0, 0, width, height),
        info: <String, Object?>{'offset': 0},
      ),
      const LayoutRegion(
        kind: LayoutKind.nav,
        rect: LayoutRect(0, 0, width, 56),
        z: 1,
      ),
    ];
    int z = 2;
    for (final (String title, double top) in <(String, double)>[
      ('Анатомия', 70),
      ('Физиология', 370),
    ]) {
      regions
        ..add(
          LayoutRegion(
            kind: LayoutKind.shelfCategory,
            id: title,
            rect: LayoutRect(16, top, 1248, 30),
            z: z++,
            info: const <String, Object?>{'part': 'header'},
          ),
        )
        ..add(
          LayoutRegion(
            kind: LayoutKind.shelfCategory,
            id: title,
            rect: LayoutRect(16, top + 30, 1248, 250),
            z: z++,
            info: const <String, Object?>{'part': 'area'},
          ),
        );
      for (int i = 0; i < 3; i++) {
        regions.add(
          LayoutRegion(
            kind: LayoutKind.shelfBook,
            id: '${title.substring(0, 1)}${i + 1}',
            rect: LayoutRect(40.0 + i * 400, top + 50, 300, 210),
            z: z++,
            info: <String, Object?>{'category': title},
          ),
        );
      }
    }
    return LayoutSnapshot(
      viewport: const LayoutViewport(width: width, height: height, dpr: 1.5),
      regions: regions,
    );
  }

  /// Запись: калибровка, полка (взгляд на книгу «Анатомии», между
  /// книгами «Физиологии», на книгу «Физиологии»), нажатие по ней —
  /// книга открыта — остановка.
  Future<File> pack() async {
    final Directory folder = Directory(p.join(records.path, name));
    final RecordingContext context = RecordingContext()..screen = 'testing';
    final DateTime wall = DateTime(2026, 10, 10, 9);
    final List<String> events = <String>[];
    void event(
      int t,
      SnoEventType type, {
      Map<String, Object?> data = const <String, Object?>{},
      int? input,
      bool post = false,
    }) {
      events.add(
        encodeEvent(
          seq: events.length + 1,
          t: t,
          wall: wall.add(Duration(milliseconds: t)),
          type: type,
          context: context,
          data: data,
          input: input,
          post: post,
        ),
      );
    }

    final List<Map<String, Object?>> inputs = <Map<String, Object?>>[];
    int tap(int t, double x, double y, String screen) {
      final int n = inputs.length + 1;
      inputs.add(<String, Object?>{
        'n': n,
        't': t,
        'dt': 80,
        'dev': 'mouse',
        'button': 'primary',
        'kind': 'tap',
        'x': x,
        'y': y,
        'x1': x,
        'y1': y,
        'path': 0,
        'vw': width,
        'vh': height,
        'screen': screen,
      });
      return n;
    }

    final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
    final LayoutTracker tracker = LayoutTracker(
      (Map<String, Object?> line) =>
          frames.add(<String, Object?>{...line, 'screen': context.screen}),
    );

    event(0, SnoEventType.recordingStart);
    event(1000, SnoEventType.studyStart, data: <String, Object?>{'gaze': true});
    final int toShelf = tap(2000, 160, 28, 'testing');
    context.screen = 'shelf';
    event(
      2000,
      SnoEventType.navScreen,
      data: <String, Object?>{'from': 'testing', 'to': 'shelf'},
      input: toShelf,
    );
    tracker.frame(shelf(), t: 2000, moving: false);
    final int open = tap(5600, 590, 525, 'shelf');
    context.screen = 'reader';
    event(
      5600,
      SnoEventType.navScreen,
      data: <String, Object?>{'from': 'shelf', 'to': 'reader'},
      input: open,
    );
    context.book = 'Ф2';
    event(
      6000,
      SnoEventType.bookOpen,
      data: <String, Object?>{'via': 'shelf', 'visit': 1},
      input: open,
    );
    event(
      8000,
      SnoEventType.recordingStop,
      data: <String, Object?>{'by': 'experimenter', 'study_ms': 7000},
    );
    event(9000, SnoEventType.sessionFinish, post: true);

    // Взгляд: куда смотрел участник, 30 кадров в секунду.
    const List<List<num>> looks = <List<num>>[
      <num>[1000, 2050, 160, 28],
      <num>[2300, 3300, 590, 225],
      <num>[3400, 4400, 390, 525],
      <num>[4500, 5650, 590, 525],
      <num>[5700, 8100, 640, 400],
    ];
    final StringBuffer gaze = StringBuffer();
    int n = 1;
    for (int t = 1000; t < 8000; t += 33) {
      final List<num> look = looks.lastWhere((List<num> l) => l[0] <= t);
      final double wobble = (n % 3 - 1) * 2.0;
      gaze
        ..write(
          jsonEncode(<String, Object?>{
            'n': n++,
            't': t,
            'x': look[2] + wobble,
            'y': look[3] - wobble,
            'ok': true,
            'conf': 1.0,
            'yaw': 1.0,
            'seg': 0,
          }),
        )
        ..write('\n');
    }

    String lines(List<Object?> rows) =>
        rows.map((Object? row) => '${jsonEncode(row)}\n').join();

    final Map<String, String> files = <String, String>{
      kEventsFile: events.map((String line) => '$line\n').join(),
      kInputFile: lines(inputs),
      kLayoutFile: lines(frames),
      kSnapshotStartFile: '{"schema": "sno2026-snapshot/1"}',
      kSnapshotEndFile: '{"schema": "sno2026-snapshot/1"}',
      'eye/gaze.jsonl': gaze.toString(),
      'eye/calibration.json': jsonEncode(<String, Object?>{
        'schema': 'sno2026-eyecal/2',
        'screen': <String, Object?>{
          'w': width,
          'h': height,
          'w_mm': 340,
          'h_mm': 212.5,
          'distance_mm': 600,
        },
      }),
      kRecordingFile: jsonEncode(<String, Object?>{
        'schema': 'sno2026-recording/1',
        'branch': 'I',
        'app': <String, Object?>{
          'version': '0.40.0-sno2026.I',
          'commit': '1435424501234567890123456789012345678901',
          'study_tag': 'sno2026-1',
          'built': '2026-10-10',
        },
        'device': <String, Object?>{
          'node_id': 'd10708aa',
          'code': 'd10708',
          'os': 'windows',
        },
        'participant': <String, Object?>{'code': '93461318'},
        'recording': <String, Object?>{
          'id': '01KB5Z3M4N7Q8R9S0T1V2W3X4Y',
          'planned_s': 2400,
          'duration_ms': 8000,
          'stopped_by': 'experimenter',
          'events': events.length,
          'finished': true,
          'study_t': 1000,
        },
        'input': <String, Object?>{'file': kInputFile, 'lines': inputs.length},
        'layout': <String, Object?>{
          'file': kLayoutFile,
          'lines': frames.length,
          'units': 'logical_px',
        },
        'eye_tracker': <String, Object?>{
          'present': true,
          'configured': true,
          'quality': 'ok',
          'calibration': <String, Object?>{
            'accepted': true,
            'accuracy_deg': 1.0,
            'precision_deg': 0.3,
            'latency_ms': 0,
          },
          'end_check': <String, Object?>{'accuracy_deg': 1.2},
          'file': 'eye/gaze.jsonl',
          'segments': 1,
        },
      }),
    };
    for (final MapEntry<String, String> file in files.entries) {
      final File target = File(p.join(folder.path, file.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(file.value, flush: true);
    }
    return packRecording(folder, now: () => DateTime(2026, 10, 10, 9, 20));
  }

  /// Гоняет «Разбор записи» над [archive]; `null` — Python на машине
  /// нет (только у разработчика; в CI — отказ).
  Future<Map<String, Object?>?> analyse(File archive) async {
    for (final String python in const <String>['python3', 'python']) {
      final ProcessResult result;
      try {
        result = await Process.run(
          python,
          <String>[
            '-m',
            'sno_eye',
            'report',
            archive.path,
            '--json',
            '--no-files',
          ],
          workingDirectory: 'eye',
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
      } on ProcessException {
        continue;
      }
      final String out = '${result.stdout}'.trim();
      if (!out.startsWith('[')) {
        if (result.exitCode == 9009 || out.isEmpty) {
          continue;
        }
        fail('разбор ответил не JSON: $out ${result.stderr}');
      }
      return (jsonDecode(out) as List<Object?>).single!
          as Map<String, Object?>;
    }
    if (Platform.environment['CI'] == 'true') {
      fail('в CI нет Python: «Разбор записи» не проверен');
    }
    return null;
  }

  test('SNO-F-RES-03: поход на полку из архива приложения', () async {
    final Map<String, Object?>? result = await analyse(await pack());
    if (result == null) {
      return;
    }
    expect(result['refused'], isNull, reason: '${result['refused']}');
    expect(result['gaze_used'], isTrue);
    expect(result['layout_known'], isTrue);
    final List<Object?> visits = result['visits']! as List<Object?>;
    expect(visits, hasLength(1));
    final Map<String, Object?> visit = visits.single! as Map<String, Object?>;
    // Отпечаток книги из `book.open` нашёлся в зонах полки: известна
    // её категория.
    expect(visit['book'], 'Ф2');
    expect(visit['via'], 'shelf');
    expect(visit['target'], 'Физиология');
    expect(visit['duration_ms'], 3600);
    // Взгляд лёг в зоны кадра, записанного `LayoutTracker`.
    expect(visit['path_strict'], <String>['Анатомия', 'Физиология']);
    expect(visit['books_strict'], 2);
    expect(visit['direct_strict'], isFalse);
    expect(
      (visit['first_target_ms_strict']! as num).toDouble(),
      closeTo(1400, 70),
    );
    final Map<String, Object?> quality =
        result['quality']! as Map<String, Object?>;
    // Неявные точки — нажатия мышью, на которые сослались события.
    expect((quality['implicit']! as Map<String, Object?>)['pairs'], 2);
    expect(quality['screen_known'], isTrue);
  });
}
