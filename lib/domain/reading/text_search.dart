/// Поиск по тексту книги — чистые функции над строкой страницы.
///
/// Движок PDF отдаёт текст страницы так, как он лежит в файле: с
/// переносами посреди предложения, двойными пробелами и `\r\n` между
/// строками. Искать по нему «как есть» бессмысленно — фраза из двух слов
/// не найдётся, если между словами оказался перенос строки. Поэтому текст
/// сначала нормализуется, поиск идёт по нормализованному, а найденное
/// возвращается с координатами в исходном тексте: по ним строится
/// подсветка на странице.
///
/// **Сравнение — без регистра, без разницы между `ё` и `е` и с оглядкой
/// на буквы-двойники** (F-TEXT-04, ALG-TXT-07). Текстовый слой книги,
/// прошедшей распознавание, сплошь и рядом несёт латинские буквы на
/// месте кириллических: `сердце` записано как `cepдцe`, и на экране их
/// не отличить. Двойники сворачиваются тем же правилом, что у поиска по
/// книгам устройства ([kHomoglyphFolding]) — но, в отличие от него,
/// совпадение, которое держится только на свёртке, принимается лишь в
/// слове, написанном двумя алфавитами разом. Иначе `рот` находился бы в
/// `hypothesis`, а `вас` — в `bacillus`: в учебнике с латинскими
/// терминами это не редкость, а шум на каждой странице.
///
/// Все виды текста — показанный, без регистра, свёрнутый — одной длины,
/// знак в знак: место совпадения в одном есть место в любом другом.
library;

import '../library/search_text.dart';

/// Знак, которым движок помечает перенос слова в конце строки.
///
/// PDFium дефис в конце строки, за которым слово продолжается, в тексте
/// страницы не отдаёт: на его месте стоит служебный знак U+0002, а
/// перевода строки после него нет — `остео`, знак, `логия`. Закреплено
/// на настоящем движке файлом `hyphen_breaks.pdf` корпуса.
///
/// По тексту не узнать, что стояло на бумаге: перенос обычного слова
/// или дефис составного, попавший на конец строки. Поэтому поиск читает
/// знак **двояко** (BUG-50): как ничто — «остеология» находит `остео`,
/// знак, `логия` — и как дефис — «сердечно-сосудистая» находит
/// `сердечно`, знак, `сосудистая`. В запросе знака нет вовсе.
///
/// Оговорка: у шрифта без таблицы соответствия движок отдаёт сырые коды
/// знаков, и код 2 там — обычная буква. Набором в такой книге не ищут
/// всё равно, а для неё это значит одно: буква с кодом 2 поиску не
/// видна.
const int kLineBreakHyphen = 0x02;

/// Текст страницы, подготовленный к поиску.
class SearchableText {
  const SearchableText._(this.text, this.sourceIndex);

  /// Готовит текст: пробельные последовательности схлопываются в один
  /// пробел, края обрезаются, для каждого символа запоминается его место
  /// в исходной строке. Знак переноса слова ([kLineBreakHyphen])
  /// выбрасывается: слово по обе стороны от него становится целым, а
  /// место совпадения в исходном тексте по-прежнему известно до знака.
  /// С [breaksAsHyphens] знак, наоборот, становится дефисом — так текст
  /// читается, если на конец строки попал дефис составного слова.
  factory SearchableText.of(String raw, {bool breaksAsHyphens = false}) {
    final StringBuffer buffer = StringBuffer();
    final List<int> map = <int>[];
    bool pendingSpace = false;
    for (int i = 0; i < raw.length; i++) {
      String char = raw[i];
      if (char.codeUnitAt(0) == kLineBreakHyphen) {
        if (!breaksAsHyphens) {
          continue;
        }
        char = '-';
      }
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

/// Латинские двойники кириллических букв по кодам знаков.
final Map<int, int> _lookalikes = <int, int>{
  for (final MapEntry<String, String> pair in kHomoglyphFolding.entries)
    pair.key.codeUnitAt(0): pair.value.codeUnitAt(0),
};

/// Снимает регистр, не меняя длины строки.
///
/// У редких букв длина при смене регистра меняется (`İ`). Тогда регистр
/// снимается познаково, а такая буква остаётся как была: место
/// совпадения в исходном тексте важнее, чем находка по ней.
String _lowered(String text) {
  final String lowered = text.toLowerCase();
  if (lowered.length == text.length) {
    return lowered;
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final String char = text[i];
    final String low = char.toLowerCase();
    out.write(low.length == 1 ? low : char);
  }
  return out.toString();
}

/// Текст без регистра и без разницы между `ё` и `е`. Длина прежняя.
String plainSearchText(String text) => _lowered(text).replaceAll('ё', 'е');

/// [plain] со свёрнутыми буквами-двойниками: кириллические `а`, `е`,
/// `о`, `р`, `с` и остальные из [kHomoglyphFolding] становятся
/// латинскими. Длина прежняя.
String foldedSearchText(String plain) {
  List<int>? units;
  for (int i = 0; i < plain.length; i++) {
    final int? twin = _lookalikes[plain.codeUnitAt(i)];
    if (twin != null) {
      units ??= List<int>.of(plain.codeUnits);
      units[i] = twin;
    }
  }
  return units == null ? plain : String.fromCharCodes(units);
}

bool _isLatin(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

bool _isCyrillic(int unit) => unit >= 0x400 && unit <= 0x4FF;

bool _isLetter(int unit) => _isLatin(unit) || _isCyrillic(unit);

/// Честно ли совпадение, найденное по свёрнутому тексту.
///
/// [shown] — текст как он есть, [plain] — он же без регистра и `ё`,
/// [needle] — запрос в том же виде, [at] — место совпадения. Знаки,
/// совпавшие и без свёртки, вопросов не вызывают. Знак, совпавший только
/// как двойник, принимается, если слово вокруг него написано двумя
/// алфавитами разом: так выглядит ошибка распознавания, а не другое
/// слово.
bool _isHonestMatch(String shown, String plain, String needle, int at) {
  final int end = at + needle.length;
  int i = at;
  while (i < end) {
    if (plain.codeUnitAt(i) == needle.codeUnitAt(i - at)) {
      i++;
      continue;
    }
    int from = i;
    while (from > 0 && _isLetter(shown.codeUnitAt(from - 1))) {
      from--;
    }
    int to = i + 1;
    while (to < shown.length && _isLetter(shown.codeUnitAt(to))) {
      to++;
    }
    bool latin = false;
    bool cyrillic = false;
    for (int k = from; k < to; k++) {
      final int unit = shown.codeUnitAt(k);
      latin = latin || _isLatin(unit);
      cyrillic = cyrillic || _isCyrillic(unit);
    }
    if (!latin || !cyrillic) {
      return false;
    }
    // Слово целиком проверено: дальше — следующее.
    i = to;
  }
  return true;
}

/// Ищет [query] в тексте одной страницы.
///
/// Поиск нечувствителен к регистру, если [caseSensitive] ложно, и всегда
/// нечувствителен к тому, как в файле расставлены переносы строк. Без
/// учёта регистра он не различает и `ё` с `е`, а буквы-двойники сводит
/// вместе там, где слово написано двумя алфавитами (см. описание файла).
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
  final List<SearchHit> hits = _findPrepared(
    prepared: SearchableText.of(pageText),
    pageNumber: pageNumber,
    needle: needle,
    caseSensitive: caseSensitive,
    snippetRadius: snippetRadius,
    limit: limit,
  );
  // BUG-50: знак переноса читается и как дефис. Второй проход нужен
  // только запросу с дефисом на странице, где такой знак есть: иначе он
  // нашёл бы то же самое.
  if (!needle.contains('-') || !pageText.codeUnits.contains(kLineBreakHyphen)) {
    return hits;
  }
  final List<SearchHit> hyphened = _findPrepared(
    prepared: SearchableText.of(pageText, breaksAsHyphens: true),
    pageNumber: pageNumber,
    needle: needle,
    caseSensitive: caseSensitive,
    snippetRadius: snippetRadius,
    limit: limit,
  );
  // Место, найденное обоими чтениями, берётся из второго: в запросе
  // дефис есть, и отрывки одной страницы показаны одинаково — с ним.
  final List<SearchHit> all = <SearchHit>[
    ...hyphened,
    for (final SearchHit hit in hits)
      if (!hyphened.contains(hit)) hit,
  ]..sort(compareSearchHits);
  return all.length > limit ? all.sublist(0, limit) : all;
}

/// Порядок совпадений одной страницы: как они идут в её тексте.
int compareSearchHits(SearchHit a, SearchHit b) {
  final int byStart = a.sourceStart.compareTo(b.sourceStart);
  return byStart != 0 ? byStart : a.sourceEnd.compareTo(b.sourceEnd);
}

/// Ищет [needle] в уже подготовленном тексте страницы.
List<SearchHit> _findPrepared({
  required SearchableText prepared,
  required int pageNumber,
  required String needle,
  required bool caseSensitive,
  required int snippetRadius,
  required int limit,
}) {
  final String shown = prepared.text;
  final String plain = caseSensitive ? shown : plainSearchText(shown);
  final String plainNeedle = caseSensitive ? needle : plainSearchText(needle);
  final String haystack = caseSensitive ? shown : foldedSearchText(plain);
  final String pattern = caseSensitive ? needle : foldedSearchText(plainNeedle);

  final List<SearchHit> hits = <SearchHit>[];
  int from = 0;
  while (hits.length < limit) {
    final int at = haystack.indexOf(pattern, from);
    if (at < 0) {
      break;
    }
    if (!caseSensitive && !_isHonestMatch(shown, plain, plainNeedle, at)) {
      // Совпало только двойниками, а слово написано одним алфавитом:
      // это другое слово. Следующее совпадение может начинаться внутри
      // этого — шаг на один знак.
      from = at + 1;
      continue;
    }
    final int end = at + pattern.length;
    final int snippetStart = at - snippetRadius < 0 ? 0 : at - snippetRadius;
    final int snippetEnd = end + snippetRadius > shown.length
        ? shown.length
        : end + snippetRadius;
    final String core = shown.substring(snippetStart, snippetEnd);
    final String prefix = snippetStart > 0 ? '…' : '';
    final String suffix = snippetEnd < shown.length ? '…' : '';
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
    // В запросе знака переноса нет вовсе: вставленный из буфера текст
    // может принести его с собой (BUG-51).
    if (char.codeUnitAt(0) == kLineBreakHyphen) {
      continue;
    }
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
