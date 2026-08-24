import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/library/cover_service.dart';
import 'package:memoria/domain/library/book_file_picker.dart';
import 'package:memoria/domain/library/book_source.dart';
import 'package:memoria/domain/library/book_storage.dart';
import 'package:memoria/domain/reading/reader_document.dart';

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
}) {
  final ReaderDocument doc =
      document ?? FakeReaderDocument(pages: <String>['текст']);
  final MemoryCoverStore covers = coverStore ?? MemoryCoverStore();
  return AppServices(
    data: data,
    opener: FakeDocumentOpener(doc),
    picker: FakeBookFilePicker(picked, batch: batch),
    storage: storage ?? MemoryBookStorage(),
    coverStore: covers,
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
  );
}
