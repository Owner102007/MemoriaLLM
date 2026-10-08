import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_window.dart';

import '../support/test_services.dart';

/// SNO-F-EYE-07, SNO-F-EYE-05: окно на монитор айтрекера — договор
/// с `windows/runner` по каналу `memoria/window`.
///
/// Пока окно под замком, чтению кнопки и клавиши «во весь экран» нет
/// (`available` — `false`): как экран чтения ведёт себя без неё, уже
/// проверяет `reader_full_screen_test.dart` («окна нет — кнопки нет,
/// F11 молчит»).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('memoria/window');
  final List<MethodCall> calls = <MethodCall>[];

  void answer(Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(calls.clear);
  tearDown(() => answer(null));

  final Map<Object?, Object?> locked = <Object?, Object?>{
    'monitor': r'\\.\DISPLAY2',
    'name': 'DELL P2419H',
    'found': true,
    'w_px': 1920,
    'h_px': 1080,
    'dpr': 1.25,
  };

  void platform() {
    answer((MethodCall call) async {
      calls.add(call);
      return switch (call.method) {
        'monitors' => <Object?>[
          <Object?, Object?>{
            'id': r'\\.\DISPLAY1',
            'name': '',
            'left': 0,
            'top': 0,
            'w_px': 2560,
            'h_px': 1440,
            'w_mm': 0,
            'h_mm': 0,
            'primary': true,
            'current': true,
          },
          <Object?, Object?>{
            'id': r'\\.\DISPLAY2',
            'name': 'DELL P2419H',
            'left': 2560,
            'top': 0,
            'w_px': 1920,
            'h_px': 1080,
            'w_mm': 527,
            'h_mm': 296,
            'primary': false,
            'current': false,
          },
          'мусор',
        ],
        'lock' => locked,
        'unlock' => true,
        _ => null,
      };
    });
  }

  test('SNO-F-EYE-05: мониторы — с размером и сведениями системы', () async {
    platform();
    final LockableWindow window = LockableWindow(FakeFullScreenWindow());
    final List<EyeMonitor> monitors = await window.monitors();
    expect(monitors, hasLength(2));
    expect(monitors.first.label, 'Монитор 1 · 2560×1440 · основной');
    expect(monitors.first.widthMm, isNull);
    expect(monitors.first.current, isTrue);
    expect(monitors.last.label, 'DELL P2419H · 1920×1080');
    expect(monitors.last.widthMm, 527);
    expect(monitors.last.left, 2560);
    await window.dispose();
  });

  test('SNO-F-EYE-07: под замком чтение окна не трогает', () async {
    platform();
    final FakeFullScreenWindow inner = FakeFullScreenWindow();
    final LockableWindow window = LockableWindow(inner);
    expect(window.available, isTrue);

    final EyeWindowLock lock = (await window.lock(r'\\.\DISPLAY2'))!;
    expect(calls.last.method, 'lock');
    expect(calls.last.arguments, r'\\.\DISPLAY2');
    expect(lock.toJson(), <String, Object?>{
      'monitor': r'\\.\DISPLAY2',
      'name': 'DELL P2419H',
      'found': true,
      'w_px': 1920,
      'h_px': 1080,
      'dpr': 1.25,
    });
    expect(window.locked, isTrue);
    // Кнопки и F11 нет; слово чтения до окна не доходит.
    expect(window.available, isFalse);
    expect(await window.setFullScreen(false), isFalse);
    expect(inner.requests, isEmpty);

    await window.unlock();
    expect(calls.last.method, 'unlock');
    expect(window.locked, isFalse);
    expect(window.available, isTrue);
    expect(await window.setFullScreen(true), isTrue);
    expect(inner.requests, <bool>[true]);
    // Снятый замок второй раз платформу не беспокоит.
    final int before = calls.length;
    await window.unlock();
    expect(calls, hasLength(before));
    await window.dispose();
  });

  test('SNO-F-EYE-07: монитор замка сменился — окно говорит об этом', () async {
    platform();
    final LockableWindow window = LockableWindow(FakeFullScreenWindow());
    final Completer<EyeWindowLock> changed = Completer<EyeWindowLock>();
    final StreamSubscription<EyeWindowLock> listening = window.changes.listen(
      changed.complete,
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'memoria/window',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('lockChanged', <Object?, Object?>{
              ...locked,
              'w_px': 1280,
              'found': false,
            }),
          ),
          (ByteData? reply) {},
        );
    final EyeWindowLock lock = await changed.future;
    expect(lock.widthPx, 1280);
    expect(lock.found, isFalse);
    await listening.cancel();
    await window.dispose();
  });

  test('SNO-F-EYE-07: платформа отказала или канала нет — замка нет', () async {
    answer((MethodCall call) async => null);
    final LockableWindow window = LockableWindow(FakeFullScreenWindow());
    expect(await window.lock(r'\\.\DISPLAY1'), isNull);
    expect(window.locked, isFalse);
    answer((MethodCall call) async => throw PlatformException(code: 'x'));
    expect(await window.lock(r'\\.\DISPLAY1'), isNull);
    expect(await window.monitors(), isEmpty);
    answer(null);
    expect(await window.lock(r'\\.\DISPLAY1'), isNull);
    expect(await window.monitors(), isEmpty);
    await window.dispose();
  });

  test('SNO-F-EYE-07: слова канала одни у Dart и у windows/runner', () {
    final String runner = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();
    for (final String word in <String>[
      '"memoria/window"',
      '"monitors"',
      '"lock"',
      '"unlock"',
      '"lockChanged"',
      '"monitor"',
      '"found"',
      '"w_px"',
      '"h_px"',
      '"w_mm"',
      '"h_mm"',
      '"dpr"',
      '"primary"',
      '"current"',
      'WM_WINDOWPOSCHANGING',
      'SC_MINIMIZE',
      'WM_DISPLAYCHANGE',
    ]) {
      expect(runner, contains(word), reason: word);
    }
  });
}
