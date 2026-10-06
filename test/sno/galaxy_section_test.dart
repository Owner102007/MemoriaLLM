import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/galaxy.dart';
import 'package:memoria/application/reading/book_times.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/galaxy/galaxy_screen.dart';
import 'package:memoria/ui/library/library_screen.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/galaxy_shelf.dart';
import '../support/recording_fakes.dart';
import '../support/shown_reading.dart';
import '../support/test_services.dart';

/// SNO-F-MAP-01, F-MAP-06: раздел «Галактика» в собранном приложении
/// (кадр SNO-SCR-00.2).
///
/// Флаги ветви — константы сборки, поэтому один прогон видит одно
/// приложение из трёх: прогон ветви II (`flutter test test/sno
/// --dart-define=SNO_BRANCH=II`) проверяет, что раздел есть и ведёт
/// себя как раздел; основной прогон и прогон ветви I — что раздела нет.
/// Сам экран проверен основным прогоном в
/// `test/map/galaxy_screen_test.dart`.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  const String galaxyOnly =
      'проверяется прогоном ветви II (--dart-define=SNO_BRANCH=II)';
  const String othersOnly =
      'прогон ветви II: проверяется основным прогоном и прогоном ветви I';

  Future<void> pumpApp(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      MemoriaApp(themeController: ThemeController(), services: services),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String section) async {
    await tester.tap(find.byKey(Key('nav-$section')));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  GalaxyMapState mapOf(WidgetTester tester) {
    return tester.state<GalaxyMapState>(find.byType(GalaxyMap));
  }

  Future<void> tapStar(WidgetTester tester, String id) async {
    final GalaxyMapState map = mapOf(tester);
    final int index = map.scene!.stars.indexWhere(
      (GalaxyStar star) => star.book.id == id,
    );
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
          map.scene!.placeOf(index),
    );
    await tester.pumpAndSettle();
  }

  group('SNO-F-MAP-01: ветвь II', () {
    testWidgets('SNO-F-MAP-01: «Галактика» стоит между «Полкой» и '
        '«Тестированием»', (WidgetTester tester) async {
      await pumpApp(tester, testServices(data: data));

      double at(String section) {
        return tester.getCenter(find.byKey(Key('nav-$section'))).dx;
      }

      expect(find.byKey(const Key('nav-galaxy')), findsOneWidget);
      expect(find.text('Галактика'), findsWidgets);
      expect(at('library'), lessThan(at('galaxy')));
      expect(at('galaxy'), lessThan(at('testing')));
      expect(at('testing'), lessThan(at('settings')));
      expect(find.byKey(const Key('nav-device')), findsNothing);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: на широком окне раздел — в верхней '
        'полосе', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(1280, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('nav-top')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('nav-top')),
          matching: find.byKey(const Key('nav-galaxy')),
        ),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: раздел показывает книги полки картой', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpApp(tester, testServices(data: data));
      // Пока раздел не открыли, карта с устройства не читается.
      expect(find.byType(GalaxyMap), findsNothing);

      await open(tester, 'galaxy');

      expect(find.byType(GalaxyMap), findsOneWidget);
      expect(mapOf(tester).scene!.stars, hasLength(6));
      // Навигация на месте: из раздела уходят ею.
      expect(find.byKey(const Key('nav-bottom')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: книга, открытая с карты, останавливает '
        'подготовку книг и считает своё время', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      final ShownReading reading = ShownReading(data);
      int now = 0;
      final BookTimes times = BookTimes(
        settings: MemorySettings(),
        key: 'sno.book_times',
        nowMs: () => now,
      );
      await pumpApp(
        tester,
        testServices(data: data, shelfReading: reading, bookTimes: times),
      );
      await open(tester, 'galaxy');
      await tapStar(tester, 'a2');

      await tester.tap(find.byKey(const Key('galaxy-read')));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(reading.held, isTrue, reason: 'движок PDF отдан странице');
      expect(times.open, 'a2');
      now += 60000;

      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await settle(tester);

      expect(reading.held, isFalse);
      expect(times.times, <String, int>{'a2': 60000});
      // Вернулись в «Галактику», а не на полку.
      expect(find.byType(GalaxyMap), findsOneWidget);
      expect(find.byKey(const Key('galaxy-card-a2')), findsOneWidget);
      expect(find.textContaining('читали 1 мин'), findsOneWidget);

      await unmount(tester);
      reading.dispose();
    });

    testWidgets('SNO-F-MAP-01: «назад» из раздела ведёт на «Полку»', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpApp(tester, testServices(data: data));
      await open(tester, 'galaxy');
      final LibraryScreen before = tester.widget(
        find.byType(LibraryScreen, skipOffstage: false),
      );
      expect(before.visible, isFalse);

      await tester.binding.handlePopRoute();
      await settle(tester);

      final LibraryScreen shelf = tester.widget(find.byType(LibraryScreen));
      expect(shelf.visible, isTrue);
      final GalaxyScreen galaxy = tester.widget(
        find.byType(GalaxyScreen, skipOffstage: false),
      );
      expect(galaxy.visible, isFalse);

      await unmount(tester);
    });
  }, skip: Sno.galaxy ? false : galaxyOnly);

  group('SNO-F-MAP-01: основное приложение и ветвь I', () {
    testWidgets('SNO-F-MAP-01: раздела «Галактика» в них нет', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpApp(tester, testServices(data: data));

      expect(find.byKey(const Key('nav-galaxy')), findsNothing);
      expect(find.text('Галактика'), findsNothing);
      expect(find.byType(GalaxyScreen), findsNothing);
      expect(find.byKey(const Key('nav-library')), findsOneWidget);
      expect(find.byKey(const Key('nav-settings')), findsOneWidget);

      await unmount(tester);
    });
  }, skip: Sno.galaxy ? othersOnly : false);
}
