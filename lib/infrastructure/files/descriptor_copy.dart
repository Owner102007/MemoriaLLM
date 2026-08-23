import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'libc.dart';

/// Сколько байт переносится за раз.
///
/// Мегабайт — это компромисс между числом системных вызовов и памятью,
/// которую копирование занимает. Важно другое: величина эта постоянная,
/// и книга любого размера переносится одним и тем же буфером. Именно
/// этим потоковое копирование отличается от того, которое роняло
/// приложение: оно растило буфер до размера книги.
const int copyChunkSize = 1024 * 1024;

/// Потоково переносит книгу с дескриптора в файл.
///
/// Возвращает, сколько байт перенесено.
///
/// Работа идёт в отдельном изоляте: системные вызовы чтения и записи
/// блокирующие, и на изоляте интерфейса книга в сотню мегабайт
/// подвесила бы приложение на несколько секунд. Дескриптор при этом
/// общий на весь процесс, поэтому в изолят достаточно передать его
/// номер.
Future<int> copyDescriptorToFile({
  required int descriptor,
  required String destination,
  int chunkSize = copyChunkSize,
}) {
  return Isolate.run<int>(
    () => _copyDescriptor(descriptor, destination, chunkSize),
  );
}

int _copyDescriptor(int descriptor, String destination, int chunkSize) {
  final Pointer<Uint8> buffer = malloc<Uint8>(chunkSize);
  final File file = File(destination);
  file.parent.createSync(recursive: true);
  final RandomAccessFile sink = file.openSync(mode: FileMode.writeOnly);
  int total = 0;
  try {
    while (true) {
      final int got = sequentialRead(descriptor, buffer, chunkSize);
      if (got < 0) {
        throw const FileSystemException('чтение с дескриптора не удалось');
      }
      if (got == 0) {
        break;
      }
      sink.writeFromSync(buffer.asTypedList(got));
      total += got;
    }
    return total;
  } finally {
    sink.closeSync();
    malloc.free(buffer);
  }
}
