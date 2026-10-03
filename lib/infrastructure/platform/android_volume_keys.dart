import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/reading/volume_keys.dart';

/// Кнопки громкости Android — через канал в `MainActivity` (F-READ-26).
///
/// Своего плагина ради этого не заводится по той же причине, что и для
/// закреплённых ссылок: работы тут на один перехват `dispatchKeyEvent`.
///
/// Договор канала `memoria/volume_keys`:
///
/// * отсюда туда — `active` с признаком `active`: перехватывать ли
///   кнопки;
/// * оттуда сюда — `key` на каждое событие кнопки: `key` (`up` или
///   `down`), `pressed`, `repeat`, `canceled`. Ответ — `raise`, `lower`
///   или `none`: громкость по нашему слову меняет сама `MainActivity`.
class AndroidVolumeKeys implements VolumeKeys {
  /// Создаёт доступ к каналу.
  AndroidVolumeKeys([
    this._channel = const MethodChannel('memoria/volume_keys'),
  ]);

  final MethodChannel _channel;
  VolumeKeyHandler? _handler;

  @override
  void attach(VolumeKeyHandler handler) {
    _handler = handler;
    _channel.setMethodCallHandler(_onCall);
  }

  @override
  void detach(VolumeKeyHandler handler) {
    if (_handler != handler) {
      return;
    }
    _handler = null;
    _channel.setMethodCallHandler(null);
    // Получателя нет — и перехватывать не для кого: иначе кнопки
    // громкости замолчали бы вовсе.
    unawaited(_send(false));
  }

  @override
  Future<void> setActive(bool active) => _send(active);

  Future<void> _send(bool active) async {
    try {
      final Map<String, bool> args = <String, bool>{'active': active};
      await _channel.invokeMethod<void>('active', args);
    } on PlatformException {
      // Перехват не переключился. Хуже от этого не станет: на событие
      // кнопки мы всё равно ответим по текущему состоянию.
    } on MissingPluginException {
      // Канала нет — значит, мы не на Android.
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    final VolumeKeyHandler? handler = _handler;
    final VolumeKeyEvent? event = call.method == 'key'
        ? volumeKeyEventFrom(call.arguments)
        : null;
    if (handler == null || event == null) {
      throw MissingPluginException('memoria/volume_keys: ${call.method}');
    }
    return volumeKeyAnswer(handler(event));
  }
}

/// Разбирает событие кнопки, пришедшее по каналу; `null` — не разобрано.
VolumeKeyEvent? volumeKeyEventFrom(Object? arguments) {
  if (arguments is! Map<Object?, Object?>) {
    return null;
  }
  final Object? key = arguments['key'];
  final Object? pressed = arguments['pressed'];
  final Object? repeat = arguments['repeat'];
  if (pressed is! bool || (key != 'up' && key != 'down')) {
    return null;
  }
  return VolumeKeyEvent(
    key: key == 'up' ? VolumeKey.up : VolumeKey.down,
    pressed: pressed,
    repeat: repeat is int ? repeat : 0,
    canceled: arguments['canceled'] == true,
  );
}

/// Ответ `MainActivity`: что сделать с громкостью.
///
/// Листание в ответ не попадает — оно уже случилось здесь, в Dart.
String volumeKeyAnswer(VolumeKeyOutcome outcome) {
  switch (outcome) {
    case VolumeKeyOutcome.raise:
      return 'raise';
    case VolumeKeyOutcome.lower:
      return 'lower';
    case VolumeKeyOutcome.none:
    case VolumeKeyOutcome.forward:
    case VolumeKeyOutcome.back:
      return 'none';
  }
}
