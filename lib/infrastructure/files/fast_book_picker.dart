import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;

import '../../domain/library/book_file_picker.dart';

/// Системный диалог выбора файла, который файл не читает.
///
/// Прежний пикер (`file_selector`) на Android вычитывал выбранный файл
/// **целиком в память**, а потом писал копию в кэш: на книге в 73 МБ он
/// растил буфер до 146 МБ, держал оба разом и упирался в потолок кучи.
/// Приложение падало с `OutOfMemoryError` ещё до того, как файл доходил
/// до нашего кода. Это известная ошибка самого пакета
/// (flutter/flutter#141002, заведена в январе 2024 и открыта до сих пор),
/// поэтому чинился не разбор ошибки, а способ приёма файла.
///
/// `fast_file_picker` сделан поверх того же `file_selector`, но, по
/// прямой формулировке автора, «never performs any file copying or
/// conversion»: на Android он отдаёт имя и ссылку, на Windows — имя и
/// путь. Падение исчезает у источника, на файлах любого размера.
class FastBookPicker implements BookFilePicker {
  /// Создаёт пикер.
  const FastBookPicker();

  @override
  Future<PickedFile?> pickPdf() async {
    // Расширение понимают Windows и Linux, MIME-тип — Android. Указаны
    // оба: на платформе, которая не понимает свой вариант фильтра,
    // диалог бросает ArgumentError.
    const XTypeGroup pdf = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
      mimeTypes: <String>['application/pdf'],
    );
    final FastFilePickerPath? file = await FastFilePicker.pickFile(
      acceptedTypeGroups: const <XTypeGroup>[pdf],
    );
    if (file == null) {
      return null;
    }
    return PickedFile(name: file.name, path: file.path, uri: file.uri);
  }
}
