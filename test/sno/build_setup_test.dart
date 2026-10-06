import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/recording/file_store.dart';
import 'package:memoria/sno/recording/record_outlet.dart';
import 'package:memoria/sno/recording/records.dart';

/// SNO-ALG-CFG-01: три приложения из одного кода — согласие исходников.
///
/// Имя ветви записано в трёх местах, потому что читают его три разных
/// инструмента: Gradle (подпись под иконкой), компилятор C++ (заголовок
/// окна) и Dart (`appNameFor`). Руками такое согласие расходится
/// незаметно, поэтому сверяет его тест. Что вышло в собранном APK и exe,
/// проверяет CI — шагами «Что внутри…» после сборки.
void main() {
  final String gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final String runner = File('windows/runner/main.cpp').readAsStringSync();

  /// Тело флейвора [name] в `build.gradle.kts`.
  String flavor(String name) {
    final RegExpMatch? match = RegExp('create\\("$name"\\)\\s*\\{([^}]*)\\}')
        .firstMatch(gradle);
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
          contains(
            'manifestPlaceholders["appLabel"] = '
            '"${appNameFor(entry.value)}"',
          ),
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

  group('SNO-F-LIT-03: разрешения на доступ к файлам', () {
    const List<String> storage = <String>[
      'MANAGE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
      'requestLegacyExternalStorage',
    ];
    const List<String> flavors = <String>['full', 'sno2026core', 'sno2026test'];

    test('SNO-F-LIT-03: в общем манифесте их нет', () {
      // Зачем доступ нужен, у каждого приложения сказано своё — в
      // манифесте его флейвора.
      final String shared = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final String name in storage) {
        expect(
          shared,
          isNot(contains('android.permission.$name')),
          reason: name,
        );
        expect(shared, isNot(contains('android:$name')), reason: name);
      }
    });

    test('SNO-F-LIT-03: читать файлы устройства может каждая сборка', () {
      // Основное приложение ищет книги, ветвь — архив с литературой.
      for (final String name in flavors) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(
          own,
          contains('android.permission.MANAGE_EXTERNAL_STORAGE'),
          reason: 'флейвор $name',
        );
        expect(
          own,
          contains('android.permission.READ_EXTERNAL_STORAGE'),
          reason: 'флейвор $name',
        );
        expect(
          own,
          contains('android:requestLegacyExternalStorage="true"'),
          reason: 'флейвор $name',
        );
      }
    });

    test('SNO-F-LIT-03: писать в чужие файлы и смотреть медиа — никому', () {
      for (final String name in <String>['main', ...flavors]) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(
          own,
          isNot(contains('WRITE_EXTERNAL_STORAGE')),
          reason: 'манифест $name',
        );
        expect(own, isNot(contains('READ_MEDIA_')), reason: 'манифест $name');
      }
    });

    test('SNO-F-LIT-03: манифест ветви говорит, зачем ей доступ', () {
      for (final String name in <String>['sno2026core', 'sno2026test']) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(own, contains('SNO-F-LIT-03'), reason: 'флейвор $name');
      }
    });
  });

  group('SNO-F-REC-06: поставщик файлов для архивов записей', () {
    const Map<String, String> branches = <String, String>{
      'sno2026core': snoBranchCore,
      'sno2026test': snoBranchTest,
    };

    test('SNO-F-REC-06: у ветви поставщик есть, и наружу он не '
        'выставлен', () {
      for (final String name in branches.keys) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(
          own,
          contains(
            'android:name="io.github.owner102007.memoria.'
            'RecordsFileProvider"',
          ),
          reason: 'флейвор $name',
        );
        // Имя поставщика — от идентификатора сборки: у ветвей они
        // разные, и два приложения на одном телефоне не спорят.
        expect(
          own,
          contains(r'android:authorities="${applicationId}.records"'),
          reason: 'флейвор $name',
        );
        expect(own, contains('android:exported="false"'), reason: name);
        expect(
          own,
          contains('android:grantUriPermissions="true"'),
          reason: 'флейвор $name',
        );
        expect(
          own,
          contains('android:resource="@xml/sno_records_paths"'),
          reason: 'флейвор $name',
        );
        expect(own, contains('SNO-F-REC-06'), reason: 'флейвор $name');
      }
    });

    test('SNO-F-REC-06: поставщик отдаёт только папку записей своей '
        'ветви', () {
      for (final MapEntry<String, String> branch in branches.entries) {
        final String paths = File(
          'android/app/src/${branch.key}/res/xml/sno_records_paths.xml',
        ).readAsStringSync();
        // Та же папка, куда записи кладёт приложение: подпапка данных
        // ветви и «Записи».
        final String folder =
            '${dataFolderFor(branch.value)}/${FileRecordingStore.folderName}/';
        expect(
          paths,
          contains('<files-path name="records" path="$folder" />'),
          reason: 'флейвор ${branch.key}',
        );
        // Других путей нет: ни кэша, ни общей памяти, ни корня.
        expect(
          RegExp('<[a-z-]+-path ').allMatches(paths),
          hasLength(1),
          reason: 'флейвор ${branch.key}',
        );
      }
    });

    test('SNO-F-REC-06: в основном приложении поставщика нет', () {
      for (final String name in <String>['main', 'full']) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(own, isNot(contains('<provider')), reason: 'манифест $name');
      }
      expect(
        File('android/app/src/full/res/xml/sno_records_paths.xml').existsSync(),
        isFalse,
      );
    });

    test('SNO-F-REC-06: канал и имя поставщика у Kotlin и у Dart одни', () {
      final String activity = File(
        'android/app/src/main/kotlin/io/github/owner102007/memoria/'
        'MainActivity.kt',
      ).readAsStringSync();
      final String outlet = File('lib/sno/recording/record_outlet.dart')
          .readAsStringSync();

      expect(activity, contains('RECORDS_CHANNEL = "memoria/records"'));
      expect(outlet, contains("MethodChannel('memoria/records')"));
      // Хвост имени поставщика — тот же, что в манифестах ветвей.
      expect(activity, contains('RECORDS_AUTHORITY = ".records"'));
      // Библиотека с `FileProvider` названа сборке явно.
      expect(gradle, contains('implementation("androidx.core:core:'));
    });
  });

  group('SNO-F-REC-13: служба записи, вторая копия и подпись', () {
    const List<String> branches = <String>['sno2026core', 'sno2026test'];
    final String activity = File(
      'android/app/src/main/kotlin/io/github/owner102007/memoria/'
      'MainActivity.kt',
    ).readAsStringSync();

    test('SNO-F-REC-13: у ветви служба записи есть, наружу не выставлена '
        'и уходит вместе с задачей', () {
      for (final String name in branches) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(
          own,
          contains(
            'android:name="io.github.owner102007.memoria.RecordingService"',
          ),
          reason: 'флейвор $name',
        );
        expect(
          own,
          contains('android:foregroundServiceType="specialUse"'),
          reason: 'флейвор $name',
        );
        // Уведомление «Идёт запись» не должно пережить запись.
        expect(
          own,
          contains('android:stopWithTask="true"'),
          reason: 'флейвор $name',
        );
        for (final String permission in <String>[
          'FOREGROUND_SERVICE',
          'FOREGROUND_SERVICE_SPECIAL_USE',
          'POST_NOTIFICATIONS',
        ]) {
          expect(
            own,
            contains('android:name="android.permission.$permission"'),
            reason: 'флейвор $name',
          );
        }
        expect(own, contains('SNO-F-REC-13'), reason: 'флейвор $name');
      }
    });

    test('SNO-F-REC-13: в основном приложении службы и её разрешений '
        'нет', () {
      for (final String name in <String>['main', 'full']) {
        final String own = File('android/app/src/$name/AndroidManifest.xml')
            .readAsStringSync();
        expect(own, isNot(contains('<service')), reason: 'манифест $name');
        expect(
          own,
          isNot(contains('FOREGROUND_SERVICE')),
          reason: 'манифест $name',
        );
        expect(
          own,
          isNot(contains('POST_NOTIFICATIONS')),
          reason: 'манифест $name',
        );
      }
    });

    test('SNO-F-REC-13: значок уведомления лежит там, где его ищет '
        'служба', () {
      final String service = File(
        'android/app/src/main/kotlin/io/github/owner102007/memoria/'
        'RecordingService.kt',
      ).readAsStringSync();
      expect(service, contains('R.drawable.ic_recording'));
      expect(
        File('android/app/src/main/res/drawable/ic_recording.xml').existsSync(),
        isTrue,
      );
    });

    test('SNO-F-REC-13: каналы и их слова у Kotlin и у Dart одни', () {
      final String guard = File('lib/sno/recording/recording_guard.dart')
          .readAsStringSync();
      final String outlet = File('lib/sno/recording/record_outlet.dart')
          .readAsStringSync();
      final String passport = File('lib/sno/recording/device_passport.dart')
          .readAsStringSync();

      expect(activity, contains('GUARD_CHANNEL = "memoria/guard"'));
      expect(guard, contains("MethodChannel('memoria/guard')"));
      for (final String method in <String>[
        'notifications',
        'askNotifications',
        'hold',
        'release',
      ]) {
        expect(activity, contains('"$method" ->'), reason: method);
        expect(guard, contains("'$method'"), reason: method);
      }
      for (final String method in <String>['share', 'canBackup', 'backup']) {
        expect(activity, contains('"$method" ->'), reason: method);
        expect(outlet, contains("'$method'"), reason: method);
      }
      expect(activity, contains('"passport" ->'));
      expect(passport, contains("'passport'"));
      expect(passport, contains("MethodChannel('memoria/device')"));
    });

    test('SNO-F-REC-14: слова ответа окна «Поделиться» у Kotlin и у Dart '
        'одни', () {
      const Map<String, ShareOutcome> words = <String, ShareOutcome>{
        'chosen': ShareOutcome.chosen,
        'dismissed': ShareOutcome.dismissed,
        'untold': ShareOutcome.untold,
        'failed': ShareOutcome.failed,
      };
      for (final MapEntry<String, ShareOutcome> word in words.entries) {
        expect(
          activity,
          contains('= "${word.key}"'),
          reason: 'слово ${word.key}',
        );
        expect(shareOutcomeOf(word.key), word.value);
      }
      // Каждому исходу окна соответствует своё слово.
      expect(words.values.toSet(), ShareOutcome.values.toSet());
    });

    test('SNO-F-REC-13: вторая копия пишется без разрешения на чужие '
        'файлы — через хранилище загрузок', () {
      expect(activity, contains('MediaStore.Downloads'));
      // Папка копий названа в одном месте — в Dart.
      expect(activity, isNot(contains(kBackupFolder)));
      expect(kBackupPlace, endsWith('/$kBackupFolder'));
    });

    test('SNO-F-REC-13: сборки ветвей подписываются ключом из окружения, '
        'в репозитории его нет', () {
      expect(gradle, contains('System.getenv("SNO_KEYSTORE_FILE")'));
      for (final String secret in <String>[
        'SNO_KEYSTORE_PASSWORD',
        'SNO_KEY_ALIAS',
        'SNO_KEY_PASSWORD',
      ]) {
        expect(gradle, contains('System.getenv("$secret")'), reason: secret);
      }
      // Ни пароля, ни пути к ключу строкой в сборке нет.
      expect(gradle, isNot(contains(RegExp('Password = "'))));
      expect(gradle, isNot(contains(RegExp(r'\.(jks|keystore)"'))));
      for (final String name in branches) {
        expect(
          flavor(name),
          contains('signingConfig = branchSigning'),
          reason: 'флейвор $name',
        );
      }
      // Основное приложение этим ключом не подписывается (F-REL-08).
      expect(flavor('full'), contains('signingConfig = debugSigning'));

      final String ci = File('.github/workflows/ci.yml').readAsStringSync();
      for (final String secret in <String>[
        'SNO_KEYSTORE_BASE64',
        'SNO_KEYSTORE_PASSWORD',
        'SNO_KEY_ALIAS',
        'SNO_KEY_PASSWORD',
      ]) {
        expect(ci, contains('secrets.$secret'), reason: secret);
      }
      // Подпись собранного сверяется с отпечатком самого ключа: сборка,
      // которой дали ключ, не вправе молча подписаться отладочным.
      expect(ci, contains('keytool -list -v'));
      expect(ci, contains(r'"$RUNNER_TEMP/sno.sha256"'));
      // Чем подписан собранный APK, читает свой разбор блока подписи:
      // `apksigner` на раннере отпечатка не отдал.
      expect(ci, contains('python3 tool/apk_cert_sha256.py'));
      expect(File('tool/apk_cert_sha256.py').existsSync(), isTrue);
      final String ignored = File('.gitignore').readAsStringSync();
      expect(ignored, contains('*.jks'));
      expect(ignored, contains('*.keystore'));
    });

    test('SNO-F-REC-13: отпечаток ключа — 64 шестнадцатеричных знака '
        'одной строкой или ничего', () {
      final List<String> lines = <String>[
        for (final String line in File(
          'tool/sno_signing_sha256.txt',
        ).readAsLinesSync())
          if (line.trim().isNotEmpty && !line.startsWith('#')) line.trim(),
      ];
      expect(lines.length, lessThanOrEqualTo(1));
      for (final String line in lines) {
        expect(line, matches(RegExp(r'^[0-9a-fA-F]{64}$')));
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
      final String cmake = File('windows/runner/CMakeLists.txt')
          .readAsStringSync();
      expect(cmake, contains(r'"$ENV{SNO_BRANCH}" STREQUAL "I"'));
      expect(cmake, contains(r'"$ENV{SNO_BRANCH}" STREQUAL "II"'));
      expect(cmake, contains('"SNO_BRANCH_I"'));
      expect(cmake, contains('"SNO_BRANCH_II"'));
    });
  });

  group('SNO-F-CLT-01: пароль теста нагрузки приходит при сборке', () {
    test('SNO-F-CLT-01: сборке ветви пароль даёт секрет, в исходниках его '
        'нет', () {
      // SNO-DIV-06: в коде — только чтение переменной сборки.
      final String flags = File('lib/sno/flags.dart').readAsStringSync();
      expect(flags, contains("String.fromEnvironment('SNO_CLT_PASSWORD')"));
      final String ci = File('.github/workflows/ci.yml').readAsStringSync();
      expect(ci, contains('secrets.SNO_CLT_PASSWORD'));
      // Пароль получают обе платформы — и только сборка ветви.
      expect(
        RegExp(
          RegExp.escape(
            r'clt=(--dart-define=SNO_CLT_PASSWORD="$SNO_CLT_PASSWORD")',
          ),
        ).allMatches(ci),
        hasLength(2),
      );
      expect(
        RegExp(
          RegExp.escape(
            r'if [ -n "${SNO_BRANCH:-}" ] && [ -n "${SNO_CLT_PASSWORD:-}" ]',
          ),
        ).allMatches(ci),
        hasLength(2),
      );
      // Релиз основного приложения о пароле теста не знает.
      final String release = File('.github/workflows/release.yml')
          .readAsStringSync();
      expect(release, isNot(contains('SNO_CLT_PASSWORD')));
    });

    test('SNO-F-CLT-01: тест нагрузки заводится только в сборке с паролем', () {
      // Условие начинается с константы сборки: в основное приложение
      // код теста не попадает, а сборка ветви без пароля выходит без
      // пункта теста.
      final String services = File('lib/application/app_services.dart')
          .readAsStringSync();
      expect(
        services,
        matches(
          RegExp(
            r'loadTest:\s*Sno\.recording\s*&&\s*recording != null\s*&&'
            r'\s*_hasLoadTest',
          ),
        ),
      );
      expect(services, contains('Sno.cltPassword.isNotEmpty'));
    });
  });

  group('SNO-F-IDX-04: подготовка книг — только в ветви II', () {
    test('SNO-F-IDX-04: проход по полке заводится под флагом карты', () {
      // Условие — константа сборки: в основном приложении и в ветви I
      // прохода по полке нет вовсе, и код его туда не попадает.
      final String services = File('lib/application/app_services.dart')
          .readAsStringSync();
      expect(services, matches(RegExp(r'shelfReading:\s*Sno\.galaxy\s*\?')));
      expect(BranchFlags.of('').galaxy, isFalse);
      expect(BranchFlags.of(snoBranchCore).galaxy, isFalse);
      expect(BranchFlags.of(snoBranchTest).galaxy, isTrue);
      expect(Sno.galaxy, Sno.branch == snoBranchTest);
    });
  });
}
