import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/infrastructure/images/png.dart';

/// Растр BGRA заданного размера, раскрашенный по клеткам.
Uint8List _raster(int width, int height) {
  final Uint8List pixels = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      pixels[i] = (x * 7) & 0xFF; // B
      pixels[i + 1] = (y * 11) & 0xFF; // G
      pixels[i + 2] = ((x + y) * 3) & 0xFF; // R
      pixels[i + 3] = 0xFF; // A — отбрасывается
    }
  }
  return pixels;
}

/// Читает блоки PNG подряд: имя и данные.
List<MapEntry<String, Uint8List>> _chunks(Uint8List png) {
  final ByteData view = ByteData.view(png.buffer, png.offsetInBytes);
  final List<MapEntry<String, Uint8List>> result =
      <MapEntry<String, Uint8List>>[];
  int at = kPngSignature.length;
  while (at + 8 <= png.length) {
    final int length = view.getUint32(at);
    final String name = String.fromCharCodes(png, at + 4, at + 8);
    final Uint8List data = Uint8List.sublistView(png, at + 8, at + 8 + length);
    result.add(MapEntry<String, Uint8List>(name, data));
    at += 12 + length;
  }
  return result;
}

void main() {
  // Декодер картинок живёт в движке: без поднятого окружения
  // `instantiateImageCodec` не с чем работать.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('кодировщик PNG', () {
    test('файл начинается подписью и кончается IEND', () {
      final Uint8List png = encodeBgraToPng(_raster(4, 3), 4, 3);
      expect(png.sublist(0, 8), kPngSignature);
      final List<String> names = _chunks(
        png,
      ).map((MapEntry<String, Uint8List> e) => e.key).toList();
      expect(names.first, 'IHDR');
      expect(names.last, 'IEND');
      expect(names, contains('IDAT'));
    });

    test('заголовок описывает истинный цвет без альфы', () {
      final Uint8List png = encodeBgraToPng(_raster(7, 5), 7, 5);
      final Uint8List header = _chunks(png).first.value;
      final ByteData view = ByteData.view(
        header.buffer,
        header.offsetInBytes,
        header.length,
      );
      expect(view.getUint32(0), 7, reason: 'ширина');
      expect(view.getUint32(4), 5, reason: 'высота');
      expect(header[8], 8, reason: 'бит на канал');
      expect(header[9], 2, reason: 'тип цвета: RGB');
      expect(header[10], 0, reason: 'сжатие deflate');
      expect(header[11], 0, reason: 'стандартная фильтрация');
      expect(header[12], 0, reason: 'без чересстрочности');
    });

    test('распакованные строки совпадают с исходными пикселями', () {
      const int width = 9;
      const int height = 6;
      final Uint8List pixels = _raster(width, height);
      final Uint8List png = encodeBgraToPng(pixels, width, height);
      final Uint8List idat = _chunks(
        png,
      ).firstWhere((MapEntry<String, Uint8List> e) => e.key == 'IDAT').value;
      final List<int> raw = ZLibCodec().decode(idat);

      expect(raw.length, height * (1 + width * 3));
      for (int y = 0; y < height; y++) {
        final int row = y * (1 + width * 3);
        expect(raw[row], 0, reason: 'фильтр строки $y');
        for (int x = 0; x < width; x++) {
          final int src = (y * width + x) * 4;
          final int dst = row + 1 + x * 3;
          // Порядок каналов переставлен: PDFium отдаёт BGRA, PNG ждёт RGB.
          expect(raw[dst], pixels[src + 2], reason: 'R в ($x, $y)');
          expect(raw[dst + 1], pixels[src + 1], reason: 'G в ($x, $y)');
          expect(raw[dst + 2], pixels[src], reason: 'B в ($x, $y)');
        }
      }
    });

    test('контрольные суммы блоков сходятся', () {
      // Испорченная сумма — это картинка, которую откажется показывать
      // ровно половина программ, а наша покажет: без этой проверки
      // ошибка вылезла бы на чужом устройстве.
      final Uint8List png = encodeBgraToPng(_raster(5, 5), 5, 5);
      int at = kPngSignature.length;
      final ByteData view = ByteData.view(png.buffer, png.offsetInBytes);
      while (at + 8 <= png.length) {
        final int length = view.getUint32(at);
        final int stored = view.getUint32(at + 8 + length);
        final int actual = _crc32(png, at + 4, at + 8 + length);
        expect(stored, actual, reason: 'сумма блока по смещению $at');
        at += 12 + length;
      }
    });

    test('картинка читается настоящим декодером', () async {
      // Главная проверка: не «мы написали то, что задумали», а «это
      // действительно PNG». Декодер здесь чужой — тот самый, которым
      // Flutter показывает обложку на полке.
      const int width = 12;
      const int height = 8;
      final Uint8List png = encodeBgraToPng(
        _raster(width, height),
        width,
        height,
      );
      final ui.Codec codec = await ui.instantiateImageCodec(png);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      expect(image.width, width);
      expect(image.height, height);

      final ByteData? decoded = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(decoded, isNotNull);
      final Uint8List rgba = decoded!.buffer.asUint8List();
      final Uint8List source = _raster(width, height);
      for (final int index in <int>[0, 5, width * 3 + 7, width * height - 1]) {
        expect(rgba[index * 4], source[index * 4 + 2], reason: 'R #$index');
        expect(rgba[index * 4 + 1], source[index * 4 + 1], reason: 'G #$index');
        expect(rgba[index * 4 + 2], source[index * 4], reason: 'B #$index');
        expect(rgba[index * 4 + 3], 255, reason: 'обложка непрозрачна');
      }
      image.dispose();
      codec.dispose();
    });

    test('несходящийся размер — ошибка, а не испорченная картинка', () {
      expect(() => encodeBgraToPng(Uint8List(10), 4, 3), throwsArgumentError);
      expect(() => encodeBgraToPng(Uint8List(4), 0, 1), throwsArgumentError);
      expect(() => encodeBgraToPng(Uint8List(4), 1, 0), throwsArgumentError);
    });

    test('одинаковый вход даёт одинаковый файл', () {
      // Кэш обложек опознаёт готовое по имени файла, но повторяемость
      // упаковки — то, на что опираются и тесты, и сравнение сборок.
      final Uint8List a = encodeBgraToPng(_raster(6, 6), 6, 6);
      final Uint8List b = encodeBgraToPng(_raster(6, 6), 6, 6);
      expect(a, b);
    });
  });
}

/// CRC-32, как в PNG. Своя копия: в рабочем коде она приватная, и
/// открывать её наружу ради теста — плохой размен.
int _crc32(Uint8List bytes, int start, int end) {
  final Uint32List table = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    int c = i;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  int crc = 0xFFFFFFFF;
  for (int i = start; i < end; i++) {
    crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
