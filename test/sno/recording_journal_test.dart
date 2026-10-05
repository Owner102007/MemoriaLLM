import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/clock.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/journal.dart';
import 'package:memoria/sno/recording/store.dart';

/// SNO-ALG-REC-01: событие журнала, часы записи и запись на диск.

/// Файл журнала, который пишет не быстрее, чем разрешит тест.
class _SlowFile implements JournalFile {
  /// Что записано, пачками, в порядке записи.
  final List<String> chunks = <String>[];

  /// Ждущие записи: тест завершает их по одной.
  final List<Completer<void>> waiting = <Completer<void>>[];

  /// Отказывать ли в записи.
  bool failing = false;

  /// Закрыт ли файл.
  bool closed = false;

  @override
  Future<void> append(String text) async {
    final Completer<void> gate = Completer<void>();
    waiting.add(gate);
    await gate.future;
    if (failing) {
      throw StateError('диск полон');
    }
    chunks.add(text);
  }

  @override
  Future<void> close() async => closed = true;

  /// Даёт завершиться одной ждущей записи.
  Future<void> release() async {
    waiting.removeAt(0).complete();
    await Future<void>.delayed(Duration.zero);
  }
}

/// Строка журнала, разобранная из JSON.
Map<String, Object?> _decode(String line) {
  return jsonDecode(line) as Map<String, Object?>;
}

void main() {
  group('SNO-ALG-REC-01: строка события', () {
    final DateTime wall = DateTime(2026, 11, 3, 14, 2, 11, 482);

    test('SNO-ALG-REC-01: номер, время, вид и экран — в каждой строке', () {
      final String line = encodeEvent(
        seq: 812,
        t: 734512,
        wall: wall,
        type: SnoEventType.heartbeat,
        context: RecordingContext()..screen = 'reader',
      );
      final Map<String, Object?> event = _decode(line);
      expect(event['seq'], 812);
      expect(event['t'], 734512);
      expect(event['type'], 'session.heartbeat');
      expect(event['screen'], 'reader');
      expect(event['wall'], isoWithOffset(wall));
    });

    test('SNO-ALG-REC-01: чего нет, того в строке нет', () {
      final Map<String, Object?> bare = _decode(
        encodeEvent(
          seq: 1,
          t: 0,
          wall: wall,
          type: SnoEventType.recordingStart,
          context: RecordingContext(),
        ),
      );
      expect(bare.containsKey('book'), isFalse);
      expect(bare.containsKey('page'), isFalse);
      expect(bare.containsKey('strip'), isFalse);
      expect(bare.containsKey('mode'), isFalse);
      expect(bare.containsKey('data'), isFalse);
      expect(bare.containsKey('phase'), isFalse);

      final RecordingContext reading = RecordingContext()
        ..screen = 'reader'
        ..book = '8123456-3f9a'
        ..page = 57
        ..strip = 1
        ..mode = 'half';
      final Map<String, Object?> full = _decode(
        encodeEvent(
          seq: 2,
          t: 10,
          wall: wall,
          type: SnoEventType.sessionFinish,
          context: reading,
          data: const <String, Object?>{'from': 56},
          post: true,
        ),
      );
      expect(full['book'], '8123456-3f9a');
      expect(full['page'], 57);
      expect(full['strip'], 1);
      expect(full['mode'], 'half');
      expect(full['data'], <String, Object?>{'from': 56});
      expect(full['phase'], 'post');
    });

    test('SNO-ALG-REC-01: событие — одна строка, какой бы ни был текст', () {
      final String line = encodeEvent(
        seq: 3,
        t: 20,
        wall: wall,
        type: SnoEventType.stateReset,
        context: RecordingContext(),
        data: journalText('первая строка\nвторая «строка»\r\nтретья\t"'),
      );
      expect(line.contains('\n'), isFalse);
      expect(line.contains('\r'), isFalse);
      final Map<String, Object?> event = _decode(line);
      final Map<String, Object?> data = event['data']! as Map<String, Object?>;
      expect(data['text'], 'первая строка\nвторая «строка»\r\nтретья\t"');
    });

    test('SNO-ALG-REC-01: огромный текст обрезан и помечен', () {
      final String huge = 'я' * 20000;
      final Map<String, Object?> cut = journalText(huge);
      expect((cut['text']! as String).length, kJournalTextLimit);
      expect(cut['truncated'], isTrue);
      expect(cut['length'], 20000);

      final Map<String, Object?> whole = journalText('я' * kJournalTextLimit);
      expect((whole['text']! as String).length, kJournalTextLimit);
      expect(whole.containsKey('truncated'), isFalse);
    });

    test('SNO-ALG-REC-01: настенное время пишется со смещением пояса', () {
      final String text = isoWithOffset(wall);
      expect(
        text,
        matches(
          RegExp(
            r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{2}:\d{2}$',
          ),
        ),
      );
      expect(text.startsWith('2026-11-03T14:02:11.482'), isTrue);
      // Тот же миг: смещение не потеряно и не перевёрнуто.
      expect(DateTime.parse(text).isAtSameMomentAs(wall), isTrue);
      // Время в UTC пишется местным — с его смещением.
      final DateTime utc = DateTime.utc(2026, 11, 3, 11, 2, 11, 482);
      expect(DateTime.parse(isoWithOffset(utc)).isAtSameMomentAs(utc), isTrue);
    });

    test('SNO-ALG-REC-01: по строке узнаются номер и время события', () {
      final String line = encodeEvent(
        seq: 41,
        t: 20500,
        wall: wall,
        type: SnoEventType.heartbeat,
        context: RecordingContext(),
      );
      expect(eventMarks(line), (seq: 41, t: 20500));
      // Оборванная строка и чужой текст не читаются.
      expect(eventMarks(line.substring(0, line.length ~/ 2)), isNull);
      expect(eventMarks(''), isNull);
      expect(eventMarks('[1, 2]'), isNull);
      expect(eventMarks('{"seq": "41", "t": 1}'), isNull);
    });

    test('SNO-F-REC-02: виды событий названы по одному образцу и не '
        'повторяются', () {
      final Set<String> names = <String>{};
      for (final SnoEventType type in SnoEventType.values) {
        expect(type.wire, matches(RegExp(r'^[a-z]+\.[a-z]+$')));
        expect(names.add(type.wire), isTrue, reason: type.wire);
      }
      expect(names, contains('recording.start'));
      expect(names, contains('recording.stop'));
      expect(names, contains('app.background'));
      expect(names, contains('app.foreground'));
      expect(names, contains('clock.resync'));
      expect(names, contains('session.heartbeat'));
      expect(names, contains('state.reset'));
      expect(names, contains('session.finish'));
    });
  });

  group('SNO-ALG-REC-01: часы записи', () {
    late DateTime wall;
    late int monotonic;

    RecordingClock clock() {
      return RecordingClock(now: () => wall, elapsedMs: () => monotonic);
    }

    setUp(() {
      wall = DateTime(2026, 11, 3, 14, 2, 11, 482);
      // Монотонный счёт начинается не со старта записи.
      monotonic = 987654;
    });

    void pass(int milliseconds) {
      wall = wall.add(Duration(milliseconds: milliseconds));
      monotonic += milliseconds;
    }

    test('SNO-ALG-REC-01: t считается от старта записи', () {
      final RecordingClock started = clock();
      expect(started.t, 0);
      expect(started.anchor, wall);
      pass(1500);
      expect(started.t, 1500);
      expect(started.wallElapsedMs, 1500);
    });

    test('SNO-ALG-REC-01: настенное время события — якорь плюс t', () {
      final RecordingClock started = clock();
      final DateTime anchor = started.anchor;
      pass(734512);
      expect(
        started.wallAt(started.t),
        anchor.add(const Duration(milliseconds: 734512)),
      );
    });

    test('SNO-ALG-REC-01: малое расхождение якорь не переставляет', () {
      final RecordingClock started = clock();
      final DateTime anchor = started.anchor;
      pass(60000);
      // Настенные убежали на 300 мс — меньше порога.
      wall = wall.add(const Duration(milliseconds: 300));
      final ({int driftMs, bool applied}) check = started.resync();
      expect(check.driftMs, 300);
      expect(check.applied, isFalse);
      expect(started.resyncs, 0);
      expect(
        started.wallAt(started.t),
        anchor.add(const Duration(milliseconds: 60000)),
      );
    });

    test('SNO-ALG-REC-01: устройство спало — якорь новый, t прежний', () {
      final RecordingClock started = clock();
      pass(60000);
      // Пять минут сна: настенные идут, монотонные стоят.
      wall = wall.add(const Duration(minutes: 5));
      final ({int driftMs, bool applied}) check = started.resync();
      expect(check.driftMs, 300000);
      expect(check.applied, isTrue);
      expect(started.resyncs, 1);
      // t не правится: сдвиг применяет разбор.
      expect(started.t, 60000);
      // Следующие события получают настенное время от нового якоря.
      expect(started.wallAt(started.t), wall);
      pass(2000);
      expect(started.wallAt(started.t), wall);
      // Сорок минут считаются по настенным часам — сон в них входит.
      expect(started.wallElapsedMs, 60000 + 300000 + 2000);
    });

    test('SNO-ALG-REC-01: часы перевели назад — расхождение со знаком', () {
      final RecordingClock started = clock();
      pass(10000);
      wall = wall.subtract(const Duration(hours: 1));
      final ({int driftMs, bool applied}) check = started.resync();
      expect(check.driftMs, -3600000);
      expect(check.applied, isTrue);
      expect(started.t, 10000);
    });
  });

  group('SNO-ALG-REC-01: запись журнала на диск', () {
    test('SNO-ALG-REC-01: строки уходят на диск пачкой и по порядку', () async {
      final _SlowFile file = _SlowFile();
      final EventJournal journal = EventJournal(file)
        ..add('один')
        ..add('два');
      expect(journal.lines, 2);
      // До сброса на диске ничего нет: событие диска не ждёт.
      expect(file.waiting, isEmpty);

      final Future<void> flushed = journal.flush();
      await Future<void>.delayed(Duration.zero);
      expect(file.waiting, hasLength(1));
      // Пока первая пачка пишется, приходят новые строки.
      journal.add('три');
      final Future<void> again = journal.flush();
      await file.release();
      expect(file.chunks, <String>['один\nдва\n']);
      await file.release();
      await flushed;
      await again;
      expect(file.chunks, <String>['один\nдва\n', 'три\n']);
      expect(journal.failed, isFalse);
    });

    test('SNO-ALG-REC-01: сброс без новых строк диск не трогает', () async {
      final _SlowFile file = _SlowFile();
      final EventJournal journal = EventJournal(file);
      await journal.flush();
      expect(file.waiting, isEmpty);
      expect(file.chunks, isEmpty);
    });

    test('SNO-ALG-REC-01: отказ диска помечен, запись идёт дальше', () async {
      final _SlowFile file = _SlowFile()..failing = true;
      final EventJournal journal = EventJournal(file)..add('пропало');
      final Future<void> flushed = journal.flush();
      await Future<void>.delayed(Duration.zero);
      await file.release();
      await flushed;
      expect(journal.failed, isTrue);

      file.failing = false;
      journal.add('уцелело');
      final Future<void> next = journal.flush();
      await Future<void>.delayed(Duration.zero);
      await file.release();
      await next;
      expect(file.chunks, <String>['уцелело\n']);
    });

    test('SNO-ALG-REC-01: закрытие дописывает оставшееся', () async {
      final _SlowFile file = _SlowFile();
      final EventJournal journal = EventJournal(file)..add('последнее');
      final Future<void> closing = journal.close();
      await Future<void>.delayed(Duration.zero);
      await file.release();
      await closing;
      expect(file.chunks, <String>['последнее\n']);
      expect(file.closed, isTrue);
      // После закрытия строки не принимаются.
      journal.add('поздно');
      await journal.flush();
      expect(file.chunks, <String>['последнее\n']);
      expect(journal.lines, 1);
    });
  });
}
