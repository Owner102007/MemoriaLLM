import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/logged_settings.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/sno/recording/summary.dart';
import 'package:memoria/sno/recording/thinning.dart';
import 'package:memoria/sno/settings_keys.dart';

import '../support/recording_fakes.dart';

/// Шаг 18: журнал действий участника и его отлучки.
///
/// С шага 25 блоков тестирования нет (SNO-F-REC-15): запись идёт в один
/// этап, и о блоках здесь проверяется только то, что записи прежних
/// сборок читаются как раньше. Открытую книгу закрывает сама остановка
/// записи (SNO-F-REC-16).
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

  /// Даёт журналу лечь на диск: его сбрасывает секунда записи.
  Future<void> written(SessionKit kit) async {
    kit.session.tick();
    await kit.settle();
  }

  Map<String, Object?> recordingInfo(SessionKit kit, String folder) {
    return kit.store.json(folder, kRecordingFile)['recording']!
        as Map<String, Object?>;
  }

  group('SNO-F-REC-02: действия участника в журнале', () {
    test(
      'SNO-F-REC-02: смена экрана — событием, экран в нём уже новый',
      () async {
        final SessionKit kit = SessionKit();
        kit.session.screen('testing');
        await kit.session.start(code);
        kit.session.screen('shelf');
        // Тот же экран второй раз событием не становится.
        kit.session.screen('shelf');
        kit.session.screen('reader');
        await written(kit);

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
      },
    );

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
      await written(kit);

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
      await written(kit);

      expect(
        eventsOf(
          kit,
          'book.open',
        ).map((Map<String, Object?> event) => dataOf(event)['visit']),
        <int>[1, 1, 2, 3],
      );
      expect(eventsOf(kit, 'book.close'), hasLength(4));
      // Закрытие без открытой книги ничего не пишет.
      kit.session.bookClosed();
      await written(kit);
      expect(eventsOf(kit, 'book.close'), hasLength(4));

      // Новая запись считает обращения заново.
      await kit.session.stop(StopReason.experimenter);
      await kit.session.finish();
      await kit.session.start(code);
      kit.session.bookOpened('a', via: 'shelf');
      await written(kit);
      expect(dataOf(eventsOf(kit, 'book.open').single)['visit'], 1);
      kit.session.dispose();
    });

    test(
      'SNO-F-REC-02: вне записи место чтения помнится, а строк нет',
      () async {
        final SessionKit kit = SessionKit();
        kit.session.screen('reader');
        kit.session.bookOpened('hash-a', via: 'shelf');
        kit.session.place(page: 3, strip: 1, mode: 'full');
        kit.session.log(SnoEventType.pageShown);
        kit.session.bookClosed();
        await written(kit);

        expect(kit.store.journals, isEmpty);
        expect(kit.session.context.screen, 'reader');
        expect(kit.session.context.book, isNull);
        kit.session.dispose();
      },
    );

    test(
      'SNO-F-REC-02: сценарий «открыл книгу, три страницы, выделил, '
      'цитата, поиск, закрыл» — виды по порядку, номера без пропусков',
      () async {
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
      },
    );

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
      // Экран закрыт: запоздавшее значение не пишется и срока не заводит.
      thinned.add(6);
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

    test(
      'SNO-F-REC-10: потеряло фокус, но осталось на виду — `unfocused`',
      () async {
        final SessionKit kit = SessionKit();
        await kit.session.start(code);
        kit.session.appState('inactive');
        kit.time.pass(const Duration(seconds: 4));
        kit.session.appState('resumed');
        await kit.settle();

        expect(
          dataOf(eventsOf(kit, 'app.foreground').single),
          <String, Object?>{
            'away_ms': 4000,
            'deepest': 'inactive',
            'kind': 'unfocused',
            'hidden_ms': 0,
          },
        );
        kit.session.dispose();
      },
    );

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

    test(
      'SNO-F-REC-10: сердцебиение вне переднего плана несёт состояние',
      () async {
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
      },
    );

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
      expect(
        describeAway(kit.session.away),
        'Уходил из приложения: 2 раза, 0:12',
      );

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
      // Отлучка, на которой запись кончилась, вошла в итог — до конца
      // записи, не дальше.
      expect(kit.session.away!.count, 1);
      expect(kit.session.away!.totalMs, 30000);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: время вышло во сне устройства — запись кончилась '
        'в отсутствие участника, отлучка сочтена до её конца', () async {
      final SessionKit kit = SessionKit(planned: const Duration(minutes: 10));
      await kit.session.start(code);
      kit.run(300);
      kit.session.appState('inactive');
      kit.session.appState('paused');
      // Телефон спал четверть часа: счёт секунд стоял, и о конце записи
      // приложение узнаёт только по возвращении.
      kit.time.sleep(const Duration(minutes: 15));
      kit.session.appState('resumed');
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      final Map<String, Object?> stop = dataOf(
        eventsOf(kit, 'recording.stop').single,
      );
      expect(stop['stopped_by'], 'auto');
      expect(stop['in_background'], isTrue);
      expect(stop['late_ms'], 10 * 60 * 1000);
      // Возвращение записано как было: отлучка длилась четверть часа.
      expect(
        dataOf(eventsOf(kit, 'app.foreground').single)['away_ms'],
        15 * 60 * 1000,
      );
      // А в итог записи она входит только до её конца: с пятой минуты
      // по десятую.
      final Map<String, Object?> info = recordingInfo(kit, kit.folder);
      expect(info['in_background'], isTrue);
      expect(info['away'], <String, Object?>{
        'count': 1,
        'total_ms': 5 * 60 * 1000,
        'hidden_ms': 5 * 60 * 1000,
        'longest_ms': 5 * 60 * 1000,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-10: время вышло во сне, а узнал об этом счёт секунд — '
        'отлучка всё равно сочтена до конца записи', () async {
      final SessionKit kit = SessionKit(planned: const Duration(minutes: 10));
      await kit.session.start(code);
      kit.run(300);
      kit.session.appState('inactive');
      kit.session.appState('paused');
      kit.time.sleep(const Duration(minutes: 15));
      // Устройство проснулось, приложение ещё в фоне: тикнул счёт.
      kit.session.tick();
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      final Map<String, Object?> stop = dataOf(
        eventsOf(kit, 'recording.stop').single,
      );
      expect(stop['in_background'], isTrue);
      expect(stop['late_ms'], 10 * 60 * 1000);
      expect(recordingInfo(kit, kit.folder)['away'], <String, Object?>{
        'count': 1,
        'total_ms': 5 * 60 * 1000,
        'hidden_ms': 5 * 60 * 1000,
        'longest_ms': 5 * 60 * 1000,
      });
      // Возвращение после остановки второй отлучкой не становится.
      kit.session.appState('resumed');
      await kit.settle();
      expect(kit.session.away!.count, 1);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: устройство засыпало дважды за одну отлучку — в '
        'журнале оба сдвига часов', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(30);
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      kit.session.appState('paused');
      kit.time.sleep(const Duration(minutes: 5));
      // Проснулось до экрана блокировки — и уснуло снова.
      kit.session.appState('hidden');
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      kit.session.appState('paused');
      kit.time.sleep(const Duration(minutes: 10));
      kit.session.appState('hidden');
      kit.session.appState('inactive');
      kit.session.appState('resumed');
      await kit.settle();

      expect(eventsOf(kit, 'clock.resync').map(dataOf), <Map<String, Object?>>[
        <String, Object?>{'drift_ms': 5 * 60 * 1000, 'applied': true},
        <String, Object?>{'drift_ms': 10 * 60 * 1000, 'applied': true},
      ]);
      final Map<String, Object?> back = dataOf(
        eventsOf(kit, 'app.foreground').single,
      );
      expect(back['away_ms'], 15 * 60 * 1000);
      expect(back['hidden_ms'], 15 * 60 * 1000);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: шаги возвращения после сна стоят в журнале '
        'настоящим временем', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(30);
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      kit.session.appState('paused');
      kit.time.sleep(const Duration(minutes: 3));
      // Android возвращает приложение тремя шагами подряд.
      kit.session.appState('hidden');
      kit.session.appState('inactive');
      kit.session.appState('resumed');
      await kit.settle();

      final List<Map<String, Object?>> states = eventsOf(kit, 'app.state');
      final String woke = isoWithOffset(kit.time.wall);
      // Первый же шаг к переднему плану — уже по сверенным часам, а не
      // временем, когда устройство уснуло.
      expect(states[3]['wall'], woke);
      expect(states[4]['wall'], woke);
      expect(states[5]['wall'], woke);
      // Сверка одна на всё возвращение, и расхождение в ней — сон.
      expect(dataOf(eventsOf(kit, 'clock.resync').single), <String, Object?>{
        'drift_ms': 3 * 60 * 1000,
        'applied': true,
      });
      expect(dataOf(eventsOf(kit, 'app.foreground').single), <String, Object?>{
        'away_ms': 3 * 60 * 1000,
        'deepest': 'paused',
        'kind': 'hidden',
        'hidden_ms': 3 * 60 * 1000,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-10: часы перевели назад, пока участника не было, — '
        'отлучка не выходит отрицательной', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(10);
      kit.session.appState('hidden');
      kit.time.pass(const Duration(seconds: 8));
      kit.time.wall = kit.time.wall.subtract(const Duration(hours: 1));
      kit.session.appState('resumed');
      await kit.settle();

      final Map<String, Object?> back = dataOf(
        eventsOf(kit, 'app.foreground').single,
      );
      // Счёт — по большему из двух часов: монотонные прошли восемь секунд.
      expect(back['away_ms'], 8000);
      expect(back['hidden_ms'], 8000);
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запись началась, когда окно уже без фокуса, — '
        'отлучка идёт с первого мига', () async {
      final SessionKit kit = SessionKit();
      kit.session.appState('inactive');
      await kit.session.start(code);
      kit.run(6);
      kit.session.appState('resumed');
      await kit.settle();

      final Map<String, Object?> left = eventsOf(kit, 'app.background').single;
      expect(left['t'], 0);
      expect(dataOf(left), <String, Object?>{'state': 'inactive'});
      expect(dataOf(eventsOf(kit, 'app.foreground').single), <String, Object?>{
        'away_ms': 6000,
        'deepest': 'inactive',
        'kind': 'unfocused',
        'hidden_ms': 0,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запись началась при свёрнутом окне — время, когда '
        'его не было видно, сочтено', () async {
      final SessionKit kit = SessionKit();
      kit.session.appState('inactive');
      kit.session.appState('hidden');
      await kit.session.start(code);
      kit.run(9);
      kit.session.appState('inactive');
      kit.session.appState('resumed');
      await kit.settle();

      expect(dataOf(eventsOf(kit, 'app.foreground').single), <String, Object?>{
        'away_ms': 9000,
        'deepest': 'hidden',
        'kind': 'hidden',
        'hidden_ms': 9000,
      });
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запоздавший ответ об экране к другой отлучке не '
        'относится', () async {
      final SessionKit kit = SessionKit();
      kit.status.holdScreen = true;
      await kit.session.start(code);
      // Первая отлучка: вопрос об экране задан, ответа нет.
      kit.session.appState('hidden');
      kit.time.pass(const Duration(seconds: 2));
      kit.session.appState('resumed');
      // Вторая отлучка — и только теперь приходит ответ на первый вопрос.
      kit.time.pass(const Duration(seconds: 5));
      kit.session.appState('hidden');
      expect(kit.status.screenAsks, hasLength(2));
      kit.status.screenAsks[0].complete(false);
      await kit.settle();
      kit.status.screenAsks[1].complete(true);
      await kit.settle();
      kit.time.pass(const Duration(seconds: 2));
      kit.session.appState('resumed');
      await kit.settle();

      for (final Map<String, Object?> back in eventsOf(kit, 'app.foreground')) {
        expect(dataOf(back).containsKey('reason'), isFalse);
      }

      // Ответ, пришедший вовремя, принимается.
      kit.session.appState('hidden');
      kit.status.screenAsks[2].complete(false);
      await kit.settle();
      kit.session.appState('resumed');
      await kit.settle();
      expect(
        dataOf(eventsOf(kit, 'app.foreground').last)['reason'],
        'screen_off',
      );
      kit.session.dispose();
    });

    test('SNO-F-REC-10: запись оборвалась в фоне — закрытая после сбоя '
        'запись это говорит', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(20);
      first.session.appState('inactive');
      first.session.appState('paused');
      // Приложение ещё полминуты жило в фоне, потом система его убрала.
      first.run(30);
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
      expect(dataOf(second.store.events(folder).last)['in_background'], isTrue);
      expect(recordingInfo(second, folder)['in_background'], isTrue);
      // Итог отлучек оборванной записи собран по журналу: от ухода до
      // его последней строки.
      expect(recordingInfo(second, folder)['away'], <String, Object?>{
        'count': 1,
        'total_ms': 30000,
        'hidden_ms': 30000,
        'longest_ms': 30000,
      });
      expect(
        describeAway(second.session.away),
        'Уходил из приложения: 1 раз, 0:30',
      );
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

  group('SNO-F-REC-16: остановка закрывает открытую книгу', () {
    test('SNO-F-REC-16: книга открыта в миг остановки — `book.close` лежит '
        'перед `recording.stop`, тем же мигом', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(20);
      kit.session.screen('reader');
      kit.session.bookOpened('hash-a', via: 'shelf');
      kit.session.place(page: 7, strip: 2, mode: 'half');
      kit.run(95);

      await kit.session.stop(StopReason.experimenter);

      final List<String> types = kit.store.types(kit.folder);
      expect(types.sublist(types.length - 2), <String>[
        'book.close',
        'recording.stop',
      ]);
      final Map<String, Object?> close = eventsOf(kit, 'book.close').single;
      final Map<String, Object?> stop = eventsOf(kit, 'recording.stop').single;
      expect(close['t'], stop['t']);
      expect(close['seq'], (stop['seq']! as int) - 1);
      // Строка закрытия — ещё о книге: её отпечаток и место чтения.
      expect(close['book'], 'hash-a');
      expect(close['page'], 7);
      expect(close['strip'], 2);
      expect(dataOf(close), <String, Object?>{'open_ms': 95000, 'by': 'stop'});
      // А остановка — уже без книги.
      expect(stop.containsKey('book'), isFalse);
      expect(stop.containsKey('page'), isFalse);
      expect(kit.session.context.book, isNull);

      // Экран чтения снимают следом; его слово о закрытии второй строки
      // не даёт.
      kit.session.bookClosed(
        data: const <String, Object?>{'read_ms': 1, 'read_total_ms': 2},
      );
      await kit.settle();
      expect(eventsOf(kit, 'book.close'), hasLength(1));
      kit.session.dispose();
    });

    test('SNO-F-REC-16: то же на сороковой минуте — книгу закрывает '
        'автостоп', () async {
      final SessionKit kit = SessionKit(planned: const Duration(minutes: 2));
      await kit.session.start(code);
      kit.run(30);
      kit.session.bookOpened('hash-a', via: 'shelf');

      kit.run(120);
      await kit.settle();

      expect(kit.session.phase, RecordingPhase.stopped);
      expect(kit.session.state!.stoppedBy, StopReason.auto);
      final List<String> types = kit.store.types(kit.folder);
      expect(types.sublist(types.length - 2), <String>[
        'book.close',
        'recording.stop',
      ]);
      expect(dataOf(eventsOf(kit, 'book.close').single)['by'], 'stop');
      kit.session.dispose();
    });

    test('SNO-F-REC-17: с книгой закрывается и счёт времени в ней — теми '
        'же числами, что принёс бы экран', () async {
      Map<String, Object?> facts = const <String, Object?>{
        'read_ms': 61000,
        'read_total_ms': 184000,
      };
      final SessionKit kit = SessionKit(closingFacts: () => facts);
      await kit.session.start(code);
      kit.session.bookOpened('hash-a', via: 'galaxy');
      kit.run(70);

      await kit.session.stop(StopReason.experimenter);

      expect(dataOf(eventsOf(kit, 'book.close').single), <String, Object?>{
        'open_ms': 70000,
        'read_ms': 61000,
        'read_total_ms': 184000,
        'by': 'stop',
      });
      // Книгу, закрытую экраном, остановка второй раз не закрывает.
      await kit.session.finish();
      await kit.session.start(code);
      kit.session.bookOpened('hash-b', via: 'shelf');
      kit.run(5);
      facts = const <String, Object?>{'read_ms': 5000, 'read_total_ms': 5000};
      kit.session.bookClosed(data: facts);
      kit.run(5);
      await kit.session.stop(StopReason.experimenter);
      final Map<String, Object?> closed = eventsOf(kit, 'book.close').single;
      expect(dataOf(closed).containsKey('by'), isFalse);
      kit.session.dispose();
    });

    test('SNO-F-REC-16: счёт времени не ответил — книга всё равно '
        'закрыта', () async {
      final SessionKit kit = SessionKit(
        closingFacts: () => throw StateError('счёт не ответил'),
      );
      await kit.session.start(code);
      kit.session.bookOpened('hash-a', via: 'shelf');
      kit.run(12);

      await kit.session.stop(StopReason.experimenter);

      expect(dataOf(eventsOf(kit, 'book.close').single), <String, Object?>{
        'open_ms': 12000,
        'by': 'stop',
      });
      expect(kit.session.phase, RecordingPhase.stopped);
      kit.session.dispose();
    });

    test('SNO-F-REC-16: книга не открыта — строки закрытия нет', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.session.bookOpened('hash-a', via: 'shelf');
      kit.run(10);
      kit.session.bookClosed();
      kit.run(10);

      await kit.session.stop(StopReason.experimenter);

      expect(eventsOf(kit, 'book.close'), hasLength(1));
      expect(kit.store.types(kit.folder).last, 'recording.stop');
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-15: блоков нет', () {
    test('SNO-F-REC-15: запись идёт в один этап — событий о блоках сборка '
        'не пишет, в сведениях записи их нет', () async {
      final SessionKit kit = SessionKit();
      await kit.session.start(code);
      kit.run(300);
      await kit.session.stop(StopReason.experimenter);

      final List<String> types = kit.store.types(kit.folder);
      expect(types, isNot(contains('block.start')));
      expect(types, isNot(contains('block.end')));
      expect(kit.session.state!.blocks, isEmpty);
      expect(recordingInfo(kit, kit.folder)['blocks'], isEmpty);
      await kit.session.finish();
      expect(recordingInfo(kit, kit.store.finished.single)['blocks'], isEmpty);
      kit.session.dispose();
    });
  });

  group('SNO-F-REC-15: записи прежних сборок с блоками', () {
    /// Строка журнала, какой её написала бы прежняя сборка: следующая
    /// по номеру, со временем [t].
    void append(
      SessionKit kit,
      int t,
      SnoEventType type,
      Map<String, Object?> data,
    ) {
      final StringBuffer journal = kit.store.journals[kit.folder]!;
      final int seq = kit.store.events(kit.folder).length + 1;
      journal.writeln(
        encodeEvent(
          seq: seq,
          t: t,
          wall: kit.time.wall,
          type: type,
          context: RecordingContext(),
          data: data,
        ),
      );
    }

    test('SNO-F-REC-15: остановленная сессия прежней сборки — блоки из её '
        'отметки целы после обновления приложения', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(75);
      await first.session.stop(StopReason.experimenter);
      final String folder = first.folder;
      first.session.dispose();
      // Отметку о сессии оставила сборка, в которой блоки были.
      final SessionState old = SessionState.decode(
        first.settings.values[SnoSettingsKeys.session],
      )!;
      first.settings.values[SnoSettingsKeys.session] = SessionState(
        id: old.id,
        folder: old.folder,
        participant: old.participant,
        startedAt: old.startedAt,
        plannedSeconds: old.plannedSeconds,
        phase: old.phase,
        stoppedBy: old.stoppedBy,
        durationMs: old.durationMs,
        events: old.events,
        lastT: old.lastT,
        resyncs: old.resyncs,
        failed: old.failed,
        away: old.away,
        blocks: const <BlockMark>[
          BlockMark(
            number: 3,
            startMs: 0,
            durationMs: 75000,
            closedBy: 'experimenter',
          ),
        ],
        check: old.check,
      ).encode();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(describeBlocks(second.session.state!.blocks), 'Блоки: 3 — 1:15');
      // Запись завершается как есть: блоки доезжают до сведений записи.
      await second.session.finish();
      expect(recordingInfo(second, folder)['blocks'], <Object?>[
        <String, Object?>{
          'n': 3,
          'start_ms': 0,
          'duration_ms': 75000,
          'closed_by': 'experimenter',
        },
      ]);
      second.session.dispose();
    });

    test('SNO-F-REC-15: запись прежней сборки оборвалась — блоки собраны '
        'по журналу, открытый закрыт последним его мигом', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(10);
      await first.settle();
      // Дальше журнал — каким его вела прежняя сборка: два блока, и
      // приложение убито посреди второго.
      append(first, 10000, SnoEventType.blockStart, <String, Object?>{'n': 1});
      first.time.pass(const Duration(seconds: 100));
      append(first, 110000, SnoEventType.blockEnd, <String, Object?>{
        'n': 1,
        'duration_ms': 100000,
        'by': 'experimenter',
      });
      first.time.pass(const Duration(seconds: 5));
      append(first, 115000, SnoEventType.blockStart, <String, Object?>{'n': 2});
      first.time.pass(const Duration(seconds: 35));
      append(first, 150000, SnoEventType.heartbeat, <String, Object?>{});
      final String folder = first.folder;
      first.session.dispose();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      expect(second.session.state!.stoppedBy, StopReason.crash);
      final List<Map<String, Object?>> events = second.store.events(folder);
      // Конец блока дописан раньше остановки, и номера идут подряд.
      final Map<String, Object?> closed = events[events.length - 2];
      expect(closed['type'], 'block.end');
      expect(dataOf(closed), <String, Object?>{
        'n': 2,
        'duration_ms': 35000,
        'by': 'crash',
        'late': true,
      });
      expect(events.last['type'], 'recording.stop');
      final int closedSeq = closed['seq']! as int;
      expect(events.last['seq'], closedSeq + 1);
      expect(second.session.state!.events, closedSeq + 1);
      expect(recordingInfo(second, folder)['blocks'], <Object?>[
        <String, Object?>{
          'n': 1,
          'start_ms': 10000,
          'duration_ms': 100000,
          'closed_by': 'experimenter',
        },
        <String, Object?>{
          'n': 2,
          'start_ms': 115000,
          'duration_ms': 35000,
          'closed_by': 'crash',
        },
      ]);
      expect(
        describeBlocks(second.session.state!.blocks),
        'Блоки: 1 — 1:40 · 2 — 0:35',
      );

      // Второй перезапуск ничего не дописывает и блоков не теряет.
      second.session.dispose();
      final SessionKit third = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await third.session.restore();
      expect(third.store.events(folder), hasLength(events.length));
      expect(third.session.state!.blocks, hasLength(2));
      third.session.dispose();
    });
  });

  group('SNO-F-REC-10: отлучки оборванной остановки', () {
    test('SNO-F-REC-10: умерло между остановкой и отметкой о ней — отлучки '
        'берутся из журнала', () async {
      final SessionKit first = SessionKit();
      await first.session.start(code);
      first.run(20);
      first.session.appState('inactive');
      first.time.pass(const Duration(seconds: 3));
      first.session.appState('resumed');
      first.run(10);
      // Отметка о сессии не ляжет: настройки отказали на остановке.
      first.settings.failKeys.add(SnoSettingsKeys.session);
      await first.session.stop(StopReason.experimenter);
      final String folder = first.folder;
      final int lines = first.store.events(folder).length;
      first.session.dispose();
      first.settings.failKeys.clear();

      final SessionKit second = SessionKit(
        settings: first.settings,
        store: first.store,
        time: first.time,
      );
      await second.session.restore();

      // Запись закрыта своей остановкой, второй поверх нет.
      expect(second.store.events(folder), hasLength(lines));
      expect(second.session.state!.stoppedBy, StopReason.experimenter);
      expect(recordingInfo(second, folder)['blocks'], isEmpty);
      expect(recordingInfo(second, folder)['away'], <String, Object?>{
        'count': 1,
        'total_ms': 3000,
        'hidden_ms': 0,
        'longest_ms': 3000,
      });
      second.session.dispose();
    });
  });

  group('SNO-F-REC-10: итоги по журналу', () {
    final DateTime start = DateTime.utc(2026, 10, 5, 9);
    int seq = 0;
    EventMarks at(
      int t,
      SnoEventType type, [
      Map<String, Object?> data = const <String, Object?>{},
      int sleptMs = 0,
    ]) {
      seq++;
      return EventMarks(
        seq: seq,
        t: t,
        type: type.wire,
        wall: start.add(Duration(milliseconds: t + sleptMs)),
        data: data,
      );
    }

    test('SNO-F-REC-10: пустой журнал — пустые итоги', () {
      final JournalSummary told = summarizeJournal(const <EventMarks>[]);
      expect(told.away.count, 0);
      expect(told.blocks, isEmpty);
      expect(told.openBlock, isNull);
      expect(told.inBackground, isFalse);
    });

    test('SNO-F-REC-10: закрытые отлучки — по словам возвращения, открытая '
        '— до последней строки', () {
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(1000, SnoEventType.appState, <String, Object?>{
          'from': 'resumed',
          'to': 'inactive',
        }),
        at(1000, SnoEventType.appBackground, <String, Object?>{
          'state': 'inactive',
        }),
        at(5000, SnoEventType.appState, <String, Object?>{
          'from': 'inactive',
          'to': 'resumed',
        }),
        at(5000, SnoEventType.appForeground, <String, Object?>{
          'away_ms': 4000,
          'hidden_ms': 0,
        }),
        at(9000, SnoEventType.appState, <String, Object?>{
          'from': 'resumed',
          'to': 'inactive',
        }),
        at(9000, SnoEventType.appBackground, <String, Object?>{
          'state': 'inactive',
        }),
        at(10000, SnoEventType.appState, <String, Object?>{
          'from': 'inactive',
          'to': 'paused',
        }),
        // Устройство спало минуту: `t` стоял, настенные часы шли.
        at(10000, SnoEventType.heartbeat, <String, Object?>{
          'state': 'paused',
        }, 60000),
      ]);

      expect(told.inBackground, isTrue);
      expect(told.away.count, 2);
      expect(told.away.totalMs, 4000 + 61000);
      expect(told.away.hiddenMs, 60000);
      expect(told.away.longestMs, 61000);
    });

    test('SNO-F-REC-10: запоздавшая остановка — время после конца записи в '
        'открытую отлучку не входит', () {
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(2000, SnoEventType.appState, <String, Object?>{
          'from': 'resumed',
          'to': 'hidden',
        }),
        at(2000, SnoEventType.appBackground, <String, Object?>{
          'state': 'hidden',
        }),
        at(30000, SnoEventType.recordingStop, <String, Object?>{
          'stopped_by': 'auto',
          'late_ms': 8000,
          'in_background': true,
        }),
        // Что записано после остановки, в итог не входит.
        at(90000, SnoEventType.sessionFinish),
      ]);

      expect(told.away.count, 1);
      expect(told.away.totalMs, 20000);
      expect(told.away.hiddenMs, 20000);
    });

    test('SNO-F-REC-10: о конце записи узнали по возвращении — последняя '
        'отлучка идёт в итог до конца записи', () {
      const int quarter = 15 * 60 * 1000;
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(300000, SnoEventType.appState, <String, Object?>{
          'from': 'resumed',
          'to': 'paused',
        }),
        at(300000, SnoEventType.appBackground, <String, Object?>{
          'state': 'paused',
        }),
        at(300000, SnoEventType.appState, <String, Object?>{
          'from': 'paused',
          'to': 'resumed',
        }, quarter),
        at(300000, SnoEventType.appForeground, <String, Object?>{
          'away_ms': quarter,
          'hidden_ms': quarter,
        }, quarter),
        at(300000, SnoEventType.recordingStop, <String, Object?>{
          'stopped_by': 'auto',
          'late_ms': 10 * 60 * 1000,
          'in_background': true,
        }, quarter),
      ]);

      expect(told.away.count, 1);
      expect(told.away.totalMs, 5 * 60 * 1000);
      expect(told.away.hiddenMs, 5 * 60 * 1000);
      // Отлучка закрыта возвращением: открытой журнал её не называет.
      expect(told.inBackground, isFalse);
    });

    test('SNO-F-REC-10: запись началась при свёрнутом окне и оборвалась — '
        'время, когда приложения не было видно, сочтено', () {
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(0, SnoEventType.appBackground, <String, Object?>{'state': 'hidden'}),
        at(10000, SnoEventType.heartbeat, <String, Object?>{'state': 'hidden'}),
      ]);

      expect(told.inBackground, isTrue);
      expect(told.away.totalMs, 10000);
      expect(told.away.hiddenMs, 10000);
    });

    test('SNO-F-REC-10: строки, дописанные после сбоя, концом записи не '
        'считаются', () {
      const int hour = 60 * 60 * 1000;
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(1000, SnoEventType.blockStart, <String, Object?>{'n': 1}),
        at(5000, SnoEventType.appState, <String, Object?>{
          'from': 'resumed',
          'to': 'hidden',
        }),
        at(5000, SnoEventType.appBackground, <String, Object?>{
          'state': 'hidden',
        }),
        at(9000, SnoEventType.heartbeat, <String, Object?>{'state': 'hidden'}),
        // Приложение перезапустили через час: эти строки — его время.
        at(9000, SnoEventType.blockEnd, <String, Object?>{
          'n': 1,
          'duration_ms': 8000,
          'by': 'crash',
          'late': true,
        }, hour),
        at(9000, SnoEventType.recordingStop, <String, Object?>{
          'stopped_by': 'crash',
          'duration_ms': 9000,
          'late': true,
          'in_background': true,
        }, hour),
      ]);

      // Отлучка — до последней строки самой записи, а не до перезапуска.
      expect(told.away.totalMs, 4000);
      expect(told.away.hiddenMs, 4000);
      // Блок закрыт дописанной строкой и открытым больше не считается.
      expect(told.openBlock, isNull);
      expect(told.blocks.single.toJson(), <String, Object?>{
        'n': 1,
        'start_ms': 1000,
        'duration_ms': 8000,
        'closed_by': 'crash',
      });
    });

    test('SNO-F-CFG-03: блоки — закрытые как записаны, открытый до '
        'последней строки', () {
      final JournalSummary told = summarizeJournal(<EventMarks>[
        at(0, SnoEventType.recordingStart),
        at(1000, SnoEventType.blockStart, <String, Object?>{'n': 1}),
        at(4000, SnoEventType.blockEnd, <String, Object?>{
          'n': 1,
          'duration_ms': 3000,
          'by': 'experimenter',
        }),
        at(6000, SnoEventType.blockStart, <String, Object?>{'n': 2}),
        at(6500, SnoEventType.heartbeat, const <String, Object?>{}, 20000),
      ]);

      expect(told.blocks.single.toJson(), <String, Object?>{
        'n': 1,
        'start_ms': 1000,
        'duration_ms': 3000,
        'closed_by': 'experimenter',
      });
      expect(told.openBlock!.toJson(), <String, Object?>{
        'n': 2,
        'start_ms': 6000,
        'duration_ms': 20500,
        'closed_by': 'crash',
      });
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
      await settings.remove('ui.theme');

      expect(inner.values.containsKey('ui.theme'), isFalse);
      expect(log.events, isEmpty);
      // Вне записи событие даже не собирают.
      expect(log.asked, 0);
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
