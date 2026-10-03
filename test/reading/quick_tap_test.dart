import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reader_gestures.dart';
import 'package:memoria/ui/reader/quick_tap.dart';

/// BUG-37: нажатие по странице листало на 300 мс позже стрелки панели.
///
/// Просмотрщик с настоящим PDFium в widget-тестах не строится, поэтому
/// здесь стоит его точная модель по исходникам pdfrx 2.6.1: один
/// `GestureDetector`, на котором сразу и одиночное, и двойное нажатие.
/// Именно это сочетание и задерживает одиночное.
void main() {
  late TapWatch watch;
  late List<Offset> ours;
  late List<Offset> viewers;
  late int executed;

  setUp(() {
    watch = TapWatch();
    ours = <Offset>[];
    viewers = <Offset>[];
    executed = 0;
  });

  /// Страница, как её ловит просмотрщик, и наш слушатель поверх неё.
  ///
  /// Сообщение просмотрщика о нажатии разбирается так же, как в листе:
  /// эхо уже исполненного нажатия второй раз не исполняется.
  Future<void> pumpPage(WidgetTester tester, {bool quick = true}) async {
    final Widget viewer = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails details) {
        viewers.add(details.localPosition);
        if (!watch.echoes()) {
          executed++;
        }
      },
      onDoubleTapDown: (TapDownDetails details) {},
      child: const SizedBox.expand(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: quick
            ? QuickTap(
                watch: watch,
                onTap: (Offset at) {
                  ours.add(at);
                  executed++;
                },
                child: viewer,
              )
            : viewer,
      ),
    );
  }

  testWidgets('BUG-37: просмотрщик объявляет нажатие только через 300 мс', (
    WidgetTester tester,
  ) async {
    // Сам дефект: без нашего слушателя нажатие исполняется, лишь когда
    // истёк срок ожидания двойного.
    await pumpPage(tester, quick: false);

    await tester.tapAt(const Offset(700, 300));
    await tester.pump();
    expect(executed, 0);

    await tester.pump(kDoubleTapTimeout - const Duration(milliseconds: 20));
    expect(executed, 0);

    await tester.pump(const Duration(milliseconds: 40));
    expect(executed, 1);
  });

  testWidgets('BUG-37: нажатие исполняется сразу, не дожидаясь двойного', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);

    await tester.tapAt(const Offset(700, 300));

    // Ни одного кадра и ни одной миллисекунды спустя.
    expect(ours, <Offset>[const Offset(700, 300)]);
    expect(executed, 1);
    expect(viewers, isEmpty);
  });

  testWidgets('BUG-37: эхо просмотрщика второй раз не исполняется', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);

    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

    // Просмотрщик сообщил о том же нажатии — и оно опознано как эхо.
    expect(viewers, hasLength(1));
    expect(executed, 1);
  });

  testWidgets('BUG-37: два быстрых нажатия — два шага', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);

    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

    expect(ours, hasLength(2));
    // Просмотрщик счёл это двойным нажатием и одиночным не сообщил.
    expect(viewers, isEmpty);
    expect(executed, 2);
  });

  testWidgets('BUG-37: удержание пальца — не нажатие', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);

    final TestGesture gesture = await tester.startGesture(
      const Offset(700, 300),
    );
    // Удержание узнаёт распознаватель листа и сообщает наблюдателю.
    await tester.pump(kTouchSelectionDelay);
    watch.spoil();
    await gesture.up();
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

    expect(ours, isEmpty);
    expect(executed, 0);
  });

  testWidgets('BUG-37: протяжка — не нажатие', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.dragFrom(const Offset(700, 300), const Offset(-120, 0));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

    expect(ours, isEmpty);
    expect(executed, 0);
  });

  testWidgets('BUG-37: щелчок мышью листает сразу, правая кнопка — нет', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);

    await tester.tapAt(
      const Offset(700, 300),
      kind: PointerDeviceKind.mouse,
    );
    expect(ours, <Offset>[const Offset(700, 300)]);

    await tester.tapAt(
      const Offset(700, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    expect(ours, hasLength(1));
  });
}
