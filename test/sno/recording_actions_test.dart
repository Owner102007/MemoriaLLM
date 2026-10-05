import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/logged_settings.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/recording/summary.dart';
import 'package:memoria/sno/recording/thinning.dart';

import '../support/recording_fakes.dart';

/// Шаг 18: журнал действий участника, его отлучки и блоки тестирования.
///
/// Здесь — правила сессии на памяти и подменённом времени: что пишется
/// в журнал, с какими данными и что ложится в сведения записи. Провода
/// экранов проверяются отдельно, на самих экранах.
void main() {
  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  /// События журнала без смен состояния приложения и сердцебиений.
  List<Map<String, Object?>> eventsOf(SessionKit kit, String type) {
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(kit.folder))
        if (event['type'] == type) event,
    ];
  }

  Map<String, Object?> dataOf(Map<String, Object?> event) {
    return event['data']! as Map<String, Object?>;
  }

  Map<String, Object?> recordingInfo(SessionKit kit, String folder) {
    return kit.store.json(folder, kRecordingFile)['recording']!
        as Map<String, Object?>;
  }

  group('SNO-F-REC-02: действия участника в журнале', () {
    test('SNO-F-REC-02: смена экрана — событием, экран в нём уже новый', () async {
      final SessionKit kit = SessionKit();
      kit.session.screen('testing');
      await kit.session.start(code);
      kit.session.screen('shelf');
      // Тот же экран второй раз событием не становится.
      kit.session.screen('shelf');
      kit.session.screen('reader');
      await kit.settle();

      final List<Map<String, Object?>> moves = eventsOf(kit, 'nav.screen');
      expect(moves, hasLength(2));
      expect(dataOf(moves[0]), <String, Object?>{
        'from': 'testing',
        'to': 'shelf',
      });
      expect(moves[0]['screen'], 'shelf');
      expect(dataOf(moves[1]), <String, Object?>{
        'from': 'shelf',
        'to': 'reader',
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-02: книга, страница, полоса и режим стоят в каждом '
        'событии, пока книга открыта', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.session.bookOpened(
        'hash-a',
        via: 'shelf',
        data: const <String, Object?>{'title': 'Анатомия'},
      );
      kit.session.place(page: 12, strip: 2, mode: 'half');
      kit.session.log(
        SnoEventType.pageShown,
        data: const <String, Object?>{'cause': 'open'},
      );
      kit.time.pass(const Duration(seconds: 30));
      kit.session.place(page: 13, strip: 1, mode: 'half');
      kit.session.log(
        SnoEventType.pageShown,
        data: const <String, Object?>{'cause': 'tap_zone'},
      );
      kit.session.bookClosed();
      kit.session.screen('shelf');
      await kit.settle();

      final Map<String, Object?> opened = eventsOf(kit, 'book.open').single;
      expect(opened['book'], 'hash-a');
      expect(dataOf(opened), <String, Object?>{
        'via': 'shelf',
        'visit': 1,
        'title': 'Анатомия',
      });
      final List<Map<String, Object?>> shown = eventsOf(kit, 'page.shown');
      expect(shown[0]['book'], 'hash-a');
      expect(shown[0]['page'], 12);
      expect(shown[0]['strip'], 2);
      expect(shown[0]['mode'], 'half');
      expect(shown[1]['page'], 13);
      expect(shown[1]['strip'], 1);
      // Время на странице — разность времён показов.
      expect((shown[1]['t']! as int) - (shown[0]['t']! as int), 30000);

      final Map<String, Object?> closed = eventsOf(kit, 'book.close').single;
      // Закрытие ещё несёт книгу и место, на котором её закрыли.
      expect(closed['book'], 'hash-a');
      expect(closed['page'], 13);
      expect(dataOf(closed), <String, Object?>{'open_ms': 30000});
      // После закрытия книги в событиях её нет.
      final Map<String, Object?> back = eventsOf(kit, 'nav.screen').last;
      expect(back.containsKey('book'), isFalse);
      expect(back.containsKey('page'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-02: обращения к книге считаются за запись', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      for (final String book in <String>['a', 'b', 'a', 'a']) {
        kit.session.bookOpened(book, via: 'shelf_search');
        kit.session.bookClosed();
      }
      await kit.settle();

      expect(
        eventsOf(kit, 'book.open').map(
          (Map<String, Object?> event) => dataOf(event)['visit'],
        ),
        <int>[1, 1, 2, 3],
      );
      expect(eventsOf(kit, 'book.close'), hasLength(4));
      // Закрытие без открытой книги ничего не пишет.
      kit.session.bookClosed();
      await kit.settle();
      expect(eventsOf(kit, 'book.close'), hasLength(4));

      // Новая запись считает обращения заново.
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();
      await kit.session.start(code);
      kit.session.bookOpened('a', via: 'shelf');
      await kit.settle();
      expect(dataOf(eventsOf(kit, 'book.open').single)['visit'], 1);
      kit.session.dispose();
    });

    test('SNO-F-REC-02: вне записи место чтения помнится, а строк нет', () async {
      final SessionKit kit = SessionKit();
      kit.session.screen('reader');
      kit.session.bookOpened('hash-a', via: 'shelf');
      kit.session.place(page: 3, strip: 1, mode: 'full');
      kit.session.log(SnoEventType.pageShown);
      kit.session.bookClosed();
      expect(kit.session.startBlock(1), isFalse);
      await kit.settle();

      expect(kit.store.journals, isEmpty);
      expect(kit.session.context.screen, 'reader');
      expect(kit.session.context.book, isNull);
      kit.session.dispose();
    });

    test('SNO-F-REC-02: сценарий «открыл книгу, три страницы, выделил, '
        'цитата, поиск, закрыл» — виды по порядку, номера без пропусков', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      final RecordingSession log = kit.session;
      log.screen('reader');
      log.bookOpened('hash-a', via: 'shelf');
      for (int page = 1; page <= 3; page++) {
        log.place(page: page, strip: 1, mode: 'full');
        log.log(SnoEventType.pageShown);
        kit.time.pass(const Duration(seconds: 5));
      }
      log
        ..log(SnoEventType.selectEnd, data: journalText('остеология'))
        ..log(SnoEventType.selectionAction, data: journalText('остеология'))
        ..log(SnoEventType.quoteCreate, data: journalText('остеология'))
        ..log(SnoEventType.searchQuery, data: journalText('кость'))
        ..log(SnoEventType.searchResultOpen)
        ..log(SnoEventType.searchClose)
        ..bookClosed()
        ..screen('shelf');
      await kit.session.stop(StopReason.experimenter);

      final List<Map<String, Object?>> events = kit.store.events(kit.folder);
      expect(
        events.map((Map<String, Object?> event) => event['type']),
        <String>[
          'recording.start',
          'nav.screen',
          'book.open',
          'page.shown',
          'page.shown',
          'page.shown',
          'select.end',
          'selection.action',
          'quote.create',
          'search.query',
          'search.result.open',
          'search.close',
          'book.close',
          'nav.screen',
          'recording.stop',
        ],
      );
      for (int i = 0; i < events.length; i++) {
        expect(events[i]['seq'], i + 1);
        if (i > 0) {
          expect(
            events[i]['t']! as int,
            greaterThanOrEqualTo(events[i - 1]['t']! as int),
          );
        }
      }
      kit.session.dispose();
    });

    test('SNO-F-REC-02: восемь тысяч событий — журнал меньше трёх '
        'мегабайт', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.screen('reader');
      kit.session.bookOpened('f' * 64, via: 'shelf');
      for (int i = 0; i < 8000; i++) {
        kit.session.place(page: i % 700 + 1, strip: i % 3 + 1, mode: 'third');
        kit.session.log(
          SnoEventType.pageShown,
          data: <String, Object?>{
            'cause': 'tap_zone',
            'strips': 3,
            'of': 700,
            'from': <String, Object?>{'page': i % 700, 'strip': 1},
          },
        );
      }
      await kit.session.stop(StopReason.experimenter);

      int size = 0;
      for (final String line in kit.store.lines(kit.folder)) {
        size += line.length + 1;
      }
      expect(kit.store.lines(kit.folder).length, greaterThan(8000));
      expect(size, lessThan(3 * 1024 * 1024));
      kit.session.dispose();
    });
  });

  group('SNO-ALG-REC-01: прореживание непрерывных событий', () {
    // Время здесь — подменённое время widget-теста: `pump` ведёт его
    // вперёд и даёт сработать срокам.
    testWidgets('SNO-ALG-REC-01: не чаще пяти раз в секунду, последнее '
        'значение — обязательно', (WidgetTester tester) async {
      final List<int> written = <int>[];
      final Thinned<int> thinned = Thinned<int>(written.add);
      // Жест на секунду: значение меняется каждые десять миллисекунд.
      for (int i = 1; i <= 100; i++) {
        thinned.add(i);
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(seconds: 1));

      expect(written.first, 1);
      expect(written.last, 100);
      expect(written.length, lessThanOrEqualTo(6));
      // После тишины новое значение пишется сразу.
      thinned.add(500);
      expect(written.last, 500);
      await tester.pump(const Duration(seconds: 1));
      thinned.dispose();
    });

    testWidgets('SNO-ALG-REC-01: конец жеста пишет отложенное сразу', (
      WidgetTester tester,
    ) async {
      final List<int> written = <int>[];
      final Thinned<int> thinned = Thinned<int>(written.add);
      thinned
        ..add(1)
        ..add(2)
        ..add(3);
      expect(written, <int>[1]);
      thinned.flush();
      expect(written, <int>[1, 3]);
      // Отложенного больше нет: срок ничего не допишет.
      await tester.pump(const Duration(seconds: 1));
      expect(written, <int>[1, 3]);

      thinned
        ..add(4)
        ..add(5)
        ..dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(written, <int>[1, 3, 4]);
    });
  });

  group('SNO-F-REC-10: уход из приложения виден в записи', () {
    test('SNO-F-REC-10: каждая смена состояния — событием; отлучка, когда '
        'приложения не было видно, — `hidden`', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(5);

      kit.session.appState('inactive');
      kit.time.pass(const Duration(seconds: 1));
      kit.session.appState('hidden');
      kit.time.pass(const Duration(seconds: 7));
      kit.session.appState('inactive');
      kit.time.pass(const Duration(seconds: 2));
      kit.session.appState('resumed');
      await kit.settle();

      final List<Map<String, Object?>> states = eventsOf(kit, 'app.state');
      expect(states.map(dataOf), <Map<String, Object?>>[
        <String, Object?>{'from': 'resumed', 'to': 'inactive'},
        <String, Object?>{'from': 'inactive', 'to': 'hidden'},
        <String, Object?>{'from': 'hidden', 'to': 'inactive'},
        <String, Object?>{'from': 'inactive', 'to': 'resumed'},
      ]);
      // Миг, когда окно свернули, известен временем события.
      expect(states[1]['t'], 6000);
      expect(eventsOf(kit, 'app.background'), hasLength(1));
      final Map<String, Object?> back = eventsOf(kit, 'app.foreground').single;
      expect(dataOf(back), <String, Object?>{
        'away_ms': 10000,
        'deepest': 'hidden',
        'kind': 'hidden',
        'hidden_ms': 7000,
      });
      // То же состояние второй раз событием не становится.
      kit.session.appState('resumed');
      await kit.settle();
      expect(eventsOf(kit, 'app.state'), hasLength(4));
      kit.session.dispose();
    });

    test('SNO-F-REC-10: потеряло фокус, но осталось на виду — `unfocused`', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.appState('inactive');
      kit.time.pass(const Duration(seconds: 4));
      kit.session.appState('resumed');
      await kit.settle();

      expect(dataOf(eventsOf(kit, 'app.foreground').single), <String, Object?>{
        'away_ms': 4000,
        'deepest': 'inactive',
        'kind': 'unfocused',
        'hidden_ms': 0,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-10: экран погасили кнопкой — отлучка помечена', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.status.lit = false;
      kit.session.appState('inactive');
      kit.session.appState('paused');
      await kit.settle();
      kit.time.sleep(const Duration(seconds: 20));
      kit.session.appState('resumed');
      await kit.settle();

      final Map<String, Object?> back = dataOf(
        eventsOf(kit, 'app.foreground').single,
      );
      expect(back['reason'], 'screen_off');
      expect(back['kind'], 'hidden');

      // Экран горел — пометки нет.
      kit.status.lit = true;
      kit.session.appState('hidden');
      await kit.settle();
      kit.session.appState('resumed');
      await kit.settle();
      expect(
        dataOf(eventsOf(kit, 'app.foreground').last).containsKey('reason'),
        isFalse,
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-10: сердцебиение вне переднего плана несёт состояние', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(10);
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      kit.run(10);
      kit.session.appState('resumed');
      kit.run(10);
      await kit.settle();

      final List<Map<String, Object?>> beats = eventsOf(
        kit,
        'session.heartbeat',
      );
      expect(beats, hasLength(3));
      expect(beats[0].containsKey('data'), isFalse);
      expect(dataOf(beats[1]), <String, Object?>{'state': 'hidden'});
      expect(beats[2].containsKey('data'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: итог отлучек — в сведениях записи и строкой для '
        'экспериментатора', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.appState('inactive');
      kit.time.pass(const Duration(seconds: 3));
      kit.session.appState('resumed');
      kit.run(60);
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      kit.time.pass(const Duration(seconds: 9));
      kit.session.appState('resumed');
      kit.run(5);
      await kit.session.stop(StopReason.experimenter);

      final String folder = kit.folder;
      expect(recordingInfo(kit, folder)['away'], <String, Object?>{
        'count': 2,
        'total_ms': 12000,
        'hidden_ms': 9000,
        'longest_ms': 9000,
      });
      expect(recordingInfo(kit, folder)['in_background'], isFalse);
      expect(kit.session.away!.count, 2);
      expect(describeAway(kit.session.away), 'Уходил из приложения: 2 раза, 0:12');

      // Итог переживает перезапуск приложения до завершения сессии.
      final SessionKit second = SessionKit(
        settings: kit.settings,
        store: kit.store,
        time: kit.time,
      );
      await second.session.restore();
      expect(second.session.away!.totalMs, 12000);
      kit.session.dispose();
      second.session.dispose();
    });

    test('SNO-F-REC-10: участник не уходил — строки нет', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(30);
      await kit.session.stop(StopReason.experimenter);

      expect(recordingInfo(kit, kit.folder)['away'], <String, Object?>{
        'count': 0,
        'total_ms': 0,
        'hidden_ms': 0,
        'longest_ms': 0,
      });
      expect(describeAway(kit.session.away), isNull);
      expect(describeAway(null), isNull);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запись остановилась сама, пока участника не было — '
        'так и сказано', () async {
      final SessionKit kit = SessionKit(planned: const Duration(minutes: 1));
      await kit.session.start(code);
      kit.run(30);
      kit.session.appState('inactive');
      // Окно без фокуса на ПК живёт: счёт идёт, и время выходит.
      kit.run(40);
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      final Map<String, Object?> stop = eventsOf(kit, 'recording.stop').single;
      expect(dataOf(stop)['in_background'], isTrue);
      expect(recordingInfo(kit, kit.folder)['in_background'], isTrue);
      // Отлучка, на которой запись кончилась, вошла в итог.
      expect(kit.session.away!.count, 1);
      expect(kit.session.away!.totalMs, greaterThanOrEqualTo(30000));
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запись оборвалась в фоне — закрытая после сбоя '
        'запись это говорит', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(20);
      first.session.appState('inactive');
      first.session.appState('paused');
      await first.settle();
      final String folder = first.folder;
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(second.session.state!.stoppedBy, StopReason.crash);
      expect(second.session.state!.inBackground, isTrue);
      expect(
        dataOf(second.store.events(folder).last)['in_background'],
        isTrue,
      );
      expect(recordingInfo(second, folder)['in_background'], isTrue);
      // Отлучки оборванной записи читаются из журнала: итога нет.
      expect(recordingInfo(second, folder)['away'], isNull);
      second.session.dispose();
    });

    test('SNO-F-REC-10: оборвалась на переднем плане — пометки нет', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(5);
      first.session.appState('inactive');
      first.session.appState('resumed');
      first.run(15);
      await first.settle();
      final String folder = first.folder;
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(second.session.state!.inBackground, isFalse);
      expect(
        dataOf(second.store.events(folder).last).containsKey('in_background'),
        isFalse,
      );
      second.session.dispose();
    });

    test('SNO-F-REC-10: слова об отлучках согласованы с числом', () {
      String line(int count) {
        return describeAway(AwaySummary(count: count, totalMs: 65000))!;
      }

      expect(line(1), 'Уходил из приложения: 1 раз, 1:05');
      expect(line(2), 'Уходил из приложения: 2 раза, 1:05');
      expect(line(4), 'Уходил из приложения: 4 раза, 1:05');
      expect(line(5), 'Уходил из приложения: 5 раз, 1:05');
      expect(line(11), 'Уходил из приложения: 11 раз, 1:05');
      expect(line(12), 'Уходил из приложения: 12 раз, 1:05');
      expect(line(21), 'Уходил из приложения: 21 раз, 1:05');
      expect(line(22), 'Уходил из приложения: 22 раза, 1:05');
    });
  });

  group('SNO-F-CFG-03: блоки тестирования', () {
    test('SNO-F-CFG-03: «начать» и «закончить» — в журнале, блок один', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(10);
      expect(kit.session.nextBlock, 1);
      expect(kit.session.block, isNull);

      expect(kit.session.startBlock(1), isTrue);
      expect(kit.session.block, 1);
      // Пока блок открыт, второй не начинается.
      expect(kit.session.startBlock(2), isFalse);
      kit.run(100);
      expect(kit.session.blockElapsedMs, 100000);
      expect(kit.session.endBlock(), isTrue);
      expect(kit.session.block, isNull);
      // Заканчивать больше нечего.
      expect(kit.session.endBlock(), isFalse);
      expect(kit.session.nextBlock, 2);

      expect(kit.session.startBlock(2), isTrue);
      kit.run(50);
      await kit.session.stop(StopReason.experimenter);

      expect(eventsOf(kit, 'block.start').map(dataOf), <Map<String, Object?>>[
        <String, Object?>{'n': 1},
        <String, Object?>{'n': 2},
      ]);
      expect(eventsOf(kit, 'block.end').map(dataOf), <Map<String, Object?>>[
        <String, Object?>{'n': 1, 'duration_ms': 100000, 'by': 'experimenter'},
        // Открытый блок закрыла остановка записи.
        <String, Object?>{'n': 2, 'duration_ms': 50000, 'by': 'stop'},
      ]);
      // Конец блока — раньше остановки записи.
      final List<String> types = kit.store.types(kit.folder);
      expect(types.sublist(types.length - 2), <String>[
        'block.end',
        'recording.stop',
      ]);
      expect(recordingInfo(kit, kit.folder)['blocks'], <Object?>[
        <String, Object?>{
          'n': 1,
          'start_ms': 10000,
          'duration_ms': 100000,
          'closed_by': 'experimenter',
        },
        <String, Object?>{
          'n': 2,
          'start_ms': 110000,
          'duration_ms': 50000,
          'closed_by': 'stop',
        },
      ]);
      expect(describeBlocks(kit.session.blocks), 'Блоки: 1 — 1:40 · 2 — 0:50');
      kit.session.dispose();
    });

    test('SNO-F-CFG-03: блоков не отмечали — строки нет; после остановки '
        'блок не начать', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(10);
      await kit.session.stop(StopReason.experimenter);

      expect(describeBlocks(kit.session.blocks), isNull);
      expect(recordingInfo(kit, kit.folder)['blocks'], isEmpty);
      expect(kit.session.startBlock(1), isFalse);
      expect(kit.session.startBlock(0), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-CFG-03: блоки остановленной сессии переживают перезапуск', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.session.startBlock(3);
      first.run(75);
      first.session.endBlock();
      await first.session.stop(StopReason.experimenter);
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(describeBlocks(second.session.blocks), 'Блоки: 3 — 1:15');
      second.session.dispose();
    });
  });

  group('SNO-F-REC-02: настройки в журнале', () {
    test('SNO-F-REC-02: запись в настройки — событием, длинное значение '
        'обрезано', () async {
      final MemorySettings inner = MemorySettings();
      final ListActionLog log = ListActionLog();
      final LoggedSettings settings = LoggedSettings(inner: inner, log: log);

      await settings.write('reader.tap_zone', '0.25');
      await settings.write('reader.keys', 'k' * 500);
      await settings.remove('reader.tap_zone');

      expect(inner.values.keys, <String>['reader.keys']);
      expect(await settings.read('reader.keys'), hasLength(500));
      final List<Map<String, Object?>> changes = log.dataOf(
        SnoEventType.settingsChange,
      );
      expect(changes[0], <String, Object?>{
        'key': 'reader.tap_zone',
        'value': '0.25',
      });
      expect(changes[1]['key'], 'reader.keys');
      expect(changes[1]['value'], hasLength(kSettingValueLimit));
      expect(changes[1]['truncated'], isTrue);
      expect(changes[2], <String, Object?>{
        'key': 'reader.tap_zone',
        'removed': true,
      });
    });

    test('SNO-F-REC-02: записи нет — настройка пишется, события нет', () async {
      final MemorySettings inner = MemorySettings();
      final ListActionLog log = ListActionLog(recording: false);
      final LoggedSettings settings = LoggedSettings(inner: inner, log: log);

      await settings.write('ui.theme', 'sepia');

      expect(inner.values['ui.theme'], 'sepia');
      expect(log.events, isEmpty);
    });

    test('SNO-F-REC-02: настройка не записалась — события нет', () async {
      final MemorySettings inner = MemorySettings()..failWrites = true;
      final ListActionLog log = ListActionLog();
      final LoggedSettings settings = LoggedSettings(inner: inner, log: log);

      await expectLater(settings.write('ui.theme', 'sepia'), throwsStateError);
      expect(log.events, isEmpty);
    });
  });
}
