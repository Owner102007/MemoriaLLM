import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/application/reading/page_frames.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';
import 'package:memoria/domain/reading/text_search.dart';
import 'package:memoria/infrastructure/pdf/pdfrx_document.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDocument, pdfrxInitialize;

/// Прогон корпуса проблемных PDF через настоящий PDFium.
///
/// Это единственный тест проекта, которому нужен движок: остальные
/// работают с подставным документом. Смысл прогона — не проверить PDFium
/// (чужой код не тестируем), а закрепить, **как приложение ведёт себя**
/// на файлах, которые в жизни встречаются постоянно и ломают читалки:
/// сканы без текста, шрифты без встроенной программы, битые указатели,
/// шифрование, тысяча с лишним страниц.
///
/// Состав корпуса и ожидания по каждому файлу описаны в
/// `test/fixtures/README.md`. Файлы собирает `tool/make_fixtures.py`.
///
/// Библиотека PDFium берётся из переменной окружения `PDFIUM_PATH`
/// (её выставляет CI), иначе — из нативного ассета pdfrx.

const String _fixtures = 'test/fixtures';

String _file(String name) => '$_fixtures/$name';

/// Файлы, которые обязаны открываться.
const Map<String, int> _readable = <String, int>{
  'basic_text.pdf': 8,
  'outline_nested.pdf': 12,
  'two_columns.pdf': 4,
  'scan_no_text.pdf': 2,
  'cjk.pdf': 1,
  'rtl.pdf': 1,
  'rotated_pages.pdf': 4,
  'mixed_page_sizes.pdf': 4,
  'broken_xref.pdf': 3,
  'huge_1200_pages.pdf': 1200,
};

/// Файлы, которые открыться не могут, и то, чем это должно кончиться.
const Map<String, DocumentProblem> _unreadable = <String, DocumentProblem>{
  'empty_file.pdf': DocumentProblem.empty,
  'not_a_pdf.pdf': DocumentProblem.damaged,
  'truncated.pdf': DocumentProblem.damaged,
  'encrypted.pdf': DocumentProblem.passwordRequired,
};

/// Сколько пикселей темнее порога — так видно, что страница действительно
/// нарисована, а не осталась белым листом.
int _darkPixels(PageRaster raster) {
  int count = 0;
  for (int i = 0; i + 3 < raster.pixels.length; i += 4) {
    if (raster.pixels[i] < 200 &&
        raster.pixels[i + 1] < 200 &&
        raster.pixels[i + 2] < 200) {
      count++;
    }
  }
  return count;
}

void main() {
  final Directory tmp = Directory(
    '${Directory.systemTemp.path}/memoria-pdfrx-tests',
  );
  final PdfrxDocumentOpener opener = PdfrxDocumentOpener(
    initialize: () => pdfrxInitialize(tmpPath: tmp.path),
  );

  Future<ReaderDocument> open(String name, {String? password}) async {
    final ReaderDocument document = await opener.open(
      _file(name),
      password: password,
    );
    addTearDown(document.close);
    return document;
  }

  test('корпус на месте', () {
    final List<String> all = <String>[..._readable.keys, ..._unreadable.keys];
    for (final String name in all) {
      expect(
        File(_file(name)).existsSync(),
        isTrue,
        reason: 'нет файла $name — пересоберите корпус tool/make_fixtures.py',
      );
    }
  });

  group('открыть → извлечь текст → отрендерить страницу', () {
    _readable.forEach((String name, int pages) {
      test(name, () async {
        final ReaderDocument document = await open(name);

        expect(document.pageCount, pages, reason: 'число страниц');
        expect(document.sourceName, _file(name));

        // Текст читается без исключения: у книги он есть, у скана пуст.
        await document.pageText(1);

        // Геометрия осмысленная.
        final PageGeometry geometry = document.geometry(1);
        expect(geometry.width, greaterThan(0));
        expect(geometry.height, greaterThan(0));

        // Страница рисуется, и растр сходится с заявленным размером.
        const int width = 200;
        final int height = (width * geometry.height / geometry.width).round();
        final PageRaster? raster = await document.renderPage(
          1,
          width: width,
          height: height,
        );
        expect(raster, isNotNull, reason: 'страница не отрисовалась');
        expect(raster!.isConsistent, isTrue, reason: 'растр не сходится');

        // Оглавление читается всегда, пусть даже пустое.
        expect(await document.outline(), isA<List<OutlineEntry>>());
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  });

  group('битые и защищённые файлы', () {
    _unreadable.forEach((String name, DocumentProblem problem) {
      test('$name: понятная ошибка вместо падения', () async {
        await expectLater(
          opener.open(_file(name)),
          throwsA(
            isA<DocumentOpenException>().having(
              (DocumentOpenException e) => e.problem,
              'причина',
              problem,
            ),
          ),
        );
      });
    });

    test('файла нет — так и сказано', () async {
      await expectLater(
        opener.open(_file('нет-такого-файла.pdf')),
        throwsA(
          isA<DocumentOpenException>().having(
            (DocumentOpenException e) => e.problem,
            'причина',
            DocumentProblem.missing,
          ),
        ),
      );
    });
  });

  group('текстовый слой', () {
    test(
      'обычная книга: текст на месте и разный на разных страницах',
      () async {
        final ReaderDocument document = await open('basic_text.pdf');
        expect(await hasTextLayer(document), isTrue);
        expect(await document.pageText(1), contains('Memoria page 1'));
        expect(await document.pageText(8), contains('Memoria page 8'));
        expect(
          await document.pageText(1),
          contains('The quick brown fox jumps over the lazy dog.'),
        );
      },
    );

    test('скан: текстового слоя нет — предупреждаем при импорте', () async {
      final ReaderDocument document = await open('scan_no_text.pdf');
      expect((await document.pageText(1)).trim(), isEmpty);
      expect(await hasTextLayer(document), isFalse);
    });

    test(
      'CJK: текст извлекается по ToUnicode без встроенного шрифта',
      () async {
        final ReaderDocument document = await open('cjk.pdf');
        final String text = await document.pageText(1);
        expect(text, contains('日本語'));
        expect(text, contains('中文'));
        expect(text, contains('한국어'));
      },
    );

    test('RTL: арабица и иврит доезжают до приложения', () async {
      final ReaderDocument document = await open('rtl.pdf');
      final String text = await document.pageText(1);
      // Порядок символов при извлечении RTL-текста не логический —
      // это свойство PDF, а не ошибка. Приложению важно, что символы
      // вообще пришли и не превратились в мусор.
      expect(text.contains('ا'), isTrue, reason: 'арабский алиф');
      expect(text.contains('ב'), isTrue, reason: 'ивритский бет');
    });

    test('двухколоночная статья отдаёт текст обеих колонок', () async {
      final ReaderDocument document = await open('two_columns.pdf');
      final String text = await document.pageText(1);
      expect(text, contains('Left column line 0 of page 1'));
      expect(text, contains('Right column line 0 of page 1'));
    });
  });

  group('оглавление', () {
    test('плоское оглавление из трёх пунктов', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final List<OutlineEntry> outline = await document.outline();
      expect(outline.length, 3);
      expect(outline.first.title, 'Chapter One');
      expect(outline.first.pageNumber, 1);
      expect(outline.last.pageNumber, 7);
      expect(outline.every((OutlineEntry e) => e.children.isEmpty), isTrue);
    });

    test('вложенное оглавление разбирается целиком', () async {
      final ReaderDocument document = await open('outline_nested.pdf');
      final List<OutlineEntry> outline = await document.outline();
      expect(outline.length, 2);
      expect(outline.first.title, 'Part I');
      expect(outline.first.children.length, 2);
      expect(outline.first.children.first.title, 'Chapter 1');
      expect(outline.first.children.first.children.length, 2);
      expect(outline.first.children.first.children.first.pageNumber, 3);
    });

    test(
      'у книги без оглавления оглавление пустое, а не отсутствует',
      () async {
        final ReaderDocument document = await open('two_columns.pdf');
        expect(await document.outline(), isEmpty);
      },
    );
  });

  group('геометрия страниц', () {
    test('повороты приходят уже применёнными к размерам', () async {
      final ReaderDocument document = await open('rotated_pages.pdf');
      expect(document.geometry(1).isLandscape, isFalse);
      expect(document.geometry(2).isLandscape, isTrue);
      expect(document.geometry(3).isLandscape, isFalse);
      expect(document.geometry(4).isLandscape, isTrue);
      expect(document.geometry(2).quarterTurns, 1);
      expect(document.geometry(4).quarterTurns, 3);
    });

    test('в одной книге страницы бывают разного размера', () async {
      final ReaderDocument document = await open('mixed_page_sizes.pdf');
      final Set<PageGeometry> sizes = <PageGeometry>{
        for (int page = 1; page <= document.pageCount; page++)
          document.geometry(page),
      };
      expect(sizes.length, 4, reason: 'все четыре страницы разные');
      expect(document.geometry(4).width, closeTo(200, 0.5));
    });
  });

  group('рендер', () {
    test('текстовая страница рисуется, а не остаётся белым листом', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final PageRaster raster = (await document.renderPage(
        1,
        width: 300,
        height: 424,
      ))!;
      expect(_darkPixels(raster), greaterThan(100));
    });

    test('скан рисуется картинкой', () async {
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageRaster raster = (await document.renderPage(
        1,
        width: 300,
        height: 424,
      ))!;
      expect(_darkPixels(raster), greaterThan(100));
    });

    test('бессмысленный размер растра — null, а не падение', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      expect(await document.renderPage(1, width: 0, height: 100), isNull);
    });
  });

  group('битый xref', () {
    test('PDFium пересобирает таблицу, и книга открывается', () async {
      // Самый частый вид «повреждённого» PDF в жизни. Испорченный
      // указатель не должен стоить читателю книги.
      final ReaderDocument document = await open('broken_xref.pdf');
      expect(document.pageCount, 3);
      expect(await document.pageText(1), contains('Recovered page 1'));
    });
  });

  group('шифрование', () {
    test('без пароля — просьба ввести пароль', () async {
      await expectLater(
        opener.open(_file('encrypted.pdf')),
        throwsA(
          isA<DocumentOpenException>().having(
            (DocumentOpenException e) => e.problem,
            'причина',
            DocumentProblem.passwordRequired,
          ),
        ),
      );
    });

    test('неверный пароль отличается от отсутствующего', () async {
      await expectLater(
        opener.open(_file('encrypted.pdf'), password: 'не тот'),
        throwsA(
          isA<DocumentOpenException>().having(
            (DocumentOpenException e) => e.problem,
            'причина',
            DocumentProblem.wrongPassword,
          ),
        ),
      );
    });

    test('верный пароль открывает книгу', () async {
      final ReaderDocument document = await open(
        'encrypted.pdf',
        password: 'memoria',
      );
      expect(document.pageCount, 3);
      expect(await document.pageText(1), contains('Secret page 1'));
    });
  });

  group('очень большая книга', () {
    test(
      '1200 страниц: открывается, последняя доступна',
      () async {
        final Stopwatch watch = Stopwatch()..start();
        final ReaderDocument document = await open('huge_1200_pages.pdf');
        watch.stop();

        expect(document.pageCount, 1200);
        expect(await document.pageText(1200), contains('Long book page'));
        expect(document.geometry(1200).width, greaterThan(0));
        // Не измерение производительности, а страховка от квадратичных
        // алгоритмов: то, что незаметно на десяти страницах, вешает
        // приложение на тысяче.
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 60)),
          reason: 'открытие тысячестраничной книги подозрительно долгое',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test('страница за краем книги — RangeError, а не тихий мусор', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      expect(() => document.geometry(9), throwsRangeError);
      expect(() => document.geometry(0), throwsRangeError);
    });
  });

  group('поиск по настоящему PDF', () {
    test('находит слово и указывает верную страницу', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final DocumentSearch search = DocumentSearch(document: document);
      addTearDown(search.dispose);

      await search.start('unique-token-5');
      expect(search.hits.length, 1);
      expect(search.hits.single.pageNumber, 5);
    });

    test('фраза находится через перенос строки в файле', () async {
      // В содержимом страницы эти слова разделены переносом; без
      // нормализации текста запрос не нашёлся бы вовсе.
      final ReaderDocument document = await open('basic_text.pdf');
      final String text = await document.pageText(1);
      expect(text.contains('\n'), isTrue, reason: 'перенос в исходном тексте');

      final List<SearchHit> hits = findInPageText(
        pageNumber: 1,
        pageText: text,
        query: 'lazy dog. Marker1',
      );
      expect(hits.length, 1);
      expect(
        text.substring(hits.single.sourceStart, hits.single.sourceEnd),
        contains('Marker1'),
      );
    });

    test('в скане искать нечего, и поиск это переживает', () async {
      final ReaderDocument document = await open('scan_no_text.pdf');
      final DocumentSearch search = DocumentSearch(document: document);
      addTearDown(search.dispose);

      await search.start('что угодно');
      expect(search.isEmptyResult, isTrue);
      expect(search.scannedPages, 2);
    });
  });

  group('читательская рамка на корпусе', () {
    _readable.forEach((String name, int pages) {
      test(
        '$name: рамка не пустая и не вывернутая',
        () async {
          final ReaderDocument document = await open(name);
          final PageFrameSource frames = PageFrameSource(document: document);
          // Шести страниц довольно: дальше повторяется та же вёрстка,
          // а тысяча страниц превратила бы прогон в получасовой.
          final int limit = math.min(document.pageCount, 6);

          for (int page = 1; page <= limit; page++) {
            final PageFrame frame = await frames.frameFor(page);
            final String where = '$name, страница $page';

            expect(frame.content.isValid, isTrue, reason: 'рамка: $where');
            expect(frame.content.width, greaterThan(0.05), reason: where);
            expect(frame.content.height, greaterThan(0.05), reason: where);
            expect(frame.columns, isNotEmpty, reason: 'колонки: $where');

            // Ни один режим не должен давать пустой или вывернутый фрагмент:
            // это чёрный экран вместо книги.
            for (final PageDisplayMode mode in PageDisplayMode.values) {
              final List<CropBox> parts = fragmentsFor(
                content: frame.content,
                mode: mode,
                columns: frame.columns,
              );
              expect(parts, isNotEmpty, reason: '$mode: $where');
              expect(
                parts.length,
                fragmentCountFor(mode: mode, columnCount: frame.columns.length),
                reason: '$mode: $where',
              );
              for (final CropBox part in parts) {
                expect(part.isValid, isTrue, reason: '$mode: $where');
                expect(
                  part.left,
                  greaterThanOrEqualTo(frame.content.left - 1e-9),
                );
                expect(
                  part.right,
                  lessThanOrEqualTo(frame.content.right + 1e-9),
                );
              }
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    test(
      'движок отдаёт тот же документ, что читает текст',
      () async {
        // Рисовать страницу должен тот же открытый файл: второе открытие
        // стоит вдвое больше памяти, а на большой книге отдаёт страницы
        // не сразу — и вместо содержимого читатель видит пустой экран.
        final ReaderDocument document = await open('huge_1200_pages.pdf');
        final Object? engine = document.engineDocument;
        expect(engine, isNotNull);
        expect(engine, isA<PdfDocument>());
        expect(
          (engine! as PdfDocument).pages.length,
          document.pageCount,
          reason: 'страницы должны быть на месте все сразу',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('обычная книга: поля обрезаются по тексту', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final PageFrame frame = await frames.frameFor(1);

      expect(frame.fromText, isTrue, reason: 'текстовый слой есть');
      expect(frame.content.width, lessThan(0.8), reason: 'поля срезаны');
      expect(frame.hasColumns, isFalse);
    });

    test('ни один символ не остаётся за рамкой', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final List<TextBox> boxes = await document.pageTextBoxes(1);
      expect(boxes, isNotEmpty);

      final PageFrameSource frames = PageFrameSource(document: document);
      final CropBox content = (await frames.frameFor(1)).content;
      for (final TextBox box in boxes) {
        expect(box.left, greaterThanOrEqualTo(content.left));
        expect(box.right, lessThanOrEqualTo(content.right));
        expect(box.top, greaterThanOrEqualTo(content.top));
        expect(box.bottom, lessThanOrEqualTo(content.bottom));
      }
    });

    test('двухколоночная статья делится по колонкам', () async {
      final ReaderDocument document = await open('two_columns.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final PageFrame frame = await frames.frameFor(1);

      expect(frame.hasColumns, isTrue, reason: 'колонки не найдены');
      expect(frame.columns.length, 2);
      expect(
        frame.columns.last.left - frame.columns.first.right,
        greaterThan(0.05),
        reason: 'между колонками обязан быть просвет',
      );

      final List<CropBox> halves = fragmentsFor(
        content: frame.content,
        mode: PageDisplayMode.half,
        columns: frame.columns,
      );
      // Половина двухколоночной страницы — колонка, а не верх страницы.
      expect(halves.first.height, closeTo(frame.content.height, 1e-9));
      expect(halves.first.width, lessThan(frame.content.width * 0.6));
    });

    test('скан без текста разбирается по пикселям', () async {
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final PageFrame frame = await frames.frameFor(1);

      expect(frame.fromText, isFalse);
      expect(frame.content.isValid, isTrue);
      expect(frame.content.width, lessThan(0.95), reason: 'поля скана срезаны');
    });

    test('у скана просветы между строками тоже находятся', () async {
      // Текстового слоя нет, а строки есть — просто нарисованные. Без
      // просветов половина скана резалась по геометрической середине и
      // рассекала строку: читать её было нельзя ни на одном экране.
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final PageFrame frame = await frames.frameFor(1);

      expect(frame.breaks, isNotEmpty, reason: 'строки скана не разделены');
      for (final double gap in frame.breaks) {
        expect(gap, greaterThan(0));
        expect(gap, lessThan(1));
      }

      final List<CropBox> halves = fragmentsFor(
        content: frame.content,
        mode: PageDisplayMode.half,
        columns: frame.columns,
        breaks: frame.breaks,
      );
      expect(
        halves.first.bottom,
        closeTo(halves.last.top, 1e-9),
        reason: 'просвет нашёлся — повторять строку не надо',
      );
    });

    test('прямоугольники символов приходят в долях страницы', () async {
      final ReaderDocument document = await open('basic_text.pdf');
      final List<TextBox> boxes = await document.pageTextBoxes(1);
      for (final TextBox box in boxes) {
        expect(box.isValid, isTrue, reason: '$box');
      }
      // Пробелы отброшены: иначе концевые пробелы строк растянули бы
      // рамку до самого края поля.
      final String text = await document.pageText(1);
      expect(boxes.length, lessThan(text.length));
    });

    test('повёрнутые страницы: рамка в координатах читателя', () async {
      final ReaderDocument document = await open('rotated_pages.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      for (int page = 1; page <= document.pageCount; page++) {
        final PageFrame frame = await frames.frameFor(page);
        expect(frame.content.isValid, isTrue, reason: 'страница $page');
      }

      final List<TextBox> boxes = await document.pageTextBoxes(2);
      final PageGeometry geometry = document.geometry(2);
      expect(geometry.isLandscape, isTrue);
      if (boxes.isNotEmpty) {
        // Доли считаются от повёрнутой страницы: иначе на альбомной
        // странице рамка вылезла бы за её край.
        for (final TextBox box in boxes) {
          expect(box.right, lessThanOrEqualTo(1));
          expect(box.bottom, lessThanOrEqualTo(1));
        }
      }
    });
  });
}
