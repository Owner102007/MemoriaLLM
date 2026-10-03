import 'package:flutter/services.dart';

import '../../domain/reading/full_screen.dart';

/// Окно Windows во весь экран — через канал в `windows/runner`
/// (F-READ-35).
///
/// Своего плагина ради этого не заводится по той же причине, что и для
/// кнопок громкости: работы там на одну функцию — снять рамку окна и
/// поставить его на весь монитор, а новая зависимость потребовала бы
/// пересчитывать замок сборки.
///
/// Договор канала `memoria/window`: `setFullScreen` с признаком
/// «развернуть»; ответ — оказалось ли окно в запрошенном состоянии.
class WindowsFullScreen implements FullScreenWindow {
  /// Создаёт доступ к каналу.
  WindowsFullScreen([this._channel = const MethodChannel('memoria/window')]);

  final MethodChannel _channel;

  @override
  bool get available => true;

  @override
  Future<bool> setFullScreen(bool on) async {
    try {
      final bool? done = await _channel.invokeMethod<bool>('setFullScreen', on);
      return done ?? false;
    } on PlatformException {
      // Окно не развернулось. Чтение от этого не страдает: страница
      // остаётся в окне, как была.
      return false;
    } on MissingPluginException {
      // Канала нет — сборка без нашего `windows/runner`.
      return false;
    }
  }
}
