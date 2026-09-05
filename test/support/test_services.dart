import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/cover_service.dart';
import 'package:memoria/application/library/device_library.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/library/device_scan.dart';
import 'package:memoria/domain/library/storage_access.dart';
import 'package:memoria/domain/reading/reader_document.dart';
import 'package:memoria/infrastructure/files/device_scanner.dart';

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
AppServices testServices({
  required AppData data,
  ReaderDocument? document,
  PickedFile? picked,
  List<PickedFile>? batch,
  BookStorage? storage,
  MemoryCoverStore? coverStore,
  StorageAccess? access,
  List<ScannedFile> onDevice = const <ScannedFile>[],
}) {
  final ReaderDocument doc =
      document ?? FakeReaderDocument(pages: <String>['текст']);
  final MemoryCoverStore covers = coverStore ?? MemoryCoverStore();
  final BookStorage books = storage ?? MemoryBookStorage();
  final StorageAccess grant = access ?? FakeStorageAccess();
  return AppServices(
    data: data,
    opener: FakeDocumentOpener(doc),
    picker: FakeBookFilePicker(picked, batch: batch),
    storage: books,
    coverStore: covers,
    access: grant,
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
      storage: PathBytesStorage(),
      opener: FakeDocumentOpener(doc),
      // Обход в widget-тесте не ходит на диск вовсе: изолят с подменённым
      // временем `flutter test` не дожидается, а проверять здесь надо
      // экран, а не файловую систему. Настоящий обход проверяется
      // отдельно, на дереве во временной папке.
      runner: (List<String> roots) => fakeScan(onDevice),
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
