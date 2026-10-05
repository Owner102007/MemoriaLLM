/// Запись ZIP-архива потоком, без сборки в памяти (SNO-ALG-REC-03).
///
/// Запись сессии исследования СНО2026 уходит с устройства одним файлом
/// (SNO-F-REC-05): его открывают «Проводником», 7-Zip и разбором на
/// Python, поэтому архив — самый обычный ZIP, без расширений.
///
/// Писатель свой по той же причине, что читатель (`zip_reader.dart`):
/// пакет `archive` стоит в замке чужой зависимостью, и взять его
/// напрямую значило бы править замок. Сжатие — Deflate из `dart:io`.
///
/// Длины и контрольная сумма записи известны только после того, как
/// она сжата. Описателя данных после записи (флаг 3) здесь нет: не
/// каждый распаковщик его понимает. Вместо этого писатель возвращается
/// к заголовку записи и вписывает числа на место — файл на диске это
/// позволяет. ZIP64 нет: архив записи — мегабайты, а не гигабайты;
/// запись длиннее 4 ГБ — отказ, а не тихо испорченный архив.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zip_reader.dart';

/// Почему архив не записался.
class ZipWriteException implements Exception {
  /// Создаёт отказ.
  const ZipWriteException(this.reason, {this.entry});

  /// Причина словами — для журнала, не для экрана.
  final String reason;

  /// Имя записи, на которой случился отказ.
  final String? entry;

  @override
  String toString() => 'ZipWriteException($reason, $entry)';
}

/// Что легло в архив одной записью.
class ZipWritten {
  /// Создаёт сведения.
  const ZipWritten({
    required this.name,
    required this.size,
    required this.compressedSize,
    required this.crc32,
  });

  /// Имя записи.
  final String name;

  /// Сколько байт в исходном содержимом.
  final int size;

  /// Сколько байт запись заняла в архиве.
  final int compressedSize;

  /// Контрольная сумма содержимого.
  final int crc32;
}

const int _localSignature = 0x04034b50;
const int _centralSignature = 0x02014b50;
const int _endSignature = 0x06054b50;

/// Версия формата, нужная распаковщику: 2.0 — Deflate.
const int _version = 20;

/// Способ сжатия Deflate.
const int _deflate = 8;

/// Признак «имя в UTF-8».
const int _utf8Flag = 0x800;

/// Больше этого поле длины обычного ZIP не вмещает.
const int _limit32 = 0xFFFFFFFF;

/// Больше записей оглавление обычного ZIP не вмещает.
const int _limit16 = 0xFFFF;

class _Entry {
  _Entry({
    required this.name,
    required this.flags,
    required this.time,
    required this.date,
    required this.offset,
  });

  final Uint8List name;
  final int flags;
  final int time;
  final int date;
  final int offset;
  int crc32 = 0;
  int size = 0;
  int compressedSize = 0;
}

/// Архив, который пишется на диск запись за записью.
///
/// Порядок записей — порядок вызовов [add]. Архив годен только после
/// [finish]: оглавление ZIP лежит в конце файла.
class ZipWriter {
  ZipWriter._(this._file);

  /// Начинает архив в файле [target]; прежнее содержимое стирается.
  static Future<ZipWriter> create(File target) async {
    return ZipWriter._(await target.open(mode: FileMode.write));
  }

  final RandomAccessFile _file;
  final List<_Entry> _entries = <_Entry>[];
  final Set<String> _names = <String>{};
  int _position = 0;
  bool _closed = false;

  /// Кладёт в архив запись [name] с содержимым [content].
  ///
  /// Имя — с путём через `/`, без `\`, без `..` и не от корня: такие
  /// имена распаковщики читают по-разному. [modified] — время файла в
  /// оглавлении. Содержимое читается потоком и в памяти целиком не
  /// лежит.
  Future<ZipWritten> add(
    String name,
    Stream<List<int>> content, {
    DateTime? modified,
  }) async {
    if (_closed) {
      throw ZipWriteException('архив уже закрыт', entry: name);
    }
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.endsWith('/') ||
        name.contains(r'\') ||
        name.split('/').any((String part) => part.isEmpty || part == '..')) {
      throw ZipWriteException('имя записи не годится', entry: name);
    }
    if (!_names.add(name)) {
      throw ZipWriteException('запись с таким именем уже есть', entry: name);
    }
    if (_entries.length >= _limit16) {
      throw ZipWriteException('слишком много записей', entry: name);
    }
    final Uint8List nameBytes = Uint8List.fromList(utf8.encode(name));
    if (nameBytes.length > _limit16) {
      throw ZipWriteException('имя записи слишком длинное', entry: name);
    }
    final DateTime stamp = (modified ?? DateTime.now()).toLocal();
    final _Entry entry = _Entry(
      name: nameBytes,
      // Имя латиницей читается одинаково в любой кодировке; иначе —
      // сказано, что оно в UTF-8.
      flags: nameBytes.any((int byte) => byte >= 0x80) ? _utf8Flag : 0,
      time: _dosTime(stamp),
      date: _dosDate(stamp),
      offset: _position,
    );
    await _write(_localHeader(entry));

    final Crc32 crc = Crc32();
    final RawZLibFilter deflate = RawZLibFilter.deflateFilter(raw: true);
    int size = 0;
    int packed = 0;
    // Пока поток идёт, сжатое забирается без сброса; сброс — в конце.
    List<int>? next({required bool end}) {
      return end
          ? deflate.processed(end: true)
          : deflate.processed(flush: false);
    }

    Future<void> drain({required bool end}) async {
      List<int>? out = next(end: end);
      while (out != null) {
        packed += out.length;
        await _write(out);
        out = next(end: end);
      }
    }

    await for (final List<int> chunk in content) {
      if (chunk.isEmpty) {
        continue;
      }
      size += chunk.length;
      crc.add(chunk);
      deflate.process(chunk, 0, chunk.length);
      await drain(end: false);
    }
    await drain(end: true);
    if (size > _limit32 || packed > _limit32 || _position > _limit32) {
      throw ZipWriteException('запись больше 4 ГБ', entry: name);
    }
    entry
      ..crc32 = crc.value
      ..size = size
      ..compressedSize = packed;

    // Числа — на место в заголовке записи: он уже лежит на диске с
    // нулями вместо них.
    final ByteData sums = ByteData(12)
      ..setUint32(0, entry.crc32, Endian.little)
      ..setUint32(4, entry.compressedSize, Endian.little)
      ..setUint32(8, entry.size, Endian.little);
    await _file.setPosition(entry.offset + 14);
    await _file.writeFrom(sums.buffer.asUint8List());
    await _file.setPosition(_position);

    _entries.add(entry);
    return ZipWritten(
      name: name,
      size: size,
      compressedSize: packed,
      crc32: entry.crc32,
    );
  }

  /// Кладёт в архив запись [name] с готовым содержимым [bytes].
  Future<ZipWritten> addBytes(
    String name,
    List<int> bytes, {
    DateTime? modified,
  }) {
    return add(name, Stream<List<int>>.value(bytes), modified: modified);
  }

  /// Дописывает оглавление, сбрасывает файл на диск и закрывает его.
  Future<void> finish() async {
    if (_closed) {
      return;
    }
    final int directory = _position;
    for (final _Entry entry in _entries) {
      await _write(_centralHeader(entry));
    }
    final int directorySize = _position - directory;
    if (_position > _limit32) {
      throw const ZipWriteException('архив больше 4 ГБ');
    }
    final ByteData end = ByteData(22)
      ..setUint32(0, _endSignature, Endian.little)
      // Номер тома и том оглавления: архив из одного файла.
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _entries.length, Endian.little)
      ..setUint16(10, _entries.length, Endian.little)
      ..setUint32(12, directorySize, Endian.little)
      ..setUint32(16, directory, Endian.little)
      // Комментария нет.
      ..setUint16(20, 0, Endian.little);
    await _write(end.buffer.asUint8List());
    _closed = true;
    await _file.flush();
    await _file.close();
  }

  /// Закрывает файл, не дописывая оглавления: архив не состоялся, и
  /// тот, кто его начал, уберёт обрывок.
  Future<void> abort() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _file.close();
    } on FileSystemException {
      // Файл уже не закрыть — убирать обрывок всё равно вызывающему.
    }
  }

  Future<void> _write(List<int> bytes) async {
    if (bytes.isEmpty) {
      return;
    }
    await _file.writeFrom(bytes);
    _position += bytes.length;
  }

  Uint8List _localHeader(_Entry entry) {
    final ByteData head = ByteData(30)
      ..setUint32(0, _localSignature, Endian.little)
      ..setUint16(4, _version, Endian.little)
      ..setUint16(6, entry.flags, Endian.little)
      ..setUint16(8, _deflate, Endian.little)
      ..setUint16(10, entry.time, Endian.little)
      ..setUint16(12, entry.date, Endian.little)
      // Сумма и длины (14…25) вписываются после сжатия.
      ..setUint16(26, entry.name.length, Endian.little)
      // Дополнительного поля нет.
      ..setUint16(28, 0, Endian.little);
    return Uint8List(30 + entry.name.length)
      ..setAll(0, head.buffer.asUint8List())
      ..setAll(30, entry.name);
  }

  Uint8List _centralHeader(_Entry entry) {
    final ByteData head = ByteData(46)
      ..setUint32(0, _centralSignature, Endian.little)
      // Чем создано и что нужно распаковщику.
      ..setUint16(4, _version, Endian.little)
      ..setUint16(6, _version, Endian.little)
      ..setUint16(8, entry.flags, Endian.little)
      ..setUint16(10, _deflate, Endian.little)
      ..setUint16(12, entry.time, Endian.little)
      ..setUint16(14, entry.date, Endian.little)
      ..setUint32(16, entry.crc32, Endian.little)
      ..setUint32(20, entry.compressedSize, Endian.little)
      ..setUint32(24, entry.size, Endian.little)
      ..setUint16(28, entry.name.length, Endian.little)
      // Дополнительного поля, комментария, номера тома, внутренних и
      // внешних признаков нет (30…41).
      ..setUint32(42, entry.offset, Endian.little);
    return Uint8List(46 + entry.name.length)
      ..setAll(0, head.buffer.asUint8List())
      ..setAll(46, entry.name);
  }
}

/// Время в формате оглавления ZIP: секунды — с шагом в две.
int _dosTime(DateTime moment) {
  return (moment.hour << 11) | (moment.minute << 5) | (moment.second ~/ 2);
}

/// Дата в формате оглавления ZIP: годы считаются от 1980-го.
int _dosDate(DateTime moment) {
  if (moment.year < 1980) {
    return (1 << 5) | 1;
  }
  final int year = moment.year > 2107 ? 2107 : moment.year;
  return ((year - 1980) << 9) | (moment.month << 5) | moment.day;
}
