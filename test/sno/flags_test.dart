import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/build_info.dart';
import 'package:memoria/domain/navigation/sections.dart';
import 'package:memoria/infrastructure/files/app_directory.dart';
import 'package:memoria/sno/flags.dart';
import 'package:path/path.dart' as p;

/// SNO-ALG-CFG-01: флаги ветви — правила без виджетов.
///
/// Таблица «ветвь → что включено» проверяется здесь на все три значения
/// одним прогоном. Сами флаги сборки — константы, и в прогоне они одни:
/// какие именно, проверяет последняя группа.
void main() {
  group('SNO-ALG-CFG-01: что включает ветвь', () {
    test('SNO-ALG-CFG-01: основное приложение — без тестового', () {
      final BranchFlags flags = BranchFlags.of('');
      expect(flags.enabled, isFalse);
      expect(flags.branch, '');
      expect(flags.recording, isFalse);
      expect(flags.literature, isFalse);
      expect(flags.galaxy, isFalse);
      expect(flags.palimpsest, isFalse);
      // Своё у основного приложения на месте.
      expect(flags.scanner, isTrue);
      expect(flags.models, isTrue);
      expect(flags.sync, isTrue);
      expect(flags.enabledNames, isEmpty);
    });

    test('SNO-ALG-CFG-01: ветвь I — запись и литература, сканера нет', () {
      final BranchFlags flags = BranchFlags.of('I');
      expect(flags.enabled, isTrue);
      expect(flags.branch, 'I');
      expect(flags.recording, isTrue);
      expect(flags.literature, isTrue);
      expect(flags.scanner, isFalse);
      expect(flags.models, isFalse);
      expect(flags.sync, isFalse);
      expect(flags.galaxy, isFalse);
      expect(flags.palimpsest, isFalse);
      expect(flags.enabledNames, <String>['запись', 'литература']);
    });

    test('SNO-ALG-CFG-01: ветвь II — всё из I плюс карта и память', () {
      final BranchFlags first = BranchFlags.of('I');
      final BranchFlags second = BranchFlags.of('II');
      expect(second.branch, 'II');
      // «Одна ветвь растёт из другой»: всё включённое в I включено и в II.
      expect(second.recording, first.recording);
      expect(second.literature, first.literature);
      expect(second.scanner, first.scanner);
      expect(second.models, first.models);
      expect(second.sync, first.sync);
      expect(second.galaxy, isTrue);
      expect(second.palimpsest, isTrue);
      expect(second.enabledNames, <String>[
        'запись',
        'литература',
        'галактика',
        'палимпсест',
      ]);
    });

    test('SNO-ALG-CFG-01: опечатка в имени ветви — основное приложение', () {
      for (final String wrong in <String>['i', 'ii', 'III', '1', 'I ', 'x']) {
        expect(
          BranchFlags.of(wrong),
          BranchFlags.of(''),
          reason: 'значение «$wrong» ветвью не является',
        );
        expect(isSnoBranch(wrong), isFalse, reason: 'значение «$wrong»');
      }
    });
  });

  group('SNO-F-CFG-01: имя, папка и строка сборки', () {
    test('SNO-F-CFG-01: у ветви своё имя, у основного — прежнее', () {
      expect(appNameFor(''), 'Memoria LLM HB');
      expect(appNameFor('I'), 'Memoria · СНО2026 · I');
      expect(appNameFor('II'), 'Memoria · СНО2026 · II');
      expect(appNameFor('III'), 'Memoria LLM HB');
    });

    test('SNO-F-CFG-01: данные ветви лежат в своей подпапке', () {
      final Directory support = Directory(p.join('data', 'Memoria'));
      // База основного приложения остаётся там, где лежала.
      expect(dataDirectoryIn(support, '').path, support.path);
      final String first = dataDirectoryIn(support, 'I').path;
      final String second = dataDirectoryIn(support, 'II').path;
      expect(first, p.join(support.path, 'sno2026-I'));
      expect(second, p.join(support.path, 'sno2026-II'));
      expect(<String>{support.path, first, second}, hasLength(3));
    });

    test('SNO-F-CFG-01: строка сборки основного приложения — как была', () {
      expect(
        buildLabelFor(
          version: '0.18.0-main',
          commit: '7637a7e61184c2cd6ce6f6cbc719f1172793b585',
          flags: BranchFlags.of(''),
        ),
        '0.18.0-main · 7637a7e',
      );
      expect(
        buildLabelFor(
          version: 'dev',
          commit: 'local',
          flags: BranchFlags.of(''),
        ),
        'dev · local',
      );
    });

    test('SNO-F-CFG-01: строка сборки ветви называет ветвь и флаги', () {
      expect(
        buildLabelFor(
          version: '0.18.0-sno2026.I',
          commit: '7637a7e61184c2cd6ce6f6cbc719f1172793b585',
          flags: BranchFlags.of('I'),
        ),
        'ветвь I · 0.18.0-sno2026.I · 7637a7e · флаги: запись, литература',
      );
      expect(
        buildLabelFor(
          version: '0.18.0-sno2026.II',
          commit: 'abc',
          flags: BranchFlags.of('II'),
        ),
        'ветвь II · 0.18.0-sno2026.II · abc · '
        'флаги: запись, литература, галактика, палимпсест',
      );
    });
  });

  group('SNO-F-CFG-02: разделы сборки', () {
    test('SNO-F-CFG-02: в ветви «Устройства» нет, «Тестирование» есть', () {
      final BranchFlags flags = BranchFlags.of('I');
      expect(
        sectionsFor(scanner: flags.scanner, testing: flags.recording),
        <AppSection>[AppSection.shelf, AppSection.testing, AppSection.settings],
      );
    });

    test('SNO-F-CFG-02: основное приложение — прежние три раздела', () {
      final BranchFlags flags = BranchFlags.of('');
      expect(
        sectionsFor(scanner: flags.scanner, testing: flags.recording),
        <AppSection>[AppSection.shelf, AppSection.device, AppSection.settings],
      );
    });
  });

  group('SNO-ALG-CFG-01: флаги этой сборки', () {
    test('SNO-ALG-CFG-01: константы сборки совпадают с таблицей', () {
      // Проходит в любом прогоне: и в основном, и с
      // `--dart-define=SNO_BRANCH=I`, и с `II`.
      expect(Sno.flags, BranchFlags.of(Sno.branch));
      expect(Sno.enabled, Sno.flags.enabled);
      expect(Sno.recording, Sno.flags.recording);
      expect(Sno.scanner, Sno.flags.scanner);
      expect(Sno.literature, Sno.flags.literature);
      expect(Sno.galaxy, Sno.flags.galaxy);
      expect(Sno.palimpsest, Sno.flags.palimpsest);
    });

    test('SNO-F-CFG-01: в сборке без SNO_BRANCH флаги ветви выключены', () {
      expect(Sno.enabled, isFalse);
      expect(Sno.recording, isFalse);
      expect(Sno.literature, isFalse);
      expect(Sno.scanner, isTrue);
      expect(Sno.cltPassword, isEmpty);
    }, skip: Sno.enabled ? 'прогон ветви: проверяется основным' : false);
  });
}
