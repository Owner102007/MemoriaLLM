import '../domain/library/book_file_picker.dart';
import '../domain/reading/reader_document.dart';
import '../infrastructure/files/file_selector_picker.dart';
import '../infrastructure/pdf/pdfrx_document.dart';
import 'data/app_data.dart';

/// Всё, чем приложение пользуется извне, собранное в одном месте.
///
/// Экраны получают этот объект и не знают, что за ним стоит: настоящий
/// PDFium и системный диалог выбора файла — или заглушки из теста.
/// Благодаря этому widget-тесты экранов не требуют ни PDF-движка, ни
/// платформенных плагинов.
class AppServices {
  /// Создаёт набор служб.
  const AppServices({
    required this.data,
    required this.opener,
    required this.picker,
  });

  /// Настоящие службы для запущенного приложения.
  factory AppServices.production(AppData data) {
    return AppServices(
      data: data,
      opener: PdfrxDocumentOpener(),
      picker: const FileSelectorBookPicker(),
    );
  }

  /// Слой данных.
  final AppData data;

  /// Открыватель PDF.
  final DocumentOpener opener;

  /// Диалог выбора файла.
  final BookFilePicker picker;
}
