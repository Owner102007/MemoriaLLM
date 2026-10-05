import 'dart:convert';
import 'dart:io';

import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/record_outlet.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:path/path.dart' as p;

/// Строки журнала записи: [count] событий подряд, по секунде на
/// событие.
String journalLines(int count) {
  final RecordingContext context = RecordingContext();
  final StringBuffer text = StringBuffer();
  for (int seq = 1; seq <= count; seq++) {
    text
      ..write(
        encodeEvent(
          seq: seq,
          t: seq * 1000,
          wall: DateTime(2026, 11, 3, 14, 2, 11).add(Duration(seconds: seq)),
          type: SnoEventType.pageShown,
          context: context,
          data: <String, Object?>{'page': seq},
        ),
      )
      ..write('\n');
  }
  return text.toString();
}

/// Сведения о записи — как их пишет сессия в `recording.json`.
///
/// [anchor] — время старта со смещением пояса: по нему записи стоят в
/// списке.
Map<String, Object?> recordingInfo({
  required String id,
  String code = '67954332',
  String anchor = '2026-11-03T14:02:11.482+03:00',
  String stoppedBy = 'experimenter',
  int durationMs = 480000,
  int events = 5,
}) {
  return <String, Object?>{
    'schema': 'sno2026-recording/1',
    'branch': 'I',
    'app': <String, Object?>{'version': '0.25.0-sno2026.I'},
    'device': <String, Object?>{'node_id': 'a91f3c0b', 'code': 'a91f3c'},
    'participant': <String, Object?>{
      'code': code,
      'generated': true,
      'generator': 'sno-code/1',
      'generated_at': '2026-11-03T11:02:00.000Z',
      'attempt': 0,
    },
    'recording': <String, Object?>{
      'id': id,
      'clock_anchor': anchor,
      'planned_s': 2400,
      'duration_s': durationMs ~/ 1000,
      'duration_ms': durationMs,
      'stopped_by': stoppedBy,
      'resyncs': 0,
      'events': events,
      'write_failed': false,
      'finished': true,
      'away': null,
      'in_background': false,
      'blocks': <Object?>[],
    },
  };
}

/// Заводит в [parent] папку записи [folder]: журнал на [events]
/// событий, снимок начала и сведения [about], если названы.
Future<Directory> makeRecordingFolder(
  Directory parent,
  String folder, {
  int events = 5,
  Map<String, Object?>? about,
}) async {
  final Directory directory = Directory(p.join(parent.path, folder));
  await directory.create(recursive: true);
  await File(p.join(directory.path, kEventsFile))
      .writeAsString(journalLines(events), flush: true);
  await File(p.join(directory.path, kSnapshotStartFile))
      .writeAsString('{"schema": "sno2026-snapshot/1"}', flush: true);
  if (about != null) {
    await File(p.join(directory.path, kRecordingFile))
        .writeAsString(jsonEncode(about), flush: true);
  }
  return directory;
}

/// Выход записей, которым распоряжается тест (SNO-F-REC-06).
class FakeRecordOutlet implements RecordOutlet {
  /// Создаёт выход: телефон — [shares], ПК — [saves].
  FakeRecordOutlet({this.shares = false, this.saves = false});

  @override
  bool shares;

  @override
  bool saves;

  /// Открывается ли окно «Поделиться».
  bool opens = true;

  /// Чем кончается открывшееся окно (SNO-F-REC-14): выбрано ли в нём
  /// приложение.
  ShareOutcome outcome = ShareOutcome.chosen;

  /// Есть ли у устройства общая папка для вторых копий
  /// (SNO-F-REC-13).
  bool backs = false;

  /// Ложится ли вторая копия в общую папку.
  bool backupWorks = true;

  /// Что клали в общую папку, по вызовам: путь, сумма, папка.
  final List<({String path, String sha256, String folder})> backups =
      <({String path, String sha256, String folder})>[];

  /// Что отдавали окну «Поделиться», по вызовам.
  final List<List<String>> shared = <List<String>>[];

  /// Что открывали в «Проводнике».
  final List<({String path, bool file})> revealed =
      <({String path, bool file})>[];

  /// Папка, которую «выберет» экспериментатор; `null` — отмена.
  String? folder;

  /// С какой папки диалог выбора начинали, по вызовам.
  final List<String?> initials = <String?>[];

  @override
  Future<ShareOutcome> share(List<String> paths) async {
    shared.add(List<String>.of(paths));
    return opens ? outcome : ShareOutcome.failed;
  }

  @override
  Future<bool> canBackup() async => backs;

  @override
  Future<bool> backup(
    String path, {
    required String sha256,
    required String folder,
  }) async {
    backups.add((path: path, sha256: sha256, folder: folder));
    return backupWorks;
  }

  @override
  Future<bool> reveal(String path, {required bool file}) async {
    revealed.add((path: path, file: file));
    return true;
  }

  @override
  Future<String?> pickFolder({String? initial}) async {
    initials.add(initial);
    return folder;
  }
}
