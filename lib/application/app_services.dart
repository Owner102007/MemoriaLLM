import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/library/archive_scan.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/library/book_storage.dart';
import '../domain/library/cover.dart';
import '../domain/library/storage_access.dart';
import '../domain/reading/full_screen.dart';
import '../domain/reading/reader_document.dart';
import '../domain/reading/volume_keys.dart';
import '../infrastructure/files/android_book_storage.dart';
import '../infrastructure/files/app_directory.dart';
import '../infrastructure/files/archive_scanner.dart';
import '../infrastructure/files/book_copy.dart';
import '../infrastructure/files/cover_cache.dart';
import '../infrastructure/files/fast_book_picker.dart';
import '../infrastructure/files/local_book_storage.dart';
import '../infrastructure/files/platform_storage_access.dart';
import '../infrastructure/pdf/pdfrx_document.dart';
import '../infrastructure/platform/android_volume_keys.dart';
import '../infrastructure/platform/windows_full_screen.dart';
import '../sno/flags.dart';
import '../sno/index/shelf_reading.dart';
import '../sno/participant_code.dart';
import '../sno/recording/device_passport.dart';
import '../sno/recording/device_status.dart';
import '../sno/recording/file_records.dart';
import '../sno/recording/file_store.dart';
import '../sno/recording/record_outlet.dart';
import '../sno/recording/recording_guard.dart';
import '../sno/recording/records.dart';
import '../sno/recording/session.dart';
import '../sno/reference_state.dart';
import '../sno/settings_keys.dart';
import 'build_info.dart';
import 'data/app_data.dart';
import 'library/cover_service.dart';
import 'library/device_library.dart';
import 'map/map_builder.dart';
import 'reading/book_times.dart';

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
    this.archiveSearch = noArchiveSearch,
    this.recording,
    this.records,
    this.shelfReading,
    this.bookTimes,
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
    //
    // В сборке ветви СНО2026 книга копируется в папку приложения
    // (SNO-DIV-03): флаг — константа сборки, и в основном приложении
    // хранилища те же, что были.
    final BookStorage storage = Platform.isAndroid
        ? AndroidBookStorage(alwaysCopy: Sno.literature)
        : const LocalBookStorage(
            copyInto: Sno.literature ? applicationBooks : null,
          );
    // SNO-F-REC-01: запись сессии — только в сборке ветви. Условие —
    // константа сборки: в основном приложении записи нет вовсе.
    final RecordingSession? recording = Sno.recording
        ? _recordingFor(data, storage)
        : null;
    final DocumentOpener opener = PdfrxDocumentOpener(storage: storage);
    return AppServices(
      data: data,
      storage: storage,
      opener: opener,
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
      // SNO-F-LIT-03: архивы с литературой ищет только сборка ветви.
      // Условие — константа сборки: в основное приложение обход
      // архивов не попадает.
      archiveSearch: Sno.literature ? findArchivesInIsolate : noArchiveSearch,
      recording: recording,
      // SNO-F-REC-05: архивы записей — там же, где запись. Условие
      // начинается с константы сборки: в основное приложение код
      // архивов не попадает.
      records: Sno.recording && recording != null
          ? _recordsFor(recording)
          : null,
      // SNO-F-IDX-04: текст всех книг и карта заранее — только в ветви
      // II. Условие — константа сборки: в основное приложение и в
      // ветвь I проход по полке не попадает.
      shelfReading: Sno.galaxy
          ? _shelfReadingFor(data, opener, recording)
          : null,
      // SNO-F-MAP-01: время в книгах считается там, где есть карта, на
      // которой оно видно, — в ветви II. Условие — константа сборки.
      bookTimes: Sno.galaxy
          ? BookTimes(settings: data.settings, key: SnoSettingsKeys.bookTimes)
          : null,
    );
  }

  /// Подготовка книг полки сборки ветви II (SNO-F-IDX-04): текст всех
  /// книг в кэш текста страниц и карта по нему.
  static ShelfReading _shelfReadingFor(
    AppData data,
    DocumentOpener opener,
    RecordingSession? recording,
  ) {
    return ShelfReading(
      library: data.library,
      opener: opener,
      texts: data.pageTexts,
      settings: data.settings,
      map: MapBuilder(
        library: data.library,
        categories: data.categories,
        texts: data.pageTexts,
        store: data.bookMap,
      ),
      device: const PlatformDeviceStatus(),
      // Пока идёт запись, экран держит она: подготовка его не трогает.
      screenBusy: () => recording?.recording ?? false,
    );
  }

  /// Папка `Записи/` в папке данных приложения.
  static Future<Directory> _recordsFolder() async {
    final Directory root = await appDataDirectory();
    return Directory(p.join(root.path, FileRecordingStore.folderName));
  }

  /// Записи на устройстве сборки ветви СНО2026 (SNO-F-REC-07): архивы
  /// в той же папке `Записи/`, куда сессия кладёт папки записей.
  static DeviceRecords _recordsFor(RecordingSession recording) {
    return FileDeviceRecords(
      root: _recordsFolder,
      outlet: platformRecordOutlet(),
      // Папку незавершённой сессии не подбирают и не упаковывают.
      activeFolder: () => recording.state?.folder,
      // Отметка о сессии не прочиталась — папок не трогают вовсе.
      sessionKnown: () => recording.known,
    );
  }

  /// Сессия записи сборки ветви СНО2026 (SNO-F-REC-01).
  ///
  /// Записи лежат в папке данных приложения, в `Записи/`; снимок
  /// начала записи строится тем же кодом, что эталон.
  static RecordingSession _recordingFor(AppData data, BookStorage storage) {
    final String nodeId = data.clock.nodeId;
    final ReferenceKeeper keeper = ReferenceKeeper(
      data: data,
      storage: storage,
    );
    return RecordingSession(
      settings: data.settings,
      store: FileRecordingStore(_recordsFolder),
      nodeId: nodeId,
      snapshot: keeper.recordingSnapshot,
      endSnapshot: keeper.recordingEndSnapshot,
      branch: Sno.branch,
      device: deviceCodeOf(nodeId),
      build: <String, Object?>{
        'version': appVersion,
        'commit': appCommit,
        'flags': Sno.flags.enabledNames,
      },
      status: const PlatformDeviceStatus(),
      // SNO-F-REC-13: служба переднего плана есть только у телефона —
      // свёрнутое окно на ПК никто не выгружает.
      guard: Platform.isAndroid
          ? const AndroidRecordingGuard()
          : const NoRecordingGuard(),
      passport: platformPassport,
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

  /// Поиск архивов с книгами на устройстве (SNO-F-LIT-03): им
  /// пользуется раздел «Тестирование» сборок ветвей СНО2026. В основном
  /// приложении он ничего не ищет.
  final ArchiveSearch archiveSearch;

  /// Сессия записи (SNO-F-REC-01); `null` — в этой сборке записи нет:
  /// основное приложение и тесты, которым она не нужна.
  final RecordingSession? recording;

  /// Записи на устройстве — архивы завершённых сессий (SNO-F-REC-07);
  /// `null` — записей в этой сборке нет.
  final DeviceRecords? records;

  /// Подготовка книг полки — текст всех книг и карта (SNO-F-IDX-04);
  /// `null` — в этой сборке её нет: основное приложение, ветвь I и
  /// тесты, которым она не нужна.
  final ShelfReading? shelfReading;

  /// Время, проведённое в каждой книге (SNO-F-MAP-01): по нему у звезды
  /// на карте размер; `null` — в этой сборке его не считают.
  final BookTimes? bookTimes;
}
