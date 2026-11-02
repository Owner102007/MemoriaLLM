/// F-MAP-18 в расчёте карты: паспорт файла читается один раз и лежит по
/// отпечатку, доверие считается по запомненному тексту и пересчитывается
/// только при новом тексте; скан без слоя встаёт без созвездия.
///
/// База настоящая, в памяти; словарь — маленький, из слов самих книг;
/// паспорт — подставной (настоящий PDFium — `test/pdf/`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/map/map_builder.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/map/book_bag.dart';
import 'package:memoria/domain/map/book_map.dart';
import 'package:memoria/domain/map/book_passport.dart';
import 'package:memoria/domain/map/file_passport.dart';
import 'package:memoria/domain/map/map_trusted.dart';
import 'package:memoria/domain/map/text_trust.dart';
import 'package:memoria/domain/reading/page_text.dart';

import '../data/test_data.dart';

/// Паспорт, который считает, сколько раз его читали.
class _CountingReader implements PassportReader {
  int reads = 0;

  @override
  Future<FilePassport?> read(BookSource source) async {
    reads++;
    return passportOf(<PageFacts>[
      for (int i = 0; i < 6; i++) const PageFacts(chars: 900, imageShare: 0),
    ]);
  }
}

/// Слова тем: сосуды и интегралы.
const List<String> _angio = <String>[
  'артерия',
  'вена',
  'капилляр',
  'сосуд',
  'кровь',
  'сердце',
  'аорта',
  'давление',
  'стенка',
  'клапан',
];
const List<String> _math = <String>[
  'интеграл',
  'функция',
  'предел',
  'производная',
  'ряд',
  'сумма',
  'число',
  'задача',
  'теорема',
  'формула',
];

/// Страница из 40 слов темы, со сдвигом [shift] — книги не одинаковы.
String _page(List<String> words, int shift) =>
    <String>[for (int i = 0; i < 40; i++) words[(i * 3 + shift) % words.length]]
        .join(' ');

void main() {
  late AppData data;
  late _CountingReader reader;
  final Lexicon lexicon = SetLexicon(<String>[..._angio, ..._math]);

  setUp(() async {
    data = await openTestData();
    reader = _CountingReader();
  });

  tearDown(() async {
    await data.close();
  });

  MapBuilder builder() => MapBuilder(
    library: data.library,
    categories: data.categories,
    texts: data.pageTexts,
    store: data.bookMap,
    bags: (BagRequest request) async => bagOfBook(request),
    layout: (List<BookBag> found) async => buildBookMap(found),
    passports: data.passports,
    passportReader: reader,
    lexicon: () async => lexicon,
  );

  /// Книга с [pages] страницами текста; у книги всего [total] страниц.
  Future<void> addBook(String id, List<String> pages, {int? total}) async {
    final Book book = testBook(id: id, title: 'Том $id', hash: 'hash-$id');
    await data.library.save(
      book.copyWith(pageCount: total ?? (pages.isEmpty ? 6 : pages.length)),
    );
    await data.pageTexts.savePageTexts(
      PageTextKey(bookId: id, fingerprint: 'hash-$id'),
      <int, String>{
        for (int i = 0; i < (pages.isEmpty ? 6 : pages.length); i++)
          i + 1: pages.isEmpty ? '' : pages[i],
      },
    );
  }

  /// Шесть надёжных книг: три про сосуды, три про интегралы.
  Future<void> addLibrary() async {
    for (int k = 0; k < 3; k++) {
      await addBook('a$k', <String>[
        for (int p = 0; p < 6; p++) _page(_angio, k + p),
      ]);
      await addBook('m$k', <String>[
        for (int p = 0; p < 6; p++) _page(_math, k + p),
      ]);
    }
  }

  Future<StoredBookMap> build() async {
    final MapBuilder map = builder();
    await map.build(await map.plan());
    return (await data.bookMap.load())!;
  }

  test(
    'F-MAP-18: паспорт и доверие хранятся по отпечатку и не пересчитываются',
    () async {
      await addLibrary();
      await build();
      expect(reader.reads, 6);
      final PassportRecord first = (await data.passports.load('hash-a0'))!;
      expect(first.version, kPassportVersion);
      expect(first.passport?.kind, BookKind.digital);
      expect(first.trustKind, TrustKind.measured);
      expect(first.trust, greaterThanOrEqualTo(kTrustLow));
      expect(first.trustPages, 6);
      expect(first.pageTrust, everyElement(PageTrust.yes));

      // Второй расчёт той же полки: PDF не открывается заново.
      await data.bookMap.clear();
      await build();
      expect(reader.reads, 6);

      // Книга дочитана до седьмой страницы — доверие пересчитано,
      // паспорт — нет.
      await data.library.save(
        (await data.library.bookById('a0'))!.copyWith(pageCount: 7),
      );
      await data.pageTexts.savePageTexts(
        const PageTextKey(bookId: 'a0', fingerprint: 'hash-a0'),
        <int, String>{7: _page(_angio, 9)},
      );
      await build();
      expect(reader.reads, 6);
      expect((await data.passports.load('hash-a0'))!.trustPages, 7);
    },
  );

  test('F-MAP-18: скан без слоя — без категории, место по названию', () async {
    await addLibrary();
    // Шесть страниц без единого знака: скан без текстового слоя.
    await addBook('scan', const <String>[]);
    final StoredBookMap map = await build();
    final MapPoint scan = map.points['scan']!;
    expect(scan.constellation, -1);
    expect(scan.reason, MapReason.littleText);
    expect(
      (await data.passports.load('hash-scan'))!.trustKind,
      TrustKind.littleText,
    );
    // Остальные — в своих созвездиях, без причины.
    expect(map.points['a0']!.constellation, isNot(-1));
    expect(map.points['a0']!.reason, MapReason.none);
  });

  test('F-MAP-18: книга запомнена не целиком — текст пока не судят', () async {
    await addLibrary();
    // Две страницы из шестидесяти: судить рано.
    await addBook('part', <String>[
      _page(_angio, 1),
      _page(_angio, 2),
    ], total: 60);
    final StoredBookMap map = await build();
    expect(map.points['part']!.reason, MapReason.none);
    final PassportRecord record = (await data.passports.load('hash-part'))!;
    expect(record.trustKind, TrustKind.asIs);
    expect(record.trustTextVersion, isNull);
  });

  test('F-MAP-18: книга на языке без словаря идёт в карту как есть', () async {
    await addLibrary();
    await addBook('jp', <String>[
      for (int p = 0; p < 6; p++) List<String>.filled(40, '日本語の本です').join(' '),
    ]);
    await build();
    expect((await data.passports.load('hash-jp'))!.trustKind, TrustKind.asIs);
  });
}
