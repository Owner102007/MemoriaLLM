import '../../domain/library/book.dart';
import '../../domain/library/book_file_picker.dart';
import '../../domain/library/book_source.dart';
import '../../domain/library/book_storage.dart';
import '../../domain/library/ids.dart';
import '../../domain/library/scan_mark.dart';
import '../../domain/library/shelf.dart';
import '../../domain/reading/reader_document.dart';
import '../../infrastructure/files/file_fingerprint.dart';
import 'source_release.dart';

/// Чем закончился импорт пачки книг.
class ImportReport {
  /// Создаёт отчёт.
  const ImportReport({required this.added, required this.failed});

  /// Книги, вставшие на полку. В порядке выбора.
  final List<Book> added;

  /// Файлы, которые завести не удалось, и причина у каждого.
  final List<ImportFailure> failed;

  /// Сколько файлов было выбрано.
  int get total => added.length + failed.length;

  /// Всё ли получилось.
  bool get isClean => failed.isEmpty;

  /// Вставшие на полку сканы без текстового слоя (F-DEV-13).
  List<Book> get scans => <Book>[
    for (final Book book in added)
      if (isMarkedScan(book.hasTextLayer)) book,
  ];
}

/// Что сказать читателю после добавления книг.
///
/// F-DEV-13: о скане говорится **сразу**, а не когда читатель попробует
/// выделить в нём слово. Одна книга — названа она сама; пачка — число
/// сканов одной строкой: перечислять их поимённо в сообщении, которое
/// висит несколько секунд, незачем — у каждого метка на обложке.
String describeImportReport(ImportReport report) {
  if (report.added.isEmpty) {
    return 'Не удалось добавить ни одной книги из ${report.total}';
  }
  final List<Book> scans = report.scans;
  if (report.isClean && report.added.length == 1) {
    return scans.isEmpty
        ? 'Книга добавлена'
        : '«${scans.single.title}» — скан: $kScanExplanation';
  }
  final String head = report.isClean
      ? 'Добавлено книг: ${report.added.length}'
      : 'Добавлено ${report.added.length} из ${report.total}; '
            'не открылось: ${report.failed.length}';
  if (scans.isEmpty) {
    return head;
  }
  return '$head. Сканов без текста: ${scans.length} — в них не работают '
      'выделение, поиск и функции';
}

/// Файл, который не удалось завести.
class ImportFailure {
  /// Создаёт запись об отказе.
  const ImportFailure({required this.name, required this.reason, this.problem});

  /// Имя файла — по нему читатель поймёт, о какой книге речь.
  final String name;

  /// Что именно случилось, человеческими словами.
  final String reason;

  /// Причина, названная движком; `null` — отказ не от движка (файл не
  /// прочитался вовсе). Нужна там, где о причине говорят своими словами:
  /// [reason] написан для экрана чтения и зовёт ввести пароль, а при
  /// добавлении книги вводить его негде.
  final DocumentProblem? problem;
}

/// Выбранный заново файл — не тот, к которому была привязана книга
/// (BUG-19): отпечатки не совпали.
class RelinkMismatch {
  /// Создаёт описание расхождения.
  const RelinkMismatch({
    required this.book,
    required this.fileName,
    required this.pagesNow,
  });

  /// Книга, которую привязывают.
  final Book book;

  /// Имя выбранного файла.
  final String fileName;

  /// Сколько страниц в выбранном файле.
  final int pagesNow;

  /// Сколько страниц было в прежнем; `null` — не знаем.
  int? get pagesBefore => book.pageCount;
}

/// Перепривязка не состоялась: файл другой, а читатель на него не
/// согласился (BUG-19). Книга осталась как была.
class RelinkRefused implements Exception {
  /// Создаёт отказ.
  const RelinkRefused(this.mismatch);

  /// В чём расхождение.
  final RelinkMismatch mismatch;

  @override
  String toString() => 'RelinkRefused(${mismatch.fileName})';
}

/// Вопрос читателю: привязать ли книгу к другому файлу.
typedef RelinkConsent = Future<bool> Function(RelinkMismatch mismatch);

/// Что сказать читателю, когда выбранный файл — другой (BUG-19).
///
/// Числа страниц названы потому, что это единственное, что читатель
/// может сверить сам: отпечаток ему ничего не говорит.
String describeRelinkMismatch(RelinkMismatch mismatch) {
  final int? before = mismatch.pagesBefore;
  final String was = before == null ? '' : ' (страниц: $before)';
  final StringBuffer text = StringBuffer()
    ..write('«${mismatch.book.title}» была привязана к другому файлу$was. ')
    ..write('В выбранном — «${mismatch.fileName}» — ')
    ..write('страниц: ${mismatch.pagesNow}, и содержимое у него другое.')
    ..write('\n\n')
    ..write('Если это та же книга — другое издание или файл после ')
    ..write('распознавания, — привяжите его: место чтения, цитаты и ')
    ..write('заметки останутся при книге.');
  if (before != null && before != mismatch.pagesNow) {
    text.write(' При другом числе страниц они могут указывать не туда.');
  }
  text.write(' Если книга другая, выберите другой файл.');
  return text.toString();
}

/// Заводит выбранные файлы в библиотеке.
///
/// У книги должен быть постоянный идентификатор, иначе некуда записать
/// место, на котором её оставили, — с этого импорт и начался в S3. В S5.2
/// к нему добавились две вещи: книги заводятся пачкой и сразу в нужную
/// категорию полки.
class BookImporter {
  /// Создаёт сценарий импорта.
  ///
  /// [fingerprint] и [newId] подменяются в тестах: первый читает книгу,
  /// второй недетерминирован, и оба мешают проверять сам сценарий.
  BookImporter({
    required LibraryRepository library,
    required BookStorage storage,
    required DocumentOpener opener,
    Future<String> Function(BookHandle book)? fingerprint,
    String Function()? newId,
    DateTime Function()? now,
  }) : _library = library,
       _storage = storage,
       _opener = opener,
       _fingerprint = fingerprint ?? bookFingerprint,
       _newId = newId ?? newLibraryId,
       _now = now ?? DateTime.now;

  final LibraryRepository _library;
  final BookStorage _storage;
  final DocumentOpener _opener;
  final Future<String> Function(BookHandle book) _fingerprint;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Заводит выбранный файл и возвращает книгу.
  ///
  /// Сначала файл принимается хранилищем: на Android закрепляется
  /// разрешение на ссылку, а книга, которую нельзя читать кусками,
  /// потоково переносится к нам. Только потом она разбирается движком.
  ///
  /// Если такая книга уже на полке (совпал отпечаток), заводится не
  /// вторая её копия, а обновляется источник у прежней: файл мог
  /// переехать, но место, на котором книгу оставили, принадлежит книге,
  /// а не файлу.
  ///
  /// Бросает [DocumentOpenException], если файл не открывается: заводить
  /// в библиотеке книгу, которую нельзя прочесть, незачем.
  Future<Book> register(PickedFile file, {String? categoryId}) async {
    final BookSource source = await _storage.adopt(file);
    return registerSource(
      source,
      title: titleFromFileName(file.name),
      categoryId: categoryId,
    );
  }

  /// Заводит книгу, которая уже лежит по [source].
  ///
  /// Вторая половина [register]: файл принят хранилищем или положен в
  /// папку приложения иначе — распаковкой архива с литературой
  /// (SNO-F-LIT-01), где книга сразу пишется на своё место и принимать
  /// её ещё раз значило бы копировать дважды. Всё остальное — как у
  /// выбранного файла: та же книга второй раз не заводится, а источник,
  /// который не открылся, отпускается, если он ничей.
  ///
  /// [categoryFor] — категория, которую называют не заранее, а по
  /// требованию: её спрашивают, только когда книга новая и уже
  /// открылась. Архиву это нужно, чтобы заводить категорию под книгу,
  /// которая действительно встаёт на полку, и ставить книгу в неё одной
  /// записью.
  Future<Book> registerSource(
    BookSource source, {
    required String title,
    String? categoryId,
    Future<String?> Function()? categoryFor,
  }) async {
    try {
      return await _save(
        source,
        title,
        null,
        categoryId: categoryId,
        categoryFor: categoryFor,
        releaseReplaced: true,
      );
    } on Object {
      // Приняли файл, а прочесть не смогли: отпускаем принятое, чтобы
      // не копить в папке приложения копии нечитаемых книг и не держать
      // закреплённых ссылок в никуда.
      //
      // BUG-45: но не тогда, когда этот источник принадлежит книге, уже
      // стоящей на полке. Так бывает, когда её файл выбрали снова: копия
      // названа по содержимому, закреплённая ссылка — та же самая.
      // Отпустить такой источник значило бы удалить копию книги или
      // отозвать её ссылку из-за одного неудачного открытия.
      await _releaseUnused(source);
      rethrow;
    }
  }

  /// Отпускает [source], если он не принадлежит ни одной книге на полке.
  Future<void> _releaseUnused(BookSource source) async {
    await releaseUnusedSource(
      storage: _storage,
      library: _library,
      source: source,
    );
  }

  /// Заводит сразу несколько выбранных файлов.
  ///
  /// Одна неудача не отменяет остальных: в папке с учебниками попадётся и
  /// битый файл, и защищённый паролем, и вовсе не PDF с расширением
  /// `.pdf`. Читателю важнее, чтобы встали двадцать девять книг из
  /// тридцати, чем чтобы импорт целиком провалился из-за одной.
  ///
  /// [onProgress] зовётся после каждого файла — полке есть что показать,
  /// пока идёт разбор: «добавлено 7 из 12».
  Future<ImportReport> registerAll(
    List<PickedFile> files, {
    String? categoryId,
    void Function(int done, int total)? onProgress,
  }) async {
    final List<Book> added = <Book>[];
    final List<ImportFailure> failed = <ImportFailure>[];
    for (int i = 0; i < files.length; i++) {
      final PickedFile file = files[i];
      try {
        added.add(await register(file, categoryId: categoryId));
      } on DocumentOpenException catch (error) {
        failed.add(
          ImportFailure(
            name: file.name,
            reason: describeDocumentProblem(error.problem),
            problem: error.problem,
          ),
        );
      } on Object {
        failed.add(
          ImportFailure(name: file.name, reason: 'файл не удалось прочесть'),
        );
      }
      onProgress?.call(i + 1, files.length);
    }
    return ImportReport(added: added, failed: failed);
  }

  /// Привязывает книгу к заново выбранному файлу.
  ///
  /// Нужно, когда файл переименовали, перенесли или отозвали разрешение
  /// на ссылку. Идентификатор книги остаётся прежним, поэтому место
  /// чтения, цитаты и заметки не теряются: они принадлежат книге, а не
  /// файлу.
  ///
  /// BUG-19: именно поэтому файл обязан быть **тем же**. Отпечаток
  /// выбранного файла сверяется с отпечатком книги; прежде он считался и
  /// не сравнивался ни с чем, и место чтения, цитаты и заметки молча
  /// привязывались к чужому файлу. Не совпал — спрашивается [onMismatch]:
  /// другое издание и файл после распознавания — та же книга с другим
  /// отпечатком, и запретить такую привязку нельзя. Без согласия
  /// бросается [RelinkRefused], и книга остаётся как была.
  ///
  /// У книги без отпечатка сверять не с чем — она привязывается, как
  /// прежде.
  Future<Book> relink(
    Book book,
    PickedFile file, {
    RelinkConsent? onMismatch,
  }) async {
    final BookSource source = await _storage.adopt(file);
    final BookSource previous = book.source;
    final Book relinked;
    try {
      relinked = await _save(
        source,
        book.title,
        book,
        check: (String hash, int pageCount) async {
          if (book.fileHash.isEmpty || book.fileHash == hash) {
            return;
          }
          final RelinkMismatch mismatch = RelinkMismatch(
            book: book,
            fileName: file.name,
            pagesNow: pageCount,
          );
          final bool agreed = onMismatch != null && await onMismatch(mismatch);
          if (!agreed) {
            throw RelinkRefused(mismatch);
          }
        },
      );
    } on Object {
      // Принятое отпускается — но не тогда, когда это и есть прежний
      // источник книги: файл выбрали тот же, и отпустить его значило бы
      // отнять у книги то, что у неё было. И не тогда, когда он
      // принадлежит другой книге на полке (BUG-45): книгу по ошибке
      // привязывали к чужому файлу.
      if (previous != source) {
        await _releaseUnused(source);
      }
      rethrow;
    }
    // Прежний источник отпускается, если он больше ничей: у двух книг
    // мог быть один файл (BUG-45).
    if (previous != source) {
      await _releaseUnused(previous);
    }
    return relinked;
  }

  /// Разбирает книгу и кладёт её на полку.
  ///
  /// [known] — книга, к которой файл привязывается принудительно; если
  /// его нет, книга ищется по отпечатку.
  ///
  /// [categoryId] назначается только **новой** книге. Уже стоящую на
  /// полке импорт не переставляет: читатель мог унести её в другую
  /// категорию руками, и повторный выбор того же файла — не повод
  /// отменять это решение.
  ///
  /// [check] зовётся, когда файл уже прочитан, а в базу ещё ничего не
  /// записано: бросив ошибку, он отменяет запись (BUG-19).
  ///
  /// [releaseReplaced] — отпустить прежний источник книги, если она уже
  /// стояла на полке и переехала на новый (BUG-17): ту же книгу выбрали
  /// из другого места. Перепривязка отпускает прежний источник сама.
  Future<Book> _save(
    BookSource source,
    String title,
    Book? known, {
    String? categoryId,
    Future<String?> Function()? categoryFor,
    Future<void> Function(String hash, int pageCount)? check,
    bool releaseReplaced = false,
  }) async {
    final BookHandle handle = await _storage.open(source);
    final String hash;
    final int size;
    try {
      hash = await _fingerprint(handle);
      size = handle.length;
    } finally {
      await handle.close();
    }

    final Book? existing = known ?? await _library.bookByHash(hash);

    final ReaderDocument document = await _opener.open(source);
    final int pageCount;
    final bool? textLayer;
    try {
      pageCount = document.pageCount;
      textLayer = await hasTextLayer(document);
    } finally {
      await document.close();
    }
    await check?.call(hash, pageCount);

    // Категория новой книги. Названная по требованию спрашивается
    // здесь: файл уже прочитан и открылся, дальше только запись.
    final String? place = existing != null || categoryFor == null
        ? categoryId
        : await categoryFor();

    final DateTime moment = _now();
    final Book book = existing == null
        ? Book(
            id: _newId(),
            title: title,
            source: source,
            fileSize: size,
            fileHash: hash,
            addedAt: moment,
            pageCount: pageCount,
            hasTextLayer: textLayer,
            openedAt: moment,
            categoryId: place,
            // BUG-20: новая книга встаёт за последней книгой своей
            // категории, а не на место 0.
            shelfPosition: shelfPlaceAfterLast(await _library.books(), place),
          )
        : existing.copyWith(
            source: source,
            fileSize: size,
            fileHash: hash,
            pageCount: pageCount,
            hasTextLayer: textLayer,
            openedAt: moment,
          );
    await _library.save(book);
    // BUG-17: книга переехала на новый источник — прежний отпускается,
    // если он больше ничей. Иначе копились бы копии-сироты и
    // закреплённые ссылки, которых у приложения ограниченное число.
    if (releaseReplaced && existing != null && existing.source != source) {
      await _releaseUnused(existing.source);
    }
    return book;
  }
}
