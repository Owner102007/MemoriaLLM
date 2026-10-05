/// Текст, который уходит из книги (ALG-TXT-14, BUG-51).
///
/// Дефис в конце строки, за которым слово продолжается, движок отдаёт
/// служебным знаком ([kLineBreakHyphen]), а не дефисом. В самой книге
/// знак нужен: поиск читает его двояко (BUG-50), и «Найти в книге»
/// собирает по нему два запроса. Но наружу — в цитату, в заметку, в
/// буфер обмена, в запрос к модели, в выгрузку, в журнал записи — он
/// уходить не должен: слово с невидимым знаком внутри не находится
/// поиском нигде, а кое-где показывается квадратиком.
///
/// По тексту не узнать, перенос это обычного слова («остео» + «логия»)
/// или дефис составного, попавший на конец строки («сердечно» +
/// «сосудистая»). Правило — решение владельца Ф4 от 05.10.2026: на
/// месте знака **ничего**, а **дефис** — только если слово с дефисом
/// встречается в этой же книге написанным целиком. Какие слова
/// встречаются, знает кэш текста книги; здесь — чистые функции.
library;

import 'text_search.dart';

final String _mark = String.fromCharCode(kLineBreakHyphen);

/// Знак слова: буква, цифра или знак, который к букве приставлен, —
/// «й», записанная буквой и отдельной краткой, остаётся одним словом.
final RegExp _wordChar = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

bool _isWordChar(String text, int index) {
  return index >= 0 && index < text.length && _wordChar.hasMatch(text[index]);
}

/// Есть ли в [text] знак переноса.
bool hasLineBreakMark(String text) => text.contains(_mark);

/// Половины слова по обе стороны знака на месте [at]; `null` — знак
/// стоит не внутри слова.
({String left, String right})? _halvesAt(String text, int at) {
  int from = at;
  while (_isWordChar(text, from - 1)) {
    from--;
  }
  int to = at + 1;
  while (_isWordChar(text, to)) {
    to++;
  }
  if (from == at || to == at + 1) {
    return null;
  }
  return (left: text.substring(from, at), right: text.substring(at + 1, to));
}

/// Вид слова, в котором написания сравниваются: без регистра и без
/// разницы между `ё` и `е` — как в поиске по книге. «Трёх», знак,
/// «мерный» узнаёт своё написание и в книге, где набрано «трех-мерный».
String spellingKey(String word) => plainSearchText(word);

/// Написания с дефисом для слов [text], разрезанных знаком переноса, —
/// в виде для сравнения ([spellingKey]).
///
/// О каждом из них надо спросить книгу: встречается ли оно в ней
/// целиком. Те, что встречаются, отдаются в [leavingText].
Set<String> hyphenSpellings(String text) {
  final Set<String> spellings = <String>{};
  int at = text.indexOf(_mark);
  while (at >= 0) {
    final ({String left, String right})? halves = _halvesAt(text, at);
    if (halves != null) {
      spellings.add(spellingKey('${halves.left}-${halves.right}'));
    }
    at = text.indexOf(_mark, at + 1);
  }
  return spellings;
}

/// Текст [text] без знаков переноса — таким он уходит из книги.
///
/// На месте знака не остаётся ничего: «остео», знак, «логия» →
/// «остеология». Дефис встаёт там, где слово с дефисом есть в
/// [hyphenated] — написаниях, которые книга знает целыми (в виде для
/// сравнения, как их отдаёт [hyphenSpellings]): «сердечно», знак,
/// «сосудистая» → «сердечно-сосудистая». Без [hyphenated] дефисов не
/// будет вовсе — так чинятся цитаты, сохранённые до исправления, и
/// текст книги, которая ещё не прочитана.
String leavingText(String text, {Set<String> hyphenated = const <String>{}}) {
  int at = text.indexOf(_mark);
  if (at < 0) {
    return text;
  }
  final StringBuffer out = StringBuffer();
  int from = 0;
  while (at >= 0) {
    out.write(text.substring(from, at));
    if (hyphenated.isNotEmpty) {
      final ({String left, String right})? halves = _halvesAt(text, at);
      if (halves != null &&
          hyphenated.contains(spellingKey('${halves.left}-${halves.right}'))) {
        out.write('-');
      }
    }
    from = at + 1;
    at = text.indexOf(_mark, from);
  }
  out.write(text.substring(from));
  return out.toString();
}

/// Встречается ли слово [word] в тексте [haystack] целиком — не куском
/// более длинного слова. Оба — в виде для сравнения ([spellingKey]).
bool containsWholeWord(String haystack, String word) {
  if (word.isEmpty) {
    return false;
  }
  int at = haystack.indexOf(word);
  while (at >= 0) {
    final int end = at + word.length;
    if (!_isWordChar(haystack, at - 1) && !_isWordChar(haystack, end)) {
      return true;
    }
    at = haystack.indexOf(word, at + 1);
  }
  return false;
}
