/// Поиск по тексту книги — чистые функции над строкой страницы.
///
/// Движок PDF отдаёт текст страницы так, как он лежит в файле: с
/// переносами посреди предложения, двойными пробелами и `\r\n` между
/// строками. Искать по нему «как есть» бессмысленно — фраза из двух слов
/// не найдётся, если между словами оказался перенос строки. Поэтому текст
/// сначала нормализуется, поиск идёт по нормализованному, а найденное
/// возвращается с координатами в исходном тексте: они понадобятся
/// подсветке в S6.
library;

/// Текст страницы, подготовленный к поиску.
class SearchableText {
  const SearchableText._(this.text, this.sourceIndex);

  /// Готовит текст: пробельные последовательности схлопываются в один
  /// пробел, края обрезаются, для каждого символа запоминается его место
  /// в исходной строке.
  factory SearchableText.of(String raw) {
    final StringBuffer buffer = StringBuffer();
    final List<int> map = <int>[];
    bool pendingSpace = false;
    for (int i = 0; i < raw.length; i++) {
      final String char = raw[i];
      if (_isWhitespace(char)) {
        if (buffer.isNotEmpty) {
          pendingSpace = true;
        }
        continue;
      }
      if (pendingSpace) {
        buffer.write(' ');
        map.add(i);
        pendingSpace = false;
      }
      buffer.write(char);
      map.add(i);
    }
    return SearchableText._(buffer.toString(), map);
  }

  /// Нормализованный текст.
  final String text;

  /// `sourceIndex[i]` — индекс символа `text[i]` в исходной строке.
  final List<int> sourceIndex;

  /// Индекс в исходном тексте для позиции [index] в нормализованном.
  int sourceOf(int index) {
    if (sourceIndex.isEmpty) {
      return 0;
    }
    if (index < 0) {
      return sourceIndex.first;
    }
    if (index >= sourceIndex.length) {
      return sourceIndex.last + 1;
    }
    return sourceIndex[index];
  }
}

/// Пробельный ли символ.
///
/// Кроме обычных пробелов и переводов строки сюда попадают неразрывный
/// пробел `U+00A0` и мягкий перенос `U+00AD`: в PDF они встречаются
/// сплошь и рядом, а человек, набирающий запрос, о них не думает.
bool _isWhitespace(String char) {
  final int code = char.codeUnitAt(0);
  return code == 0x20 || // пробел
      code == 0x09 || // табуляция
      code == 0x0A || // перевод строки
      code == 0x0B ||
      code == 0x0C ||
      code == 0x0D || // возврат каретки
      code == 0xA0 || // неразрывный пробел
      code == 0xAD || // мягкий перенос
      code == 0x2007 ||
      code == 0x200B || // нулевой пробел
      code == 0x202F ||
      code == 0x3000; // идеографический пробел
}

/// Одно совпадение.
class SearchHit {
  /// Создаёт совпадение.
  const SearchHit({
    required this.pageNumber,
    required this.sourceStart,
    required this.sourceEnd,
    required this.snippet,
    required this.snippetMatchStart,
    required this.snippetMatchEnd,
  });

  /// Страница, начиная с единицы.
  final int pageNumber;

  /// Начало совпадения в исходном тексте страницы.
  final int sourceStart;

  /// Конец совпадения в исходном тексте страницы (не включая).
  final int sourceEnd;

  /// Фрагмент вокруг совпадения — то, что видно в списке результатов.
  final String snippet;

  /// Начало совпадения внутри [snippet].
  final int snippetMatchStart;

  /// Конец совпадения внутри [snippet].
  final int snippetMatchEnd;

  /// Совпавший текст.
  String get matchedText =>
      snippet.substring(snippetMatchStart, snippetMatchEnd);

  @override
  bool operator ==(Object other) {
    return other is SearchHit &&
        other.pageNumber == pageNumber &&
        other.sourceStart == sourceStart &&
        other.sourceEnd == sourceEnd;
  }

  @override
  int get hashCode => Object.hash(pageNumber, sourceStart, sourceEnd);

  @override
  String toString() => 'SearchHit(стр. $pageNumber, «$snippet»)';
}

/// Готов ли запрос к поиску.
///
/// Односимвольный запрос находит пол-книги и только мешает, поэтому
/// поиск начинается с двух непробельных символов.
bool isSearchableQuery(String query) => query.trim().length >= 2;

/// Ищет [query] в тексте одной страницы.
///
/// Поиск нечувствителен к регистру, если [caseSensitive] ложно, и всегда
/// нечувствителен к тому, как в файле расставлены переносы строк.
/// [snippetRadius] — сколько символов контекста показать с каждой стороны.
List<SearchHit> findInPageText({
  required int pageNumber,
  required String pageText,
  required String query,
  bool caseSensitive = false,
  int snippetRadius = 48,
  int limit = 200,
}) {
  final String needle = _collapse(query);
  if (needle.isEmpty || pageText.isEmpty) {
    return const <SearchHit>[];
  }
  final SearchableText prepared = SearchableText.of(pageText);
  final String haystack = caseSensitive
      ? prepared.text
      : prepared.text.toLowerCase();
  final String pattern = caseSensitive ? needle : needle.toLowerCase();

  final List<SearchHit> hits = <SearchHit>[];
  int from = 0;
  while (hits.length < limit) {
    final int at = haystack.indexOf(pattern, from);
    if (at < 0) {
      break;
    }
    final int end = at + pattern.length;
    final int snippetStart = at - snippetRadius < 0 ? 0 : at - snippetRadius;
    final int snippetEnd = end + snippetRadius > prepared.text.length
        ? prepared.text.length
        : end + snippetRadius;
    final String core = prepared.text.substring(snippetStart, snippetEnd);
    final String prefix = snippetStart > 0 ? '…' : '';
    final String suffix = snippetEnd < prepared.text.length ? '…' : '';
    hits.add(
      SearchHit(
        pageNumber: pageNumber,
        sourceStart: prepared.sourceOf(at),
        sourceEnd: prepared.sourceOf(end - 1) + 1,
        snippet: '$prefix$core$suffix',
        snippetMatchStart: prefix.length + (at - snippetStart),
        snippetMatchEnd: prefix.length + (end - snippetStart),
      ),
    );
    from = end;
  }
  return hits;
}

String _collapse(String value) {
  final StringBuffer buffer = StringBuffer();
  bool pendingSpace = false;
  for (int i = 0; i < value.length; i++) {
    final String char = value[i];
    if (_isWhitespace(char)) {
      if (buffer.isNotEmpty) {
        pendingSpace = true;
      }
      continue;
    }
    if (pendingSpace) {
      buffer.write(' ');
      pendingSpace = false;
    }
    buffer.write(char);
  }
  return buffer.toString();
}
