import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/cover_service.dart';
import 'package:memoria/domain/library/book.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/cover.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/images/png.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';

Book _book({String id = 'book-1', String hash = 'hash-1'}) {
  return Book(
    id: id,
    title: 'Пиковая дама',
    source: FilePathSource('/books/$id.pdf'),
    fileSize: 2048,
    fileHash: hash,
    addedAt: DateTime.utc(2026, 8, 1),
  );
}

/// Открыватель, который считает обращения и видит, сколько документов
/// открыто одновременно.
class _CountingOpener implements DocumentOpener {
  _CountingOpener({this.failFor = const <String>{}});

  /// Отпечатки-источники, на которых открытие проваливается.
  final Set<String> failFor;

  /// Сколько раз открывали.
  int opens = 0;

  /// Сколько документов открыто прямо сейчас.
  int live = 0;

  /// Сколько было открыто одновременно в пике.
  int peak = 0;

  /// Пускать документы только по команде.
  final List<void Function()> gate = <void Function()>[];

  /// Держать ли открытие до [releaseAll].
  bool hold = false;

  @override
  Future<ReaderDocument> open(BookSource source, {String? password}) async {
    opens++;
    if (failFor.contains(source.encode())) {
      throw DocumentOpenException(DocumentProblem.missing, source);
    }
    if (hold) {
      await Future<void>(() {});
      final Completer<void> wait = Completer<void>();
      gate.add(wait.complete);
      await wait.future;
    }
    live++;
    peak = live > peak ? live : peak;
    return _TrackedDocument(this);
  }

  /// Пропускает всех, кто ждёт у ворот.
  void releaseAll() {
    final List<void Function()> waiting = <void Function()>[...gate];
    gate.clear();
    for (final void Function() open in waiting) {
      open();
    }
  }
}

class _TrackedDocument extends FakeReaderDocument {
  _TrackedDocument(this._owner) : super(pages: <String>['страница']);

  final _CountingOpener _owner;

  @override
  Future<void> close() async {
    _owner.live--;
    await super.close();
  }
}

void main() {
  late AppData data;

  setUp(() async => data = await openTestData());
  tearDown(() async => data.close());

  group('обложка рисуется один раз', () {
    test('повторный вопрос не трогает ни движок, ни диск', () async {
      final _CountingOpener opener = _CountingOpener();
      final MemoryCoverStore store = MemoryCoverStore();
      final CoverService covers = CoverService(
        opener: opener,
        store: store,
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      final Book book = _book();
      await data.library.save(book);

      final String? first = await covers.coverFor(book);
      final String? second = await covers.coverFor(book);
      final String? third = await covers.coverFor(book);

      expect(first, isNotNull);
      expect(second, first);
      expect(third, first);
      expect(opener.opens, 1, reason: 'книга открывалась ровно один раз');
      expect(store.reads, 1, reason: 'кэш спрашивали один раз');
    });

    test('готовая обложка из кэша не рисуется вовсе', () async {
      final _CountingOpener opener = _CountingOpener();
      final MemoryCoverStore store = MemoryCoverStore();
      final Book book = _book();
      await data.library.save(book);
      store.saved[coverKeyFor(book)] = '/covers/готовая.png';

      final CoverService covers = CoverService(
        opener: opener,
        store: store,
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      expect(await covers.coverFor(book), '/covers/готовая.png');
      expect(opener.opens, 0);
    });

    test('одна и та же книга под другим идентификатором делит обложку', () {
      // Ключ считается по отпечатку: книга, выбранная заново после
      // переезда файла, не рисуется второй раз.
      final Book first = _book(id: 'a', hash: 'одинаковый');
      final Book second = _book(id: 'b', hash: 'одинаковый');
      expect(coverKeyFor(first), coverKeyFor(second));
      expect(coverKeyFor(_book(hash: 'другой')), isNot(coverKeyFor(first)));
    });

    test('в ключе нет ничего, что сломает имя файла', () {
      final Book odd = _book(hash: '../../и/тут/слэши?и*звёзды');
      expect(coverKeyFor(odd), isNot(contains('/')));
      expect(coverKeyFor(odd), isNot(contains('.')));
      expect(coverKeyFor(odd), isNot(contains('*')));
    });
  });

  group('путь обложки доезжает до библиотеки', () {
    test('нарисованная обложка записывается книге', () async {
      final CoverService covers = CoverService(
        opener: _CountingOpener(),
        store: MemoryCoverStore(),
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      final Book book = _book();
      await data.library.save(book);

      final String? path = await covers.coverFor(book);
      final Book? saved = await data.library.bookById(book.id);
      expect(saved!.coverPath, path);
    });

    test('обложка снятой книги убирается вместе с ней', () async {
      final MemoryCoverStore store = MemoryCoverStore();
      final CoverService covers = CoverService(
        opener: _CountingOpener(),
        store: store,
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      final Book book = _book();
      await data.library.save(book);
      await covers.coverFor(book);
      expect(store.saved, isNotEmpty);

      await covers.forget(book);
      expect(store.saved, isEmpty);
    });
  });

  group('поломка одной книги не ломает полку', () {
    test('книга, которая не открывается, отдаёт пустую обложку', () async {
      final Book broken = _book(id: 'broken', hash: 'hash-broken');
      final _CountingOpener opener = _CountingOpener(
        failFor: <String>{broken.source.encode()},
      );
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      await data.library.save(broken);
      expect(await covers.coverFor(broken), isNull);
    });

    test('соседи по полке при этом получают свои обложки', () async {
      final Book broken = _book(id: 'broken', hash: 'hash-broken');
      final Book fine = _book(id: 'fine', hash: 'hash-fine');
      final _CountingOpener opener = _CountingOpener(
        failFor: <String>{broken.source.encode()},
      );
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      await data.library.save(broken);
      await data.library.save(fine);

      final List<String?> results = await Future.wait(<Future<String?>>[
        covers.coverFor(broken),
        covers.coverFor(fine),
      ]);
      expect(results[0], isNull);
      expect(results[1], isNotNull);
    });

    test('упавшая упаковка не оставляет книгу без ответа', () async {
      final CoverService covers = CoverService(
        opener: _CountingOpener(),
        store: MemoryCoverStore(),
        library: data.library,
        encode: (PageRaster raster) async => throw StateError('не сжалось'),
      );
      final Book book = _book();
      await data.library.save(book);
      expect(await covers.coverFor(book), isNull);
    });

    test('документ закрывается даже когда обложка не вышла', () async {
      final _CountingOpener opener = _CountingOpener();
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        encode: (PageRaster raster) async => throw StateError('не сжалось'),
      );
      final Book book = _book();
      await data.library.save(book);
      await covers.coverFor(book);
      // Незакрытый документ — это удержанный дескриптор и память PDFium.
      expect(opener.live, 0);
    });
  });

  group('очередь', () {
    test('одновременно открыто не больше положенного', () async {
      final _CountingOpener opener = _CountingOpener()..hold = true;
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        parallel: 2,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      final List<Future<String?>> pending = <Future<String?>>[];
      for (int i = 0; i < 8; i++) {
        final Book book = _book(id: 'book-$i', hash: 'hash-$i');
        await data.library.save(book);
        pending.add(covers.coverFor(book));
      }
      // Даём очереди раскрутиться и пропускаем всех, кто дошёл до ворот.
      for (int i = 0; i < 60; i++) {
        await Future<void>.delayed(Duration.zero);
        opener.releaseAll();
      }
      await Future.wait(pending);

      expect(opener.opens, 8, reason: 'все восемь книг обсчитаны');
      expect(
        opener.peak,
        lessThanOrEqualTo(2),
        reason: 'тридцать открытых книг съели бы всю память',
      );
    });

    test('снятая служба никого не оставляет ждать вечно', () async {
      final _CountingOpener opener = _CountingOpener()..hold = true;
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        parallel: 1,
        encode: (PageRaster raster) async => Uint8List(4),
      );
      final Book first = _book(id: 'a', hash: 'hash-a');
      final Book second = _book(id: 'b', hash: 'hash-b');
      await data.library.save(first);
      await data.library.save(second);

      // Первая книга занимает единственное место и встаёт у ворот,
      // вторая ждёт в очереди — именно её и обязан отпустить `dispose`.
      unawaited(covers.coverFor(first));
      final Future<String?> waiting = covers.coverFor(second);
      await Future<void>.delayed(Duration.zero);
      covers.dispose();

      expect(await waiting, isNull);
    });

    test('карточка ушла с экрана — её задание снято', () async {
      // Без этого прокрутка по тысяче файлов ставит в очередь тысячу
      // рендеров, и обложка книги, на которую читатель смотрит сейчас,
      // ждёт за девятьюстами чужими.
      final _CountingOpener opener = _CountingOpener()..hold = true;
      final CoverService covers = CoverService(
        opener: opener,
        store: MemoryCoverStore(),
        library: data.library,
        parallel: 1,
        encode: (PageRaster raster) async => Uint8List(4),
      );

      unawaited(
        covers.coverForSource(key: 'занял', source: const FilePathSource('/a')),
      );
      final Future<String?> queued = covers.coverForSource(
        key: 'ушёл',
        source: const FilePathSource('/b'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(covers.cancel('ушёл'), isTrue);
      expect(await queued, isNull);

      // Уже начатое задание снять нельзя: PDFium не останавливают посреди
      // страницы.
      expect(covers.cancel('занял'), isFalse);

      // А попросить снятую обложку заново — можно: карточка вернулась на
      // экран, и работа обязана начаться, а не считаться сделанной.
      final Future<String?> again = covers.coverForSource(
        key: 'ушёл',
        source: const FilePathSource('/b'),
      );
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
        opener.releaseAll();
      }
      expect(await again, isNotNull);

      covers.dispose();
    });
  });

  group('размер обложки', () {
    test('пропорции страницы сохраняются', () {
      final CoverSize? size = coverSizeFor(pageWidth: 595, pageHeight: 842);
      expect(size!.width, kCoverWidth);
      expect(size.height, (kCoverWidth * 842 / 595).round());
    });

    test('свиток рисуется уже, а не сплющивается', () {
      final CoverSize? size = coverSizeFor(pageWidth: 100, pageHeight: 900);
      expect(size!.height, lessThanOrEqualTo(kCoverMaxHeight));
      expect(size.width, lessThan(kCoverWidth));
      // Пропорция обязана остаться прежней: обложка тем и полезна, что
      // повторяет книгу.
      expect(size.height / size.width, closeTo(9, 0.05));
    });

    test('вырожденная страница честно отдаёт «нечего рисовать»', () {
      expect(coverSizeFor(pageWidth: 0, pageHeight: 100), isNull);
      expect(coverSizeFor(pageWidth: 100, pageHeight: 0), isNull);
      expect(coverSizeFor(pageWidth: double.nan, pageHeight: 100), isNull);
      expect(coverSizeFor(pageWidth: 100, pageHeight: double.infinity), isNull);
    });
  });

  group('упаковка в отдельном изоляте', () {
    test('изолят отдаёт тот же PNG, что и прямой вызов', () async {
      final Uint8List pixels = Uint8List(8 * 6 * 4);
      for (int i = 0; i < pixels.length; i++) {
        pixels[i] = (i * 13) & 0xFF;
      }
      final PageRaster raster = PageRaster(width: 8, height: 6, pixels: pixels);
      final Uint8List viaIsolate = await encodeCoverInIsolate(raster);
      expect(viaIsolate, encodeBgraToPng(pixels, 8, 6));
    });
  });
}
