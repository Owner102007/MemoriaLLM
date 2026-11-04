import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../application/app_services.dart';
import '../../application/library/cover_service.dart';
import '../../application/map/galaxy.dart';
import '../../application/map/shelf_reading.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/map/map_layout.dart';
import '../../domain/map/map_trusted.dart';
import '../../domain/map/map_view.dart';
import '../../domain/navigation/sections.dart';
import '../../domain/reading/reading.dart';
import '../../domain/theme/app_palette.dart';
import '../../sno/recording/action_log.dart';
import '../../sno/recording/event.dart';
import '../../sno/recording/layout_frames.dart';
import '../../sno/recording/layout_probe.dart';
import '../../sno/recording/thinning.dart';
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

/// С каким запасом имя созвездия ловит нажатие, в логических пикселях.
const double kGalaxyLabelSlop = 8;

/// Сколько миллисекунд звёзды летят на новые места, когда карту
/// перестроили (F-MAP-04).
const int kGalaxyFlightMs = 700;

/// Раздел «Галактика»: книги полки картой (F-MAP-06, SNO-F-MAP-01,
/// экран SCR-04).
///
/// Книга — точка; близкие по содержанию книги стоят рядом, книги одного
/// созвездия — одной группой под его именем; нажатие на имя — список
/// книг созвездия от типичной к особенной (F-MAP-17). Карту здесь не
/// считают: места книг посчитаны подготовкой книг
/// (`application/map/shelf_reading.dart`) и лежат на устройстве. Пока
/// карты нет или книг для неё мало, раздел говорит об этом словами
/// (F-MAP-11) — пустого поля читатель не видит никогда.
///
/// Раздел есть в основном приложении (S59) и в сборке ветви II СНО2026.
/// Признак сборки сюда приходит одним [mainApp]: в ветви II раздел
/// ведёт себя, как вёл в исследовании.
class GalaxyScreen extends StatefulWidget {
  /// Создаёт раздел.
  const GalaxyScreen({
    required this.services,
    this.visible = true,
    this.onReading,
    this.canRelink = true,
    this.models = true,
    this.ribbon = true,
    this.mainApp = false,
    super.key,
  });

  /// Основное приложение (`true`) или ветвь II СНО2026 (F-MAP-06, S59).
  ///
  /// В основном приложении книги встают на полку когда угодно, и раздел
  /// ведёт себя иначе: открытый — проверяет, всё ли прочитано, и при
  /// нужде запускает подготовку книг; пока она идёт, прежняя карта стоит
  /// на месте, ход — строкой под ней, с кнопкой «Остановить»; имена
  /// созвездий нажимаются. В ветви II полку раскладывает архив, и на
  /// время подготовки карта прячется — как в записях исследования.
  final bool mainApp;

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

  /// Есть ли у экрана чтения способ листания «Лента» (SNO-F-READ-02).
  final bool ribbon;

  @override
  State<GalaxyScreen> createState() => _GalaxyScreenState();
}

class _GalaxyScreenState extends State<GalaxyScreen> {
  Galaxy? _galaxy;
  bool _failed = false;
  int _run = 0;
  bool _wasBusy = false;

  /// Фаза подготовки, которую экран видел последней.
  ShelfReadingPhase? _lastPhase;

  /// Раздел открыли, а журнал записи об этом ещё не знает: скажет,
  /// когда карта прочитается, — размеры точек считаются по ней
  /// (SNO-F-MAP-01).
  bool _sayOpen = false;

  /// Сколько раз раздел открывали: по новому номеру полотно карты
  /// пишет в журнал `galaxy.open`.
  int _opens = 0;

  ShelfReading? get _reading => widget.services.shelfReading;

  /// Журнал действий участника; `null` — в этой сборке записи нет.
  ActionLog? get _log => widget.services.recording;

  @override
  void initState() {
    super.initState();
    _reading?.addListener(_readingChanged);
    _wasBusy = _reading?.progress.busy ?? false;
    _lastPhase = _reading?.progress.phase;
    if (widget.visible) {
      _sayOpen = true;
      unawaited(_load());
      _prepare();
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
      _lastPhase = _reading?.progress.phase;
    }
    if (widget.visible && !oldWidget.visible) {
      _sayOpen = true;
      _prepare();
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

  /// Раздел открыли в основном приложении: карта читателю нужна, и это
  /// помнится (D-048); если на полке есть непрочитанное или карта
  /// устарела, подготовка книг начинается (F-MAP-06). Когда всё готово,
  /// проход только сверяется с базой и молчит. Остановленную читателем
  /// подготовку раздел сам не будит — для этого кнопка «Посчитать карту».
  void _prepare() {
    final ShelfReading? reading = _reading;
    if (!widget.mainApp || reading == null) {
      return;
    }
    reading.want();
    if (!reading.running) {
      reading.resume();
    }
  }

  /// Подготовка книг сдвинулась: ход на экране обновляется, а когда она
  /// кончилась — карта читается заново, она могла пересчитаться.
  void _readingChanged() {
    if (!mounted) {
      return;
    }
    final ShelfReadingProgress? progress = _reading?.progress;
    final bool busy = progress?.busy ?? false;
    final ShelfReadingPhase? phase = progress?.phase;
    // Основное приложение: проход кончился — и тогда, когда хода видно не
    // было (прошёл молча после «Остановить» и «Посчитать карту»): карта
    // могла пересчитаться.
    final bool finished =
        (_wasBusy && !busy) ||
        (widget.mainApp &&
            phase == ShelfReadingPhase.done &&
            _lastPhase != ShelfReadingPhase.done);
    final bool changed = busy != _wasBusy || phase != _lastPhase;
    _wasBusy = busy;
    _lastPhase = phase;
    if (widget.mainApp && !changed && !finished) {
      // Основное приложение: тик хода рисуют сами строка и надпись
      // (`ListenableBuilder`) — карта на каждую страницу не
      // перестраивается (вторая пара глаз S59).
      return;
    }
    setState(() {
      if (finished && widget.visible && !widget.mainApp) {
        // Ветвь II: прежняя карта посчитана до этой подготовки — на тот
        // кадр, пока читается новая, её на экране нет, и в журнал записи
        // она не попадает. В основном приложении прежняя карта стоит,
        // пока не прочитается новая: экран не мигает.
        _galaxy = null;
      }
    });
    if (finished && widget.visible) {
      // Карта появится на глазах у участника: для журнала это то же,
      // что открытый раздел.
      _sayOpen = true;
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
    final bool opening = _sayOpen && widget.visible;
    setState(() {
      _galaxy = galaxy ?? _galaxy;
      _failed = failed && _galaxy == null;
      if (opening) {
        _sayOpen = false;
        _opens++;
      }
    });
    if (opening) {
      _sayEmpty();
    }
  }

  /// Какие слова стоят в разделе вместо карты; `null` — карта на
  /// экране либо раздел ещё читает её.
  String? _emptyState() {
    if (_busy && !widget.mainApp) {
      return 'preparing';
    }
    if (_failed) {
      return 'failed';
    }
    return switch (_galaxy?.status) {
      GalaxyStatus.tooFew => 'too_few',
      GalaxyStatus.noMap => _busy ? 'preparing' : 'no_map',
      GalaxyStatus.ready || null => null,
    };
  }

  /// Идёт ли подготовка книг.
  bool get _busy => _reading?.progress.busy ?? false;

  /// SNO-F-MAP-01: раздел открыли, а карты в нём нет — в журнале
  /// записи сказано, что участник увидел вместо неё. Карту на экране
  /// называет само полотно (`galaxy.open`).
  void _sayEmpty() {
    final ActionLog? log = _log;
    final String? state = _emptyState();
    if (log == null || !log.recording || state == null) {
      return;
    }
    final ShelfReadingProgress? progress = _reading?.progress;
    log.log(
      SnoEventType.galaxyEmpty,
      data: <String, Object?>{
        'state': state,
        'books': _galaxy?.books,
        if (state == 'preparing' && progress != null) ...<String, Object?>{
          'phase': progress.phase.name,
          'books_done': progress.booksDone,
          'books_total': progress.booksTotal,
        },
      },
    );
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
            // SNO-F-READ-02: в ветви ленты нет.
            ribbon: widget.ribbon,
            // SNO-F-REC-02: журнал записи пишет, каким путём открыли.
            openedVia: 'galaxy',
          ),
        ),
      );
    } finally {
      // SNO-F-REC-02: закрытие книги — раньше перехода в раздел.
      // SNO-F-MAP-01: с ним — сколько книгу читали на виду.
      widget.services.recording?.bookClosed(
        data:
            widget.services.bookTimes?.closingFacts(book.id) ??
            const <String, Object?>{},
      );
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
    // SNO-F-REC-03: раздел — зона кадра раскладки; что в нём сейчас
    // показано вместо карты или вместе с ней — в её сведениях.
    return LayoutProbe(
      kind: LayoutKind.screen,
      id: 'galaxy',
      info: () => <String, Object?>{'shows': _shows},
      child: Scaffold(
        appBar: AppBar(
          title: Text(sectionTitle(AppSection.galaxy)),
          actions: <Widget>[
            // F-MAP-04: полный пересчёт — только по просьбе читателя.
            if (_canRebuild)
              // Словом, а не значком: значок «пересчитать» читается как
              // «обновить» или «копировать» (самопроверка S60).
              TextButton.icon(
                key: const Key('galaxy-rebuild'),
                onPressed: _rebuild,
                icon: const Icon(Icons.refresh),
                label: const Text('Перестроить'),
              ),
          ],
        ),
        body: _body(context),
      ),
    );
  }

  /// Можно ли сейчас перестроить карту (F-MAP-04): основное приложение,
  /// карта на экране, подготовка книг не идёт.
  bool get _canRebuild =>
      widget.mainApp &&
      _reading != null &&
      !(_reading?.progress.busy ?? false) &&
      _galaxy?.status == GalaxyStatus.ready;

  /// «Перестроить» (F-MAP-04, D-049): карта считается заново; когда
  /// посчитается, звёзды перелетят на новые места.
  void _rebuild() {
    _reading?.rebuild();
  }

  /// Что раздел показывает: карту или слова вместо неё — то же
  /// ветвление, что в [_body].
  String get _shows {
    if (_busy && !widget.mainApp) {
      return 'preparing';
    }
    if (_failed) {
      return 'failed';
    }
    final Galaxy? galaxy = _galaxy;
    if (galaxy == null) {
      return 'loading';
    }
    return switch (galaxy.status) {
      GalaxyStatus.tooFew => 'too_few',
      GalaxyStatus.noMap => _busy ? 'preparing' : 'no_map',
      GalaxyStatus.ready => 'map',
    };
  }

  Widget _body(BuildContext context) {
    final ShelfReading? reading = _reading;
    final ShelfReadingProgress? progress = reading?.progress;
    final bool busy = progress != null && progress.busy;
    if (busy && !widget.mainApp) {
      // Ветвь II: карта считается по тексту всех книг — пока он
      // читается, прежняя карта устарела, а новой ещё нет.
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
        if (busy && reading != null) {
          // Основное приложение, карты ещё нет: ход подготовки и
          // «Остановить» (F-MAP-11). Прочитанное не теряется.
          return ListenableBuilder(
            listenable: reading,
            builder: (BuildContext context, Widget? child) => _Notice(
              key: const Key('galaxy-preparing'),
              icon: Icons.hourglass_empty,
              lines: describeGalaxyPreparing(reading.progress),
              share: shelfReadingShare(reading.progress),
              action: 'Остановить',
              onAction: reading.stop,
            ),
          );
        }
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
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GalaxyMap(
                      stars: galaxy.stars,
                      covers: widget.services.covers,
                      reading: widget.services.data.reading,
                      onOpen: (Book book) => unawaited(_openBook(book)),
                      log: _log,
                      opened: _opens,
                      constellations: widget.mainApp
                          ? galaxy.constellations
                          : const <String, List<GalaxyStar>>{},
                    ),
                  ),
                  // Строка хода — поверх нижнего края карты, а не под ней:
                  // карта не меняет высоту, когда строка появляется.
                  if (busy && reading != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PreparingStrip(
                        key: const Key('galaxy-preparing-strip'),
                        reading: reading,
                      ),
                    ),
                ],
              ),
            ),
            if (!busy && galaxy.missing > 0)
              _MissingStrip(
                key: const Key('galaxy-missing'),
                missing: galaxy.missing,
                // Основное приложение: дочитать книги без места можно
                // сразу — и после «Остановить».
                onRead: widget.mainApp ? reading?.start : null,
              )
            else if (!busy &&
                widget.mainApp &&
                reading != null &&
                galaxy.seated > 0)
              // F-MAP-11, F-MAP-04: книги досажены к карте — своё
              // созвездие они получат при «Перестроить».
              _SeatedStrip(
                key: const Key('galaxy-seated'),
                seated: galaxy.seated,
                onRebuild: _rebuild,
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

/// Почему книга без созвездия — словами для карточки (F-MAP-18); пусто
/// — причины нет.
String describeMapReason(MapReason reason) => switch (reason) {
  MapReason.none => '',
  MapReason.littleText => 'Мало надёжного текста',
  MapReason.unsure => 'Не уверены — поставьте сами',
  MapReason.awaiting => 'Новая книга — созвездие получит при «Перестроить»',
};

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

/// Строка под картой, пока книги готовятся (F-MAP-11, основное
/// приложение): что делается, полоса хода и «Остановить». Карта над ней
/// — прежняя: новая встанет, когда подготовка кончится.
class _PreparingStrip extends StatelessWidget {
  const _PreparingStrip({required this.reading, super.key});

  final ShelfReading reading;

  @override
  Widget build(BuildContext context) {
    // Ход меняется каждые несколько страниц: перерисовывается только эта
    // строка, а не карта над ней.
    return ListenableBuilder(
      listenable: reading,
      builder: (BuildContext context, Widget? child) =>
          _strip(context, reading.progress),
    );
  }

  Widget _strip(BuildContext context, ShelfReadingProgress progress) {
    final ThemeData theme = Theme.of(context);
    final VoidCallback onStop = reading.stop;
    final List<String> lines = describeGalaxyPreparing(progress);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lines.isEmpty ? '' : lines.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('galaxy-stop'),
                  onPressed: onStop,
                  child: const Text('Остановить'),
                ),
              ],
            ),
            LinearProgressIndicator(value: shelfReadingShare(progress)),
          ],
        ),
      ),
    );
  }
}

/// Строка под картой: каких книг на ней нет.
class _MissingStrip extends StatelessWidget {
  const _MissingStrip({required this.missing, this.onRead, super.key});

  final int missing;

  /// «Дочитать» — подготовка книг сейчас; `null` — кнопки нет.
  final VoidCallback? onRead;

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
            if (onRead case final VoidCallback read)
              TextButton(
                key: const Key('galaxy-missing-read'),
                onPressed: read,
                child: const Text('Дочитать'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Строка под картой: сколько книг досажено после полного расчёта
/// (F-MAP-11, F-MAP-04) и «Перестроить».
class _SeatedStrip extends StatelessWidget {
  const _SeatedStrip({
    required this.seated,
    required this.onRebuild,
    super.key,
  });

  final int seated;
  final VoidCallback onRebuild;

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
                describeSeated(seated),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              key: const Key('galaxy-seated-rebuild'),
              onPressed: onRebuild,
              child: const Text('Перестроить'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка о досаженных книгах (F-MAP-11): «Добавлено 2 книги — они
/// встали рядом с похожими».
String describeSeated(int books) =>
    'Добавлено ${_booksWord(books)} — '
    '${books == 1 ? 'она встала' : 'они встали'} рядом с похожими.';

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
    this.log,
    this.opened = 0,
    this.constellations = const <String, List<GalaxyStar>>{},
    super.key,
  });

  /// Книги созвездий от типичной к особенной — по имени созвездия
  /// (F-MAP-17, `Galaxy.constellations`). Нажатие на имя созвездия
  /// открывает его список; пусто — имена не нажимаются (ветвь II).
  final Map<String, List<GalaxyStar>> constellations;

  /// Журнал действий участника (SNO-F-MAP-01): что на карте, куда она
  /// смотрит, на какую точку нажали; `null` — записи в сборке нет.
  final ActionLog? log;

  /// Сколько раз раздел открывали. Новый номер — карту показали
  /// участнику заново: полотно пишет в журнал `galaxy.open`.
  final int opened;

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
class GalaxyMapState extends State<GalaxyMap>
    with SingleTickerProviderStateMixin {
  static final Stopwatch _watch = Stopwatch()..start();

  /// Перелёт звёзд на новые места (F-MAP-04): карту перестроили, и
  /// звезда летит от прежней точки к новой, а не прыгает.
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kGalaxyFlightMs),
  )..addListener(_flown);

  /// Откуда летит каждая звезда — по идентификатору книги; пусто —
  /// перелёта нет.
  Map<String, Offset> _from = const <String, Offset>{};

  late MapExtent _extent;
  late StarGrid _grid;
  MapCamera? _camera;
  Size _size = Size.zero;

  /// Выбранная книга — по идентификатору: звёзды могут прийти заново.
  String? _selectedId;
  double? _progress;

  /// Созвездие, чей список открыт (F-MAP-17); `null` — списка нет.
  String? _group;

  // Щипок и перетаскивание: точка карты, взятая пальцами.
  double _grabX = 0;
  double _grabY = 0;
  double _grabScale = 1;

  // Двойное нажатие.
  int _tapAt = -kGalaxyDoubleTapMs * 2;
  Offset _tapPlace = Offset.zero;

  GalaxyScene? _scene;

  /// О каком открытии раздела журнал записи уже знает.
  int _saidOpen = 0;

  /// Чем был жест, который сейчас двигает карту: щипок или перенос; и
  /// сдвинул ли он её вообще.
  bool _pinched = false;
  bool _dragged = false;

  /// Колесо мыши крутят щелчками, а журналу нужен ход, а не каждый
  /// щелчок: первое положение и то, на чём остановились.
  late final Thinned<String> _wheelSaid = Thinned<String>(_sayView);

  bool get _logging => widget.log?.recording ?? false;

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

  /// Созвездие, чей список открыт; `null` — списка нет.
  String? get openGroup => _group;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(GalaxyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stars, widget.stars)) {
      _takeOff(oldWidget.stars);
      _measure();
      final MapCamera? camera = _camera;
      if (camera != null) {
        // Карта пришла заново — читатель остаётся там же, насколько это
        // позволяет новый размах.
        _camera = clampCamera(camera, _extent);
      }
      final String? id = _selectedId;
      if (_selectedIndex() == null) {
        if (id != null) {
          // Выбранной книги на новой карте нет: карточка ушла сама.
          _sayCard(oldWidget.stars, id, open: false, by: 'map_changed');
        }
        _selectedId = null;
        _progress = null;
      } else if (id != null) {
        // Карта пришла заново после чтения: прочитанное в карточке
        // выбранной книги могло вырасти.
        unawaited(_loadProgress(id));
      }
    }
    if (_group != null && !widget.constellations.containsKey(_group)) {
      // Карта пересчиталась, и созвездия с этим именем больше нет.
      _group = null;
    }
  }

  /// Кадр перелёта: звёзды сдвинулись на шаг.
  void _flown() {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_flight.isCompleted) {
        _from = const <String, Offset>{};
      }
    });
  }

  /// Карта пришла заново: если звёзды, что были и раньше, стоят теперь
  /// в других местах (карту перестроили), они летят туда из прежних.
  /// Досадка старых звёзд не двигает — тогда и лететь некому. Если
  /// система просит меньше движения — звёзды встают на места сразу.
  void _takeOff(List<GalaxyStar> before) {
    final List<GalaxyStar> shown = _shown(before);
    final Map<String, Offset> from = <String, Offset>{
      for (final GalaxyStar star in shown) star.book.id: Offset(star.x, star.y),
    };
    bool moved = false;
    for (final GalaxyStar star in widget.stars) {
      final Offset? was = from[star.book.id];
      if (was != null && (was.dx != star.x || was.dy != star.y)) {
        moved = true;
        break;
      }
    }
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!moved || still) {
      _flight.stop();
      _from = const <String, Offset>{};
      return;
    }
    _from = from;
    _flight.forward(from: 0);
  }

  /// Звёзды, как они видны сейчас: в полёте — между прежним местом и
  /// новым; иначе — на местах [stars].
  List<GalaxyStar> _shown(List<GalaxyStar> stars) {
    if (_from.isEmpty || !_flight.isAnimating) {
      return stars;
    }
    final double t = Curves.easeInOut.transform(_flight.value);
    return <GalaxyStar>[
      for (final GalaxyStar star in stars)
        if (_from[star.book.id] case final Offset was)
          star.at(
            was.dx + (star.x - was.dx) * t,
            was.dy + (star.y - was.dy) * t,
          )
        else
          star,
    ];
  }

  /// Летят ли звёзды сейчас — для тестов.
  bool get flying => _from.isNotEmpty && _flight.isAnimating;

  @override
  void dispose() {
    _flight.dispose();
    _wheelSaid.dispose();
    _scene?.dispose();
    _scene = null;
    super.dispose();
  }

  /// Где полотно стоит в окне и куда смотрит — числами, по которым
  /// место нажатия из потока ввода переводится в координаты карты:
  /// `x = cx + (нажатие.x − left − w / 2) / unit`, по ординате так же
  /// (SNO-F-MAP-01).
  Map<String, Object?> _viewFacts() {
    final MapViewport view = viewport;
    final RenderObject? box = context.findRenderObject();
    final Offset? origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : null;
    return <String, Object?>{
      if (origin != null) 'left': origin.dx,
      if (origin != null) 'top': origin.dy,
      'w': _size.width,
      'h': _size.height,
      'scale': view.camera.scale,
      'cx': view.camera.cx,
      'cy': view.camera.cy,
      'unit': view.unit,
    };
  }

  /// SNO-F-MAP-01: карту показали участнику — в журнал записи ложится,
  /// сколько на ней точек, где каждая стоит и какого она размера.
  void _sayOpened() {
    final GalaxyScene? scene = _scene;
    if (!mounted || !_logging || scene == null) {
      return;
    }
    widget.log?.log(
      SnoEventType.galaxyOpen,
      data: <String, Object?>{
        ..._viewFacts(),
        'stars': widget.stars.length,
        'points': <Object?>[
          for (int i = 0; i < widget.stars.length; i++)
            <String, Object?>{
              'book': widget.stars[i].book.fileHash,
              'group': widget.stars[i].group,
              'x': widget.stars[i].x,
              'y': widget.stars[i].y,
              if (i < scene.radii.length) 'r': scene.radii[i],
              'ms': widget.stars[i].ms,
            },
        ],
      },
    );
  }

  /// Карту подвинули или приблизили: чем жест кончился.
  void _sayView(String cause) {
    if (!mounted || !_logging) {
      return;
    }
    widget.log?.log(
      SnoEventType.galaxyView,
      data: <String, Object?>{'cause': cause, ..._viewFacts()},
    );
  }

  /// Карточка книги [id] открылась или закрылась; [by] — чем закрыта.
  void _sayCard(
    List<GalaxyStar> stars,
    String id, {
    required bool open,
    String? by,
  }) {
    if (!_logging) {
      return;
    }
    widget.log?.log(
      open ? SnoEventType.galaxyCardOpen : SnoEventType.galaxyCardClose,
      data: <String, Object?>{
        'book': _hashOf(stars, id),
        if (by != null) 'by': by,
      },
    );
  }

  /// SNO-F-REC-03, шаг 31: камера карты для кадра раскладки — по ней
  /// точка зоны переводится в координаты карты:
  /// `x = cx + (точка.x − left − w / 2) / unit`, где `left` и `w` —
  /// место зоны в кадре.
  Map<String, Object?> _layoutInfo() {
    final MapViewport view = _scene?.viewport ?? viewport;
    return <String, Object?>{
      'map': <String, Object?>{
        'scale': layoutFine(view.camera.scale),
        'cx': layoutFine(view.camera.cx),
        'cy': layoutFine(view.camera.cy),
        'unit': layoutFine(view.unit),
      },
      'stars': widget.stars.length,
    };
  }

  /// SNO-F-REC-03, SNO-ALG-REC-02, шаг 31: звёзды для кадра раскладки
  /// — видимые, крупные первыми, не больше [kLayoutStarLimit]; места —
  /// на полотне, в окно их переводит слой записи.
  List<LayoutMark> _layoutMarks() {
    final GalaxyScene? scene = _scene;
    if (scene == null) {
      return const <LayoutMark>[];
    }
    final MapViewport view = scene.viewport;
    // Звёзды — того же кадра, что и радиусы: номера у них общие.
    final List<GalaxyStar> stars = scene.stars;
    final List<int> chosen = layoutStars(
      view: view,
      xs: <double>[for (final GalaxyStar star in stars) star.x],
      ys: <double>[for (final GalaxyStar star in stars) star.y],
      radii: scene.radii,
    );
    return <LayoutMark>[
      for (final int i in chosen)
        LayoutMark(
          id: stars[i].book.fileHash,
          x: view.screenX(stars[i].x),
          y: view.screenY(stars[i].y),
          r: scene.radii[i],
        ),
    ];
  }

  /// Отпечаток книги [id] — им книга названа во всём журнале записи.
  static String? _hashOf(List<GalaxyStar> stars, String id) {
    for (final GalaxyStar star in stars) {
      if (star.book.id == id) {
        return star.book.fileHash;
      }
    }
    return null;
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

  /// По имени какого созвездия попала точка экрана [at]; `null` — мимо
  /// или имена в этой сборке не нажимаются (F-MAP-17).
  ///
  /// Имя ловит нажатие с запасом в [kGalaxyLabelSlop] точек: подпись —
  /// строка мелкого текста, и попасть в неё пальцем трудно.
  String? groupAt(Offset at) {
    final GalaxyScene? scene = _scene;
    if (scene == null || widget.constellations.isEmpty) {
      return null;
    }
    for (final GalaxyLabel label in scene.labels) {
      if (label.group &&
          label.rect.inflate(kGalaxyLabelSlop).contains(at) &&
          widget.constellations.containsKey(label.text)) {
        return label.text;
      }
    }
    return null;
  }

  /// Звезда, в круг которой точно попала точка экрана [at]; `null` —
  /// ни в одну.
  int? _starUnder(Offset at) {
    final GalaxyScene? scene = _scene;
    if (scene == null) {
      return null;
    }
    for (int i = 0; i < widget.stars.length && i < scene.radii.length; i++) {
      if ((scene.placeOf(i) - at).distance <= scene.radii[i]) {
        return i;
      }
    }
    return null;
  }

  /// Открывает список созвездия [name] (F-MAP-17); карточка книги,
  /// если была, закрывается.
  void _openGroup(String name) {
    final String? before = _selectedId;
    setState(() {
      _group = name;
      _selectedId = null;
      _progress = null;
    });
    if (before != null) {
      _sayCard(widget.stars, before, open: false, by: 'group');
    }
  }

  /// Читатель выбрал книгу в списке созвездия: список уходит, у звезды
  /// открывается карточка книги — оттуда её читают.
  void _pickFromList(GalaxyStar star) {
    setState(() {
      _group = null;
      _selectedId = star.book.id;
      _progress = null;
    });
    _sayCard(widget.stars, star.book.id, open: true);
    unawaited(_loadProgress(star.book.id));
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
      _sayView('double_tap');
      return;
    }
    // Точное попадание в звезду важнее имени созвездия: имя стоит над
    // своими звёздами, и запас вокруг него не должен их закрывать.
    final int? exact = _starUnder(at);
    final String? name = exact == null ? groupAt(at) : null;
    if (name != null) {
      _openGroup(name);
      return;
    }
    if (_group != null) {
      // Нажатие по карте мимо имени только закрывает список созвездия.
      setState(() => _group = null);
      return;
    }
    final int? hit = exact ?? starAt(at);
    final String? id = hit == null ? null : widget.stars[hit].book.id;
    final String? before = _selectedId;
    if (hit != null && _logging) {
      // SNO-F-MAP-01: нажатие по точке — и тогда, когда её карточка
      // уже открыта. Нажатие мимо точек событием не пишется: в потоке
      // ввода оно остаётся без ссылки.
      widget.log?.log(
        SnoEventType.galaxyStar,
        data: <String, Object?>{
          'book': widget.stars[hit].book.fileHash,
          'selected': id == before,
        },
      );
    }
    if (id == before) {
      return;
    }
    setState(() {
      _selectedId = id;
      _progress = null;
    });
    if (before != null) {
      _sayCard(
        widget.stars,
        before,
        open: false,
        by: id == null ? 'tap_away' : 'other_star',
      );
    }
    if (id != null) {
      _sayCard(widget.stars, id, open: true);
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
    _pinched = false;
    _dragged = false;
  }

  void _scaleEnd(ScaleEndDetails details) {
    if (_dragged) {
      _sayView(_pinched ? 'pinch' : 'drag');
    }
    _dragged = false;
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    _dragged = true;
    if (details.pointerCount > 1 || details.scale != 1) {
      _pinched = true;
    }
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
    if (_logging) {
      _wheelSaid.add('wheel');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppPalette palette = AppPaletteScope.of(context);
    if (_saidOpen != widget.opened) {
      // Раздел открыли: после этого кадра, когда полотно знает своё
      // место в окне, журнал записи получает карту целиком.
      _saidOpen = widget.opened;
      if (_logging) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          _sayOpened();
        });
      }
    }
    final Color ink = Color(palette.text);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _size = constraints.biggest;
        final int? selected = _selectedIndex();
        final GalaxyScene scene = GalaxyScene(
          stars: _shown(widget.stars),
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
                // SNO-F-REC-03: полотно — зона кадра раскладки с камерой
                // и звёздами.
                child: LayoutProbe(
                  kind: LayoutKind.galaxyMap,
                  info: _layoutInfo,
                  marks: _layoutMarks,
                  child: Listener(
                    onPointerSignal: _signal,
                    child: GestureDetector(
                      key: const Key('galaxy-map'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) =>
                          _tap(details.localPosition),
                      onScaleStart: _scaleStart,
                      onScaleUpdate: _scaleUpdate,
                      onScaleEnd: _scaleEnd,
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
              ),
              if (selected != null)
                _placeCard(scene, selected, constraints.biggest),
              if (_group case final String group)
                _placeList(group, constraints.biggest),
            ],
          ),
        );
      },
    );
  }

  /// Ставит список созвездия [group]: на узком экране — у нижнего края
  /// во всю ширину, не выше половины карты; на окне от [kTopNavWidth]
  /// точек — у правого края во всю высоту (набросок SCR-04.9).
  Widget _placeList(String group, Size size) {
    final Widget list = GalaxyConstellationList(
      key: const Key('galaxy-list'),
      name: group,
      stars: widget.constellations[group] ?? const <GalaxyStar>[],
      onPick: _pickFromList,
      onClose: () => setState(() => _group = null),
    );
    if (navPlacementFor(size.width) == NavPlacement.bottom) {
      return Positioned(
        left: 8,
        right: 8,
        bottom: 8,
        height: math.max(
          0,
          math.min(size.height - 16, math.max(160, size.height / 2 - 8)),
        ),
        child: list,
      );
    }
    return Positioned(
      right: 8,
      top: 8,
      bottom: 8,
      width: kGalaxyCardWidth,
      child: list,
    );
  }

  /// Ставит карточку выбранной книги: на узком экране — у нижнего
  /// края во всю ширину, на окне от [kTopNavWidth] точек — рядом с
  /// точкой, с той стороны, где есть место (кадр SCR-04.3).
  Widget _placeCard(GalaxyScene scene, int selected, Size size) {
    final GalaxyStar star = widget.stars[selected];
    // SNO-F-REC-03: карточка — зона кадра раскладки поверх карты.
    final Widget card = LayoutProbe(
      kind: LayoutKind.galaxyCard,
      id: star.book.fileHash,
      child: GalaxyBookCard(
        key: Key('galaxy-card-${star.book.id}'),
        star: star,
        covers: widget.covers,
        progress: _progress,
        onRead: () => widget.onOpen(star.book),
        onClose: () {
          _sayCard(widget.stars, star.book.id, open: false, by: 'button');
          setState(() {
            _selectedId = null;
            _progress = null;
          });
        },
      ),
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

/// Список созвездия по нажатию на его имя (F-MAP-17, D-044): книги от
/// самой типичной — у неё больше всего общего с остальными книгами
/// созвездия — к самой особенной.
class GalaxyConstellationList extends StatelessWidget {
  /// Создаёт список.
  const GalaxyConstellationList({
    required this.name,
    required this.stars,
    required this.onPick,
    required this.onClose,
    super.key,
  });

  /// Имя созвездия.
  final String name;

  /// Книги созвездия — уже по порядку (`Galaxy.constellations`).
  final List<GalaxyStar> stars;

  /// Читатель выбрал книгу.
  final ValueChanged<GalaxyStar> onPick;

  /// Закрыть список.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        key: const Key('galaxy-list-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        name == kUncategorizedTitle
                            ? describeUncategorizedCount(stars.length)
                            : describeConstellationCount(stars.length),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('galaxy-list-close'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Закрыть',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: stars.length,
              itemBuilder: (BuildContext context, int i) {
                final GalaxyStar star = stars[i];
                final String? author = star.book.author;
                return ListTile(
                  key: Key('galaxy-list-${star.book.id}'),
                  dense: true,
                  title: Text(
                    star.book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: author == null || author.isEmpty
                      ? null
                      : Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => onPick(star),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка под именем созвездия: сколько в нём книг и в каком они
/// порядке — «6 книг · от типичной к особенной».
String describeConstellationCount(int books) =>
    '${_booksWord(books)} · от типичной к особенной';

/// Строка под «Без категории»: это не созвездие, и «типичной» книги у
/// него нет — сверху те, что ближе к середине карты этих книг.
String describeUncategorizedCount(int books) =>
    '${_booksWord(books)} · без созвездия';

/// «1 книга», «3 книги», «5 книг».
String _booksWord(int books) {
  final int last = books % 10;
  final int lastTwo = books % 100;
  final String word = lastTwo >= 11 && lastTwo <= 14
      ? 'книг'
      : last == 1
      ? 'книга'
      : last >= 2 && last <= 4
      ? 'книги'
      : 'книг';
  return '$books $word';
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
    final String reason = describeMapReason(star.reason);
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
                  // F-MAP-18: почему книга без созвездия — честно, словами.
                  if (reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        reason,
                        key: const Key('galaxy-card-reason'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
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
