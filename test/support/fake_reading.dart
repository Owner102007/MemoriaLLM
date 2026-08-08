import 'dart:typed_data';

import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';

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
  });

  /// Документ из [count] пустых страниц.
  factory FakeReaderDocument.blank(int count) {
    return FakeReaderDocument(pages: List<String>.filled(count, ''));
  }

  /// Тексты страниц.
  final List<String> pages;

  /// Оглавление.
  final List<OutlineEntry> outlineNodes;

  @override
  final String sourceName;

  /// Ширина каждой страницы.
  final double pageWidth;

  /// Высота каждой страницы.
  final double pageHeight;

  /// Сколько раз читали текст каждой страницы — по этому счётчику видно,
  /// не перечитывает ли поиск одно и то же.
  final Map<int, int> textReads = <int, int>{};

  /// Закрыт ли документ.
  bool closed = false;

  /// Бросать ли ошибку при чтении оглавления.
  bool failOutline = false;

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

  /// Пути, которые просили открыть.
  final List<String> openedPaths = <String>[];

  @override
  Future<ReaderDocument> open(String path, {String? password}) async {
    openedPaths.add(path);
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
    filePath: path,
    fileSize: 4096,
    fileHash: 'hash-read',
    addedAt: DateTime.utc(2026, 8, 7, 12),
    pageCount: pageCount,
  );
}
