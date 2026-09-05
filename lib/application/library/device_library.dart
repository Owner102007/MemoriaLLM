import 'dart:async';

import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/library/device_files.dart';
import '../../domain/library/device_scan.dart';
import '../../domain/library/search_text.dart';
import '../../domain/library/storage_access.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/files/device_scanner.dart';
import '../../infrastructure/files/file_fingerprint.dart';
import '../../infrastructure/pdf/pdf_info.dart';

/// Как запускается обход. Подменяется в тестах на обход без изолята.
typedef ScanRunner = Stream<ScanEvent> Function(List<String> roots);

/// Книги, лежащие на устройстве: обход, разборка и поиск.
///
/// Три ступени поиска идут **слоями по всей библиотеке**, а не подряд по
/// одному файлу. Имена есть у всех сразу — их дал обход. Метаданные
/// подъезжают через секунды: файл открывается на чтение, но не движком.
/// Текст первых страниц — через минуту: тут уже нужен PDFium. Ни одна
/// ступень не ждёт следующую, и книга находится по имени задолго до того,
/// как кто-нибудь прочитает её первую страницу.
class DeviceLibrary {
  /// Создаёт службу.
  DeviceLibrary({
    required DeviceFileRepository files,
    required StorageAccess access,
    required BookStorage storage,
    required DocumentOpener opener,
    ScanRunner? runner,
    Future<String> Function(BookHandle book)? fingerprint,
    DateTime Function()? now,
  }) : _files = files,
       _access = access,
       _storage = storage,
       _opener = opener,
       _runner = runner ?? scanInIsolate,
       _fingerprint = fingerprint ?? bookFingerprint,
       _now = now ?? DateTime.now;

  /// По сколько находок записывается в базу за раз.
  ///
  /// Не по одной: транзакция на каждый файл превращает обход тысячи книг
  /// в тысячу записей на диск. И не в конце: список на экране обязан
  /// расти по ходу дела, а не появиться разом через минуту.
  static const int kWriteBatch = 64;

  /// Сколько страниц смотрит разборка текста.
  ///
  /// Ищутся первые непустые: у скана первая страница часто обложка, у
  /// книги — титул. Дальше двадцатой не заглядываем: если на двадцати
  /// страницах текста нет вовсе, его нет и дальше.
  static const int kTextProbePages = 20;

  /// Сколько непустых страниц довольно для индекса.
  static const int kTextPages = 5;

  /// Сколько знаков текста уходит в индекс с одной книги.
  ///
  /// Пять страниц научной статьи — это тысячи знаков, и класть их целиком
  /// в индекс по тысяче файлов значит раздуть базу на десятки мегабайт
  /// ради хвостов, по которым никто не ищет.
  static const int kTextBudget = 4000;

  /// Ниже этого числа находок включается проход по опечаткам.
  static const int kFewResults = 5;

  /// Насколько похожим должно быть имя, чтобы считаться опечаткой.
  ///
  /// Треть общих триграмм — это примерно «одна-две буквы не те» на слове
  /// средней длины. Ниже начинается случайное сходство, и в выдачу лезет
  /// всё подряд.
  static const double kTypoThreshold = 0.34;

  final DeviceFileRepository _files;
  final StorageAccess _access;
  final BookStorage _storage;
  final DocumentOpener _opener;
  final ScanRunner _runner;
  final Future<String> Function(BookHandle book) _fingerprint;
  final DateTime Function() _now;

  StreamSubscription<ScanEvent>? _scan;
  Completer<void>? _finished;

  /// Идёт ли обход прямо сейчас.
  bool get isScanning => _scan != null;

  /// Состояние разрешения на доступ ко всем файлам.
  Future<StorageAccessState> accessState() => _access.state();

  /// Открывает системный экран выдачи разрешения.
  Future<void> requestAccess() => _access.request();

  /// Живой список файлов устройства.
  Stream<List<DeviceFileRecord>> watchFiles() => _files.watchFiles();

  /// Обходит устройство и записывает найденное.
  ///
  /// Возвращает поток состояний: сколько найдено, сколько папок пройдено.
  /// Последнее состояние — с [ScanProgress.done].
  Stream<ScanProgress> scan() {
    final StreamController<ScanProgress> progress =
        StreamController<ScanProgress>();
    unawaited(_runScan(progress));
    progress.onCancel = stopScan;
    return progress.stream;
  }

  /// Останавливает обход.
  ///
  /// Отписка от потока не приводит к `onDone` — значит, тот, кто ждёт
  /// конца обхода, ждал бы вечно. Поэтому конец объявляется здесь же:
  /// остановленный обход обязан закончиться так же честно, как дошедший
  /// до края.
  Future<void> stopScan() async {
    final StreamSubscription<ScanEvent>? scan = _scan;
    _scan = null;
    await scan?.cancel();
    final Completer<void>? finished = _finished;
    _finished = null;
    if (finished != null && !finished.isCompleted) {
      finished.complete();
    }
  }

  /// Разбирает следующую порцию файлов.
  ///
  /// Возвращает, сколько файлов разобрано. Ноль означает, что на этой
  /// ступени работы больше нет.
  ///
  /// Порция, а не всё сразу: разборка идёт, пока читатель смотрит на
  /// список, и обязана уступать ему и движок, и диск.
  Future<int> indexBatch({required IndexStage upTo, int limit = 8}) async {
    final List<DeviceFileRecord> pending = await _files.pendingIndex(
      upTo: upTo,
      limit: limit,
    );
    int done = 0;
    for (final DeviceFileRecord record in pending) {
      final _Indexed next = record.stage == IndexStage.name
          ? await _readMeta(record)
          : await _readText(record);
      await _files.saveFile(next.record, body: next.body);
      done++;
    }
    return done;
  }

  /// Ищет по устройству.
  ///
  /// Сначала точный запрос по индексу. Если нашлось мало, включается
  /// второй проход — по триграммам имён: `Достаевский` обязан находить
  /// `Достоевский`. Второй проход именно второй, а не всегда: похожесть
  /// имён размывает выдачу, и платить ею за каждый запрос незачем.
  Future<List<DeviceBookEntry>> find(String query) async {
    final List<DeviceFileRecord> all = await _files.files();
    if (searchTokens(query).isEmpty) {
      return groupDeviceFiles(all);
    }
    final Map<String, DeviceFileRecord> byPath = <String, DeviceFileRecord>{
      for (final DeviceFileRecord record in all) record.path: record,
    };

    final List<String> exact = await _files.search(query);
    final List<DeviceFileRecord> ranked = <DeviceFileRecord>[
      for (final String path in exact)
        if (byPath[path] case final DeviceFileRecord record)
          if (!record.missing) record,
    ];

    if (ranked.length < kFewResults) {
      final Set<String> already = <String>{
        for (final DeviceFileRecord record in ranked) record.path,
      };
      final List<_Similar> similar = <_Similar>[];
      for (final DeviceFileRecord record in all) {
        if (record.missing || already.contains(record.path)) {
          continue;
        }
        final double score = trigramSimilarity(
          query,
          '${record.name} ${record.title ?? ''}',
        );
        if (score >= kTypoThreshold) {
          similar.add(_Similar(record, score));
        }
      }
      similar.sort((_Similar a, _Similar b) => b.score.compareTo(a.score));
      ranked.addAll(similar.map((_Similar item) => item.record));
    }

    // Склейка идёт **после** ранжирования и порядок сохраняет: карточка
    // встаёт туда, где стоял её лучший путь.
    final List<DeviceBookEntry> grouped = groupDeviceFiles(ranked);
    final Map<String, int> order = <String, int>{
      for (int i = 0; i < ranked.length; i++) ranked[i].path: i,
    };
    grouped.sort((DeviceBookEntry a, DeviceBookEntry b) {
      final int left = order[a.primary.path] ?? order.length;
      final int right = order[b.primary.path] ?? order.length;
      return left.compareTo(right);
    });
    return grouped;
  }

  /// Забывает список файлов и индекс: разрешение отозвано.
  Future<void> forgetDevice() => _files.forgetEverything();

  Future<void> _runScan(StreamController<ScanProgress> progress) async {
    final StorageAccessState state = await _access.state();
    if (!state.allowsScan) {
      progress.add(
        const ScanProgress(found: 0, visitedDirectories: 0, done: true),
      );
      await progress.close();
      return;
    }
    final List<String> roots = await _access.roots();
    if (roots.isEmpty) {
      progress.add(
        const ScanProgress(found: 0, visitedDirectories: 0, done: true),
      );
      await progress.close();
      return;
    }

    final List<DeviceFileRecord> known = await _files.files();
    final Set<String> visitedPaths = <String>{};
    final List<ScannedFile> batch = <ScannedFile>[];
    final Map<String, DeviceFileRecord> byPath = <String, DeviceFileRecord>{
      for (final DeviceFileRecord record in known) record.path: record,
    };
    int found = 0;
    int directories = 0;
    String current = '';

    Future<void> flush() async {
      if (batch.isEmpty) {
        return;
      }
      final List<ScannedFile> chunk = <ScannedFile>[...batch];
      batch.clear();
      // Сверяется только то, что в этой порции: вердикт «файла больше
      // нет» выносится в самом конце, когда известно, что обход дошёл
      // до всех папок.
      final List<ScanDecision> decisions = reconcileScan(
        known: <DeviceFileRecord>[
          for (final ScannedFile file in chunk)
            if (byPath[file.path] case final DeviceFileRecord record) record,
        ],
        found: chunk,
        seenAt: _now(),
      );
      await _files.applyScan(decisions);
    }

    // Записи идут цепочкой, а не вперемешку: обход находит файлы быстрее,
    // чем база успевает их принять, и две транзакции внахлёст ничего не
    // ускорят, зато сделают порядок записи непредсказуемым.
    Future<void> writes = Future<void>.value();
    final Completer<void> finished = Completer<void>();
    _finished = finished;
    // Подписка живёт в переменной, а не только в поле: так она заводится
    // и закрывается в одной функции — и видно, что забыть её закрытие
    // здесь негде.
    final StreamSubscription<ScanEvent> events = _runner(roots).listen(
      (ScanEvent event) {
        final ScannedFile? file = event.file;
        if (file == null) {
          directories = event.visited;
          current = event.directory;
        } else {
          found++;
          visitedPaths.add(file.path);
          batch.add(file);
        }
        if (batch.length >= kWriteBatch) {
          writes = writes.then((void _) => flush());
        }
        progress.add(
          ScanProgress(
            found: found,
            visitedDirectories: directories,
            currentDirectory: current,
          ),
        );
      },
      onDone: () {
        if (!finished.isCompleted) {
          finished.complete();
        }
      },
      onError: (Object error) {
        // Обход упал целиком — редкость, но список от этого не должен
        // осыпаться: то, что успели найти, уже записано.
        if (!finished.isCompleted) {
          finished.complete();
        }
      },
      cancelOnError: true,
    );
    _scan = events;

    await finished.future;
    _scan = null;
    _finished = null;
    await writes;
    await flush();

    // Пропавшие: те, кого знали, но в этом обходе не встретили.
    final List<DeviceFileRecord> gone = <DeviceFileRecord>[
      for (final DeviceFileRecord record in known)
        if (!visitedPaths.contains(record.path) && !record.missing) record,
    ];
    if (gone.isNotEmpty) {
      await _files.applyScan(<ScanDecision>[
        for (final DeviceFileRecord record in gone)
          ScanDecision(ScanVerdict.gone, record.copyWith(missing: true)),
      ]);
    }

    progress.add(
      ScanProgress(found: found, visitedDirectories: directories, done: true),
    );
    // Отписка не ждётся, и это не небрежность. Поток к этому моменту уже
    // кончился, отписка от него — формальность; а вот **ждать** её между
    // концом обхода и записью найденного нельзя: в подменённом времени
    // widget-теста ожидание, которому не нужен кадр, обрывает
    // `pumpAndSettle` — и найденные книги не успевают попасть в базу.
    // На это уже потрачен один прогон CI (№88).
    unawaited(events.cancel());
    await progress.close();
  }

  /// Вторая ступень: отпечаток и метаданные, без движка.
  ///
  /// Отпечаток считается здесь же, а не при обходе: он требует чтения
  /// файла, а обход обязан оставаться дешёвым. Зато файл открывается
  /// один раз на обе работы.
  Future<_Indexed> _readMeta(DeviceFileRecord record) async {
    final BookSource source = FilePathSource(record.path);
    BookHandle? handle;
    try {
      handle = await _storage.open(source);
      final String hash = await _fingerprint(handle);
      final PdfInfo info = await readPdfInfo(handle);
      return _Indexed(
        record.copyWith(
          fingerprint: hash,
          title: info.title,
          author: info.author,
          stage: IndexStage.meta,
        ),
      );
    } on Object {
      // Файл не открылся: его унесли, он битый, или это не PDF вовсе.
      // Ступень всё равно засчитывается — иначе разборка будет вечно
      // возвращаться к одному и тому же нечитаемому файлу.
      return _Indexed(record.copyWith(stage: IndexStage.meta));
    } finally {
      await handle?.close();
    }
  }

  /// Третья ступень: текст первых непустых страниц.
  Future<_Indexed> _readText(DeviceFileRecord record) async {
    ReaderDocument? document;
    try {
      document = await _opener.open(FilePathSource(record.path));
      final StringBuffer text = StringBuffer();
      int pages = 0;
      final int limit = document.pageCount < kTextProbePages
          ? document.pageCount
          : kTextProbePages;
      for (int page = 1; page <= limit; page++) {
        final String content = (await document.pageText(page)).trim();
        if (content.isEmpty) {
          continue;
        }
        pages++;
        text.write(content);
        text.write(' ');
        if (pages >= kTextPages || text.length >= kTextBudget) {
          break;
        }
      }
      final String body = text.toString();
      return _Indexed(
        record.copyWith(stage: IndexStage.text, hasTextLayer: pages > 0),
        // Текст уходит живым: приводить его к виду индекса — дело
        // репозитория, и делается это в одном месте.
        body: body.length > kTextBudget ? body.substring(0, kTextBudget) : body,
      );
    } on Object {
      // Книга не открылась движком. Она остаётся в списке и находится по
      // имени: обещать по ней поиск в тексте было бы неправдой.
      return _Indexed(
        record.copyWith(stage: IndexStage.text, hasTextLayer: false),
        body: '',
      );
    } finally {
      await document?.close();
    }
  }
}

class _Indexed {
  const _Indexed(this.record, {this.body});

  final DeviceFileRecord record;
  final String? body;
}

class _Similar {
  const _Similar(this.record, this.score);

  final DeviceFileRecord record;
  final double score;
}
