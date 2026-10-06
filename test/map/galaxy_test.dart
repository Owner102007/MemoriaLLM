import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/galaxy.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_layout.dart';

import '../data/test_data.dart';
import '../support/galaxy_shelf.dart';

/// F-MAP-06, F-MAP-11, SNO-F-MAP-01: карта для экрана — из того, что
/// лежит на устройстве. Настоящая база в памяти.
void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  Future<Galaxy> load({Map<String, int> times = const <String, int>{}}) {
    return loadGalaxy(
      library: data.library,
      categories: data.categories,
      store: data.bookMap,
      times: times,
    );
  }

  group('F-MAP-11: когда карты нет', () {
    test('F-MAP-11: пустая полка — книг мало', () async {
      final Galaxy galaxy = await load();
      expect(galaxy.status, GalaxyStatus.tooFew);
      expect(galaxy.books, 0);
      expect(galaxy.stars, isEmpty);
    });

    test('F-MAP-11: книг меньше, чем берёт расчёт, — книг мало, даже '
        'если карта лежит', () async {
      expect(kMinMapBooks, 3);
      await seedGalaxy(data, kTwoGroups.sublist(0, 2));
      final Galaxy galaxy = await load();
      expect(galaxy.status, GalaxyStatus.tooFew);
      expect(galaxy.books, 2);
    });

    test('F-MAP-11: книги есть, карты нет', () async {
      await seedGalaxy(data, kTwoGroups, withMap: false);
      final Galaxy galaxy = await load();
      expect(galaxy.status, GalaxyStatus.noMap);
      expect(galaxy.books, 6);
      expect(galaxy.stars, isEmpty);
    });

    test('F-MAP-11: карта другой версии расчёта — не карта', () async {
      await seedGalaxy(data, kTwoGroups, version: kBookMapVersion + 1);
      expect((await load()).status, GalaxyStatus.noMap);
    });

    test('F-MAP-11: ни одна книга полки места не имеет — карты нет', () async {
      await seedGalaxy(data, <ShelfStar>[
        for (final ShelfStar star in kTwoGroups)
          ShelfStar(star.id, star.title, star.x, star.y, onMap: false),
      ]);
      // Чужие точки не дают карте лечь пустой.
      await data.bookMap.replace(
        const StoredBookMap(
          layoutKey: 'набор',
          version: kBookMapVersion,
          points: <String, MapPoint>{
            'a1': MapPoint(key: 'другой-файл', x: 0, y: 0),
          },
        ),
      );
      expect((await load()).status, GalaxyStatus.noMap);
    });
  });

  group('F-MAP-06: карта есть', () {
    test('F-MAP-06: у каждой книги полки — звезда на своём месте', () async {
      await seedGalaxy(data, kTwoGroups);
      final Galaxy galaxy = await load();

      expect(galaxy.status, GalaxyStatus.ready);
      expect(galaxy.books, 6);
      expect(galaxy.missing, 0);
      expect(galaxy.stars.map((GalaxyStar star) => star.book.id), <String>[
        'a1',
        'a2',
        'a3',
        'm1',
        'm2',
        'm3',
      ], reason: 'по возрастанию отпечатка файла, а не по полке');
      final GalaxyStar first = galaxy.stars.first;
      expect(first.x, -0.8);
      expect(first.y, -0.6);
      expect(first.book.title, 'Клиническая ангиология');
      expect(first.ms, 0);
    });

    test('SNO-F-MAP-01: группа звезды — категория полки', () async {
      await seedGalaxy(data, <ShelfStar>[
        ...kTwoGroups,
        const ShelfStar('z1', 'Ничья книга', 0, 0.9),
      ]);
      final Galaxy galaxy = await load();

      expect(
        <String, String>{
          for (final GalaxyStar star in galaxy.stars) star.book.id: star.group,
        },
        <String, String>{
          'a1': 'Ангиология',
          'a2': 'Ангиология',
          'a3': 'Ангиология',
          'm1': 'Математика',
          'm2': 'Математика',
          'm3': 'Математика',
          'z1': kUncategorizedTitle,
        },
      );
    });

    test('SNO-F-MAP-01: у звезды — время, проведённое в её книге', () async {
      await seedGalaxy(data, kTwoGroups);
      final Galaxy galaxy = await load(
        times: <String, int>{'a2': 300000, 'm3': 60000, 'нет-такой': 5},
      );

      expect(
        <String, int>{
          for (final GalaxyStar star in galaxy.stars) star.book.id: star.ms,
        },
        <String, int>{
          'a1': 0,
          'a2': 300000,
          'a3': 0,
          'm1': 0,
          'm2': 0,
          'm3': 60000,
        },
      );
    });

    test('F-MAP-11: книга, добавленная после расчёта, звезды не имеет и '
        'названа в счёте', () async {
      await seedGalaxy(data, <ShelfStar>[
        ...kTwoGroups,
        const ShelfStar('n1', 'Новая книга', 0, 0, onMap: false),
      ]);
      final Galaxy galaxy = await load();

      expect(galaxy.status, GalaxyStatus.ready);
      expect(galaxy.books, 7);
      expect(galaxy.stars, hasLength(6));
      expect(galaxy.missing, 1);
    });

    test('F-MAP-06: место, посчитанное по другому файлу, книге не '
        'годится', () async {
      await seedGalaxy(data, kTwoGroups);
      // Книгу привязали к другому файлу: отпечаток у неё теперь другой.
      await data.library.save(
        (await data.library.bookById('a1'))!.copyWith(fileHash: 'новый-файл'),
      );
      final Galaxy galaxy = await load();

      expect(galaxy.stars.map((GalaxyStar star) => star.book.id), <String>[
        'a2',
        'a3',
        'm1',
        'm2',
        'm3',
      ]);
      expect(galaxy.missing, 1);
    });
  });
}
