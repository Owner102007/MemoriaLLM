import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/galaxy.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/shelf.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/participant_code.dart';
import 'package:memoria/sno/recording/layout_frames.dart';
import 'package:memoria/sno/recording/layout_probe.dart';
import 'package:memoria/sno/recording/recording_overlay.dart';
import 'package:memoria/ui/galaxy/galaxy_painter.dart';
import 'package:memoria/ui/galaxy/galaxy_screen.dart';
import 'package:memoria/ui/library/library_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/galaxy_shelf.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// Шаг 31, SNO-F-REC-03, SNO-ALG-REC-02: кадры раскладки полки, поиска
/// по названию и карты (сессия ET-05).
///
/// Экраны — те же, что в приложении, под слоем записи; сессия — на
/// памяти и подменённом времени. Проверяется, что в кадр ложатся
/// категории и книги полки с их названиями и отпечатками, строки
/// найденного с местом в списке, звёзды карты с камерой; что зона за
/// краем прокрутки в кадр не попадает, а подрезанная помечена; что
/// прокрутка даёт кадры «в движении» не чаще пяти в секунду и один
/// устоявшийся; и что касание книги, строки и звезды лежит по кадру в
/// той зоне, которая его приняла.
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
    await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
  });
  tearDown(() async {
    kit.session.dispose();
    await data.close();
  });

  /// Экран [home] под слоем записи, как в приложении.
  Future<void> pumpUnder(WidgetTester tester, Widget home) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (BuildContext context, Widget? page) {
          return RecordingOverlay(
            session: kit.session,
            navigator: navigator,
            child: page!,
          );
        },
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Запись началась, и первый кадр простоял.
  Future<void> startRecording(WidgetTester tester) async {
    await kit.session.start(code);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Кадры, как они лежат «на диске».
  Future<List<Map<String, Object?>>> frames(WidgetTester tester) async {
    kit.session.tick();
    await tester.pump();
    return kit.store.layoutLines(kit.folder);
  }

  Future<LayoutFrame> lastFrame(WidgetTester tester) async {
    return LayoutFrame.fromJson((await frames(tester)).last)!;
  }

  List<LayoutRegion> of(LayoutFrame frame, LayoutKind kind) {
    return <LayoutRegion>[
      for (final LayoutRegion region in frame.regions)
        if (region.kind == kind) region,
    ];
  }

  /// Последнее касание потока ввода — точкой окна.
  Future<Offset> lastTap(WidgetTester tester) async {
    kit.session.tick();
    await tester.pump();
    final Map<String, Object?> tap = kit.store.inputLines(kit.folder).last;
    return Offset(
      (tap['x']! as num).toDouble(),
      (tap['y']! as num).toDouble(),
    );
  }

  group('SNO-F-REC-03: зона за краем прокрутки', () {
    /// Список из тридцати помеченных строк по 100 пикселей под шапкой
    /// в 56: в окне 800 × 600 видно пять с половиной.
    Widget list() {
      return Scaffold(
        appBar: AppBar(title: const Text('список')),
        body: ListView.builder(
          key: const Key('list'),
          itemCount: 30,
          itemBuilder: (BuildContext context, int index) {
            return LayoutProbe(
              kind: LayoutKind.shelfBook,
              id: 'строка $index',
              child: SizedBox(height: 100, child: Text('строка $index')),
            );
          },
        ),
      );
    }

    testWidgets('SNO-F-REC-03: строки запаса прокрутки в кадр не попадают, '
        'подрезанная краем — видимой частью и с пометкой', (
      WidgetTester tester,
    ) async {
      await pumpUnder(tester, list());
      await startRecording(tester);

      final LayoutFrame frame = await lastFrame(tester);
      final List<LayoutRegion> rows = of(frame, LayoutKind.shelfBook);
      // 544 пикселя списка: пять строк целиком и половина шестой.
      expect(rows.map((LayoutRegion row) => row.id), <String>[
        'строка 0',
        'строка 1',
        'строка 2',
        'строка 3',
        'строка 4',
        'строка 5',
      ]);
      expect(rows.take(5).every((LayoutRegion row) => !row.clipped), isTrue);
      expect(rows.last.clipped, isTrue);
      expect(rows.last.rect.top, closeTo(556, 0.06));
      expect(rows.last.rect.bottom, closeTo(600, 0.06));

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: прокрутка — кадры «в движении» не чаще пяти '
        'в секунду и один устоявшийся; строка под шапкой подрезана сверху', (
      WidgetTester tester,
    ) async {
      await pumpUnder(tester, list());
      await startRecording(tester);
      final int before = (await frames(tester)).length;

      final TestGesture finger = await tester.startGesture(
        const Offset(400, 400),
      );
      for (int i = 0; i < 30; i++) {
        await finger.moveBy(const Offset(0, -5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Палец постоял и поднялся: без скорости список не катится сам.
      await tester.pump(const Duration(milliseconds: 300));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 150));

      final List<Map<String, Object?>> lines = (await frames(
        tester,
      )).skip(before).toList();
      final List<Map<String, Object?>> moving = <Map<String, Object?>>[
        for (final Map<String, Object?> line in lines)
          if (line['moving'] == true) line,
      ];
      expect(moving, isNotEmpty);
      // Полсекунды прокрутки — не больше трёх кадров «в движении».
      expect(moving.length, lessThanOrEqualTo(3));
      expect(lines.last['moving'], isFalse);
      expect(
        lines.where((Map<String, Object?> line) => line['moving'] == false),
        hasLength(1),
      );
      final LayoutFrame frame = LayoutFrame.fromJson(lines.last)!;
      final LayoutRegion first = of(frame, LayoutKind.shelfBook).first;
      expect(first.clipped, isTrue);
      expect(first.rect.top, closeTo(56, 0.06));

      await unmount(tester);
    });
  });

  group('SNO-F-REC-03: полка', () {
    /// Окно 800 × 1400: телефонная раскладка, на экране две категории
    /// целиком и третья — краем.
    void tallWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Восемь категорий по книге: полку можно прокрутить.
    Future<void> eightCategories(WidgetTester tester) async {
      tallWindow(tester);
      for (int i = 0; i < 8; i++) {
        await data.categories.save(
          BookCategory(
            id: 'c$i',
            title: 'Раздел $i',
            position: i,
            createdAt: DateTime.utc(2026, 8, 20),
          ),
        );
        await data.library.save(
          testBook(id: 'b$i', title: 'Том $i', hash: 'hash-b$i'),
        );
        await placeBook(data, 'b$i', 'c$i');
      }
    }

    Widget shelf(AppServices services) {
      return LibraryScreen(
        services: services,
        canAddBooks: false,
        defaultSort: ShelfSort.manual,
        titleSearch: true,
        models: false,
        locked: true,
      );
    }

    AppServices services() {
      return testServices(
        data: data,
        recording: kit.session,
        document: FakeReaderDocument(pages: <String>['один', 'два']),
      );
    }

    testWidgets('SNO-F-REC-03: в кадре полка со сдвигом прокрутки, шапки и '
        'участки категорий с названием, книги с отпечатком и категорией', (
      WidgetTester tester,
    ) async {
      await eightCategories(tester);
      await pumpUnder(tester, shelf(services()));
      await startRecording(tester);

      final LayoutFrame frame = await lastFrame(tester);
      final LayoutRegion screen = of(frame, LayoutKind.screen).single;
      expect(screen.id, 'shelf');
      expect(screen.info['scroll'], 0);
      final List<LayoutRegion> categories = of(
        frame,
        LayoutKind.shelfCategory,
      );
      expect(categories.first.id, 'Раздел 0');
      expect(categories.first.info, <String, Object?>{'part': 'header'});
      expect(categories[1].id, 'Раздел 0');
      expect(categories[1].info, <String, Object?>{'part': 'area'});
      final List<LayoutRegion> books = of(frame, LayoutKind.shelfBook);
      expect(books.first.id, 'hash-b0');
      expect(books.first.info, <String, Object?>{'category': 'Раздел 0'});
      // Книга внутри своего участка и выше него по наложению.
      expect(books.first.z, greaterThan(categories[1].z));
      expect(
        categories[1].rect.contains(
          books.first.rect.left + 1,
          books.first.rect.top + 1,
        ),
        isTrue,
      );
      // Восьмой категории на экране нет — и в кадре тоже.
      expect(
        categories.map((LayoutRegion region) => region.id),
        isNot(contains('Раздел 7')),
      );
      // Ни одна зона не вылезает за низ окна и выше шапки полки.
      for (final LayoutRegion region in <LayoutRegion>[
        ...categories,
        ...books,
      ]) {
        expect(
          region.rect.bottom,
          lessThanOrEqualTo(1400.05),
          reason: region.id,
        );
        expect(
          region.rect.top,
          greaterThanOrEqualTo(55.95),
          reason: region.id,
        );
      }

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: полку прокрутили — сдвиг в кадре тот же, что '
        'у списка, книги уехали вместе с ним', (WidgetTester tester) async {
      await eightCategories(tester);
      await pumpUnder(tester, shelf(services()));
      await startRecording(tester);
      final LayoutFrame before = await lastFrame(tester);
      final LayoutRegion book0 = of(before, LayoutKind.shelfBook).first;

      await tester.drag(
        find.byKey(const Key('library-shelf')),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));

      final LayoutFrame after = await lastFrame(tester);
      final double scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('library-shelf')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      expect(scroll, greaterThan(0));
      expect(
        (of(after, LayoutKind.screen).single.info['scroll']! as num)
            .toDouble(),
        closeTo(scroll, 0.06),
      );
      final LayoutRegion moved = of(after, LayoutKind.shelfBook).firstWhere(
        (LayoutRegion region) => region.id == 'hash-b0',
        orElse: () => book0,
      );
      // Книга ещё видна: она уехала вверх ровно на сдвиг или подрезана
      // шапкой.
      expect(identical(moved, book0), isFalse);
      expect(
        moved.clipped ||
            (book0.rect.top - moved.rect.top - scroll).abs() < 0.2,
        isTrue,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: касание книги лежит по кадру в зоне этой книги '
        '— той, что её открыла', (WidgetTester tester) async {
      await eightCategories(tester);
      await pumpUnder(tester, shelf(services()));
      await startRecording(tester);
      final LayoutFrame frame = await lastFrame(tester);
      final LayoutRegion target = of(frame, LayoutKind.shelfBook)[1];

      await tester.tapAt(
        Offset(
          target.rect.left + target.rect.width / 2,
          target.rect.top + target.rect.height / 2,
        ),
      );
      await tester.pumpAndSettle();

      final Offset tap = await lastTap(tester);
      final LayoutHit hit = frame.locate(tap.dx, tap.dy);
      expect(hit.zone, 'shelf_book');
      expect(hit.id, target.id);
      expect(hit.info['category'], 'Раздел 1');
      // Книгу открыло именно это касание: в журнале открыта та же.
      kit.session.tick();
      await tester.pump();
      final Map<String, Object?> opened = kit.store
          .events(kit.folder)
          .lastWhere(
            (Map<String, Object?> event) => event['type'] == 'book.open',
          );
      expect(opened['book'], target.id);

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: поиск по названию на телефоне — поле и строки '
        'найденного с местом в списке; полки под списком в кадре нет', (
      WidgetTester tester,
    ) async {
      await eightCategories(tester);
      await pumpUnder(tester, shelf(services()));
      await startRecording(tester);

      await tester.tap(find.byKey(const Key('library-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shelf-search-field')),
        'том',
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 800));

      final LayoutFrame frame = await lastFrame(tester);
      expect(of(frame, LayoutKind.shelfSearch), hasLength(1));
      final LayoutRegion results = of(frame, LayoutKind.shelfResults).single;
      expect(results.info['hits'], 8);
      expect(of(frame, LayoutKind.shelfCategory), isEmpty);
      final List<LayoutRegion> rows = of(frame, LayoutKind.shelfBook);
      expect(rows, isNotEmpty);
      expect(rows.first.info['in'], 'results');
      expect(rows.first.info['rank'], 1);
      expect(rows[1].info['rank'], 2);
      expect(rows.first.info['category'], isA<String>());
      expect(of(frame, LayoutKind.screen).single.info['searching'], isTrue);

      // Касание строки — по кадру в строке с тем же местом.
      await tester.tapAt(rows[1].rect.center);
      await tester.pumpAndSettle();
      final Offset tap = await lastTap(tester);
      final LayoutHit hit = frame.locate(tap.dx, tap.dy);
      expect(hit.zone, 'shelf_book');
      expect(hit.id, rows[1].id);
      expect(hit.info['rank'], 2);

      await unmount(tester);
    });
  });

  group('SNO-F-REC-03: карта «Галактика»', () {
    Future<void> pumpGalaxy(WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpUnder(
        tester,
        GalaxyScreen(
          services: testServices(data: data, recording: kit.session),
          visible: true,
          canRelink: false,
          models: false,
        ),
      );
    }

    Offset placeOf(WidgetTester tester, String id) {
      final GalaxyMapState map = tester.state<GalaxyMapState>(
        find.byType(GalaxyMap),
      );
      final GalaxyScene scene = map.scene!;
      final int index = scene.stars.indexWhere(
        (GalaxyStar star) => star.book.id == id,
      );
      return tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
          scene.placeOf(index);
    }

    testWidgets('SNO-F-REC-03: в кадре — раздел, полотно с камерой и всеми '
        'видимыми звёздами на их местах', (WidgetTester tester) async {
      await pumpGalaxy(tester);
      await startRecording(tester);

      final LayoutFrame frame = await lastFrame(tester);
      expect(of(frame, LayoutKind.screen).single.id, 'galaxy');
      expect(of(frame, LayoutKind.screen).single.info['shows'], 'map');
      final LayoutRegion map = of(frame, LayoutKind.galaxyMap).single;
      final Map<String, Object?> camera =
          map.info['map']! as Map<String, Object?>;
      expect(camera.keys, containsAll(<String>['scale', 'cx', 'cy', 'unit']));
      expect(map.info['stars'], kTwoGroups.length);
      expect(map.marks, hasLength(kTwoGroups.length));
      final Rect drawn = tester.getRect(find.byKey(const Key('galaxy-map')));
      expect(map.rect.left, closeTo(drawn.left, 0.06));
      expect(map.rect.top, closeTo(drawn.top, 0.06));
      for (final ShelfStar star in kTwoGroups) {
        final LayoutMark mark = map.marks.firstWhere(
          (LayoutMark mark) => mark.id == hashOfStar(star.id),
        );
        final Offset place = placeOf(tester, star.id);
        expect(mark.x, closeTo(place.dx, 0.06), reason: star.id);
        expect(mark.y, closeTo(place.dy, 0.06), reason: star.id);
      }

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: касание звезды — по кадру её отпечаток; '
        'открытая карточка — зона поверх карты', (WidgetTester tester) async {
      await pumpGalaxy(tester);
      await startRecording(tester);
      final LayoutFrame before = await lastFrame(tester);

      await tester.tapAt(placeOf(tester, 'a2') + const Offset(3, -2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));

      final Offset tap = await lastTap(tester);
      final LayoutHit hit = before.locate(tap.dx, tap.dy);
      expect(hit.zone, 'galaxy_map');
      expect(hit.mark, hashOfStar('a2'));
      final LayoutFrame after = await lastFrame(tester);
      final LayoutRegion card = of(after, LayoutKind.galaxyCard).single;
      expect(card.id, hashOfStar('a2'));
      expect(
        card.z,
        greaterThan(of(after, LayoutKind.galaxyMap).single.z),
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-REC-03: перенос карты — кадры «в движении» и один '
        'устоявшийся с новой камерой', (WidgetTester tester) async {
      await pumpGalaxy(tester);
      await startRecording(tester);
      final int before = (await frames(tester)).length;
      final LayoutFrame start = await lastFrame(tester);

      final TestGesture finger = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('galaxy-map'))),
      );
      for (int i = 0; i < 20; i++) {
        await finger.moveBy(const Offset(6, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await finger.up();
      await tester.pump(const Duration(milliseconds: 150));

      final List<Map<String, Object?>> lines = (await frames(
        tester,
      )).skip(before).toList();
      expect(
        lines.where((Map<String, Object?> line) => line['moving'] == true),
        isNotEmpty,
      );
      expect(lines.last['moving'], isFalse);
      final LayoutFrame end = LayoutFrame.fromJson(lines.last)!;
      final LayoutMark a1Before = of(
        start,
        LayoutKind.galaxyMap,
      ).single.marks.firstWhere((LayoutMark m) => m.id == hashOfStar('a1'));
      final LayoutMark a1After = of(
        end,
        LayoutKind.galaxyMap,
      ).single.marks.firstWhere(
        (LayoutMark m) => m.id == hashOfStar('a1'),
        orElse: () => a1Before,
      );
      expect(a1After.x, isNot(closeTo(a1Before.x, 1)));

      await unmount(tester);
    });
  });
}
