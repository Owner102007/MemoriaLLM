/// Доверие текстовому слою книги (ALG-MAP-19, F-MAP-18, шаг S58).
///
/// Карта строит созвездия по словам книг. Скан со шумным распознаванием,
/// со сломанным слоем (чужая таблица букв) или без слоя почти всегда
/// заводил своё созвездие из одной книги — мусор на карте (расчёт шага
/// 46). Здесь решается, каким страницам книги верить и можно ли книге
/// заводить созвездия.
///
/// Мера — доля «словарных» слов страницы: слов от трёх букв, которые
/// есть в частотном словаре языка (по образцу Alex, Burns, 2014). У
/// чистого русского текста она около 0,86, у распознавания с 20 %
/// ошибок в буквах — около 0,28, у сломанного слоя — около 0,01.
///
/// Правило — перенос `доверие.py` и `read_book` из `устойчивость_46.py`
/// (шаг 46) без ветки распознавания: OCR придёт в v1.2 (D-031). Словарь
/// — срез wordfreq (D-047), загружает его `infrastructure`.
library;

import 'file_passport.dart';

/// Доля словарных слов, начиная с которой странице верят (τ).
const double kPageTrustShare = 0.25;

/// Меньше этого числа слов страница не судится — берётся как есть.
const int kPageMinWords = 30;

/// Слова короче не считаются.
const int kMinWordLength = 3;

/// Доля словарных слов у чистого русского текста (по этому словарю).
const double kCleanTextShare = 0.86;

/// Доверие ниже — текст книги ненадёжен (около 3 % ошибок в буквах).
const double kTrustLow = 0.8;

/// Если текст дали меньше этой доли страниц — это тоже слабое
/// свидетельство, доверие не выше той же доли.
const double kTextCover = 0.8;

/// Надёжных страниц меньше — надёжного текста у книги нет.
const int kMinTrustedPages = 5;

/// Словарь языка: знает ли он слово.
abstract interface class Lexicon {
  /// Есть ли [word] (в нижнем регистре) в словаре.
  bool knows(String word);
}

/// Словарь из готового множества слов — для тестов и малых списков.
class SetLexicon implements Lexicon {
  /// Создаёт словарь.
  SetLexicon(Iterable<String> words) : _words = words.toSet();

  final Set<String> _words;

  @override
  bool knows(String word) => _words.contains(word);
}

/// Слово — подряд идущие буквы (и «числовые буквы» вроде римских цифр),
/// как `[^\W\d_]+` в Python шага 46: цифры, подчёркивание, знаки и
/// пробелы слово рвут.
final RegExp _word = RegExp(r'[\p{L}\p{Nl}\p{No}]+', unicode: true);

/// Сколько слов страницы и какая их доля словарная.
class PageShare {
  /// Создаёт долю.
  const PageShare(this.share, this.words);

  /// Доля словарных слов; `null` — слов нет.
  final double? share;

  /// Сколько слов от трёх букв.
  final int words;
}

/// Доля словарных слов в [text] (ALG-MAP-19, шаг 1).
///
/// Слово в нижнем регистре ищется как есть и с `ё` → `е`: словарь
/// хранит формы так, как их пишут, а в книгах `ё` то есть, то нет.
PageShare layerShare(String text, Lexicon lexicon) {
  int words = 0;
  int known = 0;
  for (final RegExpMatch match in _word.allMatches(text)) {
    final String word = match[0]!.toLowerCase();
    // Длина — в знаках Юникода, не в единицах UTF-16.
    if (word.runes.length < kMinWordLength) continue;
    words++;
    if (lexicon.knows(word) ||
        (word.contains('ё') && lexicon.knows(word.replaceAll('ё', 'е')))) {
      known++;
    }
  }
  return PageShare(words == 0 ? null : known / words, words);
}

/// Состояние страницы.
enum PageTrust {
  /// Слов нет — слоя нет.
  empty,

  /// Слов меньше [kPageMinWords] — судить не по чему, берётся как есть.
  short,

  /// Слою можно верить: доля ≥ [kPageTrustShare].
  yes,

  /// Слою верить нельзя.
  no,
}

/// Состояние страницы по её доле (ALG-MAP-19, шаг 2).
PageTrust pageTrustOf(PageShare page) {
  if (page.words == 0) return PageTrust.empty;
  if (page.words < kPageMinWords) return PageTrust.short;
  return page.share! >= kPageTrustShare ? PageTrust.yes : PageTrust.no;
}

/// Доверие книги.
class TextTrust {
  /// Создаёт доверие.
  const TextTrust({required this.pages, required this.trust});

  /// Состояние каждой страницы, по порядку.
  final List<PageTrust> pages;

  /// Доверие T от 0 до ~1,2; `null` — надёжного текста нет (страниц
  /// «да» меньше [kMinTrustedPages]).
  final double? trust;

  /// Надёжного текста нет вовсе: «Мало надёжного текста».
  bool get noReliableText => trust == null;

  /// Текст ненадёжен: книга не заводит созвездий (T < [kTrustLow]).
  bool get unreliable => trust == null || trust! < kTrustLow;

  /// Номера страниц (от нуля), чей текст идёт в мешок книги: «да» и
  /// «коротко». Слой страниц «нет» — шум, его слова в карту не идут.
  List<int> get usedPages => <int>[
    for (int i = 0; i < pages.length; i++)
      if (pages[i] == PageTrust.yes || pages[i] == PageTrust.short) i,
  ];
}

/// Доверие книги по текстам её страниц (ALG-MAP-19, шаги 3–5).
///
/// T — медиана доли по страницам «да», делённая на [kCleanTextShare].
/// Если текст дали меньше [kTextCover] страниц, T не выше доли страниц с
/// текстом. Страницы, пустые по паспорту ([kinds], если он есть), в
/// счёт страниц не входят: пустая страница — не недостаток текста.
TextTrust textTrustOf(
  List<String> pageTexts,
  Lexicon lexicon, {
  List<PageKind>? kinds,
}) {
  final List<PageShare> shares = <PageShare>[
    for (final String text in pageTexts) layerShare(text, lexicon),
  ];
  final List<PageTrust> states = <PageTrust>[
    for (final PageShare share in shares) pageTrustOf(share),
  ];
  final List<double> judged = <double>[
    for (int i = 0; i < shares.length; i++)
      if (states[i] == PageTrust.yes) shares[i].share!,
  ];
  if (judged.length < kMinTrustedPages) {
    return TextTrust(pages: states, trust: null);
  }
  double trust = _median(judged) / kCleanTextShare;
  int counted = 0;
  int used = 0;
  for (int i = 0; i < states.length; i++) {
    final bool blank =
        kinds != null && i < kinds.length && kinds[i] == PageKind.empty;
    if (blank) continue;
    counted++;
    if (states[i] == PageTrust.yes || states[i] == PageTrust.short) used++;
  }
  if (counted > 0 && used < kTextCover * counted) {
    // Как в шаге 46: T не выше kTrustLow · used / (kTextCover · counted).
    final double cap = kTrustLow * used / (kTextCover * counted);
    if (cap < trust) trust = cap;
  }
  return TextTrust(pages: states, trust: trust);
}

/// Медиана; при чётном числе — среднее двух средних (как numpy).
double _median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}
