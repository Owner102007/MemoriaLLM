import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/cover_service.dart';
import 'package:memoria/application/library/device_library.dart';
import 'package:memoria/domain/library/archive_scan.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/domain/reading/full_screen.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/domain/reading/volume_keys.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/session.dart';

import 'fake_reading.dart';

/// Службы приложения для widget-тестов: ни диска, ни PDFium, ни плагинов.
///
/// Обложки здесь намеренно **не рисуются**: у службы обложек свой
/// открыватель, и он всегда отказывает. Причина не в лени, а в правиле,
/// выросшем из S5.1: в widget-тесте не должно быть настоящего файлового
/// ввода-вывода — время там подменено, и `Image.file` по несуществующему
/// пути превратил бы `pumpAndSettle` в ожидание до таймаута. Полка при
/// этом проверяется в том виде, в каком читатель видит её первые
/// мгновения после запуска: с заглушками вместо картинок.
///
/// [opener] подменяет открывателя книги для чтения — когда тесту надо
/// решать самому, откроется ли книга и когда. Обложек и обхода устройства
/// это не касается.
///
/// [scanRunner] подменяет сам обход устройства — когда тесту надо решать,
/// когда он кончится и чем: дойдёт до конца, оборвётся или будет идти,
/// пока его не остановят. Без него обход «находит» [onDevice].
///
/// [archiveSearch] так же подменяет поиск архивов с книгами
/// (SNO-F-LIT-03); без него поиск «находит» [archives].
///
/// [recording] — сессия записи (SNO-F-REC-01); без неё записи в
/// приложении нет, как в основной сборке. [records] — записи на
/// устройстве (SNO-F-REC-07); без них нет ни списка, ни архива.
AppServices testServices({
  required AppData data,
  ReaderDocument? document,
  DocumentOpener? opener,
  PickedFile? picked,
  List<PickedFile>? batch,
  BookStorage? storage,
  MemoryCoverStore? coverStore,
  StorageAccess? access,
  VolumeKeys volumeKeys = const NoVolumeKeys(),
  FullScreenWindow window = const NoFullScreenWindow(),
  List<ScannedFile> onDevice = const <ScannedFile>[],
  ScanRunner? scanRunner,
  List<FoundArchive> archives = const <FoundArchive>[],
  ArchiveSearch? archiveSearch,
  RecordingSession? recording,
  DeviceRecords? records,
}) {
  final ReaderDocument doc =
      document ?? FakeReaderDocument(pages: <String>['текст']);
  final MemoryCoverStore covers = coverStore ?? MemoryCoverStore();
  final BookStorage books = storage ?? MemoryBookStorage();
  final StorageAccess grant = access ?? FakeStorageAccess();
  return AppServices(
    data: data,
    opener: opener ?? FakeDocumentOpener(doc),
    picker: FakeBookFilePicker(picked, batch: batch),
    storage: books,
    coverStore: covers,
    access: grant,
    volumeKeys: volumeKeys,
    window: window,
    // Изолята здесь нет по той же причине, что и у обхода книг ниже.
    archiveSearch: archiveSearch ?? fakeArchiveSearch(archives),
    recording: recording,
    records: records,
    covers: CoverService(
      opener: FakeDocumentOpener(
        doc,
        failure: const DocumentOpenException(
          DocumentProblem.missing,
          FilePathSource('/covers/none.pdf'),
        ),
      ),
      store: covers,
      library: data.library,
    ),
    deviceLibrary: DeviceLibrary(
      files: data.deviceFiles,
      access: grant,
      // У каждого файла своё содержимое, выведенное из пути: иначе все
      // книги получили бы один отпечаток и склеились в одну карточку —
      // ровно то поведение, которое здесь и проверяется.
      storage: const PathBytesStorage(),
      opener: FakeDocumentOpener(doc),
      // Обход в widget-тесте не ходит на диск вовсе: изолят с подменённым
      // временем `flutter test` не дожидается, а проверять здесь надо
      // экран, а не файловую систему. Настоящий обход проверяется
      // отдельно, на дереве во временной папке.
      runner: scanRunner ?? (List<String> roots) => fakeScan(onDevice),
    ),
  );
}

/// Хранилище, где содержимое книги выведено из её пути.
///
/// Нужно там, где важен отпечаток: настоящий считается по содержимому, и
/// две «книги» с одинаковыми байтами — это честный дубликат, а не ошибка
/// теста.
class PathBytesStorage implements BookStorage {
  /// Создаёт хранилище.
  const PathBytesStorage();

  @override
  Future<BookSource> adopt(PickedFile file) async =>
      FilePathSource(file.path ?? file.name);

  @override
  Future<BookHandle> open(BookSource source) async {
    final String key = source is FilePathSource ? source.path : '$source';
    return MemoryBookHandle(<int>[...'%PDF-1.7 '.codeUnits, ...key.codeUnits]);
  }

  @override
  Future<bool> available(BookSource source) async => true;

  @override
  Future<void> release(BookSource source) async {}
}

/// Обход, который «нашёл» заранее заданные файлы.
Stream<ScanEvent> fakeScan(List<ScannedFile> files) async* {
  for (final ScannedFile file in files) {
    yield ScanEvent(file: file, directory: '', visited: 0);
  }
  yield ScanEvent(directory: 'готово', visited: files.length);
}

/// Поиск архивов, который «нашёл» заранее заданные (SNO-F-LIT-03).
ArchiveSearch fakeArchiveSearch(List<FoundArchive> archives) {
  return (List<String> roots) => Stream<FoundArchive>.fromIterable(archives);
}

/// Разрешение на доступ к файлам, которым распоряжается тест.
class FakeStorageAccess implements StorageAccess {
  /// Создаёт заглушку.
  FakeStorageAccess({
    this.current = StorageAccessState.granted,
    this.paths = const <String>['/device'],
  });

  /// Текущее состояние.
  StorageAccessState current;

  /// Корни обхода.
  List<String> paths;

  /// Сколько раз спрашивали разрешение.
  int requests = 0;

  @override
  Future<StorageAccessState> state() async => current;

  @override
  Future<void> request() async {
    requests++;
  }

  @override
  Future<List<String>> roots() async =>
      current.allowsScan ? paths : const <String>[];
}

/// Кнопки громкости, которые нажимает тест (F-READ-26).
///
/// Запоминает всё, что экран говорил платформе о перехвате, и отдаёт
/// получателю события так же, как это делает `MainActivity`.
class FakeVolumeKeys implements VolumeKeys {
  VolumeKeyHandler? _handler;

  /// Что экран говорил о перехвате, по порядку.
  final List<bool> switches = <bool>[];

  /// Перехватываются ли кнопки сейчас.
  bool get active => switches.isNotEmpty && switches.last;

  /// Подключён ли получатель.
  bool get attached => _handler != null;

  @override
  void attach(VolumeKeyHandler handler) => _handler = handler;

  @override
  void detach(VolumeKeyHandler handler) {
    if (_handler == handler) {
      _handler = null;
      switches.add(false);
    }
  }

  @override
  Future<void> setActive(bool active) async => switches.add(active);

  /// Событие кнопки; `null` — получателя нет.
  VolumeKeyOutcome? send(VolumeKeyEvent event) => _handler?.call(event);

  /// Короткое нажатие: нажали и отпустили. Возвращает ответ на отпускание.
  VolumeKeyOutcome? click(VolumeKey key) {
    send(VolumeKeyEvent(key: key, pressed: true));
    return send(VolumeKeyEvent(key: key, pressed: false));
  }
}

/// Окно, которое разворачивает тест (F-READ-35).
///
/// Запоминает всё, о чём экран просил платформу, и отвечает так, как
/// велено: [works] — развернулось ли окно в самом деле.
class FakeFullScreenWindow implements FullScreenWindow {
  /// Создаёт заглушку.
  FakeFullScreenWindow({this.works = true});

  /// Слушается ли окно: `false` — платформа отказывает.
  bool works;

  /// О чём экран просил платформу, по порядку.
  final List<bool> requests = <bool>[];

  /// Развёрнуто ли окно сейчас.
  bool full = false;

  @override
  bool get available => true;

  @override
  Future<bool> setFullScreen(bool on) async {
    requests.add(on);
    if (works) {
      full = on;
    }
    return works;
  }
}
