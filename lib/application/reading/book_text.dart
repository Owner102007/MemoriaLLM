import 'dart:async';

import '../../domain/reading/page_text.dart';
import '../../domain/reading/reader_document.dart';

/// Сколько страниц фоновый проход записывает в базу одним разом.
///
/// Запись на каждую страницу — это семьсот походов в базу на толстый
/// том; запись в самом конце — потерянная работа, если книгу закрыли на
/// полпути. Пачка — середина: закрытая книга теряет не больше её.
const int kTextPassBatch = 16;

/// Через сколько после открытия книги начинается фоновый проход.
///
/// Первые секунды движок занят тем, что читатель видит: первой
/// страницей, её соседями и рамкой книги. Проход им не соперник — он
/// подождёт.
const Duration kTextPassDelay = Duration(seconds: 2);

/// Текст страниц открытой книги: кэш в базе устройства и движок PDF за
/// ним (F-TEXT-04, ALG-TXT-09).
///
/// Поиск по книге прежде каждый раз заново читал её движком — страницу
/// за страницей. Теперь текст страницы извлекается из файла один раз и
/// запоминается: запомненное отдаётся из базы, остальное — как раньше,
/// движком, и по дороге запоминается. Поиск от этого ни в чём не хуже
/// прежнего и сам наполняет кэш.
///
/// Кроме поиска кэш наполняет **фоновый проход**: он идёт вперёд от
/// места чтения, дойдя до конца книги — с её начала, читает по одной
/// странице за раз (движок между ними успевает обслужить страницу, на
/// которую читатель перешёл) и останавливается, когда книгу закрыли.
/// При следующем открытии запомненное уже лежит в базе, и проход
/// продолжается с того, что осталось.
///
/// **Кэш — производное**: сбой базы не повод ни не открыть книгу, ни
/// сорвать поиск. Не прочиталось из базы — читается движком; не
/// записалось — запишется в другой раз.
class BookTextCache {
  /// Создаёт кэш текста книги.
  ///
  /// [version] задаётся в тестах; приложение берёт [kPageTextVersion].
  BookTextCache({
    required ReaderDocument document,
    required PageTextRepository store,
    required String bookId,
    required String fingerprint,
    int version = kPageTextVersion,
    this.passBatch = kTextPassBatch,
    this.onBookRead,
  }) : _document = document,
       _store = store,
       _key = PageTextKey(
         bookId: bookId,
         fingerprint: fingerprint,
         version: version,
       );

  /// Сколько страниц проход записывает одним разом.
  final int passBatch;

  /// Зовётся, когда проход кончился, а книга запомнена целиком
  /// (F-DEV-13): `true` — в ней есть текст, `false` — нет ни знака.
  ///
  /// При импорте на текст проверяются только первые страницы, и книга с
  /// картинками в начале и текстом дальше называется сканом зря. Кэш
  /// знает ответ точно — когда прочитана вся книга, — и говорит его
  /// тому, кто ведёт признак на полке.
  final void Function(bool hasText)? onBookRead;

  final ReaderDocument _document;
  final PageTextRepository _store;
  final PageTextKey _key;

  /// Запомненные страницы: страница → длина её текста.
  final Map<int, int> _cached = <int, int>{};

  /// Чтения из движка, которые идут прямо сейчас: страница → чтение.
  /// Поиск и проход могут прийти за одной страницей одновременно, и
  /// читать её дважды незачем.
  final Map<int, Future<String?>> _reading = <int, Future<String?>>{};

  /// Прочитанное движком, но ещё не записанное в базу: страница → текст.
  /// Пока пачка ждёт записи, за теми же страницами может прийти поиск —
  /// и читать их движком второй раз незачем.
  final Map<int, String> _unsaved = <int, String>{};

  Future<void>? _loading;
  bool _closed = false;

  /// Счёт проходов: остановленный проход узнаёт по нему, что устарел.
  int _passRun = 0;
  Future<void>? _pass;

  /// Число страниц книги.
  int get pageCount => _document.pageCount;

  /// Сколько страниц запомнено.
  int get cachedCount => _cached.length;

  /// Запомнена ли книга целиком.
  bool get isComplete => _cached.length >= pageCount;

  /// Сколько знаков текста книги лежит в кэше — для замеров, с
  /// точностью до редких знаков: страницы, запомненные в прошлый раз,
  /// посчитаны базой в знаках, а записанные сейчас — в кодовых единицах.
  int get cachedSize {
    int total = 0;
    for (final int size in _cached.values) {
      total += size;
    }
    return total;
  }

  /// Есть ли в книге текст — по прочитанному, а не по первым страницам
  /// (F-DEV-13). `null`, пока книга не запомнена целиком: о книге,
  /// которую не дочитали или не смогли прочесть, ответа нет.
  bool? get readVerdict {
    if (pageCount <= 0 || !isComplete) {
      return null;
    }
    return cachedSize > 0;
  }

  /// Идёт ли сейчас фоновый проход.
  bool get isPassing => _pass != null;

  /// Запомнена ли страница [page].
  bool isCached(int page) => _cached.containsKey(page);

  /// Узнаёт у базы, какие страницы уже запомнены.
  ///
  /// Зовётся один раз; повторные вызовы отдают тот же ответ. Всё
  /// остальное зовёт это само.
  Future<void> load() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    if (_closed) {
      return;
    }
    try {
      final Map<int, int> pages = await _store.cachedPages(_key);
      final int total = pageCount;
      for (final MapEntry<int, int> entry in pages.entries) {
        // Страница за краем книги — след другого файла под тем же
        // отпечатком; такой быть не должно, и верить ей незачем.
        if (entry.key >= 1 && entry.key <= total) {
          _cached.putIfAbsent(entry.key, () => entry.value);
        }
      }
    } on Object {
      // База не ответила — кэш считается пустым, книга читается движком.
    }
  }

  /// Текст страниц с [from] по [to] включительно: страница → текст.
  ///
  /// Запомненные страницы берутся из базы одним запросом, остальные
  /// читаются движком и запоминаются. Страница, которую движок не смог
  /// прочитать, приходит пустой — и не запоминается: в другой раз её
  /// попробуют снова.
  Future<Map<int, String>> textsOf(int from, int to) async {
    await load();
    final int first = from < 1 ? 1 : from;
    final int last = to > pageCount ? pageCount : to;
    final Map<int, String> texts = <int, String>{};
    if (first > last) {
      return texts;
    }
    bool any = false;
    for (int page = first; page <= last; page++) {
      if (_cached.containsKey(page)) {
        any = true;
        break;
      }
    }
    if (any) {
      try {
        final Map<int, String> stored = await _store.pageTexts(
          _key,
          from: first,
          to: last,
        );
        // База отвечает по ключу — этот файл, эта версия алгоритма, — так
        // что годится всё, что она отдала в запрошенном отрезке.
        for (final MapEntry<int, String> entry in stored.entries) {
          if (entry.key >= first && entry.key <= last) {
            texts[entry.key] = entry.value;
          }
        }
      } on Object {
        // Не прочиталось из базы — прочитается движком.
      }
    }
    final Map<int, String> fresh = <int, String>{};
    for (int page = first; page <= last; page++) {
      if (texts.containsKey(page)) {
        continue;
      }
      final String? text = await _fetch(page);
      texts[page] = text ?? '';
      if (text != null && !_cached.containsKey(page)) {
        fresh[page] = text;
      }
    }
    await _save(fresh);
    return texts;
  }

  /// Начинает фоновый проход от страницы [from].
  ///
  /// Идёт вперёд до конца книги, затем с её начала — до страницы, с
  /// которой начал. Запомненные страницы пропускает. Пока проход идёт,
  /// повторный вызов ничего не делает: второго прохода не будет.
  void startPass({required int from}) {
    if (_closed || _pass != null) {
      return;
    }
    final int run = ++_passRun;
    final Future<void> work = _runPass(run, from).whenComplete(() {
      if (run == _passRun) {
        _pass = null;
      }
    });
    _pass = work;
    unawaited(work);
  }

  /// Останавливает фоновый проход. Прочитанное им записывается — если
  /// книгу при этом не закрыли: закрытая книга к базе больше не ходит и
  /// теряет последнюю неполную пачку.
  void stopPass() {
    _passRun++;
    _pass = null;
  }

  /// Ждёт конца идущего прохода — для тестов и замеров.
  Future<void> passDone() => _pass ?? Future<void>.value();

  Future<void> _runPass(int run, int from) async {
    await load();
    final int total = pageCount;
    if (total <= 0) {
      return;
    }
    final int start = from < 1 ? 1 : (from > total ? total : from);
    final Map<int, String> batch = <int, String>{};
    for (int step = 0; step < total; step++) {
      if (_closed || run != _passRun) {
        break;
      }
      final int page = (start - 1 + step) % total + 1;
      if (_cached.containsKey(page)) {
        continue;
      }
      final String? text = await _fetch(page);
      if (text != null && !_cached.containsKey(page)) {
        batch[page] = text;
      }
      if (batch.length >= passBatch) {
        await _save(Map<int, String>.of(batch));
        batch.clear();
      }
    }
    // Остановленный проход прочитанное не выбрасывает.
    await _save(batch);
    // Проход дошёл до конца, и книга запомнена вся — про её текст теперь
    // известно точно. Остановленный и закрытый молчат.
    final bool? verdict = readVerdict;
    if (verdict != null && !_closed && run == _passRun) {
      onBookRead?.call(verdict);
    }
  }

  /// Текст страницы из движка; `null` — страница не прочиталась.
  Future<String?> _fetch(int page) {
    final String? ready = _unsaved[page];
    if (ready != null) {
      return Future<String?>.value(ready);
    }
    final Future<String?>? running = _reading[page];
    if (running != null) {
      return running;
    }
    final Future<String?> work = _read(page).whenComplete(() {
      _reading.remove(page);
    });
    _reading[page] = work;
    return work;
  }

  Future<String?> _read(int page) async {
    if (_closed) {
      return null;
    }
    try {
      final String text = await _document.pageText(page);
      if (!_closed && !_cached.containsKey(page)) {
        _unsaved[page] = text;
      }
      return text;
    } on Object {
      // Одна нечитаемая страница не должна обрывать ни поиск, ни проход.
      return null;
    }
  }

  Future<void> _save(Map<int, String> texts) async {
    if (texts.isEmpty || _closed) {
      return;
    }
    bool saved = true;
    try {
      await _store.savePageTexts(_key, texts);
    } on Object {
      // Не записалось — эти страницы прочитаются движком ещё раз.
      saved = false;
    }
    for (final MapEntry<int, String> entry in texts.entries) {
      _unsaved.remove(entry.key);
      if (saved) {
        // Страница из одних пробелов — страница без текста: по этим
        // длинам кэш отвечает, есть ли в книге текст (F-DEV-13).
        _cached[entry.key] = entry.value.trim().isEmpty
            ? 0
            : entry.value.length;
      }
    }
  }

  /// Книгу закрыли: проход останавливается, к движку и к базе кэш
  /// больше не ходит.
  void close() {
    stopPass();
    _closed = true;
    _unsaved.clear();
  }
}
