/// Чтение ZIP-архива кусками, без распаковки в память (SNO-ALG-LIT-01).
///
/// Литература приходит тестировщикам исследования СНО2026 одним архивом
/// (SNO-F-LIT-01): его собирают «Проводником» или 7-Zip, а приложение
/// раскладывает книги по полке. Архив читается там, где лежит, — через
/// тот же [BookHandle], каким читается книга: на Windows это файл, на
/// Android — документ по дескриптору. Оглавление ZIP стоит в конце
/// файла, поэтому нужны перескоки, а не поток.
///
/// Читатель свой, а не пакет `archive`: замок зависимостей не трогается
/// ради двух способов сжатия. Понимает записи без сжатия и Deflate,
/// ZIP64, описатель данных после записи; сверяет CRC-32. Не понимает —
/// и говорит об этом [ZipException] — пароль, LZMA и bzip2, многотомные
/// архивы.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/library/book_storage.dart';

/// Сколько байт архива читается за раз.
///
/// Величина постоянная: книга любого размера распаковывается одним и тем
/// же буфером, и память не растёт с размером книги.
const int zipChunkSize = 256 * 1024;

/// Что не так с архивом.
enum ZipProblem {
  /// Это не ZIP.
  notZip,

  /// Архив оборван: начало ZIP есть, оглавления в конце нет.
  truncated,

  /// Оглавление или запись не разбираются.
  damaged,

  /// Запись защищена паролем.
  encrypted,

  /// Способ сжатия не Deflate и не «без сжатия».
  unsupportedMethod,

  /// Архив разбит на тома.
  multiDisk,

  /// Распакованное не сошлось с контрольной суммой или длиной.
  badChecksum,

  /// Архив не читается: место, где он лежит, не отдаёт байты.
  unreadable,
}

/// Отказ читателя архива.
class ZipException implements Exception {
  /// Создаёт отказ.
  const ZipException(this.problem, {this.entry});

  /// Причина.
  final ZipProblem problem;

  /// Имя записи, на которой случился отказ; `null` — отказ про архив
  /// целиком.
  final String? entry;

  @override
  String toString() => 'ZipException(${problem.name}, $entry)';
}

/// Запись архива — строка его оглавления.
class ZipEntry {
  /// Создаёт запись.
  const ZipEntry({
    required this.name,
    required this.method,
    required this.flags,
    required this.crc32,
    required this.compressedSize,
    required this.size,
    required this.headerOffset,
  });

  /// Имя с путём; папки разделены `/`. У записи-папки кончается на `/`.
  final String name;

  /// Способ сжатия: 0 — без сжатия, 8 — Deflate.
  final int method;

  /// Флаги общего назначения.
  final int flags;

  /// Контрольная сумма распакованного.
  final int crc32;

  /// Сколько байт запись занимает в архиве.
  final int compressedSize;

  /// Сколько байт в распакованной записи.
  final int size;

  /// Где в архиве стоит заголовок записи.
  final int headerOffset;

  /// Запись-папка: файла за ней нет.
  bool get isDirectory => name.endsWith('/');

  /// Защищена ли запись паролем.
  bool get isEncrypted => flags & 0x1 != 0;

  /// Лежит ли запись без сжатия.
  bool get isStored => method == _methodStored;

  /// Умеем ли мы распаковать запись.
  bool get isSupported => method == _methodStored || method == _methodDeflate;

  @override
  String toString() => 'ZipEntry($name, $size)';
}

const int _methodStored = 0;
const int _methodDeflate = 8;

const int _endSignature = 0x06054b50;
const int _end64Signature = 0x06064b50;
const int _locator64Signature = 0x07064b50;
const int _centralSignature = 0x02014b50;
const int _localSignature = 0x04034b50;

const int _endSize = 22;
const int _locator64Size = 20;
const int _end64Size = 56;
const int _centralSize = 46;
const int _localSize = 30;

/// Признак «имя в UTF-8».
const int _utf8Flag = 0x800;

/// Дополнительное поле ZIP64.
const int _extra64 = 0x0001;

/// Дополнительное поле Info-ZIP «имя в Юникоде».
const int _extraUnicodePath = 0x7075;

/// Оглавление больше этого — не оглавление, а мусор на его месте.
const int zipDirectoryLimit = 64 * 1024 * 1024;

/// Открытый архив: оглавление прочитано, записи распаковываются по одной.
class ZipArchive {
  ZipArchive._(this._handle, this.entries);

  final BookHandle _handle;

  /// Записи в порядке оглавления, включая записи-папки.
  final List<ZipEntry> entries;

  /// Читает оглавление архива.
  ///
  /// Бросает [ZipException]: не ZIP, оборван, повреждён, многотомный.
  /// Сам [handle] не закрывает — им распоряжается тот, кто его открыл.
  ///
  /// [directoryLimit] — оглавление больше этого не читается вовсе
  /// ([ZipProblem.damaged]). Поиск архивов с книгами (SNO-ALG-LIT-02)
  /// ставит предел ниже обычного: он заглядывает в каждый ZIP на
  /// устройстве, и чужой архив в сотни тысяч записей не должен стоить
  /// ему сотен мегабайт памяти.
  static Future<ZipArchive> read(
    BookHandle handle, {
    int directoryLimit = zipDirectoryLimit,
  }) async {
    final int length = handle.length;
    if (length < _endSize) {
      throw await _noDirectory(handle);
    }
    // Конец оглавления — последняя запись файла, за ней только
    // комментарий не длиннее 65 535 байт.
    final int tailSize = length < _endSize + 0xFFFF
        ? length
        : _endSize + 0xFFFF;
    final int tailStart = length - tailSize;
    final Uint8List tail = await _readAt(handle, tailStart, tailSize);
    final ByteData tailData = ByteData.sublistView(tail);
    int end = -1;
    for (int i = tailSize - _endSize; i >= 0; i--) {
      if (tailData.getUint32(i, Endian.little) == _endSignature &&
          i + _endSize + tailData.getUint16(i + 20, Endian.little) <=
              tailSize) {
        end = i;
        break;
      }
    }
    if (end < 0) {
      throw await _noDirectory(handle);
    }

    int disk = tailData.getUint16(end + 4, Endian.little);
    int directoryDisk = tailData.getUint16(end + 6, Endian.little);
    int count = tailData.getUint16(end + 10, Endian.little);
    int directorySize = tailData.getUint32(end + 12, Endian.little);
    int directoryOffset = tailData.getUint32(end + 16, Endian.little);
    int directoryEnd = tailStart + end;

    // ZIP64: настоящие числа лежат в отдельной записи, а на неё
    // указывает метка прямо перед концом оглавления. Архив больше 4 ГБ
    // и архив, собранный с ключом «всегда ZIP64», устроены так.
    final int locator = tailStart + end - _locator64Size;
    if (locator >= 0) {
      final ByteData mark = ByteData.sublistView(
        await _readAt(handle, locator, _locator64Size),
      );
      if (mark.getUint32(0, Endian.little) == _locator64Signature) {
        final int end64 = mark.getUint64(8, Endian.little);
        if (end64 < 0 || end64 + _end64Size > length) {
          throw const ZipException(ZipProblem.damaged);
        }
        final ByteData wide = ByteData.sublistView(
          await _readAt(handle, end64, _end64Size),
        );
        if (wide.getUint32(0, Endian.little) != _end64Signature) {
          throw const ZipException(ZipProblem.damaged);
        }
        disk = wide.getUint32(16, Endian.little);
        directoryDisk = wide.getUint32(20, Endian.little);
        count = wide.getUint64(32, Endian.little);
        directorySize = wide.getUint64(40, Endian.little);
        directoryOffset = wide.getUint64(48, Endian.little);
        directoryEnd = end64;
      }
    }

    if (disk != 0 || directoryDisk != 0) {
      throw const ZipException(ZipProblem.multiDisk);
    }
    if (count < 0 ||
        directorySize < 0 ||
        directoryOffset < 0 ||
        directorySize > directoryLimit ||
        directoryOffset + directorySize > directoryEnd) {
      throw const ZipException(ZipProblem.damaged);
    }

    final Uint8List directory = await _readAt(
      handle,
      directoryOffset,
      directorySize,
    );
    return ZipArchive._(handle, _parseDirectory(directory, count));
  }

  /// Распаковывает [entry], отдавая содержимое кусками в [onChunk].
  ///
  /// Кусок действителен только до возврата из [onChunk]: буфер один на
  /// всю запись. В конце длина и CRC-32 сверяются с оглавлением; не
  /// сошлись — [ZipProblem.badChecksum].
  ///
  /// [chunkSize] — сколько байт архива читается за раз; меняется только
  /// в тестах, чтобы границы кусков проверялись на маленьких архивах.
  Future<void> extract(
    ZipEntry entry,
    Future<void> Function(Uint8List chunk) onChunk, {
    int chunkSize = zipChunkSize,
  }) async {
    if (entry.isEncrypted) {
      throw ZipException(ZipProblem.encrypted, entry: entry.name);
    }
    if (!entry.isSupported) {
      throw ZipException(ZipProblem.unsupportedMethod, entry: entry.name);
    }
    final int start = await _dataStart(entry);
    final _Checked checked = _Checked(entry, onChunk);
    final Uint8List buffer = Uint8List(chunkSize);
    // Пустой записи распаковывать нечего, каким бы способом она ни
    // была помечена.
    final RawZLibFilter? inflate = entry.isStored || entry.compressedSize == 0
        ? null
        : RawZLibFilter.inflateFilter(raw: true);
    int done = 0;
    while (done < entry.compressedSize) {
      final int rest = entry.compressedSize - done;
      final int want = rest < chunkSize ? rest : chunkSize;
      final int got = await _readInto(_handle, buffer, start + done, want);
      if (got < want) {
        throw ZipException(ZipProblem.truncated, entry: entry.name);
      }
      done += got;
      if (inflate == null) {
        await checked.add(Uint8List.sublistView(buffer, 0, got));
        continue;
      }
      try {
        inflate.process(buffer, 0, got);
        List<int>? out = inflate.processed(flush: false);
        while (out != null) {
          await checked.add(_bytes(out));
          out = inflate.processed(flush: false);
        }
      } on FormatException {
        throw ZipException(ZipProblem.damaged, entry: entry.name);
      }
    }
    if (inflate != null) {
      try {
        List<int>? out = inflate.processed(end: true);
        while (out != null) {
          await checked.add(_bytes(out));
          out = inflate.processed(end: true);
        }
      } on FormatException {
        throw ZipException(ZipProblem.damaged, entry: entry.name);
      }
    }
    checked.finish();
  }

  /// Запись без сжатия как книга: её байты лежат в архиве подряд.
  ///
  /// Нужна, чтобы посчитать отпечаток книги, не распаковывая её: по
  /// нему видно, что книга уже стоит на полке. Возвращённое закрывать
  /// не нужно — архив закрывает тот, кто его открыл.
  Future<BookHandle> stored(ZipEntry entry) async {
    if (!entry.isStored || entry.isEncrypted) {
      throw ZipException(ZipProblem.unsupportedMethod, entry: entry.name);
    }
    final int start = await _dataStart(entry);
    if (start + entry.size > _handle.length) {
      throw ZipException(ZipProblem.truncated, entry: entry.name);
    }
    return _RangeHandle(_handle, start, entry.size);
  }

  /// Где начинаются данные записи.
  ///
  /// Длины имени и дополнительного поля у заголовка записи свои, и с
  /// оглавлением они совпадать не обязаны — поэтому заголовок читается.
  Future<int> _dataStart(ZipEntry entry) async {
    if (entry.headerOffset + _localSize > _handle.length) {
      throw ZipException(ZipProblem.truncated, entry: entry.name);
    }
    final ByteData header = ByteData.sublistView(
      await _readAt(_handle, entry.headerOffset, _localSize),
    );
    if (header.getUint32(0, Endian.little) != _localSignature) {
      throw ZipException(ZipProblem.damaged, entry: entry.name);
    }
    final int start =
        entry.headerOffset +
        _localSize +
        header.getUint16(26, Endian.little) +
        header.getUint16(28, Endian.little);
    if (start + entry.compressedSize > _handle.length) {
      throw ZipException(ZipProblem.truncated, entry: entry.name);
    }
    return start;
  }
}

/// Считает длину и CRC-32 распакованного и сверяет их с оглавлением.
class _Checked {
  _Checked(this._entry, this._onChunk);

  final ZipEntry _entry;
  final Future<void> Function(Uint8List chunk) _onChunk;

  int _crc = 0xFFFFFFFF;
  int _written = 0;

  Future<void> add(Uint8List chunk) async {
    if (chunk.isEmpty) {
      return;
    }
    _written += chunk.length;
    // Запись длиннее обещанного — оглавление врёт. Остановиться надо
    // сразу: писать на диск сколько угодно нельзя.
    if (_written > _entry.size) {
      throw ZipException(ZipProblem.badChecksum, entry: _entry.name);
    }
    _crc = _crcUpdate(_crc, chunk);
    await _onChunk(chunk);
  }

  void finish() {
    if (_written != _entry.size || (_crc ^ 0xFFFFFFFF) != _entry.crc32) {
      throw ZipException(ZipProblem.badChecksum, entry: _entry.name);
    }
  }
}

/// Кусок чужого файла как самостоятельная книга.
class _RangeHandle implements BookHandle {
  _RangeHandle(this._inner, this._start, this.length);

  final BookHandle _inner;
  final int _start;

  @override
  final int length;

  @override
  String? get path => null;

  @override
  Future<int> read(Uint8List buffer, int position, int size) async {
    if (size <= 0 || position >= length) {
      return 0;
    }
    final int want = position + size > length ? length - position : size;
    return _readInto(_inner, buffer, _start + position, want);
  }

  @override
  Future<void> close() async {}
}

/// Разбирает оглавление архива.
List<ZipEntry> _parseDirectory(Uint8List directory, int count) {
  final ByteData data = ByteData.sublistView(directory);
  final List<_RawEntry> raw = <_RawEntry>[];
  int at = 0;
  for (int i = 0; i < count; i++) {
    if (at + _centralSize > directory.length ||
        data.getUint32(at, Endian.little) != _centralSignature) {
      throw const ZipException(ZipProblem.damaged);
    }
    final int flags = data.getUint16(at + 8, Endian.little);
    final int method = data.getUint16(at + 10, Endian.little);
    final int crc = data.getUint32(at + 16, Endian.little);
    int compressedSize = data.getUint32(at + 20, Endian.little);
    int size = data.getUint32(at + 24, Endian.little);
    final int nameLength = data.getUint16(at + 28, Endian.little);
    final int extraLength = data.getUint16(at + 30, Endian.little);
    final int commentLength = data.getUint16(at + 32, Endian.little);
    int disk = data.getUint16(at + 34, Endian.little);
    int headerOffset = data.getUint32(at + 42, Endian.little);
    final int nameStart = at + _centralSize;
    final int extraStart = nameStart + nameLength;
    final int next = extraStart + extraLength + commentLength;
    if (next > directory.length) {
      throw const ZipException(ZipProblem.damaged);
    }
    final Uint8List name = Uint8List.sublistView(
      directory,
      nameStart,
      extraStart,
    );

    String? unicodeName;
    int field = extraStart;
    final int extraEnd = extraStart + extraLength;
    while (field + 4 <= extraEnd) {
      final int id = data.getUint16(field, Endian.little);
      final int fieldSize = data.getUint16(field + 2, Endian.little);
      final int body = field + 4;
      if (body + fieldSize > extraEnd) {
        break;
      }
      if (id == _extra64) {
        // Поля идут в этом порядке, и каждое есть, только если его
        // короткий двойник в оглавлении забит единицами.
        int cursor = body;
        final int fieldEnd = body + fieldSize;
        if (size == 0xFFFFFFFF && cursor + 8 <= fieldEnd) {
          size = data.getUint64(cursor, Endian.little);
          cursor += 8;
        }
        if (compressedSize == 0xFFFFFFFF && cursor + 8 <= fieldEnd) {
          compressedSize = data.getUint64(cursor, Endian.little);
          cursor += 8;
        }
        if (headerOffset == 0xFFFFFFFF && cursor + 8 <= fieldEnd) {
          headerOffset = data.getUint64(cursor, Endian.little);
          cursor += 8;
        }
        if (disk == 0xFFFF && cursor + 4 <= fieldEnd) {
          disk = data.getUint32(cursor, Endian.little);
        }
      } else if (id == _extraUnicodePath && fieldSize > 5) {
        // Имя в Юникоде годится, только если оно про это же имя:
        // рядом лежит контрольная сумма обычного.
        final bool sameName =
            data.getUint8(body) == 1 &&
            data.getUint32(body + 1, Endian.little) == crc32Of(name);
        if (sameName) {
          unicodeName = utf8.decode(
            Uint8List.sublistView(directory, body + 5, body + fieldSize),
            allowMalformed: true,
          );
        }
      }
      field = body + fieldSize;
    }

    if (disk != 0) {
      throw const ZipException(ZipProblem.multiDisk);
    }
    if (size < 0 || compressedSize < 0 || headerOffset < 0) {
      throw const ZipException(ZipProblem.damaged);
    }
    raw.add(
      _RawEntry(
        name: name,
        unicodeName: unicodeName,
        entry: ZipEntry(
          name: '',
          method: method,
          flags: flags,
          crc32: crc,
          compressedSize: compressedSize,
          size: size,
          headerOffset: headerOffset,
        ),
      ),
    );
    at = next;
  }

  // Кодировка имён без признака UTF-8 решается на весь архив разом:
  // одно короткое русское имя в 866-й странице может случайно оказаться
  // правильным UTF-8, все имена архива сразу — нет.
  final bool legacyIsUtf8 = raw
      .where((_RawEntry item) => item.entry.flags & _utf8Flag == 0)
      .every((_RawEntry item) => _isUtf8(item.name));
  return <ZipEntry>[
    for (final _RawEntry item in raw)
      ZipEntry(
        name: _entryName(item, legacyIsUtf8: legacyIsUtf8),
        method: item.entry.method,
        flags: item.entry.flags,
        crc32: item.entry.crc32,
        compressedSize: item.entry.compressedSize,
        size: item.entry.size,
        headerOffset: item.entry.headerOffset,
      ),
  ];
}

class _RawEntry {
  const _RawEntry({
    required this.name,
    required this.unicodeName,
    required this.entry,
  });

  final Uint8List name;
  final String? unicodeName;
  final ZipEntry entry;
}

/// Имя записи словами.
///
/// Признак UTF-8 — верим ему. Имя в Юникоде рядом — берём его (так пишет
/// WinRAR). Иначе имя в кодировке системы, где архив собран: «Проводник»
/// и 7-Zip на русской Windows пишут в 866-й странице, macOS и Android —
/// в UTF-8 без признака.
String _entryName(_RawEntry item, {required bool legacyIsUtf8}) {
  final String name;
  if (item.entry.flags & _utf8Flag != 0) {
    name = utf8.decode(item.name, allowMalformed: true);
  } else if (item.unicodeName != null) {
    name = item.unicodeName!;
  } else if (legacyIsUtf8) {
    name = utf8.decode(item.name, allowMalformed: true);
  } else {
    name = decodeCp866(item.name);
  }
  // Некоторые архиваторы Windows разделяют папки обратной чертой.
  return name.replaceAll(r'\', '/');
}

bool _isUtf8(Uint8List bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// Верхняя половина 866-й кодовой страницы: байты от 0x80 до 0xFF.
const String _cp866High =
    'АБВГДЕЖЗИЙКЛМНОП'
    'РСТУФХЦЧШЩЪЫЬЭЮЯ'
    'абвгдежзийклмноп'
    '░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧'
    '╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀'
    'рстуфхцчшщъыьэюя'
    'ЁёЄєЇїЎў°∙·√№¤■ ';

/// Читает строку в 866-й кодовой странице — так русская Windows пишет
/// имена файлов в архив.
String decodeCp866(List<int> bytes) {
  final StringBuffer text = StringBuffer();
  for (final int byte in bytes) {
    text.writeCharCode(
      byte < 0x80 ? byte : _cp866High.codeUnitAt((byte & 0xFF) - 0x80),
    );
  }
  return text.toString();
}

/// CRC-32 от [bytes] — та же сумма, что стоит в оглавлении ZIP.
int crc32Of(List<int> bytes) {
  return _crcUpdate(0xFFFFFFFF, _bytes(bytes)) ^ 0xFFFFFFFF;
}

/// CRC-32 по частям: писателю архива (`zip_writer.dart`) сумма нужна
/// от потока, а не от готового списка байт.
class Crc32 {
  int _crc = 0xFFFFFFFF;

  /// Принимает очередной кусок.
  void add(List<int> bytes) {
    _crc = _crcUpdate(_crc, _bytes(bytes));
  }

  /// Сумма всего принятого.
  int get value => _crc ^ 0xFFFFFFFF;
}

int _crcUpdate(int crc, Uint8List bytes) {
  int value = crc;
  for (int i = 0; i < bytes.length; i++) {
    value = _crcTable[(value ^ bytes[i]) & 0xFF] ^ (value >> 8);
  }
  return value;
}

final Uint32List _crcTable = _makeCrcTable();

Uint32List _makeCrcTable() {
  final Uint32List table = Uint32List(256);
  for (int n = 0; n < 256; n++) {
    int value = n;
    for (int bit = 0; bit < 8; bit++) {
      value = value & 1 != 0 ? 0xEDB88320 ^ (value >> 1) : value >> 1;
    }
    table[n] = value;
  }
  return table;
}

Uint8List _bytes(List<int> data) {
  return data is Uint8List ? data : Uint8List.fromList(data);
}

/// Отказ для файла без оглавления: начинается как ZIP — значит,
/// оборван; иначе это чужой формат.
Future<ZipException> _noDirectory(BookHandle handle) async {
  if (handle.length < 4) {
    return const ZipException(ZipProblem.notZip);
  }
  final ByteData head = ByteData.sublistView(await _readAt(handle, 0, 4));
  return ZipException(
    head.getUint32(0, Endian.little) == _localSignature
        ? ZipProblem.truncated
        : ZipProblem.notZip,
  );
}

/// Читает ровно [size] байт с позиции [position].
Future<Uint8List> _readAt(BookHandle handle, int position, int size) async {
  final Uint8List buffer = Uint8List(size);
  final int got = await _readInto(handle, buffer, position, size);
  if (got < size) {
    throw const ZipException(ZipProblem.truncated);
  }
  return buffer;
}

/// Читает до [size] байт в начало [buffer]; меньше — только у конца
/// файла.
///
/// Чтение вправе вернуть меньше запрошенного, не дойдя до конца, —
/// дочитываем сами. Отказ чтения — [ZipProblem.unreadable]: так
/// отвечает документ Android, по которому нельзя перескакивать.
Future<int> _readInto(
  BookHandle handle,
  Uint8List buffer,
  int position,
  int size,
) async {
  int done = 0;
  while (done < size) {
    final Uint8List target = done == 0
        ? buffer
        : Uint8List.sublistView(buffer, done);
    final int got;
    try {
      got = await handle.read(target, position + done, size - done);
    } on FileSystemException {
      throw const ZipException(ZipProblem.unreadable);
    }
    if (got < 0) {
      throw const ZipException(ZipProblem.unreadable);
    }
    if (got == 0) {
      break;
    }
    done += got;
  }
  return done;
}
