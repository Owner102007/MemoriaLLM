import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/source_release.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/drag_scroll.dart';
import '../../domain/library/shelf.dart';
import '../../domain/library/shelf_title_search.dart';
import '../../domain/navigation/sections.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import '../../sno/recording/action_log.dart';
import '../../sno/recording/event.dart';
import '../../sno/recording/thinning.dart';
import '../reader/reader_screen.dart';
import 'book_drag.dart';
import 'category_shelf.dart';
import 'device_books_screen.dart';
import 'library_dialogs.dart';
import 'shelf_search.dart';

/// Полка книг.
///
/// Полка состоит из категорий: у каждой свой узор и цвет подложки,
/// выведенные из названия, и своя сетка блоков — книга занимает блок,
/// последним блоком стоит кнопка «+». Раздел «Без категории» стоит
/// первым и никогда не удаляется: он не строка в базе, а просто книги,
/// которые никуда не разложили.
class LibraryScreen extends StatefulWidget {
  /// Создаёт экран.
  const LibraryScreen({
    required this.services,
    this.onAddBooks,
    this.onReading,
    this.canAddBooks = true,
    this.defaultSort = ShelfSort.recent,
    this.titleSearch = false,
    this.locked = false,
    this.models = true,
    this.visible = true,
    super.key,
  });

  /// Службы приложения.
  final AppServices services;

  /// На экране ли полка: открыт её раздел, и книга не читается.
  ///
  /// Нужно журналу записи сборок ветвей СНО2026 (SNO-F-REC-02): когда
  /// полка снова перед участником, в журнал ложится `shelf.shown`.
  final bool visible;

  /// Просьба показать книги устройства, чтобы добавить их на полку
  /// (F-APP-02). Аргумент — категория, чей «+» нажали; `null` — кнопка в
  /// шапке или на пустой полке.
  ///
  /// Оболочка этим переключает раздел. Без обработчика полка открывает
  /// экран книг устройства поверх себя, как делала до разделов: так она
  /// живёт в тестах и там, где оболочки нет.
  final ValueChanged<String?>? onAddBooks;

  /// Читатель открыл книгу (`true`) или закрыл её (`false`).
  ///
  /// Оболочка передаёт это разделу «Устройство»: пока книгу читают,
  /// обход и разборка стоят — движок и диск отданы странице.
  final ValueChanged<bool>? onReading;

  /// Можно ли добавлять книги с полки.
  ///
  /// В сборках ветвей СНО2026 — нет (SNO-F-CFG-02): раздела «Устройство»
  /// там не существует, и полка на него не ведёт. Кнопки в шапке и «+»
  /// в категориях нет, а пустая полка говорит, откуда берутся книги, —
  /// их добавляет экспериментатор в разделе «Тестирование».
  final bool canAddBooks;

  /// Порядок книг, пока читатель не выбрал свой.
  ///
  /// В сборках ветвей СНО2026 это «Как расставил» (SNO-F-CFG-04): книги
  /// стоят так, как их положил архив с литературой, — по порядку имён.
  /// В порядке «Сначала недавние» полка тестировщика вставала бы в
  /// порядке, обратном архиву, и менялась после каждой открытой книги,
  /// а эталонное состояние — это одна и та же полка у всех.
  final ShelfSort defaultSort;

  /// Есть ли на полке поиск по названию (SNO-F-LIB-01).
  ///
  /// В сборках ветвей СНО2026 — есть: значок в шапке на телефоне, поле в
  /// шапке на широком окне. С первой буквы полка сменяется списком книг,
  /// в названии которых есть набранное. В основном приложении поиска по
  /// полке нет: там это пока идея, а не функция.
  final bool titleSearch;

  /// Закреплена ли полка (SNO-F-LIB-02).
  ///
  /// Пока идёт запись сессии, расположение книг обязано стоять на месте:
  /// его участник запоминает, и оно одно у всех участников. Под замком
  /// нет ничего, что его меняет, — смены порядка, переноса книги, меню
  /// книги со снятием с полки, новой категории, переименования и
  /// удаления категорий. Пункты спрятаны, а не показаны серыми. Открыть
  /// книгу и найти её по названию можно всегда.
  final bool locked;

  /// Есть ли в сборке модель: промпты над выделенным текстом.
  ///
  /// В сборках ветвей СНО2026 — нет (SNO-F-READ-01): экран чтения
  /// показывает над выделением четыре действия без промптов.
  final bool models;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  /// Сколько секунд сообщение «убрана с полки» предлагает вернуть книгу.
  ///
  /// Снятие с полки необратимо для источника: своя копия удаляется, а
  /// закреплённая ссылка освобождается. Промах по кнопке стоил бы
  /// повторного выбора файла, поэтому источник отпускается не раньше,
  /// чем с экрана ушло «Вернуть» ([_removeBook]).
  static const Duration _undoWindow = Duration(seconds: 5);

  /// Как часто полка сдвигается, пока книгу держат у края.
  ///
  /// Шаг считается **из скорости и прошедшего времени**, а не задаётся
  /// в точках за тик: сама скорость живёт в `domain/library/drag_scroll.dart`
  /// и проверяется там же, а здесь остаётся только перевод в пиксели.
  static const Duration _autoScrollTick = Duration(milliseconds: 16);

  late ShelfSort _sort = widget.defaultSort;

  /// Снятые книги, которые ещё можно вернуть: их «Вернуть» стоит на
  /// экране или ждёт своей очереди. Источник такой книги не отпущен.
  final Map<String, Book> _removed = <String, Book>{};
  final ScrollController _shelf = ScrollController();

  /// Ключ на сам список категорий.
  ///
  /// Зона самопрокрутки отсчитывается от **полки**, а не от экрана:
  /// сверху стоит панель приложения, и зона, отсчитанная от экрана,
  /// уходила бы под неё.
  final GlobalKey _shelfViewport = GlobalKey();

  Timer? _autoScroll;
  double _scrollSpeed = 0;
  DragScrollGate _gate = DragScrollGate();

  /// Поиск по названию (SNO-F-LIB-01): набранное и поле.
  ///
  /// [_searching] — открыто ли поле на узком экране; на широком окне оно
  /// стоит в шапке всегда. Список обновляется с каждой буквой: названия
  /// лежат в памяти, и ждать тут нечего.
  final TextEditingController _searchField = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'shelf-search');
  bool _searching = false;
  String _query = '';

  /// Занят ли экран поиском: тогда «назад» закрывает его, а не раздел.
  bool get _searchActive => _searching || _query.isNotEmpty;

  /// Журнал действий участника; `null` — в этой сборке записи нет
  /// (SNO-F-REC-02).
  ActionLog? get _log => widget.services.recording;

  /// Сколько запрос обязан простоять без изменений, чтобы журнал счёл
  /// его запросом: иначе каждая буква стала бы отдельным событием.
  static const Duration _queryRest = Duration(milliseconds: 150);

  /// Срок, который набранный запрос обязан простоять.
  Timer? _queryTimer;

  /// Полка, какой её построили в последний раз: по ней журнал пишет,
  /// что показано и сколько нашлось.
  List<ShelfSection> _shown = const <ShelfSection>[];

  /// Прокрутка полки для журнала — прореженно (SNO-ALG-REC-01).
  late final Thinned<double> _scrolled = Thinned<double>(_logScroll);

  void _logScroll(double offset) {
    final ActionLog? log = _log;
    if (log == null || !log.recording || !_shelf.hasClients) {
      return;
    }
    final ScrollPosition position = _shelf.position;
    log.log(
      SnoEventType.shelfScroll,
      data: <String, Object?>{
        'offset': offset.round(),
        'max': position.maxScrollExtent.round(),
        'viewport': position.viewportDimension.round(),
      },
    );
  }

  /// Полка снова перед участником: что на ней и где она стоит.
  void _logShown() {
    final ActionLog? log = _log;
    if (!mounted || log == null || !log.recording) {
      return;
    }
    int books = 0;
    for (final ShelfSection section in _shown) {
      books += section.books.length;
    }
    log.log(
      SnoEventType.shelfShown,
      data: <String, Object?>{
        'sort': (widget.locked ? ShelfSort.manual : _sort).name,
        'locked': widget.locked,
        'books': books,
        'categories': <Object?>[
          for (final ShelfSection section in _shown)
            <String, Object?>{
              'title': section.title,
              'books': section.books.length,
            },
        ],
        if (_shelf.hasClients) 'offset': _shelf.position.pixels.round(),
      },
    );
  }

  /// Книги полки в том порядке, в каком они стоят.
  List<Book> get _shownBooks {
    return <Book>[for (final ShelfSection section in _shown) ...section.books];
  }

  /// Запрос простоял свой срок — он пишется в журнал с числом найденного.
  void _logQuery() {
    _queryTimer = null;
    final ActionLog? log = _log;
    final String query = _query.trim();
    if (!mounted || log == null || !log.recording || query.isEmpty) {
      return;
    }
    log.log(
      SnoEventType.searchQuery,
      data: <String, Object?>{
        'scope': 'shelf',
        ...journalText(query),
        'hits': searchShelfTitles(query: query, books: _shownBooks).length,
      },
    );
  }

  /// Потоки полки: категории, книги, места чтения.
  ///
  /// Заводятся один раз, а не в каждом построении: поиск по названию
  /// перестраивает экран с каждой буквой, и подписываться на базу заново
  /// на каждую букву незачем.
  late Stream<List<BookCategory>> _categoryStream;
  late Stream<List<Book>> _bookStream;
  late Stream<Map<String, ReadingPosition>> _positionStream;

  void _watchShelf() {
    _categoryStream = widget.services.data.categories.watchCategories();
    _bookStream = widget.services.data.library.watchBooks();
    _positionStream = widget.services.data.reading.watchPositions();
  }

  @override
  void initState() {
    super.initState();
    _watchShelf();
    unawaited(_restoreSort());
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.services, widget.services)) {
      _watchShelf();
    }
    if (widget.visible && !oldWidget.visible) {
      // После кадра: полка под замком могла смениться в этом же
      // построении, и писать надо ту, что участник увидит.
      WidgetsBinding.instance.addPostFrameCallback((_) => _logShown());
    }
  }

  @override
  void dispose() {
    _queryTimer?.cancel();
    _scrolled.dispose();
    _removed.clear();
    _autoScroll?.cancel();
    _shelf.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Открывает поле поиска и ставит в него указатель ввода.
  void _openSearch() {
    setState(() => _searching = true);
    // Поле в этом кадре ещё не стоит на экране — указатель после кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) {
        _searchFocus.requestFocus();
      }
    });
  }

  /// Закрывает поиск: набранное стирается, на экране снова полка.
  void _closeSearch() {
    // Указатель ввода уходит из поля и тогда, когда закрывать нечего: на
    // широком окне поле стоит всегда и могло быть просто нажато.
    _searchFocus.unfocus();
    if (!_searchActive && _searchField.text.isEmpty) {
      return;
    }
    _queryTimer?.cancel();
    _queryTimer = null;
    _log?.log(
      SnoEventType.searchClose,
      data: const <String, Object?>{'scope': 'shelf'},
    );
    _searchField.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  /// Открывает книгу, найденную по названию (SNO-F-LIB-01).
  ///
  /// Свой путь, отдельный от нажатия на полке: журнал записи отличает
  /// «нашёл поиском» от «открыл по памяти» (SNO-F-REC-02) — здесь
  /// пишется, какой по счёту из найденного открыт, а книга открывается
  /// с пометкой пути. Поиск закрывает само открытие книги
  /// ([_openBook]).
  Future<void> _openFound(Book book) {
    final ActionLog? log = _log;
    if (log != null && log.recording) {
      final List<ShelfTitleHit> hits = searchShelfTitles(
        query: _query,
        books: _shownBooks,
      );
      final int at = hits.indexWhere(
        (ShelfTitleHit hit) => hit.book.id == book.id,
      );
      log.log(
        SnoEventType.searchResultOpen,
        data: <String, Object?>{
          'scope': 'shelf',
          ...journalText(_query.trim()),
          'rank': at + 1,
          'of': hits.length,
          'book': book.fileHash,
        },
      );
    }
    return _openBook(book, via: 'shelf_search');
  }

  /// Книгу подняли: полка готовится ехать под пальцем.
  void _dragStarted() {
    _scrollSpeed = 0;
    // Предохранитель заводится заново на каждое поднятие книги: книга,
    // взятая из верхнего ряда, не имеет права увезти полку сама собой.
    _gate = DragScrollGate();
    _autoScroll?.cancel();
    // Один таймер на всё перетаскивание, а не по таймеру на движение:
    // книгу ведут десятками событий в секунду, и заводить на каждое своё
    // ожидание значило бы дёргать полку рывками.
    _autoScroll = Timer.periodic(_autoScrollTick, (Timer _) {
      if (_scrollSpeed == 0 || !_shelf.hasClients) {
        return;
      }
      final ScrollPosition position = _shelf.position;
      final double step =
          _scrollSpeed * _autoScrollTick.inMicroseconds / 1000000;
      final double next = (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) {
        position.jumpTo(next);
      }
    });
  }

  /// Книгу отпустили — где угодно, в том числе мимо полки.
  void _dragEnded() {
    _scrollSpeed = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  /// Книгу ведут над полкой: у её краёв список едет сам.
  ///
  /// Без этого книгу нельзя перенести в категорию, которой не видно, —
  /// а на полке из десятка категорий это обычный случай. Зон две:
  /// у самого края полка едет быстро, чуть дальше от него — медленно.
  /// Вся арифметика — в [DragScrollGate], и одна и та же на телефоне и
  /// на ПК: мышь колесом полку прокрутит, но вести книгу и крутить колесо
  /// одновременно — не то, чего стоит требовать от читателя.
  ///
  /// Мерить надо от **списка**, а не от экрана. Прежде здесь стоял
  /// `context.findRenderObject()`, то есть коробка всего экрана вместе с
  /// панелью приложения: зона в 22 % высоты начиналась выше самой полки,
  /// и быстрая её половина целиком пряталась под панелью — вверх полка
  /// умела ехать только медленно, а книга, поднятая из верхнего ряда,
  /// сразу оказывалась в зоне и уезжала вместе с полкой.
  void _dragOver(Offset globalPosition) {
    final RenderObject? object = _shelfViewport.currentContext
        ?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return;
    }
    _scrollSpeed = _gate.speedAt(
      y: object.globalToLocal(globalPosition).dy,
      height: object.size.height,
    );
  }

  Future<void> _restoreSort() async {
    final String? stored = await widget.services.data.settings.read(
      SettingsKeys.shelfSort,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sort = shelfSortFromName(stored, fallback: widget.defaultSort);
    });
  }

  Future<void> _chooseSort(ShelfSort sort) async {
    // SNO-F-LIB-02: под замком порядок полки не меняется ничем.
    if (widget.locked) {
      return;
    }
    setState(() => _sort = sort);
    await widget.services.data.settings.write(
      SettingsKeys.shelfSort,
      sort.name,
    );
  }

  /// Открывает книги, лежащие на устройстве.
  ///
  /// С S5.5 «+» ведёт сюда, а не в системный диалог. Разница в том, кто
  /// ищет книгу: прежде — читатель, вспоминая, в какой папке она лежит;
  /// теперь — приложение, показывая всё, что нашлось, с обложками и
  /// поиском. Системный диалог никуда не делся и стоит на том же экране
  /// кнопкой в шапке: разрешения может не быть, а книгу добавить надо.
  ///
  /// С шага 10 книги устройства — раздел главной навигации (F-APP-02):
  /// полка просит оболочку переключиться на него и называет категорию.
  Future<void> _addBooks(String? categoryId) async {
    final ValueChanged<String?>? onAddBooks = widget.onAddBooks;
    if (onAddBooks != null) {
      onAddBooks(categoryId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DeviceBooksScreen(
          services: widget.services,
          categoryId: categoryId,
        ),
      ),
    );
  }

  /// Убирает книгу с полки — с возможностью вернуть.
  ///
  /// Строка в базе получает надгробие сразу: книга обязана исчезнуть с
  /// полки в тот же миг, иначе непонятно, сработало ли нажатие. А вот
  /// источник — своя копия и закреплённая ссылка — отпускается только
  /// после того, как окно отмены закрылось: вернуть их назад нельзя.
  ///
  /// BUG-47: окно отмены — это само сообщение. Срок ему задан явно:
  /// сообщение с кнопкой действия Flutter по умолчанию держит на экране,
  /// пока его не закроют (`persist`), и «Вернуть» висело без конца — в
  /// том числе поверх книги, открытой следом. Источник отпускается
  /// тогда, когда сообщение ушло, а не своим таймером: иначе «Вернуть»
  /// оставалось бы на экране дольше, чем книгу можно вернуть с файлом.
  Future<void> _removeBook(Book book) async {
    if (widget.locked) {
      return;
    }
    await widget.services.data.library.delete(book.id);
    if (!mounted) {
      return;
    }
    _removed[book.id] = book;
    final SnackBar bar = SnackBar(
      content: Text('«${book.title}» убрана с полки'),
      duration: _undoWindow,
      persist: false,
      action: SnackBarAction(
        label: 'Вернуть',
        onPressed: () => unawaited(_restoreBook(book)),
      ),
    );
    final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown =
        ScaffoldMessenger.of(context).showSnackBar(bar);
    unawaited(
      shown.closed.then<void>((SnackBarClosedReason reason) async {
        if (reason != SnackBarClosedReason.action) {
          await _releaseRemoved(book);
        }
      }),
    );
  }

  /// Отпускает источник снятой книги: вернуть её больше нельзя.
  ///
  /// Зовётся и тогда, когда сообщение ушло само, и тогда, когда его
  /// убрали ([_dismissMessages]); отпускает один раз.
  Future<void> _releaseRemoved(Book book) async {
    if (!mounted || _removed.remove(book.id) == null) {
      return;
    }
    await _releaseBook(book);
  }

  /// Убирает с экрана сообщения полки — сразу и все (BUG-47).
  ///
  /// Сообщения показывает общий на всё приложение `ScaffoldMessenger`,
  /// поэтому они остаются и поверх экрана, открытого с полки. Страница
  /// не должна быть закрыта ничем (правило 7): книгу открывают — и
  /// сообщение уходит без затухания, вместе с теми, что ждали очереди.
  /// Вернуть снятые книги после этого нечем, и их источники отпускаются.
  void _dismissMessages() {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    for (final Book book in _removed.values.toList()) {
      unawaited(_releaseRemoved(book));
    }
  }

  Future<void> _releaseBook(Book book) async {
    await widget.services.covers.forget(book);
    // BUG-45: источник отпускается, только если он больше ничей — у
    // двух книг мог быть один файл, и вторая стоит на полке.
    await releaseUnusedSource(
      storage: widget.services.storage,
      library: widget.services.data.library,
      source: book.source,
    );
  }

  Future<void> _restoreBook(Book book) async {
    _removed.remove(book.id);
    final LibraryRepository library = widget.services.data.library;
    // Книга уже на полке — её успели добавить снова (BUG-30). Снимок,
    // сделанный при снятии, новее строки не станет: затирать её нечем.
    if (await library.bookById(book.id) != null) {
      return;
    }
    await library.save(book);
  }

  Future<void> _moveBook(
    Book book,
    List<BookCategory> categories,
    List<ShelfSection> sections,
  ) async {
    if (widget.locked) {
      return;
    }
    final MoveTarget? target = await askWhereToMove(
      context,
      categories: categories,
      current: book.categoryId,
    );
    if (target == null || !mounted || widget.locked) {
      return;
    }
    String? destination = target.categoryId;
    if (target.isNew) {
      await _afterFrame();
      if (!mounted) {
        return;
      }
      final BookCategory? created = await _createCategory(categories.length);
      if (created == null) {
        return;
      }
      destination = created.id;
    }
    // Через меню книга встаёт в конец выбранной категории: места
    // назначения читатель не выбирал, а совать её в середину чужого
    // порядка — значит решать за него.
    await _place(
      target: _booksOf(sections, destination),
      moved: book,
      before: null,
      categoryId: destination,
    );
  }

  /// Книга легла в участок [into] перед книгой [before]; `null` — в конец.
  Future<void> _dropBook(
    DraggedBook dragged,
    ShelfSection into,
    Book? before,
  ) async {
    await _place(
      target: into.books,
      moved: dragged.book,
      before: before,
      categoryId: into.category?.id,
    );
  }

  /// Записывает расстановку и, если надо, переводит полку в ручной порядок.
  Future<void> _place({
    required List<Book> target,
    required Book moved,
    required Book? before,
    required String? categoryId,
  }) async {
    // SNO-F-LIB-02: под замком книга остаётся там, где стоит. Поднять её
    // и так нечем: эта проверка и такие же в снятии с полки, переносе
    // через меню и правке категорий — на случай, если замок закрылся,
    // пока меню было открыто или книгу уже несли.
    if (widget.locked) {
      return;
    }
    final List<BookPlacement> placements = placeBefore(
      target: target,
      moved: moved,
      before: before,
      categoryId: categoryId,
    );
    if (placementChangesNothing(target, placements)) {
      return;
    }
    // Книга, ушедшая в другую категорию, оставляет в прежней дыру в
    // нумерации — 0, 1, 3. Заделывать её незачем: порядок задают не сами
    // числа, а то, как они идут, и от дыры он не меняется.
    await widget.services.data.library.placeBooks(placements);
    if (!mounted || _sort == ShelfSort.manual) {
      return;
    }
    // Перетаскивание при включённой сортировке было бы обманом: книга
    // вернулась бы на место в тот же миг. Поэтому первый же перенос
    // переводит полку в ручной порядок — и говорит об этом.
    await _chooseSort(ShelfSort.manual);
    if (mounted) {
      _say('Порядок теперь ручной — книги стоят так, как вы их расставили');
    }
  }

  /// Книги категории в том порядке, в каком их видит читатель.
  List<Book> _booksOf(List<ShelfSection> sections, String? categoryId) {
    for (final ShelfSection section in sections) {
      final String? id = section.category?.id;
      if (id == categoryId) {
        return section.books;
      }
    }
    // Категория есть, но пуста и на полке её сейчас нет — например,
    // «Без категории», из которой всё разложили.
    return const <Book>[];
  }

  Future<BookCategory?> _createCategory(int position) async {
    if (widget.locked) {
      return null;
    }
    final String? name = await askCategoryName(context);
    if (name == null || !mounted || widget.locked) {
      return null;
    }
    final BookCategory category = BookCategory(
      id: newCategoryId(),
      title: normalizeCategoryTitle(name),
      position: position,
      createdAt: DateTime.now(),
    );
    await widget.services.data.categories.save(category);
    return category;
  }

  Future<void> _renameCategory(BookCategory category) async {
    // Меню категории в этот момент ещё уходит с экрана — см. [_afterFrame].
    await _afterFrame();
    if (!mounted || widget.locked) {
      return;
    }
    final String? name = await askCategoryName(
      context,
      initial: category.title,
    );
    if (name == null || !mounted || widget.locked) {
      return;
    }
    await widget.services.data.categories.save(
      category.copyWith(title: normalizeCategoryTitle(name)),
    );
  }

  Future<void> _deleteCategory(BookCategory category) async {
    await _afterFrame();
    if (!mounted || widget.locked) {
      return;
    }
    final bool confirmed = await confirmCategoryRemoval(context, category);
    if (!confirmed || !mounted || widget.locked) {
      return;
    }
    await widget.services.data.categories.delete(category.id);
    if (mounted) {
      _say('Категория убрана, книги остались на полке');
    }
  }

  /// Открывает книгу в чтении.
  ///
  /// BUG-09: открытие здесь не засчитывается. Его считает экран чтения —
  /// один раз и только когда книга действительно открылась. Прежде оно
  /// записывалось и тут, до открытия: одно открытие считалось дважды, а
  /// книга с потерянным файлом поднималась в «Сначала недавние».
  ///
  /// [via] — каким путём книгу открыли: с полки или из найденного по
  /// названию; это пишет журнал записи (SNO-F-REC-02).
  Future<void> _openBook(Book book, {String via = 'shelf'}) async {
    // SNO-F-LIB-01: открытая книга закрывает поиск по названию.
    // Вернувшись, читатель видит полку, а не список найденного и не
    // поле с клавиатурой: каждое обращение к поиску — отдельное действие.
    _closeSearch();
    // BUG-47: сообщение полки не ложится на страницу и на ползунок.
    _dismissMessages();
    widget.onReading?.call(true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ReaderScreen(
            book: book,
            services: widget.services,
            // BUG-46: где книги с полки не добавляют, там и файл книги
            // заново не выбирают — в сборке ветви книги приходят только
            // архивом с литературой.
            canRelink: widget.canAddBooks,
            // SNO-F-READ-01: без модели над выделением нет промптов.
            models: widget.models,
            // SNO-F-REC-02: журнал записи пишет, каким путём открыли.
            openedVia: via,
          ),
        ),
      );
    } finally {
      // SNO-F-REC-02: закрытие книги — раньше перехода на полку.
      _log?.bookClosed();
      widget.onReading?.call(false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Палец, ведущий книгу, слушается здесь, а не в блоках полки.
    // События указателя после нажатия идут по тому пути, который был
    // определён в момент нажатия, поэтому этот слушатель получает их все —
    // и над блоком, и над заголовком категории, и над пустотой под
    // последней категорией, и над панелью приложения. Прежде положение
    // пальца приходило из `DragTarget.onMove` самих блоков, а между
    // блоками таких целей нет вовсе: стоило пальцу замереть в промежутке,
    // и полка продолжала ехать с той скоростью, которая была в последний
    // раз, — то есть не останавливалась там, где читатель её остановил.
    return Listener(
      onPointerMove: (PointerMoveEvent event) {
        if (_autoScroll != null) {
          _dragOver(event.position);
        }
      },
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    // Широкое окно — то же, где навигация стоит наверху: поле поиска
    // там в шапке всегда, а найденное ложится списком под ним.
    final bool wide =
        widget.titleSearch &&
        navPlacementFor(MediaQuery.sizeOf(context).width) == NavPlacement.top;
    // Запрос остался от широкого окна, которое сузили: на узком экране
    // поле держится своим признаком — иначе оно закрылось бы само, стоило
    // стереть последнюю букву.
    if (widget.titleSearch && !wide && _query.isNotEmpty) {
      _searching = true;
    }
    // И наоборот: на широком окне поле стоит всегда, открывать его
    // нечем — признак не должен пережить узкий экран и держать «назад».
    if (wide) {
      _searching = false;
    }
    return PopScope<Object?>(
      // «Назад» при открытом поиске закрывает поиск, а не раздел.
      canPop: !_searchActive,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _log?.log(
            SnoEventType.navBack,
            data: const <String, Object?>{'closes': 'shelf_search'},
          );
          _closeSearch();
        }
      },
      child: Scaffold(
        appBar: _bar(wide: wide),
        body: StreamBuilder<List<BookCategory>>(
          stream: _categoryStream,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<BookCategory>> categories,
              ) {
                return StreamBuilder<List<Book>>(
                  stream: _bookStream,
                  builder:
                      (BuildContext context, AsyncSnapshot<List<Book>> books) {
                        return StreamBuilder<Map<String, ReadingPosition>>(
                          stream: _positionStream,
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<Map<String, ReadingPosition>>
                                positions,
                              ) {
                                return _buildShelf(
                                  categories:
                                      categories.data ?? const <BookCategory>[],
                                  books: books.data ?? const <Book>[],
                                  positions:
                                      positions.data ??
                                      const <String, ReadingPosition>{},
                                  wide: wide,
                                );
                              },
                        );
                      },
                );
              },
        ),
      ),
    );
  }

  /// Шапка полки.
  ///
  /// SNO-F-LIB-01: на узком экране значок поиска открывает поле на месте
  /// заголовка; на широком окне поле стоит в шапке всегда. SNO-F-LIB-02:
  /// под замком в шапке остаётся только поиск.
  PreferredSizeWidget _bar({required bool wide}) {
    if (widget.titleSearch && !wide && _searching) {
      return AppBar(
        leading: IconButton(
          key: const Key('shelf-search-back'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Закрыть поиск',
          onPressed: _closeSearch,
        ),
        titleSpacing: 0,
        title: ShelfSearchField(
          controller: _searchField,
          focusNode: _searchFocus,
          onChanged: _onQuery,
          onClose: _closeSearch,
        ),
      );
    }
    return AppBar(
      automaticallyImplyLeading: !wide,
      centerTitle: wide ? false : null,
      // Отступ назван числом: по нему же список найденного встаёт под
      // полем на широком окне.
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      title: wide
          ? Row(
              children: <Widget>[
                const SizedBox(
                  width: kShelfTitleWidth,
                  child: Text(
                    'Полка',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kShelfSearchWidth,
                    ),
                    child: ShelfSearchField(
                      controller: _searchField,
                      focusNode: _searchFocus,
                      onChanged: _onQuery,
                      onClose: _closeSearch,
                      framed: true,
                      showClose: _query.isNotEmpty,
                    ),
                  ),
                ),
              ],
            )
          : const Text('Полка'),
      actions: <Widget>[
        if (widget.titleSearch && !wide)
          IconButton(
            key: const Key('library-search'),
            icon: const Icon(Icons.search),
            tooltip: 'Поиск по названию',
            onPressed: _openSearch,
          ),
        if (!widget.locked)
          PopupMenuButton<ShelfSort>(
            key: const Key('library-sort'),
            icon: const Icon(Icons.sort),
            tooltip: 'Порядок книг',
            initialValue: _sort,
            onSelected: (ShelfSort sort) => unawaited(_chooseSort(sort)),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<ShelfSort>>[
              for (final ShelfSort sort in ShelfSort.values)
                PopupMenuItem<ShelfSort>(
                  value: sort,
                  child: Text(shelfSortTitle(sort)),
                ),
            ],
          ),
        if (!widget.locked)
          IconButton(
            key: const Key('library-new-category'),
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Новая категория',
            onPressed: () => unawaited(_newCategoryFromBar()),
          ),
        if (widget.canAddBooks && !widget.locked)
          IconButton(
            key: const Key('library-open-file'),
            icon: const Icon(Icons.library_add_outlined),
            tooltip: 'Книги на устройстве',
            onPressed: () => unawaited(_addBooks(null)),
          ),
      ],
    );
  }

  void _onQuery(String value) {
    setState(() => _query = value);
    // SNO-F-REC-02: запросом журнал считает набранное, простоявшее
    // свой срок; список найденного при этом обновляется с каждой буквой.
    _queryTimer?.cancel();
    final ActionLog? log = _log;
    _queryTimer = log != null && log.recording
        ? Timer(_queryRest, _logQuery)
        : null;
  }

  Future<void> _newCategoryFromBar() async {
    final List<BookCategory> existing = await widget.services.data.categories
        .categories();
    if (!mounted) {
      return;
    }
    await _createCategory(existing.length);
  }

  Widget _buildShelf({
    required List<BookCategory> categories,
    required List<Book> books,
    required Map<String, ReadingPosition> positions,
    required bool wide,
  }) {
    final Map<String, double> progress = <String, double>{
      for (final MapEntry<String, ReadingPosition> entry in positions.entries)
        entry.key: entry.value.progress,
    };
    final bool empty = books.isEmpty && categories.isEmpty;
    final List<ShelfSection> sections = empty
        ? const <ShelfSection>[]
        : buildShelf(
            categories: categories,
            books: books,
            // SNO-F-LIB-02: под замком полка стоит в порядке «Как
            // расставил», какой бы порядок ни был выбран. «Сначала
            // недавние» переставлял бы книги после каждой открытой.
            sort: widget.locked ? ShelfSort.manual : _sort,
            progress: progress,
          );
    _shown = sections;
    final Widget shelf;
    if (empty) {
      shelf = widget.canAddBooks
          ? _EmptyShelf(onOpen: () => unawaited(_addBooks(null)))
          : const _EmptyBranchShelf();
    } else {
      // `KeyedSubtree` не рисует ничего сам, поэтому его коробка — это
      // коробка списка. Так у полки появляется ключ, не отнимая у неё
      // прежний, по которому её находят тесты.
      shelf = KeyedSubtree(
        key: _shelfViewport,
        child: _shelfList(
          sections: sections,
          categories: categories,
          progress: progress,
        ),
      );
    }
    if (!widget.titleSearch) {
      return shelf;
    }
    // SNO-F-LIB-01: пока в поле пусто, на экране полка как есть.
    final bool searching = _query.trim().isNotEmpty;
    final Widget found = searching
        ? ShelfSearchResults(
            // Книги — в порядке полки: при равном весе находки стоят
            // так же, как стоят на ней.
            hits: searchShelfTitles(
              query: _query,
              books: <Book>[
                for (final ShelfSection section in sections) ...section.books,
              ],
            ),
            categories: <String, String>{
              for (final ShelfSection section in sections)
                for (final Book book in section.books) book.id: section.title,
            },
            covers: widget.services.covers,
            onOpen: (Book book) => unawaited(_openFound(book)),
            shrinkWrap: wide,
          )
        : const SizedBox.shrink();
    if (!wide) {
      // Телефон: полка сменяется списком, но из дерева не уходит — и
      // после поиска стоит там же, где её оставили. Расположение книг
      // участник запоминает; полка, прыгнувшая в начало, сбивала бы его.
      return IndexedStack(
        index: searching ? 1 : 0,
        sizing: StackFit.expand,
        children: <Widget>[shelf, found],
      );
    }
    // Широкое окно: список — под полем, полка под ним видна затемнённой.
    // Нажатие мимо списка закрывает поиск.
    final ThemeData theme = Theme.of(context);
    return Stack(
      children: <Widget>[
        shelf,
        if (searching)
          Positioned.fill(
            child: GestureDetector(
              key: const Key('shelf-search-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _closeSearch,
              child: ColoredBox(
                color: theme.colorScheme.scrim.withValues(alpha: 0.6),
              ),
            ),
          ),
        if (searching)
          Positioned(
            // Левый край поля в шапке: отступ заголовка и место под
            // слово «Полка».
            left: NavigationToolbar.kMiddleSpacing + kShelfTitleWidth,
            top: 0,
            bottom: 16,
            width: kShelfSearchWidth,
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: theme.colorScheme.surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: found,
              ),
            ),
          ),
      ],
    );
  }

  Widget _shelfList({
    required List<ShelfSection> sections,
    required List<BookCategory> categories,
    required Map<String, double> progress,
  }) {
    final Widget list = _shelfItems(
      sections: sections,
      categories: categories,
      progress: progress,
    );
    if (_log == null) {
      return list;
    }
    // SNO-F-REC-02: прокрутка полки — в журнал, прореженно; чем жест
    // кончился, пишется обязательно. Слушатель только смотрит.
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.depth != 0) {
          return false;
        }
        if (notification is ScrollUpdateNotification) {
          _scrolled.add(notification.metrics.pixels);
        } else if (notification is ScrollEndNotification) {
          _scrolled.flush();
        }
        return false;
      },
      child: list,
    );
  }

  Widget _shelfItems({
    required List<ShelfSection> sections,
    required List<BookCategory> categories,
    required Map<String, double> progress,
  }) {
    return ListView.builder(
      key: const Key('library-shelf'),
      controller: _shelf,
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: sections.length,
      itemBuilder: (BuildContext context, int index) {
        final ShelfSection section = sections[index];
        final BookCategory? category = section.category;
        return CategoryShelf(
          section: section,
          covers: widget.services.covers,
          progress: progress,
          // Импорт больше не идёт на этом экране: «+» открывает экран
          // книг устройства, и ждать здесь нечего.
          busy: false,
          onOpen: (Book book) => unawaited(_openBook(book)),
          // SNO-F-LIB-02: под замком нет ни меню книги, ни «+», ни меню
          // категории, и книгу не поднять.
          onMenu: widget.locked
              ? null
              : (Book book) =>
                    unawaited(_showBookMenu(book, categories, sections)),
          onAdd: widget.canAddBooks && !widget.locked
              ? () => unawaited(_addBooks(category?.id))
              : null,
          movable: !widget.locked,
          onDropBook: (DraggedBook dragged, ShelfSection into, Book? before) =>
              unawaited(_dropBook(dragged, into, before)),
          onDragStarted: _dragStarted,
          onDragEnded: _dragEnded,
          onRename: category == null || widget.locked
              ? null
              : () => unawaited(_renameCategory(category)),
          onDelete: category == null || widget.locked
              ? null
              : () => unawaited(_deleteCategory(category)),
        );
      },
    );
  }

  /// Ждёт, пока закроется то, что закрывается.
  ///
  /// Открывать диалог в тот же миг, когда предыдущая шторка ещё уходит с
  /// экрана, нельзя: две области фокуса накладываются, и Flutter роняет
  /// сборку кадра. Один кадр ожидания стоит меньше, чем сломанное дерево
  /// виджетов.
  Future<void> _afterFrame() => WidgetsBinding.instance.endOfFrame;

  Future<void> _showBookMenu(
    Book book,
    List<BookCategory> categories,
    List<ShelfSection> sections,
  ) async {
    final BookAction? action = await askBookAction(context, book);
    if (action == null || !mounted) {
      return;
    }
    await _afterFrame();
    if (!mounted) {
      return;
    }
    switch (action) {
      case BookAction.open:
        await _openBook(book);
      case BookAction.move:
        await _moveBook(book, categories, sections);
      case BookAction.remove:
        await _removeBook(book);
    }
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.auto_stories_outlined,
              size: 72,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              'Memoria LLM HB',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Вернуть электронной книге свойства бумажной '
              'и превзойти их.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              key: const Key('library-open-file-empty'),
              onPressed: onOpen,
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Найти книги на устройстве'),
            ),
            const SizedBox(height: 16),
            Text(
              'Приложение покажет все PDF, которые лежат на устройстве, — '
              'с обложками и поиском. Можно и выбрать файлы вручную.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Пустая полка сборки ветви СНО2026 (SNO-F-CFG-02).
///
/// Кнопки здесь нет намеренно: тестировщик книг не добавляет, а
/// экспериментатору сказано, куда идти.
class _EmptyBranchShelf extends StatelessWidget {
  const _EmptyBranchShelf();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          key: const Key('library-empty-branch'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.auto_stories_outlined,
              size: 72,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              'Литература ещё не добавлена',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Книги приходят архивом. Экспериментатор: Тестирование → '
              'Для экспериментатора — приложение найдёт архив само.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
