import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/annotations/annotations.dart';
import '../../domain/library/book.dart';
import '../../domain/llm/llm_query.dart';
import '../../domain/reading/reading.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/sync/hlc.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/database/connection.dart';
import '../../infrastructure/repositories/drift_annotation_repository.dart';
import '../../infrastructure/repositories/drift_app_settings_repository.dart';
import '../../infrastructure/repositories/drift_library_repository.dart';
import '../../infrastructure/repositories/drift_llm_history_repository.dart';
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
    required this.reading,
    required this.annotations,
    required this.llmHistory,
  });

  /// Открывает базу и собирает репозитории.
  ///
  /// [executor] задаётся в тестах; приложение открывает файл на диске.
  static Future<AppData> open({QueryExecutor? executor}) async {
    final AppDatabase database = AppDatabase(executor ?? openDatabaseFile());
    final AppSettingsRepository settings = DriftAppSettingsRepository(database);
    final HlcClock clock = await restoreClock(settings);
    return AppData._(
      database: database,
      clock: clock,
      settings: settings,
      library: DriftLibraryRepository(database, clock),
      reading: DriftReadingRepository(database, clock),
      annotations: DriftAnnotationRepository(database, clock),
      llmHistory: DriftLlmHistoryRepository(database, clock),
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

  /// Прогресс и настройки чтения.
  final ReadingRepository reading;

  /// Цитаты, заметки и закладки.
  final AnnotationRepository annotations;

  /// История запросов к модели.
  final LlmHistoryRepository llmHistory;

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
