import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/category_style.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/ui/library/shelf_pattern.dart';

void main() {
  // Растеризация картинки в тесте требует поднятого окружения даже там,
  // где виджетов нет вовсе.
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppPalette dark = appPalettes[AppThemeId.darkRed]!;

  ShelfPatternPainter painterFor(
    ShelfPattern pattern, {
    bool acid = false,
    double step = 30,
    int seed = 0x51ED2A17,
  }) {
    final CategoryStyle style = CategoryStyle(
      seed: seed,
      pattern: pattern,
      hueIndex: 5,
      phase: 0.37,
      acid: acid,
    );
    return ShelfPatternPainter(
      style: style,
      background: Color(style.backgroundOn(dark)),
      ink: Color(style.inkOn(dark)),
      step: step,
      stroke: style.strokeOn(dark, step),
      glow: style.acidOn(dark),
    );
  }

  void paint(ShelfPatternPainter painter, Size size) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
  }

  group('каждый узор рисуется и не зацикливается', () {
    // Половина узоров построена на циклах «пока не дошли до края»: шаг,
    // случайно ставший нулём, повесил бы полку намертво, и заметить это
    // без прогона каждого узора невозможно.
    for (final ShelfPattern pattern in ShelfPattern.values) {
      test(pattern.name, () {
        for (final Size size in <Size>[
          const Size(240, 320),
          const Size(31, 500),
          const Size(1200, 40),
        ]) {
          expect(
            () => paint(painterFor(pattern), size),
            returnsNormally,
            reason: '${pattern.name} на $size',
          );
        }
      });
    }

    test('вырожденный блок не рисуется вовсе', () {
      for (final ShelfPattern pattern in ShelfPattern.values) {
        expect(() => paint(painterFor(pattern), Size.zero), returnsNormally);
        expect(
          () => paint(painterFor(pattern, step: 0), const Size(100, 100)),
          returnsNormally,
        );
      }
    });

    test('кислотный узор рисуется тем же кодом', () {
      for (final ShelfPattern pattern in ShelfPattern.values) {
        expect(
          () => paint(painterFor(pattern, acid: true), const Size(240, 320)),
          returnsNormally,
          reason: pattern.name,
        );
      }
    });
  });

  group('узор постоянен', () {
    Future<Uint8List> pixels(ShelfPatternPainter painter) async {
      const Size size = Size(64, 64);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(64, 64);
      final ByteData? data = await image.toByteData();
      picture.dispose();
      image.dispose();
      return data!.buffer.asUint8List();
    }

    test('две отрисовки подряд дают одну и ту же картинку', () async {
      // Узоры со случайной геометрией заводят генератор от хеша названия.
      // Возьми они обычный `Random`, полка мерцала бы при каждой
      // прокрутке — и это тот вид поломки, который в коде не виден.
      for (final ShelfPattern pattern in <ShelfPattern>[
        ShelfPattern.circuit,
        ShelfPattern.glitchBlocks,
        ShelfPattern.nodes,
        ShelfPattern.pixelRain,
      ]) {
        final Uint8List first = await pixels(painterFor(pattern));
        final Uint8List second = await pixels(painterFor(pattern));
        expect(first, second, reason: pattern.name);
      }
    });

    test('разные категории рисуются по-разному', () async {
      final Uint8List one = await pixels(
        painterFor(ShelfPattern.nodes, seed: 0x11111111),
      );
      final Uint8List two = await pixels(
        painterFor(ShelfPattern.nodes, seed: 0x77777777),
      );
      expect(one, isNot(two));
    });
  });

  group('BUG-05: изометрическая сетка доходит до низа участка', () {
    /// Сколько точек закрашено узором в полосе строк [from]…[to].
    ///
    /// Узор спокойный, без свечения: размытый ореол залил бы полосу
    /// целиком, и считать было бы нечего.
    Future<({int top, int bottom})> inkInBands(Size size, int band) async {
      final ShelfPatternPainter painter = painterFor(ShelfPattern.isoGrid);
      final int width = size.width.round();
      final int height = size.height.round();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(width, height);
      final ByteData? data = await image.toByteData();
      picture.dispose();
      image.dispose();
      final Uint8List bytes = data!.buffer.asUint8List();
      final int ground = painter.background.toARGB32();
      final int red = (ground >> 16) & 0xFF;
      final int green = (ground >> 8) & 0xFF;
      final int blue = ground & 0xFF;

      int count(int from, int to) {
        int inked = 0;
        for (int y = from; y < to; y++) {
          for (int x = 0; x < width; x++) {
            final int at = (y * width + x) * 4;
            final int distance =
                (bytes[at] - red).abs() +
                (bytes[at + 1] - green).abs() +
                (bytes[at + 2] - blue).abs();
            if (distance > 6) {
              inked++;
            }
          }
        }
        return inked;
      }

      return (top: count(0, band), bottom: count(height - band, height));
    }

    test('BUG-05: низ высокого участка закрашен, как верх', () async {
      // Раздел «Без категории» у всех рисуется этим узором, и участок в
      // несколько рядов книг заметно выше своей ширины. Наклонные идут
      // под 30° к горизонтали и уходят вбок на 1,73 высоты — начал у
      // верхнего края должно хватать, чтобы обе дошли до нижнего.
      for (final Size size in <Size>[
        const Size(120, 600),
        const Size(200, 900),
        const Size(360, 1400),
      ]) {
        final ({int top, int bottom}) ink = await inkInBands(size, 100);
        expect(ink.top, greaterThan(0), reason: 'узор нарисован, $size');
        expect(
          ink.bottom,
          greaterThan(ink.top * 0.7),
          reason:
              'внизу участка $size закрашено ${ink.bottom} точек против '
              '${ink.top} вверху',
        );
      }
    });
  });

  group('художник перерисовывает только когда надо', () {
    test('тот же вид — не перерисовывать', () {
      expect(
        painterFor(ShelfPattern.hexGrid)
            .shouldRepaint(painterFor(ShelfPattern.hexGrid)),
        isFalse,
      );
    });

    test('другой узор, шаг, толщина или свечение — перерисовать', () {
      final ShelfPatternPainter base = painterFor(ShelfPattern.hexGrid);
      expect(base.shouldRepaint(painterFor(ShelfPattern.maze)), isTrue);
      expect(
        base.shouldRepaint(painterFor(ShelfPattern.hexGrid, step: 44)),
        isTrue,
      );
      expect(
        base.shouldRepaint(painterFor(ShelfPattern.hexGrid, acid: true)),
        isTrue,
      );
    });
  });
}
