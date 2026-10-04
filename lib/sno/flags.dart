/// Флаги ветви сборки (SNO-ALG-CFG-01, SNO-F-CFG-01).
///
/// Из одного кода собираются три приложения: основное и две ветви для
/// тестировщиков исследования СНО2026 — «I» (ядро) и «II» (тестовая).
/// Какая ветвь собрана, решает одно значение при сборке:
/// `--dart-define=SNO_BRANCH=I`. Всё остальное из него выводится.
///
/// Здесь только правила: какая ветвь что включает. Виджетов и ввода-
/// вывода нет — таблица проверяется тестом на все три значения сразу.
library;

/// Набор включённого в сборке.
///
/// Функции основного приложения флагами не режутся: чтение, полка,
/// выделение и цитаты общие. Флаг отвечает только за то, чем сборки
/// различаются.
class BranchFlags {
  /// Создаёт набор.
  const BranchFlags({
    required this.branch,
    required this.recording,
    required this.scanner,
    required this.models,
    required this.sync,
    required this.literature,
    required this.galaxy,
    required this.palimpsest,
  });

  /// Набор для ветви [branch].
  ///
  /// Ветвей две — `I` и `II`. Любое другое значение, включая пустое, —
  /// основное приложение: опечатка в команде сборки не должна дать
  /// полуветвь, у которой раздел «Тестирование» есть, а записи нет.
  factory BranchFlags.of(String branch) {
    final bool enabled = isSnoBranch(branch);
    final bool second = branch == snoBranchTest;
    return BranchFlags(
      branch: enabled ? branch : '',
      recording: enabled,
      scanner: !enabled,
      models: !enabled,
      sync: !enabled,
      literature: enabled,
      galaxy: second,
      palimpsest: second,
    );
  }

  /// Ветвь: `I`, `II` или пусто у основного приложения.
  final String branch;

  /// Запись сессии и раздел «Тестирование».
  final bool recording;

  /// Раздел «Устройство» и сканер книг. Доступ ко всем файлам от этого
  /// флага не зависит: ветви он нужен для поиска архива с литературой
  /// (SNO-F-LIT-03).
  final bool scanner;

  /// Промпты, модели, веб-окно, ключи.
  final bool models;

  /// Аккаунт, облако, слияние.
  final bool sync;

  /// Литература в поставке; книги — копии внутри приложения.
  final bool literature;

  /// Карта книг «Галактика».
  final bool galaxy;

  /// Индекс, второй мозг, память книги, окно поиска.
  final bool palimpsest;

  /// Собрана ли ветвь, а не основное приложение.
  bool get enabled => branch.isNotEmpty;

  /// Включённое в ветви — словами, для строки сборки.
  ///
  /// Названо только то, чем ветвь **отличается** от основного
  /// приложения: «сканер выключен» экспериментатору ничего не говорит,
  /// а «запись, литература» — ровно то, что он проверяет взглядом.
  List<String> get enabledNames {
    return <String>[
      if (recording) 'запись',
      if (literature) 'литература',
      if (galaxy) 'галактика',
      if (palimpsest) 'палимпсест',
    ];
  }

  @override
  bool operator ==(Object other) {
    return other is BranchFlags &&
        other.branch == branch &&
        other.recording == recording &&
        other.scanner == scanner &&
        other.models == models &&
        other.sync == sync &&
        other.literature == literature &&
        other.galaxy == galaxy &&
        other.palimpsest == palimpsest;
  }

  @override
  int get hashCode => Object.hash(
    branch,
    recording,
    scanner,
    models,
    sync,
    literature,
    galaxy,
    palimpsest,
  );

  @override
  String toString() => 'BranchFlags(${branch.isEmpty ? 'основное' : branch})';
}

/// Ветвь I — ядро.
const String snoBranchCore = 'I';

/// Ветвь II — тестовая.
const String snoBranchTest = 'II';

/// Называет ли [branch] одну из двух ветвей.
bool isSnoBranch(String branch) {
  return branch == snoBranchCore || branch == snoBranchTest;
}

/// Имя приложения ветви [branch]; у основного — «Memoria LLM HB».
///
/// То же имя стоит под иконкой на телефоне (`android/app/build.gradle.kts`)
/// и в заголовке окна на ПК (`windows/runner/main.cpp`): экспериментатор
/// по одному взгляду понимает, какая сборка перед ним.
String appNameFor(String branch) {
  return isSnoBranch(branch) ? 'Memoria · СНО2026 · $branch' : 'Memoria LLM HB';
}

/// Подпапка данных ветви [branch] в папке данных приложения.
///
/// На Android у каждой ветви свой `applicationId` и своя папка от
/// системы. На Windows флейворов нет: три программы получили бы одну
/// папку и одну базу, и ветвь открыла бы полку основного приложения.
/// Поэтому данные ветви лежат в своей подпапке — на обеих платформах,
/// чтобы правило было одно. У основного приложения подпапки нет: его
/// база лежит там же, где лежала.
String dataFolderFor(String branch) {
  return isSnoBranch(branch) ? 'sno2026-$branch' : '';
}

/// Флаги этой сборки.
///
/// Значения — константы времени сборки: ветка кода под
/// `if (Sno.recording)` в основном приложении недостижима, и сборщик её
/// выбрасывает. Поэтому в одном прогоне тестов раздел «Тестирование»
/// либо есть, либо нет — тесты ветвей идут своими прогонами с
/// `--dart-define=SNO_BRANCH=I` и `II` (`test/sno`).
abstract final class Sno {
  /// Ветвь, как её назвали при сборке.
  static const String _raw = String.fromEnvironment('SNO_BRANCH');

  /// Собрана ли ветвь.
  static const bool enabled = _raw == snoBranchCore || _raw == snoBranchTest;

  /// Ветвь: `I`, `II` или пусто.
  static const String branch = enabled ? _raw : '';

  /// Запись сессии и раздел «Тестирование».
  static const bool recording = enabled;

  /// Раздел «Устройство» и сканер книг. Доступ ко всем файлам от этого
  /// флага не зависит: ветви он нужен для поиска архива с литературой
  /// (SNO-F-LIT-03).
  static const bool scanner = !enabled;

  /// Промпты, модели, веб-окно, ключи.
  static const bool models = !enabled;

  /// Аккаунт, облако, слияние.
  static const bool sync = !enabled;

  /// Литература в поставке; книги — копии внутри приложения.
  static const bool literature = enabled;

  /// Карта книг «Галактика».
  static const bool galaxy = _raw == snoBranchTest;

  /// Индекс, второй мозг, память книги, окно поиска.
  static const bool palimpsest = _raw == snoBranchTest;

  /// Пароль cognitive load test; пусто — пункта теста нет вовсе.
  ///
  /// В исходниках пароля нет: он приходит при сборке (SNO-DIV-06).
  static const String cltPassword = String.fromEnvironment('SNO_CLT_PASSWORD');

  /// Те же флаги одним значением.
  static const BranchFlags flags = BranchFlags(
    branch: branch,
    recording: recording,
    scanner: scanner,
    models: models,
    sync: sync,
    literature: literature,
    galaxy: galaxy,
    palimpsest: palimpsest,
  );
}
