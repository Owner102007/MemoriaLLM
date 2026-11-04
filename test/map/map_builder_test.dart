import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/domain/library/book_category.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_seating.dart';
import 'package:memoria/domain/map/map_trusted.dart';
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

  MapBuilder builder({BagRunner? bags, MapRunner? layout, SeatRunner? seat}) {
    return MapBuilder(
      library: data.library,
      categories: data.categories,
      texts: data.pageTexts,
      store: data.bookMap,
      bags: bags ?? (BagRequest request) async => bagOfBook(request),
      layout: layout ?? (List<BookBag> found) async => buildBookMap(found),
      seat:
          seat ??
          (List<BookBag> found, Map<String, MapPoint> kept) async =>
              seatBooks(found, kept),
    );
  }

  /// Расчёт, который считает, сколько раз карта считалась целиком
  /// ([layouts]) и сколько раз досаживалась ([seats]).
  ({MapBuilder map, List<int> layouts, List<int> seats}) counted() {
    final List<int> layouts = <int>[];
    final List<int> seats = <int>[];
    final MapBuilder map = builder(
      layout: (List<BookBag> found) async {
        layouts.add(found.length);
        return buildBookMap(found);
      },
      seat: (List<BookBag> found, Map<String, MapPoint> kept) async {
        seats.add(found.length - kept.length);
        return seatBooks(found, kept);
      },
    );
    return (map: map, layouts: layouts, seats: seats);
  }

  /// Места книг, как они лежат на устройстве: идентификатор → точка.
  Future<Map<String, MapPoint>> stored() async =>
      (await data.bookMap.load())!.points;

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

  test(
    'F-MAP-02: карта считается по тексту из кэша и ложится в базу',
    () async {
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
    },
  );

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

    // Книга переехала в другую категорию полки — с S56 карта от полок не
    // зависит (созвездия складывает резонанс, F-MAP-16): пересчёт не нужен.
    await placeBook(data, 'a3', 'math');
    final MapPlan moved = await map.plan();
    expect(moved.upToDate, isTrue);
    expect(moved.key, plan.key);

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

  test('F-MAP-04: новая книга досаживается — прежние звёзды стоят до '
      'бита, полного расчёта нет', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    final Map<String, MapPoint> before = await stored();
    expect(before.values.every((MapPoint p) => !p.seated), isTrue);
    expect(before.values.every((MapPoint p) => p.input.isNotEmpty), isTrue);

    // Новая книга — о том же, что три книги о сосудах.
    await addBook(
      'a4',
      category: 'angio',
      pages: <String>[
        'Артерия несёт кровь от сердца, вена — к сердцу.',
        'Капилляр соединяет артерию и вену; сосуд a4.',
      ],
    );
    final MapPlan grown = await map.plan();
    expect(grown.upToDate, isFalse);
    final MapOutcome outcome = await map.build(grown);
    expect(outcome.kind, MapOutcomeKind.built);
    expect(outcome.seated, 1);
    expect(layouts, <int>[6], reason: 'целиком — только первый раз');
    expect(seats, <int>[1]);

    final Map<String, MapPoint> after = await stored();
    expect(after, hasLength(7));
    for (final MapEntry<String, MapPoint> was in before.entries) {
      expect(after[was.key], was.value, reason: 'звезда ${was.key} на месте');
    }
    final MapPoint added = after['a4']!;
    expect(added.seated, isTrue);
    expect(added.name, after['a1']!.name, reason: 'к сосудам');
    expect(added.constellation, after['a1']!.constellation);
    expect(added.reason, MapReason.none);
    expect((await map.plan()).upToDate, isTrue);
  });

  test('F-MAP-04: книгу, не похожую ни на одно созвездие, досадка '
      'оставляет без созвездия — до «Перестроить»', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    await addBook(
      'k1',
      pages: <String>[
        'Тесто замешивают на муке и воде, сосуд накрывают.',
        'Хлеб печётся в печи; функция печи — жар.',
      ],
    );
    await map.build(await map.plan());
    MapPoint lone = (await stored())['k1']!;
    expect(lone.constellation, -1);
    expect(lone.reason, MapReason.awaiting);
    expect(lone.seated, isTrue);

    await map.build(await map.plan(), fresh: true);
    lone = (await stored())['k1']!;
    expect(lone.reason, isNot(MapReason.awaiting));
    expect(lone.seated, isFalse);
  });

  test('F-MAP-04: убранная книга снимается, остальные стоят, ничего не '
      'считается', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    final Map<String, MapPoint> before = await stored();

    await data.library.delete('m3');
    final MapPlan shrunk = await map.plan();
    expect(shrunk.upToDate, isFalse);
    final MapOutcome outcome = await map.build(shrunk);
    expect(outcome.kind, MapOutcomeKind.built);
    expect(outcome.books, 5);
    expect(layouts, <int>[6]);
    expect(seats, isEmpty);
    final Map<String, MapPoint> after = await stored();
    expect(after.keys.toSet(), before.keys.toSet()..remove('m3'));
    for (final String id in after.keys) {
      expect(after[id], before[id]);
    }
    expect((await map.plan()).upToDate, isTrue);
  });

  test('F-MAP-04: книга с дочитанным текстом досаживается заново, '
      'остальные стоят', () async {
    await addLibrary();
    // Седьмая и восьмая — чтобы одна изменившаяся была не больше четверти.
    await addBook('a4', category: 'angio', pages: <String>['Сосуд и вена.']);
    await addBook('m4', category: 'math', pages: <String>['Ряд и предел.']);
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    final Map<String, MapPoint> before = await stored();

    await data.pageTexts.savePageTexts(
      const PageTextKey(bookId: 'm1', fingerprint: 'hash-m1'),
      <int, String>{3: 'Ещё страница про интеграл и производную.'},
    );
    await map.build(await map.plan());
    expect(layouts, <int>[8]);
    expect(seats, <int>[1]);
    final Map<String, MapPoint> after = await stored();
    for (final String id in before.keys.where((String id) => id != 'm1')) {
      expect(after[id], before[id], reason: id);
    }
    expect(after['m1']!.seated, isTrue);
    expect(after['m1']!.input, isNot(before['m1']!.input));
  });

  test('F-MAP-04: изменилось больше четверти книг — карта считается '
      'заново (D-049)', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());

    // Шесть книг на карте и три новые: 3 из 9 — больше четверти.
    for (final String id in <String>['a4', 'm4', 'm5']) {
      await addBook(id, category: 'math', pages: <String>['Ряд $id.']);
    }
    final MapOutcome outcome = await map.build(await map.plan());
    expect(outcome.seated, 0);
    expect(layouts, <int>[6, 9]);
    expect(seats, isEmpty);
    expect((await stored()).values.every((MapPoint p) => !p.seated), isTrue);
  });

  test('F-MAP-04: «Перестроить» считает карту заново, как в первый '
      'раз: та же карта, что у нового устройства', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    await addBook('a4', category: 'angio', pages: <String>['Сосуд и вена.']);
    final MapOutcome seated = await map.build(await map.plan());
    expect(seated.seated, 1);

    final MapPlan plan = await map.plan();
    expect(plan.upToDate, isTrue, reason: 'карта свежа — но читатель просит');
    final MapOutcome rebuilt = await map.build(plan, fresh: true);
    expect(rebuilt.seated, 0);
    expect(layouts, <int>[6, 7]);
    expect((await stored()).values.every((MapPoint p) => !p.seated), isTrue);

    // Новое устройство с теми же книгами считает ту же карту.
    await data.bookMap.clear();
    final MapOutcome anew = await map.build(await map.plan());
    expect(anew.fingerprint, rebuilt.fingerprint);
  });

  test('F-MAP-04: карта, положенная до S60 (без отпечатка входа), при '
      'первой перемене считается целиком', () async {
    await addLibrary();
    final (:MapBuilder map, :List<int> layouts, :List<int> seats) = counted();
    await map.build(await map.plan());
    final StoredBookMap old = (await data.bookMap.load())!;
    await data.bookMap.replace(
      StoredBookMap(
        layoutKey: old.layoutKey,
        version: old.version,
        points: <String, MapPoint>{
          for (final MapEntry<String, MapPoint> e in old.points.entries)
            e.key: e.value.withInput(''),
        },
      ),
    );
    expect((await map.plan()).upToDate, isTrue, reason: 'без перемен — стоит');
    await addBook('a4', category: 'angio', pages: <String>['Сосуд и вена.']);
    await map.build(await map.plan());
    expect(layouts, <int>[6, 7]);
    expect(seats, isEmpty);
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
    // От категории полки — нет: с S56 созвездия складывает резонанс
    // (F-MAP-16), а не полки.
    expect(
      MapBuilder.keyOf(<MapSource>[
        source('pc-1', 'hash-1', 'Ангиология'),
        source('pc-2', 'hash-2', 'Ангиология'),
      ], textVersion: 1),
      phone,
    );
    // А от отпечатка и версии текста — зависит.
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

  test('F-MAP-06: расчёт ждёт своей очереди к движку PDF перед каждой '
      'книгой и снимается, когда очередь не дали', () async {
    await addLibrary();
    final MapBuilder map = builder();
    final MapPlan plan = await map.plan();
    int turns = 0;
    final MapOutcome built = await map.build(
      plan,
      turn: () async {
        turns++;
        return true;
      },
    );
    expect(built.kind, MapOutcomeKind.built);
    expect(turns, plan.sources.length);

    await data.bookMap.clear();
    int asked = 0;
    final MapOutcome stopped = await map.build(
      plan,
      turn: () async => ++asked < 2,
    );
    expect(stopped.kind, MapOutcomeKind.stopped);
    expect(asked, 2);
    expect(await data.bookMap.load(), isNull);
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
