import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/reading/document_search.dart';
import 'package:memoria/application/reading/page_frames.dart';
import 'package:memoria/application/reading/reader_controller.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/cover.dart';
import 'package:memoria/domain/reading/book_frame.dart';
import 'package:memoria/domain/reading/crop.dart';
import 'package:memoria/domain/reading/fragments.dart';
import 'package:memoria/domain/reading/page_turning.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/reading.dart';
import 'package:memoria/domain/reading/text_geometry.dart';
import 'package:memoria/domain/reading/text_search.dart';
import 'package:memoria/infrastructure/files/local_book_storage.dart';
import 'package:memoria/infrastructure/images/png.dart';
import 'package:memoria/infrastructure/pdf/pdfrx_document.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDocument, PdfPage, pdfrxInitialize;

import 'support/descriptors.dart';
import 'support/fake_reading.dart';

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

BookSource _source(String name) => FilePathSource(_file(name));

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
  'book_120_pages.pdf': 120,
};

/// Опорная область показа для проверки деления страницы.
class _RefArea {
  const _RefArea(this.label, this.area, {required this.canTurn});

  final String label;
  final DisplayArea area;

  /// Можно ли попросить систему повернуть экран. На ПК — нельзя.
  final bool canTurn;
}

/// Области показа, на которых проверяется выбор деления.
///
/// Телефон в обоих положениях (переставит их сам выбор раскладки) и окно
/// ПК в трёх пропорциях, включая узкое высокое и широкое низкое: на ПК
/// ориентации нет вовсе, повернуть окно нельзя, и деление обязано
/// считаться по фактической форме области.
const List<_RefArea> _refAreas = <_RefArea>[
  _RefArea(
    'телефон 1080×2400',
    DisplayArea(width: 1080, height: 2400),
    canTurn: true,
  ),
  _RefArea(
    'окно 1600×900',
    DisplayArea(width: 1600, height: 900),
    canTurn: false,
  ),
  _RefArea(
    'окно 900×1600',
    DisplayArea(width: 900, height: 1600),
    canTurn: false,
  ),
  _RefArea(
    'окно 3840×1080',
    DisplayArea(width: 3840, height: 1080),
    canTurn: false,
  ),
];

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
  // Обложки проверяются чужим декодером картинок, а он живёт в движке:
  // без поднятого окружения `instantiateImageCodec` не с чем работать.
  TestWidgetsFlutterBinding.ensureInitialized();

  final Directory tmp = Directory(
    '${Directory.systemTemp.path}/memoria-pdfrx-tests',
  );
  final PdfrxDocumentOpener opener = PdfrxDocumentOpener(
    storage: const LocalBookStorage(),
    initialize: () => pdfrxInitialize(tmpPath: tmp.path),
  );

  Future<ReaderDocument> open(String name, {String? password}) async {
    final ReaderDocument document = await opener.open(
      _source(name),
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
        expect(document.sourceName, _source(name).encode());

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
          opener.open(_source(name)),
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
        opener.open(_source('нет-такого-файла.pdf')),
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
      // F-READ-02: при открытии измерена одна первая страница; геометрия
      // остальных настоящая только после измерения.
      await document.measure(<int>[1, 2, 3, 4]);
      expect(document.geometry(1).isLandscape, isFalse);
      expect(document.geometry(2).isLandscape, isTrue);
      expect(document.geometry(3).isLandscape, isFalse);
      expect(document.geometry(4).isLandscape, isTrue);
      expect(document.geometry(2).quarterTurns, 1);
      expect(document.geometry(4).quarterTurns, 3);
    });

    test('в одной книге страницы бывают разного размера', () async {
      final ReaderDocument document = await open('mixed_page_sizes.pdf');
      await document.measure(<int>[1, 2, 3, 4]);
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
        opener.open(_source('encrypted.pdf')),
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
        opener.open(_source('encrypted.pdf'), password: 'не тот'),
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
    test('1200 страниц: открывается, последняя доступна', () async {
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
    }, timeout: const Timeout(Duration(minutes: 5)));

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
      test('$name: рамка не пустая и не вывернутая', () async {
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
            );
            expect(parts, isNotEmpty, reason: '$mode: $where');
            expect(
              parts.length,
              fragmentCountFor(mode: mode),
              reason: '$mode: $where',
            );
            for (final CropBox part in parts) {
              expect(part.isValid, isTrue, reason: '$mode: $where');
              expect(
                part.left,
                greaterThanOrEqualTo(frame.content.left - 1e-9),
              );
              expect(part.right, lessThanOrEqualTo(frame.content.right + 1e-9));
            }
          }
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    _readable.forEach((String name, int pages) {
      test('$name: включённое деление не делает текст мельче', () async {
        // Тот самый тест, которого не хватало. Прежняя проверка «ради чего
        // всё затевалось» брала придуманную одноколоночную страницу и
        // делила её полосами — двухколоночного случая в ней не было, и
        // ошибку она не видела. Проверка миссии, поставленная на удобном
        // примере, проверяет пример.
        //
        // Масштаб здесь считается заново, из прямоугольника фрагмента и
        // той области показа, которую попросит приложение, — а не берётся
        // из самой раскладки. Иначе тест сверял бы функцию с собой.
        final ReaderDocument document = await open(name);
        final PageFrameSource frames = PageFrameSource(document: document);
        final int limit = math.min(document.pageCount, 6);

        double worstScale(
          List<CropBox> parts,
          PageGeometry page,
          DisplayArea a,
        ) {
          double worst = double.infinity;
          for (final CropBox part in parts) {
            final double scale = fragmentScale(
              fragmentWidth: page.width * part.width,
              fragmentHeight: page.height * part.height,
              screenWidth: a.width,
              screenHeight: a.height,
            );
            worst = scale < worst ? scale : worst;
          }
          return worst;
        }

        for (int page = 1; page <= limit; page++) {
          final PageFrame frame = await frames.frameFor(page);
          final PageGeometry geometry = document.geometry(page);

          for (final _RefArea it in _refAreas) {
            final String label = it.label;
            final FragmentLayout whole = chooseFragmentLayout(
              mode: PageDisplayMode.full,
              content: frame.content,
              sheetWidth: geometry.width,
              sheetHeight: geometry.height,
              area: it.area,
              breaks: frame.breaks,
              canTurn: it.canTurn,
            );
            final double wholeScale = worstScale(
              <CropBox>[frame.content],
              geometry,
              whole.area,
            );

            for (final PageDisplayMode mode in <PageDisplayMode>[
              PageDisplayMode.half,
              PageDisplayMode.third,
            ]) {
              final String where = '$name, страница $page, $mode, $label';
              final FragmentLayout layout = chooseFragmentLayout(
                mode: mode,
                content: frame.content,
                sheetWidth: geometry.width,
                sheetHeight: geometry.height,
                area: it.area,
                breaks: frame.breaks,
                canTurn: it.canTurn,
              );
              final List<CropBox> parts = fragmentsFor(
                content: frame.content,
                mode: mode,
                breaks: frame.breaks,
              );

              final double scale = worstScale(parts, geometry, layout.area);
              expect(scale, greaterThan(0), reason: 'пустой фрагмент: $where');

              if (layout.isWorthwhile) {
                // Главное обещание режима: текст стал крупнее. Не «не
                // хуже», а именно крупнее — иначе поворот экрана и
                // разрезанная страница не окупаются ничем.
                expect(
                  scale,
                  greaterThanOrEqualTo(wholeScale * kMinFragmentGain - 1e-6),
                  reason: 'режим включился и уменьшил текст: $where',
                );
              }

              // Положение экрана выбрано счётом, а не по названию режима.
              final double turned = worstScale(
                parts,
                geometry,
                layout.area.turned,
              );
              if (it.canTurn) {
                expect(
                  scale,
                  greaterThanOrEqualTo(turned - 1e-6),
                  reason: 'нашлось положение экрана лучше: $where',
                );
              }
            }
          }
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    test('движок отдаёт тот же документ, что читает текст', () async {
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
    }, timeout: const Timeout(Duration(minutes: 3)));

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

    test('колонки находятся, но страницу не делят', () async {
      // Колонки остаются фактом о странице — они понадобятся S6, чтобы
      // вынуть абзац вокруг выделения в правильном порядке. Но деление
      // от них не зависит: полосы идут поперёк в любой книге (решение
      // владельца, 23.08.2026).
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
        breaks: frame.breaks,
      );
      expect(halves.length, 2);
      // Половина — верх страницы во всю её ширину, а не колонка.
      expect(halves.first.width, closeTo(frame.content.width, 1e-9));
      expect(halves.first.height, lessThan(frame.content.height * 0.6));
    });

    test('в любой книге дроби делят одинаково и увеличивают текст', () async {
      // Прежде на двухколоночной книге половина отдавала колонку, и
      // читатель получал совсем не то, что нарисовано на кнопке.
      for (final String name in <String>['two_columns.pdf', 'basic_text.pdf']) {
        final ReaderDocument document = await open(name);
        final PageFrameSource frames = PageFrameSource(document: document);
        final PageFrame frame = await frames.frameFor(1);
        final PageGeometry geometry = document.geometry(1);

        FragmentLayout layoutOf(PageDisplayMode mode) => chooseFragmentLayout(
          mode: mode,
          content: frame.content,
          sheetWidth: geometry.width,
          sheetHeight: geometry.height,
          area: const DisplayArea(width: 1080, height: 2400),
          breaks: frame.breaks,
        );

        // Числа сравниваются между собой, а не с эталоном: у фикстур
        // рамка содержимого своя, и абсолютный выигрыш у них разный.
        // Обещание режима — «крупнее, и чем мельче доля, тем крупнее», —
        // а не конкретная цифра.
        final FragmentLayout half = layoutOf(PageDisplayMode.half);
        expect(half.orientation, ScreenOrientation.landscape, reason: name);
        expect(half.isWorthwhile, isTrue, reason: name);
        expect(half.gain, greaterThan(1.02), reason: name);

        // Треть не бывает мельче половины, но бывает равна ей: если
        // содержимое страницы низкое и широкое, масштаб упирается в
        // ширину, и резать по высоте дальше уже нечего. Так и выходит на
        // `basic_text.pdf`, где текст занимает узкую полосу вверху.
        final FragmentLayout third = layoutOf(PageDisplayMode.third);
        expect(third.orientation, ScreenOrientation.landscape, reason: name);
        expect(third.gain, greaterThanOrEqualTo(half.gain), reason: name);

        // Число полос одинаково в обеих книгах — ради этого всё и делалось.
        expect(
          fragmentsFor(
            content: frame.content,
            mode: PageDisplayMode.half,
          ).length,
          2,
          reason: name,
        );
        expect(
          fragmentsFor(
            content: frame.content,
            mode: PageDisplayMode.third,
          ).length,
          3,
          reason: name,
        );
      }
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

  group('обложки на корпусе', () {
    // Полка рисует обложку первой страницы каждой книги. Проверка
    // важна не тем, что PDFium умеет рисовать — это его работа, — а тем,
    // что **весь путь** до файла на диске проходит на настоящих книгах:
    // геометрия страницы, размер обложки, растр, наша упаковка в PNG.
    // Испорченная картинка на полке выглядит как сломанное приложение.
    _readable.forEach((String name, int pages) {
      test('$name даёт настоящий PNG', () async {
        final ReaderDocument document = await open(name);
        final PageGeometry page = document.geometry(1);
        final CoverSize? size = coverSizeFor(
          pageWidth: page.width,
          pageHeight: page.height,
        );
        expect(size, isNotNull, reason: 'у книги есть первая страница');

        final PageRaster? raster = await document.renderPage(
          1,
          width: size!.width,
          height: size.height,
        );
        expect(raster, isNotNull, reason: 'первая страница нарисовалась');
        expect(raster!.isConsistent, isTrue);

        final Uint8List png = encodeBgraToPng(
          raster.pixels,
          raster.width,
          raster.height,
        );
        // Читает чужой декодер — тот самый, которым Flutter покажет
        // обложку на полке.
        final ui.Codec codec = await ui.instantiateImageCodec(png);
        final ui.FrameInfo frame = await codec.getNextFrame();
        addTearDown(frame.image.dispose);
        addTearDown(codec.dispose);
        expect(frame.image.width, size.width);
        expect(frame.image.height, size.height);
      });
    });

    test('пропорции обложки повторяют пропорции страницы', () async {
      // Книга с четырьмя разными размерами страниц — тот случай, когда
      // обложка легко выходит сплющенной.
      final ReaderDocument document = await open('mixed_page_sizes.pdf');
      final PageGeometry page = document.geometry(1);
      final CoverSize size = coverSizeFor(
        pageWidth: page.width,
        pageHeight: page.height,
      )!;
      expect(size.height / size.width, closeTo(page.height / page.width, 0.02));
    });

    test('обложка альбомной страницы не выше положенного', () async {
      final ReaderDocument document = await open('rotated_pages.pdf');
      await document.measure(<int>[1, 2, 3, 4]);
      for (int p = 1; p <= document.pageCount; p++) {
        final PageGeometry page = document.geometry(p);
        final CoverSize size = coverSizeFor(
          pageWidth: page.width,
          pageHeight: page.height,
        )!;
        expect(size.width, lessThanOrEqualTo(kCoverWidth));
        expect(size.height, lessThanOrEqualTo(kCoverMaxHeight));
        expect(size.width, greaterThan(0));
        expect(size.height, greaterThan(0));
      }
    });

    test('скан без текстового слоя всё равно получает обложку', () async {
      // Обложка — это картинка, и текстовый слой ей не нужен вовсе.
      // Читатель со сканами не обязан смотреть на полку из заглушек.
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageGeometry page = document.geometry(1);
      final CoverSize size = coverSizeFor(
        pageWidth: page.width,
        pageHeight: page.height,
      )!;
      final PageRaster? raster = await document.renderPage(
        1,
        width: size.width,
        height: size.height,
      );
      expect(raster, isNotNull);
      expect(
        _darkPixels(raster!),
        greaterThan(0),
        reason: 'на обложке скана должно быть хоть что-то, кроме белого',
      );
    });
  });

  group('чтение по файловому дескриптору', () {
    // Главная проверка S5.1. На Android книга открывается не по пути —
    // пути у документа нет вовсе, — а по дескриптору, который читается
    // `pread`'ом кусками. Здесь дескриптор даёт та же libc, что и на
    // телефоне, поэтому в CI гоняется ровно тот код, который поедет на
    // устройство: движок, колбэк чтения, системный вызов.
    late DescriptorFileStorage descriptors;
    late PdfrxDocumentOpener byDescriptor;

    setUp(() {
      descriptors = DescriptorFileStorage();
      byDescriptor = PdfrxDocumentOpener(
        storage: descriptors,
        initialize: () => pdfrxInitialize(tmpPath: tmp.path),
        // Ноль запрещает движку затянуть маленький файл в память
        // целиком: иначе корпус из файлов по паре килобайт проверял бы
        // не чтение кусками, а обход для мелочи.
        maxBytesInMemory: 0,
      );
    });

    _readable.forEach((String name, int pages) {
      test('$name читается так же, как по пути', () async {
        final ReaderDocument viaPath = await open(name);
        final ReaderDocument viaFd = await byDescriptor.open(_source(name));
        addTearDown(viaFd.close);

        expect(viaFd.pageCount, pages);
        expect(viaFd.pageCount, viaPath.pageCount);
        expect(await viaFd.pageText(1), await viaPath.pageText(1));
        expect(
          viaFd.geometry(1).width,
          closeTo(viaPath.geometry(1).width, 1e-6),
        );
        final PageGeometry geometry = viaFd.geometry(1);
        final PageRaster? raster = await viaFd.renderPage(
          1,
          width: 120,
          height: (120 * geometry.height / geometry.width).round(),
        );
        expect(raster?.isConsistent, isTrue);
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    test('дескриптор закрывается вместе с книгой', () async {
      final ReaderDocument document = await byDescriptor.open(
        _source('basic_text.pdf'),
      );
      expect(descriptors.openCount, 1);
      await document.close();
      // Закрытие дескриптора движок делает через `onDispose`, а тот
      // асинхронный: даём событию доехать.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        descriptors.openCount,
        0,
        reason: 'дескрипторы текут — на полке в сотню книг это потолок',
      );
    });

    test('битый файл по дескриптору тоже не роняет приложение', () async {
      await expectLater(
        byDescriptor.open(_source('truncated.pdf')),
        throwsA(isA<DocumentOpenException>()),
      );
    });

    test('пустой файл по дескриптору — понятная причина', () async {
      await expectLater(
        byDescriptor.open(_source('empty_file.pdf')),
        throwsA(
          isA<DocumentOpenException>().having(
            (DocumentOpenException e) => e.problem,
            'причина',
            DocumentProblem.empty,
          ),
        ),
      );
    });
  });

  group('F-READ-02: книга открывается, не измеряя все страницы', () {
    test('F-READ-02: число страниц известно сразу, размеры — нет', () async {
      // Прежде движок до первого кадра загружал каждую страницу книги
      // ради её размера. Теперь при открытии измерена одна первая, а
      // число страниц отдаёт сам файл.
      final ReaderDocument document = await open('huge_1200_pages.pdf');
      expect(document.pageCount, 1200);

      final PdfDocument engine = document.engineDocument! as PdfDocument;
      expect(engine.pages.length, 1200);
      expect(engine.pages.first.isLoaded, isTrue);
      expect(
        engine.pages.where((PdfPage page) => page.isLoaded).length,
        lessThan(1200),
        reason: 'книга измерена целиком уже при открытии',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('F-READ-02: содержимое неизмеренной страницы доступно', () async {
      // У неизмеренной страницы движок не отдаёт ни текста, ни растра.
      // Документ обязан домерить её сам, не дожидаясь, пока до неё
      // дойдёт просмотрщик.
      final ReaderDocument document = await open('huge_1200_pages.pdf');

      expect(await document.pageText(900), contains('Long book page'));
      expect(await document.pageTextBoxes(1000), isNotEmpty);
      expect((await document.pageTextLayout(950)).hasGeometry, isTrue);
      final PageRaster? raster = await document.renderPage(
        1100,
        width: 100,
        height: 141,
      );
      expect(raster, isNotNull);
      expect(_darkPixels(raster!), greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('F-READ-02: измерение делает геометрию настоящей', () async {
      final ReaderDocument document = await open('mixed_page_sizes.pdf');
      await document.measure(<int>[4]);
      expect(document.geometry(4).width, closeTo(200, 0.5));

      // Номера за краем книги пропускаются, а не роняют открытие.
      await document.measure(<int>[0, 5, 99]);
    });

    test('F-READ-02: рамка страницы из середины толстой книги', () async {
      final ReaderDocument document = await open('book_120_pages.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);

      final PageFrame even = await frames.frameFor(60);
      final PageFrame odd = await frames.frameFor(61);
      expect(even.fromText, isTrue);
      expect(odd.fromText, isTrue);
      // Поля зеркальны, как в переплёте: у нечётной страницы текст
      // начинается правее.
      expect(odd.content.left, greaterThan(even.content.left));
    });

    test('F-READ-02: поиск по всей книге видит все страницы', () async {
      // Цена прогрессивного открытия, записанная в документации pdfrx:
      // текст неизмеренной страницы пуст. Поиск не имеет права её
      // заплатить — он обязан найти слово на любой странице сразу после
      // открытия книги.
      final ReaderDocument book = await open('book_120_pages.pdf');
      final DocumentSearch search = DocumentSearch(document: book);
      addTearDown(search.dispose);
      await search.start('book-token-117');
      expect(search.hits.length, 1);
      expect(search.hits.single.pageNumber, 117);
      expect(search.scannedPages, 120);

      final ReaderDocument huge = await open('huge_1200_pages.pdf');
      final DocumentSearch everywhere = DocumentSearch(
        document: huge,
        hitLimit: 5000,
      );
      addTearDown(everywhere.dispose);
      await everywhere.start('Long book page');
      expect(everywhere.scannedPages, 1200);
      expect(everywhere.hits.length, 1200, reason: 'по совпадению на страницу');
      expect(everywhere.hits.last.pageNumber, 1200);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('F-READ-02: измерить всё при открытии по-прежнему можно', () async {
      final PdfrxDocumentOpener whole = PdfrxDocumentOpener(
        storage: const LocalBookStorage(),
        initialize: () => pdfrxInitialize(tmpPath: tmp.path),
        measureAllPages: true,
      );
      final ReaderDocument document = await whole.open(
        _source('book_120_pages.pdf'),
      );
      addTearDown(document.close);

      final PdfDocument engine = document.engineDocument! as PdfDocument;
      expect(engine.pages.every((PdfPage page) => page.isLoaded), isTrue);
    });
  });

  group('F-READ-02: замеры скорости', () {
    // Числа уходят в журнал прогона строками «ЗАМЕР F-READ-02» и оттуда —
    // в PROGRESS.md. Сравнивать их с порогом здесь нельзя: раннер CI
    // шумит, и тест начал бы падать от соседа по железу, а не от кода.
    // Плавность показа на экране эти замеры не видят вовсе — только
    // открытие книги и расчёт рамки; остальное проверяется на устройстве.
    final PdfrxDocumentOpener whole = PdfrxDocumentOpener(
      storage: const LocalBookStorage(),
      initialize: () => pdfrxInitialize(tmpPath: tmp.path),
      measureAllPages: true,
    );

    void report(String book, String what, double before, double after) {
      stdout.writeln(
        'ЗАМЕР F-READ-02 | $book | $what | '
        'было ${before.toStringAsFixed(1)} мс | '
        'стало ${after.toStringAsFixed(1)} мс',
      );
    }

    double median(List<double> samples) {
      final List<double> sorted = List<double>.of(samples)..sort();
      return sorted[sorted.length ~/ 2];
    }

    double elapsedMs(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

    /// Время открытия книги: медиана пяти открытий.
    Future<double> openMs(DocumentOpener by, String name) async {
      final List<double> samples = <double>[];
      for (int run = 0; run < 5; run++) {
        final Stopwatch watch = Stopwatch()..start();
        final ReaderDocument document = await by.open(_source(name));
        watch.stop();
        samples.add(elapsedMs(watch));
        await document.close();
      }
      return median(samples);
    }

    /// Время от начала открытия до рамки страницы [page].
    Future<double> firstFrameMs(
      DocumentOpener by,
      String name,
      int page,
    ) async {
      final List<double> samples = <double>[];
      for (int run = 0; run < 5; run++) {
        final Stopwatch watch = Stopwatch()..start();
        final ReaderDocument document = await by.open(_source(name));
        await PageFrameSource(document: document).frameFor(page);
        watch.stop();
        samples.add(elapsedMs(watch));
        await document.close();
      }
      return median(samples);
    }

    const Map<String, int> books = <String, int>{
      'huge_1200_pages.pdf': 1200,
      'book_120_pages.pdf': 120,
      'scan_no_text.pdf': 2,
    };

    books.forEach((String name, int pages) {
      test('F-READ-02: $name — открытие и первая рамка', () async {
        // Первое открытие в прогоне греет движок и в счёт не идёт.
        await (await opener.open(_source(name))).close();
        final int middle = (pages + 1) ~/ 2;

        final double openBefore = await openMs(whole, name);
        final double openAfter = await openMs(opener, name);
        report(name, 'открытие книги', openBefore, openAfter);

        final double frameBefore = await firstFrameMs(whole, name, middle);
        final double frameAfter = await firstFrameMs(opener, name, middle);
        report(
          name,
          'открытие и рамка страницы $middle',
          frameBefore,
          frameAfter,
        );

        expect(openAfter.isFinite && frameAfter.isFinite, isTrue);
      }, timeout: const Timeout(Duration(minutes: 5)));

      test('F-READ-02: $name — переход на соседнюю страницу', () async {
        final int steps = math.min(20, pages - 1);

        // Было: переход ждал рамку страницы, на которую идёт (BUG-23).
        final ReaderDocument cold = await open(name);
        final PageFrameSource frames = PageFrameSource(document: cold);
        await frames.frameFor(1);
        final List<double> waited = <double>[];
        for (int page = 2; page <= steps + 1; page++) {
          final Stopwatch watch = Stopwatch()..start();
          await frames.frameFor(page);
          watch.stop();
          waited.add(elapsedMs(watch));
        }

        // Стало: рамка посчитана заранее, пока читатель читал страницу.
        final ReaderDocument warm = await open(name);
        final ReaderController controller = ReaderController(
          book: fakeBook(pageCount: pages),
          document: warm,
          reading: FakeReadingRepository(),
        );
        await controller.loadFrame();
        final List<double> turned = <double>[];
        for (int step = 0; step < steps; step++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          final Stopwatch watch = Stopwatch()..start();
          await controller.nextFragment();
          watch.stop();
          turned.add(elapsedMs(watch));
        }
        report(
          name,
          'переход на соседнюю страницу',
          median(waited),
          median(turned),
        );
        expect(controller.page, steps + 1);

        await controller.close();
        controller.dispose();
      }, timeout: const Timeout(Duration(minutes: 5)));
    });

    test('F-READ-02: дальний переход не ждёт рамку дольше срока', () async {
      // Скан — худший случай: рамка там считается рендером с разбором.
      // Было — ожидание рамки целиком; стало — не дольше отведённого.
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final Stopwatch before = Stopwatch()..start();
      await frames.frameFor(2);
      before.stop();

      final ReaderDocument fresh = await open('scan_no_text.pdf');
      final ReaderController controller = ReaderController(
        book: fakeBook(pageCount: 2),
        document: fresh,
        reading: FakeReadingRepository(),
      );
      final Stopwatch after = Stopwatch()..start();
      expect(await controller.goToPage(2), isTrue);
      after.stop();
      report(
        'scan_no_text.pdf',
        'переход на непосчитанную страницу',
        elapsedMs(before),
        elapsedMs(after),
      );
      // Запас на раннер: срок — шестьдесят миллисекунд, и переход,
      // который ждал бы рамку до победного, на загруженной машине
      // легко уходит за полсекунды.
      expect(
        after.elapsed,
        lessThan(kFrameWait + const Duration(milliseconds: 400)),
      );

      await controller.close();
      controller.dispose();
    });

    test('F-READ-02: сколько стоит измерить всю книгу', () async {
      // Столько открытие книги больше не ждёт. Не идёт эта работа и в
      // фоне: просмотрщик меряет страницы по мере надобности
      // (`loadPageDimensionsOnDemand`), а не обходит всю книгу.
      for (final String name in <String>[
        'huge_1200_pages.pdf',
        'book_120_pages.pdf',
      ]) {
        final ReaderDocument document = await open(name);
        final PdfDocument engine = document.engineDocument! as PdfDocument;
        final Stopwatch watch = Stopwatch()..start();
        await engine.loadPagesProgressively<void>();
        watch.stop();
        stdout.writeln(
          'ЗАМЕР F-READ-02 | $name | измерить все страницы | '
          '${elapsedMs(watch).toStringAsFixed(1)} мс',
        );
        expect(engine.pages.every((PdfPage page) => page.isLoaded), isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('F-READ-15: рамка обрезки на книгу', () {
    /// Рамка книги так, как её считает приложение: выборка страниц,
    /// рамка каждой, устойчивый прямоугольник.
    Future<BookFrame> bookFrameOf(
      ReaderDocument document,
      PageFrameSource frames,
    ) async {
      final List<FrameSample> samples = <FrameSample>[];
      for (final int page in bookFrameSamplePages(document.pageCount)) {
        final PageFrame frame = await frames.frameFor(page);
        samples.add(FrameSample(page: page, content: frame.content));
      }
      return bookFrameFromSamples(
        samples,
        ignoreRunningHeads: frames.options.ignoreRunningHeads,
      );
    }

    /// Файлы, где страницы точно несут текстовый слой.
    const Set<String> withText = <String>{
      'basic_text.pdf',
      'two_columns.pdf',
      'book_120_pages.pdf',
    };

    for (final String name in <String>[
      'basic_text.pdf',
      'outline_nested.pdf',
      'two_columns.pdf',
      'cjk.pdf',
      'rtl.pdf',
      'rotated_pages.pdf',
      'mixed_page_sizes.pdf',
      'broken_xref.pdf',
      'book_120_pages.pdf',
    ]) {
      test('F-READ-15: $name — ни один символ не срезан', () async {
        final ReaderDocument document = await open(name);
        // Колонтитулы здесь считаются содержимым: так проверяется каждый
        // символ страницы, а не только тело текста.
        final PageFrameSource frames = PageFrameSource(
          document: document,
          options: const CropOptions(ignoreRunningHeads: false),
          cacheSize: 200,
        );
        final BookFrame book = await bookFrameOf(document, frames);

        int checked = 0;
        for (int page = 1; page <= document.pageCount; page++) {
          final PageFrame own = await frames.frameFor(page);
          if (!own.fromText) {
            // Страница без текстового слоя: срезать по тексту нечего.
            continue;
          }
          final CropBox content = pageContentInBook(
            book: book,
            page: page,
            own: own.content,
            ownFromText: true,
          );
          final List<TextBox> boxes = await document.pageTextBoxes(page);
          double left = 1;
          double top = 1;
          double right = 0;
          double bottom = 0;
          for (final TextBox box in boxes) {
            left = math.min(left, box.left);
            top = math.min(top, box.top);
            right = math.max(right, box.right);
            bottom = math.max(bottom, box.bottom);
          }
          final String where = '$name, страница $page';
          expect(left, greaterThanOrEqualTo(content.left), reason: where);
          expect(top, greaterThanOrEqualTo(content.top), reason: where);
          expect(right, lessThanOrEqualTo(content.right), reason: where);
          expect(bottom, lessThanOrEqualTo(content.bottom), reason: where);
          checked++;
        }
        // В остальных файлах корпуса на странице может быть меньше
        // символов, чем нужно рамке по тексту, — там проверять нечего.
        if (withText.contains(name)) {
          expect(checked, greaterThan(0), reason: 'в файле есть текст');
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    test('F-READ-15: у книги из переплёта ширина текста одна', () async {
      final ReaderDocument document = await open('book_120_pages.pdf');
      final PageFrameSource frames = PageFrameSource(
        document: document,
        cacheSize: 200,
      );
      final BookFrame book = await bookFrameOf(document, frames);
      expect(book.hasContent, isTrue);
      expect(book.samples, kBookFrameSample);
      expect(book.isMirrored, isTrue, reason: 'поля в корпусе зеркальны');

      // Было: рамка у каждой страницы своя, и ширина текста гуляет.
      final Set<String> before = <String>{};
      final Set<String> after = <String>{};
      int widened = 0;
      for (int page = 1; page <= document.pageCount; page++) {
        final PageFrame own = await frames.frameFor(page);
        before.add(own.content.width.toStringAsFixed(4));
        final CropBox content = pageContentInBook(
          book: book,
          page: page,
          own: own.content,
          ownFromText: own.fromText,
        );
        if (content == book.forPage(page)) {
          after.add(content.width.toStringAsFixed(4));
        } else {
          widened++;
        }
      }
      stdout.writeln(
        'ЗАМЕР F-READ-15 | book_120_pages.pdf | разных ширин рамки | '
        'было ${before.length} | стало ${after.length} | '
        'страниц с расширенной рамкой $widened из ${document.pageCount}',
      );
      expect(after.length, 1, reason: 'рамка одна — ширина одна');
      // Страницы, чей текст выходит за рамку книги, получают свою рамку.
      // Если таких много, рамка книги взята слишком узкой.
      expect(widened, lessThanOrEqualTo(document.pageCount ~/ 4));
    });

    test('F-READ-15: выборка дешевле постраничного расчёта', () async {
      // Числа уходят в журнал прогона строкой «ЗАМЕР»; с порогом здесь не
      // сравниваются: раннер шумит.
      final ReaderDocument cold = await open('book_120_pages.pdf');
      final Stopwatch sampled = Stopwatch()..start();
      final BookFrame book = await bookFrameOf(
        cold,
        PageFrameSource(document: cold),
      );
      sampled.stop();

      final ReaderDocument whole = await open('book_120_pages.pdf');
      final PageFrameSource every = PageFrameSource(document: whole);
      final Stopwatch all = Stopwatch()..start();
      for (int page = 1; page <= whole.pageCount; page++) {
        await every.frameFor(page);
      }
      all.stop();
      stdout.writeln(
        'ЗАМЕР F-READ-15 | book_120_pages.pdf | рамка: вся книга '
        'постранично против выборки из ${book.samples} страниц | '
        'было ${(all.elapsedMicroseconds / 1000).toStringAsFixed(1)} мс | '
        'стало ${(sampled.elapsedMicroseconds / 1000).toStringAsFixed(1)} мс',
      );
      expect(book.samples, kBookFrameSample);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('F-READ-15: скан — рамка книги считается по пикселям', () async {
      final ReaderDocument document = await open('scan_no_text.pdf');
      final PageFrameSource frames = PageFrameSource(document: document);
      final BookFrame book = await bookFrameOf(document, frames);
      expect(book.hasContent, isTrue);
      expect(book.odd.isValid, isTrue);
      // Своей рамки по тексту у скана нет — рамка книги стоит твёрдо.
      final PageFrame own = await frames.frameFor(1);
      expect(own.fromText, isFalse);
      expect(pageContentInBook(book: book, page: 1), book.forPage(1));
    });
  });
}
