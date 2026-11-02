/// Паспорт файла на настоящих PDF через PDFium (ALG-MAP-18).
///
/// Корпус `test/fixtures` (собран `tool/make_fixtures.py`): набранная
/// книга, скан без слоя, скан 200 dpi с невидимым слоем распознавания,
/// битые файлы. Плюс 18 книг литературы СНО2026 — только на ПК владельца
/// (книги в публичный репозиторий не идут): в шаге 46 все они вышли
/// «электронным оригиналом».
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_passport.dart';
import 'package:memoria/domain/map/file_passport.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';
import 'package:memoria/infrastructure/pdf/pdfium_passport.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx, pdfrxInitialize;

import '../support/descriptors.dart';

/// Файл корпуса.
BookSource _fixture(String name) => FilePathSource('test/fixtures/$name');

/// Литература СНО2026 — рядом с репозиторием, в данных проекта.
const String _literature =
    '../_данные/Книги в архиве для тестирования (2 версия)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final Directory tmp = Directory(
    '${Directory.systemTemp.path}/memoria-passport-tests',
  );
  Future<void> initialize() async {
    await tmp.create(recursive: true);
    await pdfrxInitialize(tmpPath: tmp.path);
  }

  final PdfiumPassportReader reader = PdfiumPassportReader(
    storage: const LocalBookStorage(),
    initialize: initialize,
  );

  // Первым в файле: PDFium ещё никто не запускал. Так бывает в
  // приложении — инициализатор Flutter готовит только папки, а книгу до
  // паспорта не открывали (весь текст уже в базе). Без `init` в чтении
  // паспорта первый же проход уронил бы процесс (вторая пара глаз S58).
  test(
    'ALG-MAP-18: паспорт сам запускает PDFium — без открытой книги',
    () async {
      await tmp.create(recursive: true);
      final PdfiumPassportReader cold = PdfiumPassportReader(
        storage: const LocalBookStorage(),
        // Как pdfrxFlutterInitialize: папка кэша есть, путь к библиотеке
        // известен (в CI на Linux — из PDFIUM_PATH, в приложении она
        // лежит рядом с программой), но сам PDFium не запущен.
        initialize: () async {
          Pdfrx.cacheDirectoryPath ??= tmp.path;
          final String? module = Platform.environment['PDFIUM_PATH'];
          if (module != null && File(module).existsSync()) {
            Pdfrx.pdfiumModulePath ??= module;
          }
        },
      );
      final FilePassport? passport = await cold.read(
        _fixture('basic_text.pdf'),
      );
      expect(passport?.kind, BookKind.digital);
    },
  );

  test('ALG-MAP-18: набранная книга — электронный оригинал', () async {
    final FilePassport passport = (await reader.read(
      _fixture('book_120_pages.pdf'),
    ))!;
    expect(passport.pageKinds, hasLength(120));
    expect(passport.kind, BookKind.digital);
    expect(passport.dpiMedian, isNull);
    expect(passport.producer, 'Memoria LLM HB fixtures');
  });

  test(
    'ALG-MAP-18: скан без слоя — все страницы «скан без слоя», серое',
    () async {
      final FilePassport passport = (await reader.read(
        _fixture('scan_no_text.pdf'),
      ))!;
      expect(passport.pageKinds, <PageKind>[
        PageKind.scanNoLayer,
        PageKind.scanNoLayer,
      ]);
      expect(passport.kind, BookKind.scanNoLayer);
      expect(passport.color, ScanColor.gray);
    },
  );

  test(
    'ALG-MAP-18: скан с невидимым слоем — «скан со слоем», 200 dpi, серое',
    () async {
      final FilePassport passport = (await reader.read(
        _fixture('scan_with_layer.pdf'),
      ))!;
      expect(passport.pageKinds, <PageKind>[
        PageKind.scanWithLayer,
        PageKind.scanWithLayer,
      ]);
      expect(passport.kind, BookKind.scanWithLayer);
      expect(passport.dpiMedian, closeTo(200, 1));
      expect(passport.color, ScanColor.gray);
    },
  );

  test('ALG-MAP-18: закладки считаются на всех уровнях оглавления', () async {
    final FilePassport passport = (await reader.read(
      _fixture('outline_nested.pdf'),
    ))!;
    // Корпус: дерево из 7 узлов в три уровня (test/fixtures/README.md).
    expect(passport.bookmarks, 7);
  });

  test('ALG-MAP-18: битый файл и пароль — паспорта нет, не падение', () async {
    expect(await reader.read(_fixture('not_a_pdf.pdf')), isNull);
    expect(await reader.read(_fixture('truncated.pdf')), isNull);
    expect(await reader.read(_fixture('encrypted.pdf')), isNull);
  });

  test('ALG-MAP-18: файла нет — «прочитать позже», а не «битый»', () async {
    await expectLater(
      reader.read(_fixture('нет-такого.pdf')),
      throwsA(isA<PassportUnavailableException>()),
    );
  });

  test('ALG-MAP-18: 1200 страниц — проход укладывается в секунды', () async {
    final Stopwatch clock = Stopwatch()..start();
    final FilePassport passport = (await reader.read(
      _fixture('huge_1200_pages.pdf'),
    ))!;
    stdout.writeln(
      'ЗАМЕР ALG-MAP-18 | 1200 страниц | паспорт | '
      '${clock.elapsedMilliseconds} мс',
    );
    expect(passport.pageKinds, hasLength(1200));
    expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test(
    'ALG-MAP-18: по файловому дескриптору — как на Android',
    () async {
      final DescriptorFileStorage descriptors = DescriptorFileStorage();
      final PdfiumPassportReader byDescriptor = PdfiumPassportReader(
        storage: descriptors,
        initialize: initialize,
      );
      final FilePassport passport = (await byDescriptor.read(
        _fixture('scan_with_layer.pdf'),
      ))!;
      expect(passport.kind, BookKind.scanWithLayer);
      expect(descriptors.openCount, 0, reason: 'дескриптор закрыт');
    },
    // `/proc/self/fd` есть на Linux и Android (CI — Linux); на Windows
    // дескрипторов libc нет.
    skip: Platform.isWindows
        ? 'путь /proc/self/fd — только Linux/Android'
        : false,
  );

  test(
    'ALG-MAP-18: 18 книг литературы СНО2026 — электронные оригиналы',
    () async {
      final List<File> files = <File>[
        for (final String folder in <String>[
          'Аневризма - книги',
          'Число Е - книги',
        ])
          ...Directory('$_literature/$folder')
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.toLowerCase().endsWith('.pdf')),
      ]..sort((File a, File b) => a.path.compareTo(b.path));
      expect(files, hasLength(18));
      final Stopwatch clock = Stopwatch()..start();
      for (final File file in files) {
        final FilePassport passport = (await reader.read(
          FilePathSource(file.absolute.path),
        ))!;
        expect(passport.kind, BookKind.digital, reason: file.path);
      }
      stdout.writeln(
        'ЗАМЕР ALG-MAP-18 | 18 книг литературы | паспорт | '
        '${clock.elapsedMilliseconds} мс',
      );
    },
    skip: Directory(_literature).existsSync()
        ? false
        : 'нет литературы СНО2026 рядом с репозиторием (_данные) — '
              'тест идёт только на ПК владельца',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
