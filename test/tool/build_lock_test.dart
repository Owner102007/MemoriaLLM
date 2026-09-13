import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Строка `version:` внутри записи пакета в `pubspec.lock`.
final RegExp _lockVersion = RegExp(r'^    version: "(.+)"$');

/// Точная версия Flutter в композитном действии.
final RegExp _pinned = RegExp(r"^\s*default: '([^']+)'", multiLine: true);

const String _noLockReason =
    'Без замка «одинаковый код → одинаковая сборка» не работает. Замок '
    'считает работа «Замок зависимостей» в bootstrap.yml: у сессии нет '
    'доступа к pub.dev, и посчитать его может только раннер.';

const String _exactReason =
    'Версия обязана быть точной: канал или диапазон возвращает ту самую '
    'зависимость от чужого релиза, против которой сделана S6.2.1.';

const String _directReason =
    'Канарейке версия не фиксируется нарочно — в этом вся её работа. '
    'Всем остальным работам версию даёт .github/actions/flutter, и это '
    'единственное место, где она записана.';

/// Замок сборки (S6.2.1): сама проверка и есть продукт сессии.
///
/// Три свойства, которые теряются правкой одного файла: зависимости
/// приходят из `pubspec.lock`, версия Flutter записана в одном месте,
/// и `pub get` в CI не обновляет замок молча.
///
/// Чего здесь намеренно нет — сверки версии `pdfrx` с ожидаемой. Замком
/// служит сам `pubspec.lock`: пока он в репозитории, версия меняется
/// только коммитом. Прибитая рядом вторая запись про ту же версию
/// вернула бы ровно ту болезнь, от которой сессия лечит, — красный CI
/// из-за чужого релиза. Сигнал об обновлении приходит от канарейки
/// (`.github/workflows/canary.yml`).
void main() {
  group('замок зависимостей', () {
    test('pubspec.lock лежит в репозитории', () {
      final bool exists = File('pubspec.lock').existsSync();
      expect(exists, isTrue, reason: _noLockReason);
    });

    test('в замке есть движок с точной версией', () {
      final File lock = File('pubspec.lock');
      if (!lock.existsSync()) {
        return;
      }
      final String text = lock.readAsStringSync();
      expect(text, contains('\n  pdfrx:\n'));
      expect(_lockedVersion(text, 'pdfrx'), matches(r'^\d+\.\d+\.\d+'));
    });
  });

  group('версия Flutter записана в одном месте', () {
    test('у композитного действия версия точная', () {
      final File action = File('.github/actions/flutter/action.yml');
      expect(action.existsSync(), isTrue);
      final String text = action.readAsStringSync();
      final RegExpMatch? match = _pinned.firstMatch(text);
      expect(match, isNotNull, reason: 'не нашлась строка default:');
      expect(match!.group(1), matches(r'^\d+\.\d+\.\d+$'));
    });

    test('напрямую ставит Flutter только канарейка', () {
      final Directory dir = Directory('.github/workflows');
      final List<String> direct = <String>[];
      for (final FileSystemEntity entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.yml')) {
          continue;
        }
        final String text = entity.readAsStringSync();
        if (_codeHas(text, 'subosito/flutter-action')) {
          direct.add(entity.uri.pathSegments.last);
        }
      }
      expect(direct, <String>['canary.yml'], reason: _directReason);
    });

    test('версия в действии — не канал', () {
      final File action = File('.github/actions/flutter/action.yml');
      final String text = action.readAsStringSync();
      expect(text, isNot(contains("default: 'stable'")), reason: _exactReason);
    });
  });

  group('CI не обновляет замок молча', () {
    test('каждый pub get идёт с --enforce-lockfile', () {
      for (final String name in <String>['ci.yml', 'release.yml']) {
        final File file = File('.github/workflows/$name');
        final List<String> plain = <String>[];
        for (final String line in file.readAsStringSync().split('\n')) {
          final String code = line.trim();
          if (code.startsWith('#') || !code.contains('flutter pub get')) {
            continue;
          }
          if (!code.contains('--enforce-lockfile')) {
            plain.add(code);
          }
        }
        expect(plain, isEmpty, reason: '$name: $plain');
      }
    });
  });
}

/// Версия пакета из `pubspec.lock` — строка `version:` под его именем.
String? _lockedVersion(String lock, String package) {
  bool inside = false;
  for (final String line in lock.split('\n')) {
    if (line == '  $package:') {
      inside = true;
      continue;
    }
    if (!inside) {
      continue;
    }
    if (!line.startsWith('    ')) {
      return null;
    }
    final RegExpMatch? match = _lockVersion.firstMatch(line);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

/// Упоминание в коде, а не в комментарии: строки, начинающиеся с `#`,
/// пропускаются. Без этого объяснение в комментарии — почему версия
/// живёт в одном месте — само валило бы проверку.
bool _codeHas(String yaml, String needle) {
  for (final String line in yaml.split('\n')) {
    final String code = line.trim();
    if (code.startsWith('#')) {
      continue;
    }
    if (code.contains(needle)) {
      return true;
    }
  }
  return false;
}
