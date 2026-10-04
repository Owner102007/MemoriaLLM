import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/flags.dart';

/// SNO-ALG-CFG-01: три приложения из одного кода — согласие исходников.
///
/// Имя ветви записано в трёх местах, потому что читают его три разных
/// инструмента: Gradle (подпись под иконкой), компилятор C++ (заголовок
/// окна) и Dart (`appNameFor`). Руками такое согласие расходится
/// незаметно, поэтому сверяет его тест. Что вышло в собранном APK и exe,
/// проверяет CI — шагами «Что внутри…» после сборки.
void main() {
  final String gradle = File(
    'android/app/build.gradle.kts',
  ).readAsStringSync();
  final String runner = File('windows/runner/main.cpp').readAsStringSync();

  /// Тело флейвора [name] в `build.gradle.kts`.
  String flavor(String name) {
    final RegExpMatch? match = RegExp(
      'create\\("$name"\\)\\s*\\{([^}]*)\\}',
    ).firstMatch(gradle);
    expect(match, isNotNull, reason: 'нет флейвора $name');
    return match!.group(1)!;
  }

  /// Заголовок окна под условием [guard] в `main.cpp`, с раскрытыми
  /// кодами `\uXXXX`.
  String windowTitle(String guard) {
    final RegExpMatch? match = RegExp(
      '$guard\\s*\\n#define MEMORIA_WINDOW_TITLE L"([^"]*)"',
    ).firstMatch(runner);
    expect(match, isNotNull, reason: 'нет заголовка под «$guard»');
    return match!
        .group(1)!
        .replaceAllMapped(
          RegExp(r'\\u([0-9A-Fa-f]{4})'),
          (Match code) =>
              String.fromCharCode(int.parse(code.group(1)!, radix: 16)),
        );
  }

  group('SNO-ALG-CFG-01: флейворы Android', () {
    test('SNO-F-CFG-01: у ветвей свой идентификатор', () {
      // У основного приложения он прежний: обновление встаёт поверх.
      expect(
        gradle,
        contains('applicationId = "io.github.owner102007.memoria"'),
      );
      expect(flavor('full'), isNot(contains('applicationIdSuffix')));
      expect(
        flavor('sno2026core'),
        contains('applicationIdSuffix = ".sno2026.core"'),
      );
      expect(
        flavor('sno2026test'),
        contains('applicationIdSuffix = ".sno2026.test"'),
      );
    });

    test('SNO-F-CFG-01: имя под иконкой — то же, что знает приложение', () {
      final Map<String, String> branches = <String, String>{
        'full': '',
        'sno2026core': snoBranchCore,
        'sno2026test': snoBranchTest,
      };
      for (final MapEntry<String, String> entry in branches.entries) {
        expect(
          flavor(entry.key),
          contains('manifestPlaceholders["appLabel"] = '
              '"${appNameFor(entry.value)}"'),
          reason: 'флейвор ${entry.key}',
        );
      }
    });

    test('SNO-F-CFG-01: у каждой ветви своя иконка всех размеров', () {
      for (final String name in <String>['sno2026core', 'sno2026test']) {
        for (final String density in <String>[
          'mdpi',
          'hdpi',
          'xhdpi',
          'xxhdpi',
          'xxxhdpi',
        ]) {
          final String path =
              'android/app/src/$name/res/mipmap-$density/ic_launcher.png';
          final File icon = File(path);
          expect(icon.existsSync(), isTrue, reason: 'нет $path');
          final File base = File(
            'android/app/src/main/res/mipmap-$density/ic_launcher.png',
          );
          expect(
            icon.readAsBytesSync(),
            isNot(base.readAsBytesSync()),
            reason: '$path — иконка основного приложения, без плашки',
          );
        }
      }
    });
  });

  group('SNO-F-CFG-02: разрешения на доступ к файлам', () {
    const List<String> storage = <String>[
      'MANAGE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
      'requestLegacyExternalStorage',
    ];

    test('SNO-F-CFG-02: в общем манифесте их нет', () {
      final String shared = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final String name in storage) {
        expect(
          shared,
          isNot(contains('android.permission.$name')),
          reason: '$name достался бы и сборкам ветвей',
        );
        expect(shared, isNot(contains('android:$name')), reason: name);
      }
    });

    test('SNO-F-CFG-02: они объявлены только у основного приложения', () {
      final String full = File(
        'android/app/src/full/AndroidManifest.xml',
      ).readAsStringSync();
      expect(full, contains('android.permission.MANAGE_EXTERNAL_STORAGE'));
      expect(full, contains('android.permission.READ_EXTERNAL_STORAGE'));
      expect(full, contains('android:requestLegacyExternalStorage="true"'));
      for (final String name in <String>['sno2026core', 'sno2026test']) {
        final File own = File('android/app/src/$name/AndroidManifest.xml');
        if (!own.existsSync()) {
          continue;
        }
        expect(
          own.readAsStringSync(),
          isNot(contains('EXTERNAL_STORAGE')),
          reason: 'манифест флейвора $name',
        );
      }
    });
  });

  group('SNO-ALG-CFG-01: окно на Windows', () {
    test('SNO-F-CFG-01: заголовок окна — то же, что знает приложение', () {
      expect(windowTitle('#else'), appNameFor(''));
      expect(
        windowTitle(r'#elif defined\(SNO_BRANCH_I\)'),
        appNameFor(snoBranchCore),
      );
      expect(
        windowTitle(r'#if defined\(SNO_BRANCH_II\)'),
        appNameFor(snoBranchTest),
      );
    });

    test('SNO-F-CFG-01: ветвь окну называет та же переменная, что CI', () {
      final String cmake = File(
        'windows/runner/CMakeLists.txt',
      ).readAsStringSync();
      expect(cmake, contains(r'"$ENV{SNO_BRANCH}" STREQUAL "I"'));
      expect(cmake, contains(r'"$ENV{SNO_BRANCH}" STREQUAL "II"'));
      expect(cmake, contains('"SNO_BRANCH_I"'));
      expect(cmake, contains('"SNO_BRANCH_II"'));
    });
  });
}
