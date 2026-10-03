import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/library/book.dart';
import '../../domain/reading/columns.dart';
import '../../domain/reading/context_paragraph.dart';
import '../../domain/reading/crop.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/page_turning.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/reading_filter.dart';
import '../../domain/reading/sheet_placement.dart';
import '../../domain/reading/spread.dart';
import '../../domain/reading/text_geometry.dart';
import '../../domain/reading/text_highlight.dart';
import 'page_frames.dart';

/// Чем кончилась попытка сменить режим отображения.
enum DisplayModeOutcome {
  /// Режим включён.
  applied,

  /// Он и так был включён.
  unchanged,

  /// Режим не включён: на этой странице он не увеличил бы текст.
  noGain,
}

/// Ожидание, у которого есть срок: таймер и способ его оборвать.
class _Wait {
  _Wait(this.timer, this.stop);

  final Timer timer;
  final void Function() stop;
}

/// Размеры листа: одна страница или две страницы разворота рядом.
class _SheetSize {
  const _SheetSize(this.width, this.height);

  final double width;
  final double height;
}

/// Состояние открытой книги: где читатель сейчас и что об этом знает база.
///
/// Контроллер не знает ни про виджеты, ни про PDFium: документ приходит
/// готовым интерфейсом [ReaderDocument], позиция и настройки уходят в
/// [ReadingRepository]. Поэтому всё поведение — восстановление места,
/// частота записи, читательская рамка, смена режима — проверяется
/// обычными тестами, без экрана и без настоящего PDF.
class ReaderController extends ChangeNotifier {
  /// Создаёт контроллер для уже открытого документа.
  ReaderController({
    required this.book,
    required ReaderDocument document,
    required ReadingRepository reading,
    BookReadingSettings? settings,
    ReadingPosition? position,
    PageFrameSource? frames,
    Duration saveDelay = const Duration(seconds: 2),
    Duration frameWait = kFrameWait,
  }) : _document = document,
       _reading = reading,
       _saveDelay = saveDelay,
       _frameWait = frameWait,
       _settings =
           settings ??
           BookReadingSettings(bookId: book.id, orientation: kSettingsSlot),
       _page = restorePage(position, document.pageCount) {
    _frames =
        frames ??
        PageFrameSource(document: document, options: _cropOptions(_settings));
    _initialPage = _page;
    _fragment = position?.fragment ?? 0;
  }

  /// Открывает книгу и восстанавливает место, на котором её оставили.
  static Future<ReaderController> open({
    required Book book,
    required DocumentOpener opener,
    required ReadingRepository reading,
    String? password,
    Duration saveDelay = const Duration(seconds: 2),
    Duration frameWait = kFrameWait,
  }) async {
    final ReaderDocument document = await opener.open(
      book.source,
      password: password,
    );
    try {
      final ReadingPosition? position = await reading.position(book.id);
      final BookReadingSettings settings = await reading.settings(
        book.id,
        kSettingsSlot,
      );
      // F-READ-02: книга открыта, но измерена в ней пока одна первая
      // страница. Та, с которой начнётся чтение, и её соседи измеряются
      // до первого кадра: лист обязан лечь по настоящим размерам, а не
      // по прикидочным.
      final int page = restorePage(position, document.pageCount);
      await document.measure(<int>[page - 1, page, page + 1]);
      return ReaderController(
        book: book,
        document: document,
        reading: reading,
        settings: settings,
        position: position,
        saveDelay: saveDelay,
        frameWait: frameWait,
      );
    } on Object {
      // База сломалась на ровном месте — документ всё равно надо закрыть,
      // иначе утечёт память движка.
      await document.close();
      rethrow;
    }
  }

  /// Книга.
  final Book book;

  final ReaderDocument _document;
  final ReadingRepository _reading;
  final Duration _saveDelay;

  /// Сколько переход ждёт рамку страницы (BUG-23).
  final Duration _frameWait;

  late final PageFrameSource _frames;
  int _page;
  int _fragment = 0;
  late final int _initialPage;
  BookReadingSettings _settings;
  PageFrame? _frame;
  DisplayArea _area = DisplayArea.unknown;
  bool _canTurn = true;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _closed = false;
  bool _disposed = false;
  bool _navigating = false;

  /// Действуют ли режимы листа. В ленте — нет: там лист всегда одна
  /// страница, каким бы режимом книгу ни читали по страницам.
  bool _sheetModes = true;

  /// Номер последнего запрошенного перехода (BUG-11).
  ///
  /// Рамка страницы считается не мгновенно, и переходы завершаются не в
  /// том порядке, в каком их просили. Переход, чей номер устарел, свой
  /// результат выбрасывает: экран обязан встать туда, куда читатель
  /// попросил **последним**, а не туда, где рамка досчиталась позже.
  int _request = 0;

  /// Куда ведёт переход, который ещё не закончился; `null` — такого нет.
  ///
  /// Следующий шаг считается от этой цели, а не от страницы на экране:
  /// иначе два быстрых нажатия «вперёд» дают один шаг (BUG-11).
  int? _pendingPage;
  int _pendingFragment = 0;

  /// Номер последней просьбы сменить режим — той же природы, что
  /// [_request]: смена разворота ждёт рамку соседней страницы, и за это
  /// время читатель мог выбрать другой режим.
  int _modeRequest = 0;

  /// Ожидания рамки, у которых ещё не вышел срок.
  final Set<_Wait> _waits = <_Wait>{};

  /// В какую сторону читатель листал последним: туда и готовятся рамки.
  bool _forward = true;

  /// Номер последней подготовки рамок. Новая подготовка обрывает
  /// прежнюю: рамки вокруг страницы, с которой читатель ушёл, не нужны.
  int _prepareRun = 0;
  List<OutlineEntry>? _outline;
  bool _outlineLoading = false;

  /// Сколько слоёв текста держать наготове.
  ///
  /// Четыре — это текущий лист (в развороте страниц две) и по соседу с
  /// каждой стороны: ровно то, что может понадобиться выделению, не
  /// уходя в разбор всей книги.
  static const int _layoutCacheSize = 4;

  final LinkedHashMap<int, PageTextLayout> _layouts =
      LinkedHashMap<int, PageTextLayout>();
  final Map<int, Future<PageTextLayout>> _layoutsInFlight =
      <int, Future<PageTextLayout>>{};

  /// Документ. Нужен поиску и разбору страниц.
  ReaderDocument get document => _document;

  /// Число страниц.
  int get pageCount => _document.pageCount;

  /// Текущая страница, начиная с единицы.
  int get page => _page;

  /// Текущий фрагмент внутри страницы, начиная с нуля.
  int get fragment => clampFragment(_fragment, fragmentCount);

  /// Страница, с которой книга открылась.
  ///
  /// Отличается от [page] тем, что не меняется: экран отдаёт её просмотрщику
  /// при первой отрисовке и больше к ней не возвращается.
  int get initialPage => _initialPage;

  /// Страницы листа, который сейчас на экране: одна или две страницы
  /// разворота (F-READ-06).
  ///
  /// Всё, что спрашивает «что читатель видит сейчас», — лист, подпись,
  /// прогресс, шаг листания — обязано идти отсюда, а не от номера
  /// страницы: в развороте страниц на экране две.
  List<int> get sheetPages => _pagesOf(_page, _settings.displayMode);

  /// Последняя из страниц, которые сейчас на экране.
  int get lastShownPage => sheetPages.last;

  /// Доля прочитанного, от 0 до 1.
  ///
  /// Считается по страницам, а не по фрагментам: индикатор книги должен
  /// показывать одно и то же независимо от того, каким режимом её читают.
  /// В развороте счёт идёт по правой странице: она тоже открыта, и по
  /// левой последний разворот книги не дал бы ста процентов.
  double get progress => progressForPage(lastShownPage, pageCount);

  /// Подпись для панели: `12 / 340`, в развороте — `12–13 / 340`.
  String get label => sheetLabel(sheetPages, pageCount);

  /// С какой страницы начинается следующий лист; `null` — книга кончилась.
  ///
  /// Считается от цели незаконченного перехода, если такой есть: стрелка,
  /// нажатая дважды подряд, обязана дать два шага (BUG-11).
  int? get nextSheetStart => nextSheetPage(
    page: _pendingPage ?? _page,
    pageCount: pageCount,
    spread: _isSpread,
  );

  /// С какой страницы начинается предыдущий лист; `null` — начало книги.
  int? get previousSheetStart => previousSheetPage(
    page: _pendingPage ?? _page,
    pageCount: pageCount,
    spread: _isSpread,
  );

  /// Настройки чтения этой книги в текущей ориентации экрана.
  BookReadingSettings get settings => _settings;

  /// Разобранная рамка текущей страницы; `null` — ещё считается.
  PageFrame? get frame => _frame;

  /// Прямоугольник содержимого листа в долях листа, с учётом настроек.
  ///
  /// На одной странице это её рамка. В развороте — объединение рамок
  /// обеих страниц (BUG-02): прежде сюда шла рамка одной страницы, и лист
  /// из двух понимал её поля как свои, вдвое шире.
  CropBox get contentBox => _contentFor(_settings.displayMode);

  /// Прямоугольник содержимого текущей страницы в долях **страницы**.
  ///
  /// Нужен редактору рамки: он показывает одну страницу, и рамка листа
  /// из двух страниц ему не годится.
  CropBox get pageContentBox => _pageContent(_page);

  /// Колонки текущей страницы.
  ///
  /// Деление страницы от них **не зависит** — полосы идут поперёк в любой
  /// книге (решение владельца, 23.08.2026). Колонки остаются фактом о
  /// странице: они понадобятся S6, чтобы вынуть абзац вокруг выделения в
  /// правильном порядке.
  List<ColumnBand> get columns => _frame?.columns ?? const <ColumnBand>[];

  /// Просветы между строками листа, в долях его высоты.
  ///
  /// В развороте — только общие для обеих страниц: полоса полразворота
  /// идёт через обе сразу.
  List<double> get breaks => _breaksFor(_settings.displayMode);

  /// Фрагменты листа в порядке чтения.
  List<CropBox> get fragments {
    return fragmentsFor(
      content: contentBox,
      mode: _settings.displayMode,
      breaks: breaks,
    );
  }

  /// Сколько фрагментов на листе.
  int get fragmentCount => fragments.length;

  /// Форма области показа, о которой сообщил экран.
  DisplayArea get displayArea => _area;

  /// Сообщает контроллеру, во что вписывается лист.
  ///
  /// Это не «размер экрана», а форма области показа: на телефоне она
  /// меняется при повороте, на ПК — при каждом движении края окна.
  /// Геометрия деления работает с числами и одинаково обслуживает обе
  /// платформы; [canTurn] говорит лишь о том, можно ли попросить систему
  /// повернуть экран (на ПК — нельзя, там форму окна выбирает человек).
  ///
  /// Слушатели намеренно **не** оповещаются: область сообщает сам экран, и
  /// делает он это тогда, когда уже перестраивается сам (поворот, новый
  /// размер окна). Оповещение отсюда означало бы `setState` посреди
  /// построения дерева — то есть падение на ровном месте.
  void setDisplayArea(DisplayArea area, {bool canTurn = true}) {
    _area = area;
    _canTurn = canTurn;
  }

  /// Сообщает, листается книга листами или идёт лентой.
  ///
  /// В ленте режимы листа не действуют, и разворот там — одна страница:
  /// иначе подпись называла бы две страницы над одной, а стрелки шагали
  /// бы через страницу. Сам режим остаётся в настройках книги и вернётся
  /// вместе с листанием по страницам.
  ///
  /// Слушатели не оповещаются по той же причине, что и в
  /// [setDisplayArea]: способ листания меняет сам экран и перестраивается
  /// при этом сам.
  void setSheetModes({required bool enabled}) {
    _sheetModes = enabled;
  }

  /// Раскладка текущего режима: чем режем, в какой форме показываем и
  /// насколько от этого вырос кегль.
  FragmentLayout get layout => layoutFor(_settings.displayMode);

  /// Какой была бы раскладка, если включить [mode] на этой странице.
  ///
  /// Нужна кнопкам-дробям: они обязаны показывать, что режим даст **на
  /// этой** книге, а не вообще.
  FragmentLayout layoutFor(PageDisplayMode mode) {
    final _SheetSize sheet = _sheetSize(mode);
    return chooseFragmentLayout(
      mode: mode,
      content: _contentFor(mode),
      sheetWidth: sheet.width,
      sheetHeight: sheet.height,
      area: _area,
      breaks: _breaksFor(mode),
      canTurn: _canTurn,
    );
  }

  /// В каком положении экрана текущий режим имеет смысл.
  ScreenOrientation get preferredOrientation => layout.orientation;

  /// Размеры листа: одна страница или две страницы разворота рядом.
  _SheetSize _sheetSize(PageDisplayMode mode) {
    double width = 0;
    double height = 0;
    for (final int number in _pagesOf(_page, mode)) {
      final PageGeometry geometry = _document.geometry(number);
      width += geometry.width;
      height = height < geometry.height ? geometry.height : height;
    }
    return _SheetSize(width, height);
  }

  /// Идёт ли чтение разворотами: режим разворота и не лента.
  bool get _isSpread => _sheetModes && isSpreadMode(_settings.displayMode);

  /// Страницы листа, на котором лежит [page] в режиме [mode].
  List<int> _pagesOf(int page, PageDisplayMode mode) {
    return _sheetModes && isSpreadMode(mode)
        ? spreadPages(page, pageCount)
        : <int>[page];
  }

  /// Рамка страницы [page], если она уже посчитана.
  PageFrame? _frameOf(int page) {
    return page == _page ? _frame : _frames.cached(page);
  }

  /// Рамка содержимого страницы [page] в долях страницы.
  ///
  /// BUG-23: пока своя рамка не посчитана, берётся рамка ближайшей
  /// посчитанной страницы — страница встаёт почти так, как встанет в
  /// итоге, и подрезка следом почти не видна. Занять не у кого —
  /// страница берётся целиком: лишнее поле лучше срезанного текста.
  CropBox _pageContent(int page) {
    return effectiveCrop(
      settings: _settings,
      automatic:
          _frameOf(page)?.content ?? _frames.borrowed(page) ?? CropBox.full,
    );
  }

  /// Страницы листа с размерами, рамками и просветами — для объединения.
  List<SheetPage> _sheetOf(List<int> pages) {
    return <SheetPage>[
      for (final int number in pages)
        SheetPage(
          width: _document.geometry(number).width,
          height: _document.geometry(number).height,
          content: _pageContent(number),
          breaks: _frameOf(number)?.breaks ?? const <double>[],
        ),
    ];
  }

  /// Рамка листа в режиме [mode], в долях листа.
  ///
  /// Лист из одной страницы отдаёт её рамку как есть и размеров страницы
  /// не спрашивает: считать там нечего.
  CropBox _contentFor(PageDisplayMode mode) {
    final List<int> pages = _pagesOf(_page, mode);
    if (pages.length < 2) {
      return _pageContent(_page);
    }
    return sheetContent(_sheetOf(pages));
  }

  /// Просветы листа в режиме [mode], в долях его высоты.
  List<double> _breaksFor(PageDisplayMode mode) {
    final List<int> pages = _pagesOf(_page, mode);
    if (pages.length < 2) {
      return _frame?.breaks ?? const <double>[];
    }
    return sheetBreaks(_sheetOf(pages));
  }

  /// Область листа, которую надо показать сейчас, в долях листа.
  CropBox get fragmentBox {
    final List<CropBox> parts = fragments;
    return parts[clampFragment(_fragment, parts.length)];
  }

  /// Светофильтр, собранный из настроек.
  ReadingFilterPipeline get filter =>
      ReadingFilterPipeline.fromSettings(_settings);

  /// Оглавление; `null` — ещё не читали.
  List<OutlineEntry>? get outline => _outline;

  /// Идёт ли чтение оглавления.
  bool get isOutlineLoading => _outlineLoading;

  /// Есть ли в книге оглавление. `null` — пока неизвестно.
  bool? get hasOutline => _outline?.isNotEmpty;

  /// Читает оглавление документа. Повторные вызовы бесплатны.
  Future<void> loadOutline() async {
    if (_outline != null || _outlineLoading || _closed) {
      return;
    }
    _outlineLoading = true;
    _notify();
    try {
      _outline = await _document.outline();
    } on Object {
      // Испорченное оглавление — не повод не дать читать книгу.
      _outline = const <OutlineEntry>[];
    } finally {
      _outlineLoading = false;
      _notify();
    }
  }

  /// Текст страницы вместе с местом каждого символа.
  ///
  /// Держится небольшой кэш: выделение спрашивает слой при каждом
  /// движении ручки, а разбор текста страницы стоит похода в движок.
  /// Кэш маленький намеренно — на книге в тысячу страниц он иначе растёт
  /// вместе с чтением, как это уже было с рамками.
  Future<PageTextLayout> textLayout(int pageNumber) {
    final PageTextLayout? ready = _layouts[pageNumber];
    if (ready != null) {
      return Future<PageTextLayout>.value(ready);
    }
    return _layoutsInFlight[pageNumber] ??= _loadLayout(pageNumber)
        .whenComplete(() {
          _layoutsInFlight.remove(pageNumber);
        });
  }

  /// Уже разобранный слой текста страницы или `null`.
  ///
  /// Нужен отрисовке: подсветка обязана ответить за один кадр и ждать
  /// разбора страницы не может.
  PageTextLayout? cachedLayout(int pageNumber) => _layouts[pageNumber];

  /// Абзац вокруг выделения на странице [pageNumber].
  ///
  /// Спрашивается **только тогда, когда он нужен**: промпт без
  /// `{{контекст}}` абзаца не получает, и разбирать ради него страницу
  /// незачем. Цитата, наоборот, сохраняет контекст всегда — по нему
  /// потом видно, откуда она.
  Future<ParagraphContext?> contextAround({
    required int pageNumber,
    required int start,
    required int end,
  }) async {
    final PageTextLayout layout = await textLayout(pageNumber);
    final PageFrame frame = await _frames.frameFor(pageNumber);
    return paragraphAround(
      layout: layout,
      selectionStart: start,
      selectionEnd: end,
      columns: frame.columns,
    );
  }

  /// Прямоугольники подсветки для куска текста на странице.
  ///
  /// Одна дорога и у выделения, и у найденного поиском: и то, и другое —
  /// кусок текста, который надо показать на странице. Колонки берутся из
  /// разобранной рамки, потому что без них подсветка на двухколоночной
  /// странице растянулась бы через межколоночное поле в чужой текст.
  Future<List<TextBox>> highlightFor({
    required int pageNumber,
    required int start,
    required int end,
  }) async {
    final PageTextLayout layout = await textLayout(pageNumber);
    if (!layout.hasGeometry) {
      return const <TextBox>[];
    }
    final PageFrame frame = await _frames.frameFor(pageNumber);
    return highlightRects(
      layout: layout,
      start: start,
      end: end,
      columns: frame.columns,
    );
  }

  /// Переводит место выделения в счёт **нашего** слоя текста.
  ///
  /// У pdfrx два текста страницы, и они не совпадают: сырой
  /// (`loadText`), по которому мы считаем всё — рамку, контекст,
  /// подсветку, поиск, — и разобранный на строки (`loadStructuredText`),
  /// по которому просмотрщик считает выделение. Во втором подряд идущие
  /// пробелы склеены, а переводы строк расставлены заново, поэтому число,
  /// пришедшее от просмотрщика, в нашем тексте означает не то же место.
  ///
  /// Ищется само выделение — ближайшее к подсказке вхождение. Не нашлось
  /// (тексты разошлись сильнее, чем на пробелы) — возвращается `null`, и
  /// зовущий остаётся с числами просмотрщика: это не хуже, чем было.
  Future<({int start, int end})?> locateOnPage({
    required int pageNumber,
    required String text,
    required int hint,
  }) async {
    if (text.isEmpty) {
      return null;
    }
    final PageTextLayout layout = await textLayout(pageNumber);
    final String page = layout.text;
    if (page.isEmpty) {
      return null;
    }
    if (hint >= 0 && hint + text.length <= page.length) {
      // Обычный случай: тексты сошлись, и по подсказке лежит ровно оно.
      if (page.startsWith(text, hint)) {
        return (start: hint, end: hint + text.length);
      }
    }
    int best = -1;
    int at = page.indexOf(text);
    while (at >= 0) {
      if (best < 0 || (at - hint).abs() < (best - hint).abs()) {
        best = at;
      }
      at = page.indexOf(text, at + 1);
    }
    return best < 0 ? null : (start: best, end: best + text.length);
  }

  Future<PageTextLayout> _loadLayout(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount) {
      return PageTextLayout.empty;
    }
    PageTextLayout layout;
    try {
      layout = await _document.pageTextLayout(pageNumber);
    } on Object {
      // Испорченный текстовый слой — не повод не показать страницу.
      layout = PageTextLayout.empty;
    }
    if (_closed) {
      return layout;
    }
    _layouts[pageNumber] = layout;
    while (_layouts.length > _layoutCacheSize) {
      _layouts.remove(_layouts.keys.first);
    }
    return layout;
  }

  /// Считает рамки страниц листа, если их ещё нет.
  ///
  /// В развороте рамок две: без рамки соседней страницы лист показывается
  /// с её полями целиком, и обрезка вступает в силу, когда рамка готова.
  ///
  /// Это и есть «подрезка» из BUG-23: страница уже на экране, а рамка
  /// приходит следом. Рамка, досчитавшаяся после того, как читатель ушёл
  /// на другую страницу, ничего не меняет.
  Future<void> loadFrame() async {
    final int target = _page;
    final bool ready = _frame?.pageNumber == target && _sheetFramesReady;
    if (_closed || ready) {
      return;
    }
    final PageFrame frame = await _loadSheetFrames(target);
    if (_closed || _page != target) {
      return;
    }
    _frame = frame;
    // Число полос задаёт режим, а не рамка: читатель, пришедший назад в
    // низ страницы по чужой рамке, после подрезки остаётся в её низу.
    _fragment = clampFragment(_fragment, fragmentCount);
    _notify();
    _prepareFrames();
  }

  /// Ждёт рамку открытой страницы, но не дольше [limit].
  ///
  /// Нужен открытию книги: первый кадр лучше показать уже по рамке, но
  /// держать ради неё пустой экран на скане нельзя (F-READ-02).
  Future<void> settleFrame({Duration limit = kOpenFrameWait}) async {
    await _within(loadFrame(), limit);
  }

  /// Ждёт [work], но не дольше [limit]; `true` — работа успела.
  ///
  /// Срок вышел — зовущий идёт дальше, а работа доделывается сама.
  /// Нулевой срок означает «не ждать вовсе».
  Future<bool> _within(Future<Object?> work, Duration limit) {
    final Completer<bool> done = Completer<bool>();
    _Wait? wait;
    void finish(bool inTime) {
      wait?.timer.cancel();
      _waits.remove(wait);
      if (!done.isCompleted) {
        done.complete(inTime);
      }
    }

    if (limit <= Duration.zero) {
      // Ошибку работы всё равно кто-то обязан принять: иначе она станет
      // необработанной и уронит приложение из-за рамки, которую не ждали.
      unawaited(work.then<void>((_) {}, onError: (Object _) {}));
      return Future<bool>.value(false);
    }
    wait = _Wait(Timer(limit, () => finish(false)), () => finish(false));
    _waits.add(wait);
    unawaited(
      work.then<void>(
        (_) => finish(true),
        onError: (Object _) => finish(false),
      ),
    );
    return done.future;
  }

  /// Рамка страницы [page], если посчитаны рамки всего её листа.
  PageFrame? _readyFrame(int page) {
    for (final int number in _pagesOf(page, _settings.displayMode)) {
      if (_frames.cached(number) == null) {
        return null;
      }
    }
    return _frames.cached(page);
  }

  /// Считает заранее рамки листов, куда читатель уйдёт следующим шагом.
  ///
  /// F-READ-02: к моменту нажатия рамка следующей страницы уже лежит в
  /// кэше, и переход не ждёт ничего. В ленте рамки не нужны вовсе.
  void _prepareFrames() {
    final int run = ++_prepareRun;
    if (_closed || !_sheetModes) {
      return;
    }
    final List<int> pages = framesAhead(
      page: _page,
      pageCount: pageCount,
      spread: _isSpread,
      forward: _forward,
    );
    unawaited(_prepare(run, pages));
  }

  Future<void> _prepare(int run, List<int> pages) async {
    for (final int number in pages) {
      // Читатель ушёл — эти рамки ему больше не соседние.
      if (_closed || run != _prepareRun) {
        return;
      }
      if (_frames.cached(number) != null) {
        continue;
      }
      try {
        await _frames.frameFor(number);
      } on Object {
        // Рамка про запас: не посчиталась — посчитается, когда
        // читатель туда придёт.
      }
    }
  }

  /// Посчитаны ли рамки соседних страниц листа.
  bool get _sheetFramesReady {
    for (final int number in sheetPages) {
      if (number != _page && _frames.cached(number) == null) {
        return false;
      }
    }
    return true;
  }

  /// Считает рамки всех страниц листа и отдаёт рамку самой [page].
  Future<PageFrame> _loadSheetFrames(int page) async {
    final PageFrame own = await _frames.frameFor(page);
    for (final int number in _pagesOf(page, _settings.displayMode)) {
      if (number != page) {
        await _frames.frameFor(number);
      }
    }
    return own;
  }

  /// Просмотрщик сообщил, что показывается другая страница.
  void onPageChanged(int page) {
    final int safe = clampPage(page, pageCount);
    if (safe == _page) {
      return;
    }
    _page = safe;
    // Читатель долистал сюда сам — значит, начинает страницу сначала.
    // Во время нашего собственного перехода просмотрщик по дороге может
    // отчитаться о промежуточных страницах; сбивать номер фрагмента об
    // них нельзя, поэтому переход огорожен [beginViewerNavigation].
    if (!_navigating) {
      _fragment = 0;
    }
    _frame = _frames.cached(safe);
    _dirty = true;
    _notify();
    // BUG-23: в ленте рамка каждой пролистанной страницы не считается.
    // Полос там нет, а рамка понадобится, только когда читатель вернётся
    // к листам, — тогда её и посчитает [loadFrame].
    if (_sheetModes) {
      unawaited(loadFrame());
    }
    _scheduleSave();
  }

  /// Начало собственного перехода экрана: сообщения просмотрщика о смене
  /// страницы больше не сбрасывают номер фрагмента.
  void beginViewerNavigation() {
    _navigating = true;
  }

  /// Конец собственного перехода экрана.
  void endViewerNavigation() {
    _navigating = false;
  }

  /// Переходит на страницу [page], к фрагменту [fragment].
  ///
  /// Отрицательный [fragment] означает «последний фрагмент страницы» —
  /// так листается назад: читатель должен попасть в низ предыдущей
  /// страницы, а не в её начало.
  ///
  /// BUG-11: переходу выдаётся номер. Пока считалась рамка, читатель мог
  /// попросить другой переход — тогда этот устарел и ничего не меняет.
  /// Возвращает `true`, если переход состоялся, и `false`, если его
  /// обогнал следующий: зовущему незачем довозить экран до страницы, с
  /// которой читатель уже ушёл.
  ///
  /// BUG-23: переход не ждёт рамку. Посчитанная берётся из кэша, и
  /// страница меняется сразу; непосчитанную ждут не дольше [_frameWait],
  /// а потом показывают страницу по рамке ближайшей посчитанной и
  /// подрезают, когда своя досчитается. Прежде смена страницы ждала
  /// рамку всегда, и на скане каждое нажатие стоило рендера с разбором.
  Future<bool> goToPage(int page, {int fragment = 0}) async {
    final int safe = clampPage(page, pageCount);
    final int request = ++_request;
    final bool forward = safe >= (_pendingPage ?? _page);
    _pendingPage = safe;
    _pendingFragment = fragment < 0
        ? fragmentCountFor(mode: _settings.displayMode) - 1
        : fragment;
    PageFrame? frame = _readyFrame(safe);
    if (frame == null) {
      await _within(_loadSheetFrames(safe), _frameWait);
      if (_closed || request != _request) {
        return false;
      }
      // Спрашиваем кэш заново, чем бы ни кончилось ожидание: рамка
      // страницы с текстом успевает досчитаться, даже когда её не ждали
      // вовсе, и показывать такую страницу по чужой рамке незачем.
      frame = _readyFrame(safe);
    }
    _pendingPage = null;
    _page = safe;
    // В развороте рамка самой страницы может быть готова, когда рамка
    // её соседки ещё считается: своя берётся сразу, лист подрежется.
    _frame = frame ?? _frames.cached(safe);
    _forward = forward;
    final int count = fragmentCount;
    _fragment = fragment < 0 ? count - 1 : clampFragment(fragment, count);
    _dirty = true;
    _notify();
    _scheduleSave();
    if (frame == null) {
      // Подрезка: рамка досчитается и встанет сама, а за ней — рамки
      // соседних листов.
      unawaited(loadFrame());
    } else {
      _prepareFrames();
    }
    return true;
  }

  /// Следующий фрагмент; на последнем фрагменте последнего листа — ничего.
  ///
  /// Возвращает `true`, если позиция изменилась.
  Future<bool> nextFragment() => _step(forward: true);

  /// Предыдущий фрагмент; на первом фрагменте первой страницы — ничего.
  ///
  /// Возвращает `true`, если позиция изменилась.
  Future<bool> previousFragment() => _step(forward: false);

  /// Шаг чтения: полоса, а за краем листа — соседний лист.
  ///
  /// BUG-01: в развороте соседний лист — это следующая **пара** страниц.
  /// Прежде шаг вёл на страницу + 1, а она лежит на том же листе: каждое
  /// второе нажатие не меняло экран.
  ///
  /// BUG-11: шаг считается от цели незаконченного перехода, если такой
  /// есть. Число полос на листе известно заранее — его задаёт режим, —
  /// поэтому ждать рамку той страницы не нужно.
  Future<bool> _step({required bool forward}) async {
    final int? pending = _pendingPage;
    final SheetPosition? target = stepSheet(
      page: pending ?? _page,
      fragment: pending == null ? fragment : _pendingFragment,
      pageCount: pageCount,
      fragmentCount: pending == null
          ? fragmentCount
          : fragmentCountFor(mode: _settings.displayMode),
      spread: _isSpread,
      forward: forward,
    );
    if (target == null) {
      return false;
    }
    if (pending == null && target.page == _page) {
      // Полоса того же листа: рамка уже есть, ждать нечего.
      _fragment = target.fragment;
      _dirty = true;
      _notify();
      _scheduleSave();
      return true;
    }
    await goToPage(target.page, fragment: target.fragment);
    return true;
  }

  /// Меняет режим отображения, оставляя читателя примерно на месте.
  ///
  /// Режим, который не увеличивает текст, **не включается** — и не молча:
  /// возвращается [DisplayModeOutcome.noGain], а экран объясняет это
  /// читателю. Читалка не имеет права уменьшить текст в ответ на просьбу
  /// его увеличить.
  Future<DisplayModeOutcome> setDisplayMode(PageDisplayMode mode) async {
    if (mode == _settings.displayMode) {
      return DisplayModeOutcome.unchanged;
    }
    if (!layoutFor(mode).isWorthwhile) {
      return DisplayModeOutcome.noGain;
    }
    // Разворот кладёт на лист вторую страницу. Её рамка считается до
    // смены режима: иначе первый кадр разворота вышел бы с необрезанной
    // соседней страницей, а следующий — уже с обрезанной, и текст на
    // глазах менял бы размер.
    final int request = ++_modeRequest;
    for (final int number in _pagesOf(_page, mode)) {
      if (number != _page && _frames.cached(number) == null) {
        await _frames.frameFor(number);
      }
    }
    if (_closed || request != _modeRequest) {
      return DisplayModeOutcome.unchanged;
    }
    final int oldCount = fragmentCount;
    final int oldIndex = fragment;
    _settings = _settings.copyWith(displayMode: mode);
    final int newCount = fragmentCount;
    _fragment = remapFragment(
      index: oldIndex,
      oldCount: oldCount,
      newCount: newCount,
    );
    await _saveSettings();
    if (_isSpread && !_sheetFramesReady) {
      // Пока считалась рамка соседней, читатель мог уйти на другой лист.
      await loadFrame();
    }
    return DisplayModeOutcome.applied;
  }

  /// Включает или выключает автообрезку полей.
  Future<void> setAutoCrop(bool value) async {
    if (value == _settings.autoCrop) {
      return;
    }
    _settings = _settings.copyWith(autoCrop: value);
    await _saveSettings();
  }

  /// Считать ли колонтитулы содержимым.
  Future<void> setIgnoreRunningHeads(bool value) async {
    if (value == _settings.ignoreRunningHeads) {
      return;
    }
    _settings = _settings.copyWith(ignoreRunningHeads: value);
    _frames.options = _cropOptions(_settings);
    _frame = null;
    await _saveSettings();
    await loadFrame();
  }

  /// Ставит рамку, выставленную руками, сразу на всю книгу.
  ///
  /// `null` возвращает автообрезку.
  Future<void> setManualCrop(CropBox? box) async {
    _settings = BookReadingSettings(
      bookId: _settings.bookId,
      orientation: _settings.orientation,
      displayMode: _settings.displayMode,
      autoCrop: _settings.autoCrop,
      ignoreRunningHeads: _settings.ignoreRunningHeads,
      manualCrop: box != null && box.isValid ? box : null,
      filter: _settings.filter,
      filterIntensity: _settings.filterIntensity,
      brightness: _settings.brightness,
      contrast: _settings.contrast,
      gamma: _settings.gamma,
      stripFit: _settings.stripFit,
      dimOutside: _settings.dimOutside,
    );
    _fragment = clampFragment(_fragment, fragmentCount);
    await _saveSettings();
  }

  /// Меняет запас по краям полосы.
  ///
  /// Значение приводится к допустимому диапазону здесь, а не в интерфейсе:
  /// полоса мельче [kMinStripFit] перестаёт быть чтением.
  Future<void> setStripFit(double value) async {
    final double safe = clampStripFit(value);
    if (safe == _settings.stripFit) {
      return;
    }
    await _updateSettings(_settings.copyWith(stripFit: safe));
  }

  /// Меняет силу затемнения нечитаемой части страницы.
  Future<void> setDimOutside(double value) async {
    final double safe = clampDimOutside(value);
    if (safe == _settings.dimOutside) {
      return;
    }
    await _updateSettings(_settings.copyWith(dimOutside: safe));
  }

  /// Выбирает светофильтр и сразу даёт ему заметную силу.
  Future<void> setFilter(ReadingFilter value) async {
    if (value == _settings.filter) {
      return;
    }
    _settings = _settings.copyWith(
      filter: value,
      filterIntensity: defaultFilterIntensity(value),
    );
    await _saveSettings();
  }

  /// Меняет силу фильтра.
  Future<void> setFilterIntensity(double value) =>
      _updateSettings(_settings.copyWith(filterIntensity: value));

  /// Меняет яркость.
  Future<void> setBrightness(double value) =>
      _updateSettings(_settings.copyWith(brightness: value));

  /// Меняет контраст.
  Future<void> setContrast(double value) =>
      _updateSettings(_settings.copyWith(contrast: value));

  /// Меняет гамму.
  Future<void> setGamma(double value) =>
      _updateSettings(_settings.copyWith(gamma: value));

  /// Записывает позицию немедленно.
  ///
  /// Вызывается при уходе с экрана и при сворачивании приложения: система
  /// вправе убить процесс сразу после этого, а место в книге терять нельзя.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) {
      return;
    }
    _dirty = false;
    // Место — страница, а прогресс — лист: в развороте правая страница
    // тоже открыта, и полка обязана показывать то же, что экран чтения.
    await _reading.savePosition(
      positionForPage(
        bookId: book.id,
        page: _page,
        pageCount: pageCount,
        fragment: fragment,
      ).copyWith(progress: progress),
    );
  }

  /// Записывает позицию и закрывает документ.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    // Переходы, которые ещё ждут рамку, отпускаются сразу: ждать её
    // больше некому, а таймер ожидания пережил бы закрытую книгу.
    for (final _Wait wait in _waits.toList()) {
      wait.stop();
    }
    _prepareRun++;
    await flush();
    await _document.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }

  /// Оповещает слушателей, если оповещать ещё есть кого.
  ///
  /// Разбор страницы асинхронен и вполне может закончиться после того, как
  /// читатель закрыл книгу. Оповещение уничтоженного контроллера — не
  /// мелочь, а падение приложения на ровном месте.
  void _notify() {
    if (_closed || _disposed) {
      return;
    }
    notifyListeners();
  }

  Future<void> _updateSettings(BookReadingSettings settings) async {
    _settings = settings;
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    _notify();
    await _reading.saveSettings(_settings);
  }

  /// Планирует запись позиции.
  ///
  /// Таймер намеренно **не** перезапускается на каждой странице. При
  /// быстром листании перезапуск откладывал бы запись бесконечно, и
  /// закрытое по питанию приложение теряло бы место. Здесь же запись
  /// случается не реже одного раза в [_saveDelay], сколько бы страниц
  /// ни пролистали.
  void _scheduleSave() {
    _saveTimer ??= Timer(_saveDelay, () {
      _saveTimer = null;
      unawaited(flush());
    });
  }
}

CropOptions _cropOptions(BookReadingSettings settings) {
  return CropOptions(ignoreRunningHeads: settings.ignoreRunningHeads);
}
