import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';
import 'package:path/path.dart' as p;

/// Обход устройства на дереве, собранном прямо в тесте.
///
/// Телефона у сессии нет, но правила отбора — это чистая работа с
/// файловой системой, и проверить их можно на настоящих папках во
/// временном каталоге. Ровно те случаи, из-за которых полка превращается
/// в помойку: кэш мессенджера, служебные ветки Android, скрытые папки,
/// картинка с расширением `.pdf`.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('memoria-scan');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> writePdf(String relative, {String body = 'книга'}) async {
    final File file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    final List<int> bytes = <int>[...kPdfSignature, ...'1.7\n$body'.codeUnits];
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file;
  }

  Future<File> writeRaw(String relative, List<int> bytes) async {
    final File file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file;
  }

  Future<List<String>> scan() async {
    final List<String> found = <String>[];
    await scanForPdfs(
      roots: <String>[root.path],
      onFile: (ScannedFile file) =>
          found.add(p.relative(file.path, from: root.path)),
    );
    found.sort();
    return found;
  }

  group('правила отбора', () {
    test('служебные ветки Android не обходятся', () {
      expect(
        shouldSkipDirectory(
          path: '/storage/emulated/0/Android/data',
          name: 'data',
        ),
        isTrue,
      );
      expect(
        shouldSkipDirectory(
          path: '/storage/emulated/0/Android/obb',
          name: 'obb',
        ),
        isTrue,
      );
      // А папка с похожим именем — обходится: правило смотрит на путь
      // целиком, а не на подстроку.
      expect(
        shouldSkipDirectory(path: '/storage/emulated/0/mydata', name: 'mydata'),
        isFalse,
      );
    });

    test('скрытые папки пропускаются', () {
      expect(shouldSkipDirectory(path: '/books/.git', name: '.git'), isTrue);
      expect(shouldSkipDirectory(path: '/books/Учёба', name: 'Учёба'), isFalse);
    });

    test('кэши пропускаются по имени', () {
      expect(shouldSkipDirectory(path: '/a/Cache', name: 'Cache'), isTrue);
      expect(
        shouldSkipDirectory(path: '/a/.thumbnails', name: '.thumbnails'),
        isTrue,
      );
    });

    test('сигнатура ищется в начале файла, но не строго с нуля', () {
      expect(hasPdfSignature(kPdfSignature), isTrue);
      expect(hasPdfSignature(<int>[0, 0, ...kPdfSignature]), isTrue);
      expect(hasPdfSignature(<int>[0x89, 0x50, 0x4e, 0x47]), isFalse);
      expect(hasPdfSignature(<int>[]), isFalse);
    });
  });

  group('обход дерева', () {
    test('находит книги и не находит чужого', () async {
      await writePdf('Книги/Онегин.pdf');
      await writePdf('Downloads/учебник.PDF');
      await writePdf('Android/data/com.chat/files/чек.pdf');
      await writePdf('Telegram/Telegram Documents/cache/присланное.pdf');
      await writePdf('.thumbnails/эскиз.pdf');
      await writePdf('Книги/.скрытая.pdf');
      await writeRaw('Книги/картинка.pdf', <int>[0x89, 0x50, 0x4e, 0x47, 0]);
      await writeRaw('Книги/заметки.txt', 'просто текст'.codeUnits);

      expect(await scan(), <String>[
        p.join('Downloads', 'учебник.PDF'),
        p.join('Книги', 'Онегин.pdf'),
      ]);
    });

    test('пустой файл не считается книгой', () async {
      await writeRaw('Книги/пусто.pdf', <int>[]);
      expect(await scan(), isEmpty);
    });

    test('размер и время берутся с диска', () async {
      final File file = await writePdf('Книги/Онегин.pdf', body: 'подлиннее');
      final List<ScannedFile> found = <ScannedFile>[];
      await scanForPdfs(roots: <String>[root.path], onFile: found.add);
      expect(found.single.size, await file.length());
      expect(found.single.name, 'Онегин.pdf');
      expect(found.single.folder, 'Книги');
    });

    test('несуществующий корень не роняет обход', () async {
      await writePdf('Книги/Онегин.pdf');
      final List<ScannedFile> found = <ScannedFile>[];
      await scanForPdfs(
        roots: <String>[p.join(root.path, 'нет-такой'), root.path],
        onFile: found.add,
      );
      expect(found.length, 1);
    });

    test('обход останавливается по требованию', () async {
      for (int i = 0; i < 5; i++) {
        await writePdf('Книги/книга-$i.pdf');
      }
      bool stop = false;
      final List<ScannedFile> found = <ScannedFile>[];
      await scanForPdfs(
        roots: <String>[root.path],
        onFile: found.add,
        isCancelled: () {
          final bool now = stop;
          stop = true;
          return now;
        },
      );
      // Первая папка обошлась, вторая — уже нет. Точное число здесь не
      // важно: важно, что обход слушается и не идёт до конца.
      expect(found.length, lessThan(5));
    });
  });
}
