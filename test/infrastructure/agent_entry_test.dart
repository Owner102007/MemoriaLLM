/// Marionette не попадает в приложение (F-REL-11).
///
/// Управление агентом живёт только в точке входа `tool/agent/` и
/// подключается dev-зависимостью. Тест стережёт это: ни один файл `lib/`
/// не импортирует Marionette, а в обычных зависимостях `pubspec.yaml` его
/// нет — значит, в выпуск он не соберётся.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F-REL-11: в коде приложения нет Marionette', () {
    final List<String> offenders = <String>[
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains('package:marionette'))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });

  test('F-REL-11: Marionette — только dev-зависимость', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final int dev = pubspec.indexOf('\ndev_dependencies:');
    final int marionette = pubspec.indexOf('marionette_flutter:');
    expect(dev, greaterThan(0));
    expect(marionette, greaterThan(dev));
  });
}
