import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/library/book.dart';
import '../../domain/library/cover.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/images/png.dart';

/// Превращает растр страницы в PNG.
///
/// Подменяется в тестах: настоящая реализация уводит работу в отдельный
/// изолят, а изолят с подменённым временем `flutter test` не дожидается.
typedef CoverEncoder = Future<Uint8List> Function(PageRaster raster);

/// Рисует и хранит обложки книг.
///
/// **Что и почему уезжает в фоновый изолят.** Рисование страницы делает
/// PDFium, и делает это своими средствами — заворачивать его в свой
/// изолят значило бы открыть книгу второй раз, а этот урок проект уже
/// проходил в S4.3: вторая копия документа стоит вдвое больше памяти и
/// отдаёт страницы не сразу. Зато **упаковка картинки в PNG** — наша
/// работа, чистый Dart и настоящий счёт: сжатие полумегабайтного растра
/// на изоляте интерфейса заметно подёргивало бы полку при импорте
/// тридцати книг подряд. Именно она и уходит в `Isolate.run`.
///
/// Обложки рисуются **по две за раз**. Открытая книга — это документ
/// PDFium в памяти; тридцать разом при импорте папки учебников съели бы
/// её всю. Очередь заодно делает полку отзывчивой: первые карточки
/// получают картинки сразу, а не после того, как обсчитается последняя.
class CoverService {
  /// Создаёт службу.
  CoverService({
    required DocumentOpener opener,
    required CoverStore store,
    required LibraryRepository library,
    int width = kCoverWidth,
    int parallel = 2,
    CoverEncoder? encode,
  }) : _opener = opener,
       _store = store,
       _library = library,
       _width = width,
       _parallel = parallel < 1 ? 1 : parallel,
       _encode = encode ?? encodeCoverInIsolate;

  final DocumentOpener _opener;
  final CoverStore _store;
  final LibraryRepository _library;
  final int _width;
  final int _parallel;
  final CoverEncoder _encode;

  /// Уже отвеченные и ещё считающиеся обложки.
  ///
  /// Полка перестраивается на каждое изменение прогресса и на каждую
  /// прокрутку; без этой памяти карточка просила бы обложку заново
  /// в каждом кадре.
  final Map<String, Future<String?>> _known = <String, Future<String?>>{};
  final List<_CoverJob> _queue = <_CoverJob>[];
  int _running = 0;
  bool _disposed = false;

  /// Путь к обложке книги или `null`, если её не удалось нарисовать.
  ///
  /// Повторные вызовы для той же книги бесплатны: ни файла, ни движка они
  /// не трогают вовсе.
  Future<String?> coverFor(Book book) {
    final String key = coverKeyFor(book, width: _width);
    final Future<String?>? ready = _known[key];
    if (ready != null) {
      return ready;
    }
    final Completer<String?> completer = Completer<String?>();
    final Future<String?> result = completer.future;
    _known[key] = result;
    _queue.add(_CoverJob(book: book, key: key, completer: completer));
    _pump();
    return result;
  }

  /// Убирает обложку книги, снятой с полки.
  Future<void> forget(Book book) async {
    final String key = coverKeyFor(book, width: _width);
    _known.remove(key);
    await _store.remove(key);
  }

  /// Забывает посчитанное. Файлы кэша при этом остаются.
  void reset() {
    _known.clear();
  }

  /// Отменяет то, что ещё не начато.
  ///
  /// Уже идущий рендер не прерывается: PDFium остановить посреди
  /// страницы нельзя, а бросать документ неоткрытым — верный способ
  /// подвесить дескриптор.
  void dispose() {
    _disposed = true;
    for (final _CoverJob job in _queue) {
      if (!job.completer.isCompleted) {
        job.completer.complete(null);
      }
    }
    _queue.clear();
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final _CoverJob job = _queue.removeAt(0);
      _running++;
      unawaited(
        _render(job).then((String? path) {
          if (!job.completer.isCompleted) {
            job.completer.complete(path);
          }
        }).whenComplete(() {
          _running--;
          if (!_disposed) {
            _pump();
          }
        }),
      );
    }
  }

  Future<String?> _render(_CoverJob job) async {
    final String? cached = await _store.read(job.key);
    if (cached != null) {
      // Путь мог потеряться: кэш переехал, приложение переустановили,
      // база приехала с другого устройства. Книга при этом та же.
      if (job.book.coverPath != cached) {
        await _library.setCoverPath(job.book.id, cached);
      }
      return cached;
    }

    ReaderDocument? document;
    try {
      document = await _opener.open(job.book.source);
      if (document.pageCount < 1) {
        return null;
      }
      final PageGeometry page = document.geometry(1);
      final CoverSize? size = coverSizeFor(
        pageWidth: page.width,
        pageHeight: page.height,
        width: _width,
      );
      if (size == null) {
        return null;
      }
      final PageRaster? raster = await document.renderPage(
        1,
        width: size.width,
        height: size.height,
      );
      if (raster == null || !raster.isConsistent) {
        return null;
      }
      final Uint8List png = await _encode(raster);
      final String path = await _store.write(job.key, png);
      await _library.setCoverPath(job.book.id, path);
      return path;
    } on Object {
      // Книга не открылась, файл унесли, страница не нарисовалась — это
      // карточка с заглушкой вместо обложки, а не сломанная полка.
      // Остальные книги обязаны появиться как ни в чём не бывало.
      return null;
    } finally {
      await document?.close();
    }
  }
}

/// Упаковывает растр в PNG в отдельном изоляте.
Future<Uint8List> encodeCoverInIsolate(PageRaster raster) {
  final Uint8List pixels = raster.pixels;
  final int width = raster.width;
  final int height = raster.height;
  return Isolate.run(() => encodeBgraToPng(pixels, width, height));
}

class _CoverJob {
  _CoverJob({required this.book, required this.key, required this.completer});

  final Book book;
  final String key;
  final Completer<String?> completer;
}
