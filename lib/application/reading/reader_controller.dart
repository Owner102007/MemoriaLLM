import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/library/book.dart';
import '../../domain/reading/columns.dart';
import '../../domain/reading/context_paragraph.dart';
import '../../domain/reading/crop.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/reading_filter.dart';
import '../../domain/reading/sheet_placement.dart';
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
  }) : _document = document,
       _reading = reading,
       _saveDelay = saveDelay,
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
      return ReaderController(
        book: book,
        document: document,
        reading: reading,
        settings: settings,
        position: position,
        saveDelay: saveDelay,
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

  /// Доля прочитанного, от 0 до 1.
  ///
  /// Считается по страницам, а не по фрагментам: индикатор книги должен
  /// показывать одно и то же независимо от того, каким режимом её читают.
  double get progress => progressForPage(_page, pageCount);

  /// Подпись для панели: `12 / 340`.
  String get label => pageLabel(_page, pageCount);

  /// Настройки чтения этой книги в текущей ориентации экрана.
  BookReadingSettings get settings => _settings;

  /// Разобранная рамка текущей страницы; `null` — ещё считается.
  PageFrame? get frame => _frame;

  /// Прямоугольник содержимого текущей страницы с учётом настроек.
  CropBox get contentBox {
    return effectiveCrop(
      settings: _settings,
      automatic: _frame?.content ?? CropBox.full,
    );
  }

  /// Колонки текущей страницы.
  ///
  /// Деление страницы от них **не зависит** — полосы идут поперёк в любой
  /// книге (решение владельца, 23.08.2026). Колонки остаются фактом о
  /// странице: они понадобятся S6, чтобы вынуть абзац вокруг выделения в
  /// правильном порядке.
  List<ColumnBand> get columns => _frame?.columns ?? const <ColumnBand>[];

  /// Просветы между строками текущей страницы.
  List<double> get breaks => _frame?.breaks ?? const <double>[];

  /// Фрагменты текущей страницы в порядке чтения.
  List<CropBox> get fragments {
    return fragmentsFor(
      content: contentBox,
      mode: _settings.displayMode,
      breaks: breaks,
    );
  }

  /// Сколько фрагментов на текущей странице.
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
      content: contentBox,
      sheetWidth: sheet.width,
      sheetHeight: sheet.height,
      area: _area,
      breaks: breaks,
      canTurn: _canTurn,
    );
  }

  /// В каком положении экрана текущий режим имеет смысл.
  ScreenOrientation get preferredOrientation => layout.orientation;

  /// Размеры листа: одна страница или две страницы разворота рядом.
  _SheetSize _sheetSize(PageDisplayMode mode) {
    final List<int> pages = isSpreadMode(mode)
        ? spreadPages(_page, pageCount)
        : <int>[_page];
    double width = 0;
    double height = 0;
    for (final int number in pages) {
      final PageGeometry geometry = _document.geometry(number);
      width += geometry.width;
      height = height < geometry.height ? geometry.height : height;
    }
    return _SheetSize(width, height);
  }

  /// Область страницы, которую надо показать сейчас.
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

  /// Считает рамку текущей страницы, если её ещё нет.
  Future<void> loadFrame() async {
    final int target = _page;
    if (_frame?.pageNumber == target || _closed) {
      return;
    }
    final PageFrame frame = await _frames.frameFor(target);
    if (_closed || _page != target) {
      return;
    }
    _frame = frame;
    _fragment = clampFragment(_fragment, fragmentCount);
    _notify();
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
    unawaited(loadFrame());
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
  Future<void> goToPage(int page, {int fragment = 0}) async {
    final int safe = clampPage(page, pageCount);
    final PageFrame frame = await _frames.frameFor(safe);
    if (_closed) {
      return;
    }
    _page = safe;
    _frame = frame;
    final int count = fragmentCount;
    _fragment = fragment < 0 ? count - 1 : clampFragment(fragment, count);
    _dirty = true;
    _notify();
    _scheduleSave();
  }

  /// Следующий фрагмент; на последнем фрагменте последней страницы — ничего.
  ///
  /// Возвращает `true`, если позиция изменилась.
  Future<bool> nextFragment() async {
    if (_fragment + 1 < fragmentCount) {
      _fragment++;
      _dirty = true;
      _notify();
      _scheduleSave();
      return true;
    }
    if (_page >= pageCount) {
      return false;
    }
    await goToPage(_page + 1);
    return true;
  }

  /// Предыдущий фрагмент; на первом фрагменте первой страницы — ничего.
  ///
  /// Возвращает `true`, если позиция изменилась.
  Future<bool> previousFragment() async {
    if (_fragment > 0) {
      _fragment--;
      _dirty = true;
      _notify();
      _scheduleSave();
      return true;
    }
    if (_page <= 1) {
      return false;
    }
    await goToPage(_page - 1, fragment: -1);
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
    await _reading.savePosition(
      positionForPage(
        bookId: book.id,
        page: _page,
        pageCount: pageCount,
        fragment: fragment,
      ),
    );
  }

  /// Записывает позицию и закрывает документ.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
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
