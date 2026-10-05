import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/index/shelf_reading.dart';
import 'package:memoria/sno/index/shelf_reading_view.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:memoria/ui/library/library_screen.dart';

import '../data/test_data.dart';
import '../support/shown_reading.dart';
import '../support/test_services.dart';

const ShelfReadingProgress _reading = ShelfReadingProgress(
  phase: ShelfReadingPhase.reading,
  booksDone: 12,
  booksTotal: 40,
  title: 'Анатомия человека',
  page: 212,
  pages: 608,
  elapsedMs: 125000,
);

const ShelfIndexSummary _finished = ShelfIndexSummary(
  complete: true,
  books: 40,
  pages: 16212,
  scans: 3,
  readMs: 400000,
  map: MapSummary(
    state: MapSummary.built,
    books: 40,
    groups: 2,
    ms: 1400,
    fingerprint: '5f3a9c1e',
  ),
);

/// SNO-F-IDX-04: что экспериментатор видит о подготовке книг — полоска
/// над полкой и блок в «Тестировании» (кадр SNO-SCR-01.1).
void main() {
  group('SNO-F-IDX-04: слова', () {
    test('SNO-F-IDX-04: числа и сроки пишутся по-русски', () {
      expect(describeCount(0), '0');
      expect(describeCount(999), '999');
      expect(describeCount(1000), '1 000');
      expect(describeCount(16212), '16 212');
      expect(describeCount(1234567), '1 234 567');

      expect(describeSpan(0), '0,0 с');
      expect(describeSpan(1400), '1,4 с');
      expect(describeSpan(9949), '9,9 с');
      expect(describeSpan(40000), '40 с');
      expect(describeSpan(400000), '6 мин 40 с');
      expect(describeSpan(125000), '2 мин 05 с');
      expect(describeSpan(3900000), '1 ч 05 мин');
      expect(describeSpan(-5), '0,0 с');
    });

    test('SNO-F-IDX-04: полоска говорит, что делается', () {
      expect(describeShelfReading(_reading), 'Читаю книги · 12 из 40');
      expect(
        describeShelfReading(
          _reading.copyWith(phase: ShelfReadingPhase.held),
        ),
        'Чтение книг приостановлено: открыта книга · 12 из 40',
      );
      expect(
        describeShelfReading(
          const ShelfReadingProgress(
            phase: ShelfReadingPhase.mapping,
            mapDone: 7,
            mapTotal: 40,
          ),
        ),
        'Считаю карту · 7 из 40',
      );
      expect(describeShelfReading(const ShelfReadingProgress()), '');
      expect(
        describeShelfReading(
          const ShelfReadingProgress(phase: ShelfReadingPhase.done),
        ),
        '',
      );
    });

    test('SNO-F-IDX-04: доля хода считается с точностью до страницы', () {
      // Двенадцать книг из сорока и треть тринадцатой.
      expect(
        shelfReadingShare(_reading),
        closeTo((12 + 212 / 608) / 40, 1e-12),
      );
      expect(
        shelfReadingShare(
          const ShelfReadingProgress(
            phase: ShelfReadingPhase.mapping,
            mapDone: 10,
            mapTotal: 40,
          ),
        ),
        0.25,
      );
      expect(shelfReadingShare(const ShelfReadingProgress()), isNull);
      expect(
        shelfReadingShare(
          const ShelfReadingProgress(phase: ShelfReadingPhase.reading),
        ),
        isNull,
      );
    });

    test('SNO-F-IDX-04: пока идёт чтение — книга, страница и срок', () {
      expect(describeShelfIndex(_reading, null), <String>[
        'Читаю текст · 12 из 40',
        '«Анатомия человека» · стр. 212 из 608',
        'Прошло 2 мин 05 с',
      ]);
      expect(
        describeShelfIndex(
          _reading.copyWith(phase: ShelfReadingPhase.held),
          null,
        ),
        <String>[
          'Чтение книг приостановлено: открыта книга.',
          'Прочитано 12 из 40',
        ],
      );
    });

    test('SNO-F-IDX-04: итог — книги, страницы, срок, сканы и карта', () {
      expect(
        describeShelfIndex(
          const ShelfReadingProgress(phase: ShelfReadingPhase.done),
          _finished,
        ),
        <String>[
          'Прочитано книг: 40 · 16 212 стр.',
          'Заняло 6 мин 40 с',
          'Без текста (сканы): 3',
          'Карта посчитана · книг: 40, групп: 2 · 1,4 с · отпечаток 5f3a9c1e',
        ],
      );
    });

    test('SNO-F-IDX-04: непрочитанные книги названы, но не все', () {
      final List<String> lines = describeShelfIndex(
        const ShelfReadingProgress(),
        const ShelfIndexSummary(
          complete: true,
          books: 36,
          pages: 900,
          unread: <String>['Атлас', 'Том 2', 'Том 3', 'Том 4', 'Том 5'],
          map: MapSummary(state: MapSummary.failed),
        ),
      );
      expect(lines, <String>[
        'Прочитано книг: 36 · 900 стр.',
        'Не прочитаны: 5 — «Атлас», «Том 2», «Том 3» и ещё 2',
        'Карта не посчиталась — расчёт повторится при следующем запуске.',
      ]);
    });

    test('SNO-F-IDX-04: о карте, которой нет, сказано почему', () {
      expect(
        describeMapSummary(const MapSummary(state: MapSummary.tooFew)),
        contains('меньше трёх'),
      );
      expect(
        describeMapSummary(const MapSummary(state: MapSummary.tooMany)),
        contains('слишком много'),
      );
      // Карта, лежавшая готовой: времени расчёта нет — нет и слова о нём.
      expect(
        describeMapSummary(
          const MapSummary(
            state: MapSummary.built,
            books: 5,
            groups: 1,
            fingerprint: 'abcdef01',
          ),
        ),
        'Карта посчитана · книг: 5, групп: 1 · отпечаток abcdef01',
      );
    });

    test('SNO-F-IDX-04: без итога и с пустой полкой — свои слова', () {
      expect(describeShelfIndex(const ShelfReadingProgress(), null), <String>[
        'Книги ещё не читались.',
      ]);
      expect(
        describeShelfIndex(
          const ShelfReadingProgress(),
          const ShelfIndexSummary(complete: true),
        ),
        <String>['Книг на полке нет.'],
      );
      expect(
        describeShelfIndex(
          const ShelfReadingProgress(),
          const ShelfIndexSummary(readMs: 65000),
        ),
        <String>[
          'Чтение книг не закончено — продолжится при следующем запуске.',
          'Уже заняло 1 мин 05 с',
        ],
      );
    });

    test('SNO-F-IDX-04: пройти полку ещё раз предлагают, когда есть '
        'зачем', () {
      const ShelfReadingProgress idle = ShelfReadingProgress();
      expect(shelfIndexNeedsRetry(idle, null), isTrue);
      expect(shelfIndexNeedsRetry(idle, const ShelfIndexSummary()), isTrue);
      expect(shelfIndexNeedsRetry(idle, _finished), isFalse);
      expect(
        shelfIndexNeedsRetry(
          idle,
          _finished.copyWith(unread: <String>['Атлас']),
        ),
        isTrue,
      );
      expect(
        shelfIndexNeedsRetry(
          idle,
          _finished.copyWith(
            map: const MapSummary(state: MapSummary.failed),
          ),
        ),
        isTrue,
      );
      // Пока подготовка идёт, начинать её нечем.
      expect(shelfIndexNeedsRetry(_reading, null), isFalse);
    });
  });

  group('SNO-F-IDX-04: экраны', () {
    late AppData data;

    setUp(() async => data = await openTestData());
    tearDown(() async => data.close());

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('SNO-F-IDX-04: полоска над полкой есть, только пока книги '
        'готовятся', (WidgetTester tester) async {
      final ShownReading reading = ShownReading(data);
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            services: testServices(data: data, shelfReading: reading),
            canAddBooks: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-shelf-reading')), findsNothing);

      reading.show(_reading);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-shelf-reading')), findsOneWidget);
      expect(find.text('Читаю книги · 12 из 40'), findsOneWidget);
      // Полка под полоской остаётся полкой.
      expect(find.byKey(const Key('library-empty-branch')), findsOneWidget);

      reading.show(
        const ShelfReadingProgress(
          phase: ShelfReadingPhase.mapping,
          mapDone: 7,
          mapTotal: 40,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Считаю карту · 7 из 40'), findsOneWidget);

      reading.show(const ShelfReadingProgress(phase: ShelfReadingPhase.done));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-shelf-reading')), findsNothing);

      await unmount(tester);
      reading.dispose();
    });

    testWidgets('SNO-F-IDX-04: без подготовки полоски на полке нет вовсе', (
      WidgetTester tester,
    ) async {
      // Основное приложение и ветвь I: подготовки в службах нет.
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            services: testServices(data: data),
            canAddBooks: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ShelfReadingStrip), findsNothing);
      expect(find.byKey(const Key('library-empty-branch')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('SNO-F-IDX-04: «Тестирование» показывает ход и итог '
        'подготовки', (WidgetTester tester) async {
      final ShownReading reading = ShownReading(data);
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, shelfReading: reading),
            flags: BranchFlags.of('II'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sno-shelf-index')), findsOneWidget);
      expect(find.text('Подготовка книг'), findsOneWidget);
      expect(find.text('Книги ещё не читались.'), findsOneWidget);

      reading.show(_reading);
      await tester.pumpAndSettle();
      expect(find.text('Читаю текст · 12 из 40'), findsOneWidget);
      expect(
        find.text('«Анатомия человека» · стр. 212 из 608'),
        findsOneWidget,
      );
      // Пока подготовка идёт, начинать её заново нечем.
      expect(find.byKey(const Key('sno-shelf-index-retry')), findsNothing);

      reading.show(
        const ShelfReadingProgress(phase: ShelfReadingPhase.done),
        summary: _finished,
      );
      await tester.pumpAndSettle();
      expect(find.text('Прочитано книг: 40 · 16 212 стр.'), findsOneWidget);
      expect(find.text('Заняло 6 мин 40 с'), findsOneWidget);
      expect(find.textContaining('отпечаток 5f3a9c1e'), findsOneWidget);
      expect(find.byKey(const Key('sno-shelf-index-retry')), findsNothing);

      await unmount(tester);
      reading.dispose();
    });

    testWidgets('SNO-F-IDX-04: непрочитанные книги — и кнопка «Прочитать '
        'книги»', (WidgetTester tester) async {
      final ShownReading reading = ShownReading(data);
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, shelfReading: reading),
            flags: BranchFlags.of('II'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();
      reading.show(
        const ShelfReadingProgress(phase: ShelfReadingPhase.done),
        summary: _finished.copyWith(unread: <String>['Атлас']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Не прочитаны: 1 — «Атлас»'), findsOneWidget);
      final Finder retry = find.byKey(const Key('sno-shelf-index-retry'));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(reading.starts, 1);

      await unmount(tester);
      reading.dispose();
    });

    testWidgets('SNO-F-IDX-04: в ветви без подготовки блока в '
        '«Тестировании» нет', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sno-shelf-index')), findsNothing);
      expect(find.text('Подготовка книг'), findsNothing);
      await unmount(tester);
    });
  });
}
