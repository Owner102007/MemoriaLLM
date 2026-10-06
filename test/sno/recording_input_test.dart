import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/input_tap.dart';
import 'package:memoria/sno/recording/journal_check.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';

import '../support/recording_fakes.dart';

/// Шаг 23, SNO-F-REC-11: поток сырого ввода в записи сессии.
///
/// Правила сессии на памяти и подменённом времени: когда поток
/// существует, что в него ложится, какое событие журнала на какую
/// строку ввода ссылается и что о потоке сказано в сведениях записи.
/// Сами события указателя проверяются на экране — `input_layer_test`.
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

  /// Участник коротко нажал в точку ([x], [y]): касание и отпускание
  /// через восемьдесят миллисекунд.
  void tap(SessionKit kit, int pointer, {double x = 200, double y = 400}) {
    final InputTracker input = kit.session.input!;
    input.down(
      pointer: pointer,
      t: kit.session.inputNow,
      x: x,
      y: y,
      dev: 'touch',
      vw: 411,
      vh: 914,
      screen: kit.session.context.screen,
    );
    kit.time.pass(const Duration(milliseconds: 80));
    input.up(pointer: pointer, t: kit.session.inputNow, x: x, y: y);
  }

  List<Map<String, Object?>> eventsOf(SessionKit kit, String type) {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(kit.folder))
        if (event['type'] == type) event,
    ];
  }

  Map<String, Object?> infoOf(SessionKit kit, String folder) {
    return kit.store.json(folder, kRecordingFile);
  }

  group('SNO-F-REC-11: поток есть только во время записи', () {
    test('SNO-F-REC-11: запись не идёт — сборщика нет, и ни одна строка '
        'не пишется никуда', () async {
      final SessionKit kit = SessionKit();

      expect(kit.session.input, isNull);
      kit.session.keyInput(1, 'PageDown', pressed: true);
      kit.session.keyInput(1, 'PageDown', pressed: false);
      expect(kit.store.inputs, isEmpty);
      expect(kit.store.openInputs, 0);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: старт заводит поток, остановка закрывает его; '
        'после остановки ввод не пишется', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);

      expect(kit.session.input, isNotNull);
      expect(kit.store.openInputs, 1);
      tap(kit, 1);
      await written(kit);
      expect(kit.store.inputLines(kit.folder), hasLength(1));

      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.input, isNull);
      expect(kit.store.openInputs, 0);
      kit.session.keyInput(1, 'PageDown', pressed: true);
      kit.session.keyInput(1, 'PageDown', pressed: false);
      expect(kit.store.inputLines(kit.folder), hasLength(1));
      kit.session.dispose();
    });

    test('SNO-F-REC-11: строка касания — время по часам записи, место, '
        'вид, размер окна и экран', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.time.pass(const Duration(seconds: 12));
      tap(kit, 1, x: 312.5, y: 640);
      await written(kit);

      expect(kit.store.inputLines(kit.folder).single, <String, Object?>{
        'n': 1,
        't': 12000,
        'dt': 80,
        'dev': 'touch',
        'kind': 'tap',
        'x': 312.5,
        'y': 640.0,
        'x1': 312.5,
        'y1': 640.0,
        'path': 0.0,
        'vw': 411.0,
        'vh': 914.0,
        'screen': 'reader',
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-11: запись остановили при опущенном пальце — касание '
        'в потоке есть, с пометкой cut', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.input!.down(
        pointer: 1,
        t: kit.session.inputNow,
        x: 20,
        y: 20,
        dev: 'touch',
        vw: 411,
        vh: 914,
        screen: 'shelf',
      );
      kit.time.pass(const Duration(seconds: 3));
      await kit.session.stop(StopReason.experimenter);

      final Map<String, Object?> line = kit.store
          .inputLines(kit.folder)
          .single;
      expect(line['kind'], 'cut');
      expect(line['dt'], 3000);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: клавиша, которую Flutter не видит, — кнопка '
        'громкости — ложится в поток именем', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.session.keyInput('down', 'VolumeDown', pressed: true);
      kit.time.pass(const Duration(milliseconds: 120));
      kit.session.keyInput('down', 'VolumeDown', pressed: true, repeat: true);
      kit.session.keyInput('down', 'VolumeDown', pressed: false);
      await written(kit);

      final Map<String, Object?> line = kit.store
          .inputLines(kit.folder)
          .single;
      expect(line['dev'], 'key');
      expect(line['key'], 'VolumeDown');
      expect(line['repeat'], 1);
      expect(line['dt'], 120);
      expect(line['screen'], 'reader');
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-11: сделало ли нажатие что-нибудь', () {
    test('SNO-F-REC-11: событие в ответ на нажатие несёт его номер, '
        'пустое нажатие осталось без ссылок', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.time.pass(const Duration(seconds: 5));

      // Нажатие по зоне листания: страница перевернулась.
      tap(kit, 1);
      kit.session.log(
        SnoEventType.pageShown,
        data: const <String, Object?>{'cause': 'tap_zone'},
      );
      kit.time.pass(const Duration(seconds: 2));
      // Нажатие в никуда: приложение не сделало ничего.
      tap(kit, 2, x: 5, y: 5);
      kit.time.pass(const Duration(seconds: 2));
      // Событие без нажатия — закладка времени, не ответ на ввод.
      kit.session.log(
        SnoEventType.pageShown,
        data: const <String, Object?>{'cause': 'mode'},
      );
      await written(kit);

      final List<Map<String, Object?>> shown = eventsOf(kit, 'page.shown');
      expect(shown[0]['input'], 1);
      expect(shown[1].containsKey('input'), isFalse);
      final Set<Object?> referenced = <Object?>{
        for (final Map<String, Object?> event in kit.store.events(kit.folder))
          if (event.containsKey('input')) event['input'],
      };
      final List<Object?> empty = <Object?>[
        for (final Map<String, Object?> line
            in kit.store.inputLines(kit.folder))
          if (!referenced.contains(line['n'])) line['n'],
      ];
      expect(empty, <int>[2]);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: событие, записанное, пока палец ещё на экране, '
        'ссылается на это касание', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final InputTracker input = kit.session.input!;
      input.down(
        pointer: 1,
        t: kit.session.inputNow,
        x: 100,
        y: 300,
        dev: 'touch',
        vw: 411,
        vh: 914,
        screen: 'shelf',
      );
      kit.time.pass(const Duration(seconds: 2));
      kit.session.log(
        SnoEventType.shelfScroll,
        data: const <String, Object?>{'offset': 240},
      );
      input.up(pointer: 1, t: kit.session.inputNow, x: 100, y: 60);
      await written(kit);

      expect(eventsOf(kit, 'shelf.scroll').single['input'], 1);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: событие позже окна связи ссылки не получает, а '
        'запрос поиска, который пишется с опозданием, — получает', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.keyInput(4, 'char', pressed: true);
      kit.session.keyInput(4, 'char', pressed: false);
      kit.time.pass(const Duration(milliseconds: 700));
      kit.session.log(
        SnoEventType.searchQuery,
        data: const <String, Object?>{'scope': 'shelf', 'text': 'анат'},
      );
      kit.session.log(
        SnoEventType.shelfScroll,
        data: const <String, Object?>{'offset': 0},
      );
      await written(kit);

      expect(eventsOf(kit, 'search.query').single['input'], 1);
      expect(
        eventsOf(kit, 'shelf.scroll').single.containsKey('input'),
        isFalse,
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-11: книга открывалась дольше окна связи — открытие '
        'всё равно ответ на нажатие по обложке', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      tap(kit, 1);
      // Экран чтения приехал сразу, а книга открылась через три секунды.
      kit.session.screen('reader');
      kit.time.pass(const Duration(seconds: 3));
      kit.session.bookOpened('hash-a', via: 'shelf');
      kit.session.bookClosed();
      kit.session.screen('shelf');
      // Вторая книга открыта без нажатия — ссылки у неё нет.
      kit.time.pass(const Duration(seconds: 3));
      kit.session.screen('reader');
      kit.session.bookOpened('hash-b', via: 'shelf');
      await written(kit);

      final List<Map<String, Object?>> opened = eventsOf(kit, 'book.open');
      expect(opened[0]['input'], 1);
      expect(opened[1].containsKey('input'), isFalse);
      expect(eventsOf(kit, 'nav.screen').first['input'], 1);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: то, что запись пишет сама, на ввод не ссылается', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final InputTracker input = kit.session.input!;
      // Палец лежит на экране десять секунд: сердцебиение и смена
      // состояния приложения пишутся при опущенном пальце.
      input.down(
        pointer: 1,
        t: kit.session.inputNow,
        x: 1,
        y: 1,
        dev: 'touch',
        vw: 411,
        vh: 914,
        screen: 'shelf',
      );
      kit.run(kHeartbeatTicks);
      kit.session.appState('inactive');
      kit.session.appState('resumed');
      await kit.session.stop(StopReason.experimenter);

      for (final Map<String, Object?> event in kit.store.events(kit.folder)) {
        expect(
          event.containsKey('input'),
          isFalse,
          reason: 'событие ${event['type']}',
        );
      }
      expect(eventsOf(kit, 'session.heartbeat'), isNotEmpty);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-11: поток в сведениях записи', () {
    test('SNO-F-REC-11: после остановки — сколько строк, цел ли поток и '
        'чего он не видит', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      for (int i = 1; i <= 5; i++) {
        tap(kit, i);
      }
      await kit.session.stop(StopReason.experimenter);

      expect(kit.session.inputs, 5);
      final JournalCheck check = kit.session.inputCheck!;
      expect(check.lines, 5);
      expect(check.intact, isTrue);
      expect(infoOf(kit, kit.folder)['input'], <String, Object?>{
        'file': kInputFile,
        'lines': 5,
        'check': <String, Object?>{'lines': 5, 'gaps': 0, 'torn': false},
        'blind': kInputBlind,
      });
      // Журнал событий проверен отдельно и по-прежнему цел.
      expect(kit.session.check!.intact, isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: экрана не касались — поток есть и пуст, и это '
        'сказано', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(3);
      await kit.session.stop(StopReason.auto);

      expect(kit.session.inputs, 0);
      expect(kit.session.inputCheck!.lines, 0);
      expect(kit.session.inputCheck!.intact, isTrue);
      expect(kit.store.inputs.containsKey(kit.folder), isTrue);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: строки ввода не легли на диск — поток неполон, и '
        'запись помечена', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      tap(kit, 1);
      await written(kit);
      kit.store.failInputAppend = true;
      tap(kit, 2);
      tap(kit, 3);
      await kit.session.stop(StopReason.experimenter);

      final JournalCheck check = kit.session.inputCheck!;
      expect(check.lines, 1);
      expect(check.gaps, 2);
      expect(check.intact, isFalse);
      expect(kit.session.writeFailed, isTrue);
      expect(describeInputCheck(check), 'Ввод неполон: 1 строка, '
          'пропущено строк 2');
      kit.session.dispose();
    });

    test('SNO-F-REC-11: поток ввода не открылся — запись идёт без него, '
        'журнал событий пишется, отказ диска сказан', () async {
      final SessionKit kit = SessionKit();
      kit.store.failInputOpen = true;

      expect(await kit.session.start(code), isTrue);
      expect(kit.session.input, isNull);
      expect(kit.session.writeFailed, isTrue);
      kit.session.log(
        SnoEventType.pageShown,
        data: const <String, Object?>{'cause': 'open'},
      );
      await kit.session.stop(StopReason.experimenter);

      expect(eventsOf(kit, 'page.shown'), hasLength(1));
      expect(kit.session.inputs, isNull);
      expect(kit.session.inputCheck, isNull);
      expect(infoOf(kit, kit.folder).containsKey('input'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-11: итог потока помнится между запусками', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      tap(first, 1);
      tap(first, 2);
      await first.session.stop(StopReason.experimenter);
      first.session.dispose();

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.phase, RecordingPhase.stopped);
      expect(second.session.inputs, 2);
      expect(second.session.inputCheck!.intact, isTrue);
      await second.session.finish();
      expect(
        (second.store.json(folder, kRecordingFile)['input']!
            as Map<String, Object?>)['lines'],
        2,
      );
      second.session.dispose();
    });

    test('SNO-F-REC-11: запись оборвалась — поток сверен таким, каким '
        'остался; сколько строк посчитано, неизвестно', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      tap(first, 1);
      tap(first, 2);
      await written(first);
      first.session.dispose();
      // Приложение умерло посреди записи строки ввода.
      first.store.inputs[folder]!.write('{"n":3,"t":900,"dev":"to');

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(second.session.inputs, isNull);
      final JournalCheck check = second.session.inputCheck!;
      expect(check.late, isTrue);
      expect(check.torn, isTrue);
      expect(check.lines, 2);
      expect(check.gaps, 0);
      final Map<String, Object?> input =
          infoOf(second, folder)['input']! as Map<String, Object?>;
      expect(input['lines'], isNull);
      expect(input['blind'], kInputBlind);
      second.session.dispose();
    });

    test('SNO-F-REC-11: запись прежней сборки, без потока ввода, — о '
        'потоке ничего не сказано', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      final String folder = first.folder;
      first.run(4);
      await written(first);
      first.session.dispose();
      // Прежняя сборка файла ввода не заводила.
      first.store.inputs.remove(folder);

      final SessionKit second = restarted(first);
      await second.session.restore();

      expect(second.session.inputCheck, isNull);
      expect(infoOf(second, folder).containsKey('input'), isFalse);
      second.session.dispose();
    });
  });
}
