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

  group('художник перерисовывает только когда надо', () {
    test('тот же вид — не перерисовывать', () {
      expect(
        painterFor(
          ShelfPattern.hexGrid,
        ).shouldRepaint(painterFor(ShelfPattern.hexGrid)),
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
