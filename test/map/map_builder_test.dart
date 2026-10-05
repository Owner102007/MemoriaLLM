import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/reading/page_text.dart';

import '../data/test_data.dart';

/// F-MAP-02, SNO-F-MAP-01: расчёт карты поверх кэша текста и базы.
///
/// База настоящая, в памяти; мешки и раскладка считаются на месте, без
/// изолята, — кроме одного теста, который проверяет именно изолят.
void main() {
  late AppData data;

  setUp(() async {
    data = await openTestData();
    const Map<String, String> categories = <String, String>{
      'angio': 'Ангиология',
      'math': 'Математика',
    };
    int position = 0;
    for (final MapEntry<String, String> entry in categories.entries) {
      await data.categories.save(
        BookCategory(
          id: entry.key,
          title: entry.value,
          position: position++,
          createdAt: DateTime.utc(2026, 10, 5),
        ),
      );
    }
  });

  tearDown(() async {
    await data.close();
  });

  MapBuilder builder({BagRunner? bags, MapRunner? layout}) {
    return MapBuilder(
      library: data.library,
      categories: data.categories,
      texts: data.pageTexts,
      store: data.bookMap,
      bags: bags ?? (BagRequest request) async => bagOfBook(request),
      layout: layout ?? (List<BookBag> found) async => buildBookMap(found),
    );
  }

  Future<void> addBook(
    String id, {
    String? category,
    List<String> pages = const <String>[],
    String? title,
  }) async {
    await data.library.save(
      testBook(id: id, title: title ?? 'Том $id', hash: 'hash-$id'),
    );
    if (category != null) {
      await placeBook(data, id, category);
    }
    if (pages.isNotEmpty) {
      await data.pageTexts.savePageTexts(
        PageTextKey(bookId: id, fingerprint: 'hash-$id'),
        <int, String>{for (int i = 0; i < pages.length; i++) i + 1: pages[i]},
      );
    }
  }

  /// Шесть книг: три про сосуды, три про интегралы.
  Future<void> addLibrary() async {
    for (final String id in <String>['a1', 'a2', 'a3']) {
      await addBook(
        id,
        category: 'angio',
        pages: <String>[
          'Артерия несёт кровь от сердца, вена — к сердцу.',
          'Капилляр соединяет артерию и вену; сосуд $id.',
        ],
      );
    }
    for (final String id in <String>['m1', 'm2', 'm3']) {
      await addBook(
        id,
        category: 'math',
        pages: <String>[
          'Интеграл функции есть предел интегральных сумм.',
          'Производная функции и ряд Тейлора; задача $id.',
        ],
      );
    }
  }

  test('F-MAP-02: карта считается по тексту из кэша и ложится в базу', () async {
    await addLibrary();
    final MapBuilder map = builder();
    final MapPlan plan = await map.plan();
    expect(plan.upToDate, isFalse);
    final List<String> hashes = <String>[
      for (final MapSource source in plan.sources) source.book.fileHash,
    ];
    expect(hashes, <String>[
      'hash-a1',
      'hash-a2',
      'hash-a3',
      'hash-m1',
      'hash-m2',
      'hash-m3',
    ]);
    expect(plan.sources.first.group, 'Ангиология');
    expect(plan.sources.first.cachedPages, 2);
    expect(plan.sources.last.group, 'Математика');

    final List<List<int>> steps = <List<int>>[];
    final MapOutcome outcome = await map.build(
      plan,
      onProgress: (int done, int total) => steps.add(<int>[done, total]),
    );
    expect(outcome.kind, MapOutcomeKind.built);
    expect(outcome.books, 6);
    expect(outcome.groups, 2);
    expect(outcome.fingerprint, hasLength(8));
    expect(steps.last, <int>[6, 6]);
    expect(steps, hasLength(6));

    final StoredBookMap stored = (await data.bookMap.load())!;
    expect(stored.layoutKey, plan.key);
    expect(stored.version, kBookMapVersion);
    expect(stored.points.keys.toSet(), <String>{
      'a1',
      'a2',
      'a3',
      'm1',
      'm2',
      'm3',
    });
    // Место лежит под идентификатором книги, а несёт отпечаток файла.
    expect(stored.points['m2']!.key, 'hash-m2');
    // Книги одной категории стоят вместе: ближайшая к «a1» — тоже «a».
    double distance(String a, String b) {
      final MapPoint p = stored.points[a]!;
      final MapPoint q = stored.points[b]!;
      return (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
    }

    for (final String other in <String>['m1', 'm2', 'm3']) {
      expect(distance('a1', 'a2'), lessThan(distance('a1', other)));
    }
  });

  test('F-MAP-04: карта стабильна — второй раз не считается', () async {
    await addLibrary();
    int layouts = 0;
    final MapBuilder map = builder(
      layout: (List<BookBag> found) async {
        layouts++;
        return buildBookMap(found);
      },
    );
    final MapOutcome first = await map.build(await map.plan());
    final MapPlan again = await map.plan();
    expect(again.upToDate, isTrue);
    expect(again.current!.kind, MapOutcomeKind.built);
    expect(again.current!.books, 6);
    expect(again.current!.groups, 2);
    // Отпечаток лежащей карты тот же, что у только что посчитанной.
    expect(again.current!.fingerprint, first.fingerprint);
    expect(layouts, 1);
  });

  test('F-MAP-04: карта устаревает, когда меняется то, по чему она '
      'посчитана', () async {
    await addLibrary();
    final MapBuilder map = builder();
    final MapPlan plan = await map.plan();
    await map.build(plan);

    // Книга переехала в другую категорию.
    await placeBook(data, 'a3', 'math');
    final MapPlan moved = await map.plan();
    expect(moved.upToDate, isFalse);
    expect(moved.key, isNot(plan.key));
    await map.build(moved);
    expect((await map.plan()).upToDate, isTrue);

    // У книги запомнена ещё одна страница.
    await data.pageTexts.savePageTexts(
      const PageTextKey(bookId: 'm1', fingerprint: 'hash-m1'),
      <int, String>{3: 'Ещё страница про интеграл.'},
    );
    final MapPlan longer = await map.plan();
    expect(longer.upToDate, isFalse);
    expect(longer.key, isNot(moved.key));
    await map.build(longer);

    // На полку встала новая книга.
    await addBook('m4', category: 'math', pages: <String>['Предел.']);
    final MapPlan grown = await map.plan();
    expect(grown.upToDate, isFalse);
    expect(grown.sources, hasLength(7));
    await map.build(grown);

    // Книгу сняли с полки.
    await data.library.delete('m4');
    final MapPlan shrunk = await map.plan();
    expect(shrunk.upToDate, isFalse);
    expect(shrunk.key, longer.key);
  });

  test('F-MAP-02: ключ набора не зависит от идентификаторов книг', () {
    MapSource source(String id, String hash, String group) {
      return MapSource(
        book: testBook(id: id, hash: hash, title: 'Том'),
        group: group,
        cachedPages: 7,
        lastPage: 7,
      );
    }

    // На двух устройствах у одной и той же книги разные идентификаторы.
    final String phone = MapBuilder.keyOf(<MapSource>[
      source('phone-1', 'hash-1', 'Ангиология'),
      source('phone-2', 'hash-2', 'Математика'),
    ], textVersion: 1);
    final String desktop = MapBuilder.keyOf(<MapSource>[
      source('pc-1', 'hash-1', 'Ангиология'),
      source('pc-2', 'hash-2', 'Математика'),
    ], textVersion: 1);
    expect(desktop, phone);
    expect(phone, hasLength(64));
    // А от категории, отпечатка и версии текста — зависит.
    expect(
      MapBuilder.keyOf(<MapSource>[
        source('pc-1', 'hash-1', 'Ангиология'),
        source('pc-2', 'hash-2', 'Ангиология'),
      ], textVersion: 1),
      isNot(phone),
    );
    expect(
      MapBuilder.keyOf(<MapSource>[
        source('pc-1', 'hash-1', 'Ангиология'),
        source('pc-2', 'hash-3', 'Математика'),
      ], textVersion: 1),
      isNot(phone),
    );
    expect(
      MapBuilder.keyOf(<MapSource>[
        source('pc-1', 'hash-1', 'Ангиология'),
        source('pc-2', 'hash-2', 'Математика'),
      ], textVersion: 2),
      isNot(phone),
    );
  });

  test('F-MAP-02: меньше трёх книг — карты нет, прежняя стёрта', () async {
    await addLibrary();
    final MapBuilder map = builder();
    await map.build(await map.plan());
    expect(await data.bookMap.load(), isNotNull);

    for (final String id in <String>['a2', 'a3', 'm2', 'm3']) {
      await data.library.delete(id);
    }
    final MapPlan plan = await map.plan();
    expect(plan.sources, hasLength(2));
    expect(plan.upToDate, isFalse);
    final MapOutcome outcome = await map.build(plan);
    expect(outcome.kind, MapOutcomeKind.tooFew);
    expect(await data.bookMap.load(), isNull);
  });

  test('F-MAP-02: книга без запомненного текста получает место по '
      'названию', () async {
    await addLibrary();
    await addBook('scan', category: 'angio', title: 'Атлас сосудов');
    final MapBuilder map = builder();
    final MapPlan plan = await map.plan();
    final MapSource scan = plan.sources.firstWhere(
      (MapSource source) => source.book.id == 'scan',
    );
    expect(scan.cachedPages, 0);
    expect(scan.lastPage, 0);
    final MapOutcome outcome = await map.build(plan);
    expect(outcome.books, 7);
    final MapPoint point = (await data.bookMap.load())!.points['scan']!;
    expect(point.x.isFinite && point.y.isFinite, isTrue);
  });

  test('F-MAP-02: книга без категории — в группе «без категории»', () async {
    await addLibrary();
    await addBook('free', pages: <String>['Артерия и интеграл.']);
    final MapPlan plan = await builder().plan();
    final MapSource free = plan.sources.firstWhere(
      (MapSource source) => source.book.id == 'free',
    );
    expect(free.group, '');
    expect((await builder().build(plan)).groups, 3);
  });

  test('F-MAP-02: остановленный расчёт прежнюю карту не трогает', () async {
    await addLibrary();
    final MapBuilder map = builder();
    final MapPlan first = await map.plan();
    await map.build(first);
    final StoredBookMap before = (await data.bookMap.load())!;

    await addBook('m4', category: 'math', pages: <String>['Предел.']);
    int asked = 0;
    final MapOutcome outcome = await map.build(
      await map.plan(),
      stopped: () => ++asked > 2,
    );
    expect(outcome.kind, MapOutcomeKind.stopped);
    final StoredBookMap after = (await data.bookMap.load())!;
    expect(after.layoutKey, before.layoutKey);
    expect(after.points, before.points);
  });

  test('F-MAP-02: расчёт в изоляте даёт ту же карту', () async {
    await addLibrary();
    final MapBuilder here = builder();
    final MapOutcome local = await here.build(await here.plan());
    final Map<String, MapPoint> localPoints =
        (await data.bookMap.load())!.points;
    await data.bookMap.clear();

    final MapBuilder isolated = MapBuilder(
      library: data.library,
      categories: data.categories,
      texts: data.pageTexts,
      store: data.bookMap,
    );
    final MapOutcome remote = await isolated.build(await isolated.plan());
    expect(remote.fingerprint, local.fingerprint);
    expect((await data.bookMap.load())!.points, localPoints);
  });
}
