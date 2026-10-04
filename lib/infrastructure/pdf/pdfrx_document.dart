import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/text_geometry.dart';

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
  PdfrxDocumentOpener({
    required BookStorage storage,
    Future<void> Function()? initialize,
    int? maxBytesInMemory,
    bool measureAllPages = false,
  }) : _storage = storage,
       _initialize = initialize ?? _flutterInitialize,
       _maxBytesInMemory = maxBytesInMemory,
       _measureAllPages = measureAllPages;

  final BookStorage _storage;
  final Future<void> Function() _initialize;

  /// Сколько книги движку разрешено держать в памяти целиком.
  ///
  /// `null` — как решит pdfrx (сегодня это мегабайт). Ноль заставляет
  /// его читать кусками всегда: так корпус-тесты гоняют настоящий путь
  /// чтения по дескриптору, а не быстрый обход для маленьких файлов.
  final int? _maxBytesInMemory;

  /// Измерять ли все страницы книги прямо при открытии.
  ///
  /// Так было до F-READ-02, и так книга в семьсот страниц открывалась
  /// секундами. Оставлено выключателем ради замера «было — стало» в
  /// корпус-тестах; приложение открывает книги без него.
  final bool _measureAllPages;

  static Future<void> _flutterInitialize() => pdfrxFlutterInitialize();

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    final BookHandle book;
    try {
      book = await _storage.open(source);
    } on BookUnavailableException catch (error) {
      throw DocumentOpenException(
        DocumentProblem.missing,
        source,
        cause: error,
      );
    }
    if (book.length == 0) {
      await book.close();
      throw DocumentOpenException(DocumentProblem.empty, source);
    }

    await _initialize();

    final String name = source.encode();
    try {
      // F-READ-02: книга открывается прогрессивно — измеряется одна
      // первая страница. Число страниц при этом известно сразу: его
      // отдаёт сам файл, и позиция с подписью «12 / 340» ничего не ждут.
      // Откладываются только размеры остальных страниц; их досчитывает
      // [PdfrxReaderDocument.measure] по мере надобности. Прежде движок
      // до первого кадра загружал каждую страницу книги ради её размера.
      final bool progressive = !_measureAllPages;
      final PdfPasswordProvider? provider = password == null
          ? null
          : createSimplePasswordProvider(password);
      final String? path = book.path;
      if (path != null) {
        // Есть путь — движок откроет файл лучше нас, и посредник ему
        // только мешал бы.
        await book.close();
        return PdfrxReaderDocument._(
          name,
          await PdfDocument.openFile(
            path,
            passwordProvider: provider,
            useProgressiveLoading: progressive,
          ),
        );
      }
      return PdfrxReaderDocument._(
        name,
        await PdfDocument.openCustom(
          read: book.read,
          fileSize: book.length,
          sourceName: name,
          passwordProvider: provider,
          useProgressiveLoading: progressive,
          maxSizeToCacheOnMemory: _maxBytesInMemory,
          // Дескриптор живёт ровно столько, сколько открыт документ.
          onDispose: () => unawaited(book.close()),
        ),
      );
    } on PdfPasswordException catch (error) {
      await book.close();
      throw DocumentOpenException(
        password == null
            ? DocumentProblem.passwordRequired
            : DocumentProblem.wrongPassword,
        source,
        cause: error,
      );
    } on PdfException catch (error) {
      await book.close();
      throw DocumentOpenException(
        DocumentProblem.damaged,
        source,
        cause: error,
      );
    } on Exception catch (error) {
      await book.close();
      throw DocumentOpenException(
        DocumentProblem.unknown,
        source,
        cause: error,
      );
    }
  }
}

/// Документ PDFium за интерфейсом [ReaderDocument].
class PdfrxReaderDocument implements ReaderDocument {
  PdfrxReaderDocument._(this.sourceName, this._document);

  @override
  final String sourceName;

  final PdfDocument _document;

  /// Сколько страниц измеряется одним походом в движок.
  ///
  /// Поиск и импорт читают страницы подряд. Измеряй мы их по одной,
  /// каждая стоила бы отдельного похода в движок и отдельного сообщения
  /// просмотрщику о том, что раскладка изменилась.
  static const int _measureBatch = 16;

  List<OutlineEntry>? _outlineCache;
  bool _closed = false;

  /// Измерения, которые идут прямо сейчас: страница → её измерение.
  final Map<int, Future<void>> _measuring = <int, Future<void>>{};

  @override
  Object? get engineDocument => _document;

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
  Future<void> measure(Iterable<int> pageNumbers) async {
    for (final int number in pageNumbers) {
      if (number >= 1 && number <= pageCount) {
        await _measured(number);
      }
    }
  }

  /// Страница с настоящими размерами (F-READ-02).
  ///
  /// У неизмеренной страницы движок не отдаёт текста, а её размеры,
  /// поворот и начало координат пока прикидочные — растр по ним вышел бы
  /// не тем. Поэтому всё, что читает содержимое страницы, приходит за
  /// ней сюда, — и поиск по всей книге видит все страницы, сколько бы их
  /// ни осталось неизмеренными при открытии.
  ///
  /// Сбой измерения книгу не роняет: возвращается страница как есть.
  /// Рамка и слой текста получат от неё пустой ответ, как от страницы
  /// без текста, а [pageText] скажет прямо, что текст не прочитан.
  Future<PdfPage> _measured(int pageNumber) async {
    PdfPage page = _pageAt(pageNumber);
    // Повтор нужен в одном случае: фоновое измерение просмотрщика
    // успело вернуть в список страницу-заготовку поверх только что
    // измеренной. Трёх попыток на это хватает с запасом.
    for (int attempt = 0; attempt < 3; attempt++) {
      if (page.isLoaded || _closed) {
        break;
      }
      try {
        await (_measuring[pageNumber] ??= _measureFrom(pageNumber));
      } on Object {
        break;
      }
      page = _pageAt(pageNumber);
    }
    return page;
  }

  /// Измеряет [pageNumber] и неизмеренные страницы сразу за ней.
  Future<void> _measureFrom(int pageNumber) {
    final List<PdfPage> pages = _document.pages;
    final List<int> batch = <int>[];
    for (int number = pageNumber; number <= pages.length; number++) {
      if (batch.length >= _measureBatch) {
        break;
      }
      if (!pages[number - 1].isLoaded && !_measuring.containsKey(number)) {
        batch.add(number);
      }
    }
    final Future<void> work = _document
        .reloadPages(pageNumbersToReload: batch)
        .whenComplete(() {
          for (final int number in batch) {
            _measuring.remove(number);
          }
        });
    for (final int number in batch) {
      _measuring[number] = work;
    }
    return work;
  }

  @override
  Future<String> pageText(int pageNumber) async {
    final PdfPage page = await _measured(pageNumber);
    final PdfPageRawText? text = await page.loadText();
    if (text == null) {
      // Движок не ответил: страница не измерилась или книга уже
      // закрыта. Это не «страница без текста» — у той текст пустой, а не
      // отсутствующий. Разница важна кэшу текста (F-TEXT-04): пустой
      // ответ он запоминает навсегда, а этот обязан спросить ещё раз.
      throw StateError('текст страницы $pageNumber не прочитан');
    }
    return text.fullText;
  }

  @override
  Future<List<TextBox>> pageTextBoxes(int pageNumber) async {
    final PdfPage page = await _measured(pageNumber);
    final PdfPageRawText? raw = await page.loadText();
    if (raw == null) {
      return const <TextBox>[];
    }
    final List<PdfRect> rects = raw.charRects;
    if (rects.isEmpty) {
      return const <TextBox>[];
    }
    final List<int> codes = _alignedCodes(raw.fullText, rects.length);
    final double width = page.width;
    final double height = page.height;
    if (width <= 0 || height <= 0) {
      return const <TextBox>[];
    }

    final List<TextBox> boxes = <TextBox>[];
    for (int i = 0; i < rects.length; i++) {
      if (i < codes.length && _isBlank(codes[i])) {
        continue;
      }
      final PdfRect rect = rects[i];
      if (rect.isEmpty) {
        continue;
      }
      // Координаты символов лежат в неповёрнутом пространстве страницы
      // и снизу вверх; `toRect` разворачивает их в то, что видит читатель.
      final Rect display = rect.toRect(page: page);
      final TextBox box = TextBox(
        left: (display.left / width).clamp(0.0, 1.0),
        top: (display.top / height).clamp(0.0, 1.0),
        right: (display.right / width).clamp(0.0, 1.0),
        bottom: (display.bottom / height).clamp(0.0, 1.0),
      );
      if (!box.isValid) {
        continue;
      }
      // Символ размером в треть страницы — это не буквица, а мусор из
      // сломанного шрифта. Такой прямоугольник растянул бы рамку на всё.
      if (box.height > 0.3 || box.width > 0.5) {
        continue;
      }
      boxes.add(box);
    }
    return boxes;
  }

  @override
  Future<PageTextLayout> pageTextLayout(int pageNumber) async {
    final PdfPage page = await _measured(pageNumber);
    final PdfPageRawText? raw = await page.loadText();
    if (raw == null || raw.fullText.isEmpty) {
      return PageTextLayout.empty;
    }
    final String text = raw.fullText;
    final List<PdfRect> rects = raw.charRects;
    final double width = page.width;
    final double height = page.height;
    if (rects.isEmpty || width <= 0 || height <= 0) {
      return PageTextLayout(text: text, boxes: const <TextBox>[]);
    }

    // Прямоугольники приходят по одному на символ, а «символ» у движка —
    // это кодовая точка, тогда как индекс в строке Dart считает кодовые
    // единицы. Пока в тексте нет ничего за пределами основной плоскости
    // Юникода, это одно и то же; как только встретится эмодзи или редкий
    // иероглиф, прямое обращение по индексу поедет — и выделение начнёт
    // подсвечивать соседние буквы. Поэтому места раскладываются по
    // кодовым единицам явно.
    final List<TextBox> boxes = List<TextBox>.filled(
      text.length,
      _noBox,
      growable: false,
    );
    if (text.length == rects.length) {
      for (int i = 0; i < rects.length; i++) {
        boxes[i] = _boxOf(rects[i], page, width, height);
      }
      return PageTextLayout(text: text, boxes: boxes);
    }
    final List<int> runes = text.runes.toList();
    if (runes.length != rects.length) {
      // Ни одна разбивка не сошлась — геометрии у этой страницы для нас
      // нет. Текст при этом честно отдаётся: он нужен поиску и контексту.
      return PageTextLayout(text: text, boxes: const <TextBox>[]);
    }
    int at = 0;
    for (int i = 0; i < runes.length; i++) {
      final TextBox box = _boxOf(rects[i], page, width, height);
      final int units = runes[i] > 0xFFFF ? 2 : 1;
      for (int u = 0; u < units && at < boxes.length; u++, at++) {
        boxes[at] = box;
      }
    }
    return PageTextLayout(text: text, boxes: boxes);
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
    final PdfPage page = await _measured(pageNumber);
    final PdfImage? image = await page.render(
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

  /// Коды символов, выровненные с прямоугольниками один к одному.
  ///
  /// PDFium отдаёт по прямоугольнику на символ, а текст приходит строкой:
  /// символ вне основной плоскости Юникода занимает в ней две единицы, и
  /// прямое обращение по индексу после первого же такого символа поедет.
  /// Поэтому берётся та разбивка, длина которой сошлась с числом
  /// прямоугольников; если не сошлась ни одна, пробелы просто не
  /// отфильтровываются — рамка получится чуть шире, но не поедет.
  List<int> _alignedCodes(String text, int expected) {
    final List<int> runes = text.runes.toList();
    if (runes.length == expected) {
      return runes;
    }
    if (text.length == expected) {
      return text.codeUnits;
    }
    return const <int>[];
  }

  /// Прямоугольник символа в долях отображаемой страницы.
  ///
  /// Пустой прямоугольник (пробел, перевод строки) остаётся пустым: место
  /// в списке за ним сохраняется, чтобы индексы не поехали, а рисовать
  /// там нечего.
  TextBox _boxOf(PdfRect rect, PdfPage page, double width, double height) {
    if (rect.isEmpty) {
      return _noBox;
    }
    final Rect display = rect.toRect(page: page);
    final TextBox box = TextBox(
      left: (display.left / width).clamp(0.0, 1.0),
      top: (display.top / height).clamp(0.0, 1.0),
      right: (display.right / width).clamp(0.0, 1.0),
      bottom: (display.bottom / height).clamp(0.0, 1.0),
    );
    return box.isValid ? box : _noBox;
  }

  bool _isBlank(int code) {
    switch (code) {
      case 0x09:
      case 0x0A:
      case 0x0B:
      case 0x0C:
      case 0x0D:
      case 0x20:
      case 0x85:
      case 0xA0:
      case 0x1680:
      case 0x2028:
      case 0x2029:
      case 0x202F:
      case 0x205F:
      case 0x2060:
      case 0x3000:
      case 0xFEFF:
      case 0xFFFE:
      case 0xFFFF:
        return true;
      default:
        return (code >= 0x2000 && code <= 0x200B) || code == 0;
    }
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

/// Пустое место: у символа нет своего прямоугольника на странице.
const TextBox _noBox = TextBox(left: 0, top: 0, right: 0, bottom: 0);
