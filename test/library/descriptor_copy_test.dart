import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/infrastructure/files/descriptor_book_handle.dart';
import 'package:memoria/infrastructure/files/descriptor_copy.dart';
import 'package:memoria/infrastructure/files/libc.dart';

import '../support/descriptors.dart' as fd;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-descriptor');
  });
  tearDown(() async => temp.delete(recursive: true));

  File writeBook(String name, int size) {
    final File file = File('${temp.path}/$name');
    file.writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(size, (int i) => i % 251)),
    );
    return file;
  }

  group('чтение по дескриптору', () {
    test('перескоки по книге читают то, что просили', () async {
      final File book = writeBook('книга.bin', 300 * 1024);
      final int descriptor = fd.openDescriptor(book.path);
      final DescriptorBookHandle handle = DescriptorBookHandle(
        descriptor: descriptor,
        length: book.lengthSync(),
        onClose: () async => fd.closeDescriptor(descriptor),
      );
      addTearDown(handle.close);

      // Порядок нарочно не по возрастанию: PDF читается перескоками, и
      // именно этого не умеет поток.
      for (final int position in <int>[200 * 1024, 0, 299 * 1024, 1024]) {
        final Uint8List buffer = Uint8List(128);
        expect(handle.read(buffer, position, 128), 128);
        expect(buffer[0], position % 251);
        expect(buffer[127], (position + 127) % 251);
      }
    });

    test('позиция дескриптора не двигается', () async {
      // `pread` читает с позиции, не трогая её, — потому один дескриптор
      // и выдерживает нескольких читателей.
      final File book = writeBook('книга.bin', 4096);
      final int descriptor = fd.openDescriptor(book.path);
      final DescriptorBookHandle handle = DescriptorBookHandle(
        descriptor: descriptor,
        length: 4096,
        onClose: () async => fd.closeDescriptor(descriptor),
      );
      addTearDown(handle.close);

      final Uint8List first = Uint8List(16);
      final Uint8List again = Uint8List(16);
      handle.read(first, 1000, 16);
      handle.read(again, 1000, 16);
      expect(again, first);
    });

    test('за концом книги читается ноль, а не мусор', () async {
      final File book = writeBook('книга.bin', 100);
      final int descriptor = fd.openDescriptor(book.path);
      final DescriptorBookHandle handle = DescriptorBookHandle(
        descriptor: descriptor,
        length: 100,
        onClose: () async => fd.closeDescriptor(descriptor),
      );
      addTearDown(handle.close);

      final Uint8List buffer = Uint8List(64);
      expect(handle.read(buffer, 100, 64), 0);
      // Просили больше, чем осталось: отдаётся остаток, а не ошибка.
      expect(handle.read(buffer, 80, 64), 20);
    });

    test('закрытая книга не читается', () async {
      final File book = writeBook('книга.bin', 100);
      final int descriptor = fd.openDescriptor(book.path);
      final DescriptorBookHandle handle = DescriptorBookHandle(
        descriptor: descriptor,
        length: 100,
        onClose: () async => fd.closeDescriptor(descriptor),
      );
      await handle.close();
      expect(handle.read(Uint8List(10), 0, 10), -1);
    });
  });

  group('можно ли перескакивать', () {
    test('у файла — можно', () {
      final File book = writeBook('книга.bin', 100);
      final int descriptor = fd.openDescriptor(book.path);
      addTearDown(() => fd.closeDescriptor(descriptor));
      expect(descriptorIsSeekable(descriptor), isTrue);
    });

    test('у трубы — нельзя', () {
      final ({int read, int write}) pipe = fd.createPipe();
      addTearDown(() {
        fd.closeDescriptor(pipe.read);
        fd.closeDescriptor(pipe.write);
      });
      expect(descriptorIsSeekable(pipe.read), isFalse);
    });
  });

  group('потоковое копирование', () {
    test('книга заметно больше буфера переносится целиком', () async {
      // Четыре с лишним куска: именно на файлах длиннее буфера прежний
      // способ и падал, потому что растил буфер до размера книги.
      const int chunk = 64 * 1024;
      final File book = writeBook('большая.bin', chunk * 4 + 777);
      final int descriptor = fd.openDescriptor(book.path);
      addTearDown(() => fd.closeDescriptor(descriptor));

      final String destination = '${temp.path}/копия/книга.bin';
      final int copied = await copyDescriptorToFile(
        descriptor: descriptor,
        destination: destination,
        chunkSize: chunk,
      );

      expect(copied, book.lengthSync());
      expect(File(destination).readAsBytesSync(), book.readAsBytesSync());
    });

    test('поток из трубы тоже доезжает целиком', () async {
      final List<int> bytes = List<int>.generate(40000, (int i) => i % 251);
      final ({int read, int write}) pipe = fd.createPipe();
      fd.writeDescriptor(pipe.write, bytes);
      fd.closeDescriptor(pipe.write);
      addTearDown(() => fd.closeDescriptor(pipe.read));

      final String destination = '${temp.path}/поток.bin';
      final int copied = await copyDescriptorToFile(
        descriptor: pipe.read,
        destination: destination,
        chunkSize: 4096,
      );

      expect(copied, bytes.length);
      expect(File(destination).readAsBytesSync(), bytes);
    });

    test('пустой источник даёт пустой файл, а не ошибку', () async {
      final File book = writeBook('пустая.bin', 0);
      final int descriptor = fd.openDescriptor(book.path);
      addTearDown(() => fd.closeDescriptor(descriptor));

      final String destination = '${temp.path}/пусто.bin';
      expect(
        await copyDescriptorToFile(
          descriptor: descriptor,
          destination: destination,
        ),
        0,
      );
      expect(File(destination).existsSync(), isTrue);
    });
  });
}
