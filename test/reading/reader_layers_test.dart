import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/progress_slot.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/reading_filter.dart';
import 'package:memoria/ui/reader/reader_layers.dart';
import 'package:memoria/ui/reader/reader_mask.dart';
import 'package:memoria/ui/reader/reading_filter_layer.dart';
import 'package:memoria/ui/reader/reading_progress_book.dart';

/// Страница-заглушка, которая считает, сколько раз её создавали.
class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// BUG-04: порядок слоёв листа.
///
/// Светофильтр оборачивал лист целиком — с маской, подсветкой найденного,
/// панелью над выделением и указателем места. Ночью «Инверсия» делала
/// тёмные поля вокруг страницы почти белыми, а «Ночной красный» красил
/// панели. Здесь закреплено главное: под фильтром лежит только картинка
/// страницы, всё остальное — выше.
void main() {
  const ReadingFilterPipeline invert = ReadingFilterPipeline(
    filter: ReadingFilter.invert,
    intensity: 1,
  );
  const ReadingFilterPipeline none = ReadingFilterPipeline();
  const Key pageKey = Key('layers-page');
  const Key overlayKey = Key('layers-overlay');
  const Key maskKey = Key('layers-mask');
  const Key bookKey = Key('reader-progress-book');

  Widget layers({
    required ReadingFilterPipeline filter,
    Widget page = const ColoredBox(key: pageKey, color: Color(0xFFFFFFFF)),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderLayers(
          filter: filter,
          page: page,
          mask: const ReaderMask(
            key: maskKey,
            sheet: Rect.fromLTWH(200, 0, 400, 600),
            strip: Rect.fromLTWH(200, 0, 400, 300),
            dim: 0.6,
            background: Color(0xFF0E0708),
          ),
          overlay: const ColoredBox(key: overlayKey, color: Color(0x33FFFFFF)),
          progress: const ReadingProgressBook(
            slot: ProgressSlot(
              side: ProgressSlotSide.right,
              left: 600,
              top: 0,
              width: 200,
              height: 600,
              overlaps: false,
            ),
            page: 3,
            pageCount: 10,
          ),
        ),
      ),
    );
  }

  Finder underFilter(Finder what) {
    return find.descendant(of: find.byType(ReadingFilterLayer), matching: what);
  }

  testWidgets('BUG-04: под светофильтром лежит только страница', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(layers(filter: invert));
    await tester.pump();

    // Фильтр включён и накрывает страницу.
    expect(
      underFilter(
        find.byWidgetPredicate(
          (Widget widget) => widget is ColorFiltered || widget is ImageFiltered,
        ),
      ),
      findsOneWidget,
    );
    expect(underFilter(find.byKey(pageKey)), findsOneWidget);

    // Маска, подсветка с панелью и указатель места — на экране, но не
    // под фильтром: при «Инверсии» поля вокруг страницы остаются
    // тёмными, а панели — в своих цветах.
    expect(find.byKey(maskKey), findsOneWidget);
    expect(find.byKey(overlayKey), findsOneWidget);
    expect(find.byKey(bookKey), findsOneWidget);
    expect(underFilter(find.byKey(maskKey)), findsNothing);
    expect(underFilter(find.byKey(overlayKey)), findsNothing);
    expect(underFilter(find.byKey(bookKey)), findsNothing);
  });

  testWidgets('BUG-04: без фильтра слои те же', (WidgetTester tester) async {
    await tester.pumpWidget(layers(filter: none));
    await tester.pump();

    expect(find.byKey(pageKey), findsOneWidget);
    expect(find.byKey(maskKey), findsOneWidget);
    expect(find.byKey(overlayKey), findsOneWidget);
    expect(find.byKey(bookKey), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('BUG-04: слоя пометок может не быть', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderLayers(
            filter: invert,
            page: ColoredBox(key: pageKey, color: Color(0xFFFFFFFF)),
            mask: SizedBox.expand(key: maskKey),
            progress: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(underFilter(find.byKey(pageKey)), findsOneWidget);
    expect(underFilter(find.byKey(maskKey)), findsNothing);
  });

  testWidgets('BUG-04: смена фильтра не пересоздаёт страницу', (
    WidgetTester tester,
  ) async {
    // Фильтр то оборачивает страницу, то нет: место страницы в дереве
    // меняется. Без ключа просмотрщик создавался бы заново при каждом
    // включении фильтра — с белым листом и возвратом на первую страницу
    // листа. Лист держит его глобальным ключом, и здесь проверяется, что
    // через слой фильтра такой ключ переезжает с тем же состоянием.
    final GlobalKey viewer = GlobalKey();
    int created = 0;
    Widget page() {
      return KeyedSubtree(key: viewer, child: _Probe(onInit: () => created++));
    }

    await tester.pumpWidget(layers(filter: none, page: page()));
    await tester.pump();
    expect(created, 1);

    await tester.pumpWidget(layers(filter: invert, page: page()));
    await tester.pump();
    expect(created, 1, reason: 'фильтр включили — страница та же');
    expect(underFilter(find.byType(_Probe)), findsOneWidget);

    await tester.pumpWidget(layers(filter: none, page: page()));
    await tester.pump();
    expect(created, 1, reason: 'фильтр выключили — страница та же');
  });
}
