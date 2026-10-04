/// «Найти в книге»: выделенное становится запросом поиска.
///
/// SNO-F-READ-01. Чистые функции: что из выделенного уходит в поиск по
/// книге и какое из найденного — то самое место, которое выделяли.
library;

import 'text_search.dart';

/// Длиннее этого запрос из выделенного не бывает.
///
/// Выделить можно и абзац, но абзац — не запрос: он найдёт только сам
/// себя и не поместится в поле. Обрезается по слову.
const int kSelectionQueryLimit = 200;

/// Слово, разрезанное концом строки: буква, дефис, перевод строки и
/// строчная буква следом. «Что-то» посреди строки сюда не попадает, а
/// «Санкт-» и «Петербург» на двух строках не склеиваются: заглавная
/// после дефиса — начало слова, а не его продолжение.
final RegExp _brokenWord = RegExp(
  r'(\p{L})[-\u2010\u2011\u00AD][ \t]*(?:\r\n|\r|\n)\s*(?=\p{Ll})',
  unicode: true,
);

/// Дефис в конце строки, за которым слово продолжается с любой буквы.
final RegExp _hyphenAtBreak = RegExp(
  r'(\p{L})[-\u2010\u2011\u00AD][ \t]*(?:\r\n|\r|\n)\s*(?=\p{L})',
  unicode: true,
);

final RegExp _spaces = RegExp(r'\s+');

/// Запросы поиска из выделенного текста — от лучшего к запасному.
///
/// Обычно запрос один: выделенное без переводов строк и лишних
/// пробелов. Их становится больше, когда в выделенном слово разрезано
/// концом строки, — по тексту не узнать, перенос это или дефис
/// составного слова:
///
/// 1. слово склеено — «остео-», «логия» → «остеология»: так оно
///    написано во всех остальных местах книги;
/// 2. дефис оставлен, перевод строки убран — «сердечно-»,
///    «сосудистая» → «сердечно-сосудистая», «Санкт-», «Петербург» →
///    «Санкт-Петербург»: составное слово склейкой не находится;
/// 3. как выделено — «остео- логия»: находит хотя бы само это место.
///
/// Поиск берёт первый запрос, по которому что-то нашлось. Каждый
/// укорочен до [limit] по слову; пустых и одинаковых в списке нет.
List<String> selectionSearchQueries(
  String selected, {
  int limit = kSelectionQueryLimit,
}) {
  String flat(String raw) {
    return _shorten(raw.replaceAll(_spaces, ' ').trim(), limit);
  }

  final String plain = flat(selected);
  final String glued = flat(
    selected.replaceAllMapped(_brokenWord, (Match word) => word.group(1)!),
  );
  final String hyphened = flat(
    selected.replaceAllMapped(
      _hyphenAtBreak,
      (Match word) => '${word.group(1)}-',
    ),
  );
  final List<String> queries = <String>[];
  for (final String query in <String>[glued, hyphened, plain]) {
    if (query.isNotEmpty && !queries.contains(query)) {
      queries.add(query);
    }
  }
  // «Как выделено» — всегда последним: оно находит только своё место.
  if (queries.length > 1 && queries.remove(plain)) {
    queries.add(plain);
  }
  return queries;
}

/// Первый из запросов по выделенному: тот, что встаёт в поле поиска.
/// Пустая строка — искать нечего.
String selectionSearchQuery(
  String selected, {
  int limit = kSelectionQueryLimit,
}) {
  final List<String> queries = selectionSearchQueries(selected, limit: limit);
  return queries.isEmpty ? '' : queries.first;
}

/// Укорачивает запрос до [limit] знаков по слову.
String _shorten(String flat, int limit) {
  if (flat.length <= limit) {
    return flat;
  }
  String cut = flat.substring(0, limit);
  // Предел пришёлся ровно на конец слова — резать нечего.
  if (flat.codeUnitAt(limit) == 0x20) {
    return cut.trimRight();
  }
  // Половина знака из двух — не знак: пара режется целиком.
  final int last = cut.codeUnitAt(cut.length - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    cut = cut.substring(0, cut.length - 1);
  }
  final int space = cut.lastIndexOf(' ');
  return (space > 0 ? cut.substring(0, space) : cut).trim();
}

/// Номер совпадения, лежащего на месте выделения; −1 — такого нет.
///
/// Место — страница [pageNumber] и кусок её текста от [start] до [end].
/// Годится только совпадение, которое с этим куском пересекается.
/// Ближайшее по соседству не берётся: читатель просил найти, а не
/// увести его с места, где он читает, — на другую страницу или в
/// другую полосу той же.
int hitIndexAt(
  List<SearchHit> hits, {
  required int pageNumber,
  required int start,
  required int end,
}) {
  for (int i = 0; i < hits.length; i++) {
    final SearchHit hit = hits[i];
    if (hit.pageNumber == pageNumber &&
        hit.sourceStart < end &&
        hit.sourceEnd > start) {
      return i;
    }
  }
  return -1;
}
