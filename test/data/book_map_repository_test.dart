import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/domain/map/book_map.dart';

import 'test_data.dart';

/// F-MAP-02, SNO-F-MAP-01: карта книг в базе устройства.
///
/// Настоящая база в памяти: здесь проверяется то, чего хранилище в
/// памяти не покажет, — что карта ложится целиком, что прежняя уходит
/// вместе с новой и что место книги уходит вместе с книгой.
void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    for (final String id in <String>['a', 'b', 'c']) {
      await data.library.save(testBook(id: id, hash: 'hash-$id'));
    }
  });

  tearDown(() async {
    await data.close();
  });

  StoredBookMap mapOf(String key, Map<String, List<double>> places) {
    return StoredBookMap(
      layoutKey: key,
      version: kBookMapVersion,
      points: <String, MapPoint>{
        for (final MapEntry<String, List<double>> entry in places.entries)
          entry.key: MapPoint(
            key: 'hash-${entry.key}',
            x: entry.value[0],
            y: entry.value[1],
          ),
      },
    );
  }

  test('F-MAP-02: пока карту не считали, её нет', () async {
    expect(await data.bookMap.load(), isNull);
  });

  test('F-MAP-02: карта пишется и читается той же', () async {
    await data.bookMap.replace(
      mapOf('набор-1', <String, List<double>>{
        'a': <double>[0.25, -0.5],
        'b': <double>[-1, 1],
        'c': <double>[0.1234567890123, 0],
      }),
    );
    final StoredBookMap stored = (await data.bookMap.load())!;
    expect(stored.layoutKey, 'набор-1');
    expect(stored.version, kBookMapVersion);
    expect(stored.points, <String, MapPoint>{
      'a': const MapPoint(key: 'hash-a', x: 0.25, y: -0.5),
      'b': const MapPoint(key: 'hash-b', x: -1, y: 1),
      // Координата лежит числом двойной точности — без округления.
      'c': const MapPoint(key: 'hash-c', x: 0.1234567890123, y: 0),
    });
  });

  test('F-MAP-02: новая карта ложится вместо прежней целиком', () async {
    await data.bookMap.replace(
      mapOf('набор-1', <String, List<double>>{
        'a': <double>[0, 0],
        'b': <double>[1, 1],
        'c': <double>[-1, -1],
      }),
    );
    await data.bookMap.replace(
      mapOf('набор-2', <String, List<double>>{
        'a': <double>[0.5, 0.5],
        'b': <double>[-0.5, -0.5],
      }),
    );
    final StoredBookMap stored = (await data.bookMap.load())!;
    expect(stored.layoutKey, 'набор-2');
    // Книги «c» в новой карте нет — нет и её прежнего места.
    expect(stored.points.keys.toSet(), <String>{'a', 'b'});
    expect(stored.points['a'], const MapPoint(key: 'hash-a', x: 0.5, y: 0.5));
  });

  test('F-MAP-02: карта с книгой, которой нет, не ложится вовсе', () async {
    final StoredBookMap first = mapOf('набор-1', <String, List<double>>{
      'a': <double>[0, 0],
      'b': <double>[1, 1],
    });
    await data.bookMap.replace(first);
    // Книги «призрак» в базе нет: запись её места нарушает внешний ключ.
    await expectLater(
      data.bookMap.replace(
        mapOf('набор-2', <String, List<double>>{
          'a': <double>[0.5, 0.5],
          'призрак': <double>[0, 0],
        }),
      ),
      throwsA(anything),
    );
    // Прежняя карта осталась как была: половины карты в базе не бывает.
    final StoredBookMap stored = (await data.bookMap.load())!;
    expect(stored.layoutKey, 'набор-1');
    expect(stored.points, first.points);
  });

  test('F-MAP-02: карта стирается', () async {
    await data.bookMap.replace(
      mapOf('набор-1', <String, List<double>>{
        'a': <double>[0, 0],
      }),
    );
    await data.bookMap.clear();
    expect(await data.bookMap.load(), isNull);
  });

  test('F-MAP-02: вычищена книга — ушло и её место на карте', () async {
    await data.bookMap.replace(
      mapOf('набор-1', <String, List<double>>{
        'a': <double>[0, 0],
        'b': <double>[1, 1],
      }),
    );
    // Снятая с полки книга — строка с надгробием: её место ещё лежит.
    await data.library.delete('a');
    expect((await data.bookMap.load())!.points.keys, contains('a'));
    await data.library.purgeDeleted();
    expect((await data.bookMap.load())!.points.keys.toSet(), <String>{'b'});
  });
}
