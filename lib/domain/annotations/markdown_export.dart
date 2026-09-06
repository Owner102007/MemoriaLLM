/// Выгрузка цитат и заметок в Markdown — чистые функции над строками.
///
/// Markdown выбран не из любви к формату, а потому что он одновременно
/// читается глазами в любом текстовом редакторе и открывается в Obsidian,
/// Notion и десятке других мест. Выгрузка — это обещание, что написанное
/// читателем принадлежит читателю и не заперто в приложении.
library;

import '../library/search_text.dart';
import 'annotations.dart';

/// Собирает цитаты и заметки книги в один Markdown-документ.
///
/// Порядок — по страницам, а не по времени: так документ читается как
/// путь по книге. Заметка, привязанная к цитате, идёт сразу за ней;
/// заметка сама по себе — отдельным блоком.
String annotationsToMarkdown({
  required String bookTitle,
  required List<Quote> quotes,
  required List<Note> notes,
  String? author,
  DateTime? exportedAt,
}) {
  final StringBuffer out = StringBuffer();
  out.writeln('# ${_escapeHeading(bookTitle)}');
  if (author != null && author.trim().isNotEmpty) {
    out.writeln();
    out.writeln('*${author.trim()}*');
  }
  if (exportedAt != null) {
    out.writeln();
    out.writeln('Выгружено ${_date(exportedAt)}.');
  }

  final Map<String, List<Note>> notesByQuote = <String, List<Note>>{};
  final List<Note> loose = <Note>[];
  for (final Note note in notes) {
    final String? quoteId = note.quoteId;
    if (quoteId == null) {
      loose.add(note);
    } else {
      notesByQuote.putIfAbsent(quoteId, () => <Note>[]).add(note);
    }
  }

  final List<int> pages = <int>{
    for (final Quote quote in quotes) quote.page,
    for (final Note note in loose) note.page,
  }.toList()..sort();

  if (pages.isEmpty) {
    out.writeln();
    out.writeln('Пока пусто.');
    return out.toString();
  }

  for (final int page in pages) {
    out.writeln();
    out.writeln('## Страница $page');
    for (final Quote quote in quotes.where((Quote q) => q.page == page)) {
      out.writeln();
      out.writeln(_blockquote(quote.content));
      for (final Note note in notesByQuote[quote.id] ?? const <Note>[]) {
        out.writeln();
        out.writeln(note.body.trim());
      }
    }
    for (final Note note in loose.where((Note n) => n.page == page)) {
      out.writeln();
      out.writeln(note.body.trim());
    }
  }
  return out.toString();
}

/// Подходит ли цитата или заметка под запрос.
///
/// Нормализация — та же, что у поиска по книгам устройства
/// (`domain/library/search_text.dart`): свёртка похожих букв, `ё`/`е`,
/// простой стеммер. Второй реализации поиска в проекте быть не должно —
/// две нормализации всегда расходятся, и расхождение видно не сразу.
bool matchesQuery(String text, String query) {
  final List<String> needles = searchTokens(query);
  if (needles.isEmpty) {
    return true;
  }
  final String haystack = indexableText(text);
  for (final String needle in needles) {
    if (!haystack.contains(needle)) {
      return false;
    }
  }
  return true;
}

String _blockquote(String text) {
  final List<String> lines = text.trim().split('\n');
  return lines.map((String line) => '> ${line.trim()}').join('\n>\n');
}

String _escapeHeading(String value) {
  final String trimmed = value.trim();
  return trimmed.isEmpty ? 'Без названия' : trimmed.replaceAll('\n', ' ');
}

String _date(DateTime moment) {
  final String day = moment.day.toString().padLeft(2, '0');
  final String month = moment.month.toString().padLeft(2, '0');
  return '$day.$month.${moment.year}';
}
