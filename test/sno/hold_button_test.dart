import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/hold_button.dart';

/// SNO-F-CFG-04: кнопка, которая срабатывает только удержанием.
void main() {
  const Key key = Key('hold');

  Future<void> pumpButton(
    WidgetTester tester, {
    required VoidCallback? onConfirmed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              HoldToConfirmButton(
                key: key,
                label: 'Удерживайте, чтобы сбросить',
                onConfirmed: onConfirmed,
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Нажимает на кнопку и ждёт, пока нажатие будет узнано.
  Future<TestGesture> press(WidgetTester tester) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    return gesture;
  }

  testWidgets('SNO-F-CFG-04: додержали — сработала, и ровно один раз', (
    WidgetTester tester,
  ) async {
    int confirmed = 0;
    await pumpButton(tester, onConfirmed: () => confirmed++);

    final TestGesture gesture = await press(tester);
    await tester.pump(kResetHold - const Duration(milliseconds: 300));
    expect(confirmed, 0, reason: 'ещё держат');
    await tester.pump(const Duration(milliseconds: 400));
    expect(confirmed, 1);

    // Палец остался на кнопке — второго срабатывания нет.
    await tester.pump(kResetHold * 2);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(confirmed, 1);
  });

  testWidgets('SNO-F-CFG-04: короткое нажатие ничего не делает', (
    WidgetTester tester,
  ) async {
    int confirmed = 0;
    await pumpButton(tester, onConfirmed: () => confirmed++);

    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    // И время, прошедшее после отпускания, удержанием не считается.
    await tester.pump(kResetHold * 2);

    expect(confirmed, 0);
  });

  testWidgets('SNO-F-CFG-04: отпустили раньше — счёт начинается заново', (
    WidgetTester tester,
  ) async {
    int confirmed = 0;
    await pumpButton(tester, onConfirmed: () => confirmed++);

    final TestGesture first = await press(tester);
    await tester.pump(kResetHold - const Duration(milliseconds: 500));
    await first.up();
    await tester.pumpAndSettle();

    final TestGesture second = await press(tester);
    await tester.pump(kResetHold - const Duration(milliseconds: 500));
    expect(confirmed, 0, reason: 'два неполных удержания не складываются');
    await second.up();
    await tester.pumpAndSettle();

    expect(confirmed, 0);
  });

  testWidgets('SNO-F-CFG-04: палец повёл список — это не удержание', (
    WidgetTester tester,
  ) async {
    int confirmed = 0;
    await pumpButton(tester, onConfirmed: () => confirmed++);

    final TestGesture gesture = await press(tester);
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await tester.pump(kResetHold * 2);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(confirmed, 0);
  });

  testWidgets('SNO-F-CFG-04: выключенная кнопка не срабатывает', (
    WidgetTester tester,
  ) async {
    await pumpButton(tester, onConfirmed: null);

    final TestGesture gesture = await press(tester);
    await tester.pump(kResetHold * 2);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Удерживайте, чтобы сбросить'), findsOneWidget);
  });
}
