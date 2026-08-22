import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/ui/reader/dim_outside.dart';

/// Тень поверх нечитаемой части страницы.
///
/// Проверяется не картинка, а смысл: что накрыто тенью и что осталось
/// светлым. Путь отвечает на этот вопрос точкой — попала она в закрашенную
/// область или нет, — и это ровно то, что увидит читатель.
void main() {
  const Rect sheet = Rect.fromLTWH(0, 0, 400, 600);
  const Rect strip = Rect.fromLTWH(0, 0, 400, 300);

  group('что накрыто тенью', () {
    final Path path = dimOutsidePath(sheet: sheet, fragment: strip);

    test('читаемая полоса остаётся светлой', () {
      expect(path.contains(const Offset(200, 150)), isFalse);
      expect(path.contains(const Offset(5, 5)), isFalse);
    });

    test('остальная страница гаснет', () {
      expect(path.contains(const Offset(200, 450)), isTrue);
      expect(path.contains(const Offset(10, 590)), isTrue);
    });

    test('за краем листа тени нет', () {
      // Гаснет страница, а не экран: фон вокруг листа темнеть не должен,
      // иначе поля вокруг страницы начнут жить своей жизнью.
      expect(path.contains(const Offset(-20, 300)), isFalse);
      expect(path.contains(const Offset(420, 300)), isFalse);
      expect(path.contains(const Offset(200, 700)), isFalse);
    });
  });

  test('страница целиком тенью не накрывается вовсе', () {
    final Path path = dimOutsidePath(sheet: sheet, fragment: sheet);
    expect(path.contains(const Offset(200, 300)), isFalse);
    expect(path.contains(const Offset(1, 599)), isFalse);
  });

  test('фрагмент за пределами листа не делает дырки', () {
    final Path path = dimOutsidePath(
      sheet: sheet,
      fragment: const Rect.fromLTWH(1000, 1000, 100, 100),
    );
    expect(path.contains(const Offset(200, 300)), isTrue);
  });

  testWidgets('нулевое затемнение ничего не рисует', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DimOutside(sheet: sheet, fragment: strip, dim: 0),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(DimOutside),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('тень не перехватывает нажатия по странице', (
    WidgetTester tester,
  ) async {
    // Переход по фрагментам — это нажатие в край экрана. Если тень
    // начнёт его съедать, книга перестанет листаться там, где темно.
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const DimOutside(sheet: sheet, fragment: strip, dim: 0.6),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(taps, 1);
  });
}
