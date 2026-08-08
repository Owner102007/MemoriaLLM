import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/reader_document.dart';

/// Открывает PDF движком PDFium через `pdfrx`.
///
/// Единственное место в приложении, которое знает про PDFium. Всё
/// остальное разговаривает с книгой через [ReaderDocument], поэтому
/// сценарии чтения тестируются подставным документом, а корпус-тесты
/// гоняют настоящий движок через ту же дверь.
class PdfrxDocumentOpener implements DocumentOpener {
  /// Создаёт открыватель.
  ///
  /// [initialize] нужен потому, что pdfrx инициализируется по-разному в
  /// приложении и вне его: приложению нужен каталог кэша от Flutter,
  /// headless-тесту — обычный временный каталог и путь к библиотеке
  /// PDFium из `PDFIUM_PATH`. Подменяемый инициализатор избавляет от
  /// проверок «а мы сейчас в тесте?» внутри рабочего кода.
  PdfrxDocumentOpener({Future<void> Function()? initialize})
    : _initialize = initialize ?? _flutterInitialize;

  final Future<void> Function() _initialize;

  static Future<void> _flutterInitialize() => pdfrxFlutterInitialize();

  @override
  Future<ReaderDocument> open(String path, {String? password}) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw DocumentOpenException(DocumentProblem.missing, path);
    }
    if (await file.length() == 0) {
      throw DocumentOpenException(DocumentProblem.empty, path);
    }

    await _initialize();

    try {
      final PdfDocument document = await PdfDocument.openFile(
        path,
        passwordProvider: password == null
            ? null
            : createSimplePasswordProvider(password),
        // Число страниц нужно сразу: без него не восстановить позицию и
        // не показать «12 / 340». Прогрессивная загрузка отдаёт его позже.
        useProgressiveLoading: false,
      );
      return PdfrxReaderDocument._(path, document);
    } on PdfPasswordException catch (error) {
      throw DocumentOpenException(
        password == null
            ? DocumentProblem.passwordRequired
            : DocumentProblem.wrongPassword,
        path,
        cause: error,
      );
    } on PdfException catch (error) {
      throw DocumentOpenException(DocumentProblem.damaged, path, cause: error);
    } on Exception catch (error) {
      throw DocumentOpenException(DocumentProblem.unknown, path, cause: error);
    }
  }
}

/// Документ PDFium за интерфейсом [ReaderDocument].
class PdfrxReaderDocument implements ReaderDocument {
  PdfrxReaderDocument._(this.sourceName, this._document);

  @override
  final String sourceName;

  final PdfDocument _document;

  List<OutlineEntry>? _outlineCache;
  bool _closed = false;

  @override
  int get pageCount => _document.pages.length;

  @override
  PageGeometry geometry(int pageNumber) {
    final PdfPage page = _pageAt(pageNumber);
    return PageGeometry(
      width: page.width,
      height: page.height,
      quarterTurns: page.rotation.index,
    );
  }

  @override
  Future<String> pageText(int pageNumber) async {
    final PdfPageRawText? text = await _pageAt(pageNumber).loadText();
    return text?.fullText ?? '';
  }

  @override
  Future<List<OutlineEntry>> outline() async {
    // Оглавление читается один раз: панель открывают и закрывают часто,
    // а дерево от этого не меняется.
    return _outlineCache ??= _convertOutline(await _document.loadOutline());
  }

  @override
  Future<PageRaster?> renderPage(
    int pageNumber, {
    required int width,
    required int height,
  }) async {
    if (width <= 0 || height <= 0) {
      return null;
    }
    final PdfImage? image = await _pageAt(pageNumber).render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (image == null) {
      return null;
    }
    try {
      // Копия обязательна: `pixels` смотрит в память движка, и после
      // `dispose` это уже чужие байты.
      return PageRaster(
        width: image.width,
        height: image.height,
        pixels: Uint8List.fromList(image.pixels),
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _document.dispose();
  }

  PdfPage _pageAt(int pageNumber) {
    final List<PdfPage> pages = _document.pages;
    if (pageNumber < 1 || pageNumber > pages.length) {
      throw RangeError.range(pageNumber, 1, pages.length, 'pageNumber');
    }
    return pages[pageNumber - 1];
  }

  List<OutlineEntry> _convertOutline(List<PdfOutlineNode> nodes) {
    return <OutlineEntry>[
      for (final PdfOutlineNode node in nodes)
        OutlineEntry(
          title: node.title,
          pageNumber: _pageOfDest(node.dest),
          children: _convertOutline(node.children),
        ),
    ];
  }

  int? _pageOfDest(PdfDest? dest) {
    if (dest == null) {
      return null;
    }
    final int page = dest.pageNumber;
    // Назначение может указывать за край: PDF собирают чем попало,
    // и обрезанная книга с полным оглавлением — обычное дело.
    if (page < 1 || page > pageCount) {
      return null;
    }
    return page;
  }
}
