import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/build_info.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/testing_screen.dart';

import '../data/test_data.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-CFG-06: сборка исследования и проверочная сборка.
///
/// Участников записывают на сборке, собранной CI по тегу исследования
/// (`sno2026-1`); у неё тег и день сборки зашиты при компиляции. Любая
/// другая сборка — из `latest`, из ветки, локальная — проверочная: на
/// ней можно записывать, но над «Старт записи» об этом сказано.
///
/// Тег — константа сборки, поэтому раздел получает его параметром: в
/// одном прогоне тестов сборка одна, а проверить надо обе.
void main() {
  const String branchOnly =
      'основной прогон: проверяется прогонами ветвей '
      '(--dart-define=SNO_BRANCH=I и II)';

  group('SNO-F-CFG-06: тег сборки исследования', () {
    test('SNO-F-CFG-06: тег исследования — sno2026-N и sno2026-N.M', () {
      expect(isStudyTag('sno2026-1'), isTrue);
      expect(isStudyTag('sno2026-12'), isTrue);
      expect(isStudyTag('sno2026-1.1'), isTrue);
      expect(isStudyTag('sno2026-2.10'), isTrue);
    });

    test('SNO-F-CFG-06: остальное тегом исследования не считается', () {
      for (final String tag in <String>[
        '',
        'latest',
        'v0.39.0-alpha',
        'sno2026-',
        'sno2026-0',
        'sno2026-01',
        'sno2026-1.0',
        'sno2026-1.1.1',
        'sno2026-1-test',
        'SNO2026-1',
        ' sno2026-1',
        'sno2026-1 ',
      ]) {
        expect(isStudyTag(tag), isFalse, reason: tag);
      }
    });

    test('SNO-F-CFG-06: строка «О ветви» называет сборку и день', () {
      expect(
        studyBuildLine(studyTag: 'sno2026-1', built: '2026-10-10'),
        'Сборка исследования sno2026-1 · собрана 10.10.2026',
      );
      expect(
        studyBuildLine(studyTag: '', built: '2026-10-10'),
        'Проверочная сборка — не для участников · собрана 10.10.2026',
      );
      // Неверный тег — проверочная сборка, а не «исследования».
      expect(
        studyBuildLine(studyTag: 'sno2026-x', built: '2026-10-10'),
        startsWith(kTrialBuildNote),
      );
      // Локальная сборка дня не знает.
      expect(studyBuildLine(studyTag: '', built: ''), kTrialBuildNote);
      // День, который не разобрался, стоит как есть.
      expect(
        studyBuildLine(studyTag: 'sno2026-1', built: '10 окт'),
        'Сборка исследования sno2026-1 · собрана 10 окт',
      );
    });

    test('SNO-F-CFG-06: сборка без тега — проверочная', () {
      // В тестах тега нет: прогоны CI идут без APP_STUDY_TAG.
      expect(appStudyTag, isEmpty);
      expect(isStudyBuild, isFalse);
    });
  });

  group('SNO-F-CFG-06: «Тестирование» на сборке исследования', () {
    late AppData data;
    late SessionKit kit;

    setUp(() async {
      data = await openTestData();
      kit = SessionKit(status: FakeDeviceStatus(battery: 84, free: 1 << 30));
    });
    tearDown(() async {
      kit.session.dispose();
      await data.close();
    });

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> pumpTesting(
      WidgetTester tester, {
      required String studyTag,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(data: data, recording: kit.session),
            flags: BranchFlags.of('I'),
            studyTag: studyTag,
            built: '2026-10-10',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String about(WidgetTester tester) {
      final ListTile tile = tester.widget<ListTile>(
        find.byKey(const Key('sno-about')),
      );
      return (tile.subtitle! as Text).data!;
    }

    testWidgets('SNO-F-CFG-06: проверочная сборка сказана над стартом', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, studyTag: '');

      expect(find.byKey(const Key('sno-trial-build')), findsOneWidget);
      expect(find.text(kTrialBuildNote), findsOneWidget);
      // Старт не запрещён: на проверочной сборке проверяют запись.
      final FilledButton start = tester.widget<FilledButton>(
        find.byKey(const Key('sno-record-start')),
      );
      expect(start.onPressed, isNotNull);
      // Строка стоит над кнопкой, а не под ней.
      expect(
        tester.getTopLeft(find.byKey(const Key('sno-trial-build'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('sno-record-start'))).dy,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('sno-about')));
      expect(
        about(tester),
        endsWith('\n$kTrialBuildNote · собрана 10.10.2026'),
      );

      await unmount(tester);
    });

    testWidgets('SNO-F-CFG-06: на сборке исследования пометки нет', (
      WidgetTester tester,
    ) async {
      await pumpTesting(tester, studyTag: 'sno2026-1');

      expect(find.byKey(const Key('sno-trial-build')), findsNothing);
      expect(find.byKey(const Key('sno-record-start')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('sno-about')));
      expect(
        about(tester),
        endsWith('\nСборка исследования sno2026-1 · собрана 10.10.2026'),
      );
      // Первая строка — прежняя строка сборки с ветвью и флагами.
      expect(about(tester), startsWith('ветвь I · '));

      await unmount(tester);
    });
  }, skip: Sno.recording ? false : branchOnly);
}
