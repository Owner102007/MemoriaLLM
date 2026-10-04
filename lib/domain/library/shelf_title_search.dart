/// Поиск по названию на полке — чистые функции над названиями книг.
///
/// SNO-ALG-LIB-01, SNO-F-LIB-01. Простой поиск сборок ветвей СНО2026:
/// найти книгу по названию за время набора, без базы и без индекса. В
/// исследовании он ещё и мера стратегии — по нему видно, когда участник
/// перестаёт искать источник и начинает открывать его по памяти.
///
/// Название и запрос приводятся к одному виду тем же правилом, что текст
/// книги при поиске по ней: без регистра, без разницы между `ё` и `е`,
/// буквы-двойники латиницы и кириллицы сведены вместе. **Длина при этом
/// не меняется, знак в знак**: место совпадения в свёрнутом названии и
/// есть место в исходном, и подсветке не нужна таблица соответствия.
/// Окончания не снимаются: поиск идёт по подстроке, и стеммер здесь
/// только прятал бы совпадения.
library;

import '../reading/text_search.dart';
import 'book.dart';
import 'search_text.dart';

/// Вес слова запроса, стоящего в начале слова названия.
const int kTitleWordStartRank = 3;

/// Вес слова запроса, найденного внутри слова названия.
const int kTitleInsideRank = 1;

/// Кусок названия, совпавший с запросом.
class TitleSpan {
  /// Создаёт кусок от [start] до [end], не включая.
  const TitleSpan(this.start, this.end);

  /// Начало в названии.
  final int start;

  /// Конец в названии, не включая.
  final int end;

  @override
  bool operator ==(Object other) {
    return other is TitleSpan && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TitleSpan($start..$end)';
}

/// Книга, найденная по названию.
class ShelfTitleHit {
  /// Создаёт находку.
  const ShelfTitleHit({
    required this.book,
    required this.spans,
    required this.rank,
  });

  /// Книга.
  final Book book;

  /// Что в названии подсветить: по порядку, без наложений.
  final List<TitleSpan> spans;

  /// Вес находки: чем больше, тем выше в списке.
  final int rank;

  @override
  String toString() => 'ShelfTitleHit(«${book.title}», вес $rank)';
}

/// Название в том виде, в каком его сравнивают с запросом.
///
/// Длина та же, что у [title].
String foldShelfTitle(String title) {
  return foldedSearchText(plainSearchText(title));
}

/// Слова запроса: свёрнутые, без разделителей и без повторов.
///
/// Запрос из одних знаков слов не даёт — и ничего не находит.
List<String> titleQueryWords(String query) {
  final String folded = foldShelfTitle(query);
  final List<String> words = <String>[];
  final StringBuffer current = StringBuffer();

  void flush() {
    if (current.isEmpty) {
      return;
    }
    final String word = current.toString();
    current.clear();
    if (!words.contains(word)) {
      words.add(word);
    }
  }

  for (final int rune in folded.runes) {
    if (isSearchWordRune(rune)) {
      current.writeCharCode(rune);
    } else {
      flush();
    }
  }
  flush();
  return words;
}

/// Подходит ли книга под слова запроса; `null` — нет.
///
/// Книга подходит, если **каждое** слово запроса есть в названии
/// подстрокой. Слово, которым начинается слово названия, весит больше,
/// чем найденное в середине: набравший «анат» ищет «Анатомию», а не
/// «Патанатомию».
ShelfTitleHit? matchShelfTitle(Book book, List<String> words) {
  if (words.isEmpty) {
    return null;
  }
  // Слой названия пока один. Название от читателя (F-LIB-18) встанет
  // сюда вторым и будет весить больше: его дал сам читатель.
  final String folded = foldShelfTitle(book.title);
  final List<TitleSpan> found = <TitleSpan>[];
  int rank = 0;
  for (final String word in words) {
    bool startsWord = false;
    int from = 0;
    int count = 0;
    while (true) {
      final int at = folded.indexOf(word, from);
      if (at < 0) {
        break;
      }
      count++;
      startsWord = startsWord || _startsWord(folded, at);
      found.add(TitleSpan(at, at + word.length));
      from = at + word.length;
    }
    if (count == 0) {
      return null;
    }
    rank += startsWord ? kTitleWordStartRank : kTitleInsideRank;
  }
  return ShelfTitleHit(book: book, spans: _merge(found), rank: rank);
}

/// Ищет книги по названию.
///
/// [books] — книги в порядке полки: при равном весе находки стоят так
/// же, как стоят на полке. Пустой запрос и запрос из одних знаков не
/// находят ничего.
List<ShelfTitleHit> searchShelfTitles({
  required String query,
  required List<Book> books,
}) {
  final List<String> words = titleQueryWords(query);
  if (words.isEmpty) {
    return const <ShelfTitleHit>[];
  }
  final List<(int, ShelfTitleHit)> ranked = <(int, ShelfTitleHit)>[];
  for (int i = 0; i < books.length; i++) {
    final ShelfTitleHit? hit = matchShelfTitle(books[i], words);
    if (hit != null) {
      ranked.add((i, hit));
    }
  }
  // Место на полке — второй ключ: сортировка списка не обязана быть
  // устойчивой, и без него равные находки менялись бы местами.
  ranked.sort(((int, ShelfTitleHit) a, (int, ShelfTitleHit) b) {
    final int byRank = b.$2.rank.compareTo(a.$2.rank);
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return <ShelfTitleHit>[
    for (final (int, ShelfTitleHit) entry in ranked) entry.$2,
  ];
}

/// Стоит ли место [at] в начале слова.
bool _startsWord(String folded, int at) {
  return at == 0 || !isSearchWordRune(folded.codeUnitAt(at - 1));
}

/// Склеивает куски, которые наложились или встали вплотную.
List<TitleSpan> _merge(List<TitleSpan> spans) {
  final List<TitleSpan> sorted = <TitleSpan>[...spans]
    ..sort((TitleSpan a, TitleSpan b) => a.start.compareTo(b.start));
  final List<TitleSpan> merged = <TitleSpan>[];
  for (final TitleSpan span in sorted) {
    if (merged.isNotEmpty && span.start <= merged.last.end) {
      final TitleSpan last = merged.removeLast();
      merged.add(
        TitleSpan(last.start, span.end > last.end ? span.end : last.end),
      );
    } else {
      merged.add(span);
    }
  }
  return merged;
}
