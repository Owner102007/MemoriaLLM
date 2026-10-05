import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/reading/page_turning.dart';
import '../../domain/reading/progress_slot.dart';
import '../../domain/reading/reader_gestures.dart';
import '../../domain/reading/reading.dart';
import '../../domain/reading/reading_filter.dart';
import '../../domain/reading/sheet_arrangement.dart';
import '../../domain/reading/sheet_placement.dart';
import '../../domain/reading/sheet_transform.dart';
import 'quick_tap.dart';
import 'reader_layers.dart';
import 'reader_mask.dart';
import 'reading_progress_book.dart';

/// Где сейчас лежит лист: раскладка плюс то, что читатель добавил щипком.
///
/// Экрану чтения это нужно затем, чтобы поставить панель действий над
/// выделением и подсветку на найденное: место и того, и другого известно в
/// долях страницы, а рисуются они на экране.
class SheetView {
  /// Создаёт вид листа.
  const SheetView({required this.placement, required this.transform});

  /// Куда положен лист.
  final SheetPlacement placement;

  /// Что читатель добавил сам; единичное, когда замок заперт.
  final SheetTransform transform;

  /// Переводит точку листа (в точках PDF) в точку экрана.
  Offset toScreen(double x, double y) {
    return transform.apply(
      Offset(
        placement.left + x * placement.scale,
        placement.top + y * placement.scale,
      ),
    );
  }
}

/// Управление листом снаружи.
///
/// Ровно одна нужда: снять выделение, не трогая страницу. Нажатие в
/// середину экрана, `Esc` и сохранение цитаты убирают выделение вместе с
/// панелью, а живёт оно внутри просмотрщика.
class ReaderSheetController {
  _ReaderSheetState? _sheet;

  /// Снять выделение.
  void clearSelection() => _sheet?._clearSelection();

  /// Выделено ли что-нибудь прямо сейчас — по словам просмотрщика. Он
  /// узнаёт о выделении раньше, чем экран чтения успевает его разобрать.
  bool get selecting => _sheet?._selecting ?? false;

  void _attach(_ReaderSheetState sheet) => _sheet = sheet;

  void _detach(_ReaderSheetState sheet) {
    if (identical(_sheet, sheet)) {
      _sheet = null;
    }
  }
}

/// Лист книги на экране: один просмотрщик, жёсткая раскладка, маска сверху.
///
/// Читалка не наводит объектив на кусок страницы, а кладёт лист так, что
/// читаемая часть занимает экран целиком. Масштаб определяется размерами
/// листа и экрана — одинаковый на каждой странице книги.
///
/// **Второго слоя нет** (решение владельца от 06.09.2026, по проверке S6.1
/// на ПК; отменяет подмену листа из S6). Страницу рисует один `PdfViewer`,
/// а читательская рамка стала **позицией плюс маской**:
///
/// 1. **Позиция.** Матрица просмотрщика приколочена к нашей раскладке —
///    `normalizeMatrix` возвращает нашу матрицу, а не его. Масштаб считаем
///    мы, а не жест, и он одинаков на каждой странице книги.
/// 2. **Маска.** Поверх — [ReaderMask] в координатах экрана, трёх уровней:
///    за пределами листа фон наглухо (иначе на широком окне видно столько
///    соседних страниц, сколько влезло, — ровно то, на чём сломалась
///    S6.1), на листе вне читаемой полосы — затемнение по настройке, а от
///    соседнего листа виден назначенный нами кусок, темнее своей страницы
///    (F-READ-13). Страница не обрезана: она продолжается в темноте.
///
/// **Листы лежат в ряд или в столбик** (F-READ-12, `sheet_arrangement`).
/// Лист, который показывается целиком, стоит в ряду: соседи по бокам. В
/// режимах с полосами листы стоят в столбик: под последней полосой
/// страницы физически лежит верх следующей, и подглядывание в неё рисует
/// тот же просмотрщик.
///
/// **Светофильтр — только на картинке страницы** (BUG-04): маска,
/// подсветка, панель над выделением и указатель места лежат выше него,
/// порядок слоёв — [ReaderLayers].
///
/// **Замок решает, можно ли трогать страницу.** Заперт — любая попытка
/// сдвинуть или приблизить возвращает матрицу на место, страница стоит
/// там, где её положили. Отперт — пан и зум принадлежат просмотрщику, и
/// он же разводит их с выделением: мышью протяжка по тексту выделяет,
/// протяжка мимо текста двигает страницу; пальцем протяжка двигает,
/// удержание выделяет. Проверено по исходникам pdfrx 2.6.1: так работает
/// `enableSelectionHandles`, оставленный по умолчанию.
///
/// **Нажатие узнаём сами** (BUG-37): просмотрщик объявляет одиночное
/// нажатие на 300 мс позже, чем оно случилось, — ждёт, не окажется ли
/// оно двойным. Поверх него стоит [QuickTap], который только смотрит на
/// указатель и сообщает о нажатии сразу; замок на это не влияет.
///
/// **Движение читателя — только пока раскладка стоит** (BUG-40). Когда
/// меняется лист, область показа или домеряются страницы книги,
/// просмотрщик перекладывает страницы и сам возвращает вид «туда, где он
/// был». На это время предложенные им матрицы не принимаются и при
/// отпертом замке — иначе его возврат читался как сдвиг страницы
/// читателем.
class ReaderSheet extends StatefulWidget {
  /// Создаёт лист.
  const ReaderSheet({
    required this.document,
    required this.pages,
    required this.fragment,
    required this.background,
    required this.page,
    required this.pageCount,
    required this.locked,
    this.stripFit = 1,
    this.dim = kDefaultDimOutside,
    this.filter = const ReadingFilterPipeline(),
    this.arrangement = SheetArrangement.row,
    this.spread = false,
    this.overlap = 0,
    this.neighbourShare = 0,
    this.preview = true,
    this.reserve = 1,
    this.progressOverPage = true,
    this.sheetController,
    this.onSelection,
    this.onTap,
    this.onMoved,
    this.overlay,
    super.key,
  });

  /// Потолок кэша растров страницы.
  ///
  /// Проверено по исходникам pdfrx 2.6.1: когда все картинки вместе
  /// весят больше этого числа, просмотрщик выбрасывает картинки страниц
  /// **до** запаса по порядку книги, начиная с дальних. Картинки страниц,
  /// которые видны или лежат в запасе, он не трогает; картинки страниц
  /// после запаса — тоже (BUG-35), и на это число не влияет ничто.
  ///
  /// Девяносто шесть мегабайт — это страница на экране, запас в две
  /// страницы с каждой стороны и резкие картинки к ним. Меньше нельзя:
  /// на время смены листа запас придерживается ([kReserveHold]), и при
  /// тесном потолке картинка только что пройденной страницы
  /// выбрасывалась бы и тут же рисовалась заново.
  static const int imageCacheBytes = 96 * 1024 * 1024;

  /// Открытый документ.
  final PdfDocument document;

  /// Номера страниц листа, начиная с единицы.
  final List<int> pages;

  /// Какую часть листа читают сейчас, в долях листа.
  final CropBox fragment;

  /// Фон вокруг страницы.
  final Color background;

  /// Текущая страница для указателя места.
  final int page;

  /// Всего страниц в книге.
  final int pageCount;

  /// Заперт ли масштаб.
  final bool locked;

  /// Запас по краям полосы: 1 — вписана вплотную.
  final double stripFit;

  /// Сила затемнения нечитаемой части страницы.
  final double dim;

  /// Светофильтр. Ложится только на картинку страницы (BUG-04).
  final ReadingFilterPipeline filter;

  /// Как листы лежат в документе просмотрщика: в ряд или в столбик.
  final SheetArrangement arrangement;

  /// Листается ли книга разворотами: в столбике лист разворота — две
  /// страницы рядом.
  final bool spread;

  /// Нахлёст полосы, доля высоты экрана — уже для текущего режима
  /// (F-READ-12). Ноль — полоса вплотную.
  final double overlap;

  /// Ширина полоски соседней страницы, доля ширины экрана (F-READ-13).
  final double neighbourShare;

  /// Показывать ли страницу сразу — грубой картинкой, а резкую
  /// дорисовывать следом (F-READ-02).
  final bool preview;

  /// Сколько соседних листов держать наготове с каждой стороны.
  final int reserve;

  /// Можно ли класть указатель места поверх страницы, когда свободного
  /// поля под него нет. В чтении во весь экран — нельзя (F-READ-35).
  final bool progressOverPage;

  /// Рычаги к листу снаружи.
  final ReaderSheetController? sheetController;

  /// Выделение изменилось. Пустой список означает, что выделения нет.
  final void Function(List<PdfPageTextRange> ranges)? onSelection;

  /// Нажатие по странице: экран чтения решает, листать, снять выделение
  /// или показать панели. `selecting` — есть ли сейчас выделение у
  /// просмотрщика: он узнаёт о нём раньше, чем экран успевает его
  /// разобрать.
  final void Function(Offset localPosition, {required bool selecting})? onTap;

  /// Читатель подвинул или приблизил страницу при отпертом замке.
  ///
  /// Только сообщение: лист от ответа не зависит. Его слушает журнал
  /// записи сборок ветвей СНО2026 (SNO-F-REC-02).
  final void Function(SheetTransform transform)? onMoved;

  /// Что нарисовать поверх листа: подсветка найденного, панель действий.
  final Widget Function(BuildContext context, SheetView view)? overlay;

  @override
  State<ReaderSheet> createState() => _ReaderSheetState();
}

class _ReaderSheetState extends State<ReaderSheet> {
  /// Указатели, которыми выделяют удержанием, а не протяжкой.
  static final Set<PointerDeviceKind> _holdDevices = <PointerDeviceKind>{
    for (final PointerDeviceKind kind in PointerDeviceKind.values)
      if (!selectionStartsOnDrag(kind)) kind,
  };

  final PdfViewerController _viewer = PdfViewerController();

  /// Ключ просмотрщика: светофильтр то оборачивает его, то нет, и без
  /// ключа каждая смена фильтра пересоздавала бы просмотрщик — с белым
  /// листом и возвратом на первую страницу листа (BUG-04).
  final GlobalKey _viewerKey = GlobalKey(debugLabel: 'reader-viewer');

  /// Нажатие узнаём сами, по сырым событиям указателя, а не от
  /// просмотрщика: тот объявляет его на 300 мс позже (BUG-37).
  final TapWatch _taps = TapWatch();

  /// Раскладка последнего построения: её же спрашивает [_pin].
  SheetPlacement _placement = SheetPlacement.none;

  /// Что читатель добавил к раскладке сам.
  SheetTransform _transform = SheetTransform.none;

  Size _screen = Size.zero;
  bool _ready = false;

  /// Раскладка и страницы, до которых просмотрщик уже доехал.
  SheetPlacement? _appliedPlacement;
  List<int> _appliedPages = const <int>[];
  Size _appliedScreen = Size.zero;
  SheetArrangement? _appliedArrangement;
  bool _appliedSpread = false;

  /// Страницы документа, как мы их разложили для просмотрщика в прошлый
  /// раз. Сменились — он перекладывает их у себя.
  List<Rect>? _laidOut;

  /// Сколько перекладок просмотрщика ещё не закончено (BUG-40).
  int _relays = 0;

  /// Масштаб, в котором держатся грубые картинки страниц, в пикселях
  /// на точку PDF. Ноль — раскладки ещё не было.
  double _previewScale = 0;

  /// Сообщения движка о домеренных страницах.
  StreamSubscription<PdfDocumentEvent>? _documentEvents;
  PdfDocument? _eventsOf;

  /// Придержан ли запас соседних страниц: лист только что сменился, и
  /// первой в очередь на отрисовку обязана встать страница на экране.
  bool _reserveHeld = true;
  Timer? _reserveTimer;

  PdfDocument? _refFor;
  PdfDocumentRefDirect? _ref;

  /// Ссылка на открытый документ, одна и та же между перестроениями.
  ///
  /// Новый экземпляр на каждый кадр просмотрщик считал бы за смену
  /// документа: при отпертом замке дерево перестраивается на каждое
  /// движение пальца, и книга перезагружалась бы под руками.
  PdfDocumentRefDirect get _documentRef {
    if (!identical(_refFor, widget.document)) {
      _refFor = widget.document;
      _ref = PdfDocumentRefDirect(widget.document, autoDispose: false);
    }
    return _ref!;
  }

  @override
  void initState() {
    super.initState();
    widget.sheetController?._attach(this);
    _viewer.addListener(_onMatrixChanged);
    _watchDocument();
    _holdReserve();
  }

  @override
  void didUpdateWidget(ReaderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sheetController, widget.sheetController)) {
      oldWidget.sheetController?._detach(this);
      widget.sheetController?._attach(this);
    }
    _watchDocument();
    if (!_samePages(oldWidget.pages)) {
      _holdReserve();
    }
    // Замок захлопнулся — страница замирает как есть. Но если её только
    // сдвинули, не меняя масштаба, сдвиг снимается: смещённая на палец
    // страница выглядит не выбором читателя, а поломкой, и вернуть её при
    // запертом замке было бы нечем (BUG-26).
    if (widget.locked && !oldWidget.locked) {
      final SheetTransform kept = sheetTransformOnLock(_transform);
      if (kept != _transform) {
        _transform = kept;
        _sync();
      }
    }
  }

  @override
  void dispose() {
    widget.sheetController?._detach(this);
    _viewer.removeListener(_onMatrixChanged);
    unawaited(_documentEvents?.cancel());
    _reserveTimer?.cancel();
    super.dispose();
  }

  /// Убирает запас соседних страниц на время смены листа.
  ///
  /// F-READ-02: без этого грубая картинка страницы, только что попавшей
  /// в запас, вставала в очередь движка раньше резкой картинки страницы
  /// на экране — и читатель ждал резкости дольше, чем до запаса.
  void _holdReserve() {
    _reserveHeld = true;
    _reserveTimer?.cancel();
    _reserveTimer = Timer(kReserveHold, () {
      if (mounted) {
        setState(() => _reserveHeld = false);
      }
    });
  }

  /// Подписывается на сообщения открытого документа.
  void _watchDocument() {
    if (identical(_eventsOf, widget.document)) {
      return;
    }
    unawaited(_documentEvents?.cancel());
    _eventsOf = widget.document;
    _documentEvents = widget.document.events.listen(_onDocumentEvent);
  }

  /// Движок домерил страницы книги.
  ///
  /// F-READ-02: книга открывается, не измеряя все свои страницы, и
  /// размеры досчитываются уже при открытой книге. Страницы лежат в ряд
  /// или в столбик вплотную, поэтому новый размер любой страницы перед
  /// листом сдвигает сам лист: просмотрщик обязан встать на его новое
  /// место раньше, чем нарисует кадр. А если домерили страницу самого
  /// листа, меняется и раскладка — её пересчитает перестроение.
  void _onDocumentEvent(PdfDocumentEvent event) {
    if (!mounted || event is! PdfDocumentPageStatusChangedEvent) {
      return;
    }
    _sync();
    if (widget.pages.any(event.changes.containsKey)) {
      setState(() {});
    }
  }

  /// Масштаб грубой картинки страницы, в пикселях на точку PDF.
  ///
  /// F-READ-02: грубая картинка — то, что читатель видит в первый миг
  /// после нажатия, пока резкая ещё рисуется. Чем она ближе к нужному
  /// экрану масштабу, тем незаметнее ступенька «грубо → резко»; предел
  /// пикселей на страницу не даёт запасу соседних страниц съесть память.
  double _pagePreviewScale(
    BuildContext context,
    PdfPage page,
    PdfViewerController controller,
    double estimatedScale,
  ) {
    if (_previewScale <= 0) {
      return estimatedScale;
    }
    final double cap = previewScaleCap(
      pageWidth: page.width,
      pageHeight: page.height,
    );
    return cap > 0 && cap < _previewScale ? cap : _previewScale;
  }

  /// Читатель подвинул или приблизил страницу.
  ///
  /// Пока замок заперт, матрица возвращается на место в [_pin], и слушать
  /// нечего. Отперев его, читатель двигает страницу — а вместе с ней
  /// обязаны ехать и маска, и подсветка, и панель над выделением.
  void _onMatrixChanged() {
    if (!mounted || widget.locked || !_ready || !_placement.isVisible) {
      return;
    }
    // Пока просмотрщик перекладывает страницы, матрицу двигает он, а не
    // читатель (BUG-40): запоминать нечего.
    if (_relaying) {
      return;
    }
    final Offset origin = _origin();
    final SheetTransform next = sheetTransformOf(
      matrix: _viewer.value,
      placement: _placement,
      documentLeft: origin.dx,
      documentTop: origin.dy,
    );
    if (next == _transform) {
      return;
    }
    widget.onMoved?.call(next);
    // Матрицу просмотрщик меняет и во время собственной раскладки, а
    // `setState` посреди построения дерева — исключение. Тогда правка
    // откладывается на конец кадра: маска отстанет на кадр, но не уронит
    // чтение.
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _transform = next);
        }
      });
      return;
    }
    setState(() => _transform = next);
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    _ready = true;
    _sync();
  }

  /// Ставит просмотрщик туда, где по нашей раскладке лежит лист.
  ///
  /// `goTo` с нулевой длительностью проходит через [_pin] и своего
  /// ограничения границами при этом не применяет вовсе — матрица встаёт
  /// ровно нашей.
  void _sync() {
    if (!_ready || !_viewer.isReady || !_placement.isVisible) {
      return;
    }
    unawaited(_viewer.goTo(_target(), duration: Duration.zero));
  }

  /// Просмотрщика на экране нет — и всё, что мы о нём знали, устарело.
  ///
  /// Свёрнутое окно ПК раскладывается в ноль на ноль: показывать нечего,
  /// и просмотрщик уходит из дерева. Вернётся он уже новым — заново
  /// разложит страницы и сам встанет на первую. Если помнить прежнего
  /// «готовым», при отпертом замке эта его расстановка читалась бы как
  /// движение читателя — тот же дефект, что BUG-40, с другого входа.
  void _viewerGone() {
    _ready = false;
    _laidOut = null;
  }

  Matrix4 _target() {
    final Offset origin = _origin();
    return sheetMatrix(
      placement: _placement,
      documentLeft: origin.dx,
      documentTop: origin.dy,
      transform: _transform,
    );
  }

  /// Перекладывает ли просмотрщик страницы прямо сейчас.
  bool get _relaying => _relays > 0;

  /// Раскладка сменилась: до конца перекладки матрицы просмотрщика — не
  /// движение читателя.
  ///
  /// BUG-40, ALG-PDF-21; проверено по исходникам pdfrx 2.6.1
  /// (`_updateLayout`, `onLayoutUpdate`). Переложив страницы или получив
  /// область показа другого размера, просмотрщик возвращает вид «туда,
  /// где он был», и делает это микрозадачей, поставленной во время
  /// построения кадра. Если в том же кадре сменился лист, «где был» —
  /// это прежний лист. При отпертом замке мы принимали такой возврат за
  /// жест, и страница уезжала к краю экрана на всех следующих листах.
  ///
  /// Окно закрывается своей микрозадачей, поставленной после кадра: в
  /// очереди она стоит за микрозадачей просмотрщика, и к её началу его
  /// возврат уже отработал — и был отклонён в [_pin]. Зовётся только во
  /// время построения кадра; запрос кадра — страховка на случай, если
  /// это когда-нибудь перестанет быть так, иначе окно осталось бы
  /// открытым, а страница — неподвижной.
  ///
  /// **Держится на порядке внутри pdfrx**: возврат ставится микрозадачей
  /// из построения. Поднимая версию pdfrx, это проверяют первым — тестом
  /// порядок не закреплён: просмотрщик с настоящим PDFium в widget-тестах
  /// не строится.
  void _beginRelay() {
    _relays++;
    SchedulerBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(_endRelay);
    });
  }

  void _endRelay() {
    if (_relays > 0) {
      _relays--;
    }
    if (mounted && !_relaying) {
      // Просмотрщик мог оставить матрицу своей — ставим лист на место.
      _sync();
    }
  }

  /// Матрица, приколоченная к раскладке листа.
  ///
  /// Просмотрщик зовёт это на каждое изменение матрицы и берёт ответ как
  /// есть. Заперт замок — возвращается наша матрица, и страница не уезжает
  /// ни от инерции, ни от случайного жеста. Отперт — берётся предложенная,
  /// но в разумных пределах: страницу нельзя ни увести с экрана целиком,
  /// ни уменьшить до точки. Пока просмотрщик перекладывает страницы,
  /// предложенное не берётся и при отпертом замке (BUG-40): это не жест.
  Matrix4 _pin(
    Matrix4 matrix,
    Size viewSize,
    PdfPageLayout layout,
    PdfViewerController? controller,
  ) {
    if (!_placement.isVisible) {
      return matrix;
    }
    final Offset origin = _origin();
    final SheetTransform kept = sheetTransformAfterMove(
      current: _transform,
      proposed: sheetTransformOf(
        matrix: matrix,
        placement: _placement,
        documentLeft: origin.dx,
        documentTop: origin.dy,
      ),
      placement: _placement,
      screen: viewSize,
      locked: widget.locked,
      relaying: _relaying,
    );
    return sheetMatrix(
      placement: _placement,
      documentLeft: origin.dx,
      documentTop: origin.dy,
      transform: kept,
    );
  }

  /// Где первая страница листа лежит в документе просмотрщика.
  ///
  /// Считается по тем же правилам, что и раскладка в [_layoutPages], и по
  /// сегодняшним размерам страниц: домерили страницу перед листом — лист
  /// уехал, и матрица обязана уехать за ним.
  Offset _origin() {
    if (widget.pages.isEmpty) {
      return Offset.zero;
    }
    final List<PdfPage> pages = widget.document.pages;
    return sheetOrigin(
      firstPage: widget.pages.first,
      pageCount: pages.length,
      widthOf: (int page) => pages[page - 1].width,
      heightOf: (int page) => pages[page - 1].height,
      arrangement: widget.arrangement,
      spread: widget.spread,
    );
  }

  /// Страницы вплотную и без полей — в ряд или в столбик (F-READ-12).
  ///
  /// Соседние страницы при этом остаются в раскладке — их закрывает
  /// маска, а не отсутствие. Убрать их из раскладки нельзя: номера
  /// страниц и места в тексте считаются по всему документу.
  ///
  /// Просмотрщик зовёт это при каждом своём построении. Если страницы
  /// легли иначе, чем в прошлый раз, — домерены их размеры или режим
  /// сменил ряд на столбик, — он переложит их и вернёт вид сам:
  /// открывается окно перекладки (BUG-40).
  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) {
    final List<Rect> rects = arrangePages(
      pageCount: pages.length,
      widthOf: (int page) => pages[page - 1].width,
      heightOf: (int page) => pages[page - 1].height,
      arrangement: widget.arrangement,
      spread: widget.spread,
    );
    if (!listEquals(_laidOut, rects)) {
      _laidOut = rects;
      _beginRelay();
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: arrangedSize(rects));
  }

  /// Выделено ли что-нибудь прямо сейчас — по словам самого просмотрщика.
  bool get _selecting =>
      _ready && _viewer.textSelectionDelegate.hasSelectedText;

  /// Нажатие, которое мы узнали сами, — исполняется сразу.
  ///
  /// Кроме одного случая: **пока текст выделен, решает просмотрщик**.
  /// Слушатель указателя видит и касания ручек выделения, а короткий
  /// толчок ручки от нажатия по странице ему не отличить — выделение
  /// снималось бы у читателя из-под пальца. Просмотрщик отличает: о
  /// ручках он не сообщает вовсе. Цена — прежние 300 мс до снятия
  /// выделения; листают без выделения, и там паузы нет.
  void _onQuickTap(Offset position) {
    if (_selecting) {
      _taps.leaveToViewer();
      return;
    }
    widget.onTap?.call(position, selecting: false);
  }

  /// Что о нажатии сообщил просмотрщик.
  ///
  /// BUG-37, проверено по исходникам pdfrx 2.6.1 (`pdf_viewer.dart`,
  /// `GestureDetector` страниц): одиночное, двойное и долгое нажатие
  /// стоят на одном распознавателе, и одиночное объявляется, только когда
  /// истёк срок ожидания двойного, — через 300 мс. Двойное при этом не
  /// делает ничего. Поэтому нажатие исполняет [_onQuickTap], в миг, когда
  /// указатель поднят, а сюда оно доходит эхом — и второй раз не
  /// исполняется, иначе страница перелистнулась бы дважды.
  ///
  /// Не эхо — нажатие без указателя: так нажимают средства доступности.
  /// И не эхо — нажатие, которое [_onQuickTap] оставил просмотрщику,
  /// потому что текст был выделен.
  ///
  /// Одиночное нажатие просмотрщику не отдаётся никогда, в том числе по
  /// выделенному тексту: снять выделение или листать, решает экран
  /// чтения (F-READ-22), а не просмотрщик.
  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type == PdfViewerGeneralTapType.tap) {
      if (!_taps.echoes()) {
        widget.onTap?.call(details.localPosition, selecting: _selecting);
      }
      return true;
    }
    if (details.type == PdfViewerGeneralTapType.longPress) {
      // Мышью удержание узнаёт сам просмотрщик — и выделяет слово.
      // Жест, которым оно сделано, нажатием уже не станет.
      _taps.spoil();
    }
    return false;
  }

  void _onSelectionChange(PdfTextSelection selection) {
    unawaited(_reportSelection(selection));
  }

  Future<void> _reportSelection(PdfTextSelection selection) async {
    final List<PdfPageTextRange> ranges = await selection
        .getSelectedTextRanges();
    if (!mounted) {
      return;
    }
    widget.onSelection?.call(ranges);
  }

  void _clearSelection() {
    if (_ready) {
      unawaited(_viewer.textSelectionDelegate.clearTextSelection());
    }
  }

  /// Выделить слово под пальцем.
  ///
  /// Своё долгое нажатие, а не то, что у просмотрщика: у него порог —
  /// стандартные полсекунды, а владелец на проверке S6 назвал это
  /// «слишком долго». Наш распознаватель объявляет победу раньше, поэтому
  /// нажатие просмотрщика до дела не доходит, а делает он ровно то же
  /// самое — [PdfTextSelectionDelegate.selectWord].
  void _selectWordAt(Offset screen) {
    if (!_ready || !_placement.isVisible) {
      return;
    }
    final Offset origin = _origin();
    final Offset? point = documentPoint(
      screen: screen,
      placement: _placement,
      documentLeft: origin.dx,
      documentTop: origin.dy,
      transform: _transform,
    );
    if (point == null) {
      return;
    }
    unawaited(_viewer.textSelectionDelegate.selectWord(point));
  }

  @override
  Widget build(BuildContext context) {
    final List<PdfPage> sheet = <PdfPage>[
      for (final int number in widget.pages)
        if (number >= 1 && number <= widget.document.pages.length)
          widget.document.pages[number - 1],
    ];
    if (sheet.isEmpty) {
      _viewerGone();
      // Молчаливый чёрный прямоугольник — худший из возможных ответов:
      // по нему не отличить «страница ещё грузится» от «книга сломана».
      return ColoredBox(
        color: widget.background,
        child: const Center(
          child: SizedBox(
            key: Key('reader-sheet-waiting'),
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    double sheetWidth = 0;
    double sheetHeight = 0;
    for (final PdfPage page in sheet) {
      sheetWidth += page.width;
      sheetHeight = sheetHeight < page.height ? page.height : sheetHeight;
    }

    return ColoredBox(
      color: widget.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints limits) {
          final SheetPlacement placement = placeFragment(
            sheetWidth: sheetWidth,
            sheetHeight: sheetHeight,
            fragment: widget.fragment,
            screenWidth: limits.maxWidth,
            screenHeight: limits.maxHeight,
            fit: widget.stripFit,
            overlap: widget.overlap,
            // F-READ-11: полоса прижата кверху; лист целиком — по центру.
            anchorTop: widget.arrangement == SheetArrangement.column,
          );
          _placement = placement;
          _screen = Size(limits.maxWidth, limits.maxHeight);
          if (!placement.isVisible) {
            _viewerGone();
            return const SizedBox.expand();
          }
          _scheduleSync(placement);
          _previewScale = heldPreviewScale(
            held: _previewScale,
            wanted: placement.scale * MediaQuery.devicePixelRatioOf(context),
          );

          final SheetView view = SheetView(
            placement: placement,
            transform: _transform,
          );
          final Rect sheetRect = sheetRectOnScreen(
            placement: placement,
            transform: _transform,
          );
          final Rect stripRect = stripRectOnScreen(
            placement: placement,
            fragment: widget.fragment,
            transform: _transform,
          );
          // Что видно от соседних листов (F-READ-12, F-READ-13). Размеры
          // назначены долями экрана и едут вместе со страницей, когда
          // читатель двигает её при отпертом замке.
          final List<NeighbourZone> neighbours = neighbourZones(
            arrangement: widget.arrangement,
            sheet: sheetRect,
            strip: stripRect,
            band: widget.overlap * limits.maxHeight * _transform.scale,
            width: widget.neighbourShare * limits.maxWidth * _transform.scale,
            hasBefore: widget.pages.first > 1,
            hasAfter: widget.pages.last < widget.document.pages.length,
          );
          final int reserve = widget.preview && !_reserveHeld
              ? widget.reserve
              : 0;
          // Запас откладывается от видимой области, а она меряется в
          // точках PDF: экран, делённый на масштаб — вместе с тем, что
          // читатель добавил щипком. В ряду запас идёт по горизонтали, в
          // столбике — по вертикали.
          final double zoom = placement.scale * _transform.scale;
          final bool column = widget.arrangement == SheetArrangement.column;
          return ReaderLayers(
            filter: widget.filter,
            page: KeyedSubtree(
              key: _viewerKey,
              child: _buildViewer(
                horizontalExtent: column
                    ? 0
                    : neighbourCacheExtent(
                        sheetWidth: sheetWidth,
                        visibleWidth: limits.maxWidth / zoom,
                        sheets: reserve,
                      ),
                verticalExtent: column
                    ? columnCacheExtent(
                        sheetHeight: sheetHeight,
                        visibleTop: -sheetRect.top / zoom,
                        visibleHeight: limits.maxHeight / zoom,
                        sheets: reserve,
                      )
                    : kRowVerticalCacheExtent,
              ),
            ),
            mask: ReaderMask(
              key: const Key('reader-mask'),
              sheet: sheetRect,
              strip: stripRect,
              dim: widget.dim,
              background: widget.background,
              neighbours: neighbours,
            ),
            overlay: widget.overlay?.call(context, view),
            progress: ReadingProgressBook(
              slot: progressSlotFor(
                placement: placement,
                screenWidth: _screen.width,
                screenHeight: _screen.height,
                overPage: widget.progressOverPage,
                reservedRight: _reserved(neighbours, sheetRect, right: true),
                reservedBottom: _reserved(neighbours, sheetRect, right: false),
              ),
              page: widget.page,
              pageCount: widget.pageCount,
            ),
          );
        },
      ),
    );
  }

  /// Сколько поля у правого или нижнего края листа занято соседней
  /// страницей: указатель места встаёт за ней (F-READ-13).
  static double _reserved(
    List<NeighbourZone> neighbours,
    Rect sheet, {
    required bool right,
  }) {
    double taken = 0;
    for (final NeighbourZone zone in neighbours) {
      final double size = right
          ? (zone.rect.left >= sheet.right ? zone.rect.width : 0)
          : (zone.rect.top >= sheet.bottom ? zone.rect.height : 0);
      if (size > taken) {
        taken = size;
      }
    }
    return taken;
  }

  /// Довозит просмотрщик до новой раскладки — но не во время построения.
  ///
  /// Новый лист, новая раскладка, область показа другого размера или
  /// листы, вставшие из ряда в столбик, — это ещё и перекладка у
  /// просмотрщика: до её конца его матрицы не принимаются за движение
  /// читателя (BUG-40).
  void _scheduleSync(SheetPlacement placement) {
    if (placement == _appliedPlacement &&
        _screen == _appliedScreen &&
        widget.arrangement == _appliedArrangement &&
        widget.spread == _appliedSpread &&
        _samePages(_appliedPages)) {
      return;
    }
    _appliedPlacement = placement;
    _appliedScreen = _screen;
    _appliedArrangement = widget.arrangement;
    _appliedSpread = widget.spread;
    _appliedPages = List<int>.of(widget.pages);
    _beginRelay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sync();
      }
    });
  }

  bool _samePages(List<int> other) {
    if (other.length != widget.pages.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (other[i] != widget.pages[i]) {
        return false;
      }
    }
    return true;
  }

  Widget _buildViewer({
    required double horizontalExtent,
    required double verticalExtent,
  }) {
    // Слушатель нажатий стоит снаружи и в арене жестов не участвует
    // вовсе: он только смотрит на указатель и узнаёт нажатие раньше
    // просмотрщика (BUG-37).
    return QuickTap(
      watch: _taps,
      onTap: _onQuickTap,
      child: _buildSelectingViewer(
        horizontalExtent: horizontalExtent,
        verticalExtent: verticalExtent,
      ),
    );
  }

  Widget _buildSelectingViewer({
    required double horizontalExtent,
    required double verticalExtent,
  }) {
    // Своё долгое нажатие поверх просмотрщика: порог у него стандартный,
    // полсекунды, а нужно «почти моментально». Распознаватель спорит в
    // общей арене на равных — быстрое касание он проигрывает, и зоны
    // листания живут как жили.
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: kTouchSelectionDelay,
                supportedDevices: _holdDevices,
              ),
              (LongPressGestureRecognizer instance) {
                instance.onLongPressStart = (LongPressStartDetails details) {
                  // Удержание победило: этот жест — выделение, и нажатием
                  // он уже не станет, когда бы ни подняли палец.
                  _taps.spoil();
                  _selectWordAt(details.localPosition);
                };
              },
            ),
      },
      child: PdfViewer(
        // Тот же открытый документ, что и у контроллера чтения: второе
        // открытие книги стоило бы вдвое больше памяти и отдавало бы
        // страницы не сразу.
        _documentRef,
        controller: _viewer,
        initialPageNumber: widget.pages.isEmpty ? 1 : widget.pages.first,
        params: PdfViewerParams(
          // Своего фона у просмотрщика нет (BUG-04): он лежит под
          // светофильтром, и его фон «Инверсия» сделала бы светлым —
          // там, где в дырке маски нет страницы: рядом с обложкой в
          // столбике разворотов, под короткой страницей разворота. Фон
          // даёт сам лист, ниже фильтра; прозрачность фильтр не трогает.
          backgroundColor: Colors.transparent,
          margin: 0,
          pageDropShadow: null,
          // Пан и зум просмотрщику не запрещены вовсе, и это не оплошность.
          // Замок живёт в [_pin]: заперт — любая предложенная матрица
          // заменяется нашей, и страница стоит намертво. Запрещать их
          // параметрами значило бы пересобирать просмотрщик на каждое
          // нажатие замка, а заодно ронять кэш растров.
          //
          // Клавиши у просмотрщика отобраны целиком: листание принадлежит
          // экрану чтения, а его собственная навигация увела бы страницу
          // от нашей. Выключается это `keyHandlerParams`, а не
          // `enableKeyboardNavigation`: последний в pdfrx 2.6.1 нигде не
          // читается — параметр остался, а поведение из него ушло.
          keyHandlerParams: const PdfViewerKeyHandlerParams(enabled: false),
          // F-READ-02, проверено по исходникам pdfrx 2.6.1. Резкую
          // картинку просмотрщик рисует только для видимой части
          // страницы и заново при каждом сдвиге: запас кэша на неё не
          // действует вовсе. Запас решает одно — каким страницам держать
          // **грубую** картинку целиком. Пока грубая была выключена,
          // наготове не было ничего, и любое нажатие — даже на следующую
          // полосу той же страницы — показывало белый лист до конца
          // рендера. Теперь грубая картинка страницы и её соседей лежит
          // в памяти: текст на месте сразу, резкость дорисовывается.
          //
          // Соседние страницы под маской, и платим мы памятью за
          // невидимое — зато к моменту нажатия они уже нарисованы.
          horizontalCacheExtent: horizontalExtent,
          verticalCacheExtent: verticalExtent,
          maxImageBytesCachedOnMemory: ReaderSheet.imageCacheBytes,
          getPageRenderingScale: _pagePreviewScale,
          // Ступенька «грубо → резко» раздражает не всех одинаково, и
          // выключить её можно в настройках: тогда страница появляется
          // только резкой, как до F-READ-02.
          //
          // Размеры страниц просмотрщик меряет по мере надобности — тех,
          // что попали в запас. Иначе он сам обходит всю книгу в фоне, и
          // в pdfrx 2.6.1 этот обход идёт в том же потоке движка, что и
          // отрисовка, кусками по четверти секунды: первые секунды после
          // открытия толстой книги каждое нажатие ждало бы своей очереди.
          // Поиску это не мешает: содержимое любой страницы документ
          // домеряет сам (`PdfrxReaderDocument`).
          behaviorControlParams: PdfViewerBehaviorControlParams(
            enableLowResolutionPagePreview: widget.preview,
            loadPageDimensionsOnDemand: true,
          ),
          layoutPages: _layoutPages,
          normalizeMatrix: _pin,
          textSelectionParams: PdfTextSelectionParams(
            // Ручки и лупа оставлены на усмотрение указателя, и это
            // главное в сегодняшней правке. По исходникам pdfrx: с
            // ручками протяжка по тексту выключена вовсе, а без них —
            // включена. Значение по умолчанию решает это по устройству:
            // палец получает ручки и удержание, мышь — протяжку сразу.
            showContextMenuAutomatically: false,
            onTextSelectionChange: _onSelectionChange,
          ),
          // Своё меню, а не системное: над выделением стоит панель с
          // промптами читателя, и второе меню поверх неё ни к чему.
          buildContextMenu: _noContextMenu,
          onViewerReady: _onViewerReady,
          onGeneralTap: _onGeneralTap,
        ),
      ),
    );
  }
}

/// Запас кэша просмотрщика по вертикали, когда листы лежат в ряд.
///
/// Значение pdfrx по умолчанию, и стояло оно всегда: в ряду все страницы
/// лежат на одной высоте, и вертикальный запас ни одной страницы не
/// добавляет. Записано числом, чтобы в столбике его можно было заменить
/// посчитанным, а в ряду оставить как было.
const double kRowVerticalCacheExtent = 1.0;

/// Системного меню над выделением нет: над ним стоит наша панель.
Widget? _noContextMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) => null;

/// Матрица просмотрщика, повторяющая раскладку листа.
///
/// Договор pdfrx простой: `экран = документ × масштаб + сдвиг`, масштаб
/// лежит в первой ячейке матрицы. Лист вписан в экран нашей математикой,
/// поэтому масштаб берётся из раскладки, а сдвиг — из места листа на
/// экране за вычетом того, где лист лежит в документе.
///
/// То, что читатель добавил сам, накладывается сверху: и то, и другое —
/// только сдвиг и масштаб, поэтому произведение снова оказывается сдвигом
/// и масштабом, а другого просмотрщик и не ждёт.
///
/// [documentLeft] и [documentTop] — где лист лежит в документе
/// просмотрщика: в ряду листы уходят вправо, в столбике — вниз
/// (F-READ-12).
Matrix4 sheetMatrix({
  required SheetPlacement placement,
  required double documentLeft,
  double documentTop = 0,
  SheetTransform transform = SheetTransform.none,
}) {
  final double zoom = placement.scale * transform.scale;
  final Matrix4 matrix = Matrix4.zero();
  matrix.setEntry(0, 0, zoom);
  matrix.setEntry(1, 1, zoom);
  matrix.setEntry(2, 2, zoom);
  matrix.setEntry(3, 3, 1);
  matrix.setEntry(
    0,
    3,
    (placement.left - documentLeft * placement.scale) * transform.scale +
        transform.dx,
  );
  matrix.setEntry(
    1,
    3,
    (placement.top - documentTop * placement.scale) * transform.scale +
        transform.dy,
  );
  return matrix;
}

/// Обратный ход: что читатель добавил к раскладке, судя по матрице.
///
/// Нужен ровно затем, чтобы маска и подсветка ехали за страницей, когда
/// замок отперт и матрицей распоряжается просмотрщик.
SheetTransform sheetTransformOf({
  required Matrix4 matrix,
  required SheetPlacement placement,
  required double documentLeft,
  double documentTop = 0,
}) {
  final double zoom = matrix.storage[0];
  if (!placement.isVisible || !zoom.isFinite || zoom <= 0) {
    return SheetTransform.none;
  }
  final double scale = zoom / placement.scale;
  final double baseLeft = placement.left - documentLeft * placement.scale;
  final double baseTop = placement.top - documentTop * placement.scale;
  return SheetTransform(
    scale: scale,
    dx: matrix.storage[12] - baseLeft * scale,
    dy: matrix.storage[13] - baseTop * scale,
  );
}

/// Переводит точку экрана в координаты документа просмотрщика.
///
/// Возвращает `null`, если переводить не во что: пустая раскладка или
/// вырожденный масштаб.
Offset? documentPoint({
  required Offset screen,
  required SheetPlacement placement,
  required double documentLeft,
  double documentTop = 0,
  SheetTransform transform = SheetTransform.none,
}) {
  final Matrix4 matrix = sheetMatrix(
    placement: placement,
    documentLeft: documentLeft,
    documentTop: documentTop,
    transform: transform,
  );
  final double zoom = matrix.storage[0];
  if (!zoom.isFinite || zoom <= 0) {
    return null;
  }
  return Offset(
    (screen.dx - matrix.storage[12]) / zoom,
    (screen.dy - matrix.storage[13]) / zoom,
  );
}
