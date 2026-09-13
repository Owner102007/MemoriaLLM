import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_session_numbers.dart';

/// Правильный реестр: два номера, у каждого статус.
const String _goodProgress = '''
# PROGRESS

## Реестр сессий

| Номер | Статус |
|---|---|
| S0 | выполнена 31.07.2026 |
| S6.2 | выполнена 06.09.2026 |
| S6.10 | в очереди |

## Что дальше
''';

/// Тот же реестр, но номер выдан дважды — случай S4.1 и S5.4.
const String _doubleNumber = '''
## Реестр сессий

| Номер | Статус |
|---|---|
| S6.2 | выполнена 06.09.2026 |
| S6.2 | в очереди |
''';

/// Номер есть, статуса нет.
const String _noStatus = '''
## Реестр сессий

| Номер | Статус |
|---|---|
| S6.2 |  |
''';

/// План объявляет сессию, которой нет в реестре.
const String _planWithStranger = '''
## 3. Сессии подробно

### S0 — Регистрации и доступы 🙋 ✅
### S9.9 — Придуманная сессия 🤖
''';

/// План объявляет один номер двумя заголовками.
const String _planWithTwin = '''
### S0 — Регистрации и доступы 🙋 ✅
### S0 — Она же, второй раз 🤖
''';

/// Проверка номеров сессий (принцип 4) — на настоящих файлах и на битых.
///
/// Битые примеры здесь не для полноты, а потому что проверку, которая
/// никогда не падала, нельзя считать работающей: оба сбоя, ради которых
/// она написана, выглядели именно так — дважды выданный номер и номер
/// без статуса.
void main() {
  group('настоящие файлы', () {
    test('реестр в PROGRESS.md сходится', () {
      final String progress = File('PROGRESS.md').readAsStringSync();
      expect(checkSessions(progress: progress), isEmpty);
    });

    test('план, если он рядом, сходится с реестром', () {
      final String path =
          Platform.environment['MEMORIA_PLAN_PATH'] ?? defaultPlanPath;
      final File plan = File(path);
      if (!plan.existsSync()) {
        return;
      }
      final String progress = File('PROGRESS.md').readAsStringSync();
      final List<String> problems = checkSessions(
        progress: progress,
        plan: plan.readAsStringSync(),
      );
      expect(problems, isEmpty);
    });
  });

  group('битые примеры', () {
    test('правильный реестр нарушений не даёт', () {
      expect(checkSessions(progress: _goodProgress), isEmpty);
    });

    test('дважды выданный номер виден', () {
      final List<String> problems = checkSessions(progress: _doubleNumber);
      expect(problems, hasLength(1));
      expect(problems.single, contains('S6.2'));
      expect(problems.single, contains('дважды'));
    });

    test('номер без статуса виден', () {
      final List<String> problems = checkSessions(progress: _noStatus);
      expect(problems, hasLength(1));
      expect(problems.single, contains('без статуса'));
    });

    test('отсутствующий реестр виден', () {
      final List<String> problems = checkSessions(progress: '# PROGRESS\n');
      expect(problems, hasLength(1));
      expect(problems.single, contains('Реестр сессий'));
    });

    test('номер из плана без строки статуса виден', () {
      final List<String> problems = checkSessions(
        progress: _goodProgress,
        plan: _planWithStranger,
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('S9.9'));
    });

    test('номер, объявленный в плане дважды, виден', () {
      final List<String> problems = checkSessions(
        progress: _goodProgress,
        plan: _planWithTwin,
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('S0'));
    });

    test('план без замечаний молчит', () {
      final List<String> problems = checkSessions(
        progress: _goodProgress,
        plan: '### S0 — Регистрации 🙋\n### S6.2 — Одна страница 🤖\n',
      );
      expect(problems, isEmpty);
    });
  });

  group('разбор', () {
    test('реестр читается построчно с номерами строк', () {
      final List<RegistryRow> rows = parseRegistry(_goodProgress);
      expect(rows, hasLength(3));
      expect(rows.first.number, 'S0');
      expect(rows.first.status, 'выполнена 31.07.2026');
      expect(rows.last.number, 'S6.10');
      expect(rows.last.line, 9);
    });

    test('заголовок таблицы и разделитель за номера не считаются', () {
      final List<RegistryRow> rows = parseRegistry(_noStatus);
      expect(rows, hasLength(1));
      expect(rows.single.number, 'S6.2');
    });

    test('объявления в плане находятся вместе со строками', () {
      final Map<String, List<int>> found = parsePlanDeclarations(_planWithTwin);
      expect(found.keys, <String>['S0']);
      expect(found['S0'], <int>[1, 2]);
    });
  });
}
