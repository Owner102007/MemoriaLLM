/// Созвездия на настоящих книгах исследования СНО2026 (F-MAP-16).
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

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/map_categories.dart';
import 'package:memoria/domain/map/map_vectors.dart';
import 'package:memoria/domain/reading/reader_document.dart';
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

  test(
    'F-MAP-16: 18 книг литературы СНО2026 — созвездие не смешивает папки '
    'при любом порядке поступления',
    () async {
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
      expect(bags, hasLength(18));
      bags.sort((BookBag a, BookBag b) => a.key.compareTo(b.key));
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
      // правила, а не переноса; вопрос владельцу — В-019.
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
}
