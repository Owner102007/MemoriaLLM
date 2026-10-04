import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/library/book_importer.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/scan_mark.dart';
import 'package:memoria/domain/theme/app_palette.dart';
import 'package:memoria/domain/theme/contrast.dart';

import '../data/test_data.dart';

/// F-DEV-13: честная пометка скана без текста — слова и цвета.
void main() {
  Book book(String id, {required bool? text, String title = 'Книга'}) {
    final Book base = testBook(id: id, title: title, hash: 'hash-$id');
    // `copyWith` пустой признак не ставит: «не знаю» — это книга как есть.
    return text == null ? base : base.copyWith(hasTextLayer: text);
  }

  group('F-DEV-13: кого помечать', () {
    test('F-DEV-13: метку получает только твёрдое «текста нет»', () {
      expect(isMarkedScan(false), isTrue);
      expect(isMarkedScan(true), isFalse);
      // «Не знаю»: книгу, которую не удалось прочесть, сканом не называют.
      expect(isMarkedScan(null), isFalse);
    });
  });

  group('F-DEV-13: метка читается на любой теме', () {
    for (final AppPalette palette in appPalettes.values) {
      test('F-DEV-13: ${palette.title} — не ниже 4,5:1', () {
        final ({int background, int text}) colors = scanMarkColors(palette);
        final double ratio = contrastRatio(colors.text, colors.background);
        expect(
          ratio,
          greaterThanOrEqualTo(wcagAaNormalText),
          reason: 'метка «$kScanMark» даёт ${ratio.toStringAsFixed(2)}:1',
        );
        // Подложка своя и непрозрачная: под меткой — обложка, а она
        // бывает любой.
        expect(colors.background >> 24, 0xFF);
      });
    }
  });

  group('F-DEV-13: что сказано при добавлении', () {
    test('F-DEV-13: один скан назван по имени, и сказано, что не работает', () {
      final String text = describeImportReport(
        ImportReport(
          added: <Book>[book('a', text: false, title: 'Атлас')],
          failed: const <ImportFailure>[],
        ),
      );

      expect(text, contains('«Атлас»'));
      expect(text, contains('скан'));
      expect(text, contains('текст не распознан'));
      expect(text, contains('выделение, поиск и функции'));
      expect(text, contains('не работают'));
    });

    test('F-DEV-13: книга с текстом добавляется без оговорок', () {
      final String text = describeImportReport(
        ImportReport(
          added: <Book>[book('a', text: true)],
          failed: const <ImportFailure>[],
        ),
      );

      expect(text, 'Книга добавлена');
    });

    test('F-DEV-13: книга, о которой не знаем, сканом не названа', () {
      final ImportReport report = ImportReport(
        added: <Book>[book('a', text: null)],
        failed: const <ImportFailure>[],
      );

      expect(report.scans, isEmpty);
      expect(describeImportReport(report), 'Книга добавлена');
    });

    test('F-DEV-13: в пачке сканы сосчитаны одной строкой', () {
      final ImportReport report = ImportReport(
        added: <Book>[
          book('a', text: true),
          book('b', text: false),
          book('c', text: false),
          book('d', text: null),
        ],
        failed: const <ImportFailure>[],
      );
      final String text = describeImportReport(report);

      expect(report.scans.length, 2);
      expect(text, startsWith('Добавлено книг: 4'));
      expect(text, contains('Сканов без текста: 2'));
      expect(text, contains('выделение, поиск и функции'));
    });

    test('F-DEV-13: пачка без сканов — прежние слова', () {
      final String text = describeImportReport(
        ImportReport(
          added: <Book>[book('a', text: true), book('b', text: true)],
          failed: const <ImportFailure>[],
        ),
      );

      expect(text, 'Добавлено книг: 2');
    });

    test('F-DEV-13: не открывшиеся и сканы названы вместе', () {
      final String text = describeImportReport(
        ImportReport(
          added: <Book>[book('a', text: false)],
          failed: const <ImportFailure>[
            ImportFailure(name: 'битая.pdf', reason: 'файл повреждён'),
          ],
        ),
      );

      expect(text, contains('Добавлено 1 из 2'));
      expect(text, contains('не открылось: 1'));
      expect(text, contains('Сканов без текста: 1'));
    });

    test('F-DEV-13: ничего не добавилось — сказано прямо', () {
      final String text = describeImportReport(
        const ImportReport(
          added: <Book>[],
          failed: <ImportFailure>[
            ImportFailure(name: 'битая.pdf', reason: 'файл повреждён'),
          ],
        ),
      );

      expect(text, 'Не удалось добавить ни одной книги из 1');
    });
  });
}
