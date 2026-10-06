import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/galaxy.dart';
import 'package:memoria/application/reading/book_times.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/library/category_style.dart';
import 'package:memoria/domain/map/map_view.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';
import 'package:memoria/sno/index/shelf_reading.dart';
import 'package:memoria/ui/galaxy/galaxy_painter.dart';
import 'package:memoria/ui/galaxy/galaxy_screen.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/galaxy_shelf.dart';
import '../support/recording_fakes.dart';
import '../support/shown_reading.dart';
import '../support/test_services.dart';

/// Сорок книг решёткой — левая половина в одной категории, правая в
/// другой: библиотека, у которой названия книг при наименьшем масштабе
/// не помещаются.
List<ShelfStar> fortyStars() {
  return <ShelfStar>[
    for (int i = 0; i < 40; i++)
      ShelfStar(
        'b${i.toString().padLeft(2, '0')}',
        'Книга номер $i',
        -0.9 + (i % 8) * (1.8 / 7),
        -0.9 + (i ~/ 8) * (1.8 / 4),
        category: i % 8 < 4 ? 'ang' : 'math',
      ),
  ];
}

/// F-MAP-06, F-MAP-07, F-MAP-08, F-MAP-11, SNO-F-MAP-01: раздел
/// «Галактика» — экран SCR-04.
///
/// Раздел получает службы, а не признак сборки, поэтому проверяется
/// основным прогоном: настоящая база в памяти, карта положена тестом.
/// Что раздел стоит в навигации ветви II и только её — в
/// `test/sno/galaxy_section_test.dart`.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<void> pumpGalaxy(
    WidgetTester tester,
    AppServices services, {
    bool visible = true,
    ValueChanged<bool>? onReading,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GalaxyScreen(
          services: services,
          visible: visible,
          onReading: onReading,
          canRelink: false,
          models: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
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
    expect(index, isNonNegative, reason: 'книга $id на карте');
    return tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
        scene.placeOf(index);
  }

  double radiusOf(WidgetTester tester, String id) {
    final GalaxyScene scene = mapOf(tester).scene!;
    return scene.radii[scene.stars.indexWhere(
      (GalaxyStar star) => star.book.id == id,
    )];
  }

  Future<void> tapStar(WidgetTester tester, String id) async {
    await tester.tapAt(placeOf(tester, id));
    await tester.pumpAndSettle();
  }

  /// Крутит колесо мыши над точкой экрана [at]: минус — к себе,
  /// приближение.
  Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  void expectLabelsFit(WidgetTester tester) {
    final GalaxyScene scene = mapOf(tester).scene!;
    final List<GalaxyLabel> labels = scene.labels;
    expect(labels.length, lessThanOrEqualTo(kMaxLabels));
    final Rect window = Offset.zero &
        Size(scene.viewport.width, scene.viewport.height);
    for (int i = 0; i < labels.length; i++) {
      expect(
        window.contains(labels[i].rect.topLeft) &&
            labels[i].rect.right <= window.right &&
            labels[i].rect.bottom <= window.bottom,
        isTrue,
        reason: '«${labels[i].text}» целиком в окне',
      );
      for (int j = i + 1; j < labels.length; j++) {
        expect(
          labels[i].rect.overlaps(labels[j].rect),
          isFalse,
          reason: '«${labels[i].text}» и «${labels[j].text}»',
        );
      }
    }
  }

  group('F-MAP-11: вместо карты — слова', () {
    testWidgets('F-MAP-11: книг мало — сказано, сколько нужно и сколько '
        'есть', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups.sublist(0, 2));
      await pumpGalaxy(tester, testServices(data: data));

      expect(find.byKey(const Key('galaxy-too-few')), findsOneWidget);
      expect(find.text('Для карты нужно не меньше 3 книг.'), findsOneWidget);
      expect(find.text('Сейчас на полке: 2.'), findsOneWidget);
      expect(find.byType(GalaxyMap), findsNothing);
      expect(find.text('Галактика'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-MAP-11: пустая полка названа пустой', (
      WidgetTester tester,
    ) async {
      await pumpGalaxy(tester, testServices(data: data));

      expect(find.text('На полке книг нет.'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-MAP-11: карта не посчитана — сказано, и предложено '
        'посчитать', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups, withMap: false);
      final ShownReading reading = ShownReading(data);
      addTearDown(reading.dispose);
      await pumpGalaxy(
        tester,
        testServices(data: data, shelfReading: reading),
      );

      expect(find.byKey(const Key('galaxy-no-map')), findsOneWidget);
      expect(find.text('Карта ещё не посчитана.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('galaxy-action')));
      await tester.pump();
      expect(reading.starts, 1);

      await unmount(tester);
    });

    testWidgets('F-MAP-11: без подготовки книг посчитать не предлагают', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups, withMap: false);
      await pumpGalaxy(tester, testServices(data: data));

      expect(find.byKey(const Key('galaxy-no-map')), findsOneWidget);
      expect(find.byKey(const Key('galaxy-action')), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-MAP-11: пока книги читаются — ход вместо карты, а '
        'потом карта', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      final ShownReading reading = ShownReading(data);
      addTearDown(reading.dispose);
      reading.show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.reading,
          booksDone: 9,
          booksTotal: 14,
        ),
      );
      await pumpGalaxy(
        tester,
        testServices(data: data, shelfReading: reading),
      );

      expect(find.byKey(const Key('galaxy-preparing')), findsOneWidget);
      expect(find.text('Книги ещё читаются · 9 из 14'), findsOneWidget);
      expect(
        find.text('Карта появится, когда будут прочитаны все.'),
        findsOneWidget,
      );
      // Прежняя карта лежит на устройстве, но показана не она: текст
      // книг ещё читается, и она устарела.
      expect(find.byType(GalaxyMap), findsNothing);

      reading.show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.mapping,
          mapDone: 7,
          mapTotal: 14,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Считаю карту · 7 из 14'), findsOneWidget);

      reading.show(const ShelfReadingProgress(phase: ShelfReadingPhase.done));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('galaxy-preparing')), findsNothing);
      expect(find.byType(GalaxyMap), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-MAP-06: раздел, который не открывали, карту не '
        'читает', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      final AppServices services = testServices(data: data);
      await pumpGalaxy(tester, services, visible: false);

      expect(find.byKey(const Key('galaxy-loading')), findsOneWidget);
      expect(find.byType(GalaxyMap), findsNothing);

      await pumpGalaxy(tester, services);
      expect(find.byType(GalaxyMap), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-MAP-11: книга без места на карте названа в счёте', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, <ShelfStar>[
        ...kTwoGroups,
        const ShelfStar('n1', 'Новая книга', 0, 0, onMap: false),
      ]);
      await pumpGalaxy(tester, testServices(data: data));

      expect(find.byType(GalaxyMap), findsOneWidget);
      expect(find.byKey(const Key('galaxy-missing')), findsOneWidget);
      expect(
        find.textContaining('Книг без места на карте: 1.'),
        findsOneWidget,
      );
      expect(mapOf(tester).scene!.stars, hasLength(6));

      await unmount(tester);
    });
  });

  group('F-MAP-07: карта', () {
    testWidgets('F-MAP-06: все книги полки — точками, группы подписаны '
        'названиями категорий', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));

      final GalaxyScene scene = mapOf(tester).scene!;
      expect(scene.stars, hasLength(6));
      expect(scene.viewport.camera.scale, kMapMinScale);
      final Size size = tester.getSize(find.byKey(const Key('galaxy-map')));
      for (int i = 0; i < scene.stars.length; i++) {
        final Offset at = scene.placeOf(i);
        expect(
          (Offset.zero & size).deflate(scene.radii[i]).contains(at),
          isTrue,
          reason: '«${scene.stars[i].book.title}» целиком в окне',
        );
      }
      final Set<String> groups = <String>{
        for (final GalaxyLabel label in scene.labels)
          if (label.group) label.text,
      };
      expect(groups, <String>{'Ангиология', 'Математика'});
      expectLabelsFit(tester);
      // Пока не читали ни одну книгу, точки одинаковы.
      expect(scene.radii.toSet(), hasLength(1));

      await unmount(tester);
    });

    testWidgets('F-MAP-07: книги одной категории — одного цвета', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, <ShelfStar>[
        ...kTwoGroups,
        const ShelfStar('z1', 'Ничья книга', 0, 0.9),
      ]);
      await pumpGalaxy(tester, testServices(data: data));

      final GalaxyScene scene = mapOf(tester).scene!;
      final Map<String, Set<Color>> byGroup = <String, Set<Color>>{};
      for (int i = 0; i < scene.stars.length; i++) {
        byGroup
            .putIfAbsent(scene.stars[i].group, () => <Color>{})
            .add(scene.colours[i]);
      }
      expect(byGroup.keys.toSet(), <String>{
        'Ангиология',
        'Математика',
        kUncategorizedTitle,
      });
      for (final Set<Color> colours in byGroup.values) {
        expect(colours, hasLength(1));
      }

      await unmount(tester);
    });

    test('F-MAP-07: точка любого оттенка видна на любой теме', () {
      for (final AppPalette palette in appPalettes.values) {
        for (int hue = 0; hue < kCategoryHues; hue++) {
          final CategoryStyle style = CategoryStyle(
            seed: 0,
            pattern: ShelfPattern.values.first,
            hueIndex: hue,
            phase: 0,
            acid: false,
          );
          expect(
            contrastRatio(style.starOn(palette), palette.background),
            greaterThanOrEqualTo(3),
            reason: 'тема «${palette.title}», оттенок $hue',
          );
        }
        // Книги без категории — вторичным цветом текста.
        expect(starArgbOf(kUncategorizedTitle, palette), palette.textSecondary);
        expect(
          contrastRatio(palette.textSecondary, palette.background),
          greaterThanOrEqualTo(3),
          reason: 'тема «${palette.title}», без категории',
        );
        expect(
          starArgbOf('Ангиология', palette),
          categoryStyleFor('Ангиология').starOn(palette),
        );
      }
    });

    testWidgets('F-MAP-07: колесо приближает к курсору', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));
      final Offset before = placeOf(tester, 'a2');

      await wheel(tester, before, -300);

      final MapCamera camera = mapOf(tester).viewport.camera;
      expect(camera.scale, closeTo(math.e, 1e-6));
      final Offset after = placeOf(tester, 'a2');
      expect((after - before).distance, lessThan(0.01));
      // Соседняя книга отъехала: карта приблизилась, а не сдвинулась.
      expect(
        (placeOf(tester, 'a1') - after).distance,
        greaterThan(100),
      );

      // Колесо от себя — обратно, и не дальше всей карты.
      await wheel(tester, before, 3000);
      expect(mapOf(tester).viewport.camera.scale, kMapMinScale);
      // И к себе — не ближе наибольшего масштаба.
      await wheel(tester, before, -30000);
      expect(mapOf(tester).viewport.camera.scale, kMapMaxScale);

      await unmount(tester);
    });

    testWidgets('F-MAP-07: карту двигают, взявшись за неё', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));
      final Offset centre = tester.getCenter(
        find.byKey(const Key('galaxy-map')),
      );
      await wheel(tester, centre, -300);
      final MapViewport before = mapOf(tester).viewport;

      final TestGesture gesture = await tester.startGesture(centre);
      // Первый шаг — порог жеста, второй — само движение.
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-50, 20));
      await gesture.up();
      await tester.pump();

      final MapViewport after = mapOf(tester).viewport;
      expect(after.camera.scale, before.camera.scale);
      expect(
        after.camera.cx - before.camera.cx,
        closeTo(50 / before.unit, 1e-6),
      );
      expect(
        after.camera.cy - before.camera.cy,
        closeTo(-20 / before.unit, 1e-6),
      );

      await unmount(tester);
    });

    testWidgets('F-MAP-08: двойное нажатие приближает вдвое', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));
      final Offset corner =
          tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
          const Offset(20, 20);

      await tester.tapAt(corner);
      await tester.pump();
      expect(mapOf(tester).viewport.camera.scale, kMapMinScale);
      await tester.tapAt(corner);
      await tester.pump();

      expect(mapOf(tester).viewport.camera.scale, kDoubleTapZoom);

      await unmount(tester);
    });

    testWidgets('F-MAP-07: названия книг появляются вблизи, подписей не '
        'больше двадцати четырёх, и они не пересекаются', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, fortyStars());
      await pumpGalaxy(tester, testServices(data: data));

      // Вся библиотека: подписаны только группы.
      GalaxyScene scene = mapOf(tester).scene!;
      expect(scene.stars, hasLength(40));
      expect(
        scene.labels.where((GalaxyLabel label) => !label.group),
        isEmpty,
      );
      expect(
        scene.labels.map((GalaxyLabel label) => label.text).toSet(),
        <String>{'Ангиология', 'Математика'},
      );
      expectLabelsFit(tester);

      final Offset centre = tester.getCenter(
        find.byKey(const Key('galaxy-map')),
      );
      for (final double dy in <double>[-300, -300]) {
        await wheel(tester, centre, dy);
        expectLabelsFit(tester);
      }

      scene = mapOf(tester).scene!;
      final List<GalaxyLabel> titles = scene.labels
          .where((GalaxyLabel label) => !label.group)
          .toList();
      expect(titles, isNotEmpty);
      for (final GalaxyLabel label in titles) {
        expect(label.text, startsWith('Книга номер '));
        expect(label.rect.width, lessThanOrEqualTo(kGalaxyTitleWidth));
      }

      await unmount(tester);
    });

    testWidgets('ALG-MAP-12: кадр на триста книг собирается в бюджет', (
      WidgetTester tester,
    ) async {
      // Решётка двадцать на пятнадцать: сколько книг в окне при данном
      // приближении, известно заранее.
      await seedGalaxy(data, <ShelfStar>[
        for (int i = 0; i < 300; i++)
          ShelfStar(
            'b${i.toString().padLeft(3, '0')}',
            'Учебник по предмету номер $i',
            -1 + (i % 20) * (2 / 19),
            -1 + (i ~/ 20) * (2 / 14),
            category: i % 20 < 10 ? 'ang' : 'math',
          ),
      ]);
      await pumpGalaxy(tester, testServices(data: data));
      final Offset centre = tester.getCenter(
        find.byKey(const Key('galaxy-map')),
      );
      // Наименьшее приближение, при котором у точек уже стоят названия:
      // в окне при нём больше всего книг с подписями.
      await wheel(tester, centre, -630);
      final GalaxyScene shown = mapOf(tester).scene!;
      expect(shown.labels.any((GalaxyLabel label) => !label.group), isTrue);

      final Stopwatch watch = Stopwatch()..start();
      const int rounds = 30;
      for (int i = 0; i < rounds; i++) {
        GalaxyScene(
          stars: shown.stars,
          viewport: shown.viewport,
          palette: shown.palette,
          groupStyle: const TextStyle(fontSize: 14),
          titleStyle: const TextStyle(fontSize: 12),
        );
      }
      watch.stop();
      final double perFrame = watch.elapsedMicroseconds / rounds / 1000;
      stdout.writeln(
        'ЗАМЕР ALG-MAP-12 | кадр карты на 300 книг | бюджет 16 мс | '
        '${perFrame.toStringAsFixed(2)} мс на кадр',
      );
      expect(perFrame, lessThan(16), reason: 'кадр в 60 Гц');
      expectLabelsFit(tester);

      await unmount(tester);
    });
  });

  group('F-MAP-08: карточка книги', () {
    testWidgets('F-MAP-08: нажатие по точке — карточка этой книги, мимо '
        '— карточки нет', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));
      expect(find.byType(GalaxyBookCard), findsNothing);

      await tapStar(tester, 'a2');

      expect(find.byKey(const Key('galaxy-card-a2')), findsOneWidget);
      expect(find.text('Сосудистая хирургия'), findsOneWidget);
      expect(find.text('Автор a2 · Ангиология'), findsOneWidget);
      expect(find.byKey(const Key('galaxy-read')), findsOneWidget);
      // Книгу не открывали: ни прочитанного, ни времени.
      expect(find.byKey(const Key('galaxy-card-facts')), findsNothing);
      expect(mapOf(tester).selectedId, 'a2');

      // Другая точка — другая карточка.
      await tapStar(tester, 'm1');
      expect(find.byKey(const Key('galaxy-card-a2')), findsNothing);
      expect(find.byKey(const Key('galaxy-card-m1')), findsOneWidget);
      expect(find.text('Математический анализ'), findsOneWidget);

      // Мимо точек — карточки нет.
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('galaxy-map'))) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GalaxyBookCard), findsNothing);
      expect(mapOf(tester).selectedId, isNull);

      await unmount(tester);
    });

    testWidgets('F-MAP-08: попадание находит ту самую книгу на трёх '
        'уровнях зума', (WidgetTester tester) async {
      await seedGalaxy(data, fortyStars());
      await pumpGalaxy(tester, testServices(data: data));
      final GalaxyMapState map = mapOf(tester);

      for (final double dy in <double>[0, -600, -600]) {
        if (dy != 0) {
          // Приближение — к книге посреди карты: она остаётся в окне.
          await wheel(tester, placeOf(tester, 'b19'), dy);
        }
        final GalaxyScene scene = map.scene!;
        final Rect window = Offset.zero &
            Size(scene.viewport.width, scene.viewport.height);
        int checked = 0;
        for (int i = 0; i < scene.stars.length; i++) {
          final Offset at = scene.placeOf(i);
          if (!window.contains(at)) {
            continue;
          }
          checked++;
          expect(
            map.starAt(at),
            i,
            reason: 'масштаб ${scene.viewport.camera.scale}, книга $i',
          );
          // Чуть в стороне от середины точки — всё ещё она.
          expect(map.starAt(at + const Offset(2, -2)), i);
        }
        expect(checked, greaterThan(0));
      }
      expect(map.viewport.camera.scale, greaterThan(40));

      await unmount(tester);
    });

    testWidgets('F-MAP-08: крестик закрывает карточку', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));
      await tapStar(tester, 'a1');
      expect(find.byType(GalaxyBookCard), findsOneWidget);

      await tester.tap(find.byKey(const Key('galaxy-card-close')));
      await tester.pumpAndSettle();

      expect(find.byType(GalaxyBookCard), findsNothing);

      await unmount(tester);
    });

    testWidgets('F-MAP-08: в карточке — сколько книги прочитано', (
      WidgetTester tester,
    ) async {
      await seedGalaxy(data, kTwoGroups);
      await data.reading.savePosition(
        const ReadingPosition(bookId: 'a2', page: 34, progress: 0.34),
      );
      await pumpGalaxy(tester, testServices(data: data));

      await tapStar(tester, 'a2');

      expect(find.text('прочитано 34 %'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('F-MAP-08: на широком окне карточка стоит рядом с '
        'точкой', (WidgetTester tester) async {
      tester.view.physicalSize =
          const Size(1280, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));

      await tapStar(tester, 'a2');

      final Rect card = tester.getRect(find.byKey(const Key('galaxy-card-a2')));
      final Offset star = placeOf(tester, 'a2');
      expect(card.width, kGalaxyCardWidth);
      expect(card.left, greaterThan(star.dx), reason: 'справа есть место');
      expect(card.left - star.dx, lessThan(40));
      expect(card.contains(star), isFalse, reason: 'точку карточка не закрыла');

      // У правого края справа места нет — карточка встаёт слева.
      await tapStar(tester, 'm2');
      final Rect second = tester.getRect(
        find.byKey(const Key('galaxy-card-m2')),
      );
      final Offset edge = placeOf(tester, 'm2');
      expect(second.right, lessThan(edge.dx));
      expect(second.contains(edge), isFalse);

      await unmount(tester);
    });

    testWidgets('F-MAP-08: на узком экране карточка — у нижнего края во '
        'всю ширину', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      await pumpGalaxy(tester, testServices(data: data));

      await tapStar(tester, 'a1');

      final Rect card = tester.getRect(find.byKey(const Key('galaxy-card-a1')));
      final Rect map = tester.getRect(find.byKey(const Key('galaxy-map')));
      expect(card.left, map.left + 8);
      expect(card.right, map.right - 8);
      expect(card.bottom, map.bottom - 8);

      await unmount(tester);
    });
  });

  group('SNO-F-MAP-01: чтение с карты', () {
    testWidgets('F-MAP-08: «Читать» открывает книгу, а возврат приводит '
        'на то же место карты', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      final List<bool> reading = <bool>[];
      await pumpGalaxy(
        tester,
        testServices(data: data),
        onReading: reading.add,
      );
      await wheel(tester, placeOf(tester, 'a2'), -300);
      final MapCamera camera = mapOf(tester).viewport.camera;
      await tapStar(tester, 'a2');

      await tester.tap(find.byKey(const Key('galaxy-read')));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderScreen), findsOneWidget);
      final ReaderScreen reader = tester.widget(find.byType(ReaderScreen));
      expect(reader.book.id, 'a2');
      expect(reader.openedVia, 'galaxy');
      expect(reading, <bool>[true]);

      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ReaderScreen), findsNothing);
      expect(reading, <bool>[true, false]);
      expect(mapOf(tester).viewport.camera, camera);
      expect(find.byKey(const Key('galaxy-card-a2')), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: точка книги, которую читали, крупнее '
        'остальных', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      int now = 0;
      final BookTimes times = BookTimes(
        settings: MemorySettings(),
        key: 'sno.book_times',
        nowMs: () => now,
      );
      await pumpGalaxy(tester, testServices(data: data, bookTimes: times));
      final MapCamera camera = mapOf(tester).viewport.camera;
      final Offset place = placeOf(tester, 'a2');
      expect(radiusOf(tester, 'a2'), radiusOf(tester, 'a1'));

      await tapStar(tester, 'a2');
      await tester.tap(find.byKey(const Key('galaxy-read')));
      await tester.pumpAndSettle();
      expect(times.open, 'a2');
      // Пять минут в книге.
      now += 300000;
      Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
      await tester.pumpAndSettle();

      expect(times.open, isNull);
      expect(times.times, <String, int>{'a2': 300000});
      // Всё время — в одной книге: её точка наибольшая, остальные
      // остались как были.
      final double read = radiusOf(tester, 'a2');
      final double unread = radiusOf(tester, 'a1');
      expect(
        (read * read) / (unread * unread),
        closeTo(kStarAreaGain, 1e-9),
      );
      expect(radiusOf(tester, 'm3'), unread);
      // Расположение от времени чтения не зависит.
      expect(placeOf(tester, 'a2'), place);
      expect(mapOf(tester).viewport.camera, camera);
      expect(find.textContaining('читали 5 мин'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('SNO-F-MAP-01: размер точек считается, когда раздел '
        'открывают', (WidgetTester tester) async {
      await seedGalaxy(data, kTwoGroups);
      int now = 0;
      final BookTimes times = BookTimes(
        settings: MemorySettings(),
        key: 'sno.book_times',
        nowMs: () => now,
      );
      final AppServices services = testServices(data: data, bookTimes: times);
      await pumpGalaxy(tester, services);
      final double unread = radiusOf(tester, 'm1');

      // Книгу прочли, открыв её с полки: раздел в это время не на
      // экране.
      await pumpGalaxy(tester, services, visible: false);
      times.opened('m1');
      now += 120000;
      times.closed('m1');
      await tester.pumpAndSettle();
      expect(radiusOf(tester, 'm1'), unread, reason: 'на глазах не растёт');

      await pumpGalaxy(tester, services);

      expect(radiusOf(tester, 'm1'), greaterThan(unread));
      expect(radiusOf(tester, 'a1'), unread);

      await unmount(tester);
    });

    test('SNO-F-MAP-01: время в книге — словами', () {
      expect(describeReadTime(0), '');
      expect(describeReadTime(-5), '');
      expect(describeReadTime(59999), 'читали меньше минуты');
      expect(describeReadTime(60000), 'читали 1 мин');
      expect(describeReadTime(12 * 60000 + 59000), 'читали 12 мин');
      expect(describeReadTime(60 * 60000), 'читали 1 ч 0 мин');
      expect(describeReadTime(135 * 60000), 'читали 2 ч 15 мин');
    });
  });
}
