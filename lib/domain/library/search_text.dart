/// Нормализация текста для поиска по книгам устройства.
///
/// Библиотека на телефоне собрана из чего попало: имена файлов пишут
/// сканеры, торренты, мессенджеры и сам читатель, и одна и та же книга
/// называется то «Война и мир», то «voina_i_mir», то «ВОЙНА И МИР(1).pdf».
/// Искать по такому набору дословно бессмысленно — поэтому и текст, и
/// запрос приводятся к одному виду.
///
/// Здесь чистая математика над строками: ни базы, ни файлов, ни Flutter.
/// Благодаря этому вся нормализация проверяется обычными юнит-тестами на
/// корпусе запросов, а не руками на телефоне.
library;

/// Свёртка похожих букв: латиница и кириллица приводятся к одному знаку.
///
/// **Это самое важное место во всём поиске.** В именах сканов и книг,
/// прошедших через распознавание или чужую раскладку, кириллические буквы
/// сплошь и рядом заменены латинскими двойниками: `ВОЙНА` набрано с
/// латинскими `B`, `O`, `H`, `A` и выглядит на экране точно так же, как
/// настоящее. Без свёртки такая книга не находится по собственному
/// названию — и это не редкость, а половина сканов.
///
/// Свёрнуты все пары, неразличимые глазом в **заглавном** начертании
/// (владелец назвал `А`, `О`, `Е`, `С`, `Р` — здесь их полный набор).
/// Направление выбрано к латинице: важно не то, какой алфавит победил, а
/// то, что запрос и текст сворачиваются одинаково.
///
/// Цена честная: `сор` и `cop` после свёртки совпадают. Для поиска по
/// именам файлов это дешевле, чем ненайденная книга.
const Map<String, String> kHomoglyphFolding = <String, String>{
  'а': 'a',
  'в': 'b',
  'е': 'e',
  'ё': 'e',
  'к': 'k',
  'м': 'm',
  'н': 'h',
  'о': 'o',
  'р': 'p',
  'с': 'c',
  'т': 't',
  'у': 'y',
  'х': 'x',
};

/// Окончания, которые снимает простой стеммер.
///
/// Это не морфология русского языка, а огрубление: «книги» и «книга»
/// обязаны находиться друг по другу. Список записан живыми окончаниями и
/// сворачивается тем же [foldSearchText], что и текст, — иначе пришлось бы
/// держать его в свёрнутом виде (`ob` вместо `ов`) и править вслепую.
///
/// Порядок важен: список идёт от длинных окончаний к коротким, и снимается
/// первое подошедшее.
const List<String> kSimpleEndings = <String>[
  'ями',
  'ами',
  'ого',
  'ему',
  'ому',
  'ыми',
  'ими',
  'ой',
  'ый',
  'ий',
  'ая',
  'яя',
  'ое',
  'ее',
  'ые',
  'ие',
  'ов',
  'ев',
  'ам',
  'ям',
  'ах',
  'ях',
  'ом',
  'ем',
  'а',
  'я',
  'ы',
  'и',
  'о',
  'е',
  'у',
  'ю',
  'ь',
  'й',
];

/// Короче этого слово не стеммится вовсе.
///
/// На коротких словах окончание неотличимо от корня: у `дом` снять `о`
/// значит превратить его в `дм`.
const int kStemMinLength = 5;

/// Короче этого не остаётся после снятия окончания.
const int kStemMinStem = 3;

/// Приводит строку к виду, в котором сравниваются текст и запрос.
///
/// Регистр снимается, `ё` становится `е`, похожие буквы сворачиваются.
/// Порядок именно такой: свёртка описана в нижнем регистре, и заглавная
/// латинская `В` доходит до неё уже как `в`.
String foldSearchText(String raw) {
  final StringBuffer out = StringBuffer();
  for (final int rune in raw.toLowerCase().runes) {
    final String char = String.fromCharCode(rune);
    out.write(kHomoglyphFolding[char] ?? char);
  }
  return out.toString();
}

/// Снимает с уже свёрнутого слова простое окончание.
///
/// Работает по [kSimpleEndings], свёрнутым тем же правилом. Снимается
/// ровно одно — самое длинное подходящее: цепочка отсечений превращает
/// слова в огрызки, по которым совпадает что угодно.
String stemFolded(String token) {
  if (token.length < kStemMinLength) {
    return token;
  }
  for (final String ending in kSimpleEndings) {
    final String folded = foldSearchText(ending);
    if (folded.length > token.length - kStemMinStem) {
      continue;
    }
    if (token.endsWith(folded)) {
      return token.substring(0, token.length - folded.length);
    }
  }
  return token;
}

/// Разбивает строку на слова поиска.
///
/// Словом считается связка букв и цифр; всё прочее — разделитель. Так
/// `voyna_i_mir(1).pdf` распадается ровно на то, из чего состоит, а
/// пунктуация не утекает в индекс: в FTS5 она означала бы совсем другое.
List<String> searchTokens(String raw, {bool stem = true}) {
  final String folded = foldSearchText(raw);
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();

  void flush() {
    if (current.isEmpty) {
      return;
    }
    final String token = current.toString();
    current.clear();
    tokens.add(stem ? stemFolded(token) : token);
  }

  for (final int rune in folded.runes) {
    if (_isWordRune(rune)) {
      current.writeCharCode(rune);
    } else {
      flush();
    }
  }
  flush();
  return tokens;
}

/// Текст, готовый лечь в индекс: слова через пробел.
String indexableText(String raw) => searchTokens(raw).join(' ');

/// Запрос для `MATCH` в FTS5.
///
/// Каждое слово берётся в кавычки — после свёртки в нём только буквы и
/// цифры, но кавычки снимают вопрос о синтаксисе раз и навсегда.
/// К последнему слову добавляется `*`: читатель, набравший «войн»,
/// ищет «войну», а не ошибку синтаксиса. Слова соединяются `AND` —
/// пять слов запроса обязаны найтись все, иначе поиск по длинному
/// названию вернёт полполки.
String ftsQueryFor(String raw) {
  final List<String> tokens = searchTokens(raw);
  if (tokens.isEmpty) {
    return '';
  }
  final List<String> parts = <String>[];
  for (int i = 0; i < tokens.length; i++) {
    final String token = tokens[i];
    final bool last = i == tokens.length - 1;
    parts.add(last ? '"$token"*' : '"$token"');
  }
  return parts.join(' AND ');
}

/// Триграммы строки — для второго прохода по опечаткам.
///
/// Строка обрамляется пробелами, поэтому начало и конец слова весят
/// столько же, сколько середина: опечатка в первой букве иначе оставалась
/// бы незамеченной.
Set<String> trigramsOf(String raw) {
  final String text = ' ${searchTokens(raw, stem: false).join(' ')} ';
  final Set<String> grams = <String>{};
  if (text.trim().isEmpty) {
    return grams;
  }
  final List<int> runes = text.runes.toList();
  for (int i = 0; i + 3 <= runes.length; i++) {
    grams.add(String.fromCharCodes(runes.sublist(i, i + 3)));
  }
  return grams;
}

/// Похожесть двух строк по триграммам, от 0 до 1 (коэффициент Жаккара).
///
/// Нужна ровно там, где точный запрос дал мало: `Достаевский` обязан
/// находить `Достоевский`. Считается в Dart по именам файлов, а не в
/// базе: имён тысячи, и полный проход по ним дешевле, чем второй индекс,
/// который пришлось бы поддерживать в согласии с первым.
double trigramSimilarity(String a, String b) {
  final Set<String> first = trigramsOf(a);
  final Set<String> second = trigramsOf(b);
  if (first.isEmpty || second.isEmpty) {
    return 0;
  }
  final int common = first.intersection(second).length;
  final int total = first.length + second.length - common;
  return total == 0 ? 0 : common / total;
}

bool _isWordRune(int rune) {
  // Латиница, цифры и всё, что выше ASCII и не знак препинания. Список
  // алфавитов не перечисляется намеренно: в библиотеке встретится и
  // греческий, и грузинский, и китайский, а нам от буквы нужно ровно
  // одно — что она не разделитель.
  if (rune >= 0x30 && rune <= 0x39) {
    return true;
  }
  if (rune >= 0x61 && rune <= 0x7a) {
    return true;
  }
  if (rune < 0x80) {
    return false;
  }
  return !_isPunctuationRune(rune);
}

bool _isPunctuationRune(int rune) {
  // Знаки, которые действительно встречаются в именах файлов и в тексте
  // книг: тире, кавычки, многоточие, неразрывный пробел.
  const Set<int> punctuation = <int>{
    0x00a0, // неразрывный пробел
    0x00ab, // «
    0x00bb, // »
    0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, // тире
    0x2018, 0x2019, 0x201a, 0x201c, 0x201d, 0x201e, // кавычки
    0x2022, // точка списка
    0x2026, // многоточие
    0x00ad, // мягкий перенос
  };
  return punctuation.contains(rune);
}
