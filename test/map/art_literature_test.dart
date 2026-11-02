/// Созвездия и порядок звёзд на настоящих книгах исследования СНО2026
/// (F-MAP-16, F-MAP-17).
///
/// Что проверяет. 18 книг тестовой литературы лежат в двух папках:
/// «Аневризма» (медицина) и «Число Е» (математика). Адаптивный резонанс
/// не знает папок — он видит только слова. Книги со словами должны
/// разложиться ровно по папкам при любом порядке поступления (на бумаге
/// шага 45 так и вышло: все 51 порядок).
///
/// Где книги. Литература — чужие книги, в публичный репозиторий она не
/// идёт: тест ищет её рядом с репозиторием, в папке проекта
/// `_данные/Книги в архиве для тестирования (2 версия)/`. Нет папки (CI)
/// — тест пропускается с причиной.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/exact_math.dart';
import 'package:memoria/domain/map/map_categories.dart';
import 'package:memoria/domain/map/map_order.dart';
import 'package:memoria/domain/map/map_vectors.dart';
import 'package:memoria/domain/map/text_trust.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/files/lexicon_asset.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';
import 'package:memoria/infrastructure/pdf/pdfrx_document.dart';
import 'package:pdfrx/pdfrx.dart' show pdfrxInitialize;

/// Созвездия по строкам книг: матрица Грама — как в расчёте карты.
List<int> _labels(
  List<SparseRow> rows, {
  List<int>? order,
  Map<int, int> pinned = const <int, int>{},
}) => artCategories(
  gramOf(rows),
  rows.length,
  order: order,
  pinned: pinned,
).labels;

/// Папка с литературой — рядом с репозиторием, в данных проекта.
const String _root = '../_данные/Книги в архиве для тестирования (2 версия)';

/// Папки литературы — они же правильный ответ.
const List<String> _folders = <String>['Аневризма - книги', 'Число Е - книги'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bool here = Directory(_root).existsSync();
  final Directory tmp = Directory(
    '${Directory.systemTemp.path}/memoria-art-literature',
  );
  final PdfrxDocumentOpener opener = PdfrxDocumentOpener(
    storage: const LocalBookStorage(),
    initialize: () => pdfrxInitialize(tmpPath: tmp.path),
  );

  /// Тексты всех страниц книги.
  Future<List<String>> pagesOf(File file) async {
    final ReaderDocument document = await opener.open(
      FilePathSource(file.absolute.path),
    );
    final List<String> pages = <String>[
      for (int page = 1; page <= document.pageCount; page++)
        await document.pageText(page),
    ];
    await document.close();
    return pages;
  }

  /// Мешок книги — как в приложении: название и текст всех страниц.
  Future<BookBag> bagOf(File file, String folder) async {
    final ReaderDocument document = await opener.open(
      FilePathSource(file.absolute.path),
    );
    final List<String> pages = <String>[];
    for (int page = 1; page <= document.pageCount; page++) {
      pages.add(await document.pageText(page));
    }
    await document.close();
    final String name = file.uri.pathSegments.last;
    return bagOfBook(
      BagRequest(
        key: '$folder/$name',
        group: folder,
        title: name.replaceAll('.pdf', ''),
        pages: pages,
      ),
    );
  }

  /// Мешки всех 18 книг, по возрастанию ключа; читаются один раз.
  List<BookBag>? cached;
  Future<List<BookBag>> literature() async {
    if (cached != null) return cached!;
    await tmp.create(recursive: true);
    final List<BookBag> bags = <BookBag>[];
    for (final String folder in _folders) {
      final List<File> files =
          Directory('$_root/$folder')
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.toLowerCase().endsWith('.pdf'))
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path));
      for (final File file in files) {
        bags.add(await bagOf(file, folder));
      }
    }
    bags.sort((BookBag a, BookBag b) => a.key.compareTo(b.key));
    return cached = bags;
  }

  test(
    'F-MAP-16: 18 книг литературы СНО2026 — созвездие не смешивает папки '
    'при любом порядке поступления',
    () async {
      final List<BookBag> bags = await literature();
      expect(bags, hasLength(18));
      final MapVocabulary vocabulary = vocabularyOf(bags);
      final List<SparseRow> rows = bm25Rows(bags, vocabulary);
      final int n = bags.length;

      // Порядки поступления: прямой, обратный и двадцать перемешанных.
      final List<List<int>> orders = <List<int>>[
        <int>[for (int i = 0; i < n; i++) i],
        <int>[for (int i = n - 1; i >= 0; i--) i],
      ];
      int state = 45;
      for (int k = 0; k < 20; k++) {
        final List<int> order = <int>[for (int i = 0; i < n; i++) i];
        for (int i = n - 1; i > 0; i--) {
          state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
          final int j = state % (i + 1);
          final int keep = order[i];
          order[i] = order[j];
          order[j] = keep;
        }
        orders.add(order);
      }

      // Сколько разных разметок дают порядки поступления — для разбора.
      final Map<String, int> seen = <String, int>{};
      final Map<String, List<int>> sample = <String, List<int>>{};
      for (final List<int> order in orders) {
        final List<int> labels = _labels(rows, order: order);
        final String text = labels.join(',');
        seen[text] = (seen[text] ?? 0) + 1;
        sample[text] = labels;
      }
      for (final MapEntry<String, int> entry in seen.entries) {
        final List<int> labels = sample[entry.key]!;
        stdout.writeln(
          'ЗАМЕР F-MAP-16 | разметка у ${entry.value} из ${orders.length} '
          'порядков | ${<String>[for (int i = 0; i < n; i++) '${labels[i]}:${bags[i].key.split('/').last}'].join(' | ')}',
        );
      }
      // Что правило гарантирует на любом порядке: ни одно созвездие не
      // смешивает папки, математика — одним созвездием, скан без слов —
      // без созвездия. Ровно по папкам выходит не всегда: в части порядков
      // три книги о хирургии («Хирургические тетради», «книга 7»,
      // scan_0412) встают своим созвездием внутри медицины. Эталон шага 45
      // (резонанс.py) на тех же строках даёт то же самое — это свойство
      // правила, а не переноса. Решение владельца — мелкие темы отдельно
      // (D-045).
      for (final List<int> order in orders) {
        final List<int> labels = _labels(rows, order: order);
        final Map<int, Set<String>> foldersOf = <int, Set<String>>{};
        final Map<String, Set<int>> ofFolder = <String, Set<int>>{};
        for (int i = 0; i < n; i++) {
          if (rows[i].length == 0) {
            expect(labels[i], kNoCategory, reason: bags[i].key);
            continue;
          }
          foldersOf.putIfAbsent(labels[i], () => <String>{}).add(bags[i].group);
          ofFolder.putIfAbsent(bags[i].group, () => <int>{}).add(labels[i]);
        }
        for (final Set<String> folders in foldersOf.values) {
          expect(folders, hasLength(1), reason: 'порядок $order');
        }
        expect(ofFolder[_folders[1]], hasLength(1), reason: 'порядок $order');
        expect(ofFolder[_folders[0]]!.length, lessThanOrEqualTo(2));
      }
    },
    skip: here
        ? false
        : 'нет литературы СНО2026 рядом с репозиторием (_данные) — '
              'тест идёт только на ПК владельца',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'F-MAP-17: порядок устойчив к выбросу 5 % слов',
    () async {
      final List<BookBag> bags = await literature();
      expect(bags, hasLength(18));
      final int n = bags.length;
      // Группа — папка: так считал расчёт шага 44 (ρ 0,99 и 0,97).
      final List<int> labels = <int>[
        for (final BookBag bag in bags) _folders.indexOf(bag.group),
      ];
      Float64List typicalOf(List<BookBag> set) {
        final List<SparseRow> rows = bm25Rows(set, vocabularyOf(set));
        return typicalities(gramOf(rows), n, labels);
      }

      final Float64List full = typicalOf(bags);
      // Пять выбросов: из каждой книги выпадает каждое двадцатое слово
      // (своё зерно на выброс), как при другой вёрстке или OCR.
      for (int seed = 1; seed <= 5; seed++) {
        final MapRandom random = MapRandom(seed);
        final List<BookBag> thinned = <BookBag>[
          for (final BookBag bag in bags) _thin(bag, random),
        ];
        final Float64List part = typicalOf(thinned);
        for (int g = 0; g < _folders.length; g++) {
          final List<int> members = <int>[
            for (int i = 0; i < n; i++)
              if (labels[i] == g) i,
          ];
          final double rho = _spearman(
            <double>[for (final int i in members) full[i]],
            <double>[for (final int i in members) part[i]],
          );
          stdout.writeln(
            'ЗАМЕР F-MAP-17 | выброс 5 % слов, зерно $seed | '
            '${_folders[g]} | ρ ${rho.toStringAsFixed(3)}',
          );
          expect(
            rho,
            greaterThanOrEqualTo(0.97),
            reason: '${_folders[g]}, $seed',
          );
        }
      }
    },
    skip: here
        ? false
        : 'нет литературы СНО2026 рядом с репозиторием (_данные) — '
              'тест идёт только на ПК владельца',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'ALG-MAP-19: литература СНО2026 — у книг с текстом доверие не ниже 0,8, '
    'книга без текста — «мало надёжного текста»',
    () async {
      await tmp.create(recursive: true);
      final SortedLexicon lexicon = SortedLexicon.compressed(
        File(kLexiconAsset).readAsBytesSync(),
      );
      final List<double> shares = <double>[];
      int books = 0;
      for (final String folder in _folders) {
        final List<File> files =
            Directory('$_root/$folder')
                .listSync()
                .whereType<File>()
                .where((File f) => f.path.toLowerCase().endsWith('.pdf'))
                .toList()
              ..sort((File a, File b) => a.path.compareTo(b.path));
        for (final File file in files) {
          books++;
          final List<String> pages = await pagesOf(file);
          final TextTrust trust = textTrustOf(pages, lexicon);
          for (final String page in pages) {
            final PageShare share = layerShare(page, lexicon);
            if (pageTrustOf(share) == PageTrust.yes) shares.add(share.share!);
          }
          final bool anyText = pages.any((String p) => p.trim().isNotEmpty);
          stdout.writeln(
            'ЗАМЕР ALG-MAP-19 | ${file.uri.pathSegments.last} | '
            'T ${trust.trust?.toStringAsFixed(3) ?? 'нет'}',
          );
          if (anyText) {
            expect(trust.unreliable, isFalse, reason: file.path);
          } else {
            expect(trust.noReliableText, isTrue, reason: file.path);
          }
        }
      }
      expect(books, 18);
      shares.sort();
      final double median = shares[shares.length ~/ 2];
      stdout.writeln(
        'ЗАМЕР ALG-MAP-19 | литература, страниц «да» ${shares.length} | '
        'медиана доли ${median.toStringAsFixed(3)}',
      );
      // Шаг 46: медиана чистых страниц — 0,86.
      expect(median, closeTo(kCleanTextShare, 0.05));
    },
    skip: here
        ? false
        : 'нет литературы СНО2026 рядом с репозиторием (_данные) — '
              'тест идёт только на ПК владельца',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Мешок книги, из которого выпало каждое двадцатое слово (5 %):
/// каждое употребление слова выпадает с вероятностью 1/20.
BookBag _thin(BookBag bag, MapRandom random) {
  final List<String> terms = <String>[];
  final List<int> counts = <int>[];
  int length = 0;
  for (int k = 0; k < bag.terms.length; k++) {
    int kept = 0;
    for (int c = 0; c < bag.counts[k]; c++) {
      if (random.below(20) != 0) kept++;
    }
    if (kept > 0) {
      terms.add(bag.terms[k]);
      counts.add(kept);
      length += kept;
    }
  }
  return BookBag(
    key: bag.key,
    group: bag.group,
    terms: terms,
    counts: counts,
    length: length,
  );
}

/// Ранговая корреляция Спирмена: 1 — порядок тот же, 0 — не связан.
/// Равные значения получают средний ранг.
double _spearman(List<double> a, List<double> b) {
  final List<double> ra = _ranks(a);
  final List<double> rb = _ranks(b);
  final int n = a.length;
  double ma = 0;
  double mb = 0;
  for (int i = 0; i < n; i++) {
    ma += ra[i] / n;
    mb += rb[i] / n;
  }
  double top = 0;
  double da = 0;
  double db = 0;
  for (int i = 0; i < n; i++) {
    top += (ra[i] - ma) * (rb[i] - mb);
    da += (ra[i] - ma) * (ra[i] - ma);
    db += (rb[i] - mb) * (rb[i] - mb);
  }
  return da == 0 || db == 0 ? 1 : top / math.sqrt(da * db);
}

/// Ранги чисел (от нуля), равным — средний.
List<double> _ranks(List<double> values) {
  final List<int> order = <int>[for (int i = 0; i < values.length; i++) i]
    ..sort((int x, int y) => values[x].compareTo(values[y]));
  final List<double> ranks = List<double>.filled(values.length, 0);
  int i = 0;
  while (i < order.length) {
    int j = i;
    while (j + 1 < order.length && values[order[j + 1]] == values[order[i]]) {
      j++;
    }
    for (int k = i; k <= j; k++) {
      ranks[order[k]] = (i + j) / 2;
    }
    i = j + 1;
  }
  return ranks;
}
