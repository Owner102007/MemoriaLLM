// Проверка номеров сессий — принцип 4 плана: номер выдаётся один раз
// и у него есть статус.
//
// Зачем. Номер сессии — единственное, чем работа опознаётся в плане,
// в `PROGRESS.md`, в теге и в промпте. Дважды выданный номер уже дважды
// стоил проекту работы: S4.1 и S5.4 разводились задним числом, когда
// теги были поставлены и переписать их было нельзя. Обе ошибки эта
// проверка поймала бы в тот же день.
//
// Что считается объявлением. В плане — заголовок вида
// `### S6.2 — Одна страница, один слой`; в `PROGRESS.md` — строка
// реестра `| S6.2 | выполнена 06.09.2026 |` в разделе «Реестр сессий».
// Проверяется три вещи: номер объявлен в плане один раз, в реестре
// один раз, и у каждого объявленного в плане номера есть строка статуса.
//
// Почему план не обязателен. Папка `docs/` лежит вне репозитория и не
// публикуется, поэтому в CI видно только `PROGRESS.md`: там проверяется
// реестр сам по себе. Локально план берётся из `MEMORIA_PLAN_PATH`,
// а если переменной нет — из папки рядом с репозиторием; когда файла
// нет вовсе, эта половина проверки молча пропускается.

import 'dart:io';

/// Заголовок раздела `PROGRESS.md`, в котором живёт реестр сессий.
const String registryHeading = '## Реестр сессий';

/// Где искать план, если `MEMORIA_PLAN_PATH` не задана.
const String defaultPlanPath = '../docs/dev_plan_sessions.md';

/// Строка реестра: `| S6.2 | выполнена 06.09.2026 |`.
final RegExp _registryRow = RegExp(r'^\|\s*(S[0-9][^|\s]*)\s*\|([^|]*)\|$');

/// Объявление сессии в плане: `### S6.2 — Одна страница, один слой`.
final RegExp _planDeclaration = RegExp(r'^###\s+(S[0-9]\S*)\s+—');

/// Строка реестра сессий: номер, статус и место, где она найдена.
class RegistryRow {
  /// Создаёт строку реестра.
  const RegistryRow({
    required this.number,
    required this.status,
    required this.line,
  });

  /// Номер сессии, например `S6.2.1`.
  final String number;

  /// Статус: «выполнена 06.09.2026», «в очереди» и тому подобное.
  final String status;

  /// Номер строки в файле — чтобы отказ показывал, куда смотреть.
  final int line;
}

/// Разбирает реестр сессий из текста `PROGRESS.md`.
List<RegistryRow> parseRegistry(String progress) {
  final List<String> lines = progress.split('\n');
  final List<RegistryRow> rows = <RegistryRow>[];
  bool inside = false;
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i].trimRight();
    if (line.startsWith('## ')) {
      inside = line == registryHeading;
      continue;
    }
    if (!inside) {
      continue;
    }
    final RegExpMatch? match = _registryRow.firstMatch(line);
    if (match == null) {
      continue;
    }
    final String number = match.group(1)!;
    final String status = match.group(2)!.trim();
    rows.add(RegistryRow(number: number, status: status, line: i + 1));
  }
  return rows;
}

/// Находит объявления сессий в плане: номер и строку заголовка.
Map<String, List<int>> parsePlanDeclarations(String plan) {
  final List<String> lines = plan.split('\n');
  final Map<String, List<int>> found = <String, List<int>>{};
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? match = _planDeclaration.firstMatch(lines[i]);
    if (match == null) {
      continue;
    }
    found.putIfAbsent(match.group(1)!, () => <int>[]).add(i + 1);
  }
  return found;
}

/// Проверяет номера сессий и возвращает список найденных нарушений.
///
/// Пустой список — всё в порядке. `plan` можно не передавать: в CI его
/// нет, и тогда проверяется только реестр.
List<String> checkSessions({required String progress, String? plan}) {
  final List<String> problems = <String>[];
  final List<RegistryRow> rows = parseRegistry(progress);
  if (rows.isEmpty) {
    problems.add('PROGRESS.md: нет раздела «$registryHeading» с таблицей.');
    return problems;
  }
  final Map<String, RegistryRow> byNumber = <String, RegistryRow>{};
  for (final RegistryRow row in rows) {
    final RegistryRow? seen = byNumber[row.number];
    if (seen != null) {
      final String where = 'строки ${seen.line} и ${row.line}';
      problems.add('Реестр: ${row.number} выдан дважды ($where).');
      continue;
    }
    byNumber[row.number] = row;
    if (row.status.isEmpty) {
      problems.add('Реестр, строка ${row.line}: ${row.number} без статуса.');
    }
  }
  if (plan == null) {
    return problems;
  }
  final Map<String, List<int>> declared = parsePlanDeclarations(plan);
  for (final MapEntry<String, List<int>> entry in declared.entries) {
    final List<int> at = entry.value;
    if (at.length > 1) {
      final String where = at.join(', ');
      problems.add('План: ${entry.key} объявлен ${at.length} раза ($where).');
    }
    if (!byNumber.containsKey(entry.key)) {
      final String where = 'строка ${at.first}';
      problems.add('План, $where: ${entry.key} нет в реестре PROGRESS.md.');
    }
  }
  return problems;
}

/// Запуск из корня репозитория: `dart run tool/check_session_numbers.dart`.
void main() {
  final File progressFile = File('PROGRESS.md');
  if (!progressFile.existsSync()) {
    stderr.writeln('PROGRESS.md не найден — запускайте из корня репозитория.');
    exitCode = 2;
    return;
  }
  final String planPath =
      Platform.environment['MEMORIA_PLAN_PATH'] ?? defaultPlanPath;
  final File planFile = File(planPath);
  final bool hasPlan = planFile.existsSync();
  final List<String> problems = checkSessions(
    progress: progressFile.readAsStringSync(),
    plan: hasPlan ? planFile.readAsStringSync() : null,
  );
  if (hasPlan) {
    stdout.writeln('Проверены PROGRESS.md и $planPath.');
  } else {
    stdout.writeln('Проверен PROGRESS.md; плана нет ($planPath) — пропущен.');
  }
  if (problems.isEmpty) {
    stdout.writeln('Номера сессий в порядке.');
    return;
  }
  for (final String problem in problems) {
    stdout.writeln('- $problem');
  }
  exitCode = 1;
}
