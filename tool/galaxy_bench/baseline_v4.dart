// Стенд «Галактики» (S61): базовая линия — нынешний расчёт карты v4 на наборе
// проверки, в строгом режиме (D-050).
//
// Что делает. Берёт тексты книг набора из кэша стенда (`extract_edges.py`) и
// прогоняет их через тот же код, что и приложение: доверие тексту
// (`textTrustOf`, F-MAP-18), мешок слов (`bagOfBook`, ALG-MAP-02) и карту
// (`buildBookMap`). Пишет `результат.csv` для `bench.py`: отпечаток книги,
// номер созвездия (−1 — вне созвездий) и имя созвездия.
//
// Строгий режим: у книги нет ни названия, ни автора, ни категории полки —
// в приложении название обычно берётся из имени файла, а это подсказка.
// Расчёт видит только текст страниц.
//
// Запуск (из папки MemoriaLLM):
//   dart run tool/galaxy_bench/baseline_v4.dart <набор.csv> <кэш> <края|полный> <результат.csv>
import 'dart:convert';
import 'dart:io';

import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/map_trusted.dart';
import 'package:memoria/domain/map/text_trust.dart';

/// Отпечатки книг набора — первый столбец после номера в `набор.csv`.
List<String> fingerprintsOf(String setPath) {
  final List<String> lines = File(setPath).readAsLinesSync();
  final List<String> header = lines.first.split(',');
  final int column = header.indexOf('fp');
  return <String>[
    for (final String line in lines.skip(1))
      if (line.trim().isNotEmpty) line.split(',')[column],
  ];
}

/// Тексты страниц книги из кэша: края — по номерам страниц, полный — подряд.
List<String> pagesOf(String cache, String mode, String fp) {
  final File file = File('$cache/$mode/$fp.json');
  final Map<String, dynamic> record =
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final Object? text = record['text'];
  if (text is List) {
    return text.cast<String>();
  }
  final Map<String, dynamic> byPage = text! as Map<String, dynamic>;
  final List<int> numbers = byPage.keys.map(int.parse).toList()..sort();
  return <String>[for (final int n in numbers) byPage['$n'] as String];
}

/// Доверие и страницы для мешка — как `MapBuilder._trustOf` и
/// `_trustedPages` в приложении, без паспорта файла (пустые страницы
/// считаются страницами с текстом — для базовой линии этого хватает).
(BookTrust, List<String>) judge(List<String> pages, Lexicon lexicon) {
  if (!hasLexiconScript(pages)) {
    return (const BookTrust.asIs(), pages);
  }
  final TextTrust trust = textTrustOf(pages, lexicon);
  if (trust.noReliableText) {
    return (const BookTrust.littleText(), const <String>[]);
  }
  return (
    BookTrust.of(trust.trust!),
    <String>[for (final int i in trust.usedPages) pages[i]],
  );
}

/// Значение для CSV: в кавычки, если внутри запятая или кавычка.
String cell(String value) => value.contains(RegExp('[",\n]'))
    ? '"${value.replaceAll('"', '""')}"'
    : value;

void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln('нужно: <набор.csv> <кэш> <края|полный> <результат.csv>');
    exit(2);
  }
  final String setPath = args[0], cache = args[1], mode = args[2];
  final Lexicon lexicon = SetLexicon(
    utf8
        .decode(
          gzip.decode(File('assets/lexicon/words.txt.gz').readAsBytesSync()),
        )
        .split('\n')
        .where((String w) => w.isNotEmpty),
  );
  final Stopwatch clock = Stopwatch()..start();
  final List<BookBag> bags = <BookBag>[];
  for (final String fp in fingerprintsOf(setPath)) {
    final (BookTrust trust, List<String> used) = judge(
      pagesOf(cache, mode, fp),
      lexicon,
    );
    // Строгий режим: ни названия, ни автора, ни категории полки.
    final BookBag bag = bagOfBook(
      BagRequest(key: fp, group: '', title: '', pages: used),
    );
    bags.add(bag.withTrust(trust));
  }
  final BookMap map = buildBookMap(bags)!;
  final StringBuffer out = StringBuffer('fp,группа,имя\n');
  for (final MapPoint p in map.points) {
    out.writeln('${p.key},${p.constellation},${cell(p.name)}');
  }
  File(args[3]).writeAsStringSync(out.toString());
  stdout.writeln(
    'книг ${map.points.length}, созвездий ${map.groups}, '
    'слов ${map.words}, ${clock.elapsedMilliseconds} мс',
  );
}
