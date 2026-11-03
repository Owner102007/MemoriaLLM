/// Подготовка книг полки для «Галактики»: текст всех книг и карта
/// (F-MAP-06, F-MAP-11; родом из ветви II — SNO-F-IDX-04).
///
/// Зачем. Карта складывается из текста книг, а текст книги в кэш
/// кладёт открытая книга — от места чтения вперёд. Книгу, которую не
/// открывали, карта знала бы только по названию. Подготовка читает
/// книги полки по одной в тот же кэш, а когда прочитаны все — считает
/// карту (`MapBuilder`).
///
/// Кто зовёт: `AppServices` создаёт, `main.dart` запускает после старта,
/// раздел «Галактика» показывает ход, «Остановить» и «Посчитать карту»;
/// оболочка (`ui/app.dart`) говорит, когда открыта книга
/// ([ShelfReading.held]).
///
/// До S59 файл жил в `lib/sno/index/` и работал только в сборке ветви II
/// СНО2026; перенесён в продукт по D-003 (см. учебную заметку S59).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/library/book.dart';
import '../../domain/reading/page_text.dart';
import '../../domain/reading/reader_document.dart';
import '../../domain/settings/app_settings.dart';
import '../reading/book_text.dart';
import 'map_builder.dart';

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

/// Ход подготовки книг — для раздела «Галактика», полоски на полке и
/// раздела «Тестирование» ветвей СНО2026.
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

/// Какая доля подготовки позади — для полосы хода; `null` — не узнать.
double? shelfReadingShare(ShelfReadingProgress progress) {
  switch (progress.phase) {
    case ShelfReadingPhase.reading:
    case ShelfReadingPhase.held:
      if (progress.booksTotal <= 0) {
        return null;
      }
      final double inBook = progress.pages > 0
          ? progress.page / progress.pages
          : 0.0;
      final double share = (progress.booksDone + inBook) / progress.booksTotal;
      return share.clamp(0, 1).toDouble();
    case ShelfReadingPhase.mapping:
      if (progress.mapTotal <= 0) {
        return null;
      }
      return (progress.mapDone / progress.mapTotal).clamp(0, 1).toDouble();
    case ShelfReadingPhase.idle:
    case ShelfReadingPhase.done:
      return null;
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

/// Подготовка книг полки: текст всех книг и карта (F-MAP-06,
/// SNO-F-IDX-04).
///
/// Открытая книга запоминает свой текст сама — от места чтения вперёд.
/// Карте нужен текст всех книг полки, поэтому при каждом запуске
/// приложения (и по «Посчитать карту») книги полки читаются по одной,
/// тем же движком и в тот же кэш текста страниц, что у открытой книги
/// (`page_texts`), а когда прочитаны все, считается карта (`MapBuilder`).
/// В ветви II СНО2026 так же — после раскладки архива: там карта обязана
/// существовать до первого участника.
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
/// **Когда делать нечего, подготовки не видно**: при обычном запуске
/// текст уже прочитан и карта посчитана — проход сверяет это с базой и
/// молчит, полоска над полкой не появляется.
///
/// **Читатель может остановить** подготовку ([stop]) — прочитанное
/// остаётся, следующий [start] продолжит.
///
/// **Когда начинать, решает [resume]** (D-048): в основном приложении —
/// только если «Галактику» хоть раз открывали ([want]) и читатель не
/// нажимал «Остановить»; и то и другое помнится после перезапуска. В
/// ветви II памяти нет: подготовка идёт всегда, как прежде.
///
/// Проход идёт, только пока приложение открыто: службы переднего плана
/// у него нет. Экран он держит, только если ему дали `keepScreenOn`
/// (ветвь II).
class ShelfReading extends ChangeNotifier {
  /// Создаёт подготовку.
  ///
  /// [nowMs] — часы, которые не идут назад; в тестах подменяются.
  /// [summaryKey] — под каким ключом настроек лежит итог: у ветвей
  /// СНО2026 он прежний, `sno.shelf_index`.
  /// [keepScreenOn] держит экран включённым, пока проход читает; `null`
  /// — экран не трогается (обычное приложение: читателю это разрядило
  /// бы телефон, а сорокаминутной записи ветви II — было нужно).
  /// [screenBusy] отвечает, держит ли экран включённым кто-то ещё
  /// (запись сессии): тогда подготовка экран не трогает вовсе.
  /// [openedKey] и [stoppedKey] — ключи настроек, где помнится, что
  /// «Галактику» открывали и что читатель нажал «Остановить» (D-048);
  /// `null` — не помнится: подготовка нужна всегда, а остановка — до
  /// перезапуска (ветвь II).
  ShelfReading({
    required LibraryRepository library,
    required DocumentOpener opener,
    required PageTextRepository texts,
    required AppSettingsRepository settings,
    required MapBuilder map,
    String summaryKey = SettingsKeys.shelfReading,
    Future<void> Function(bool on)? keepScreenOn,
    bool Function()? screenBusy,
    String? openedKey,
    String? stoppedKey,
    int Function()? nowMs,
    int textVersion = kPageTextVersion,
    int batch = kTextPassBatch,
  }) : _library = library,
       _opener = opener,
       _texts = texts,
       _settings = settings,
       _map = map,
       _summaryKey = summaryKey,
       _keepScreenOn = keepScreenOn,
       _screenBusy = screenBusy,
       _openedKey = openedKey,
       _stoppedKey = stoppedKey,
       // Помнить, открывали ли раздел, негде — значит, подготовка нужна.
       _wanted = openedKey == null,
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
  final String _summaryKey;
  final Future<void> Function(bool on)? _keepScreenOn;
  final bool Function()? _screenBusy;
  final String? _openedKey;
  final String? _stoppedKey;
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

  /// Подготовку остановил читатель ([stop]); снимается [start].
  bool _stopped = false;

  /// Нужна ли карта читателю: «Галактику» открывали ([want]).
  bool _wanted;
  bool _screenKept = false;
  Completer<void>? _release;

  /// С какого мига идёт нынешний отрезок чтения; `null` — чтение стоит.
  int? _activeSince;

  /// Сколько миллисекунд чтения набралось в прежних отрезках.
  int _activeMs = 0;

  /// Пора ли проходу кончать: подготовку выбросили или остановили.
  bool get _quit => _disposed || _stopped;

  /// Ход подготовки.
  ShelfReadingProgress get progress => _progress;

  /// Остановил ли подготовку читатель (F-MAP-11): до [start] она не идёт.
  bool get stopped => _stopped;

  /// Открывал ли читатель «Галактику» хоть раз (D-048): пока нет, [resume]
  /// подготовку не начинает.
  bool get wanted => _wanted;

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

  /// Поднимает из настроек итог прежней подготовки и память о том,
  /// открывали ли «Галактику» и нажимали ли «Остановить» (D-048).
  ///
  /// Запуск приложения от него не зависит: не прочитался итог — итога
  /// нет; не прочиталась память — раздел считается неоткрытым, а
  /// подготовка неостановленной.
  Future<void> restore() async {
    try {
      _summary = ShelfIndexSummary.decode(await _settings.read(_summaryKey));
    } on Object {
      _summary = null;
    }
    // `if (x case final String key)` — «если x не null, назови его key»:
    // сопоставление с образцом Dart 3.
    if (_openedKey case final String key) {
      _wanted = _wanted || await _flag(key);
    }
    if (_stoppedKey case final String key) {
      _stopped = _stopped || await _flag(key);
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
    if (_stopped) {
      // Читатель сам попросил продолжить: остановка снята и в настройках.
      _stopped = false;
      _setFlag(_stoppedKey, on: false);
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
    final Completer<void> done = Completer<void>();
    _running = done.future;
    unawaited(_run().whenComplete(done.complete));
  }

  /// Продолжает подготовку сама, без просьбы читателя (D-048): при
  /// запуске приложения, после добавления книг, при открытии
  /// «Галактики» — если карта читателю нужна ([wanted]) и он не нажимал
  /// «Остановить» ([stopped]). Иначе ничего не делает.
  void resume({Duration delay = Duration.zero}) {
    if (_disposed || !wanted || stopped) {
      return;
    }
    start(delay: delay);
  }

  /// Читатель открыл «Галактику» (D-048): карта ему нужна, и это
  /// помнится — со следующего запуска подготовка идёт сама.
  void want() {
    if (_disposed || _wanted) {
      return;
    }
    _wanted = true;
    _setFlag(_openedKey, on: true);
  }

  /// Идёт ли проход — и тогда, когда он молчит: сверяет готовые книги с
  /// базой, не показывая хода. Раздел «Галактика» по нему не будит
  /// подготовку второй раз подряд.
  bool get running => _running != null;

  /// Останавливает подготовку (F-MAP-11, «Остановить» в «Галактике»).
  ///
  /// Проход дочитывает страницу, записывает прочитанное и кончается;
  /// карта не считается. Прочитанное остаётся в кэше: [start] — кнопка
  /// «Посчитать карту» или «Дочитать» — продолжит с того же места.
  /// В основном приложении остановка помнится и после перезапуска
  /// (D-048); в ветви II — до перезапуска.
  void stop() {
    if (_disposed) {
      return;
    }
    if (!_stopped) {
      _setFlag(_stoppedKey, on: true);
    }
    _stopped = true;
    _again = false;
    _delayed?.cancel();
    _delayed = null;
    final Completer<void>? release = _release;
    _release = null;
    release?.complete();
    _show(const ShelfReadingProgress());
  }

  /// Читает отметку [key] из настроек: `true` — стоит; не прочиталась —
  /// не стоит.
  Future<bool> _flag(String key) async {
    try {
      return await _settings.read(key) == 'true';
    } on Object {
      return false;
    }
  }

  /// Ставит ([on]) или снимает отметку [key] в настройках, не дожидаясь
  /// записи; `null` — помнить негде. Сбой записи не мешает: забудется
  /// только память, а подготовка пойдёт как попросили.
  void _setFlag(String? key, {required bool on}) {
    if (key == null) {
      return;
    }
    unawaited(
      (on ? _settings.write(key, 'true') : _settings.remove(key)).catchError(
        (Object _) {},
      ),
    );
  }

  /// Ждёт конца идущей подготовки — для тестов.
  Future<void> settled() => _running ?? Future<void>.value();

  Future<void> _run() async {
    // Проход сам снимает отметку «идёт», и в том же шаге решает, нужен ли
    // ещё круг: просьба [start], пришедшая в последний миг, не теряется
    // (вторая пара глаз S59).
    while (true) {
      _again = false;
      try {
        await _round();
      } on Object {
        // Подготовка — производное: её отказ приложению не мешает.
        // Что успело записаться, лежит в кэше; остальное — в другой раз.
        _show(_progress.copyWith(phase: ShelfReadingPhase.idle));
      }
      await _keepScreen(false);
      if (_stopped) {
        // Проход мог успеть показать ход после [stop]: остановленная
        // подготовка не должна выглядеть идущей.
        _show(const ShelfReadingProgress());
      }
      if (!_again || _quit) {
        _running = null;
        return;
      }
    }
  }

  /// Один проход по полке и расчёт карты за ним.
  Future<void> _round() async {
    final List<Book> books = await _library.books();
    if (_quit) {
      return;
    }
    _activeMs = 0;
    _activeSince = null;
    final ShelfIndexSummary before = _summary ?? const ShelfIndexSummary();
    // Полоски пока нет: она появится, только если найдётся, что читать
    // или считать. При обычном запуске всё уже готово, и мелькать ей
    // перед участником незачем.
    _show(ShelfReadingProgress(booksTotal: books.length));
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
    if (_quit) {
      return;
    }
    final MapSummary map = await _buildMap(books.length, before.map);
    if (_disposed || (_stopped && map.state == MapSummary.failed)) {
      // Остановили, и карта не досчиталась: итог прежний. Досчиталась и
      // записалась — итог говорит правду и после остановки.
      return;
    }
    summary = summary.copyWith(map: map);
    await _remember(summary);
    if (_quit) {
      return;
    }
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
      if (_quit) {
        return const MapSummary(state: MapSummary.failed);
      }
      _show(
        _progress.copyWith(
          phase: ShelfReadingPhase.mapping,
          title: '',
          mapDone: 0,
          mapTotal: books,
        ),
      );
      final int started = _nowMs();
      final MapOutcome outcome = await _map.build(
        plan,
        // Фаза — явно: после «Остановить» и нового «Посчитать карту» ход
        // сброшен, и без неё расчёт шёл бы невидимым (вторая пара глаз).
        onProgress: (int done, int total) {
          _show(
            _progress.copyWith(
              phase: ShelfReadingPhase.mapping,
              mapDone: done,
              mapTotal: total,
            ),
          );
        },
        // Паспорт книги читает тот же движок PDF: пока открыта книга,
        // расчёт ждёт, как и чтение текста.
        turn: () async {
          final bool go = await _waitTurn();
          if (go) {
            _show(_progress.copyWith(phase: ShelfReadingPhase.mapping));
          }
          return go;
        },
        stopped: () => _quit,
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
          if (_held || _quit) {
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
                phase: ShelfReadingPhase.reading,
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
      if (_quit) {
        return null;
      }
    }
    if (_quit) {
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
    while (_held && !_quit) {
      _pause();
      _show(_progress.copyWith(phase: ShelfReadingPhase.held));
      final Completer<void> release = _release ??= Completer<void>();
      await release.future;
    }
    return !_quit;
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
    final Future<void> Function(bool on)? keep = _keepScreenOn;
    if (keep == null) {
      return;
    }
    _screenKept = on;
    try {
      await keep(on);
    } on Object {
      // Экран может погаснуть; проход при этом идёт, пока его не
      // остановит система.
    }
  }

  Future<void> _remember(ShelfIndexSummary summary) async {
    _summary = summary;
    try {
      await _settings.write(_summaryKey, summary.encode());
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
