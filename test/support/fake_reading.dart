import 'dart:typed_data';

import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';

/// Документ-заглушка: страницы заданы списком строк.
///
/// Позволяет проверять сценарии чтения — восстановление позиции, поиск,
/// оглавление — без PDFium и без файлов на диске. Тесты выходят быстрыми
/// и не зависят от того, что именно умеет движок.
class FakeReaderDocument implements ReaderDocument {
  /// Создаёт документ из текстов страниц.
  FakeReaderDocument({
    required this.pages,
    this.outlineNodes = const <OutlineEntry>[],
    this.sourceName = 'fake.pdf',
    this.pageWidth = 595,
    this.pageHeight = 842,
    this.boxes = const <int, List<TextBox>>{},
  });

  /// Документ из [count] пустых страниц.
  factory FakeReaderDocument.blank(int count) {
    return FakeReaderDocument(pages: List<String>.filled(count, ''));
  }

  /// Тексты страниц.
  final List<String> pages;

  /// Оглавление.
  final List<OutlineEntry> outlineNodes;

  /// Прямоугольники символов по страницам. Пустая страница — «нет текста».
  final Map<int, List<TextBox>> boxes;

  @override
  final String sourceName;

  /// Ширина каждой страницы.
  final double pageWidth;

  /// Высота каждой страницы.
  final double pageHeight;

  /// Сколько раз читали текст каждой страницы — по этому счётчику видно,
  /// не перечитывает ли поиск одно и то же.
  final Map<int, int> textReads = <int, int>{};

  /// Сколько раз спрашивали прямоугольники символов: по нему видно, что
  /// рамка страницы считается один раз, а не в каждом кадре.
  final Map<int, int> boxReads = <int, int>{};

  /// Сколько раз рисовали страницу.
  final Map<int, int> renders = <int, int>{};

  /// Закрыт ли документ.
  bool closed = false;

  /// Бросать ли ошибку при чтении оглавления.
  bool failOutline = false;

  /// У подставного документа движка нет — и это отдельно проверяется:
  /// экран чтения обязан пережить документ, который нечем рисовать.
  @override
  Object? get engineDocument => null;

  @override
  int get pageCount => pages.length;

  @override
  PageGeometry geometry(int pageNumber) =>
      PageGeometry(width: pageWidth, height: pageHeight);

  @override
  Future<String> pageText(int pageNumber) async {
    textReads[pageNumber] = (textReads[pageNumber] ?? 0) + 1;
    return pages[pageNumber - 1];
  }

  @override
  Future<List<TextBox>> pageTextBoxes(int pageNumber) async {
    boxReads[pageNumber] = (boxReads[pageNumber] ?? 0) + 1;
    return boxes[pageNumber] ?? const <TextBox>[];
  }

  @override
  Future<List<OutlineEntry>> outline() async {
    if (failOutline) {
      throw StateError('оглавление испорчено');
    }
    return outlineNodes;
  }

  @override
  Future<PageRaster?> renderPage(
    int pageNumber, {
    required int width,
    required int height,
  }) async {
    renders[pageNumber] = (renders[pageNumber] ?? 0) + 1;
    return PageRaster(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 4),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Открыватель-заглушка: отдаёт заранее подготовленный документ.
class FakeDocumentOpener implements DocumentOpener {
  /// Создаёт открыватель.
  FakeDocumentOpener(this.document, {this.failure});

  /// Что отдавать при успехе.
  final ReaderDocument document;

  /// Чем падать, если открытие должно провалиться.
  final DocumentOpenException? failure;

  /// Источники, которые просили открыть.
  final List<BookSource> opened = <BookSource>[];

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    opened.add(source);
    final DocumentOpenException? error = failure;
    if (error != null) {
      throw error;
    }
    return document;
  }
}

/// Хранилище позиций в памяти.
///
/// Widget-тесты работают в подменённом времени, а настоящая база — нет:
/// смешивать их значит ловить зависания на ровном месте. Проверять же
/// саму запись в базу лучше обычными тестами — они для этого и есть.
class FakeReadingRepository implements ReadingRepository {
  final Map<String, ReadingPosition> _positions = <String, ReadingPosition>{};
  final Map<String, BookReadingSettings> _settings =
      <String, BookReadingSettings>{};

  /// Сколько раз записывали позицию.
  int saveCount = 0;

  @override
  Future<ReadingPosition?> position(String bookId) async => _positions[bookId];

  @override
  Stream<ReadingPosition?> watchPosition(String bookId) =>
      Stream<ReadingPosition?>.value(_positions[bookId]);

  @override
  Future<void> savePosition(ReadingPosition position) async {
    saveCount++;
    _positions[position.bookId] = position;
  }

  @override
  Future<BookReadingSettings> settings(
    String bookId,
    ScreenOrientation orientation,
  ) async {
    return _settings['$bookId:${orientation.name}'] ??
        BookReadingSettings(bookId: bookId, orientation: orientation);
  }

  @override
  Future<void> saveSettings(BookReadingSettings settings) async {
    _settings['${settings.bookId}:${settings.orientation.name}'] = settings;
  }
}

/// Пикер-заглушка: «человек» всегда выбирает один и тот же файл.
class FakeBookFilePicker implements BookFilePicker {
  /// Создаёт пикер.
  FakeBookFilePicker(this.result);

  /// Что вернуть; `null` — человек закрыл диалог.
  final PickedFile? result;

  @override
  Future<PickedFile?> pickPdf() async => result;
}

/// Хранилище книг в памяти: ни одного обращения к диску.
///
/// Widget-тесты живут в подменённом времени, и настоящий файловый
/// ввод-вывод в них не завершается вовсе — `pumpAndSettle` просто ждёт до
/// таймаута и валит тест. Поэтому там, где проверяется поведение экрана,
/// а не работа с файлами, книга берётся из памяти.
class MemoryBookStorage implements BookStorage {
  /// Создаёт хранилище.
  MemoryBookStorage([this.bytes = const <int>[37, 80, 68, 70]]);

  /// Содержимое любой книги в этом хранилище.
  final List<int> bytes;

  /// Источники, переданные в [release].
  final List<BookSource> released = <BookSource>[];

  @override
  Future<BookSource> adopt(PickedFile file) async {
    final String? path = file.path;
    return path != null ? FilePathSource(path) : DocumentUriSource(file.uri!);
  }

  @override
  Future<BookHandle> open(BookSource source) async => MemoryBookHandle(bytes);

  @override
  Future<bool> available(BookSource source) async => true;

  @override
  Future<void> release(BookSource source) async => released.add(source);
}

/// Книга, которая целиком лежит в памяти.
class MemoryBookHandle implements BookHandle {
  /// Создаёт книгу из байтов.
  MemoryBookHandle(this.bytes);

  /// Содержимое книги.
  final List<int> bytes;

  @override
  int get length => bytes.length;

  /// Пути нет намеренно: так ведёт себя документ Android.
  @override
  String? get path => null;

  @override
  int read(Uint8List buffer, int position, int size) {
    if (position >= bytes.length) {
      return 0;
    }
    final int end = position + size > bytes.length
        ? bytes.length
        : position + size;
    buffer.setRange(0, end - position, bytes.sublist(position, end));
    return end - position;
  }

  @override
  Future<void> close() async {}
}

/// Прямоугольники символов ровного текстового блока.
///
/// Блок занимает прямоугольник [left]…[right] по горизонтали и [top]…
/// [bottom] по вертикали, в нём [lines] строк по [charsPerLine] символов.
/// Высота символа — 60 % шага строки, так что между строками остаётся
/// просвет, как в настоящей вёрстке: без него группировка строк не
/// проверялась бы вовсе.
List<TextBox> textBlock({
  double left = 0.1,
  double top = 0.1,
  double right = 0.9,
  double bottom = 0.9,
  int lines = 10,
  int charsPerLine = 20,
}) {
  if (lines < 1 || charsPerLine < 1) {
    return const <TextBox>[];
  }
  final double step = (bottom - top) / lines;
  final double glyph = step * 0.6;
  final double charWidth = (right - left) / charsPerLine;
  return <TextBox>[
    for (int line = 0; line < lines; line++)
      for (int i = 0; i < charsPerLine; i++)
        TextBox(
          left: left + i * charWidth,
          top: top + line * step,
          right: left + i * charWidth + charWidth * 0.9,
          bottom: top + line * step + glyph,
        ),
  ];
}

/// Книга-заготовка для тестов чтения.
Book fakeBook({
  String id = 'book-read',
  String title = 'Пиковая дама',
  String path = '/books/read.pdf',
  int? pageCount,
}) {
  return Book(
    id: id,
    title: title,
    source: FilePathSource(path),
    fileSize: 4096,
    fileHash: 'hash-read',
    addedAt: DateTime.utc(2026, 8, 7, 12),
    pageCount: pageCount,
  );
}
