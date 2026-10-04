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

final RegExp _spaces = RegExp(r'\s+');

/// Запросы поиска из выделенного текста: первый — основной, он встаёт
/// в поле поиска; остальные — другие написания того же, поиск ищет их
/// заодно (`DocumentSearch.start`, `also`).
///
/// Обычно запрос один: выделенное без переводов строк и лишних
/// пробелов. Их два, когда в выделенном слово разрезано переносом в
/// конце строки — движок ставит на этом месте [kLineBreakHyphen], и по
/// тексту не узнать, перенос это или дефис составного слова:
///
/// 1. слитно — `остео`, знак, `логия` → «остеология»: так написано
///    обычное слово в остальных местах книги, и так же находится само
///    выделенное место;
/// 2. с дефисом — `сердечно`, знак, `сосудистая` →
///    «сердечно-сосудистая»: так в остальных местах книги написано
///    составное слово.
///
/// Каждый запрос укорочен до [limit] по слову; пустых и одинаковых в
/// списке нет. Знак переноса на краю выделенного ничего не разрезает и
/// просто отбрасывается.
List<String> selectionSearchQueries(
  String selected, {
  int limit = kSelectionQueryLimit,
}) {
  final String mark = String.fromCharCode(kLineBreakHyphen);
  String core = selected.trim();
  while (core.startsWith(mark)) {
    core = core.substring(mark.length).trimLeft();
  }
  while (core.endsWith(mark)) {
    core = core.substring(0, core.length - mark.length).trimRight();
  }
  String flat(String raw) {
    return _shorten(raw.replaceAll(_spaces, ' ').trim(), limit);
  }

  final String glued = flat(core.replaceAll(mark, ''));
  final String hyphened = flat(core.replaceAll(mark, '-'));
  return <String>[
    if (glued.isNotEmpty) glued,
    if (hyphened.isNotEmpty && hyphened != glued) hyphened,
  ];
}

/// Укорачивает запрос до [limit] знаков по слову.
String _shorten(String flat, int limit) {
  if (limit <= 0) {
    return '';
  }
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
