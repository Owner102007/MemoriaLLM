import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/infrastructure/files/descriptor_book_handle.dart';

/// Открывает файл и отдаёт номер дескриптора.
///
/// На Android дескриптор приходит от `openFileDescriptor`, а здесь — от
/// той же самой libc. Для чтения разницы нет никакой: и там, и там это
/// обычный дескриптор, который читается `pread`'ом. Благодаря этому весь
/// путь «дескриптор → PDFium» проверяется в CI, без телефона.
int openDescriptor(String path) {
  const int readOnly = 0;
  final Pointer<Utf8> name = path.toNativeUtf8();
  try {
    final int descriptor = _open(name, readOnly);
    if (descriptor < 0) {
      throw FileSystemException('не открылся', path);
    }
    return descriptor;
  } finally {
    malloc.free(name);
  }
}

/// Закрывает дескриптор.
void closeDescriptor(int descriptor) => _close(descriptor);

/// Труба: пара дескрипторов, по которой нельзя перескакивать.
///
/// Ровно так выглядит документ, отданный облачным провайдером: байты
/// идут потоком, вернуться назад нельзя. PDF по такому не читается, и
/// именно этот случай хранилище обязано опознать и скопировать книгу.
({int read, int write}) createPipe() {
  final Pointer<Int32> pair = malloc<Int32>(2);
  try {
    if (_pipe(pair) != 0) {
      throw StateError('труба не создалась');
    }
    return (read: pair[0], write: pair[1]);
  } finally {
    malloc.free(pair);
  }
}

/// Пишет байты в дескриптор.
void writeDescriptor(int descriptor, List<int> bytes) {
  final Pointer<Uint8> buffer = malloc<Uint8>(bytes.length);
  try {
    int done = 0;
    while (done < bytes.length) {
      final int left = bytes.length - done;
      buffer.asTypedList(left).setAll(0, bytes.sublist(done));
      final int got = _write(descriptor, buffer, left);
      if (got <= 0) {
        throw StateError('запись в дескриптор не удалась');
      }
      done += got;
    }
  } finally {
    malloc.free(buffer);
  }
}

final int Function(Pointer<Int32> pair) _pipe = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Pointer<Int32>), int Function(Pointer<Int32>)>(
      'pipe',
    );

final int Function(int fd, Pointer<Uint8> buffer, int count) _write =
    DynamicLibrary.process().lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');

final int Function(Pointer<Utf8> path, int flags) _open =
    DynamicLibrary.process().lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)
    >('open');

final int Function(int fd) _close = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

/// Хранилище, которое отдаёт файл **только** через дескриптор.
///
/// Пути наружу нет — точно как у документа Android, — поэтому движок
/// обязан читать книгу кусками через тот же колбэк, каким он будет
/// читать её на телефоне.
class DescriptorFileStorage implements BookStorage {
  /// Создаёт хранилище.
  DescriptorFileStorage();

  /// Сколько дескрипторов сейчас открыто. Ноль после закрытия книги —
  /// это и есть проверка, что дескрипторы не текут.
  int openCount = 0;

  @override
  Future<BookSource> adopt(PickedFile file) async =>
      FilePathSource(file.path!);

  @override
  Future<BookHandle> open(BookSource source) async {
    final String path = (source as FilePathSource).path;
    final File file = File(path);
    if (!file.existsSync()) {
      throw BookUnavailableException(source);
    }
    final int descriptor = openDescriptor(path);
    openCount++;
    return DescriptorBookHandle(
      descriptor: descriptor,
      length: file.lengthSync(),
      onClose: () async {
        closeDescriptor(descriptor);
        openCount--;
      },
    );
  }

  @override
  Future<bool> available(BookSource source) async =>
      source is FilePathSource && File(source.path).existsSync();

  @override
  Future<void> release(BookSource source) async {}
}
