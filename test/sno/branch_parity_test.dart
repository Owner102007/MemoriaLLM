import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/app_services.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/application/reading/book_times.dart';
import 'package:memoria/application/theme/theme_controller.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/clt/load_test.dart';
import 'package:memoria/sno/clt/test_screens.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/hold_button.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/finish_screen.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';
import 'package:memoria/ui/app.dart';
import 'package:memoria/ui/reader/reader_screen.dart';

import '../data/test_data.dart';
import '../support/fake_reading.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-REC-17: запись и тестирование одинаковы в обеих ветвях.
///
/// Участник ветви I и участник ветви II проходят одну и ту же сессию, и
/// организатор получает архивы одного устройства: одни и те же файлы,
/// одни и те же события с одними и теми же полями. Серии «с
/// „Галактикой“» и «без неё» сравнимы только так.
///
/// Здесь один сценарий действий — старт записи, книга с полки,
/// листание, другой раздел, вторая книга, остановка, тест нагрузки,
/// завершение — проигрывается приложением в сборе. Файл гоняется
/// прогоном ветви I и прогоном ветви II (флаги ветви — константы
/// сборки), и в обоих то, что вышло, сверяется с одним эталоном в
/// репозитории: `test/goldens/sno_event_fields.txt`.
///
/// Сессия и тест — на памяти и подменённом времени; счёт времени в
/// книгах заводится тем же условием, что в приложении
/// ([AppServices.bookTimesFor]).
void main() {
  /// Пароль теста в этой проверке.
  const String password = '2580';

  const String goldenPath = 'test/goldens/sno_event_fields.txt';

  late AppData data;
  late SessionKit kit;
  late LoadTest loadTest;
  BookTimes? times;

  setUp(() async {
    data = await openTestData();
    await data.settings.write(SettingsKeys.tapZoneHintSeen, 'true');
    // Тем же условием, что в приложении: константа сборки ветви.
    times = AppServices.bookTimesFor(data.settings);
    kit = SessionKit(
      status: FakeDeviceStatus(battery: 84, free: 1288490189),
      hasTest: true,
      closingFacts: times?.openFacts,
      branch: Sno.branch,
    );
    loadTest = LoadTest(
      session: kit.session,
      password: password,
      now: kit.time.now,
      elapsedMs: () => kit.time.monotonic,
    );
  });
  tearDown(() async {
    loadTest.dispose();
    kit.session.dispose();
    await data.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  /// Держит палец на виджете с ключом [key] дольше, чем нужно кнопке.
  Future<void> holdOn(WidgetTester tester, String key) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key(key))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(kResetHold + const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Секунды записи: счёт сессии и время экрана идут вместе.
  Future<void> pass(WidgetTester tester, int seconds) async {
    kit.run(seconds);
    await tester.pump();
  }

  /// Открывает книгу с полки, листает её и возвращается на полку.
  Future<void> readBook(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('library-book-$id')));
    await settle(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    await pass(tester, 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
  }

  /// Поля [map] по алфавиту, через запятую.
  String fieldsOf(Object? map, {Set<String> without = const <String>{}}) {
    if (map is! Map<String, Object?>) {
      return '';
    }
    final List<String> keys = <String>[
      for (final String key in map.keys)
        if (!without.contains(key)) key,
    ]..sort();
    return keys.join(',');
  }

  /// Что вышло из сценария, строками эталона: виды событий с полями,
  /// файлы записи, поля сведений записи и показателей теста.
  List<String> told(String folder) {
    final Set<String> second = <String>{
      for (final SnoEventType type in kSecondBranchEvents) type.wire,
    };
    final Map<String, Set<String>> top = <String, Set<String>>{};
    final Map<String, Set<String>> inner = <String, Set<String>>{};
    for (final Map<String, Object?> event in kit.store.events(folder)) {
      final String type = event['type']! as String;
      if (second.contains(type)) {
        continue;
      }
      final Set<String> fields = top.putIfAbsent(type, () => <String>{});
      for (final String key in event.keys) {
        if (key != 'data') {
          fields.add(key);
        }
      }
      final Set<String> inside = inner.putIfAbsent(type, () => <String>{});
      final Object? payload = event['data'];
      if (payload is Map<String, Object?>) {
        inside.addAll(payload.keys);
      }
    }
    final List<String> types = top.keys.toList()..sort();
    final Map<String, String> files = kit.store.files[folder]!;
    // Имя файла ответов несёт время начала части: в эталоне его нет.
    final List<String> names = <String>[
      for (final String name in files.keys)
        name.replaceAll(RegExp(r'_\d+\.json$'), '_<t>.json'),
      if (kit.store.journals.containsKey(folder)) kEventsFile,
      if (kit.store.inputs.containsKey(folder)) kInputFile,
    ]..sort();
    final Map<String, Object?> info = kit.store.json(folder, kRecordingFile);
    final Map<String, Object?> scores = kit.store.json(
      folder,
      'clt/scores.json',
    );
    return <String>[
      for (final String type in types)
        '$type | ${(top[type]!.toList()..sort()).join(',')} | '
            '${(inner[type]!.toList()..sort()).join(',')}',
      'файлы записи | ${names.join(',')} |',
      'recording.json | ${fieldsOf(info)} |',
      'recording.json: recording | ${fieldsOf(info['recording'])} |',
      'recording.json: device | ${fieldsOf(info['device'])} |',
      'recording.json: input | ${fieldsOf(info['input'])} |',
      'recording.json: clt | ${fieldsOf(info['clt'])} |',
      'clt/scores.json | ${fieldsOf(scores)} |',
      'clt/scores.json: checks | ${fieldsOf(scores['checks'])} |',
    ];
  }

  /// Строки эталона из репозитория, без пояснений в начале файла.
  List<String> golden() {
    return <String>[
      for (final String line in File(goldenPath).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.startsWith('#')) line.trimRight(),
    ];
  }

  testWidgets('SNO-F-REC-17: один сценарий действий даёт в ветвях I и II '
      'одни события с одними полями и одни файлы записи', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await data.library.save(testBook());
    await data.library.save(
      testBook(id: 'book-2', title: 'Анатомия человека', hash: 'hash-2'),
    );
    await tester.pumpWidget(
      MemoriaApp(
        themeController: ThemeController(),
        services: testServices(
          data: data,
          recording: kit.session,
          loadTest: loadTest,
          bookTimes: times,
          document: FakeReaderDocument(
            pages: <String>['один', 'два', 'три', 'четыре'],
          ),
        ),
      ),
    );
    await settle(tester);

    // Старт записи — в «Тестировании», с кодом участника.
    await tap(tester, 'nav-testing');
    await tap(tester, 'sno-record-start');
    await tap(tester, 'sno-code-confirm');
    expect(kit.session.recording, isTrue);
    final String folder = kit.folder;
    await pass(tester, 12);

    // Первая книга: открыл, полистал, вернулся на полку.
    await readBook(tester, 'book-1');
    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await settle(tester);
    await pass(tester, 3);

    // Другой раздел и обратно.
    await tap(tester, 'nav-settings');
    await tap(tester, 'nav-library');

    // Вторая книга открыта в миг остановки записи: её закрывает сама
    // остановка (SNO-F-REC-16).
    await readBook(tester, 'book-2');
    await pass(tester, 6);
    await kit.session.stop(StopReason.experimenter);
    await settle(tester);
    expect(find.byType(SessionFinishScreen), findsOneWidget);
    expect(find.byType(ReaderScreen), findsNothing);

    // Тест нагрузки: пароль организатора, вступление, восемнадцать
    // пунктов.
    await tap(tester, 'sno-finish-test');
    for (final String digit in password.split('')) {
      await tap(tester, 'sno-clt-key-$digit');
    }
    await tap(tester, 'sno-clt-key-ok');
    expect(find.byType(LoadTestRunScreen), findsOneWidget);
    await tap(tester, 'sno-clt-begin');
    for (int i = 0; i < 18; i++) {
      kit.time.pass(const Duration(seconds: 2));
      if (find.byKey(const Key('sno-clt-strip')).evaluate().isNotEmpty) {
        await tap(tester, 'sno-clt-more');
      } else {
        await tap(tester, 'sno-clt-value-${2 + i % 4}');
      }
      await tap(tester, 'sno-clt-next');
    }
    await tap(tester, 'sno-clt-close');

    await holdOn(tester, 'sno-finish-hold');
    expect(kit.session.phase, RecordingPhase.idle);
    expect(kit.store.finished, contains(folder));

    final List<String> types = kit.store.types(folder);
    // Перечень видов событий один: то, что пишет только ветвь II, —
    // события экранов, которых в ветви I нет.
    if (!Sno.galaxy) {
      for (final SnoEventType type in kSecondBranchEvents) {
        expect(types, isNot(contains(type.wire)), reason: type.wire);
      }
    }
    // `book.close` несёт время чтения на виду — в обеих ветвях: и то,
    // что написал экран, и то, что написала остановка записи.
    final List<Map<String, Object?>> closes = <Map<String, Object?>>[
      for (final Map<String, Object?> event in kit.store.events(folder))
        if (event['type'] == 'book.close')
          event['data']! as Map<String, Object?>,
    ];
    expect(closes, hasLength(2));
    for (final Map<String, Object?> close in closes) {
      expect(close.keys, containsAll(<String>['read_ms', 'read_total_ms']));
    }
    expect(closes.first.containsKey('by'), isFalse);
    expect(closes.last['by'], 'stop');
    // Манифест различается только ветвью.
    expect(kit.store.json(folder, kRecordingFile)['branch'], Sno.branch);

    final List<String> actual = told(folder);
    final List<String> expected = golden();
    if (!listEquals(actual, expected)) {
      // Что вышло — целиком: эталон правят по этим строкам.
      for (final String line in actual) {
        debugPrint('ЭТАЛОН ${Sno.branch}: $line');
      }
    }
    expect(
      actual,
      expected,
      reason:
          'запись или тест разошлись с эталоном $goldenPath; что вышло '
          'в ветви ${Sno.branch} — в строках «ЭТАЛОН» выше',
    );

    await unmount(tester);
    // Основной прогон сценария не проходит: записи в нём нет, и
    // проверяется он прогонами ветвей (--dart-define=SNO_BRANCH=I, II).
  }, skip: !Sno.recording);

  test('SNO-F-REC-17: только ветвь II пишет события карты и подготовки '
      'книг — и больше никаких', () {
    expect(<String>[
      for (final SnoEventType type in kSecondBranchEvents) type.wire,
    ], everyElement(anyOf(startsWith('galaxy.'), equals('index.progress'))));
    // Всё, что названо событием карты или подготовки, в списке есть.
    for (final SnoEventType type in SnoEventType.values) {
      final bool screenOfSecond =
          type.wire.startsWith('galaxy.') || type.wire.startsWith('index.');
      expect(
        kSecondBranchEvents.contains(type),
        screenOfSecond,
        reason: type.wire,
      );
    }
    // Счёт времени в книгах — в обеих ветвях, в основном приложении
    // его нет.
    expect(Sno.bookTimes, Sno.enabled);
  });
}
