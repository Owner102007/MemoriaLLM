/// Сведения о сборке, зашитые при компиляции.
///
/// Нужны не из любви к номерам версий, а для проверок на живых
/// устройствах: без них отчёт «не работает» невозможно связать
/// с конкретной сборкой, а сборок у открытого проекта много — релизы
/// этапов, катящийся `latest`, локальные эксперименты.
library;

/// Версия приложения из `pubspec.yaml`. Подставляется в CI.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'dev',
);

/// Коммит, из которого собрано. Подставляется в CI.
const String appCommit = String.fromEnvironment(
  'APP_COMMIT',
  defaultValue: 'local',
);

/// Короткая строка для экрана настроек: `0.2.0-alpha · a1b2c3d`.
String get buildLabel {
  final String commit =
      appCommit.length > 7 ? appCommit.substring(0, 7) : appCommit;
  return '$appVersion · $commit';
}
