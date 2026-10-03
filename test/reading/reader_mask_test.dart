import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/sheet_arrangement.dart';
import 'package:memoria/ui/reader/reader_mask.dart';

/// Маска поверх страницы: уровни темноты вместо второго виджета.
///
/// Проверяется не картинка, а смысл: что закрыто наглухо, что притушено и
/// что осталось светлым. Путь отвечает на этот вопрос точкой — попала она
/// в закрашенную область или нет, — и это ровно то, что увидит читатель.
void main() {
  const Rect screen = Rect.fromLTWH(0, 0, 800, 600);
  const Rect sheet = Rect.fromLTWH(0, 0, 400, 600);
  const Rect strip = Rect.fromLTWH(0, 0, 400, 300);

  group('первый уровень: за листом фон наглухо', () {
    final Path path = outsideSheetPath(screen: screen, sheet: sheet);

    test('соседняя страница закрыта', () {
      // Ровно эта поломка и разворачивает S6: на широком окне ПК справа
      // от читаемой страницы стояла соседняя, и её было видно.
      expect(path.contains(const Offset(600, 300)), isTrue);
      expect(path.contains(const Offset(401, 10)), isTrue);
      expect(path.contains(const Offset(799, 599)), isTrue);
    });

    test('сам лист остаётся открытым', () {
      expect(path.contains(const Offset(200, 300)), isFalse);
      expect(path.contains(const Offset(2, 2)), isFalse);
    });

    test('край листа закрыт с нахлёстом, а не впритык', () {
      // Страницы стоят вплотную, без полей: ровная граница сглаживается,
      // и от соседней страницы остаётся волосок света. Маска заходит на
      // лист на пол-точки и съедает его.
      expect(path.contains(const Offset(399.9, 300)), isTrue);
      expect(path.contains(const Offset(398, 300)), isFalse);
    });

    test('лист шире экрана закрывать нечем — и не надо', () {
      final Path wide = outsideSheetPath(
        screen: screen,
        sheet: const Rect.fromLTWH(-200, -100, 1400, 900),
      );
      expect(wide.contains(const Offset(400, 300)), isFalse);
      expect(wide.contains(const Offset(1, 1)), isFalse);
      expect(wide.contains(const Offset(799, 599)), isFalse);
    });

    test('пустой лист закрывает экран целиком', () {
      final Path none = outsideSheetPath(screen: screen, sheet: Rect.zero);
      expect(none.contains(const Offset(400, 300)), isTrue);
    });
  });

  group('второй уровень: на листе вне полосы', () {
    final Path path = dimOutsidePath(sheet: sheet, fragment: strip);

    test('читаемая полоса остаётся светлой', () {
      expect(path.contains(const Offset(200, 150)), isFalse);
      expect(path.contains(const Offset(5, 5)), isFalse);
    });

    test('остальная страница гаснет, но не пропадает', () {
      expect(path.contains(const Offset(200, 450)), isTrue);
      expect(path.contains(const Offset(10, 590)), isTrue);
    });

    test('за краем листа второго уровня нет', () {
      // Там работает первый: фон, а не тень. Иначе поля вокруг страницы
      // начали бы жить своей жизнью и темнеть вдвое.
      expect(path.contains(const Offset(-20, 300)), isFalse);
      expect(path.contains(const Offset(420, 300)), isFalse);
      expect(path.contains(const Offset(200, 700)), isFalse);
    });

    test('страница целиком тенью не накрывается вовсе', () {
      final Path whole = dimOutsidePath(sheet: sheet, fragment: sheet);
      expect(whole.contains(const Offset(200, 300)), isFalse);
      expect(whole.contains(const Offset(1, 599)), isFalse);
    });

    test('фрагмент за пределами листа не делает дырки', () {
      final Path lost = dimOutsidePath(
        sheet: sheet,
        fragment: const Rect.fromLTWH(1000, 1000, 100, 100),
      );
      expect(lost.contains(const Offset(200, 300)), isTrue);
    });
  });

  group('F-READ-13: третий уровень — назначенный кусок соседа', () {
    // Широкое окно ПК: страница посередине, соседние — по бокам, и от
    // каждой видна полоска в 40 точек.
    const Rect wide = Rect.fromLTWH(0, 0, 1200, 600);
    const Rect page = Rect.fromLTWH(400, 0, 400, 600);
    final List<NeighbourZone> zones = neighbourZones(
      arrangement: SheetArrangement.row,
      sheet: page,
      strip: page,
      band: 0,
      width: 40,
      hasBefore: true,
      hasAfter: true,
    );
    final Path path = outsideSheetPath(
      screen: wide,
      sheet: page,
      neighbours: zones,
    );

    test('F-READ-13: полоска соседа открыта, дальше — фон наглухо', () {
      // В полоске фона нет: там видна соседняя страница под своей тенью.
      expect(path.contains(const Offset(380, 300)), isFalse);
      expect(path.contains(const Offset(820, 300)), isFalse);
      // А сразу за полоской — фон, сколько бы соседа ни влезло в окно.
      expect(path.contains(const Offset(350, 300)), isTrue);
      expect(path.contains(const Offset(850, 300)), isTrue);
      expect(path.contains(const Offset(10, 300)), isTrue);
      expect(path.contains(const Offset(1190, 300)), isTrue);
    });

    test('F-READ-13: своя страница по-прежнему открыта', () {
      expect(path.contains(const Offset(600, 300)), isFalse);
    });

    test('F-READ-13: без соседей маска та же, что была', () {
      final Path plain = outsideSheetPath(screen: wide, sheet: page);
      expect(plain.contains(const Offset(380, 300)), isTrue);
      expect(plain.contains(const Offset(820, 300)), isTrue);
      expect(plain.contains(const Offset(600, 300)), isFalse);
    });

    test('F-READ-12: под листом открыт верх следующей страницы', () {
      // Столбик: последняя полоса страницы, нахлёст 30 точек.
      const Rect screen = Rect.fromLTWH(0, 0, 800, 360);
      const Rect sheet = Rect.fromLTWH(0, -500, 800, 800);
      final List<NeighbourZone> below = neighbourZones(
        arrangement: SheetArrangement.column,
        sheet: sheet,
        strip: const Rect.fromLTWH(0, 30, 800, 270),
        band: 30,
        width: 0,
        hasBefore: true,
        hasAfter: true,
      );
      final Path lapped = outsideSheetPath(
        screen: screen,
        sheet: sheet,
        neighbours: below,
      );
      // Тридцать точек под листом открыты, ниже — фон.
      expect(lapped.contains(const Offset(400, 315)), isFalse);
      expect(lapped.contains(const Offset(400, 345)), isTrue);
    });

    test('F-READ-13: смена соседей перерисовывает маску', () {
      const ReaderMaskPainter plain = ReaderMaskPainter(
        sheet: page,
        strip: page,
        dim: 0.6,
        background: Color(0xFF0E0708),
      );
      final ReaderMaskPainter withZones = ReaderMaskPainter(
        sheet: page,
        strip: page,
        dim: 0.6,
        background: const Color(0xFF0E0708),
        neighbours: zones,
      );
      final ReaderMaskPainter same = ReaderMaskPainter(
        sheet: page,
        strip: page,
        dim: 0.6,
        background: const Color(0xFF0E0708),
        neighbours: List<NeighbourZone>.of(zones),
      );
      expect(withZones.shouldRepaint(plain), isTrue);
      expect(withZones.shouldRepaint(same), isFalse);
    });

    testWidgets('F-READ-13: маска с соседями рисуется и нажатий не ловит', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: ReaderMask(
              sheet: page,
              strip: page,
              dim: 0,
              background: const Color(0xFF0E0708),
              neighbours: zones,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(380, 300));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('маска целиком', () {
    testWidgets('нулевое затемнение не гасит страницу, но соседей прячет', (
      WidgetTester tester,
    ) async {
      // Уровни независимы: `dimOutside` — настройка читателя, а фон за
      // листом настройкой не бывает вовсе.
      const ReaderMaskPainter painter = ReaderMaskPainter(
        sheet: sheet,
        strip: strip,
        dim: 0,
        background: Color(0xFF0E0708),
      );
      const ReaderMaskPainter dimmed = ReaderMaskPainter(
        sheet: sheet,
        strip: strip,
        dim: 0.6,
        background: Color(0xFF0E0708),
      );
      expect(painter.shouldRepaint(dimmed), isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: ReaderMask(
            sheet: sheet,
            strip: strip,
            dim: 0,
            background: Color(0xFF0E0708),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ReaderMask),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('маска не перехватывает нажатия по странице', (
      WidgetTester tester,
    ) async {
      // Переход по фрагментам — это нажатие в край экрана. Если маска
      // начнёт его съедать, книга перестанет листаться там, где темно.
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const ReaderMask(
              sheet: sheet,
              strip: strip,
              dim: 0.6,
              background: Color(0xFF0E0708),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(200, 500));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
