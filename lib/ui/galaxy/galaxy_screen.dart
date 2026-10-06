import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/cover_service.dart';
import '../../application/map/galaxy.dart';
import '../../domain/library/book.dart';
import '../../domain/map/map_layout.dart';
import '../../domain/map/map_view.dart';
import '../../domain/navigation/sections.dart';
import '../../domain/reading/reading.dart';
import '../../domain/theme/app_palette.dart';
import '../../sno/index/shelf_reading.dart';
import '../../sno/index/shelf_reading_view.dart';
import '../reader/reader_screen.dart';
import '../theme/palette_scope.dart';
import 'galaxy_painter.dart';

/// За сколько миллисекунд второе нажатие в том же месте считается
/// двойным.
const int kGalaxyDoubleTapMs = 300;

/// На каком расстоянии от первого нажатия второе ещё «в том же месте»,
/// в логических пикселях.
const double kGalaxyDoubleTapSlop = 24;

/// Ширина карточки книги рядом с точкой — на широком окне.
const double kGalaxyCardWidth = 340;

/// Раздел «Галактика»: книги полки картой (F-MAP-06, SNO-F-MAP-01,
/// экран SCR-04).
///
/// Книга — точка; близкие по содержанию книги стоят рядом, книги одной
/// категории — одной группой под её названием. Карту здесь не считают:
/// места книг посчитаны заранее подготовкой книг
/// (`sno/index/shelf_reading.dart`) и лежат на устройстве. Пока
/// подготовка идёт, карты нет или книг для неё мало, раздел говорит об
/// этом словами (F-MAP-11) — пустого поля читатель не видит никогда.
///
/// Раздел пока есть только в сборке ветви II СНО2026; признак сборки
/// сюда не приходит — что показывать, решают службы: есть ли подготовка
/// книг и счёт времени чтения.
class GalaxyScreen extends StatefulWidget {
  /// Создаёт раздел.
  const GalaxyScreen({
    required this.services,
    this.visible = true,
    this.onReading,
    this.canRelink = true,
    this.models = true,
    super.key,
  });

  /// Службы приложения.
  final AppServices services;

  /// На экране ли раздел. Карта читается с устройства, когда раздел
  /// открывают: размер точек — время чтения к этому мигу, и на глазах
  /// у читателя он не меняется.
  final bool visible;

  /// Читатель открыл книгу (`true`) или закрыл её (`false`) — то же,
  /// что у полки: пока книгу читают, движок PDF отдан странице.
  final ValueChanged<bool>? onReading;

  /// Можно ли на экране чтения выбрать файл книги заново (BUG-46).
  final bool canRelink;

  /// Есть ли в сборке модель: промпты над выделенным текстом.
  final bool models;

  @override
  State<GalaxyScreen> createState() => _GalaxyScreenState();
}

class _GalaxyScreenState extends State<GalaxyScreen> {
  Galaxy? _galaxy;
  bool _failed = false;
  int _run = 0;
  bool _wasBusy = false;

  ShelfReading? get _reading => widget.services.shelfReading;

  @override
  void initState() {
    super.initState();
    _reading?.addListener(_readingChanged);
    _wasBusy = _reading?.progress.busy ?? false;
    if (widget.visible) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(GalaxyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.services.shelfReading,
      widget.services.shelfReading,
    )) {
      oldWidget.services.shelfReading?.removeListener(_readingChanged);
      _reading?.addListener(_readingChanged);
      _wasBusy = _reading?.progress.busy ?? false;
    }
    if (!identical(oldWidget.services, widget.services) ||
        (widget.visible && !oldWidget.visible)) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _reading?.removeListener(_readingChanged);
    super.dispose();
  }

  /// Подготовка книг сдвинулась: ход на экране обновляется, а когда она
  /// кончилась — карта читается заново, она могла пересчитаться.
  void _readingChanged() {
    if (!mounted) {
      return;
    }
    final bool busy = _reading?.progress.busy ?? false;
    final bool finished = _wasBusy && !busy;
    _wasBusy = busy;
    setState(() {});
    if (finished && widget.visible) {
      unawaited(_load());
    }
  }

  /// Читает карту с устройства.
  Future<void> _load() async {
    final int run = ++_run;
    Galaxy? galaxy;
    bool failed = false;
    try {
      galaxy = await loadGalaxy(
        library: widget.services.data.library,
        categories: widget.services.data.categories,
        store: widget.services.data.bookMap,
        times: widget.services.bookTimes?.times ?? const <String, int>{},
      );
    } on Object {
      // База не ответила: прежняя карта, если она была, остаётся на
      // экране; не было — сказано словами, с кнопкой «Повторить».
      failed = true;
    }
    if (!mounted || run != _run) {
      return;
    }
    setState(() {
      _galaxy = galaxy ?? _galaxy;
      _failed = failed && _galaxy == null;
    });
  }

  /// Открывает книгу в чтении — тем же экраном, что полка.
  Future<void> _openBook(Book book) async {
    // BUG-47: сообщение полки («убрана с полки · Вернуть») не ложится
    // на страницу — как и при открытии книги с самой полки.
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
    widget.onReading?.call(true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => ReaderScreen(
            book: book,
            services: widget.services,
            canRelink: widget.canRelink,
            models: widget.models,
            // SNO-F-REC-02: журнал записи пишет, каким путём открыли.
            openedVia: 'galaxy',
          ),
        ),
      );
    } finally {
      // SNO-F-REC-02: закрытие книги — раньше перехода в раздел.
      widget.services.recording?.bookClosed();
      widget.onReading?.call(false);
      // Время в книге выросло: размер её точки считается заново. Карта
      // при этом остаётся там, где читатель её оставил.
      if (mounted) {
        unawaited(_load());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(sectionTitle(AppSection.galaxy))),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final ShelfReading? reading = _reading;
    final ShelfReadingProgress? progress = reading?.progress;
    if (progress != null && progress.busy) {
      // Карта считается по тексту всех книг: пока он читается, прежняя
      // карта устарела, а новой ещё нет.
      return _Notice(
        key: const Key('galaxy-preparing'),
        icon: Icons.hourglass_empty,
        lines: describeGalaxyPreparing(progress),
        share: shelfReadingShare(progress),
      );
    }
    if (_failed) {
      return _Notice(
        key: const Key('galaxy-failed'),
        icon: Icons.error_outline,
        lines: const <String>['Карта не открылась.'],
        action: 'Повторить',
        onAction: () => unawaited(_load()),
      );
    }
    final Galaxy? galaxy = _galaxy;
    if (galaxy == null) {
      // Раздел ещё не открывали или карта читается: доли секунды.
      return const SizedBox.expand(key: Key('galaxy-loading'));
    }
    switch (galaxy.status) {
      case GalaxyStatus.tooFew:
        return _Notice(
          key: const Key('galaxy-too-few'),
          icon: Icons.auto_awesome_outlined,
          lines: describeTooFew(galaxy.books),
        );
      case GalaxyStatus.noMap:
        return _Notice(
          key: const Key('galaxy-no-map'),
          icon: Icons.auto_awesome_outlined,
          lines: const <String>[
            'Карта ещё не посчитана.',
            'Она складывается из текста книг полки.',
          ],
          action: reading == null ? null : 'Посчитать карту',
          onAction: reading?.start,
        );
      case GalaxyStatus.ready:
        return Column(
          children: <Widget>[
            Expanded(
              child: GalaxyMap(
                stars: galaxy.stars,
                covers: widget.services.covers,
                reading: widget.services.data.reading,
                onOpen: (Book book) => unawaited(_openBook(book)),
              ),
            ),
            if (galaxy.missing > 0)
              _MissingStrip(
                key: const Key('galaxy-missing'),
                missing: galaxy.missing,
              ),
          ],
        );
    }
  }
}

/// Что сказано в разделе, пока книги готовятся (F-MAP-11).
List<String> describeGalaxyPreparing(ShelfReadingProgress progress) {
  return switch (progress.phase) {
    ShelfReadingPhase.reading => <String>[
      'Книги ещё читаются · ${progress.booksDone} из '
          '${progress.booksTotal}',
      'Карта появится, когда будут прочитаны все.',
    ],
    ShelfReadingPhase.held => <String>[
      'Чтение книг приостановлено · ${progress.booksDone} из '
          '${progress.booksTotal}',
      'Карта появится, когда будут прочитаны все.',
    ],
    ShelfReadingPhase.mapping => <String>[
      progress.mapTotal > 0
          ? 'Считаю карту · ${progress.mapDone} из ${progress.mapTotal}'
          : 'Считаю карту',
    ],
    ShelfReadingPhase.idle || ShelfReadingPhase.done => const <String>[],
  };
}

/// Что сказано, когда книг для карты мало (F-MAP-11): [books] — сколько
/// их на полке.
List<String> describeTooFew(int books) {
  return <String>[
    'Для карты нужно не меньше $kMinMapBooks книг.',
    books == 0 ? 'На полке книг нет.' : 'Сейчас на полке: $books.',
  ];
}

/// Сколько времени провели в книге — словами для карточки; пусто —
/// книгу не открывали.
String describeReadTime(int ms) {
  if (ms <= 0) {
    return '';
  }
  final int minutes = ms ~/ 60000;
  if (minutes < 1) {
    return 'читали меньше минуты';
  }
  if (minutes < 60) {
    return 'читали $minutes мин';
  }
  return 'читали ${minutes ~/ 60} ч ${minutes % 60} мин';
}

/// Слова посреди раздела вместо карты.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.lines,
    this.share,
    this.action,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final List<String> lines;

  /// Какая доля подготовки позади; `null` — полосы хода нет.
  final double? share;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? done = share;
    final String? label = action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: theme.colorScheme.onSurface),
              const SizedBox(height: 12),
              for (int i = 0; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    lines[i],
                    textAlign: TextAlign.center,
                    style: i == 0
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium,
                  ),
                ),
              if (done != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: done),
                ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton(
                    key: const Key('galaxy-action'),
                    onPressed: onAction,
                    child: Text(label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка под картой: каких книг на ней нет.
class _MissingStrip extends StatelessWidget {
  const _MissingStrip({required this.missing, super.key});

  final int missing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Книг без места на карте: $missing. Место они получат при '
                'следующей подготовке книг.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Полотно карты: точки, подписи, жесты и карточка выбранной книги
/// (F-MAP-07, F-MAP-08).
///
/// Матрица своя, а не `InteractiveViewer` (ALG-MAP-13): подписи и
/// попадание считаются в том же кадре и по тем же числам, что точки, а
/// текст зумом не масштабируется. Жесты: перетаскивание двигает карту,
/// щипок и колесо мыши приближают к точке под пальцами или курсором,
/// нажатие по точке показывает карточку книги, нажатие мимо — убирает
/// её, двойное нажатие приближает вдвое.
class GalaxyMap extends StatefulWidget {
  /// Создаёт полотно.
  const GalaxyMap({
    required this.stars,
    required this.covers,
    required this.reading,
    required this.onOpen,
    this.nowMs,
    super.key,
  });

  /// Звёзды карты.
  final List<GalaxyStar> stars;

  /// Служба обложек — карточке книги.
  final CoverService covers;

  /// Места чтения — карточке книги: сколько прочитано.
  final ReadingRepository reading;

  /// Читатель нажал «Читать» в карточке.
  final ValueChanged<Book> onOpen;

  /// Часы для двойного нажатия, в миллисекундах; в тестах подменяются.
  final int Function()? nowMs;

  @override
  State<GalaxyMap> createState() => GalaxyMapState();
}

/// Состояние полотна карты. Открыто тестам: по окну карты они находят,
/// где на экране стоит книга.
class GalaxyMapState extends State<GalaxyMap> {
  static final Stopwatch _watch = Stopwatch()..start();

  late MapExtent _extent;
  late StarGrid _grid;
  MapCamera? _camera;
  Size _size = Size.zero;

  /// Выбранная книга — по идентификатору: звёзды могут прийти заново.
  String? _selectedId;
  double? _progress;

  // Щипок и перетаскивание: точка карты, взятая пальцами.
  double _grabX = 0;
  double _grabY = 0;
  double _grabScale = 1;

  // Двойное нажатие.
  int _tapAt = -kGalaxyDoubleTapMs * 2;
  Offset _tapPlace = Offset.zero;

  GalaxyScene? _scene;

  int _now() => (widget.nowMs ?? _monotonic)();

  static int _monotonic() => _watch.elapsedMilliseconds;

  /// Окно карты: пересчёт между картой и экраном.
  MapViewport get viewport {
    return MapViewport(
      width: _size.width,
      height: _size.height,
      extent: _extent,
      camera: _camera ?? MapCamera.home(_extent),
    );
  }

  /// Кадр, показанный последним; `null` — карта ещё не строилась.
  GalaxyScene? get scene => _scene;

  /// Выбранная книга; `null` — карточки нет.
  String? get selectedId => _selectedId;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(GalaxyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stars, widget.stars)) {
      _measure();
      final MapCamera? camera = _camera;
      if (camera != null) {
        // Карта пришла заново — читатель остаётся там же, насколько это
        // позволяет новый размах.
        _camera = clampCamera(camera, _extent);
      }
      final String? id = _selectedId;
      if (_selectedIndex() == null) {
        _selectedId = null;
        _progress = null;
      } else if (id != null) {
        // Карта пришла заново после чтения: прочитанное в карточке
        // выбранной книги могло вырасти.
        unawaited(_loadProgress(id));
      }
    }
  }

  @override
  void dispose() {
    _scene?.dispose();
    _scene = null;
    super.dispose();
  }

  void _measure() {
    final List<double> xs = <double>[
      for (final GalaxyStar star in widget.stars) star.x,
    ];
    final List<double> ys = <double>[
      for (final GalaxyStar star in widget.stars) star.y,
    ];
    _extent = MapExtent.of(xs, ys);
    _grid = StarGrid(xs, ys);
  }

  int? _selectedIndex() {
    final String? id = _selectedId;
    if (id == null) {
      return null;
    }
    for (int i = 0; i < widget.stars.length; i++) {
      if (widget.stars[i].book.id == id) {
        return i;
      }
    }
    return null;
  }

  /// По какой звезде попала точка экрана [at]; `null` — мимо
  /// (ALG-MAP-13).
  int? starAt(Offset at) {
    final GalaxyScene? scene = _scene;
    if (scene == null) {
      return null;
    }
    final MapViewport view = scene.viewport;
    return _grid.nearest(
      view.mapX(at.dx),
      view.mapY(at.dy),
      kHitRadius / view.unit,
      // Крупная точка ловит нажатие всей собой.
      reach: <double>[for (final double r in scene.radii) r / view.unit],
    );
  }

  void _tap(Offset at) {
    final int now = _now();
    final bool twice =
        now - _tapAt <= kGalaxyDoubleTapMs &&
        (at - _tapPlace).distance <= kGalaxyDoubleTapSlop;
    _tapAt = twice ? now - kGalaxyDoubleTapMs * 2 : now;
    _tapPlace = at;
    if (twice) {
      setState(() {
        _camera = viewport.zoomedAt(
          sx: at.dx,
          sy: at.dy,
          factor: kDoubleTapZoom,
        );
      });
      return;
    }
    final int? hit = starAt(at);
    final String? id = hit == null ? null : widget.stars[hit].book.id;
    if (id == _selectedId) {
      return;
    }
    setState(() {
      _selectedId = id;
      _progress = null;
    });
    if (id != null) {
      unawaited(_loadProgress(id));
    }
  }

  /// Читает, сколько книги прочитано, — карточке.
  Future<void> _loadProgress(String id) async {
    double? progress;
    try {
      progress = (await widget.reading.position(id))?.progress;
    } on Object {
      // Место чтения не прочиталось: карточка обходится без него.
      progress = null;
    }
    if (mounted && _selectedId == id) {
      setState(() => _progress = progress);
    }
  }

  void _scaleStart(ScaleStartDetails details) {
    final MapViewport view = viewport;
    _grabX = view.mapX(details.localFocalPoint.dx);
    _grabY = view.mapY(details.localFocalPoint.dy);
    _grabScale = view.camera.scale;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _camera = viewport.anchored(
        x: _grabX,
        y: _grabY,
        sx: details.localFocalPoint.dx,
        sy: details.localFocalPoint.dy,
        scale: _grabScale * details.scale,
      );
    });
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }
    // Один щелчок колеса — около сотни точек прокрутки: приближение
    // примерно в 1,4 раза.
    final double factor = math.exp(-event.scrollDelta.dy / 300);
    setState(() {
      _camera = viewport.zoomedAt(
        sx: event.localPosition.dx,
        sy: event.localPosition.dy,
        factor: factor,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = AppPaletteScope.of(context);
    final Color ink = Color(palette.text);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _size = constraints.biggest;
        final int? selected = _selectedIndex();
        final GalaxyScene scene = GalaxyScene(
          stars: widget.stars,
          viewport: viewport,
          palette: palette,
          // Подписи — основным цветом текста: под ночной красной темой
          // оттенки сходятся в один, а текст остаётся читаемым.
          groupStyle: (theme.textTheme.titleSmall ?? const TextStyle())
              .copyWith(color: ink, fontWeight: FontWeight.w600),
          titleStyle: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: ink,
          ),
          textScaler: MediaQuery.textScalerOf(context),
          selected: selected,
        );
        // Прежний кадр сменён: полотно получает нового художника в
        // этом же построении, и старый текст подписей рисовать некому.
        final GalaxyScene? previous = _scene;
        _scene = scene;
        previous?.dispose();
        return ColoredBox(
          color: Color(palette.background),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Listener(
                  onPointerSignal: _signal,
                  child: GestureDetector(
                    key: const Key('galaxy-map'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (TapUpDetails details) =>
                        _tap(details.localPosition),
                    onScaleStart: _scaleStart,
                    onScaleUpdate: _scaleUpdate,
                    child: Semantics(
                      label: 'Карта книг: ${widget.stars.length}',
                      child: CustomPaint(
                        painter: GalaxyPainter(scene),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
              if (selected != null)
                _placeCard(scene, selected, constraints.biggest),
            ],
          ),
        );
      },
    );
  }

  /// Ставит карточку выбранной книги: на узком экране — у нижнего
  /// края во всю ширину, на окне от [kTopNavWidth] точек — рядом с
  /// точкой, с той стороны, где есть место (кадр SCR-04.3).
  Widget _placeCard(GalaxyScene scene, int selected, Size size) {
    final GalaxyStar star = widget.stars[selected];
    final Widget card = GalaxyBookCard(
      key: Key('galaxy-card-${star.book.id}'),
      star: star,
      covers: widget.covers,
      progress: _progress,
      onRead: () => widget.onOpen(star.book),
      onClose: () => setState(() {
        _selectedId = null;
        _progress = null;
      }),
    );
    if (navPlacementFor(size.width) == NavPlacement.bottom) {
      return Positioned(left: 8, right: 8, bottom: 8, child: card);
    }
    final Offset at = scene.placeOf(selected);
    final double r = scene.radii[selected];
    const double gap = 12;
    const double edge = 8;
    final bool fitsRight =
        at.dx + r + gap + kGalaxyCardWidth + edge <= size.width;
    final double wantedLeft = fitsRight
        ? at.dx + r + gap
        : at.dx - r - gap - kGalaxyCardWidth;
    final double left = wantedLeft
        .clamp(edge, math.max(edge, size.width - kGalaxyCardWidth - edge))
        .toDouble();
    // Высота карточки заранее не известна: сверху ей оставлено место по
    // оценке, а снизу её держит край окна.
    const double tall = 150;
    final double top = (at.dy - tall / 2)
        .clamp(edge, math.max(edge, size.height - tall - edge))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: kGalaxyCardWidth,
      child: card,
    );
  }
}

/// Карточка книги у звезды (F-MAP-08, кадр SCR-04.3): обложка,
/// название, автор и группа, сколько прочитано и сколько времени в
/// книге провели, кнопка «Читать».
class GalaxyBookCard extends StatelessWidget {
  /// Создаёт карточку.
  const GalaxyBookCard({
    required this.star,
    required this.covers,
    required this.progress,
    required this.onRead,
    required this.onClose,
    super.key,
  });

  /// Звезда, о которой карточка.
  final GalaxyStar star;

  /// Служба обложек.
  final CoverService covers;

  /// Доля прочитанного, от 0 до 1; `null` — не известна.
  final double? progress;

  /// «Читать».
  final VoidCallback onRead;

  /// Закрыть карточку.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Book book = star.book;
    final String? author = book.author;
    final double? read = progress;
    final String time = describeReadTime(star.ms);
    final List<String> facts = <String>[
      if (read != null && read > 0) 'прочитано ${(read * 100).round()} %',
      if (time.isNotEmpty) time,
    ];
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 56,
              height: 80,
              child: _CardCover(book: book, covers: covers),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    book.title,
                    key: const Key('galaxy-card-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (author != null && author.isNotEmpty) author,
                      star.group,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (facts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        facts.join(' · '),
                        key: const Key('galaxy-card-facts'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('galaxy-read'),
                      onPressed: onRead,
                      child: const Text('Читать'),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('galaxy-card-close'),
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Закрыть',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Обложка в карточке. Пока её нет — и навсегда, если книга не
/// открылась, — на её месте значок книги, а не пустая заливка.
class _CardCover extends StatelessWidget {
  const _CardCover({required this.book, required this.covers});

  final Book book;
  final CoverService covers;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          size: 24,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: FutureBuilder<String?>(
        future: covers.coverFor(book),
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String? path = snapshot.data;
          if (path == null) {
            return placeholder;
          }
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stack,
            ) => placeholder,
          );
        },
      ),
    );
  }
}
