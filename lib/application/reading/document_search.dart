import 'package:flutter/foundation.dart';

import '../../domain/reading/reader_document.dart';
import '../../domain/reading/text_search.dart';
import 'book_text.dart';

/// Поиск по всей книге.
///
/// Текст страниц движок отдаёт по одной, и на книге в тысячу страниц
/// это заметная работа. Поэтому поиск идёт постранично, отдаёт найденное
/// по ходу дела, уступает управление интерфейсу между пачками страниц и
/// честно отменяется: человек, начавший печатать новый запрос, не должен
/// ждать конца старого.
///
/// **Текст берётся из кэша** (F-TEXT-04, ALG-TXT-09), если он дан:
/// запомненные страницы читаются из базы пачкой, остальные — движком, и
/// по дороге запоминаются. Книга, запомненная целиком, ищется без
/// единого обращения к движку. Без кэша поиск читает документ напрямую
/// — так, как делал всегда; найденное в обоих случаях одно и то же.
class DocumentSearch extends ChangeNotifier {
  /// Создаёт поиск по документу.
  DocumentSearch({
    required ReaderDocument document,
    BookTextCache? cache,
    this.hitLimit = 300,
    this.pagesPerYield = 8,
  }) : _document = document,
       _cache = cache;

  /// Сколько совпадений собирать, прежде чем остановиться.
  ///
  /// Список из тысяч строк бесполезен человеку и дорог интерфейсу; если
  /// совпадений столько, запрос надо уточнять, а не пролистывать.
  final int hitLimit;

  /// Сколько страниц просматривается одной пачкой: после неё найденное
  /// отдаётся интерфейсу, и ему уступается управление.
  final int pagesPerYield;

  final ReaderDocument _document;
  final BookTextCache? _cache;

  String _query = '';
  List<SearchHit> _hits = const <SearchHit>[];
  bool _isRunning = false;
  bool _reachedLimit = false;
  bool _sawText = false;
  int _unreadPages = 0;
  int _scannedPages = 0;
  int _session = 0;

  /// Текущий запрос.
  String get query => _query;

  /// Найденное, в порядке страниц.
  List<SearchHit> get hits => _hits;

  /// Идёт ли поиск прямо сейчас.
  bool get isRunning => _isRunning;

  /// Упёрлись ли в [hitLimit].
  bool get reachedLimit => _reachedLimit;

  /// Сколько страниц просмотрено.
  int get scannedPages => _scannedPages;

  /// Число страниц книги.
  int get pageCount => _document.pageCount;

  /// Сколько страниц ещё не просмотрено.
  ///
  /// Неполный поиск — честное состояние, а не отказ (F-TEXT-04):
  /// найденное показано, остаток назван числом и убывает.
  int get unscannedPages {
    final int left = _document.pageCount - _scannedPages;
    return left < 0 ? 0 : left;
  }

  /// Доля просмотренного, от 0 до 1.
  double get progress {
    final int total = _document.pageCount;
    if (total <= 0) {
      return 0;
    }
    final double value = _scannedPages / total;
    return value > 1 ? 1 : value;
  }

  /// Поиск завершён и что-то искали.
  bool get isFinished => !_isRunning && _query.isNotEmpty;

  /// Ничего не нашли.
  bool get isEmptyResult => isFinished && _hits.isEmpty;

  /// Книга просмотрена целиком, и текста в ней не оказалось вовсе: это
  /// скан без текстового слоя (F-TEXT-04).
  ///
  /// «Ничего не найдено» здесь было бы неправдой: искать было не в чем.
  /// Но и «скан» говорится только о книге, которая прочитана на самом
  /// деле: страница, которую движок не отдал, — не пустая страница.
  bool get bookHasNoText =>
      isFinished &&
      isSearchableQuery(_query) &&
      !_reachedLimit &&
      !_sawText &&
      _unreadPages == 0 &&
      (_cache?.isComplete ?? true) &&
      _scannedPages >= _document.pageCount;

  /// Запускает поиск. Предыдущий, если он шёл, отменяется.
  ///
  /// [also] — другие написания того же запроса: найденное по ним
  /// встаёт в общий список по порядку страниц, а запросом остаётся
  /// [query]. Так «Найти в книге» ищет слово, выделенное на переносе:
  /// слитно — и заодно с дефисом, каким оно может быть написано в
  /// остальных местах книги (SNO-F-READ-01). Проход по книге один.
  Future<void> start(
    String query, {
    List<String> also = const <String>[],
  }) async {
    _session++;
    final int session = _session;
    _query = query.trim();
    final List<String> queries = <String>[_query];
    for (final String other in also) {
      final String spelled = other.trim();
      if (isSearchableQuery(spelled) && !queries.contains(spelled)) {
        queries.add(spelled);
      }
    }
    _hits = const <SearchHit>[];
    _scannedPages = 0;
    _reachedLimit = false;
    _sawText = false;
    _unreadPages = 0;

    if (!isSearchableQuery(_query)) {
      _isRunning = false;
      notifyListeners();
      return;
    }

    _isRunning = true;
    notifyListeners();

    final List<SearchHit> found = <SearchHit>[];
    final int total = _document.pageCount;
    final int step = pagesPerYield < 1 ? 1 : pagesPerYield;
    for (int from = 1; from <= total; from += step) {
      if (session != _session) {
        return; // запрос сменился — этот прогон больше никому не нужен
      }
      final int to = from + step - 1 > total ? total : from + step - 1;
      final Map<int, String> texts = await _textsOf(from, to);
      if (session != _session) {
        return;
      }
      for (int page = from; page <= to; page++) {
        final String text = texts[page] ?? '';
        if (text.isNotEmpty) {
          if (!_sawText && text.trim().isNotEmpty) {
            _sawText = true;
          }
          found.addAll(
            _findOnPage(page, text, queries, hitLimit - found.length),
          );
        }
        _scannedPages = page;
        if (found.length >= hitLimit) {
          _reachedLimit = true;
          break;
        }
      }
      if (_reachedLimit) {
        break;
      }
      if (to < total) {
        _hits = List<SearchHit>.unmodifiable(found);
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (session != _session) {
      return;
    }
    _hits = List<SearchHit>.unmodifiable(found);
    _isRunning = false;
    notifyListeners();
  }

  /// Совпадения одной страницы по всем написаниям запроса — без
  /// повторов и в том порядке, в каком они идут в её тексте.
  List<SearchHit> _findOnPage(
    int page,
    String text,
    List<String> queries,
    int limit,
  ) {
    final List<SearchHit> hits = findInPageText(
      pageNumber: page,
      pageText: text,
      query: queries.first,
      limit: limit,
    );
    if (queries.length == 1) {
      return hits;
    }
    final List<SearchHit> all = <SearchHit>[...hits];
    for (final String query in queries.skip(1)) {
      final List<SearchHit> more = findInPageText(
        pageNumber: page,
        pageText: text,
        query: query,
        limit: limit,
      );
      for (final SearchHit hit in more) {
        if (!all.contains(hit)) {
          all.add(hit);
        }
      }
    }
    all.sort(compareSearchHits);
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  /// Текст страниц с [from] по [to]: из кэша, если он дан, иначе прямо
  /// из документа.
  Future<Map<int, String>> _textsOf(int from, int to) async {
    final BookTextCache? cache = _cache;
    if (cache != null) {
      return cache.textsOf(from, to);
    }
    final Map<int, String> texts = <int, String>{};
    for (int page = from; page <= to; page++) {
      try {
        texts[page] = await _document.pageText(page);
      } on Object {
        // Одна нечитаемая страница не должна обрывать поиск по книге.
        texts[page] = '';
        _unreadPages++;
      }
    }
    return texts;
  }

  /// Отменяет поиск и очищает результаты.
  void clear() {
    _session++;
    _query = '';
    _hits = const <SearchHit>[];
    _isRunning = false;
    _reachedLimit = false;
    _sawText = false;
    _unreadPages = 0;
    _scannedPages = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _session++;
    super.dispose();
  }
}
