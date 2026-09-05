import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/annotations/annotations.dart';
import '../../domain/library/book.dart';
import '../../domain/library/book_category.dart';
import '../../domain/library/device_files.dart';
import '../../domain/llm/llm_query.dart';
import '../../domain/prompts/selection_prompt.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/sync/hlc.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/connection.dart';
import '../../infrastructure/database/search_index.dart';
import '../../infrastructure/repositories/drift_annotation_repository.dart';
import '../../infrastructure/repositories/drift_app_settings_repository.dart';
import '../../infrastructure/repositories/drift_category_repository.dart';
import '../../infrastructure/repositories/drift_device_file_repository.dart';
import '../../infrastructure/repositories/drift_library_repository.dart';
import '../../infrastructure/repositories/drift_llm_history_repository.dart';
import '../../infrastructure/repositories/drift_prompt_repository.dart';
import '../../infrastructure/repositories/drift_reading_repository.dart';

/// Слой данных приложения, собранный целиком.
///
/// Единственное место, где известно, что за репозиториями стоит drift.
/// Тесты подсовывают сюда базу в памяти и работают с теми же
/// репозиториями, что и приложение.
class AppData {
  AppData._({
    required this.database,
    required this.clock,
    required this.settings,
    required this.library,
    required this.categories,
    required this.reading,
    required this.annotations,
    required this.llmHistory,
    required this.prompts,
    required this.deviceFiles,
    required this.searchIndexed,
  });

  /// Открывает базу и собирает репозитории.
  ///
  /// [executor] задаётся в тестах; приложение открывает файл на диске.
  static Future<AppData> open({QueryExecutor? executor}) async {
    final AppDatabase database = AppDatabase(executor ?? openDatabaseFile());
    final AppSettingsRepository settings = DriftAppSettingsRepository(database);
    final HlcClock clock = await restoreClock(settings);
    final LibraryRepository library = DriftLibraryRepository(database, clock);
    // FTS5 — необязательный модуль SQLite, и спрашивать о нём базу на
    // каждый запрос незачем: ответ на всю жизнь подключения один.
    final bool indexed = await hasSearchIndex(database);
    final PromptRepository prompts = DriftPromptRepository(
      database,
      clock,
      settings,
    );
    // Промпты из коробки заводятся здесь, а не миграцией: это обычные
    // записи, и заводятся они теми же средствами, какими читатель заведёт
    // свои. Ровно один раз за жизнь базы — отметка в настройках.
    await prompts.seedDefaultsOnce();
    return AppData._(
      database: database,
      clock: clock,
      settings: settings,
      library: library,
      categories: DriftCategoryRepository(database, clock, library),
      reading: DriftReadingRepository(database, clock),
      annotations: DriftAnnotationRepository(database, clock),
      llmHistory: DriftLlmHistoryRepository(database, clock),
      prompts: prompts,
      deviceFiles: DriftDeviceFileRepository(database, indexed: indexed),
      searchIndexed: indexed,
    );
  }

  /// База данных.
  final AppDatabase database;

  /// Часы этого устройства.
  final HlcClock clock;

  /// Локальные настройки приложения.
  final AppSettingsRepository settings;

  /// Библиотека книг.
  final LibraryRepository library;

  /// Категории полки.
  final CategoryRepository categories;

  /// Прогресс и настройки чтения.
  final ReadingRepository reading;

  /// Цитаты, заметки и закладки.
  final AnnotationRepository annotations;

  /// История запросов к модели.
  final LlmHistoryRepository llmHistory;

  /// Промпты к выделению. Синхронизируются наравне с цитатами.
  final PromptRepository prompts;

  /// Файлы устройства и индекс поиска по ним. Не синхронизируется.
  final DeviceFileRepository deviceFiles;

  /// Есть ли в этой базе рабочий FTS5.
  ///
  /// Читателю об этом знать незачем, а экрану поиска — да: без индекса
  /// он честно ищет по именам файлов и не обещает большего.
  final bool searchIndexed;

  /// Закрывает базу.
  Future<void> close() => database.close();
}

/// Поднимает часы устройства из локальных настроек.
///
/// Идентификатор узла рождается один раз на устройство. Последняя метка
/// сохраняется, чтобы после перезапуска часы не пошли назад: системное
/// время могло быть переведено, а метки обязаны только расти.
Future<HlcClock> restoreClock(AppSettingsRepository settings) async {
  final String storedNode = await settings.read(SettingsKeys.nodeId) ?? '';
  final String nodeId = storedNode.isEmpty ? generateNodeId() : storedNode;
  if (storedNode.isEmpty) {
    await settings.write(SettingsKeys.nodeId, nodeId);
  }
  final String? storedLast = await settings.read(SettingsKeys.lastHlc);
  return HlcClock(
    nodeId: nodeId,
    last: _parseLast(storedLast, nodeId),
    onIssued: (Hlc stamp) {
      unawaited(settings.write(SettingsKeys.lastHlc, stamp.toString()));
    },
  );
}

Hlc? _parseLast(String? stored, String nodeId) {
  if (stored == null || stored.isEmpty) {
    return null;
  }
  try {
    final Hlc parsed = Hlc.parse(stored);
    return Hlc(parsed.millis, parsed.counter, nodeId);
  } on FormatException {
    // Испорченная метка — не повод не дать человеку открыть книгу.
    return null;
  }
}
