import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/infrastructure/files/android_book_storage.dart';
import 'package:memoria/infrastructure/files/document_gateway.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';

import '../support/descriptors.dart' as fd;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('memoria-storage');
  });
  tearDown(() async => temp.delete(recursive: true));

  File writeBook(String name, int size) {
    final File file = File('${temp.path}/$name');
    // Байты предсказуемые, чтобы чтение кусками проверялось по
    // содержимому, а не по одной длине.
    file.writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(size, (int i) => i % 251)),
    );
    return file;
  }

  group('обычная файловая система', () {
    const LocalBookStorage storage = LocalBookStorage();

    test('файл не копируется и путь остаётся его собственным', () async {
      final File book = writeBook('kniga.pdf', 1000);
      final BookSource source = await storage.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );
      expect(source, FilePathSource(book.path));
      expect((source as FilePathSource).owned, isFalse);
    });

    test('читается кусками с любой позиции', () async {
      final File book = writeBook('kniga.pdf', 5000);
      final BookHandle handle = await storage.open(FilePathSource(book.path));
      addTearDown(handle.close);

      expect(handle.length, 5000);
      expect(handle.path, book.path);

      final Uint8List buffer = Uint8List(100);
      expect(await handle.read(buffer, 4000, 100), 100);
      expect(buffer[0], 4000 % 251);
      expect(buffer[99], 4099 % 251);
    });

    test('файла нет — книга недоступна, а не падение', () async {
      await expectLater(
        storage.open(const FilePathSource('/нет/такого/файла.pdf')),
        throwsA(isA<BookUnavailableException>()),
      );
      expect(
        await storage.available(const FilePathSource('/нет/такого.pdf')),
        isFalse,
      );
    });

    test('чужой файл при снятии с полки не трогается', () async {
      final File book = writeBook('чужая.pdf', 100);
      await storage.release(FilePathSource(book.path));
      expect(book.existsSync(), isTrue);
    });

    test('своя копия при снятии с полки удаляется', () async {
      final File copy = writeBook('копия.pdf', 100);
      await storage.release(FilePathSource(copy.path, owned: true));
      expect(copy.existsSync(), isFalse);
    });
  });

  group('SNO-F-LIT-02: копия книги в папке приложения', () {
    late Directory books;
    late LocalBookStorage copying;

    setUp(() {
      books = Directory('${temp.path}/books');
      copying = LocalBookStorage(copyInto: () async => books);
    });

    List<String> names() {
      return <String>[
        for (final FileSystemEntity entry in books.listSync())
          entry.uri.pathSegments.last,
      ];
    }

    test('SNO-F-LIT-02: книга копируется, источник — своя копия', () async {
      final File book = writeBook('kniga.pdf', 3000);
      final BookSource source = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );

      final FilePathSource copy = source as FilePathSource;
      expect(copy.owned, isTrue, reason: 'копию делали мы — нам и убирать');
      expect(copy.encode(), startsWith('copy:'));
      expect(copy.path, startsWith(books.path));
      expect(copy.path, isNot(book.path));
      expect(File(copy.path).readAsBytesSync(), book.readAsBytesSync());
      // Чужой файл цел, а недописанных копий не осталось.
      expect(book.existsSync(), isTrue);
      expect(names().where((String name) => name.endsWith('.part')), isEmpty);
    });

    test('SNO-F-LIT-02: копия читается и после пропажи исходника', () async {
      final File book = writeBook('kniga.pdf', 5000);
      final BookSource source = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );
      book.deleteSync();

      expect(await copying.available(source), isTrue);
      final BookHandle handle = await copying.open(source);
      addTearDown(handle.close);
      expect(handle.length, 5000);
      final Uint8List buffer = Uint8List(10);
      expect(await handle.read(buffer, 4000, 10), 10);
      expect(buffer[0], 4000 % 251);
    });

    test('SNO-F-LIT-02: тёзки из разных папок лежат порознь', () async {
      final Directory first = Directory('${temp.path}/a')..createSync();
      final Directory second = Directory('${temp.path}/b')..createSync();
      final File one = File('${first.path}/kniga.pdf')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final File two = File('${second.path}/kniga.pdf')
        ..writeAsBytesSync(<int>[4, 5, 6, 7]);

      final BookSource a = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: one.path),
      );
      final BookSource b = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: two.path),
      );

      expect(a, isNot(b));
      final FilePathSource copyA = a as FilePathSource;
      final FilePathSource copyB = b as FilePathSource;
      expect(File(copyA.path).readAsBytesSync(), <int>[1, 2, 3]);
      expect(File(copyB.path).readAsBytesSync(), <int>[4, 5, 6, 7]);
    });

    test('SNO-F-LIT-02: тот же файл повторно — та же копия', () async {
      final File book = writeBook('kniga.pdf', 1000);
      final PickedFile picked = PickedFile(name: 'kniga.pdf', path: book.path);

      final BookSource first = await copying.adopt(picked);
      final BookSource second = await copying.adopt(picked);

      expect(second, first);
      expect(names(), hasLength(1));
    });

    test('SNO-F-LIT-02: та же книга из другой папки — одна копия', () async {
      final Directory other = Directory('${temp.path}/other')..createSync();
      final File book = writeBook('kniga.pdf', 2000);
      final File twin = File('${other.path}/drugoe-imya.pdf')
        ..writeAsBytesSync(book.readAsBytesSync());

      final BookSource first = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );
      final BookSource second = await copying.adopt(
        PickedFile(name: 'drugoe-imya.pdf', path: twin.path),
      );

      // Копия названа по содержимому: вторая не появляется, и первая
      // не остаётся сиротой.
      expect(second, first);
      expect(names(), hasLength(1));
    });

    test('SNO-F-LIT-02: файл пересохранили — прежняя копия цела', () async {
      final File book = writeBook('kniga.pdf', 2000);
      final PickedFile picked = PickedFile(name: 'kniga.pdf', path: book.path);
      final BookSource first = await copying.adopt(picked);
      final FilePathSource before = first as FilePathSource;
      final List<int> was = File(before.path).readAsBytesSync();

      // Под тем же именем теперь лежит другая книга.
      book.writeAsBytesSync(<int>[9, 8, 7, 6, 5]);
      final BookSource second = await copying.adopt(picked);
      final FilePathSource after = second as FilePathSource;

      expect(after.path, isNot(before.path));
      expect(File(after.path).readAsBytesSync(), <int>[9, 8, 7, 6, 5]);
      // Книга, уже стоящая на полке, свой файл не потеряла.
      expect(File(before.path).readAsBytesSync(), was);
    });

    test('SNO-F-LIT-02: выбрана сама копия — второй не делается', () async {
      final File book = writeBook('kniga.pdf', 1000);
      final BookSource source = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );
      final FilePathSource copy = source as FilePathSource;

      final BookSource again = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: copy.path),
      );

      expect(again, copy);
      expect(names(), hasLength(1));
      expect(File(copy.path).lengthSync(), 1000);
    });

    test('SNO-F-LIT-02: недописанное с прошлого раза выметается', () async {
      // Приложение убили посреди переноса: в папке остался `.part`.
      books.createSync(recursive: true);
      final File stale = File('${books.path}/incoming-0123456789abcdef.part')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final File book = writeBook('kniga.pdf', 1000);
      final BookSource kept = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );

      await copying.adopt(
        PickedFile(name: 'drugaya.pdf', path: writeBook('d.pdf', 500).path),
      );

      expect(stale.existsSync(), isFalse);
      // Готовые копии уборка не трогает.
      expect(File((kept as FilePathSource).path).lengthSync(), 1000);
      expect(names(), hasLength(2));
    });

    test('SNO-F-LIT-02: снятая с полки копия удаляется', () async {
      final File book = writeBook('kniga.pdf', 1000);
      final BookSource source = await copying.adopt(
        PickedFile(name: 'kniga.pdf', path: book.path),
      );

      await copying.release(source);

      expect(File((source as FilePathSource).path).existsSync(), isFalse);
      expect(book.existsSync(), isTrue);
    });

    test('SNO-F-LIT-02: исходника нет — ошибка, и копии не остаётся', () async {
      await expectLater(
        copying.adopt(
          PickedFile(name: 'net.pdf', path: '${temp.path}/net.pdf'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(names(), isEmpty);
    });
  });

  group('документы Android', () {
    test('ссылка закрепляется, и книга читается без копии', () async {
      final File book = writeBook('учебник.pdf', 300 * 1024);
      final FakeDocumentGateway documents = FakeDocumentGateway(
        <String, String>{'content://doc/1': book.path},
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
      );

      final BookSource source = await storage.adopt(
        const PickedFile(name: 'учебник.pdf', uri: 'content://doc/1'),
      );

      expect(source, const DocumentUriSource('content://doc/1'));
      expect(documents.persisted, contains('content://doc/1'));
      // Копии не появилось: место книга занимает ровно одно.
      expect(Directory('${temp.path}/books').existsSync(), isFalse);
      // И дескрипторы за собой хранилище закрыло.
      expect(documents.openDescriptors, isEmpty);

      final BookHandle handle = await storage.open(source);
      addTearDown(handle.close);
      expect(handle.path, isNull, reason: 'у документа Android пути нет');
      expect(handle.length, 300 * 1024);

      final Uint8List buffer = Uint8List(64);
      expect(await handle.read(buffer, 200 * 1024, 64), 64);
      expect(buffer[0], (200 * 1024) % 251);
    });

    test('дескриптор закрывается вместе с книгой', () async {
      final File book = writeBook('книга.pdf', 4096);
      final FakeDocumentGateway documents = FakeDocumentGateway(
        <String, String>{'content://doc/2': book.path},
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
      );
      final BookHandle handle = await storage.open(
        const DocumentUriSource('content://doc/2'),
      );
      expect(documents.openDescriptors, hasLength(1));
      await handle.close();
      expect(documents.openDescriptors, isEmpty);
    });

    test('разрешение отозвано — книга недоступна, а не падение', () async {
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: FakeDocumentGateway(const <String, String>{}),
        booksDirectory: () async => Directory('${temp.path}/books'),
      );
      const BookSource source = DocumentUriSource('content://doc/пропал');
      expect(await storage.available(source), isFalse);
      await expectLater(
        storage.open(source),
        throwsA(isA<BookUnavailableException>()),
      );
    });

    test('провайдер не дал закрепить ссылку — книга переносится', () async {
      final File book = writeBook('облачная.pdf', 300 * 1024);
      final FakeDocumentGateway documents = FakeDocumentGateway(
        <String, String>{'content://cloud/1': book.path},
        allowPersist: false,
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
      );

      final BookSource source = await storage.adopt(
        const PickedFile(name: 'облачная.pdf', uri: 'content://cloud/1'),
      );

      // Ссылка не переживёт перезапуск — значит, книга обязана переехать
      // к нам, иначе завтра она «пропадёт».
      expect(source, isA<FilePathSource>());
      final FilePathSource copy = source as FilePathSource;
      expect(copy.owned, isTrue, reason: 'копию делали мы — нам и убирать');
      expect(File(copy.path).lengthSync(), book.lengthSync());
      expect(File(copy.path).readAsBytesSync(), book.readAsBytesSync());
      expect(documents.openDescriptors, isEmpty);
    });

    test('по трубе перескочить нельзя — книга переносится', () async {
      final List<int> bytes = List<int>.generate(20000, (int i) => i % 251);
      final ({int read, int write}) pipe = fd.createPipe();
      fd.writeDescriptor(pipe.write, bytes);
      fd.closeDescriptor(pipe.write);

      final FakeDocumentGateway documents = FakeDocumentGateway(
        const <String, String>{},
        descriptors: <String, int>{'content://stream/1': pipe.read},
        sizes: <String, int>{'content://stream/1': bytes.length},
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
      );

      final BookSource source = await storage.adopt(
        const PickedFile(name: 'поток.pdf', uri: 'content://stream/1'),
      );

      final FilePathSource copy = source as FilePathSource;
      expect(copy.owned, isTrue);
      expect(File(copy.path).readAsBytesSync(), bytes);
    });

    test('SNO-F-LIT-02: в ветви книга переносится всегда', () async {
      final File book = writeBook('учебник.pdf', 300 * 1024);
      final FakeDocumentGateway documents = FakeDocumentGateway(
        <String, String>{'content://doc/9': book.path},
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
        alwaysCopy: true,
      );

      final BookSource source = await storage.adopt(
        const PickedFile(name: 'учебник.pdf', uri: 'content://doc/9'),
      );

      // Ссылка годилась для чтения на месте — и всё равно книга у нас:
      // в ветви все книги живут внутри приложения (SNO-DIV-03).
      final FilePathSource copy = source as FilePathSource;
      expect(copy.owned, isTrue);
      expect(File(copy.path).readAsBytesSync(), book.readAsBytesSync());
      // И ни одного закреплённого разрешения на чужой файл.
      expect(documents.persisted, isEmpty);
      expect(documents.openDescriptors, isEmpty);
    });

    test('SNO-F-LIT-02: оборванный перенос файла не оставляет', () async {
      // Дескриптор, с которого нельзя читать: конец трубы для записи.
      final ({int read, int write}) pipe = fd.createPipe();
      addTearDown(() => fd.closeDescriptor(pipe.read));
      final FakeDocumentGateway documents = FakeDocumentGateway(
        const <String, String>{},
        descriptors: <String, int>{'content://bad/1': pipe.write},
        sizes: <String, int>{'content://bad/1': 1000},
      );
      final Directory books = Directory('${temp.path}/books');
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => books,
        alwaysCopy: true,
      );

      await expectLater(
        storage.adopt(
          const PickedFile(name: 'плохой.pdf', uri: 'content://bad/1'),
        ),
        throwsA(anything),
      );

      // Ни обрезанной книги, ни недописанного файла; дескриптор закрыт.
      expect(books.existsSync() ? books.listSync() : <Object>[], isEmpty);
      expect(documents.openDescriptors, isEmpty);
    });

    test('SNO-F-LIT-02: в ветви файл с путём тоже копируется', () async {
      final File book = writeBook('свой.pdf', 2000);
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: FakeDocumentGateway(const <String, String>{}),
        booksDirectory: () async => Directory('${temp.path}/books'),
        alwaysCopy: true,
      );

      final BookSource source = await storage.adopt(
        PickedFile(name: 'свой.pdf', path: book.path),
      );

      final FilePathSource copy = source as FilePathSource;
      expect(copy.owned, isTrue);
      expect(copy.path, startsWith('${temp.path}/books'));
      expect(File(copy.path).readAsBytesSync(), book.readAsBytesSync());
    });

    test('снятая с полки книга отпускает ссылку', () async {
      final FakeDocumentGateway documents = FakeDocumentGateway(
        const <String, String>{},
      );
      final AndroidBookStorage storage = AndroidBookStorage(
        documents: documents,
        booksDirectory: () async => Directory('${temp.path}/books'),
      );
      await storage.release(const DocumentUriSource('content://doc/3'));
      // Закреплённых ссылок Android держит ограниченное число на
      // приложение: не отпускать их — значит однажды упереться в потолок.
      expect(documents.released, <String>['content://doc/3']);
    });
  });
}

/// Storage Access Framework, собранный из настоящих файлов и труб.
///
/// Дескрипторы отдаёт та же libc, что и Android, поэтому проверяется не
/// заглушка, а весь путь чтения: дескриптор, `pread`, определение
/// перескоков и потоковый перенос.
class FakeDocumentGateway implements DocumentGateway {
  /// Создаёт порт.
  ///
  /// [files] — ссылка на путь к настоящему файлу; [descriptors] — готовые
  /// дескрипторы (например, конец трубы); [sizes] — длины для них.
  FakeDocumentGateway(
    this.files, {
    this.allowPersist = true,
    this.descriptors = const <String, int>{},
    this.sizes = const <String, int>{},
  });

  /// Ссылка → путь к файлу за ней.
  final Map<String, String> files;

  /// Ссылка → готовый дескриптор.
  final Map<String, int> descriptors;

  /// Ссылка → длина, если файла за ней нет.
  final Map<String, int> sizes;

  /// Даёт ли провайдер закрепить ссылку.
  final bool allowPersist;

  /// Закреплённые ссылки.
  final Set<String> persisted = <String>{};

  /// Отпущенные ссылки.
  final List<String> released = <String>[];

  /// Открытые сейчас дескрипторы.
  final Set<int> openDescriptors = <int>{};

  @override
  Future<int?> sizeOf(String uri) async {
    final String? path = files[uri];
    if (path != null) {
      return File(path).lengthSync();
    }
    return sizes[uri];
  }

  @override
  Future<int> openDescriptor(String uri) async {
    final int? ready = descriptors[uri];
    if (ready != null) {
      openDescriptors.add(ready);
      return ready;
    }
    final String? path = files[uri];
    if (path == null) {
      throw StateError('нет документа $uri');
    }
    final int descriptor = fd.openDescriptor(path);
    openDescriptors.add(descriptor);
    return descriptor;
  }

  @override
  Future<void> closeDescriptor(int descriptor) async {
    if (openDescriptors.remove(descriptor)) {
      fd.closeDescriptor(descriptor);
    }
  }

  @override
  Future<bool> persist(String uri) async {
    if (allowPersist) {
      persisted.add(uri);
    }
    return allowPersist;
  }

  @override
  Future<void> releasePersisted(String uri) async {
    persisted.remove(uri);
    released.add(uri);
  }
}
