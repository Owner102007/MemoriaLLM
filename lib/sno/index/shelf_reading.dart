import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../application/map/map_builder.dart';
import '../../application/reading/book_text.dart';
import '../../domain/library/book.dart';
import '../../domain/reading/page_text.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/settings/app_settings.dart';
import '../recording/device_status.dart';
import '../settings_keys.dart';

/// Через сколько после запуска приложения начинается проход по полке.
///
/// Первые секунды движок PDF занят тем, что видно: обложками полки.
const Duration kShelfReadingDelay = Duration(seconds: 2);

/// Раз во сколько страниц проход сообщает о себе экрану.
const int kShelfReadingNotifyEvery = 8;

/// Что сейчас делает подготовка книг.
enum ShelfReadingPhase {
  /// Ничего: подготовку не начинали или она не нужна.
  idle,

  /// Читает текст книг.
  reading,

  /// Стоит: открыта книга, движок PDF отдан ей.
  held,

  /// Считает карту.
  mapping,

  /// Закончена: текст прочитан, карта посчитана или не нужна.
  done,
}

/// Ход подготовки книг — для полоски на полке и раздела «Тестирование».
@immutable
class ShelfReadingProgress {
  /// Создаёт ход.
  const ShelfReadingProgress({
    this.phase = ShelfReadingPhase.idle,
    this.booksDone = 0,
    this.booksTotal = 0,
    this.title = '',
    this.page = 0,
    this.pages = 0,
    this.mapDone = 0,
    this.mapTotal = 0,
    this.elapsedMs = 0,
  });

  /// Что сейчас делается.
  final ShelfReadingPhase phase;

  /// Сколько книг прочитано.
  final int booksDone;

  /// Сколько книг на полке.
  final int booksTotal;

  /// Какая книга читается; пусто — никакая.
  final String title;

  /// Какая страница книги читается.
  final int page;

  /// Сколько в книге страниц.
  final int pages;

  /// Сколько книг разобрано для карты.
  final int mapDone;

  /// Сколько книг разбирается для карты.
  final int mapTotal;

  /// Сколько миллисекунд идёт чтение в этот раз, без простоев.
  final int elapsedMs;

  /// Идёт ли подготовка: есть что показать полоской.
  bool get busy =>
      phase == ShelfReadingPhase.reading ||
      phase == ShelfReadingPhase.held ||
      phase == ShelfReadingPhase.mapping;

  /// Копия с изменёнными полями.
  ShelfReadingProgress copyWith({
    ShelfReadingPhase? phase,
    int? booksDone,
    int? booksTotal,
    String? title,
    int? page,
    int? pages,
    int? mapDone,
    int? mapTotal,
    int? elapsedMs,
  }) {
    return ShelfReadingProgress(
      phase: phase ?? this.phase,
      booksDone: booksDone ?? this.booksDone,
      booksTotal: booksTotal ?? this.booksTotal,
      title: title ?? this.title,
      page: page ?? this.page,
      pages: pages ?? this.pages,
      mapDone: mapDone ?? this.mapDone,
      mapTotal: mapTotal ?? this.mapTotal,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}

/// Что вышло с картой — для итога подготовки.
@immutable
class MapSummary {
  /// Создаёт итог карты.
  const MapSummary({
    required this.state,
    this.books = 0,
    this.groups = 0,
    this.ms = 0,
    this.fingerprint = '',
  });

  /// Читает итог из JSON; `null` — запись не разобрать.
  static MapSummary? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final Object? state = json['state'];
    if (state is! String) {
      return null;
    }
    final Object? fingerprint = json['fingerprint'];
    return MapSummary(
      state: state,
      books: _int(json['books']),
      groups: _int(json['groups']),
      ms: _int(json['ms']),
      fingerprint: fingerprint is String ? fingerprint : '',
    );
  }

  /// Карта посчитана.
  static const String built = 'built';

  /// Книг слишком мало: карты нет.
  static const String tooFew = 'too_few';

  /// Книг слишком много: карты нет.
  static const String tooMany = 'too_many';

  /// Расчёт не удался.
  static const String failed = 'failed';

  /// Чем кончился расчёт: [built], [tooFew], [tooMany] или [failed].
  final String state;

  /// Сколько книг на карте.
  final int books;

  /// Сколько групп на карте.
  final int groups;

  /// Сколько миллисекунд занял расчёт; ноль — карта лежала готовой.
  final int ms;

  /// Отпечаток карты.
  final String fingerprint;

  /// Запись для JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'state': state,
    'books': books,
    'groups': groups,
    'ms': ms,
    'fingerprint': fingerprint,
  };
}

/// Итог подготовки книг полки (SNO-F-IDX-04): лежит в настройках и
/// переживает перезапуск и сброс к эталону.
@immutable
class ShelfIndexSummary {
  /// Создаёт итог.
  const ShelfIndexSummary({
    this.complete = false,
    this.books = 0,
    this.pages = 0,
    this.scans = 0,
    this.unread = const <String>[],
    this.readMs = 0,
    this.map,
  });

  /// Читает итог из записи настроек; `null` — записи нет или она не
  /// разбирается: тогда итога просто нет, и подготовка пройдёт заново.
  static ShelfIndexSummary? decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['schema'] != schema) {
      return null;
    }
    final Object? unread = json['unread'];
    return ShelfIndexSummary(
      complete: json['complete'] == true,
      books: _int(json['books']),
      pages: _int(json['pages']),
      scans: _int(json['scans']),
      unread: <String>[
        if (unread is List<Object?>)
          for (final Object? title in unread)
            if (title is String) title,
      ],
      readMs: _int(json['read_ms']),
      map: MapSummary.fromJson(json['map']),
    );
  }

  /// Вид записи.
  static const String schema = 'sno2026-shelf-index/1';

  /// Дошёл ли проход до конца полки.
  final bool complete;

  /// Сколько книг на полке прочитано целиком.
  final int books;

  /// Сколько страниц запомнено у всех книг полки.
  final int pages;

  /// Сколько книг без текста — сканов.
  final int scans;

  /// Названия книг, которые не открылись или прочитаны не целиком.
  final List<String> unread;

  /// Сколько миллисекунд заняло чтение текста — по всем запускам, без
  /// простоев.
  final int readMs;

  /// Что вышло с картой; `null` — до карты дело ещё не дошло.
  final MapSummary? map;

  /// Копия с изменёнными полями.
  ShelfIndexSummary copyWith({
    bool? complete,
    int? books,
    int? pages,
    int? scans,
    List<String>? unread,
    int? readMs,
    MapSummary? map,
  }) {
    return ShelfIndexSummary(
      complete: complete ?? this.complete,
      books: books ?? this.books,
      pages: pages ?? this.pages,
      scans: scans ?? this.scans,
      unread: unread ?? this.unread,
      readMs: readMs ?? this.readMs,
      map: map ?? this.map,
    );
  }

  /// Запись для настроек.
  String encode() {
    return jsonEncode(<String, Object?>{
      'schema': schema,
      'complete': complete,
      'books': books,
      'pages': pages,
      'scans': scans,
      'unread': unread,
      'read_ms': readMs,
      'map': map?.toJson(),
    });
  }
}

int _int(Object? value) => value is int ? value : 0;

/// Что проход узнал об одной книге.
class _BookResult {
  const _BookResult({
    required this.pages,
    required this.complete,
    required this.blank,
    required this.fresh,
  });

  /// Сколько страниц книги запомнено.
  final int pages;

  /// Запомнена ли книга целиком.
  final bool complete;

  /// Нет ли в книге текста вовсе.
  final bool blank;

  /// Сколько страниц прочитано движком в этот раз.
  final int fresh;
}

/// Подготовка книг полки: текст всех книг и карта (SNO-F-IDX-04,
/// SNO-F-MAP-01, расхождение SNO-DIV-04).
///
/// В основном приложении текст книги запоминает открытая книга — от
/// места чтения вперёд. В ветви II литература известна заранее, а
/// сессия длится сорок минут: карта и поиск по содержимому обязаны
/// существовать до первого участника. Поэтому после раскладки архива —
/// и при каждом запуске, если что-то осталось, — книги полки читаются
/// по одной, тем же движком и в тот же кэш текста страниц, что у
/// открытой книги (`page_texts`), а когда прочитаны все, считается
/// карта (`MapBuilder`).
///
/// **Проход уступает читателю.** Движок PDF один на приложение: пока
/// открыта книга ([held]), проход стоит и свой файл закрывает, а когда
/// книгу закрыли — продолжает с того же места.
///
/// **Продолжение с места остановки** даёт сам кэш: страницы пишутся в
/// базу пачками, и прочитанное не перечитывается ни после паузы, ни
/// после перезапуска. Закрытое приложение теряет не больше пачки.
///
/// **Кэш — производное**: сбой базы или движка подготовку не роняет.
/// Книга, которая не открылась, названа в итоге; остальные читаются.
///
/// Проход идёт, только пока приложение открыто: службы переднего плана
/// у него нет. Пока он читает, экран не гаснет.
class ShelfReading extends ChangeNotifier {
  /// Создаёт подготовку.
  ///
  /// [nowMs] — часы, которые не идут назад; в тестах подменяются.
  /// [screenBusy] отвечает, держит ли экран включённым кто-то ещё
  /// (запись сессии): тогда подготовка экран не трогает вовсе.
  ShelfReading({
    required LibraryRepository library,
    required DocumentOpener opener,
    required PageTextRepository texts,
    required AppSettingsRepository settings,
    required MapBuilder map,
    DeviceStatus device = const NoDeviceStatus(),
    bool Function()? screenBusy,
    int Function()? nowMs,
    int textVersion = kPageTextVersion,
    int batch = kTextPassBatch,
  }) : _library = library,
       _opener = opener,
       _texts = texts,
       _settings = settings,
       _map = map,
       _device = device,
       _screenBusy = screenBusy,
       _nowMs = nowMs ?? _monotonicMs,
       _textVersion = textVersion,
       _batch = batch < 1 ? 1 : batch;

  static final Stopwatch _watch = Stopwatch()..start();

  static int _monotonicMs() => _watch.elapsedMilliseconds;

  final LibraryRepository _library;
  final DocumentOpener _opener;
  final PageTextRepository _texts;
  final AppSettingsRepository _settings;
  final MapBuilder _map;
  final DeviceStatus _device;
  final bool Function()? _screenBusy;
  final int Function() _nowMs;
  final int _textVersion;
  final int _batch;

  ShelfReadingProgress _progress = const ShelfReadingProgress();
  ShelfIndexSummary? _summary;
  Future<void>? _running;
  Timer? _delayed;
  bool _again = false;
  bool _held = false;
  bool _disposed = false;
  bool _screenKept = false;
  Completer<void>? _release;

  /// С какого мига идёт нынешний отрезок чтения; `null` — чтение стоит.
  int? _activeSince;

  /// Сколько миллисекунд чтения набралось в прежних отрезках.
  int _activeMs = 0;

  /// Ход подготовки.
  ShelfReadingProgress get progress => _progress;

  /// Итог подготовки; `null` — её ещё не было.
  ShelfIndexSummary? get summary => _summary;

  /// Стоит ли проход, потому что открыта книга.
  bool get held => _held;

  /// Книгу открыли (`true`) или закрыли (`false`).
  ///
  /// Открыли — проход дочитывает страницу, записывает прочитанное,
  /// закрывает свой файл и ждёт. Закрыли — продолжает.
  set held(bool value) {
    if (_held == value || _disposed) {
      return;
    }
    _held = value;
    if (!value) {
      final Completer<void>? release = _release;
      _release = null;
      release?.complete();
    }
  }

  /// Поднимает итог прежней подготовки из настроек.
  ///
  /// Запуск приложения от него не зависит: не прочитался — итога нет.
  Future<void> restore() async {
    try {
      _summary = ShelfIndexSummary.decode(
        await _settings.read(SnoSettingsKeys.shelfIndex),
      );
    } on Object {
      _summary = null;
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Начинает подготовку — или, если она идёт, просит пройти полку ещё
  /// раз, когда нынешний проход кончится: за это время на полку могли
  /// встать новые книги.
  ///
  /// [delay] откладывает начало: при запуске приложения первые секунды
  /// отданы полке.
  void start({Duration delay = Duration.zero}) {
    if (_disposed) {
      return;
    }
    if (_running != null) {
      _again = true;
      return;
    }
    if (delay > Duration.zero) {
      _delayed?.cancel();
      _delayed = Timer(delay, start);
      return;
    }
    _delayed?.cancel();
    _delayed = null;
    final Future<void> work = _run();
    _running = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_running, work)) {
          _running = null;
        }
      }),
    );
  }

  /// Ждёт конца идущей подготовки — для тестов.
  Future<void> settled() => _running ?? Future<void>.value();

  Future<void> _run() async {
    do {
      _again = false;
      try {
        await _round();
      } on Object {
        // Подготовка — производное: её отказ приложению не мешает.
        // Что успело записаться, лежит в кэше; остальное — в другой раз.
        _show(_progress.copyWith(phase: ShelfReadingPhase.idle));
      }
      await _keepScreen(false);
    } while (_again && !_disposed);
  }

  /// Один проход по полке и расчёт карты за ним.
  Future<void> _round() async {
    final List<Book> books = await _library.books();
    if (_disposed) {
      return;
    }
    _activeMs = 0;
    _activeSince = null;
    final ShelfIndexSummary before = _summary ?? const ShelfIndexSummary();
    _show(
      ShelfReadingProgress(
        phase: _held ? ShelfReadingPhase.held : ShelfReadingPhase.reading,
        booksTotal: books.length,
      ),
    );
    int complete = 0;
    int pages = 0;
    int scans = 0;
    int fresh = 0;
    final List<String> unread = <String>[];
    for (int i = 0; i < books.length; i++) {
      final Book book = books[i];
      final _BookResult? result = await _readBook(book, i, books.length);
      if (result == null) {
        // Подготовку сняли посреди книги: итог не меняется.
        return;
      }
      pages += result.pages;
      fresh += result.fresh;
      if (result.complete) {
        complete++;
        if (result.blank) {
          scans++;
        }
      } else {
        unread.add(book.title);
      }
      _show(_progress.copyWith(booksDone: i + 1, elapsedMs: _elapsed()));
      if (result.fresh > 0) {
        // Прочитанное движком стоит времени: сколько его ушло,
        // записывается после каждой книги — закрытое на середине
        // приложение счёт не теряет.
        await _remember(
          before.copyWith(complete: false, readMs: before.readMs + _elapsed()),
        );
      }
    }
    _pause();
    await _keepScreen(false);
    final int readMs = fresh > 0 ? before.readMs + _elapsed() : before.readMs;
    ShelfIndexSummary summary = ShelfIndexSummary(
      complete: true,
      books: complete,
      pages: pages,
      scans: scans,
      unread: unread,
      readMs: readMs,
      map: before.map,
    );
    await _remember(summary);
    if (_disposed) {
      return;
    }
    summary = summary.copyWith(map: await _buildMap(books.length, before.map));
    if (_disposed) {
      return;
    }
    await _remember(summary);
    _show(
      ShelfReadingProgress(
        phase: ShelfReadingPhase.done,
        booksDone: books.length,
        booksTotal: books.length,
        elapsedMs: _elapsed(),
      ),
    );
  }

  /// Считает карту, если лежащая устарела.
  Future<MapSummary> _buildMap(int books, MapSummary? before) async {
    _show(
      _progress.copyWith(
        phase: ShelfReadingPhase.mapping,
        title: '',
        mapDone: 0,
        mapTotal: books,
      ),
    );
    try {
      final MapPlan plan = await _map.plan();
      final MapOutcome? current = plan.current;
      if (current != null) {
        // Карта лежит готовой: время её расчёта известно только из
        // прежнего итога.
        return MapSummary(
          state: MapSummary.built,
          books: current.books,
          groups: current.groups,
          ms:
              before != null &&
                  before.state == MapSummary.built &&
                  before.fingerprint == current.fingerprint
              ? before.ms
              : 0,
          fingerprint: current.fingerprint,
        );
      }
      final int started = _nowMs();
      final MapOutcome outcome = await _map.build(
        plan,
        onProgress: (int done, int total) {
          _show(_progress.copyWith(mapDone: done, mapTotal: total));
        },
        stopped: () => _disposed,
      );
      final int ms = _nowMs() - started;
      return switch (outcome.kind) {
        MapOutcomeKind.built => MapSummary(
          state: MapSummary.built,
          books: outcome.books,
          groups: outcome.groups,
          ms: ms < 0 ? 0 : ms,
          fingerprint: outcome.fingerprint,
        ),
        MapOutcomeKind.tooFew => const MapSummary(state: MapSummary.tooFew),
        MapOutcomeKind.tooMany => const MapSummary(state: MapSummary.tooMany),
        MapOutcomeKind.stopped => const MapSummary(state: MapSummary.failed),
      };
    } on Object {
      // Карта не посчиталась или не записалась: текст книг на месте, и
      // расчёт повторится при следующем запуске.
      return const MapSummary(state: MapSummary.failed);
    }
  }

  /// Читает одну книгу; `null` — подготовку сняли.
  Future<_BookResult?> _readBook(Book book, int index, int total) async {
    final PageTextKey key = PageTextKey(
      bookId: book.id,
      fingerprint: book.fileHash,
      version: _textVersion,
    );
    final Map<int, int> cached = <int, int>{};
    try {
      cached.addAll(await _texts.cachedPages(key));
    } on Object {
      // База не ответила — кэш считается пустым, книга читается движком.
    }
    int? pageCount = book.pageCount;
    if (pageCount != null && pageCount > 0 && _covers(cached, pageCount)) {
      // Книга запомнена целиком: файл не открывается вовсе.
      return _resultOf(book, cached, pageCount, fresh: 0);
    }
    int fresh = 0;
    bool opened = false;
    bool waited = false;
    while (true) {
      if (!await _waitTurn()) {
        return null;
      }
      if (waited) {
        // Пока проход стоял, читатель мог открыть эту самую книгу, и её
        // страницы запомнил он: читать их движком второй раз незачем.
        try {
          cached.addAll(await _texts.cachedPages(key));
        } on Object {
          // База не ответила — остаётся то, что проход знал сам.
        }
      }
      _show(
        _progress.copyWith(
          phase: ShelfReadingPhase.reading,
          booksDone: index,
          booksTotal: total,
          title: book.title,
          // Страницы читаются по порядку: сколько запомнено — там проход
          // и стоит.
          page: cached.length,
          pages: pageCount ?? 0,
        ),
      );
      final ReaderDocument document;
      try {
        document = await _opener.open(book.source);
      } on Object {
        // Книга не открылась: она названа в итоге, проход идёт дальше.
        break;
      }
      opened = true;
      bool interrupted = false;
      final Map<int, String> batch = <int, String>{};
      try {
        final int count = document.pageCount;
        pageCount = count;
        _resume();
        await _keepScreen(true);
        for (int page = 1; page <= count; page++) {
          if (cached.containsKey(page)) {
            continue;
          }
          if (_held || _disposed) {
            interrupted = true;
            break;
          }
          try {
            batch[page] = await document.pageText(page);
            fresh++;
          } on Object {
            // Страница не прочиталась — «не знаю», а не «текста нет»:
            // она не запоминается, и книга остаётся прочитанной не вся.
          }
          if (batch.length >= _batch) {
            await _save(key, batch, cached);
          }
          if (page % kShelfReadingNotifyEvery == 0 || page == count) {
            _show(
              _progress.copyWith(
                page: page,
                pages: count,
                elapsedMs: _elapsed(),
              ),
            );
          }
        }
        await _save(key, batch, cached);
      } finally {
        try {
          await document.close();
        } on Object {
          // Файл не закрылся — это забота движка, проход идёт дальше.
        }
      }
      if (!interrupted) {
        break;
      }
      waited = true;
      _pause();
      await _keepScreen(false);
      if (_disposed) {
        return null;
      }
    }
    if (_disposed) {
      return null;
    }
    final int known = pageCount ?? 0;
    if (!opened || known <= 0) {
      return _BookResult(
        pages: cached.length,
        complete: false,
        blank: false,
        fresh: fresh,
      );
    }
    return _resultOf(book, cached, known, fresh: fresh);
  }

  _BookResult _resultOf(
    Book book,
    Map<int, int> cached,
    int pageCount, {
    required int fresh,
  }) {
    final bool complete = _covers(cached, pageCount);
    bool anyText = false;
    for (final int length in cached.values) {
      if (length > 0) {
        anyText = true;
        break;
      }
    }
    return _BookResult(
      pages: cached.length,
      complete: complete,
      // Скан — книга, прочитанная целиком, в которой нет ни знака, и
      // книга, которую сканом уже назвал импорт: у страницы из одних
      // пробелов длина не нулевая, и по длинам её от текста не отличить.
      blank: complete && (!anyText || book.hasTextLayer == false),
      fresh: fresh,
    );
  }

  /// Запомнены ли все страницы книги из [pageCount].
  static bool _covers(Map<int, int> cached, int pageCount) {
    if (cached.length < pageCount) {
      return false;
    }
    for (int page = 1; page <= pageCount; page++) {
      if (!cached.containsKey(page)) {
        return false;
      }
    }
    return true;
  }

  /// Записывает пачку прочитанных страниц.
  Future<void> _save(
    PageTextKey key,
    Map<int, String> batch,
    Map<int, int> cached,
  ) async {
    if (batch.isEmpty) {
      return;
    }
    try {
      await _texts.savePageTexts(key, Map<int, String>.of(batch));
      for (final MapEntry<int, String> entry in batch.entries) {
        // Длина — как её отдаст база при следующем запуске: вместе с
        // пробелами. Иначе одна и та же книга была бы сканом сегодня и
        // книгой с текстом завтра.
        cached[entry.key] = entry.value.length;
      }
    } on Object {
      // Не записалось — эти страницы прочитаются в другой раз.
    }
    batch.clear();
  }

  /// Ждёт, пока книгу закроют; `false` — подготовку сняли.
  Future<bool> _waitTurn() async {
    while (_held && !_disposed) {
      _pause();
      _show(_progress.copyWith(phase: ShelfReadingPhase.held));
      final Completer<void> release = _release ??= Completer<void>();
      await release.future;
    }
    return !_disposed;
  }

  void _resume() {
    _activeSince ??= _nowMs();
  }

  void _pause() {
    final int? since = _activeSince;
    if (since != null) {
      final int passed = _nowMs() - since;
      _activeMs += passed < 0 ? 0 : passed;
      _activeSince = null;
    }
  }

  int _elapsed() {
    final int? since = _activeSince;
    if (since == null) {
      return _activeMs;
    }
    final int passed = _nowMs() - since;
    return _activeMs + (passed < 0 ? 0 : passed);
  }

  /// Держит экран включённым, пока проход читает.
  Future<void> _keepScreen(bool on) async {
    if (_screenKept == on) {
      return;
    }
    // Экран уже держит запись сессии: ни включать, ни — главное —
    // отпускать его подготовка не вправе.
    if (_screenBusy?.call() ?? false) {
      _screenKept = false;
      return;
    }
    _screenKept = on;
    try {
      await _device.keepScreenOn(on);
    } on Object {
      // Экран может погаснуть; проход при этом идёт, пока его не
      // остановит система.
    }
  }

  Future<void> _remember(ShelfIndexSummary summary) async {
    _summary = summary;
    try {
      await _settings.write(SnoSettingsKeys.shelfIndex, summary.encode());
    } on Object {
      // Итог не записался — он посчитается заново при следующем запуске.
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _show(ShelfReadingProgress progress) {
    _progress = progress;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _delayed?.cancel();
    _delayed = null;
    final Completer<void>? release = _release;
    _release = null;
    release?.complete();
    super.dispose();
  }
}
