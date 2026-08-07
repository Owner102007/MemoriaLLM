import 'package:file_selector/file_selector.dart';

import '../../domain/library/book_file_picker.dart';

/// Системный диалог выбора файла: SAF на Android, обычный диалог
/// открытия на Windows.
///
/// Пакет `file_selector` выбран вместо более популярных именно потому,
/// что он от команды Flutter и не тянет за собой сервисы Google: без них
/// проект должен собираться и работать (условие F-Droid).
class FileSelectorBookPicker implements BookFilePicker {
  /// Создаёт пикер.
  const FileSelectorBookPicker();

  @override
  Future<PickedFile?> pickPdf() async {
    // Расширение понимают Windows и Linux, MIME-тип — Android. Указаны
    // оба: на платформе, которая не понимает свой вариант фильтра,
    // `file_selector` бросает ArgumentError.
    const XTypeGroup pdf = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
      mimeTypes: <String>['application/pdf'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[pdf],
    );
    if (file == null) {
      return null;
    }
    return PickedFile(path: file.path, name: file.name);
  }
}
