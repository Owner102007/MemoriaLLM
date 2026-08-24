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

  /// Фильтр диалога.
  ///
  /// Расширение понимают Windows и Linux, MIME-тип — Android. Указаны
  /// оба: на платформе, которая не понимает свой вариант фильтра, диалог
  /// бросает `ArgumentError`.
  static const XTypeGroup _pdf = XTypeGroup(
    label: 'PDF',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
  );

  @override
  Future<PickedFile?> pickPdf() async {
    final FastFilePickerPath? file = await FastFilePicker.pickFile(
      acceptedTypeGroups: const <XTypeGroup>[_pdf],
    );
    return file == null ? null : _toPicked(file);
  }

  @override
  Future<List<PickedFile>> pickPdfs() async {
    final List<FastFilePickerPath>? files =
        await FastFilePicker.pickMultipleFiles(
          acceptedTypeGroups: const <XTypeGroup>[_pdf],
        );
    if (files == null) {
      return const <PickedFile>[];
    }
    return <PickedFile>[
      for (final FastFilePickerPath file in files) _toPicked(file),
    ];
  }

  PickedFile _toPicked(FastFilePickerPath file) =>
      PickedFile(name: file.name, path: file.path, uri: file.uri);
}
