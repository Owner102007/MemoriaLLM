import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../application/app_services.dart';
import '../../application/library/book_importer.dart';
import '../../application/reading/book_selection.dart';
import '../../application/reading/document_search.dart';
import '../../application/reading/reader_controller.dart';
import '../../domain/annotations/annotations.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/ids.dart';
import '../../domain/prompts/selection_prompt.dart';
import '../../domain/reading/context_paragraph.dart';
import '../../domain/reading/fragments.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/reading/reader_gestures.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/text_geometry.dart';
import '../../domain/reading/text_search.dart';
import '../../domain/settings/app_settings.dart';
import '../annotations/annotations_screen.dart';
import 'crop_editor_screen.dart';
import 'display_mode_buttons.dart';
import 'highlight_layer.dart';
import 'note_dialog.dart';
import 'prompt_preview_sheet.dart';
import 'reader_scaffold.dart';
import 'reader_settings_sheet.dart';
import 'reader_sheet.dart';
import 'reading_filter_layer.dart';
import 'selection_panel.dart';

/// Экран чтения.
///
/// Единственное место, где встречаются `pdfrx` и всё остальное:
/// просмотрщик рисует страницу, а состояние книги — где читатель, какая
/// у страницы рамка, какой фильтр — живёт в [ReaderController] и ничего
/// про виджеты не знает.
///
/// **Рамка работает в постраничном листании.** Там читатель ходит по
/// фрагментам, и каждый фрагмент занимает весь экран. Непрерывная лента
/// оставлена как есть: это другой способ читать, и навязывать ему рамку
/// значит сломать оба.
class ReaderScreen extends StatefulWidget {
  /// Создаёт экран чтения.
  const ReaderScreen({required this.book, required this.services, super.key});

  /// Книга.
  final Book book;

  /// Службы приложения.
  final AppServices services;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  /// Просмотрщик непрерывной ленты. Постраничное чтение рисует лист сам.
  final PdfViewerController _viewer = PdfViewerController();

  /// Рычаги к листу: снять выделение, не трогая страницу.
  final ReaderSheetController _sheet = ReaderSheetController();

  /// Книга может смениться прямо на этом экране: если файл переехал,
  /// читатель выбирает его заново, и у книги становится новый источник.
  /// Идентификатор при этом прежний — место чтения и цитаты не теряются.
  late Book _book = widget.book;
  ReaderController? _controller;
  DocumentSearch? _search;
  DocumentOpenException? _failure;
  bool _loading = true;
  PageFlow _flow = PageFlow.paged;
  AppLifecycleListener? _lifecycle;
  ScreenOrientation _rotation = ScreenOrientation.portrait;
  bool _zoomLocked = true;
  DisplayArea _area = DisplayArea.unknown;

  /// Что выделено сейчас.
  BookSelection? _selection;

  /// Промпты читателя: набор книги, если он есть, иначе мастерский.
  PromptSet _prompts = PromptSet.empty;
  StreamSubscription<PromptSet>? _promptsWatch;

  /// Что подсвечено на странице: найденное поиском или открытая цитата.
  _PageMark? _mark;
  List<TextBox> _markRects = const <TextBox>[];

  /// Язык, на который читатель просит переводить. Подставляется в
  /// `{{мой_язык}}`; настоящий выбор языка появится в S8 вместе с
  /// редактором промптов.
  String _myLanguage = 'русский';

  /// Можно ли попросить систему повернуть экран.
  ///
  /// На ПК — нельзя: `setPreferredOrientations` там не делает ничего, а
  /// форму окна выбирает человек. Поэтому и кнопки поворота на ПК нет:
  /// кнопка, которая заведомо ничего не сделает, хуже её отсутствия.
  static final bool _canTurn =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Чтение во весь экран: системные панели уходят и возвращаются по
    // жесту от края. Страница — это вся поверхность, а не окно в ней.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    // Свернули приложение — записываем место немедленно: система вправе
    // убить процесс сразу после этого, и переспросить будет некого.
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_controller?.flush()),
      onDetach: () => unawaited(_controller?.flush()),
    );
    unawaited(_restoreDeviceSettings());
    // Набор промптов слушается живьём: правка мастер-набора в настройках
    // обязана менять подписи на кнопках, не закрывая книгу.
    _promptsWatch = widget.services.data.prompts
        .watchPromptsFor(widget.book.id)
        .listen((PromptSet set) {
          if (mounted) {
            setState(() => _prompts = set);
          }
        });
    unawaited(_open());
  }

  /// Форма области показа приходит из системы и меняется сама: поворот
  /// телефона, изменение размера окна на ПК. Геометрия деления страницы
  /// работает с этими числами, а не с признаком «портрет или альбом», —
  /// иначе на ПК, где ориентации нет вовсе, ей нечего было бы сказать.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Size size = MediaQuery.sizeOf(context);
    _area = DisplayArea(width: size.width, height: size.height);
    _controller?.setDisplayArea(_area, canTurn: _canTurn);
  }

  /// Положение экрана и способ листания — настройки устройства, а не
  /// книги: держать телефон боком читатель привыкает один раз.
  Future<void> _restoreDeviceSettings() async {
    final AppSettingsRepository settings = widget.services.data.settings;
    final String? rotation = await settings.read(SettingsKeys.readingRotation);
    final String? flow = await settings.read(SettingsKeys.pageFlow);
    final String? locked = await settings.read(SettingsKeys.zoomLock);
    final String? language = await settings.read(SettingsKeys.targetLanguage);
    if (!mounted) {
      return;
    }
    _myLanguage = language ?? _myLanguage;
    setState(() {
      _rotation = rotation == ScreenOrientation.landscape.name
          ? ScreenOrientation.landscape
          : ScreenOrientation.portrait;
      _flow = flow == PageFlow.continuous.name
          ? PageFlow.continuous
          : PageFlow.paged;
      // Заперто по умолчанию: обычное чтение — это листание, и страница,
      // уехавшая от случайного движения двумя пальцами, читателю ничего
      // не даёт, а вернуть её он не догадается.
      _zoomLocked = locked != 'false';
    });
    await _applyRotation();
  }

  /// Поворачивает экран сам, не спрашивая систему.
  ///
  /// Автоповорот у многих выключен насовсем, а без поворота деление
  /// страницы на полосы не даёт ровным счётом ничего: полоса той же
  /// ширины вписывается в вертикальный экран тем же масштабом, что и
  /// целая страница. Принудительная ориентация сильнее пользовательской
  /// блокировки — именно так поступают видеоплееры.
  Future<void> _applyRotation() async {
    if (!_canTurn) {
      return;
    }
    await SystemChrome.setPreferredOrientations(
      _rotation == ScreenOrientation.landscape
          ? const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const <DeviceOrientation>[
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  Future<void> _setRotation(ScreenOrientation rotation) async {
    if (rotation == _rotation) {
      return;
    }
    setState(() => _rotation = rotation);
    await widget.services.data.settings.write(
      SettingsKeys.readingRotation,
      rotation.name,
    );
    await _applyRotation();
  }

  /// Запирает и отпирает масштаб.
  ///
  /// Настройка устройства, а не книги: привычка держать страницу
  /// запертой не меняется от книги к книге.
  Future<void> _setZoomLocked(bool value) async {
    if (value == _zoomLocked) {
      return;
    }
    setState(() => _zoomLocked = value);
    await widget.services.data.settings.write(
      SettingsKeys.zoomLock,
      value.toString(),
    );
  }

  Future<void> _setFlow(PageFlow flow) async {
    if (flow == _flow) {
      return;
    }
    setState(() => _flow = flow);
    await widget.services.data.settings.write(SettingsKeys.pageFlow, flow.name);
  }

  /// Смена режима отображения заодно поворачивает чтение.
  ///
  /// Положение экрана выбирает геометрия: на двухколоночной книге
  /// половина — это колонка, и её экран **вертикальный**, а поворот в
  /// альбом сделал бы текст мельче целой страницы. Режим, у которого
  /// выигрыша нет вовсе, не включается — но и не молчит: читателю
  /// говорится, почему страница осталась целой.
  Future<void> _setDisplayMode(PageDisplayMode mode) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final DisplayModeOutcome outcome = await controller.setDisplayMode(mode);
    if (outcome == DisplayModeOutcome.noGain) {
      _explainNoGain(mode);
      return;
    }
    // Пока область показа не измерена, поворачивать экран не по чему:
    // поворот вслепую — это ровно та ошибка, от которой уходим.
    final FragmentLayout layout = controller.layout;
    if (layout.isKnown) {
      await _setRotation(layout.orientation);
    }
  }

  /// Говорит, почему деление не включилось.
  void _explainNoGain(PageDisplayMode mode) {
    if (!mounted) {
      return;
    }
    final String fraction = mode == PageDisplayMode.third ? '⅓' : '½';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('reader-mode-no-gain'),
        duration: const Duration(seconds: 3),
        content: Text(
          'На этой странице $fraction не увеличит текст — страница '
          'осталась целой.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    _lifecycle?.dispose();
    unawaited(_promptsWatch?.cancel());
    _search?.dispose();
    final ReaderController? controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(controller.close().then((_) => controller.dispose()));
    }
    super.dispose();
  }

  Future<void> _open({String? password}) async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final ReaderController controller = await ReaderController.open(
        book: _book,
        opener: widget.services.opener,
        reading: widget.services.data.reading,
        password: password,
      );
      await widget.services.data.library.markOpened(_book.id, DateTime.now());
      if (!mounted) {
        await controller.close();
        controller.dispose();
        return;
      }
      controller.addListener(_onControllerChanged);
      controller.setDisplayArea(_area, canTurn: _canTurn);
      unawaited(controller.loadFrame());
      setState(() {
        _controller = controller;
        _search = DocumentSearch(document: controller.document);
        _loading = false;
      });
    } on DocumentOpenException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  /// Привязывает книгу к заново выбранному файлу.
  ///
  /// Файл переименовали, унесли карту памяти, отозвали разрешение на
  /// ссылку — книга при этом никуда не делась: место чтения, цитаты и
  /// заметки принадлежат ей, а не файлу. Поэтому «файл недоступен» — это
  /// не тупик с кнопкой «назад», а предложение показать файл заново.
  Future<void> _relink() async {
    final PickedFile? file = await widget.services.picker.pickPdf();
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    final BookImporter importer = BookImporter(
      library: widget.services.data.library,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
    try {
      _book = await importer.relink(_book, file);
    } on DocumentOpenException catch (error) {
      if (mounted) {
        setState(() {
          _failure = error;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      await _open();
    }
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    // Читатель ушёл со страницы — подсветке нечего показывать: текста, к
    // которому она относилась, на экране больше нет.
    final _PageMark? mark = _mark;
    if (mark != null && mark.pageNumber != _controller?.page) {
      _mark = null;
      _markRects = const <TextBox>[];
    }
    setState(() {});
  }

  /// Снять выделение вместе с панелью.
  ///
  /// Выделение живёт внутри просмотрщика — он же его и рисует, — поэтому
  /// снимается оно там, а панель уходит вместе с ним.
  void _dismissSelection() {
    _sheet.clearSelection();
    if (_selection == null) {
      return;
    }
    setState(() => _selection = null);
  }

  Future<void> _onSelectionRanges(List<PdfPageTextRange> ranges) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (ranges.isEmpty) {
      if (mounted && _selection != null) {
        setState(() => _selection = null);
      }
      return;
    }
    // Берётся первый кусок: на листе видна одна страница или разворот, и
    // выделение через границу страниц — редкость, ради которой не стоит
    // усложнять панель. Текст при этом склеивается весь.
    final PdfPageTextRange range = ranges.first;
    final String text = ranges
        .map((PdfPageTextRange part) => part.text)
        .join(' ')
        .trim();
    // Просмотрщик считает места по своему разбору страницы, а всё
    // остальное в читалке — по нашему. Числа переводятся сразу, у самого
    // входа: дальше по ним и подсветка, и абзац контекста, и координаты
    // цитаты, которые уедут в базу и переживут перезапуск.
    final ({int start, int end})? place = await controller.locateOnPage(
      pageNumber: range.pageNumber,
      text: range.text,
      hint: range.start,
    );
    final int start = place?.start ?? range.start;
    final int end = place?.end ?? range.end;
    final List<TextBox> rects = await controller.highlightFor(
      pageNumber: range.pageNumber,
      start: start,
      end: end,
    );
    if (!mounted) {
      return;
    }
    final BookSelection selection = BookSelection(
      pageNumber: range.pageNumber,
      start: start,
      end: end,
      text: text,
      rects: rects,
    );
    setState(() => _selection = selection.isEmpty ? null : selection);
  }

  /// Нажали на промпт читателя.
  ///
  /// Модели ещё нет — она появится в S8. Кнопка при этом не молчит:
  /// показывается готовый запрос со всеми подстановками. Заодно это
  /// единственный способ увидеть глазами, тот ли абзац достался
  /// контекстом.
  Future<void> _onPrompt(SelectionPrompt prompt) async {
    final BookSelection? selection = _selection;
    final ReaderController? controller = _controller;
    if (selection == null || controller == null) {
      return;
    }
    String? context;
    if (prompt.check.needsContext) {
      final ParagraphContext? paragraph = await controller.contextAround(
        pageNumber: selection.pageNumber,
        start: selection.start,
        end: selection.end,
      );
      context = paragraph?.text;
    }
    final String request = fillPrompt(
      prompt.body,
      selection: selection.text,
      context: context,
      bookLanguage: _book.language,
      myLanguage: _myLanguage,
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: this.context,
      isScrollControlled: true,
      builder: (BuildContext context) =>
          PromptPreviewSheet(prompt: prompt, request: request),
    );
  }

  /// Сохраняет выделенное цитатой.
  ///
  /// Контекст сохраняется всегда, а не только когда его просит промпт: по
  /// нему через месяц видно, откуда цитата и о чём там была речь.
  Future<Quote?> _saveQuote() async {
    final BookSelection? selection = _selection;
    final ReaderController? controller = _controller;
    if (selection == null || controller == null) {
      return null;
    }
    final ParagraphContext? paragraph = await controller.contextAround(
      pageNumber: selection.pageNumber,
      start: selection.start,
      end: selection.end,
    );
    final Quote quote = Quote(
      id: newLibraryId(),
      bookId: _book.id,
      page: selection.pageNumber,
      content: selection.text,
      context: paragraph?.text,
      // Место цитаты в тексте страницы: по нему она подсвечивается, когда
      // читатель возвращается к ней из списка. У цитат, сохранённых до
      // схемы 8, его нет — такие открываются на своей странице без
      // подсветки.
      textStart: selection.start,
      textEnd: selection.end,
      createdAt: DateTime.now(),
    );
    await widget.services.data.annotations.saveQuote(quote);
    return quote;
  }

  Future<void> _onQuote() async {
    final Quote? quote = await _saveQuote();
    if (!mounted) {
      return;
    }
    _dismissSelection();
    if (quote != null) {
      _say('Цитата сохранена');
    }
  }

  /// Заметка пишется к месту, а не в пустоту.
  ///
  /// Поэтому вместе с ней сохраняется и сама цитата: заметка «здесь автор
  /// себе противоречит» без того, чему она противоречит, через месяц не
  /// значит ничего. Цитата заводится **после** того, как читатель написал
  /// заметку: отменённое окно не должно оставлять за собой следов.
  Future<void> _onNote() async {
    final BookSelection? selection = _selection;
    if (selection == null) {
      return;
    }
    final String? body = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => NoteDialog(quote: selection.text),
    );
    if (body == null || !mounted) {
      return;
    }
    final Quote? quote = await _saveQuote();
    if (quote == null || !mounted) {
      return;
    }
    final DateTime now = DateTime.now();
    await widget.services.data.annotations.saveNote(
      Note(
        id: newLibraryId(),
        bookId: _book.id,
        quoteId: quote.id,
        page: quote.page,
        body: body,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) {
      return;
    }
    _dismissSelection();
    _say('Заметка сохранена');
  }

  Future<void> _onCopy() async {
    final BookSelection? selection = _selection;
    if (selection == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: selection.text));
    if (!mounted) {
      return;
    }
    _dismissSelection();
    _say('Скопировано');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Переход к найденному с подсветкой самого совпадения.
  ///
  /// Долг S3: список результатов был, а подсветки на странице не было —
  /// координаты символов появились только в S4, а перевод «место в тексте
  /// → прямоугольник» написан в S6.
  Future<void> _goToHit(SearchHit hit) async {
    await _showMark(
      page: hit.pageNumber,
      start: hit.sourceStart,
      end: hit.sourceEnd,
    );
  }

  /// Открывает страницу и подсвечивает на ней кусок текста.
  ///
  /// Подсветка **держится**, пока читатель на этой странице: она отвечает
  /// на вопрос «где здесь то, что я искал», и первое же касание экрана
  /// этого ответа не отменяет (правка по проверке S6: прежде подсветка
  /// пропадала от любого нажатия, и найти её снова было нечем).
  ///
  /// Без координат — просто переход на страницу. Так открываются старые
  /// цитаты, сохранённые до схемы 8: подсвечивать у них нечего, и делать
  /// вид, что есть, нечестно.
  Future<void> _showMark({
    required int page,
    required int? start,
    required int? end,
  }) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await _goToPage(page);
    if (!mounted) {
      return;
    }
    if (start == null || end == null || end <= start) {
      setState(() {
        _mark = null;
        _markRects = const <TextBox>[];
      });
      return;
    }
    final List<TextBox> rects = await controller.highlightFor(
      pageNumber: page,
      start: start,
      end: end,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _mark = _PageMark(pageNumber: page, start: start, end: end);
      _markRects = rects;
    });
  }

  /// Экран «Цитаты и заметки» и возвращение из него в книгу.
  ///
  /// Карточка отвечает на вопрос «а где это было»: экран закрывается,
  /// книга открывается на своей странице, сама цитата подсвечена.
  Future<void> _openAnnotations() async {
    final AnnotationTarget? target = await Navigator.of(context)
        .push<AnnotationTarget>(
          MaterialPageRoute<AnnotationTarget>(
            builder: (BuildContext context) => AnnotationsScreen(
              book: _book,
              annotations: widget.services.data.annotations,
            ),
          ),
        );
    if (target == null || !mounted) {
      return;
    }
    _dismissSelection();
    await _showMark(
      page: target.page,
      start: target.textStart,
      end: target.textEnd,
    );
  }

  Future<void> _goToPage(int page) async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.goToPage(page);
    if (_flow == PageFlow.continuous && _viewer.isReady) {
      await _viewer.goToPage(pageNumber: page);
    }
  }

  /// Нажатие по странице: переход к соседнему фрагменту или панели.
  ///
  /// Зоны всегда слева и справа, в любом режиме и в любом положении
  /// экрана. Пробовали привязать их к направлению деления — читатель
  /// каждый раз вспоминал, куда нажимать в этом режиме. Привычка «вправо
  /// значит дальше» сильнее любой логики раскладки.
  ///
  /// **Зоны работают и при выделенном тексте** (главное замечание
  /// владельца по проверке S6): книга не перестаёт быть книгой оттого,
  /// что в ней что-то выделено. Переход снимает выделение вместе с
  /// панелью — текста, к которому оно относилось, на экране больше нет.
  void _onTap(Offset position, Size size, VoidCallback toggleChrome) {
    final ReaderController? controller = _controller;
    if (controller == null || _flow != PageFlow.paged || size.width <= 0) {
      toggleChrome();
      return;
    }
    final ReaderTap action = readerTapAt(
      share: position.dx / size.width,
      selecting: _selection != null,
    );
    switch (action) {
      case ReaderTap.previousFragment:
        _dismissSelection();
        unawaited(controller.previousFragment());
      case ReaderTap.nextFragment:
        _dismissSelection();
        unawaited(controller.nextFragment());
      case ReaderTap.dismissSelection:
        _dismissSelection();
      case ReaderTap.toggleChrome:
        toggleChrome();
    }
  }

  /// Листание клавишами: то же самое, что зонами.
  ///
  /// В ленте фрагментов нет, там шаг — страница, и просмотрщик обязан
  /// доехать до неё сам: иначе номер страницы уехал бы, а лента осталась
  /// на месте.
  void _stepFragment({required bool forward}) {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    _dismissSelection();
    if (_flow == PageFlow.continuous) {
      final int target = controller.page + (forward ? 1 : -1);
      if (target >= 1 && target <= controller.pageCount) {
        unawaited(_goToPage(target));
      }
      return;
    }
    unawaited(
      forward ? controller.nextFragment() : controller.previousFragment(),
    );
  }

  Future<void> _openSettings() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ReaderSettingsSheet(
          controller: controller,
          flow: _flow,
          onFlow: (PageFlow value) => unawaited(_setFlow(value)),
          onDisplayMode: (PageDisplayMode mode) =>
              unawaited(_setDisplayMode(mode)),
          onEditCrop: () {
            Navigator.of(context).pop();
            unawaited(_editCrop());
          },
        );
      },
    );
  }

  Future<void> _editCrop() async {
    final ReaderController? controller = _controller;
    if (controller == null) {
      return;
    }
    final CropBox? box = await Navigator.of(context).push<CropBox>(
      MaterialPageRoute<CropBox>(
        builder: (BuildContext context) => CropEditorScreen(
          document: controller.document,
          pageNumber: controller.page,
          initial: controller.contentBox,
        ),
      ),
    );
    if (box != null) {
      await controller.setManualCrop(box);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('reader-loading')),
        ),
      );
    }
    final DocumentOpenException? failure = _failure;
    if (failure != null) {
      return _FailureScreen(
        failure: failure,
        onPassword: (String password) => unawaited(_open(password: password)),
        onRelink: () => unawaited(_relink()),
      );
    }

    final ReaderController controller = _controller!;
    return ReaderScaffold(
      controller: controller,
      search: _search!,
      onGoToPage: _goToPage,
      onGoToHit: _goToHit,
      onPreviousFragment: () => _stepFragment(forward: false),
      onNextFragment: () => _stepFragment(forward: true),
      onDismiss: _dismissSelection,
      extraActions: <Widget>[
        IconButton(
          key: const Key('reader-annotations-button'),
          icon: const Icon(Icons.format_quote),
          tooltip: 'Цитаты и заметки',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_openAnnotations()),
        ),
        // Деление страницы стоит там, где им пользуются, — на странице, а
        // не в панели настроек: это способ читать, а не настройка.
        DisplayModeButtons(
          mode: controller.settings.displayMode,
          onMode: (PageDisplayMode mode) => unawaited(_setDisplayMode(mode)),
          // Дробь, которая на этой книге не увеличит текст, показана
          // погасшей: обещать увеличение и не дать его — хуже, чем
          // честно сказать заранее.
          gainless: <PageDisplayMode>{
            for (final PageDisplayMode mode in <PageDisplayMode>[
              PageDisplayMode.half,
              PageDisplayMode.third,
            ])
              if (!controller.layoutFor(mode).isWorthwhile) mode,
          },
        ),
        IconButton(
          key: const Key('reader-zoom-lock-button'),
          icon: Icon(_zoomLocked ? Icons.lock_outline : Icons.lock_open),
          tooltip: _zoomLocked
              ? 'Разрешить двигать и масштабировать страницу'
              : 'Запереть масштаб',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_setZoomLocked(!_zoomLocked)),
        ),
        // Поворот есть только там, где он что-то делает. На ПК форму окна
        // выбирает человек, а `setPreferredOrientations` не делает ничего:
        // кнопка-обманка хуже её отсутствия.
        if (_canTurn)
          IconButton(
            key: const Key('reader-rotation-button'),
            icon: Icon(
              _rotation == ScreenOrientation.landscape
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
            ),
            tooltip: _rotation == ScreenOrientation.landscape
                ? 'Читать вертикально'
                : 'Читать горизонтально',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(
              _setRotation(
                _rotation == ScreenOrientation.landscape
                    ? ScreenOrientation.portrait
                    : ScreenOrientation.landscape,
              ),
            ),
          ),
        IconButton(
          key: const Key('reader-settings-button'),
          icon: const Icon(Icons.tune),
          tooltip: 'Рамка и светофильтр',
          visualDensity: VisualDensity.compact,
          onPressed: () => unawaited(_openSettings()),
        ),
      ],
      viewerBuilder: (BuildContext context, VoidCallback onTap) {
        return AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, Widget? child) {
            return ReadingFilterLayer(
              filter: controller.filter,
              // Лента строится один раз и передаётся мимо перестроений:
              // пересоздавать просмотрщик на каждое уведомление значило бы
              // терять место прокрутки под руками у читателя.
              child: child ?? _buildSheet(context, controller, onTap),
            );
          },
          child: _flow == PageFlow.continuous
              ? _buildRibbon(context, controller, onTap)
              : null,
        );
      },
    );
  }

  /// Чтение по страницам: жёсткая раскладка, страница целиком.
  ///
  /// Лист кладётся так, что читаемая часть занимает экран, а остальная
  /// страница гаснет вокруг неё. Масштаб один и тот же на каждой странице
  /// книги — пока замок заперт. Отперев его, читатель двигает и
  /// масштабирует страницу как в обычном просмотрщике, и она остаётся в
  /// том виде, в каком он её оставил.
  ///
  /// Жестов здесь больше нет: страницу рисует просмотрщик, он же ловит
  /// нажатия и разводит выделение с перемещением. Нам он отдаёт готовое —
  /// нажатие мимо выделения и сам выделенный диапазон.
  Widget _buildSheet(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    final Color background = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limits) {
        final Size size = Size(limits.maxWidth, limits.maxHeight);
        // Рисуем тем же документом, который уже открыл контроллер:
        // второе открытие той же книги стоило вдвое больше памяти, а на
        // большой книге отдавало страницы не сразу — и вместо содержимого
        // читатель видел пустой экран.
        final Object? engine = controller.document.engineDocument;
        final PdfDocument? document = engine is PdfDocument ? engine : null;
        final List<int> pages = isSpreadMode(controller.settings.displayMode)
            ? spreadPages(controller.page, controller.pageCount)
            : <int>[controller.page];
        if (document == null) {
          return ColoredBox(color: background, child: const SizedBox.expand());
        }
        return ReaderSheet(
          document: document,
          pages: pages,
          fragment: controller.fragmentBox,
          background: background,
          page: controller.page,
          pageCount: controller.pageCount,
          locked: _zoomLocked,
          stripFit: controller.settings.stripFit,
          dim: controller.settings.dimOutside,
          sheetController: _sheet,
          onSelection: (List<PdfPageTextRange> ranges) =>
              unawaited(_onSelectionRanges(ranges)),
          onTap: (Offset at) => _onTap(at, size, onTap),
          overlay: (BuildContext context, SheetView view) =>
              _buildOverlay(context, view, document, pages, size),
        );
      },
    );
  }

  /// Что лежит поверх листа: подсветка найденного и панель действий.
  ///
  /// И то, и другое живёт в координатах страницы, а рисуется на экране,
  /// поэтому обоим нужен [SheetView] — раскладка листа плюс щипок
  /// читателя. Считать это в самом листе нельзя: он не знает ни про
  /// поиск, ни про промпты.
  Widget _buildOverlay(
    BuildContext context,
    SheetView view,
    PdfDocument document,
    List<int> pages,
    Size size,
  ) {
    final ThemeData theme = Theme.of(context);
    final BookSelection? selection = _selection;
    final _PageMark? mark = _mark;
    final List<Rect> found = mark == null || !pages.contains(mark.pageNumber)
        ? const <Rect>[]
        : _screenRects(view, document, pages, mark.pageNumber, _markRects);
    final List<Rect> selected = selection == null
        ? const <Rect>[]
        : _screenRects(
            view,
            document,
            pages,
            selection.pageNumber,
            selection.rects,
          );
    return Stack(
      children: <Widget>[
        if (found.isNotEmpty)
          Positioned.fill(
            child: HighlightLayer(
              rects: found,
              color: theme.colorScheme.tertiary.withValues(alpha: 0.35),
            ),
          ),
        if (selection != null && selected.isNotEmpty)
          SelectionPanel(
            anchor: selected.reduce((Rect a, Rect b) => a.expandToInclude(b)),
            area: size,
            prompts: _prompts,
            onPrompt: (SelectionPrompt prompt) => unawaited(_onPrompt(prompt)),
            onQuote: () => unawaited(_onQuote()),
            onNote: () => unawaited(_onNote()),
            onCopy: () => unawaited(_onCopy()),
          ),
      ],
    );
  }

  /// Переводит прямоугольники страницы в прямоугольники экрана.
  ///
  /// Страница лежит внутри листа: в развороте вторая страница начинается
  /// там, где кончилась первая. Поэтому смещение считается по ширинам
  /// страниц листа, а не по номеру страницы в книге.
  List<Rect> _screenRects(
    SheetView view,
    PdfDocument document,
    List<int> pages,
    int pageNumber,
    List<TextBox> boxes,
  ) {
    if (boxes.isEmpty) {
      return const <Rect>[];
    }
    double left = 0;
    PdfPage? target;
    for (final int number in pages) {
      if (number < 1 || number > document.pages.length) {
        continue;
      }
      final PdfPage page = document.pages[number - 1];
      if (number == pageNumber) {
        target = page;
        break;
      }
      left += page.width;
    }
    if (target == null) {
      return const <Rect>[];
    }
    final double width = target.width;
    final double height = target.height;
    return <Rect>[
      for (final TextBox box in boxes)
        Rect.fromPoints(
          view.toScreen(left + box.left * width, box.top * height),
          view.toScreen(left + box.right * width, box.bottom * height),
        ),
    ];
  }

  /// Непрерывная лента: свободное чтение с зумом и прокруткой.
  ///
  /// Здесь читатель сам решает, что и как разглядывать, поэтому режимы
  /// отображения в ленте не действуют — это другой способ читать.
  Widget _buildRibbon(
    BuildContext context,
    ReaderController controller,
    VoidCallback onTap,
  ) {
    // Тем же документом, который уже открыл контроллер. Прежде лента
    // открывала книгу по пути во второй раз — но у документа Android
    // пути нет вовсе, а второе открытие большой книги и без того стоило
    // вдвое больше памяти. `autoDispose: false` потому, что закрывает
    // документ контроллер: он его и открыл.
    final Object? engine = controller.document.engineDocument;
    final PdfDocument? document = engine is PdfDocument ? engine : null;
    if (document == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: const SizedBox.expand(),
      );
    }
    return PdfViewer(
      PdfDocumentRefDirect(document, autoDispose: false),
      controller: _viewer,
      initialPageNumber: controller.initialPage,
      params: PdfViewerParams(
        // Фон под страницей — цвет темы, а не белый: белые поля вокруг
        // страницы ночью бьют в глаза сильнее самой страницы.
        backgroundColor: Theme.of(context).colorScheme.surface,
        margin: 6,
        pageDropShadow: null,
        enableKeyboardNavigation: true,
        onPageChanged: (int? page) {
          if (page != null) {
            controller.onPageChanged(page);
          }
        },
        onGeneralTap:
            (
              BuildContext context,
              PdfViewerController viewerController,
              PdfViewerGeneralTapHandlerDetails details,
            ) {
              // Панели переключает только простое нажатие. Двойное — это
              // масштаб, долгое — выделение текста; отбирать их у
              // просмотрщика нельзя.
              if (details.type != PdfViewerGeneralTapType.tap ||
                  details.tapOn == PdfViewerPart.selectedText) {
                return false;
              }
              onTap();
              return true;
            },
      ),
    );
  }
}

/// Кусок текста, подсвеченный на странице.
///
/// Один и тот же для найденного поиском и для открытой из списка цитаты:
/// и то, и другое — ответ на вопрос «где здесь то, что я ищу».
class _PageMark {
  const _PageMark({
    required this.pageNumber,
    required this.start,
    required this.end,
  });

  final int pageNumber;
  final int start;
  final int end;
}

/// Экран «книга не открылась».
///
/// Причина названа своими словами, а не кодом ошибки: человеку надо
/// понять, что делать дальше, а не что сломалось внутри.
class _FailureScreen extends StatefulWidget {
  const _FailureScreen({
    required this.failure,
    required this.onPassword,
    required this.onRelink,
  });

  final DocumentOpenException failure;
  final void Function(String password) onPassword;
  final VoidCallback onRelink;

  @override
  State<_FailureScreen> createState() => _FailureScreenState();
}

class _FailureScreenState extends State<_FailureScreen> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DocumentProblem problem = widget.failure.problem;
    final bool needsPassword =
        problem == DocumentProblem.passwordRequired ||
        problem == DocumentProblem.wrongPassword;
    // Файл потерялся — значит, его можно показать заново. Всё остальное
    // (повреждён, пустой) перевыбором того же файла не лечится.
    final bool canRelink = problem == DocumentProblem.missing;

    return Scaffold(
      appBar: AppBar(title: const Text('Книга не открылась')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(
              needsPassword ? Icons.lock_outline : Icons.report_gmailerrorred,
              size: 56,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text(
              describeDocumentProblem(problem),
              key: const Key('reader-failure-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (needsPassword) ...<Widget>[
              const SizedBox(height: 24),
              TextField(
                key: const Key('reader-password-field'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: widget.onPassword,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('reader-password-submit'),
                onPressed: () => widget.onPassword(_password.text),
                child: const Text('Открыть'),
              ),
            ],
            if (canRelink) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('reader-relink'),
                onPressed: widget.onRelink,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Выбрать файл заново'),
              ),
              const SizedBox(height: 12),
              Text(
                'Место чтения, цитаты и заметки останутся на месте: они '
                'принадлежат книге, а не файлу.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
