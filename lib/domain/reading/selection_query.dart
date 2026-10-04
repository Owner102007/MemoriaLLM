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
/// «Санкт-» и «Петербург» на двух строках остаются с дефисом.
final RegExp _brokenWord = RegExp(
  r'(\p{L})[-\u2010\u2011\u00AD][ \t]*(?:\r\n|\r|\n)\s*(?=\p{Ll})',
  unicode: true,
);

final RegExp _spaces = RegExp(r'\s+');

/// Запрос поиска из выделенного текста.
///
/// Слово, разрезанное переносом, склеивается: искать «остео- логия»
/// значило бы найти одно-единственное место — то, которое выделили.
/// Переводы строк и лишние пробелы становятся одним пробелом, края
/// обрезаются, слишком длинное укорачивается до [limit] по слову.
String selectionSearchQuery(
  String selected, {
  int limit = kSelectionQueryLimit,
}) {
  final String joined = selected.replaceAllMapped(
    _brokenWord,
    (Match match) => match.group(1)!,
  );
  final String flat = joined.replaceAll(_spaces, ' ').trim();
  if (flat.length <= limit) {
    return flat;
  }
  String cut = flat.substring(0, limit);
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
/// Берётся совпадение, которое с этим куском пересекается; нет такого —
/// ближайшее на той же странице. Совпадения других страниц не годятся:
/// читатель просил найти, а не увести его с места, где он читает.
int hitIndexAt(
  List<SearchHit> hits, {
  required int pageNumber,
  required int start,
  required int end,
}) {
  int nearest = -1;
  int gap = -1;
  for (int i = 0; i < hits.length; i++) {
    final SearchHit hit = hits[i];
    if (hit.pageNumber != pageNumber) {
      continue;
    }
    if (hit.sourceStart < end && hit.sourceEnd > start) {
      return i;
    }
    final int distance = hit.sourceStart >= end
        ? hit.sourceStart - end
        : start - hit.sourceEnd;
    if (nearest < 0 || distance < gap) {
      nearest = i;
      gap = distance;
    }
  }
  return nearest;
}
