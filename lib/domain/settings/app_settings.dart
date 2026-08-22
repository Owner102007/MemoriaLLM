/// Ключи локальных настроек приложения.
///
/// Значения ключей менять нельзя без миграции: они лежат в базе на
/// устройствах пользователей.
abstract final class SettingsKeys {
  /// Выбранная тема оформления.
  static const String theme = 'ui.theme';

  /// Положение экрана при чтении: `portrait` или `landscape`.
  ///
  /// Настройка устройства, а не книги: деление страницы на полосы
  /// увеличивает текст только на широком экране, и приложение
  /// поворачивается само, не полагаясь на автоповорот системы — тот у
  /// многих выключен насовсем.
  static const String readingRotation = 'ui.reading_rotation';

  /// Как листается книга: `continuous` или `paged`.
  static const String pageFlow = 'ui.page_flow';

  /// Заперт ли масштаб страницы: `true`/`false`.
  ///
  /// Заперт — щипок и перетаскивание выключены, страница стоит там, где
  /// её положила раскладка. Отперт — страница двигается и масштабируется
  /// как в обычном просмотрщике и остаётся в этом состоянии.
  static const String zoomLock = 'ui.zoom_lock';

  /// Идентификатор этого устройства для меток HLC.
  static const String nodeId = 'sync.node_id';

  /// Последняя выданная метка HLC.
  static const String lastHlc = 'sync.last_hlc';

  /// Язык, на который переводим по умолчанию (S8).
  static const String targetLanguage = 'llm.target_language';
}

/// Настройки приложения — простое хранилище «ключ-значение».
///
/// Эти настройки **не синхронизируются**: тема, выбранная для чтения
/// ночью с телефона, не должна перекрашивать ПК, а идентификатор узла
/// вообще обязан быть у каждого устройства свой.
abstract interface class AppSettingsRepository {
  /// Читает значение или `null`, если ключа нет.
  Future<String?> read(String key);

  /// Записывает значение.
  Future<void> write(String key, String value);

  /// Удаляет ключ.
  Future<void> remove(String key);

  /// Живое значение ключа.
  Stream<String?> watch(String key);
}
