/// Минимальный кодировщик PNG.
///
/// Зачем свой. Обложка приходит из PDFium сырыми пикселями BGRA, а на
/// диск её надо положить картинкой, которую потом покажет обычный
/// `Image.file`. Готовые пакеты кодирования картинок тянут за собой
/// разбор десятка форматов, которые нам не нужны ни один, — а в открытом
/// проекте каждая зависимость это ещё и лицензия, которую придётся
/// объяснять. Нужный нам PNG — самый простой из возможных: без палитры,
/// без прозрачности, без чересстрочности, все строки с нулевым фильтром.
/// Это шестьдесят строк, и они проверяются обратным разбором.
///
/// Сжатие берётся из `dart:io` (`ZLibCodec`), а не пишется руками: zlib
/// есть на обеих наших платформах, и это ровно тот формат, который PNG
/// ждёт внутри блока `IDAT`.
library;

import 'dart:io';
import 'dart:typed_data';

/// Подпись, с которой начинается любой файл PNG.
const List<int> kPngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

/// Сжатие для блока `IDAT`. Шестой уровень — обычный размен веса и
/// времени; обложка книги жмётся в разы на любом.
final ZLibCodec _zlib = ZLibCodec(level: 6);

/// Кодирует растр BGRA в PNG без прозрачности.
///
/// [pixels] — по четыре байта на пиксель в порядке B, G, R, A, ровно как
/// их отдаёт PDFium. Альфа отбрасывается: страница книги непрозрачна, а
/// лишний канал стоил бы трети веса файла на ровном месте.
///
/// Бросает [ArgumentError], если размеры не сходятся с длиной буфера:
/// молча вернуть испорченную картинку хуже, чем не вернуть никакой.
Uint8List encodeBgraToPng(Uint8List pixels, int width, int height) {
  if (width < 1 || height < 1) {
    throw ArgumentError('размер картинки должен быть положительным');
  }
  if (pixels.length < width * height * 4) {
    throw ArgumentError(
      'пикселей ${pixels.length}, а нужно ${width * height * 4}',
    );
  }

  // Каждая строка PNG начинается байтом фильтра. Ноль означает «строка
  // как есть»: фильтры дают выигрыш на фотографиях, а страница книги —
  // это белый лист с буквами, который zlib и так жмёт в разы.
  final Uint8List raw = Uint8List(height * (1 + width * 3));
  int out = 0;
  for (int y = 0; y < height; y++) {
    raw[out++] = 0;
    int inp = y * width * 4;
    for (int x = 0; x < width; x++) {
      final int b = pixels[inp];
      final int g = pixels[inp + 1];
      final int r = pixels[inp + 2];
      raw[out++] = r;
      raw[out++] = g;
      raw[out++] = b;
      inp += 4;
    }
  }

  final List<int> deflated = _zlib.encode(raw);

  final BytesBuilder file = BytesBuilder();
  file.add(kPngSignature);
  final ByteData header = ByteData(13);
  header.setUint32(0, width);
  header.setUint32(4, height);
  header.setUint8(8, 8); // бит на канал
  header.setUint8(9, 2); // тип цвета: истинный цвет без альфы
  header.setUint8(10, 0); // сжатие: deflate
  header.setUint8(11, 0); // фильтрация: стандартная
  header.setUint8(12, 0); // без чересстрочности
  file.add(_chunk('IHDR', header.buffer.asUint8List()));
  file.add(_chunk('IDAT', Uint8List.fromList(deflated)));
  file.add(_chunk('IEND', Uint8List(0)));
  return file.toBytes();
}

/// Один блок PNG: длина, имя, данные, контрольная сумма.
Uint8List _chunk(String name, Uint8List data) {
  final Uint8List label = Uint8List.fromList(name.codeUnits);
  final Uint8List result = Uint8List(12 + data.length);
  final ByteData view = ByteData.view(result.buffer);
  view.setUint32(0, data.length);
  result.setRange(4, 8, label);
  result.setRange(8, 8 + data.length, data);
  // Сумма считается по имени и данным вместе, но без поля длины.
  view.setUint32(8 + data.length, _crc32(result, 4, 8 + data.length));
  return result;
}

Uint32List? _crcTable;

Uint32List _buildCrcTable() {
  final Uint32List table = Uint32List(256);
  for (int i = 0; i < 256; i++) {
    int c = i;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

/// CRC-32 участка буфера — та же сумма, которой пользуется PNG.
int _crc32(Uint8List bytes, int start, int end) {
  final Uint32List table = _crcTable ??= _buildCrcTable();
  int crc = 0xFFFFFFFF;
  for (int i = start; i < end; i++) {
    crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
