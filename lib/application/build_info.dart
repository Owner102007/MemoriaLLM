/// Сведения о сборке, зашитые при компиляции.
///
/// Нужны не из любви к номерам версий, а для проверок на живых
/// устройствах: без них отчёт «не работает» невозможно связать
/// с конкретной сборкой, а сборок у открытого проекта много — релизы
/// этапов, катящийся `latest`, локальные эксперименты.
library;

import '../sno/flags.dart';

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
///
/// У сборки ветви (SNO-F-CFG-01) — с ветвью и её флагами:
/// `ветвь I · 0.18.0-sno2026.I · a1b2c3d · флаги: запись, литература`.
String get buildLabel {
  return buildLabelFor(
    version: appVersion,
    commit: appCommit,
    flags: Sno.flags,
  );
}

/// Строка сборки из её частей.
///
/// Отдельной функцией — чтобы строку всех трёх сборок проверял один
/// прогон тестов: сами флаги сборки — константы, и в прогоне они одни.
String buildLabelFor({
  required String version,
  required String commit,
  required BranchFlags flags,
}) {
  final String short = commit.length > 7 ? commit.substring(0, 7) : commit;
  final String base = '$version · $short';
  if (!flags.enabled) {
    return base;
  }
  return 'ветвь ${flags.branch} · $base · '
      'флаги: ${flags.enabledNames.join(', ')}';
}
