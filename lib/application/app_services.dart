import 'dart:io';

import '../domain/library/book_file_picker.dart';
import '../domain/library/book_storage.dart';
import '../domain/library/cover.dart';
import '../domain/library/storage_access.dart';
import '../domain/reading/full_screen.dart';
import '../domain/reading/reader_document.dart';
import '../domain/reading/volume_keys.dart';
import '../infrastructure/files/android_book_storage.dart';
import '../infrastructure/files/cover_cache.dart';
import '../infrastructure/files/fast_book_picker.dart';
import '../infrastructure/files/local_book_storage.dart';
import '../infrastructure/files/platform_storage_access.dart';
import '../infrastructure/pdf/pdfrx_document.dart';
import '../infrastructure/platform/android_volume_keys.dart';
import '../infrastructure/platform/windows_full_screen.dart';
import 'data/app_data.dart';
import 'library/cover_service.dart';
import 'library/device_library.dart';

/// Всё, чем приложение пользуется извне, собранное в одном месте.
///
/// Экраны получают этот объект и не знают, что за ним стоит: настоящий
/// PDFium, системный диалог выбора файла и Storage Access Framework — или
/// заглушки из теста. Благодаря этому widget-тесты экранов не требуют ни
/// PDF-движка, ни платформенных плагинов.
class AppServices {
  /// Создаёт набор служб.
  AppServices({
    required this.data,
    required this.opener,
    required this.picker,
    required this.storage,
    required this.coverStore,
    required this.access,
    this.volumeKeys = const NoVolumeKeys(),
    this.window = const NoFullScreenWindow(),
    CoverService? covers,
    DeviceLibrary? deviceLibrary,
  }) : covers =
           covers ??
           CoverService(
             opener: opener,
             store: coverStore,
             library: data.library,
           ),
       deviceLibrary =
           deviceLibrary ??
           DeviceLibrary(
             files: data.deviceFiles,
             access: access,
             storage: storage,
             opener: opener,
           );

  /// Настоящие службы для запущенного приложения.
  factory AppServices.production(AppData data) {
    // Единственное место, где расходятся платформы. На Windows у книги
    // есть настоящий путь и посредники не нужны; на Android пути нет
    // вовсе, и книга читается по закреплённой ссылке.
    final BookStorage storage = Platform.isAndroid
        ? AndroidBookStorage()
        : const LocalBookStorage();
    return AppServices(
      data: data,
      storage: storage,
      opener: PdfrxDocumentOpener(storage: storage),
      picker: const FastBookPicker(),
      coverStore: FileCoverStore(),
      access: platformStorageAccess(),
      // Кнопки громкости есть только у телефона; на ПК ту же роль
      // играют клавиши, и их Flutter видит сам.
      volumeKeys: Platform.isAndroid
          ? AndroidVolumeKeys()
          : const NoVolumeKeys(),
      // Окно есть только у ПК; на телефоне страница и так во весь экран.
      window: Platform.isWindows
          ? WindowsFullScreen()
          : const NoFullScreenWindow(),
    );
  }

  /// Слой данных.
  final AppData data;

  /// Открыватель PDF.
  final DocumentOpener opener;

  /// Диалог выбора файла.
  final BookFilePicker picker;

  /// Хранилище книг: приём файла и доступ к его байтам.
  final BookStorage storage;

  /// Кэш обложек на диске.
  final CoverStore coverStore;

  /// Рисование обложек: очередь, кэш и упаковка в PNG.
  final CoverService covers;

  /// Разрешение на доступ ко всем файлам устройства.
  final StorageAccess access;

  /// Книги, лежащие на устройстве: обход, разборка и поиск.
  final DeviceLibrary deviceLibrary;

  /// Кнопки громкости: ими листают на телефоне (F-READ-26).
  final VolumeKeys volumeKeys;

  /// Окно приложения: на ПК чтение разворачивается во весь экран
  /// (F-READ-35).
  final FullScreenWindow window;
}
