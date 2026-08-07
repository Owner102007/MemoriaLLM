import 'package:flutter/foundation.dart';

import '../../domain/reading/reader_document.dart';
import '../../domain/reading/text_search.dart';

/// Поиск по всей книге.
///
/// Текст страниц движок отдаёт по одной, и на книге в тысячу страниц
/// это заметная работа. Поэтому поиск идёт постранично, отдаёт найденное
/// по ходу дела, уступает управление интерфейсу между страницами и
/// честно отменяется: человек, начавший печатать новый запрос, не должен
/// ждать конца старого.
class DocumentSearch extends ChangeNotifier {
  /// Создаёт поиск по документу.
  DocumentSearch({
    required ReaderDocument document,
    this.hitLimit = 300,
    this.pagesPerYield = 8,
  }) : _document = document;

  /// Сколько совпадений собирать, прежде чем остановиться.
  ///
  /// Список из тысяч строк бесполезен человеку и дорог интерфейсу; если
  /// совпадений столько, запрос надо уточнять, а не пролистывать.
  final int hitLimit;

  /// Через сколько страниц уступать управление интерфейсу.
  final int pagesPerYield;

  final ReaderDocument _document;

  String _query = '';
  List<SearchHit> _hits = const <SearchHit>[];
  bool _isRunning = false;
  bool _reachedLimit = false;
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

  /// Запускает поиск. Предыдущий, если он шёл, отменяется.
  Future<void> start(String query) async {
    _session++;
    final int session = _session;
    _query = query.trim();
    _hits = const <SearchHit>[];
    _scannedPages = 0;
    _reachedLimit = false;

    if (!isSearchableQuery(_query)) {
      _isRunning = false;
      notifyListeners();
      return;
    }

    _isRunning = true;
    notifyListeners();

    final List<SearchHit> found = <SearchHit>[];
    final int total = _document.pageCount;
    for (int page = 1; page <= total; page++) {
      if (session != _session) {
        return; // запрос сменился — этот прогон больше никому не нужен
      }
      String text = '';
      try {
        text = await _document.pageText(page);
      } on Object {
        // Одна нечитаемая страница не должна обрывать поиск по книге.
        text = '';
      }
      if (session != _session) {
        return;
      }
      if (text.isNotEmpty) {
        found.addAll(
          findInPageText(
            pageNumber: page,
            pageText: text,
            query: _query,
            limit: hitLimit - found.length,
          ),
        );
      }
      _scannedPages = page;

      if (found.length >= hitLimit) {
        _reachedLimit = true;
        break;
      }
      if (page % pagesPerYield == 0) {
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

  /// Отменяет поиск и очищает результаты.
  void clear() {
    _session++;
    _query = '';
    _hits = const <SearchHit>[];
    _isRunning = false;
    _reachedLimit = false;
    _scannedPages = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _session++;
    super.dispose();
  }
}
