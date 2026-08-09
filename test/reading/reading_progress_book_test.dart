import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/progress_slot.dart';
import 'package:memoria/ui/reader/reading_progress_book.dart';

/// Указатель места — единственная часть чтения, которая видна всегда, и
/// именно она однажды пропала: рисунок был, а на экране оставались одни
/// цифры. Поэтому здесь проверяется и геометрия стопок, и то, что рисунок
/// вообще попадает в дерево виджетов.
void main() {
  const ProgressSlot wide = ProgressSlot(
    side: ProgressSlotSide.bottom,
    left: 0,
    top: 300,
    width: 360,
    height: 44,
    overlaps: false,
  );

  Future<void> pump(
    WidgetTester tester, {
    required ProgressSlot slot,
    int page = 1,
    int pageCount = 300,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ReadingProgressBook(
                slot: slot,
                page: page,
                pageCount: pageCount,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('рисунок на экране', () {
    testWidgets('книга и подпись нарисованы', (WidgetTester tester) async {
      await pump(tester, slot: wide, page: 42, pageCount: 300);
      expect(find.byKey(const Key('reader-progress-book')), findsOneWidget);
      expect(find.text('42 / 300'), findsOneWidget);
    });

    testWidgets('в узком поле рисунок остаётся', (WidgetTester tester) async {
      // Прежняя версия прятала книгу, если поле было тесным, и читатель
      // видел одни цифры — ровно эта жалоба и пришла с устройства.
      const ProgressSlot narrow = ProgressSlot(
        side: ProgressSlotSide.right,
        left: 300,
        top: 0,
        width: 30,
        height: 600,
        overlaps: false,
      );
      await pump(tester, slot: narrow);
      expect(find.byKey(const Key('reader-progress-book')), findsOneWidget);
    });

    testWidgets('без места указателя нет вовсе', (WidgetTester tester) async {
      const ProgressSlot empty = ProgressSlot(
        side: ProgressSlotSide.bottom,
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        overlaps: false,
      );
      await pump(tester, slot: empty);
      expect(find.byKey(const Key('reader-progress-book')), findsNothing);
    });

    testWidgets('поверх страницы указатель получает подложку', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        slot: const ProgressSlot(
          side: ProgressSlotSide.bottom,
          left: 0,
          top: 300,
          width: 360,
          height: 44,
          overlaps: true,
        ),
      );
      final Finder painted = find.descendant(
        of: find.byType(ReadingProgressBook),
        matching: find.byType(DecoratedBox),
      );
      final DecoratedBox box = tester.widget(painted.first);
      final BoxDecoration decoration = box.decoration as BoxDecoration;
      expect(decoration.color, isNot(Colors.transparent));
    });
  });

  group('стопки страниц', () {
    const double height = ReadingProgressBook.bookHeight;

    test('в начале книги слева ничего, справа вся толщина', () {
      final double left = OpenBookPainter.readHeight(
        height: height,
        pageCount: 300,
        share: 0,
      );
      final double right = OpenBookPainter.restHeight(
        height: height,
        pageCount: 300,
        share: 0,
      );
      expect(left, 0);
      expect(
        right,
        closeTo(
          OpenBookPainter.thicknessFor(height: height, pageCount: 300),
          1e-9,
        ),
      );
    });

    test('к концу книги стопки меняются местами', () {
      final double left = OpenBookPainter.readHeight(
        height: height,
        pageCount: 300,
        share: 1,
      );
      final double right = OpenBookPainter.restHeight(
        height: height,
        pageCount: 300,
        share: 1,
      );
      expect(right, 0);
      expect(left, greaterThan(0));
    });

    test('левая растёт, а правая тает — и сумма постоянна', () {
      final double total = OpenBookPainter.thicknessFor(
        height: height,
        pageCount: 300,
      );
      double previous = -1;
      for (final double share in <double>[0, 0.25, 0.5, 0.75, 1]) {
        final double left = OpenBookPainter.readHeight(
          height: height,
          pageCount: 300,
          share: share,
        );
        final double right = OpenBookPainter.restHeight(
          height: height,
          pageCount: 300,
          share: share,
        );
        expect(left, greaterThan(previous));
        expect(left + right, closeTo(total, 1e-9));
        previous = left;
      }
    });

    test('брошюра и том выглядят по-разному', () {
      final double brochure = OpenBookPainter.thicknessFor(
        height: height,
        pageCount: 20,
      );
      final double volume = OpenBookPainter.thicknessFor(
        height: height,
        pageCount: 1200,
      );
      expect(brochure, greaterThan(0), reason: 'брошюру тоже надо видеть');
      expect(volume, greaterThan(brochure * 1.5));
      expect(volume, lessThanOrEqualTo(height));
    });

    test('мусорный объём не ломает рисунок', () {
      expect(
        OpenBookPainter.thicknessFor(height: height, pageCount: 0),
        greaterThan(0),
      );
      expect(
        OpenBookPainter.readHeight(height: height, pageCount: 10, share: 5),
        closeTo(
          OpenBookPainter.thicknessFor(height: height, pageCount: 10),
          1e-9,
        ),
      );
      expect(
        OpenBookPainter.restHeight(height: height, pageCount: 10, share: -2),
        closeTo(
          OpenBookPainter.thicknessFor(height: height, pageCount: 10),
          1e-9,
        ),
      );
    });
  });
}
