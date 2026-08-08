import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/reading_filter.dart';

/// Эталонная таблица: посчитана `tool/make_filter_goldens.py` — другой
/// реализацией той же математики. Картинку фильтра в `flutter test` не
/// получить (шейдеры там не собираются), поэтому «золотым» здесь служит
/// не изображение, а числа: любое случайное изменение формулы валит тест
/// сразу, а совпадение двух независимых реализаций до шестого знака
/// практически исключает ошибку в самой формуле.
const String _goldenPath = 'test/goldens/reading_filters.json';

const String _shaderPath = 'shaders/reading_filter.frag';

ReadingFilter _filterByName(String name) {
  return ReadingFilter.values.firstWhere(
    (ReadingFilter value) => value.name == name,
  );
}

/// Рисует цвет через цветовую матрицу движка и читает, что вышло.
///
/// Проверяется не математика (её проверяет эталонная таблица), а укладка
/// матрицы: строчный порядок и слагаемое в шкале 0…255. Перепутать их —
/// самая дешёвая и самая незаметная ошибка во всём фильтре.
Future<List<double>> _throughEngine(
  List<double> matrix,
  FilteredColor color,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()
      ..color = Color.fromARGB(
        255,
        (color.r * 255).round(),
        (color.g * 255).round(),
        (color.b * 255).round(),
      )
      ..colorFilter = ColorFilter.matrix(matrix),
  );
  final ui.Image image = await recorder.endRecording().toImage(2, 2);
  try {
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final Uint8List bytes = data.buffer.asUint8List();
    return <double>[bytes[0] / 255, bytes[1] / 255, bytes[2] / 255];
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('эталонная таблица', () {
    final Map<String, Object?> golden =
        jsonDecode(File(_goldenPath).readAsStringSync())
            as Map<String, Object?>;
    final List<Object?> cases = golden['cases']! as List<Object?>;

    test('таблица не пустая', () {
      expect(cases.length, greaterThanOrEqualTo(8));
    });

    for (final Object? entry in cases) {
      final Map<String, Object?> item = entry! as Map<String, Object?>;
      final String name = item['filter']! as String;
      final double intensity = (item['intensity']! as num).toDouble();
      final double brightness = (item['brightness']! as num).toDouble();
      final double contrast = (item['contrast']! as num).toDouble();
      final double gamma = (item['gamma']! as num).toDouble();
      final List<Object?> samples = item['samples']! as List<Object?>;

      test(
        '$name: сила $intensity, яркость $brightness, '
        'контраст $contrast, гамма $gamma',
        () {
          final ReadingFilterPipeline pipeline = ReadingFilterPipeline(
            filter: _filterByName(name),
            intensity: intensity,
            brightness: brightness,
            contrast: contrast,
            gamma: gamma,
          );
          for (final Object? raw in samples) {
            final Map<String, Object?> sample = raw! as Map<String, Object?>;
            final List<Object?> input = sample['in']! as List<Object?>;
            final List<Object?> output = sample['out']! as List<Object?>;
            final FilteredColor result = pipeline.apply(
              (input[0]! as num).toDouble(),
              (input[1]! as num).toDouble(),
              (input[2]! as num).toDouble(),
            );
            expect(
              result.r,
              closeTo((output[0]! as num).toDouble(), 1e-6),
              reason: 'красный на $input',
            );
            expect(
              result.g,
              closeTo((output[1]! as num).toDouble(), 1e-6),
              reason: 'зелёный на $input',
            );
            expect(
              result.b,
              closeTo((output[2]! as num).toDouble(), 1e-6),
              reason: 'синий на $input',
            );
          }
        },
      );
    }
  });

  group('смысл фильтров', () {
    test('ночной красный оставляет только красную составляющую', () {
      const ReadingFilterPipeline night = ReadingFilterPipeline(
        filter: ReadingFilter.nightRed,
        intensity: 1,
      );
      final FilteredColor white = night.apply(1, 1, 1);
      expect(white.g, 0);
      expect(white.b, 0);
      expect(white.r, greaterThan(0.9));
    });

    test('тёплый гасит синее сильнее зелёного', () {
      const ReadingFilterPipeline warm = ReadingFilterPipeline(
        filter: ReadingFilter.warm,
        intensity: 1,
      );
      final FilteredColor white = warm.apply(1, 1, 1);
      expect(white.r, 1);
      expect(white.b, lessThan(white.g));
      expect(white.g, lessThan(white.r));
    });

    test('инверсия переворачивает текст и бумагу', () {
      const ReadingFilterPipeline invert = ReadingFilterPipeline(
        filter: ReadingFilter.invert,
        intensity: 1,
      );
      expect(invert.apply(1, 1, 1).r, closeTo(0, 1e-9));
      expect(invert.apply(0, 0, 0).r, closeTo(1, 1e-9));
      expect(invert.apply(0.5, 0.5, 0.5).r, closeTo(0.5, 1e-9));
    });

    test('цветная картинка при инверсии остаётся собой', () {
      // Это и есть «двойная инверсия картинок»: фотография, пропущенная
      // через ночную инверсию, не должна становиться негативом.
      const ReadingFilterPipeline invert = ReadingFilterPipeline(
        filter: ReadingFilter.invert,
        intensity: 1,
      );
      final FilteredColor photo = invert.apply(0.9, 0.2, 0.1);
      expect(photo.r, closeTo(0.9, 0.05));
      expect(photo.g, closeTo(0.2, 0.05));
      expect(photo.b, closeTo(0.1, 0.05));
    });

    test('гамма темнит середину, не трогая края', () {
      const ReadingFilterPipeline gamma = ReadingFilterPipeline(gamma: 2);
      expect(gamma.apply(1, 1, 1).r, closeTo(1, 1e-9));
      expect(gamma.apply(0, 0, 0).r, closeTo(0, 1e-9));
      expect(gamma.apply(0.5, 0.5, 0.5).r, closeTo(0.25, 1e-9));
    });

    test('яркость ниже системного минимума, но не в ноль', () {
      const ReadingFilterPipeline dark = ReadingFilterPipeline(brightness: 0);
      expect(dark.apply(1, 1, 1).r, greaterThan(0));
      expect(dark.apply(1, 1, 1).r, lessThan(0.1));
    });

    test('ничего не настроено — фильтр ничего и не делает', () {
      const ReadingFilterPipeline plain = ReadingFilterPipeline();
      expect(plain.isIdentity, isTrue);
      expect(plain.needsShader, isFalse);
    });

    test('выбранный фильтр сразу заметен', () {
      for (final ReadingFilter filter in ReadingFilter.values) {
        final double intensity = defaultFilterIntensity(filter);
        if (filter == ReadingFilter.none) {
          expect(intensity, 0);
          continue;
        }
        expect(intensity, greaterThan(0.5), reason: '$filter');
      }
    });

    test('гамма и инверсия требуют шейдера, остальное — нет', () {
      expect(const ReadingFilterPipeline(gamma: 1.4).needsShader, isTrue);
      expect(
        const ReadingFilterPipeline(
          filter: ReadingFilter.invert,
          intensity: 1,
        ).needsShader,
        isTrue,
      );
      expect(
        const ReadingFilterPipeline(
          filter: ReadingFilter.sepia,
          intensity: 1,
        ).needsShader,
        isFalse,
      );
    });
  });

  group('запасная цветовая матрица', () {
    test('при гамме 1 совпадает с эталоном', () {
      const List<ReadingFilter> linear = <ReadingFilter>[
        ReadingFilter.none,
        ReadingFilter.nightRed,
        ReadingFilter.warm,
        ReadingFilter.sepia,
      ];
      for (final ReadingFilter filter in linear) {
        final ReadingFilterPipeline pipeline = ReadingFilterPipeline(
          filter: filter,
          intensity: 0.7,
          brightness: 0.8,
          contrast: 1.3,
        );
        final List<double> matrix = pipeline.colorMatrix();
        for (final FilteredColor color in <FilteredColor>[
          const FilteredColor(1, 1, 1),
          const FilteredColor(0, 0, 0),
          const FilteredColor(0.5, 0.5, 0.5),
          const FilteredColor(0.8, 0.3, 0.1),
        ]) {
          final FilteredColor expected = pipeline.apply(
            color.r,
            color.g,
            color.b,
          );
          final List<double> actual = _applyMatrix(matrix, color);
          expect(actual[0], closeTo(expected.r, 1e-9), reason: '$filter R');
          expect(actual[1], closeTo(expected.g, 1e-9), reason: '$filter G');
          expect(actual[2], closeTo(expected.b, 1e-9), reason: '$filter B');
        }
      }
    });

    test('приближение гаммы точно в единице', () {
      const ReadingFilterPipeline plain = ReadingFilterPipeline(gamma: 1);
      final List<double> matrix = plain.colorMatrix();
      expect(matrix[0], closeTo(1, 1e-12));
      expect(matrix[4], closeTo(0, 1e-12));
      expect(matrix[6], closeTo(1, 1e-12));
      expect(matrix[12], closeTo(1, 1e-12));
      expect(matrix[18], closeTo(1, 1e-12));
    });

    test('матрица уложена так, как её ждёт движок', () async {
      const ReadingFilterPipeline sepia = ReadingFilterPipeline(
        filter: ReadingFilter.sepia,
        intensity: 1,
        brightness: 0.9,
      );
      const FilteredColor source = FilteredColor(0.8, 0.5, 0.2);
      final FilteredColor expected = sepia.apply(
        source.r,
        source.g,
        source.b,
      );
      final List<double> actual = await _throughEngine(
        sepia.colorMatrix(),
        source,
      );
      expect(actual[0], closeTo(expected.r, 0.02));
      expect(actual[1], closeTo(expected.g, 0.02));
      expect(actual[2], closeTo(expected.b, 0.02));
    });
  });

  group('договор с шейдером', () {
    final String source = File(_shaderPath).readAsStringSync();

    test('объявлены те же uniform и в том же порядке', () {
      final List<String> declared = RegExp(
        r'^\s*uniform\s+(?:vec2|float)\s+(\w+)\s*;',
        multiLine: true,
      ).allMatches(source).map((RegExpMatch m) => m.group(1)!).toList();
      expect(declared, ReadingFilterPipeline.uniformNames);
    });

    test('первый uniform — vec2, как требует движок', () {
      final String first = ReadingFilterPipeline.uniformNames.first;
      expect(source, contains('uniform vec2 $first;'));
    });

    test('сэмплер страницы назван так же, как в коде', () {
      expect(
        source,
        contains('uniform sampler2D ${ReadingFilterPipeline.samplerName};'),
      );
    });

    test('число значений совпадает с числом uniform после размера', () {
      const ReadingFilterPipeline pipeline = ReadingFilterPipeline();
      expect(
        pipeline.uniformValues().length,
        ReadingFilterPipeline.uniformNames.length - 1,
      );
    });

    test('номера фильтров в шейдере совпадают с порядком в перечислении', () {
      expect(ReadingFilter.values[0], ReadingFilter.none);
      expect(ReadingFilter.values[1], ReadingFilter.nightRed);
      expect(ReadingFilter.values[2], ReadingFilter.warm);
      expect(ReadingFilter.values[3], ReadingFilter.sepia);
      expect(ReadingFilter.values[4], ReadingFilter.invert);
      for (final ReadingFilter filter in ReadingFilter.values) {
        final ReadingFilterPipeline pipeline = ReadingFilterPipeline(
          filter: filter,
          intensity: 1,
        );
        expect(pipeline.uniformValues().first, filter.index.toDouble());
      }
    });

    test('ось Y перевёрнута для OpenGL ES', () {
      // Без этого страница на части Android-устройств встаёт на голову.
      expect(source, contains('IMPELLER_TARGET_OPENGLES'));
    });
  });

  test('фильтр собирается из настроек книги', () {
    const BookReadingSettings settings = BookReadingSettings(
      bookId: 'b',
      orientation: ScreenOrientation.portrait,
      filter: ReadingFilter.sepia,
      filterIntensity: 0.4,
      brightness: 0.6,
      contrast: 1.2,
      gamma: 1.1,
    );
    final ReadingFilterPipeline pipeline = ReadingFilterPipeline.fromSettings(
      settings,
    );
    expect(pipeline.filter, ReadingFilter.sepia);
    expect(pipeline.intensity, 0.4);
    expect(pipeline.brightness, 0.6);
    expect(pipeline.contrast, 1.2);
    expect(pipeline.gamma, 1.1);
    expect(pipeline.isIdentity, isFalse);
  });
}

/// Считает цвет по матрице так же, как это делает движок.
List<double> _applyMatrix(List<double> matrix, FilteredColor color) {
  final List<double> input = <double>[color.r, color.g, color.b];
  return <double>[
    for (int row = 0; row < 3; row++)
      _clamp01(
        matrix[row * 5] * input[0] +
            matrix[row * 5 + 1] * input[1] +
            matrix[row * 5 + 2] * input[2] +
            matrix[row * 5 + 4] / 255,
      ),
  ];
}

double _clamp01(double value) {
  if (value < 0) {
    return 0;
  }
  return value > 1 ? 1 : value;
}
