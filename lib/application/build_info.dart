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

/// Тег сборки исследования СНО2026 — `sno2026-1`, `sno2026-1.1`; пусто
/// у любой другой сборки (SNO-F-CFG-06).
///
/// Ставит его CI, только когда собирает по тегу исследования: сборки,
/// на которых записывают участников, выходят с тега и не меняются всё
/// время сбора данных. Сборка из `latest`, из ветки и локальная тега не
/// получают — это проверочные сборки.
const String appStudyTag = String.fromEnvironment('APP_STUDY_TAG');

/// День сборки по UTC, `2026-10-10`; пусто у локальной сборки.
const String appBuilt = String.fromEnvironment('APP_BUILT');

/// Сборка ли это исследования (SNO-F-CFG-06).
bool get isStudyBuild => isStudyTag(appStudyTag);

/// Похоже ли [tag] на тег сборки исследования: `sno2026-N` или
/// `sno2026-N.M`, где N и M — числа без ведущего нуля.
///
/// Строгий разбор, а не «начинается с `sno2026-`»: опечатка в теге не
/// должна дать сборку, которая называет себя сборкой исследования.
bool isStudyTag(String tag) {
  return RegExp(r'^sno2026-[1-9][0-9]*(\.[1-9][0-9]*)?$').hasMatch(tag);
}

/// Строка о том, чья это сборка, — для «О ветви» (SNO-F-CFG-06).
///
/// `Сборка исследования sno2026-1 · собрана 10.10.2026` — или
/// `Проверочная сборка — не для участников · собрана 10.10.2026`. День
/// сборки из `2026-10-10` переписывается по-русски; не разобрался —
/// стоит как есть, а пустой не пишется вовсе.
String studyBuildLine({required String studyTag, required String built}) {
  final String who = isStudyTag(studyTag)
      ? 'Сборка исследования $studyTag'
      : kTrialBuildNote;
  if (built.isEmpty) {
    return who;
  }
  final RegExpMatch? day = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})$',
  ).firstMatch(built);
  final String date = day == null
      ? built
      : '${day.group(3)}.${day.group(2)}.${day.group(1)}';
  return '$who · собрана $date';
}

/// Пометка проверочной сборки — над «Старт записи» и в «О ветви».
const String kTrialBuildNote = 'Проверочная сборка — не для участников';

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
