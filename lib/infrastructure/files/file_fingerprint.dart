import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import 'file_book_handle.dart';

/// Сколько байт берётся с начала и с конца книги.
const int _probeSize = 64 * 1024;

/// Отпечаток книги: длина плюс sha256 от начала и конца.
///
/// Полный хеш книги на 300 МБ читателю не по карману: это секунды
/// ожидания и разряженная батарея при каждом импорте. Начало, конец и
/// длина различают книги надёжно — совпасть всем трём у разных файлов
/// практически невозможно, а подбирать коллизию здесь некому: отпечаток
/// не подпись, он только отвечает на вопрос «эта книга у нас уже есть?»
/// и опознаёт одну и ту же книгу на телефоне и на ПК (S11).
///
/// Считается через [BookHandle], а не по пути: у документа Android пути
/// нет вовсе, а отпечаток нужен ему ровно так же — именно он связывает
/// книгу с её цитатами и местом чтения, когда файл выбирают заново.
Future<String> bookFingerprint(BookHandle book) async {
  final int size = book.length;
  final int headSize = size < _probeSize ? size : _probeSize;
  final Uint8List head = Uint8List(headSize);
  if (headSize > 0) {
    await book.read(head, 0, headSize);
  }

  Uint8List tail = Uint8List(0);
  if (size > _probeSize) {
    final int from = size - _probeSize < _probeSize
        ? _probeSize
        : size - _probeSize;
    tail = Uint8List(size - from);
    await book.read(tail, from, tail.length);
  }

  final Digest digest = sha256.convert(<int>[...head, ...tail]);
  return '$size-$digest';
}

/// Отпечаток файла по пути. Удобная обёртка для того, что лежит на диске.
Future<String> fileFingerprint(String path) async {
  final BookHandle book = await FileBookHandle.open(FilePathSource(path));
  try {
    return await bookFingerprint(book);
  } finally {
    await book.close();
  }
}
