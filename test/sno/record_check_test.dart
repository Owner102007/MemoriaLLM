import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/archive.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

/// SNO-F-RES-01 (часть): «Проверка записи» на архиве, который собрало
/// само приложение.
///
/// Разбор (`eye/sno_eye/record_check.py`) проверяется pytest на архивах,
/// собранных по формату на Python (`eye/tests/test_step33.py`). Здесь —
/// стык: архив пакует настоящий `packRecording`, а читает его разбор,
/// как у организатора. Расхождение формата — манифест, суммы, число
/// строк, сквозные номера — здесь видно сразу.
///
/// Разбор — на Python без зависимостей; в CI Python есть всегда, и там
/// его отсутствие — отказ теста, а не пропуск.
void main() {
  late Directory temp;
  late Directory records;

  const String name = 'sno2026_II_93461318_d10708_20261010-0002';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-check-');
    records = Directory(p.join(temp.path, 'Записи'));
    await records.create(recursive: true);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Журнал из [count] событий: старт, показы страниц, остановка с
  /// временем изучения и завершение сессии после неё.
  String journal(int count) {
    final RecordingContext context = RecordingContext();
    final DateTime wall = DateTime(2026, 10, 10, 0, 2, 11);
    final StringBuffer text = StringBuffer();
    for (int seq = 1; seq <= count; seq++) {
      final SnoEventType type = seq == 1
          ? SnoEventType.recordingStart
          : seq == count - 1
          ? SnoEventType.recordingStop
          : seq == count
          ? SnoEventType.sessionFinish
          : SnoEventType.pageShown;
      text
        ..write(
          encodeEvent(
            seq: seq,
            t: seq * 1000,
            wall: wall.add(Duration(seconds: seq)),
            type: type,
            context: context,
            data: type == SnoEventType.recordingStop
                ? const <String, Object?>{
                    'by': 'experimenter',
                    'study_ms': 300000,
                  }
                : const <String, Object?>{},
            post: type == SnoEventType.sessionFinish,
          ),
        )
        ..write('\n');
    }
    return text.toString();
  }

  /// Поток строк с полем `n` от единицы.
  String numbered(int count, Map<String, Object?> Function(int n) row) {
    final StringBuffer text = StringBuffer();
    for (int n = 1; n <= count; n++) {
      text
        ..write(jsonEncode(<String, Object?>{'n': n, ...row(n)}))
        ..write('\n');
    }
    return text.toString();
  }

  Map<String, Object?> info({String? studyTag = 'sno2026-1'}) {
    return <String, Object?>{
      'schema': 'sno2026-recording/1',
      'branch': 'II',
      'app': <String, Object?>{
        'version': '0.39.0-sno2026.II',
        'commit': '1435424501234567890123456789012345678901',
        'flags': <String>['запись', 'литература', 'галактика', 'палимпсест'],
        'study_tag': studyTag,
        'built': '2026-10-10',
      },
      'device': <String, Object?>{
        'node_id': 'd10708aa',
        'code': 'd10708',
        'os': 'windows',
      },
      'participant': <String, Object?>{'code': '93461318', 'generated': true},
      'recording': <String, Object?>{
        'id': '01KB5Z3M4N7Q8R9S0T1V2W3X4Y',
        'clock_anchor': '2026-10-10T00:02:11.482+03:00',
        'planned_s': 2400,
        'duration_s': 320,
        'duration_ms': 320000,
        'stopped_by': 'experimenter',
        'events': 12,
        'write_failed': false,
        'finished': true,
        'in_background': false,
        'study_t': 20000,
        'away': <String, Object?>{
          'count': 0,
          'total_ms': 0,
          'hidden_ms': 0,
          'longest_ms': 0,
        },
        'check': <String, Object?>{'lines': 12, 'gaps': 0, 'torn': false},
      },
      'input': <String, Object?>{
        'file': kInputFile,
        'lines': 30,
        'blind': <String>['soft_keyboard'],
      },
      'layout': <String, Object?>{
        'file': kLayoutFile,
        'lines': 8,
        'units': 'logical_px',
      },
      'clt': <String, Object?>{'final': 'complete', 'checks_flags': 0},
      'eye_tracker': <String, Object?>{
        'present': true,
        'configured': true,
        'quality': 'ok',
        'source': 'webcam',
        'calibration': <String, Object?>{
          'attempts': 1,
          'accepted': true,
          'accuracy_deg': 1.47,
        },
        'end_check': <String, Object?>{'done': true, 'accuracy_deg': 1.9},
        'file': 'eye/gaze.jsonl',
        'segments': 1,
      },
    };
  }

  Future<File> pack(Map<String, Object?> about) async {
    final Directory folder = Directory(p.join(records.path, name));
    final Map<String, String> files = <String, String>{
      kEventsFile: journal(12),
      kInputFile: numbered(30, (int n) => <String, Object?>{'t': n * 100}),
      kLayoutFile: numbered(8, (int n) => <String, Object?>{'t': n * 900}),
      kSnapshotStartFile: '{"schema": "sno2026-snapshot/1"}',
      kSnapshotEndFile: '{"schema": "sno2026-snapshot/1"}',
      'clt/scores.json': jsonEncode(<String, Object?>{
        'schema': 'sno2026-clt-scores/1',
        'checks': <String, Object?>{'flags': 0, 'verdict': 'ok'},
      }),
      'eye/gaze.jsonl': numbered(
        900,
        (int n) => <String, Object?>{
          't': 20000 + (n - 1) * 33,
          'x': 640.5,
          'y': 400.25,
          'ok': n % 10 != 0,
          'seg': 0,
        },
      ),
      kRecordingFile: jsonEncode(about),
    };
    for (final MapEntry<String, String> file in files.entries) {
      final File target = File(p.join(folder.path, file.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(file.value, flush: true);
    }
    // Полоса глаз и признаки кадров: двоичные, лежат без сжатия.
    await File(p.join(folder.path, 'eye', 'eyes.mp4'))
        .writeAsBytes(List<int>.generate(20000, (int i) => i % 251));
    await File(p.join(folder.path, 'eye', 'features.bin'))
        .writeAsBytes(List<int>.generate(8000, (int i) => (i * 7) % 256));
    return packRecording(folder, now: () => DateTime(2026, 10, 10, 0, 20));
  }

  /// Гоняет «Проверку записи» над [archive]; `null` — Python на машине
  /// нет (только у разработчика; в CI — отказ).
  Future<List<Map<String, Object?>>?> check(File archive) async {
    for (final String python in const <String>['python3', 'python']) {
      final ProcessResult result;
      try {
        result = await Process.run(
          python,
          <String>[
            '-m',
            'sno_eye',
            'check',
            archive.path,
            '--json',
            '--no-csv',
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
          // Заглушка на месте Python (Windows без него).
          continue;
        }
        fail('разбор ответил не JSON: $out ${result.stderr}');
      }
      return <Map<String, Object?>>[
        for (final Object? row in jsonDecode(out) as List<Object?>)
          row! as Map<String, Object?>,
      ];
    }
    if (Platform.environment['CI'] == 'true') {
      fail('в CI нет Python: «Проверка записи» не проверена');
    }
    return null;
  }

  test('SNO-F-RES-01: архив приложения — «годна», числа сходятся', () async {
    final File archive = await pack(info());

    final List<Map<String, Object?>>? reports = await check(archive);
    if (reports == null) {
      return;
    }
    final Map<String, Object?> report = reports.single;
    expect(report['problems'], isEmpty);
    expect(report['notes'], isEmpty);
    expect(report['verdict'], 'ok');
    expect(report['verdict_text'], 'годна');
    // Файлов в перечне — девять, все сошлись по суммам, байтам и строкам.
    expect(report['files'], <String, Object?>{'listed': 9, 'intact': 9});
    final Map<String, Object?> streams =
        report['streams']! as Map<String, Object?>;
    int lines(String file) =>
        (streams[file]! as Map<String, Object?>)['lines']! as int;
    expect(lines(kEventsFile), 12);
    expect(lines(kInputFile), 30);
    expect(lines(kLayoutFile), 8);
    expect(lines('eye/gaze.jsonl'), 900);
    expect(report['participant'], '93461318');
    expect(report['study_tag'], 'sno2026-1');
    expect(report['platform'], 'ПК');
    expect(report['study_s'], 300);
    expect(report['valid_share'], closeTo(0.9, 1e-9));
    expect(report['fps'], closeTo(1000 / 33, 0.01));
    expect(report['start_deg'], 1.47);
    expect(report['end_deg'], 1.9);
  });

  test('SNO-F-RES-01: проверочная сборка — «с оговорками»', () async {
    final File archive = await pack(info(studyTag: null));

    final List<Map<String, Object?>>? reports = await check(archive);
    if (reports == null) {
      return;
    }
    expect(reports.single['verdict'], 'warn');
    expect(
      reports.single['notes'],
      contains('записана на проверочной сборке, а не на сборке исследования'),
    );
  });

  test('SNO-F-RES-01: подменённый байт журнала — «не годна»', () async {
    final File archive = await pack(info());
    // Журнал сжат Deflate: байт посреди данных ломает и распаковку, и
    // контрольную сумму записи. Ищем его по оглавлению — в архиве
    // журнал второй, сразу за манифестом.
    final Uint8List bytes = await archive.readAsBytes();
    final int at = _dataOf(bytes, kEventsFile);
    bytes[at + 5] ^= 0xFF;
    await archive.writeAsBytes(bytes, flush: true);

    final List<Map<String, Object?>>? reports = await check(archive);
    if (reports == null) {
      return;
    }
    expect(reports.single['verdict'], 'bad');
    expect(reports.single['problems'], isNotEmpty);
  });
}

/// Где в архиве [bytes] начинаются данные записи [name]: за её
/// локальным заголовком (`PK\x03\x04`, 30 байт, имя и поле extra).
int _dataOf(Uint8List bytes, String name) {
  final List<int> wanted = utf8.encode(name);
  final ByteData view = ByteData.sublistView(bytes);
  for (int at = 0; at + 30 < bytes.length; at++) {
    if (view.getUint32(at, Endian.little) != 0x04034b50) {
      continue;
    }
    final int nameLength = view.getUint16(at + 26, Endian.little);
    final int extra = view.getUint16(at + 28, Endian.little);
    final List<int> found = bytes.sublist(at + 30, at + 30 + nameLength);
    if (_same(found, wanted)) {
      return at + 30 + nameLength + extra;
    }
  }
  throw StateError('в архиве нет $name');
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
