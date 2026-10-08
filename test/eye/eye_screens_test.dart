import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/application/data/app_data.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_tracker.dart';
import 'package:memoria/sno/eye/place_screen.dart';
import 'package:memoria/sno/eye/trial_screen.dart';
import 'package:memoria/sno/flags.dart';
import 'package:memoria/sno/recording/code_screen.dart';
import 'package:memoria/sno/settings_keys.dart';
import 'package:memoria/sno/testing_screen.dart';
import 'package:path/path.dart' as p;

import '../data/test_data.dart';
import '../support/fake_eye.dart';
import '../support/recording_fakes.dart';
import '../support/test_services.dart';

/// SNO-F-EYE-05: «Место записи» и его строка в «Тестировании».
///
/// Спутник, окно и часы подставные: экраны проверяются на всех исходах
/// самопроверки без камеры и без Windows.
void main() {
  late MemorySettings settings;
  late FakeQpc qpc;
  late FakeEyeLauncher launcher;
  late FakeEyeWindow window;
  late MemoryEyeFiles files;
  late EyeTracker eye;

  EyeTracker tracker() {
    return EyeTracker(
      settings: settings,
      launch: launcher.launch,
      qpc: qpc,
      window: window,
      dataFolder: () async => r'C:\Memoria',
      files: files,
      monotonicMs: () => 0,
      ticker: (Duration every, void Function() onTick) => () {},
      wait: (Duration pause) async {},
    );
  }

  setUp(() {
    settings = MemorySettings();
    qpc = FakeQpc();
    launcher = FakeEyeLauncher(make: (int n) => FakeEyeProcess(clock: qpc));
    window = FakeEyeWindow();
    files = MemoryEyeFiles();
    eye = tracker();
  });

  tearDown(() async {
    eye.dispose();
    await window.dispose();
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('SNO-F-EYE-05: экран «Место записи»', () {
    /// Экран открыт поверх начального, как из «Тестирования»: уходя,
    /// он закрывается, а не оставляет приложение без экрана.
    Future<void> pumpPlace(
      WidgetTester tester, {
      Future<bool> Function()? openSettings,
    }) async {
      // Окно повыше и без масштаба: все пять шагов на экране сразу, а
      // рамка карты — в физических пикселях.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return Center(
                child: TextButton(
                  key: const Key('open-place'),
                  onPressed: () {
                    unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) => EyePlaceScreen(
                            eye: eye,
                            openSettings: openSettings ?? () async => true,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Место записи'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-place')));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-EYE-05: камера, монитор, карта, расстояние, '
        'самопроверка — и место сохранено само', (WidgetTester tester) async {
      await pumpPlace(tester);

      // Окно встало на монитор, где оно стоит; спутник запущен.
      expect(window.locks, <String>[r'\\.\DISPLAY1']);
      expect(launcher.started, hasLength(1));
      expect(find.text('Integrated Camera'), findsOneWidget);
      expect(find.text('DELL P2419H · 1920×1080 · основной'), findsOneWidget);
      // Размер экрана — подсказка системы, пока не подогнали карту.
      expect(
        find.textContaining('527 × 296 мм (по сведениям системы)'),
        findsOneWidget,
      );
      // Сохранять нечего, пока место не проверено.
      expect(find.byKey(const Key('eye-place-saved')), findsNothing);
      expect(await settings.read(SnoSettingsKeys.eyePlace), isNull);

      await tapKey(tester, 'eye-place-card-plus');
      expect(find.textContaining('(по банковской карте)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('eye-place-distance')), '65');
      await tapKey(tester, 'eye-place-check');

      expect(find.byKey(const Key('eye-place-row-camera')), findsOneWidget);
      expect(find.byKey(const Key('eye-place-row-window')), findsOneWidget);
      expect(find.text('Окно на весь экран: 1920×1080'), findsOneWidget);
      expect(find.text('Итог: годится'), findsOneWidget);
      final Map<String, Object?> check = launcher.last.commands.last;
      expect(check['cmd'], 'selfcheck');
      expect(check['preview'], isTrue);
      // BUG-58: самопроверка места — в папке спутника, не в «Записях».
      expect(check['dir'], p.join(r'C:\Memoria', 'eye'));
      expect(check['camera'], <String, Object?>{
        'index': 0,
        'name': 'Integrated Camera',
        'path': r'\\?\usb#vid_0001',
      });

      // BUG-57: место сохранено без кнопки — сказано «Сохранено».
      expect(find.byKey(const Key('eye-place-saved')), findsOneWidget);
      final EyePlace place = EyePlace.decode(
        await settings.read(SnoSettingsKeys.eyePlace),
      )!;
      expect(place.camera.name, 'Integrated Camera');
      expect(place.monitor, r'\\.\DISPLAY1');
      expect(place.distanceMm, 650);
      expect(place.sizeSource, ScreenSizeSource.card);
      expect(place.mode, <int>[1920, 1080]);
      expect(place.verdict, EyeVerdict.good);
      expect(place.checks.map((EyeCheckRow r) => r.id), contains('window'));
      expect(place.pxPerMm, closeTo(1920 / 527 * 85.7 / 85.6, 1e-4));

      await tapKey(tester, 'eye-place-done');
      expect(find.byType(EyePlaceScreen), findsNothing);
      // Уходя, экран закрыл спутник и вернул окно.
      expect(launcher.last.inputClosed, isTrue);
      expect(window.locked, isFalse);
      await unmount(tester);
    });

    testWidgets('BUG-57: проверку унесли «назад» без кнопок — место с ней '
        'сохранено', (WidgetTester tester) async {
      // Прежнее место — проверка «не годится» в 720p.
      await eye.savePlace(
        EyePlace(
          camera: const EyeCamera(
            index: 0,
            name: 'Integrated Camera',
            path: r'\\?\usb#vid_0001',
          ),
          monitor: r'\\.\DISPLAY1',
          monitorName: 'DELL P2419H',
          widthPx: 1920,
          heightPx: 1080,
          pxPerMm: 1920 / 527,
          sizeSource: ScreenSizeSource.card,
          distanceMm: 600,
          verdict: EyeVerdict.fail,
          checkedAt: DateTime(2026, 10, 8, 18, 16),
          mode: const <int>[1280, 720],
          fps: 20,
        ),
      );
      await pumpPlace(tester);
      await tapKey(tester, 'eye-place-check');
      expect(find.text('Итог: годится'), findsOneWidget);

      // «Назад» — ни «Сохранить», ни «Готово».
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(EyePlaceScreen), findsNothing);

      final EyePlace place = EyePlace.decode(
        await settings.read(SnoSettingsKeys.eyePlace),
      )!;
      expect(place.verdict, EyeVerdict.good);
      expect(place.mode, <int>[1920, 1080]);
      expect(place.fps, closeTo(29.9, 1e-9));
      await unmount(tester);
    });

    testWidgets('BUG-57: расстояние после проверки — место с новым '
        'расстоянием; другая камера — место прежнее до новой проверки', (
      WidgetTester tester,
    ) async {
      launcher = FakeEyeLauncher(
        make: (int n) => FakeEyeProcess(
          clock: qpc,
          cameraList: <Map<String, Object?>>[
            <String, Object?>{
              'index': 0,
              'name': 'Integrated Camera',
              'path': r'\\?\usb#vid_0001',
            },
            <String, Object?>{
              'index': 1,
              'name': 'Logitech C920',
              'path': r'\\?\usb#vid_046d',
            },
          ],
        ),
      );
      eye.dispose();
      eye = tracker();
      await pumpPlace(tester);
      await tapKey(tester, 'eye-place-check');
      await tester.enterText(find.byKey(const Key('eye-place-distance')), '58');
      await tester.pumpAndSettle();
      EyePlace place = EyePlace.decode(
        await settings.read(SnoSettingsKeys.eyePlace),
      )!;
      expect(place.distanceMm, 580);
      expect(place.camera.name, 'Integrated Camera');

      // Другая камера: проверки нет, «Сохранено» снято, место прежнее.
      await tester.tap(find.byKey(const Key('eye-place-camera')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logitech C920').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('eye-place-saved')), findsNothing);
      await tester.enterText(find.byKey(const Key('eye-place-distance')), '62');
      await tester.pumpAndSettle();
      place = EyePlace.decode(await settings.read(SnoSettingsKeys.eyePlace))!;
      expect(place.camera.name, 'Integrated Camera');
      expect(place.distanceMm, 580);

      // Новая проверка — место с новой камерой.
      await tapKey(tester, 'eye-place-check');
      place = EyePlace.decode(await settings.read(SnoSettingsKeys.eyePlace))!;
      expect(place.camera.name, 'Logitech C920');
      expect(place.distanceMm, 620);
      await unmount(tester);
    });

    testWidgets('BUG-58: под картинкой сказано, что она редкая; «720p не '
        'прибавил» — словами', (WidgetTester tester) async {
      launcher = FakeEyeLauncher(
        make: (int n) => FakeEyeProcess(
          clock: qpc,
          preview: true,
          stages: const <String>['warmup', 'measure', 'switch', 'keep'],
        ),
      );
      eye.dispose();
      eye = tracker();
      await pumpPlace(tester);
      await tapKey(tester, 'eye-place-check');
      expect(find.byKey(const Key('eye-place-preview')), findsOneWidget);
      expect(
        find.text(
          'Картинка — 5 кадров в секунду; частоту камеры показывает строка '
          '«Частота».',
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-05: камера запрещена — словами и кнопкой '
        'параметров', (WidgetTester tester) async {
      launcher = FakeEyeLauncher(
        make: (int n) => FakeEyeProcess(
          clock: qpc,
          check: <String, Object?>{
            'verdict': 'fail',
            'checks': <Object?>[
              <String, Object?>{
                'id': 'satellite',
                'verdict': 'good',
                'value': true,
                'text': 'Спутник запущен',
              },
              <String, Object?>{
                'id': 'camera',
                'verdict': 'fail',
                'value': 'camera_denied',
                'text':
                    'Камера запрещена в параметрах Windows — разрешите '
                    'классическим приложениям доступ к камере',
              },
            ],
            'measures': <String, Object?>{'camera': 'camera_denied'},
          },
        ),
      );
      eye.dispose();
      eye = tracker();
      int opened = 0;
      await pumpPlace(
        tester,
        openSettings: () async {
          opened++;
          return true;
        },
      );
      await tapKey(tester, 'eye-place-check');

      expect(
        find.textContaining('Камера запрещена в параметрах Windows'),
        findsOneWidget,
      );
      expect(find.text('Итог: не годится'), findsOneWidget);
      await tapKey(tester, 'eye-place-settings');
      expect(opened, 1);
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-05, BUG-58: темно — словами спутника', (
      WidgetTester tester,
    ) async {
      launcher = FakeEyeLauncher(
        make: (int n) => FakeEyeProcess(
          clock: qpc,
          check: <String, Object?>{
            'verdict': 'fail',
            'checks': <Object?>[
              <String, Object?>{
                'id': 'fps',
                'verdict': 'fail',
                'value': 20.0,
                'text':
                    'Камера сама даёт 20.0 к/с — ей мало света: поставьте '
                    'лампу перед лицом',
              },
            ],
          },
        ),
      );
      eye.dispose();
      eye = tracker();
      await pumpPlace(tester);
      await tapKey(tester, 'eye-place-check');
      expect(
        find.text(
          'Камера сама даёт 20.0 к/с — ей мало света: поставьте лампу перед '
          'лицом',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('eye-place-settings')), findsNothing);
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-05: спутник не запустился — сказано, можно ещё '
        'раз', (WidgetTester tester) async {
      launcher.failWith = const EyeError('no_satellite', 'нет eye');
      await pumpPlace(tester);
      expect(
        find.text('Айтрекер не запустился: рядом с приложением нет папки eye'),
        findsOneWidget,
      );
      launcher.failWith = null;
      await tapKey(tester, 'eye-place-retry');
      expect(find.text('Integrated Camera'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-05: диагональ — запасной путь размера', (
      WidgetTester tester,
    ) async {
      await pumpPlace(tester);
      await tester.enterText(find.byKey(const Key('eye-place-diagonal')), '3');
      await tapKey(tester, 'eye-place-diagonal-apply');
      expect(find.text('Диагональ — от 7 до 100 дюймов'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('eye-place-diagonal')),
        '23,8',
      );
      await tapKey(tester, 'eye-place-diagonal-apply');
      expect(
        find.textContaining('527 × 296 мм (по диагонали)'),
        findsOneWidget,
      );
      await unmount(tester);
    });
  });

  group('SNO-F-EYE-05: строка в «Тестировании» и старт записи', () {
    late AppData data;
    late SessionKit kit;

    setUp(() async {
      data = await openTestData();
      kit = SessionKit();
      eye.attach(kit.session);
    });

    tearDown(() async {
      kit.session.dispose();
      await data.close();
    });

    Future<void> pumpTesting(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TestingScreen(
            services: testServices(
              data: data,
              recording: kit.session,
              eye: eye,
            ),
            flags: BranchFlags.of('I'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Для экспериментатора'));
      await tester.pumpAndSettle();
    }

    testWidgets('SNO-F-EYE-05: место не задано — так и сказано, и старт '
        'предупреждает', (WidgetTester tester) async {
      await eye.loadPlace();
      await pumpTesting(tester);

      expect(find.text('Место записи (айтрекер)'), findsOneWidget);
      expect(find.text('не задано'), findsOneWidget);
      expect(find.byKey(const Key('sno-record-eye')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sno-record-start')));
      await tester.pumpAndSettle();
      expect(find.byType(ParticipantCodeScreen), findsOneWidget);
      expect(
        find.text('Айтрекер не настроен — запись пойдёт без взгляда.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('sno-code-cancel')));
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-03: «Проверка айтрекера» — без места не '
        'открывается, с местом — открывается', (WidgetTester tester) async {
      await eye.loadPlace();
      await pumpTesting(tester);
      final Finder tile = find.byKey(const Key('sno-eye-trial'));
      expect(tile, findsOneWidget);
      expect(find.text('Сначала задайте место записи'), findsOneWidget);
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
      await unmount(tester);

      await eye.savePlace(
        EyePlace(
          camera: const EyeCamera(index: 0, name: 'Logitech C920'),
          monitor: r'\\.\DISPLAY1',
          monitorName: 'DELL P2419H',
          widthPx: 1920,
          heightPx: 1080,
          pxPerMm: 1920 / 527,
          sizeSource: ScreenSizeSource.card,
          distanceMm: 600,
          verdict: EyeVerdict.good,
          checkedAt: DateTime(2026, 10, 8, 12),
          mode: const <int>[1920, 1080],
          fps: 30,
        ),
      );
      await pumpTesting(tester);
      expect(find.text('Калибровка и живой взгляд на себе'), findsOneWidget);
      expect(tester.widget<ListTile>(tile).enabled, isTrue);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      await tester.pump();
      expect(find.byType(EyeTrialScreen), findsOneWidget);
      expect(eye.trial.value, isNotNull);
      await eye.closeTrial();
      await tester.pump();
      await tester.pump();
      expect(find.byType(EyeTrialScreen), findsNothing);
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-03: место «не годится» — проверка не '
        'открывается и сказано почему', (WidgetTester tester) async {
      await eye.savePlace(
        EyePlace(
          camera: const EyeCamera(index: 0, name: 'Logitech C920'),
          monitor: r'\\.\DISPLAY1',
          monitorName: 'DELL P2419H',
          widthPx: 1920,
          heightPx: 1080,
          pxPerMm: 1920 / 527,
          sizeSource: ScreenSizeSource.card,
          distanceMm: 600,
          verdict: EyeVerdict.fail,
          checkedAt: DateTime(2026, 10, 8, 12),
        ),
      );
      await pumpTesting(tester);
      expect(
        find.text('Место записи не годится — проверьте его ещё раз'),
        findsOneWidget,
      );
      expect(
        tester.widget<ListTile>(find.byKey(const Key('sno-eye-trial'))).enabled,
        isFalse,
      );
      await unmount(tester);
    });

    testWidgets('SNO-F-EYE-05: место задано — его строка, без '
        'предупреждения', (WidgetTester tester) async {
      await eye.savePlace(
        EyePlace(
          camera: const EyeCamera(index: 0, name: 'Logitech C920'),
          monitor: r'\\.\DISPLAY1',
          monitorName: 'DELL P2419H',
          widthPx: 1920,
          heightPx: 1080,
          pxPerMm: 1920 / 527,
          sizeSource: ScreenSizeSource.card,
          distanceMm: 600,
          verdict: EyeVerdict.good,
          checkedAt: DateTime(2026, 10, 8, 12),
          mode: const <int>[1920, 1080],
          fps: 30,
        ),
      );
      await pumpTesting(tester);

      expect(
        find.text(
          'камера Logitech C920, 1920×1080, 30 к/с; экран 527×296 мм; '
          '60 см; проверено 08.10',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sno-record-eye')), findsNothing);
      await tester.tap(find.byKey(const Key('sno-record-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Айтрекер не настроен'), findsNothing);
      await tester.tap(find.byKey(const Key('sno-code-cancel')));
      await tester.pumpAndSettle();
      await unmount(tester);
    });
  });
}
