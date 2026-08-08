import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/library/book.dart';
import '../../domain/reading/columns.dart';
import '../../domain/reading/crop.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/navigation.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/reading_filter.dart';
import 'page_frames.dart';

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
           BookReadingSettings(
             bookId: book.id,
             orientation: ScreenOrientation.portrait,
           ),
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
    ScreenOrientation orientation = ScreenOrientation.portrait,
    String? password,
    Duration saveDelay = const Duration(seconds: 2),
  }) async {
    final ReaderDocument document = await opener.open(
      book.filePath,
      password: password,
    );
    try {
      final ReadingPosition? position = await reading.position(book.id);
      final BookReadingSettings settings = await reading.settings(
        book.id,
        orientation,
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
  Timer? _saveTimer;
  bool _dirty = false;
  bool _closed = false;
  bool _disposed = false;
  bool _navigating = false;
  List<OutlineEntry>? _outline;
  bool _outlineLoading = false;

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
  List<ColumnBand> get columns => _frame?.columns ?? const <ColumnBand>[];

  /// Фрагменты текущей страницы в порядке чтения.
  List<CropBox> get fragments {
    return fragmentsFor(
      content: contentBox,
      mode: _settings.displayMode,
      columns: columns,
    );
  }

  /// Сколько фрагментов на текущей странице.
  int get fragmentCount => fragments.length;

  /// Куда идёт чтение внутри страницы — вниз или вправо.
  FragmentFlow get fragmentFlow => fragmentFlowFor(fragments);

  /// В каком положении экрана этот режим имеет смысл.
  ScreenOrientation get preferredOrientation =>
      preferredOrientationFor(_settings.displayMode);

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
  Future<void> setDisplayMode(PageDisplayMode mode) async {
    if (mode == _settings.displayMode) {
      return;
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
    );
    _fragment = clampFragment(_fragment, fragmentCount);
    await _saveSettings();
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

  /// Читатель повернул экран: настройки для новой ориентации свои.
  ///
  /// Своими остаются рамка, фильтр, яркость — то, что зависит от того,
  /// как экран стоит. **Режим отображения переносится**: читатель выбрал
  /// половину страницы, экран повернулся ради неё же, и обнаружить после
  /// поворота обратно целую страницу было бы издевательством.
  Future<void> setOrientation(ScreenOrientation orientation) async {
    if (orientation == _settings.orientation || _closed) {
      return;
    }
    final int oldCount = fragmentCount;
    final int oldIndex = fragment;
    final PageDisplayMode mode = _settings.displayMode;
    _settings = await _reading.settings(book.id, orientation);
    if (_closed) {
      return;
    }
    if (_settings.displayMode != mode) {
      _settings = _settings.copyWith(displayMode: mode);
      await _reading.saveSettings(_settings);
      if (_closed) {
        return;
      }
    }
    _frames.options = _cropOptions(_settings);
    _fragment = remapFragment(
      index: oldIndex,
      oldCount: oldCount,
      newCount: fragmentCount,
    );
    _notify();
  }

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
