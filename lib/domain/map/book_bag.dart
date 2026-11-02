/// Слова книги для карты (F-MAP-02, ALG-MAP-02).
///
/// Вектор книги строится из её собственного текста: название, автор и
/// текст страниц разбираются на слова тем же правилом, что и поиск
/// (`domain/library/search_text.dart`), и складываются в «мешок» — слово
/// и сколько раз оно встретилось. Здесь только счёт слов одной книги;
/// что из них значимо для библиотеки в целом, решает словарь корпуса
/// (`map_vectors.dart`).
///
/// Чистые функции над строками: ни базы, ни файлов, ни Flutter.
library;

import '../library/search_text.dart';
import '../reading/text_search.dart';
import 'map_trusted.dart';

/// Короче этого слово в мешок не идёт (ALG-MAP-02): предлоги, союзы и
/// обрывки формул.
const int kBagMinToken = 3;

/// Во сколько раз слово названия весит больше слова со страницы.
const int kBagTitleWeight = 3;

/// Во сколько раз слово из имени автора весит больше слова со страницы.
const int kBagAuthorWeight = 2;

/// Сколько разных слов остаётся в мешке одной книги.
///
/// В толстом учебнике разных слов десятки тысяч, и хвост — опечатки
/// распознавания и слова, встреченные по разу. Мешок сорока книг целиком
/// занял бы на телефоне сотни мегабайт; остаются самые частые, а длина
/// книги считается по всем словам.
const int kBagTerms = 8000;

/// Слова одной книги: что встретилось и сколько раз.
class BookBag {
  /// Создаёт мешок. [terms] стоят по возрастанию, [counts] — им в пару.
  const BookBag({
    required this.key,
    required this.group,
    required this.terms,
    required this.counts,
    required this.length,
    this.forms,
    this.trust = const BookTrust.asIs(),
  });

  /// Чем книга опознаётся — отпечаток файла: он один и тот же на всех
  /// устройствах, и порядок обхода книг в расчёте идёт по нему.
  final String key;

  /// Группа книги — название её категории; пусто — «Без категории».
  final String group;

  /// Слова по возрастанию.
  final List<String> terms;

  /// Сколько раз встретилось каждое из [terms].
  final List<int> counts;

  /// Сколько слов в книге всего — вместе с теми, что в мешок не вошли.
  final int length;

  /// Полная форма каждого из [terms] — та, что чаще всего встретилась в
  /// книге (F-MAP-03): в мешке слово стоит без окончания («анатоми»), а
  /// в имени созвездия его показывают целым («анатомия»). Элемент `null`
  /// — форма совпадает со словом мешка; весь список `null` — формы не
  /// собирались. Так в изолят не уходят тысячи лишних строк.
  final List<String?>? forms;

  /// Доверие тексту книги (F-MAP-18): строит ли книга созвездия. По
  /// умолчанию — «как есть», текст не судили.
  final BookTrust trust;

  /// Полная форма слова номер [i].
  String formAt(int i) => forms?[i] ?? terms[i];

  /// Тот же мешок, но только со словами из [allowed] (F-MAP-18): у
  /// книги с ненадёжным текстом в карту идут лишь слова, которые есть у
  /// книг с надёжным, — общие ошибки распознавания нескольких плохих
  /// книг иначе стали бы их общими «словами». Длина — по оставшимся.
  BookBag onlyWords(Set<String> allowed) {
    final List<String> keptTerms = <String>[];
    final List<int> keptCounts = <int>[];
    final List<String?>? keptForms = forms == null ? null : <String?>[];
    int total = 0;
    for (int i = 0; i < terms.length; i++) {
      if (!allowed.contains(terms[i])) continue;
      keptTerms.add(terms[i]);
      keptCounts.add(counts[i]);
      keptForms?.add(forms![i]);
      total += counts[i];
    }
    return BookBag(
      key: key,
      group: group,
      terms: keptTerms,
      counts: keptCounts,
      length: total,
      forms: keptForms,
      trust: trust,
    );
  }
}

/// Буквы-двойники поиска — по кодам, а не по строкам: разбор идёт по
/// знакам, и заводить строку на каждый значило бы тратить на книгу
/// секунды.
final Map<int, int> _folding = <int, int>{
  for (final MapEntry<String, String> entry in kHomoglyphFolding.entries)
    entry.key.codeUnitAt(0): entry.value.codeUnitAt(0),
};

/// Окончания стеммера поиска, свёрнутые один раз.
final List<String> _endings = <String>[
  for (final String ending in kSimpleEndings) foldSearchText(ending),
];

/// Разбирает [raw] на слова карты и отдаёт каждое в [take].
///
/// Слова те же, что у `searchTokens`: регистр снят, `ё` стала `е`,
/// буквы-двойники сведены, окончание снято. Разница одна — знак
/// переноса слова ([kLineBreakHyphen]) здесь не разделитель: слово,
/// разрезанное концом строки, собирается целым, иначе половины учебника
/// не досчитались бы в его собственном словаре.
///
/// Своя реализация вместо `searchTokens` — из-за скорости: та заводит
/// строку на каждый знак и сворачивает список окончаний на каждое
/// слово, и на сорока учебниках это минуты. Согласие двух разборов
/// проверяется тестом.
void forEachMapToken(String raw, void Function(String token) take) {
  forEachMapWord(raw, (String token, String word) => take(token));
}

/// То же, что [forEachMapToken], но вместе со словом мешка отдаёт и
/// целое слово, с которого сняли окончание: `анатоми` и `анатомия`.
void forEachMapWord(String raw, void Function(String token, String word) take) {
  final String lower = raw.toLowerCase();
  final List<int> word = <int>[];
  // То же слово без свёртки букв-двойников — его и показывают читателю:
  // свёрнутое «анатомия» записано наполовину латиницей.
  final List<int> shown = <int>[];

  void flush() {
    if (word.isEmpty) {
      return;
    }
    final String token = String.fromCharCodes(word);
    final String visible = String.fromCharCodes(shown);
    word.clear();
    shown.clear();
    take(_stem(token), visible);
  }

  for (int i = 0; i < lower.length; i++) {
    final int unit = lower.codeUnitAt(i);
    if (unit == kLineBreakHyphen) {
      continue;
    }
    final int folded = _folding[unit] ?? unit;
    if (isSearchWordRune(folded)) {
      word.add(folded);
      shown.add(unit);
    } else {
      flush();
    }
  }
  flush();
}

/// Слова [raw] списком — для тестов и коротких строк.
List<String> mapTokens(String raw) {
  final List<String> tokens = <String>[];
  forEachMapToken(raw, tokens.add);
  return tokens;
}

String _stem(String token) {
  if (token.length < kStemMinLength) {
    return token;
  }
  for (final String ending in _endings) {
    if (ending.length > token.length - kStemMinStem) {
      continue;
    }
    if (token.endsWith(ending)) {
      return token.substring(0, token.length - ending.length);
    }
  }
  return token;
}

/// Идёт ли слово в мешок: не короче [kBagMinToken] и не одни цифры.
///
/// Числа — номера страниц, годы, значения из таблиц — стоят в каждой
/// книге и о её содержании не говорят.
bool isBagToken(String token) {
  if (token.length < kBagMinToken) {
    return false;
  }
  for (int i = 0; i < token.length; i++) {
    final int unit = token.codeUnitAt(i);
    if (unit < 0x30 || unit > 0x39) {
      return true;
    }
  }
  return false;
}

/// Собирает мешок одной книги.
class BagBuilder {
  final Map<String, int> _counts = <String, int>{};

  /// Слово мешка → его целые формы и сколько раз встретилась каждая.
  final Map<String, Map<String, int>> _forms = <String, Map<String, int>>{};
  int _length = 0;

  /// Добавляет слова текста [text]; каждое считается [weight] раз.
  void add(String text, {int weight = 1}) {
    if (weight <= 0 || text.isEmpty) {
      return;
    }
    forEachMapWord(text, (String token, String word) {
      if (!isBagToken(token)) {
        return;
      }
      _counts[token] = (_counts[token] ?? 0) + weight;
      final Map<String, int> forms = _forms.putIfAbsent(
        token,
        () => <String, int>{},
      );
      forms[word] = (forms[word] ?? 0) + weight;
      _length += weight;
    });
  }

  /// Готовый мешок: [limit] самых частых слов, по возрастанию.
  ///
  /// При равном счёте остаётся слово, которое раньше по алфавиту, —
  /// чтобы мешок не зависел от порядка, в котором слова встретились.
  BookBag build({
    required String key,
    required String group,
    int limit = kBagTerms,
  }) {
    final List<MapEntry<String, int>> entries = _counts.entries.toList();
    if (entries.length > limit) {
      entries.sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
      entries.removeRange(limit, entries.length);
    }
    entries.sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          a.key.compareTo(b.key),
    );
    return BookBag(
      key: key,
      group: group,
      terms: <String>[
        for (final MapEntry<String, int> entry in entries) entry.key,
      ],
      counts: <int>[
        for (final MapEntry<String, int> entry in entries) entry.value,
      ],
      length: _length,
      forms: <String?>[
        for (final MapEntry<String, int> entry in entries) _formOf(entry.key),
      ],
    );
  }

  /// Самая частая целая форма слова; при равном счёте — первая по
  /// алфавиту, чтобы не зависеть от порядка, в котором формы встретились.
  /// `null` — форма совпадает с самим словом.
  String? _formOf(String token) {
    String best = token;
    int top = -1;
    final Map<String, int> forms = _forms[token] ?? const <String, int>{};
    for (final MapEntry<String, int> entry in forms.entries) {
      if (entry.value > top ||
          (entry.value == top && entry.key.compareTo(best) < 0)) {
        best = entry.key;
        top = entry.value;
      }
    }
    return best == token ? null : best;
  }
}

/// Что нужно, чтобы собрать мешок книги.
class BagRequest {
  /// Создаёт запрос.
  const BagRequest({
    required this.key,
    required this.group,
    required this.title,
    required this.pages,
    this.author,
  });

  /// Отпечаток файла книги.
  final String key;

  /// Название категории; пусто — «Без категории».
  final String group;

  /// Название книги.
  final String title;

  /// Автор, если известен.
  final String? author;

  /// Текст страниц книги — сколько есть.
  final List<String> pages;
}

/// Мешок книги по её названию, автору и тексту страниц (ALG-MAP-02).
///
/// Скан без текста получает мешок из одного названия.
BookBag bagOfBook(BagRequest request) {
  final BagBuilder builder = BagBuilder();
  builder.add(request.title, weight: kBagTitleWeight);
  final String? author = request.author;
  if (author != null) {
    builder.add(author, weight: kBagAuthorWeight);
  }
  for (final String page in request.pages) {
    builder.add(page);
  }
  return builder.build(key: request.key, group: request.group);
}
