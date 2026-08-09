import 'dart:collection';

import '../../domain/reading/columns.dart';
import '../../domain/reading/crop.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/text_geometry.dart';

/// Рамка одной страницы: где на ней содержимое и как оно разложено.
class PageFrame {
  /// Создаёт рамку.
  const PageFrame({
    required this.pageNumber,
    required this.content,
    required this.columns,
    required this.breaks,
    required this.fromText,
  });

  /// Страница, начиная с единицы.
  final int pageNumber;

  /// Прямоугольник содержимого в долях страницы.
  final CropBox content;

  /// Колонки внутри содержимого; одна — обычная вёрстка.
  final List<ColumnBand> columns;

  /// Просветы между строками: по ним делятся половины и трети, чтобы
  /// граница не рассекала строку.
  final List<double> breaks;

  /// Считана ли рамка по тексту. `false` — страница разбиралась попиксельно.
  final bool fromText;

  /// Двухколоночная ли страница.
  bool get hasColumns => columns.length >= 2;

  @override
  String toString() =>
      'PageFrame($pageNumber, $content, колонок: ${columns.length})';
}

/// Считает и запоминает рамки страниц.
///
/// Обе дороги ведут сюда: текстовый слой, если он есть, и разбор пикселей
/// низкого рендера, если его нет. Разбор одной страницы стоит слишком
/// дорого, чтобы повторять его при каждом кадре, поэтому результат
/// хранится в кэше, а кэш ограничен: на книге в тысячу страниц он иначе
/// растёт вместе с чтением.
class PageFrameSource {
  /// Создаёт источник рамок.
  PageFrameSource({
    required ReaderDocument document,
    CropOptions options = CropOptions.standard,
    int rasterWidth = 220,
    int cacheSize = 96,
  }) : _document = document,
       _options = options,
       _rasterWidth = rasterWidth,
       _cacheSize = cacheSize;

  /// Меньше скольких символов страница считается лишённой текста.
  ///
  /// Ровно один номер страницы в углу скана — это не текстовый слой,
  /// а колонтитул, вшитый распознавалкой; рамка по нему выйдет размером
  /// с этот номер.
  static const int minTextBoxes = 12;

  final ReaderDocument _document;
  final int _rasterWidth;
  final int _cacheSize;
  final LinkedHashMap<int, PageFrame> _cache = LinkedHashMap<int, PageFrame>();
  final Map<int, Future<PageFrame>> _inFlight = <int, Future<PageFrame>>{};

  CropOptions _options;

  /// Текущие настройки обрезки.
  CropOptions get options => _options;

  /// Меняет настройки обрезки и забывает посчитанное.
  set options(CropOptions value) {
    if (value.ignoreRunningHeads == _options.ignoreRunningHeads &&
        value.padding == _options.padding &&
        value.minSize == _options.minSize &&
        value.grid == _options.grid) {
      return;
    }
    _options = value;
    _cache.clear();
  }

  /// Уже посчитанная рамка страницы или `null`.
  ///
  /// Нужна отрисовке: она обязана ответить за один кадр и ждать разбора
  /// страницы не может.
  PageFrame? cached(int pageNumber) => _cache[pageNumber];

  /// Рамка страницы. Повторные вызовы бесплатны.
  Future<PageFrame> frameFor(int pageNumber) {
    final PageFrame? ready = _cache[pageNumber];
    if (ready != null) {
      return Future<PageFrame>.value(ready);
    }
    // Один и тот же разбор часто просят дважды подряд: экран рисуется,
    // а рамка ещё считается. Второй разбор той же страницы не нужен.
    return _inFlight[pageNumber] ??= _compute(pageNumber).whenComplete(() {
      _inFlight.remove(pageNumber);
    });
  }

  /// Забывает всё посчитанное.
  void clear() {
    _cache.clear();
  }

  Future<PageFrame> _compute(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > _document.pageCount) {
      return PageFrame(
        pageNumber: pageNumber,
        content: CropBox.full,
        columns: const <ColumnBand>[ColumnBand(left: 0, right: 1)],
        breaks: const <double>[],
        fromText: false,
      );
    }

    List<TextBox> boxes = const <TextBox>[];
    try {
      boxes = await _document.pageTextBoxes(pageNumber);
    } on Object {
      // Испорченный текстовый слой — повод разобрать страницу по
      // пикселям, а не повод не показать её вовсе.
      boxes = const <TextBox>[];
    }

    PageFrame frame;
    if (boxes.length >= minTextBoxes) {
      final CropBox content = contentBoxFromTextBoxes(boxes, options: _options);
      frame = PageFrame(
        pageNumber: pageNumber,
        content: content,
        columns: detectColumns(boxes, content),
        breaks: lineBreaks(groupTextLines(boxes)),
        fromText: true,
      );
    } else {
      // У скана строк нет, и резать приходится по геометрии: попиксельный
      // разбор даёт прямоугольник содержимого, но не разметку строк.
      final CropBox content = await _rasterContent(pageNumber);
      frame = PageFrame(
        pageNumber: pageNumber,
        content: content,
        columns: <ColumnBand>[
          ColumnBand(left: content.left, right: content.right),
        ],
        breaks: const <double>[],
        fromText: false,
      );
    }

    _remember(pageNumber, frame);
    return frame;
  }

  Future<CropBox> _rasterContent(int pageNumber) async {
    try {
      final PageGeometry geometry = _document.geometry(pageNumber);
      if (geometry.width <= 0 || geometry.height <= 0) {
        return CropBox.full;
      }
      // Рендер намеренно крошечный: поля видно и на превью, а полный
      // разбор страницы в разрешении экрана стоил бы секунды.
      final int height = (_rasterWidth * geometry.height / geometry.width)
          .round()
          .clamp(8, 4000);
      final PageRaster? raster = await _document.renderPage(
        pageNumber,
        width: _rasterWidth,
        height: height,
      );
      if (raster == null) {
        return CropBox.full;
      }
      return contentBoxFromRaster(raster, options: _options);
    } on Object {
      return CropBox.full;
    }
  }

  void _remember(int pageNumber, PageFrame frame) {
    _cache.remove(pageNumber);
    _cache[pageNumber] = frame;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }
}
