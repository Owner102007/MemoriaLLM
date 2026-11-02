/// Частотный словарь для доверия тексту сканов (ALG-MAP-19, D-047).
///
/// Файл `assets/lexicon/words.txt.gz` собирает `tool/make_lexicon.py`
/// из данных wordfreq: около 285 тыс. русских и английских форм, по
/// одной на строку, по кодам знаков. Данные — CC BY-SA 4.0
/// (`assets/lexicon/NOTICE`); авторство регистрируется в списке лицензий
/// приложения ([registerLexiconLicense]).
///
/// Почему не `Set<String>`: 285 тыс. отдельных строк в памяти Dart —
/// 15–20 МБ, для телефона много. Здесь словарь — один блок байтов UTF-8
/// (~3 МБ) и таблица начал строк (~1 МБ); слово ищется двоичным поиском.
/// Порядок байтов UTF-8 совпадает с порядком кодов знаков, а по кодам
/// список и отсортирован (Python, `sorted`).
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';

import '../../domain/map/text_trust.dart';

/// Где лежит словарь в сборке.
const String kLexiconAsset = 'assets/lexicon/words.txt.gz';

/// Словарь из отсортированных строк UTF-8.
class SortedLexicon implements Lexicon {
  /// Создаёт словарь из распакованного файла: строки UTF-8 через `\n`,
  /// отсортированные по байтам.
  SortedLexicon(Uint8List text) : _text = text, _starts = _startsOf(text);

  /// Словарь из сжатого файла (`words.txt.gz`).
  factory SortedLexicon.compressed(List<int> bytes) =>
      SortedLexicon(Uint8List.fromList(gzip.decode(bytes)));

  final Uint8List _text;
  final Int32List _starts;

  /// Сколько слов в словаре.
  int get length => _starts.length;

  @override
  bool knows(String word) {
    final List<int> key = utf8.encode(word);
    int low = 0;
    int high = _starts.length - 1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      final int order = _compareAt(_starts[mid], key);
      if (order == 0) return true;
      if (order < 0) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return false;
  }

  /// Сравнивает слово словаря, начинающееся с [start], с [key] — по
  /// байтам: меньше нуля — слово словаря раньше.
  int _compareAt(int start, List<int> key) {
    int i = start;
    int k = 0;
    while (true) {
      final bool endWord = i >= _text.length || _text[i] == 0x0A;
      final bool endKey = k >= key.length;
      if (endWord || endKey) {
        if (endWord && endKey) return 0;
        return endWord ? -1 : 1;
      }
      final int diff = _text[i] - key[k];
      if (diff != 0) return diff;
      i++;
      k++;
    }
  }

  /// Начала строк файла.
  static Int32List _startsOf(Uint8List text) {
    int count = 0;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == 0x0A) count++;
    }
    if (text.isNotEmpty && text.last != 0x0A) count++;
    final Int32List starts = Int32List(count);
    int line = 0;
    int start = 0;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == 0x0A) {
        if (i > start) starts[line++] = start;
        start = i + 1;
      }
    }
    if (start < text.length) starts[line++] = start;
    return line == count ? starts : Int32List.sublistView(starts, 0, line);
  }
}

/// Загружает словарь из сборки.
Future<SortedLexicon> loadLexicon({AssetBundle? bundle}) async {
  final ByteData data = await (bundle ?? rootBundle).load(kLexiconAsset);
  return SortedLexicon.compressed(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// Авторство и лицензия данных словаря — в общий список лицензий
/// приложения (его показывает стандартная страница лицензий Flutter).
/// Условие CC BY-SA 4.0: автор, лицензия, ссылка, пометка «изменено».
void registerLexiconLicense() {
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(
        <String>['wordfreq (данные словаря)'],
        '''
Частотный словарь (assets/lexicon/words.txt.gz) — срез данных wordfreq 3.1.1:
Robyn Speer и др., https://github.com/rspeer/wordfreq.
Источники wordfreq: Google Books Ngrams, SUBTLEX, Википедия, OpenSubtitles и др.
Изменено: только формы из букв от трёх знаков, русский и английский одним списком.
Лицензия данных: Creative Commons Attribution-ShareAlike 4.0
https://creativecommons.org/licenses/by-sa/4.0/''',
      ),
    ),
  );
}
