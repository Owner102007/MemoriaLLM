import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Паспорт устройства для сведений о записи (SNO-F-REC-13).
///
/// На чём записана сессия: производитель, модель, версия системы,
/// экран и масштаб шрифта. Участники приходят со своими телефонами, и
/// при разборе нужно знать, чей экран был вдвое уже и у кого буквы
/// стояли в полтора раза крупнее. Серийных номеров, рекламных и
/// прочих идентификаторов здесь нет: устройство в записи называет его
/// случайный код узла.
///
/// Чего устройство не отдало — того в паспорте нет; пустой паспорт —
/// тоже ответ.
typedef PassportSource = Future<Map<String, Object?>> Function();

/// Паспорт, в котором ничего нет: основное приложение и тесты.
Future<Map<String, Object?>> noPassport() async {
  return const <String, Object?>{};
}

/// Экран и масштаб шрифта — то, что знает сам Flutter.
///
/// Размер — в физических точках главного окна приложения: на телефоне
/// это экран, на ПК — окно, каким оно было в миг вопроса. Масштаб
/// шрифта — во сколько раз система увеличивает строку в 16 точек:
/// на новых Android он для разных кеглей разный, и одного числа у
/// системы нет.
Map<String, Object?> screenPassport(ui.FlutterView view) {
  final MediaQueryData media = MediaQueryData.fromView(view);
  return <String, Object?>{
    'screen': <String, Object?>{
      'width_px': view.physicalSize.width.round(),
      'height_px': view.physicalSize.height.round(),
      'density': _rounded(media.devicePixelRatio),
    },
    'font_scale': _rounded(media.textScaler.scale(16) / 16),
  };
}

/// Три знака после запятой: 2.625 остаётся собой, а 1.1500000953 —
/// становится 1.15.
double _rounded(double value) => (value * 1000).round() / 1000;

/// Паспорт устройства, на котором запущено приложение.
///
/// На телефоне производителя, модель и версию системы отдаёт канал
/// `memoria/device` (`passport` в `MainActivity`): Dart их не знает.
/// На ПК версию системы знает сам Dart, а производителя и модели у
/// компьютера, собранного из частей, может не быть вовсе — их там нет.
Future<Map<String, Object?>> platformPassport([
  MethodChannel channel = const MethodChannel('memoria/device'),
]) async {
  final Map<String, Object?> passport = <String, Object?>{};
  if (Platform.isAndroid) {
    try {
      final Map<String, Object?>? told = await channel
          .invokeMapMethod<String, Object?>('passport');
      if (told != null) {
        for (final MapEntry<String, Object?> field in told.entries) {
          final Object? value = field.value;
          if (value is String || value is int) {
            passport[field.key] = value;
          }
        }
      }
    } on PlatformException {
      // Паспорт без модели: запись от этого не зависит.
    } on MissingPluginException {
      // Канала нет — сборка без нашего кода платформы.
    }
    passport.putIfAbsent('os', () => 'Android');
  } else {
    passport['os'] = Platform.operatingSystem;
    passport['os_version'] = Platform.operatingSystemVersion;
  }
  final ui.FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view != null) {
    // Окна может ещё не быть: тогда паспорт без экрана.
    passport.addAll(screenPassport(view));
  }
  return passport;
}
