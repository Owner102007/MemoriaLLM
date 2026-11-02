/// Доверие текстовому слою (ALG-MAP-19): правило на придуманном словаре
/// и настоящий срез wordfreq (`assets/lexicon/words.txt.gz`) на чистом,
/// шумном и сломанном тексте.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/exact_math.dart';
import 'package:memoria/domain/map/file_passport.dart';
import 'package:memoria/domain/map/text_trust.dart';
import 'package:memoria/infrastructure/files/lexicon_asset.dart';

/// Свой текст для проверки: обычная русская проза о чтении (написан для
/// теста, чужих прав нет). Около 120 слов от трёх букв.
const String _prose = '''
Когда человек открывает новую книгу, он сначала смотрит на обложку, потом
листает оглавление и только после этого начинает читать первую главу.
Хорошая книга не торопит читателя: она позволяет вернуться назад,
перечитать трудное место и подумать над каждой мыслью. Поэтому многие
люди держат на столе карандаш и записывают на полях свои вопросы. Через
несколько дней такие заметки помогают вспомнить, о чём шла речь, и понять,
что осталось непонятным. Библиотека большого города хранит тысячи книг по
истории, медицине, математике и литературе. Студенты приходят туда
готовиться к экзаменам, а пожилые читатели любят тихие залы, где можно
спокойно провести целый день. Каждая полка устроена так, чтобы похожие
книги стояли рядом: учебники по анатомии рядом с атласами, сборники задач
рядом с теорией. Если книга стоит не на своём месте, её трудно найти, и
библиотекарь долго ищет её по каталогу. Современная читалка делает то же
самое сама: она смотрит на слова книги и ставит её рядом с похожими.
''';

/// Буквы русского алфавита — для порчи текста.
const String _ru = 'абвгдежзийклмнопрстуфхцчшщъыьэюя';

/// Шум распознавания с долей ошибок в буквах [cer] — упрощённый
/// перенос `ocr_noise` шага 46: замены, пропуски, вставки, разрывы слов
/// и склейки (пропавший пробел).
String _noisy(String text, double cer, int seed) {
  final MapRandom random = MapRandom(seed);
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    final String ch = String.fromCharCode(rune);
    final double u = random.unit();
    final double kind = random.unit();
    final int pick = random.below(_ru.length);
    if (ch == ' ') {
      if (u < cer / 3) continue;
      out.write(ch);
      continue;
    }
    if (!_ru.contains(ch.toLowerCase()) || u >= cer) {
      out.write(ch);
      continue;
    }
    if (kind < 0.6) {
      out.write(_ru[pick]);
    } else if (kind < 0.8) {
      continue;
    } else if (kind < 0.9) {
      out
        ..write(ch)
        ..write(_ru[pick]);
    } else {
      out
        ..write(ch)
        ..write(' ');
    }
  }
  return out.toString();
}

/// Сломанный слой: каждой букве — чужая буква, одна на весь текст.
String _broken(String text) {
  const String shuffled = 'щшэюяфхцчъыьабвгдежзийклмнопрсту';
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    final String ch = String.fromCharCode(rune);
    final int lower = _ru.indexOf(ch);
    final int upper = _ru.toUpperCase().indexOf(ch);
    if (lower >= 0) {
      out.write(shuffled[lower]);
    } else if (upper >= 0) {
      out.write(shuffled[upper].toUpperCase());
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// Текст из [n] словарных слов придуманного словаря.
String _words(int n, {String word = 'слово'}) =>
    List<String>.filled(n, word).join(' ');

void main() {
  group('ALG-MAP-19: доля словарных слов', () {
    final Lexicon lexicon = SetLexicon(<String>['книга', 'ежик', 'слово']);

    test('ALG-MAP-19: слова короче трёх букв и цифры не считаются', () {
      final PageShare share = layerShare('Книга и 12 он мир1книга', lexicon);
      // «Книга», «мир», «книга»: «и», «он» коротки, 12 и 1 рвут слово.
      expect(share.words, 3);
      expect(share.share, closeTo(2 / 3, 1e-12));
    });

    test('ALG-MAP-19: «ё» ищется и как «е»', () {
      expect(layerShare('Ёжик', lexicon).share, 1);
    });

    test('ALG-MAP-19: страница без слов — доли нет', () {
      final PageShare share = layerShare('12 — 34, ...', lexicon);
      expect(share.words, 0);
      expect(share.share, isNull);
    });
  });

  group('ALG-MAP-19: состояние страницы', () {
    test('ALG-MAP-19: пусто, коротко, да, нет — пороги 30 слов и τ 0,25', () {
      expect(pageTrustOf(const PageShare(null, 0)), PageTrust.empty);
      expect(pageTrustOf(const PageShare(0.0, 29)), PageTrust.short);
      expect(pageTrustOf(const PageShare(0.25, 30)), PageTrust.yes);
      expect(pageTrustOf(const PageShare(0.24, 30)), PageTrust.no);
    });
  });

  group('ALG-MAP-19: доверие книги', () {
    final Lexicon lexicon = SetLexicon(<String>['слово']);
    // Страница «да» с долей 0,86: 43 словарных слова из 50.
    final String clean = '${_words(43)} ${_words(7, word: 'шум')}';
    // Страница «нет»: 5 словарных из 50.
    final String noise = '${_words(5)} ${_words(45, word: 'шум')}';

    test('ALG-MAP-19: страниц «да» меньше пяти — надёжного текста нет', () {
      final TextTrust trust = textTrustOf(<String>[
        for (int i = 0; i < 4; i++) clean,
        noise,
      ], lexicon);
      expect(trust.noReliableText, isTrue);
      expect(trust.unreliable, isTrue);
    });

    test('ALG-MAP-19: T — медиана доли страниц «да», делённая на 0,86', () {
      final TextTrust trust = textTrustOf(<String>[
        for (int i = 0; i < 6; i++) clean,
      ], lexicon);
      expect(trust.trust, closeTo(1.0, 1e-12));
      expect(trust.unreliable, isFalse);
      expect(trust.usedPages, <int>[0, 1, 2, 3, 4, 5]);
    });

    test('ALG-MAP-19: текст меньше чем на 80 % страниц — T не выше доли', () {
      // 5 страниц «да» из 10: T ≤ 0,8 · 5 / (0,8 · 10) = 0,5.
      final TextTrust trust = textTrustOf(<String>[
        for (int i = 0; i < 5; i++) clean,
        for (int i = 0; i < 5; i++) noise,
      ], lexicon);
      expect(trust.trust, closeTo(0.5, 1e-12));
      expect(trust.unreliable, isTrue);
      // Слой страниц «нет» в мешок книги не идёт.
      expect(trust.usedPages, <int>[0, 1, 2, 3, 4]);
    });

    test('ALG-MAP-19: пустые по паспорту страницы в счёт не входят', () {
      // 5 страниц «да» и 2 пустых листа (форзац, концевая полоса).
      final TextTrust trust = textTrustOf(
        <String>[for (int i = 0; i < 5; i++) clean, '', ''],
        lexicon,
        kinds: <PageKind>[
          for (int i = 0; i < 5; i++) PageKind.text,
          PageKind.empty,
          PageKind.empty,
        ],
      );
      expect(trust.trust, closeTo(1.0, 1e-12));
    });
  });

  group('ALG-MAP-19: настоящий словарь (срез wordfreq, D-047)', () {
    late SortedLexicon lexicon;

    setUpAll(() {
      lexicon = SortedLexicon.compressed(File(kLexiconAsset).readAsBytesSync());
    });

    test('ALG-MAP-19: в словаре ~285 тыс. форм, частые слова на месте', () {
      expect(lexicon.length, greaterThan(280000));
      for (final String word in <String>[
        'книга',
        'библиотека',
        'читателя',
        'the',
        'reading',
      ]) {
        expect(lexicon.knows(word), isTrue, reason: word);
      }
      expect(lexicon.knows('щшэюяф'), isFalse);
      expect(lexicon.knows(''), isFalse);
    });

    test('ALG-MAP-19: чистый текст — доля около 0,86 и выше τ', () {
      final PageShare share = layerShare(_prose, lexicon);
      stdout.writeln(
        'ЗАМЕР ALG-MAP-19 | свой текст | слов ${share.words} | '
        'доля ${share.share!.toStringAsFixed(3)}',
      );
      expect(share.words, greaterThan(100));
      expect(share.share, greaterThan(0.8));
      // Эталон: `доверие.py` шага 46 с wordfreq 3.1.1 напрямую даёт на
      // этом тексте 121 словарное слово из 123 — срез не потерял ни одного.
      expect(share.words, 123);
      expect(share.share, 121 / 123);
    });

    test('ALG-MAP-19: порог отделяет 30 % ошибок от чистого текста', () {
      for (int seed = 1; seed <= 5; seed++) {
        final double five = layerShare(
          _noisy(_prose, 0.05, seed),
          lexicon,
        ).share!;
        final double thirty = layerShare(
          _noisy(_prose, 0.30, seed),
          lexicon,
        ).share!;
        stdout.writeln(
          'ЗАМЕР ALG-MAP-19 | шум, зерно $seed | 5 % — '
          '${five.toStringAsFixed(3)} | 30 % — ${thirty.toStringAsFixed(3)}',
        );
        expect(five, greaterThanOrEqualTo(kPageTrustShare));
        expect(thirty, lessThan(kPageTrustShare));
      }
    });

    test('ALG-MAP-19: сломанный слой — почти ноль словарных слов', () {
      final double share = layerShare(_broken(_prose), lexicon).share!;
      stdout.writeln(
        'ЗАМЕР ALG-MAP-19 | сломанный слой | доля ${share.toStringAsFixed(3)}',
      );
      expect(share, lessThan(0.05));
    });
  });
}
