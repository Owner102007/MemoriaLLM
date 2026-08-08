import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Сколько байт берётся с начала и с конца файла.
const int _probeSize = 64 * 1024;

/// Отпечаток файла: длина плюс sha256 от начала и конца.
///
/// Полный хеш книги на 300 МБ читателю не по карману: это секунды
/// ожидания и разряженная батарея при каждом импорте. Начало, конец и
/// длина различают книги надёжно — совпасть всем трём у разных файлов
/// практически невозможно, а подбирать коллизию здесь некому: отпечаток
/// не подпись, он только отвечает на вопрос «эта книга у нас уже есть?»
/// и опознаёт одну и ту же книгу на телефоне и на ПК (S11).
Future<String> fileFingerprint(String path) async {
  final File file = File(path);
  final int size = await file.length();
  final RandomAccessFile handle = await file.open();
  try {
    final Uint8List head = await handle.read(
      size < _probeSize ? size : _probeSize,
    );
    Uint8List tail = Uint8List(0);
    if (size > _probeSize) {
      final int from = size - _probeSize < _probeSize
          ? _probeSize
          : size - _probeSize;
      await handle.setPosition(from);
      tail = await handle.read(size - from);
    }
    final Digest digest = sha256.convert(<int>[...head, ...tail]);
    return '$size-$digest';
  } finally {
    await handle.close();
  }
}
