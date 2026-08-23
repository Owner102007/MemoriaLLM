import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/library/book_storage.dart';
import 'libc.dart';

/// Книга, читаемая прямо по файловому дескриптору.
///
/// Так открывают `content://` нативные просмотрщики на PDFium:
/// `openFileDescriptor` даёт обычный дескриптор, а дальше файл читается
/// кусками системным вызовом `pread`. Ни копии, ни перехода через
/// платформенный канал на каждое чтение страницы — скорость как у
/// локального файла, а лишнего места ноль.
class DescriptorBookHandle implements BookHandle {
  /// Создаёт чтение по дескриптору.
  ///
  /// [onClose] закрывает сам дескриптор: его владелец — тот, кто его
  /// открыл, и закрывать чужой дескриптор здесь было бы самоуправством.
  DescriptorBookHandle({
    required int descriptor,
    required this.length,
    Future<void> Function()? onClose,
  }) : _fd = descriptor,
       _onClose = onClose;

  final int _fd;
  final Future<void> Function()? _onClose;

  @override
  final int length;

  /// Пути у документа Android нет вовсе — движок обязан читать кусками.
  @override
  String? get path => null;

  Pointer<Uint8> _scratch = nullptr;
  int _scratchSize = 0;
  bool _closed = false;

  @override
  int read(Uint8List buffer, int position, int size) {
    if (_closed) {
      return -1;
    }
    if (size <= 0 || position >= length) {
      return 0;
    }
    final int want = position + size > length ? length - position : size;
    final Pointer<Uint8> target = _reserve(want);
    // `pread` вправе вернуть меньше запрошенного, не дойдя до конца
    // файла: это не ошибка, а обычное поведение. Дочитываем сами —
    // движок, получивший короткое чтение, объявит книгу повреждённой.
    int done = 0;
    while (done < want) {
      final int got = positionalRead(
        _fd,
        target + done,
        want - done,
        position + done,
      );
      if (got < 0) {
        return -1;
      }
      if (got == 0) {
        break;
      }
      done += got;
    }
    buffer.setRange(0, done, target.asTypedList(done));
    return done;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_scratch != nullptr) {
      malloc.free(_scratch);
      _scratch = nullptr;
      _scratchSize = 0;
    }
    await _onClose?.call();
  }

  /// Свой буфер под системный вызов.
  ///
  /// Движок отдаёт [Uint8List], смотрящий в его собственную память, а
  /// адреса этой памяти из Dart не достать. Поэтому читаем в свой буфер
  /// и копируем: копия куска в несколько килобайт стоит несравнимо
  /// меньше, чем копия книги, ради избавления от которой всё и затеяно.
  Pointer<Uint8> _reserve(int size) {
    if (_scratchSize >= size) {
      return _scratch;
    }
    if (_scratch != nullptr) {
      malloc.free(_scratch);
    }
    _scratch = malloc<Uint8>(size);
    _scratchSize = size;
    return _scratch;
  }
}
