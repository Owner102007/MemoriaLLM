import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading_filter.dart';
import 'package:memoria/ui/reader/highlight_layer.dart';
import 'package:memoria/ui/reader/reader_layers.dart';

/// BUG-43: подсветка найденного — картинка, а не кнопка.
///
/// Слой подсветки лежит поверх страницы во весь лист. `CustomPaint` с
/// отрисовщиком считает попаданием любую точку своей площади, если
/// отрисовщик не сказал обратного, — и пока подсветка была на странице,
/// слой забирал каждое нажатие: панели не показывались, края не листали,
/// текст не выделялся. Страница «оживала» только после листания клавишей.
///
/// Слои собраны так же, как на экране чтения: страница, маска, поверх —
/// подсветка во весь лист (`reader_screen.dart`, `_buildOverlay`).
void main() {
  const Color color = Color(0x59A32F35);
  const Rect found = Rect.fromLTWH(300, 280, 200, 24);

  Widget sheet({required List<Rect> rects, required VoidCallback onTap}) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderLayers(
          filter: const ReadingFilterPipeline(),
          // Страница узнаёт нажатие слушателем указателя — как лист
          // (`QuickTap`).
          page: Listener(
            key: const Key('page'),
            behavior: HitTestBehavior.opaque,
            onPointerUp: (PointerUpEvent event) => onTap(),
            child: const SizedBox.expand(),
          ),
          mask: const SizedBox.expand(),
          overlay: Stack(
            children: <Widget>[
              Positioned.fill(
                child: HighlightLayer(rects: rects, color: color),
              ),
            ],
          ),
          progress: const SizedBox.shrink(),
        ),
      ),
    );
  }

  testWidgets('BUG-43: нажатие под подсветкой доходит до страницы', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      sheet(rects: const <Rect>[found], onTap: () => taps++),
    );
    await tester.pump();
    expect(find.byKey(const Key('reader-highlight')), findsOneWidget);

    // Мимо подсвеченного — середина экрана левее него и край экрана.
    await tester.tapAt(const Offset(100, 300));
    await tester.tapAt(const Offset(760, 500));
    expect(taps, 2, reason: 'слой подсветки не ловит нажатий мимо найденного');

    // И по самому подсвеченному: подсветка — не кнопка.
    await tester.tapAt(found.center);
    expect(taps, 3, reason: 'и по найденному — тоже');
  });

  testWidgets('BUG-43: без подсветки страница отвечает, как отвечала', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(sheet(rects: const <Rect>[], onTap: () => taps++));
    await tester.pump();
    expect(find.byKey(const Key('reader-highlight')), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
  });
}
