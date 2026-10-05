import 'package:flutter/services.dart';

/// Что запись спрашивает у устройства (SNO-F-REC-01).
///
/// Заряд и свободное место — чтобы предупредить перед стартом; «экран
/// не гаснет» — чтобы сорок минут чтения не прерывались блокировкой.
abstract interface class DeviceStatus {
  /// Заряд батареи в процентах; `null` — батареи нет или не узнать.
  Future<int?> batteryPercent();

  /// Свободное место на диске, где лежит [path], в байтах; `null` — не
  /// узнать.
  Future<int?> freeBytes(String path);

  /// Держать ли экран включённым.
  Future<void> keepScreenOn(bool on);
}

/// Устройство, о котором ничего не известно: основное приложение и
/// тесты.
class NoDeviceStatus implements DeviceStatus {
  /// Создаёт заглушку.
  const NoDeviceStatus();

  @override
  Future<int?> batteryPercent() async => null;

  @override
  Future<int?> freeBytes(String path) async => null;

  @override
  Future<void> keepScreenOn(bool on) async {}
}

/// Устройство через канал `memoria/device` — в `MainActivity` на
/// Android и в `windows/runner` на ПК.
///
/// Своего плагина ради трёх вызовов системного API не заводится: новая
/// зависимость потребовала бы пересчитывать замок сборки. Договор
/// канала: `battery` → проценты или `null`; `freeBytes` с путём →
/// байты или `null`; `keepScreenOn` с признаком.
///
/// Ни один отказ канала записи не мешает: без ответа нет
/// предупреждения, и только.
class PlatformDeviceStatus implements DeviceStatus {
  /// Создаёт доступ к каналу.
  const PlatformDeviceStatus([
    this._channel = const MethodChannel('memoria/device'),
  ]);

  final MethodChannel _channel;

  @override
  Future<int?> batteryPercent() async {
    try {
      final int? percent = await _channel.invokeMethod<int>('battery');
      if (percent == null || percent < 0 || percent > 100) {
        return null;
      }
      return percent;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<int?> freeBytes(String path) async {
    try {
      final int? free = await _channel.invokeMethod<int>('freeBytes', path);
      return free == null || free < 0 ? null : free;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', on);
    } on PlatformException {
      // Экран может погаснуть; запись при этом идёт.
    } on MissingPluginException {
      // Канала нет — сборка без нашего кода платформы.
    }
  }
}
