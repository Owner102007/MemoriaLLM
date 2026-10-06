import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/galaxy.dart';
import 'package:memoria/sno/index/shelf_reading.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/ui/galaxy/galaxy_painter.dart';
import 'package:memoria/ui/galaxy/galaxy_screen.dart';

import '../data/test_data.dart';
import '../support/galaxy_shelf.dart';
import '../support/recording_fakes.dart';
import '../support/shown_reading.dart';
import '../support/test_services.dart';

/// Шаг 23, SNO-F-MAP-01: действия на карте в журнале записи.
///
/// Раздел «Галактика» на настоящей базе в памяти и настоящая сессия
/// записи на памяти: проверяется, что открытая карта, её перенос и
/// зум, нажатие на точку и карточка книги ложатся в журнал своими
/// событиями, — и что по числам этих событий место на экране
/// переводится в координаты карты.
void main() {
  late AppData data;
  late SessionKit kit;

  final ParticipantCode code = ParticipantCode(
    code: kTestCode,
    generated: true,
    generatedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
  );

  setUp(() async {
    data = await openTestData();
    kit = SessionKit();
  });
  tearDown(() async {
    kit.session.dispose();
    await data.close();
  });

  Future<void> pumpGalaxy(
    WidgetTester tester,
    AppServices services, {
    bool visible = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GalaxyScreen(
          services: services,
          visible: visible,
          canRelink: false,
          models: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// События журнала вида, начинающегося с [prefix], по порядку.
  Future<List<Map<String, Object?>>> logged(
    WidgetTester tester, [
    String prefix = 'galaxy.',
  ]) async {
    kit.session.tick();
    await tester.pump();
    return <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(kit.folder))
        if ('${event['type']}'.startsWith(prefix)) event,
    ];
  }

  Map<String, Object?> dataOf(Map<String, Object?> event) {
    return event['data']! as Map<String, Object?>;
  }

  List<Object?> typesOf(List<Map<String, Object?>> events) {
    return <Object?>[
      for (final Map<String, Object?> event in events) event['type'],
    ];
  }

  GalaxyMapState mapOf(WidgetTester tester) {
    return tester.state<GalaxyMapState>(find.byType(GalaxyMap));
  }

  /// Где на экране стоит книга [id].
  Offset placeOf(WidgetTester tester, String id) {
    final GalaxyScene scene = mapOf(tester).scene!;
    final int index = scene.stars.indexWhere(
      (GalaxyStar star) => star.book.id == id,
    );
    return tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
        scene.placeOf(index);
  }

  Future<void> tapStar(WidgetTester tester, String id) async {
    await tester.tapAt(placeOf(tester, id));
    await tester.pumpAndSettle();
  }

  double number(Object? value) => (value! as num).toDouble();

  group('SNO-F-MAP-01: карта в журнале записи', () {
    testWidgets('SNO-F-MAP-01: раздел открыт — в журнале карта целиком, и '
        'по её числам место на экране переводится в место на карте', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );

      final List<Map<String, Object?>> events = await logged(tester);
      expect(typesOf(events), <String>['galaxy.open']);
      final Map<String, Object?> open = dataOf(events.single);
      expect(open['stars'], 6);
      expect(number(open['scale']), 1.0);
      expect(number(open['w']), greaterThan(0));
      expect(number(open['h']), greaterThan(0));
      final List<Object?> points = open['points']! as List<Object?>;
      expect(points, hasLength(6));
      final Offset origin = tester.getTopLeft(
        find.byKey(const Key('galaxy-map')),
      );
      expect(number(open['left']), closeTo(origin.dx, 0.01));
      expect(number(open['top']), closeTo(origin.dy, 0.01));
      for (final Object? raw in points) {
        final Map<String, Object?> point = raw! as Map<String, Object?>;
        final String hash = point['book']! as String;
        expect(hash, startsWith('hash-'));
        expect(number(point['r']), greaterThan(0));
        expect(point['ms'], 0);
        expect(point['group'], isIn(kGalaxyCategories.values));
        // Место точки на экране — по числам события, без кода карты.
        final double sx =
            number(open['left']) +
            number(open['w']) / 2 +
            (number(point['x']) - number(open['cx'])) * number(open['unit']);
        final double sy =
            number(open['top']) +
            number(open['h']) / 2 +
            (number(point['y']) - number(open['cy'])) * number(open['unit']);
        final Offset shown = placeOf(tester, hash.substring('hash-'.length));
        expect(sx, closeTo(shown.dx, 0.01));
        expect(sy, closeTo(shown.dy, 0.01));
      }

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: раздел, который не видно, в журнал не '
        'пишет; открыли второй раз — второе событие', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await kit.session.start(code);
      final AppServices services = testServices(
        data: data,
        recording: kit.session,
      );

      await pumpGalaxy(tester, services, visible: false);
      expect(await logged(tester), isEmpty);
      await pumpGalaxy(tester, services);
      expect(typesOf(await logged(tester)), <String>['galaxy.open']);
      await pumpGalaxy(tester, services, visible: false);
      await pumpGalaxy(tester, services);
      expect(typesOf(await logged(tester)), <String>[
        'galaxy.open',
        'galaxy.open',
      ]);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: запись не идёт — карта работает, журнал '
        'пуст', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );

      await tapStar(tester, 'a2');
      expect(find.byKey(const Key('galaxy-card-a2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('galaxy-card-close')));
      await tester.pumpAndSettle();

      expect(kit.store.journals, isEmpty);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: нажатие на точку, карточка, другая точка, '
        'нажатие мимо, крестик', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );
      final Offset away =
          tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
          const Offset(20, 20);

      // Мимо точек, пока карточки нет: событием это не становится.
      await tester.tapAt(away);
      await tester.pumpAndSettle();
      await tapStar(tester, 'a2');
      await tapStar(tester, 'm1');
      await tester.tapAt(away);
      await tester.pumpAndSettle();
      await tapStar(tester, 'a1');
      await tester.tap(find.byKey(const Key('galaxy-card-close')));
      await tester.pumpAndSettle();

      final List<Map<String, Object?>> events = (await logged(tester))
          .where((Map<String, Object?> event) {
            return event['type'] != 'galaxy.open';
          })
          .toList();
      expect(typesOf(events), <String>[
        'galaxy.star',
        'galaxy.card.open',
        'galaxy.star',
        'galaxy.card.close',
        'galaxy.card.open',
        'galaxy.card.close',
        'galaxy.star',
        'galaxy.card.open',
        'galaxy.card.close',
      ]);
      expect(dataOf(events[0]), <String, Object?>{
        'book': 'hash-a2',
        'selected': false,
      });
      expect(dataOf(events[1]), <String, Object?>{'book': 'hash-a2'});
      expect(dataOf(events[3]), <String, Object?>{
        'book': 'hash-a2',
        'by': 'other_star',
      });
      expect(dataOf(events[4]), <String, Object?>{'book': 'hash-m1'});
      expect(dataOf(events[5]), <String, Object?>{
        'book': 'hash-m1',
        'by': 'tap_away',
      });
      expect(dataOf(events[8]), <String, Object?>{
        'book': 'hash-a1',
        'by': 'button',
      });
      // Экран в каждом событии — тот, что назвала оболочка.
      expect(events.first['screen'], kit.session.context.screen);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: колесо и перенос — чем жест кончился, с '
        'причиной', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );
      final Offset centre = tester.getCenter(
        find.byKey(const Key('galaxy-map')),
      );

      // Три щелчка колеса подряд: в журнале первое положение и то, на
      // чём остановились, а не каждый щелчок.
      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(centre);
      for (int i = 0; i < 3; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final double zoomed = mapOf(tester).viewport.camera.scale;
      expect(zoomed, greaterThan(1));
      // Перенос пальцем.
      await tester.dragFrom(centre, const Offset(-80, 0));
      await tester.pumpAndSettle();

      final List<Map<String, Object?>> views = (await logged(tester))
          .where((Map<String, Object?> event) {
            return event['type'] == 'galaxy.view';
          })
          .toList();
      expect(views, hasLength(3));
      expect(dataOf(views[0])['cause'], 'wheel');
      expect(dataOf(views[1])['cause'], 'wheel');
      expect(number(dataOf(views[1])['scale']), closeTo(zoomed, 1e-9));
      expect(dataOf(views[2])['cause'], 'drag');
      // Карту увели влево — середина экрана смотрит правее.
      expect(
        number(dataOf(views[2])['cx']),
        greaterThan(number(dataOf(views[1])['cx'])),
      );
      expect(number(dataOf(views[2])['scale']), closeTo(zoomed, 1e-9));

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: двойное нажатие приближает — и это в '
        'журнале', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );
      final Offset corner =
          tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
          const Offset(20, 20);

      await tester.tapAt(corner);
      await tester.pump();
      await tester.tapAt(corner);
      await tester.pump();

      final Map<String, Object?> view = (await logged(tester))
          .singleWhere((Map<String, Object?> event) {
            return event['type'] == 'galaxy.view';
          });
      expect(dataOf(view)['cause'], 'double_tap');
      expect(number(dataOf(view)['scale']), 2.0);

      await unmount(tester);
    });
  });

  group('SNO-F-MAP-01: слова вместо карты — тоже в журнале', () {
    testWidgets('SNO-F-MAP-01: карта не посчитана', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups, withMap: false);
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );

      final Map<String, Object?> event = (await logged(tester)).single;
      expect(event['type'], 'galaxy.empty');
      expect(dataOf(event), <String, Object?>{'state': 'no_map', 'books': 6});

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: книг мало', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups.sublist(0, 2));
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session),
      );

      final Map<String, Object?> event = (await logged(tester)).single;
      expect(dataOf(event), <String, Object?>{'state': 'too_few', 'books': 2});

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: книги ещё читаются — сказано, на какой '
        'книге; дочитались — карта', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      final ShownReading reading = ShownReading(data);
      addTearDown(reading.dispose);
      reading.show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.reading,
          booksDone: 4,
          booksTotal: 6,
        ),
      );
      await kit.session.start(code);
      await pumpGalaxy(
        tester,
        testServices(data: data, recording: kit.session, shelfReading: reading),
      );

      final Map<String, Object?> waiting = (await logged(tester)).single;
      expect(waiting['type'], 'galaxy.empty');
      expect(dataOf(waiting), <String, Object?>{
        'state': 'preparing',
        'books': 6,
        'phase': 'reading',
        'books_done': 4,
        'books_total': 6,
      });

      reading.show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.done,
          booksDone: 6,
          booksTotal: 6,
        ),
      );
      await tester.pumpAndSettle();

      expect(typesOf(await logged(tester)), <String>[
        'galaxy.empty',
        'galaxy.open',
      ]);

      await unmount(tester);
    });
  });
}
