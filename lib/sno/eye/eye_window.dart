/// Окно записи на весь монитор айтрекера и мониторы для «Места записи»
/// (SNO-F-EYE-07, SNO-F-EYE-05).
///
/// Точки калибровки и кадры раскладки заданы в пикселях окна; если окно
/// сдвинуть или сузить, взгляд перестаёт соответствовать экрану. Поэтому
/// с «Код записан» и до остановки записи окно стоит на весь выбранный
/// монитор под замком: `Esc`, `F11`, двойное нажатие по заголовку и
/// `Win+↓` его размера не меняют.
///
/// Разворачивает и держит окно `windows/runner` по каналу
/// `memoria/window` (`monitors`, `lock`, `unlock`, сообщение
/// `lockChanged`); когда — решает Dart. Договор [EyeWindow] позволяет
/// проверять это на подменённом окне.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/reading/full_screen.dart';

/// Монитор, как его назвала система.
class EyeMonitor {
  /// Создаёт монитор.
  const EyeMonitor({
    required this.id,
    required this.name,
    required this.widthPx,
    required this.heightPx,
    this.left = 0,
    this.top = 0,
    this.widthMm,
    this.heightMm,
    this.primary = false,
    this.current = false,
  });

  /// Монитор из ответа платформы; `null` — ответ не о мониторе.
  static EyeMonitor? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? w = raw['w_px'];
    final Object? h = raw['h_px'];
    if (id is! String || id.isEmpty || w is! int || h is! int) {
      return null;
    }
    int? mm(Object? value) => value is int && value > 0 ? value : null;
    final Object? name = raw['name'];
    final Object? left = raw['left'];
    final Object? top = raw['top'];
    return EyeMonitor(
      id: id,
      name: name is String ? name : '',
      widthPx: w,
      heightPx: h,
      left: left is int ? left : 0,
      top: top is int ? top : 0,
      widthMm: mm(raw['w_mm']),
      heightMm: mm(raw['h_mm']),
      primary: raw['primary'] == true,
      current: raw['current'] == true,
    );
  }

  /// Имя устройства: `\\.\DISPLAY1`.
  final String id;

  /// Имя, каким его называет сам монитор; может быть пустым.
  final String name;

  /// Ширина в физических пикселях.
  final int widthPx;

  /// Высота в физических пикселях.
  final int heightPx;

  /// Левый край на рабочем столе, пикселей.
  final int left;

  /// Верхний край на рабочем столе, пикселей.
  final int top;

  /// Ширина экрана по сведениям системы, мм; `null` — система не знает.
  final int? widthMm;

  /// Высота экрана по сведениям системы, мм.
  final int? heightMm;

  /// Основной ли это монитор.
  final bool primary;

  /// Стоит ли на нём окно приложения сейчас.
  final bool current;

  /// Монитор словами: «DELL P2419H · 1920×1080».
  String get label {
    final String size = '$widthPx×$heightPx';
    final String title = name.isNotEmpty ? name : 'Монитор ${_number(id)}';
    return '$title · $size${primary ? ' · основной' : ''}';
  }

  static String _number(String id) {
    final Match? m = RegExp(r'(\d+)$').firstMatch(id);
    return m == null ? id : m.group(1)!;
  }
}

/// Окно под замком: на каком мониторе и какого оно размера.
class EyeWindowLock {
  /// Создаёт ответ.
  const EyeWindowLock({
    required this.monitor,
    required this.name,
    required this.found,
    required this.widthPx,
    required this.heightPx,
    required this.dpr,
  });

  /// Ответ из сообщения платформы; `null` — сообщение не о замке.
  static EyeWindowLock? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return null;
    }
    final Object? monitor = raw['monitor'];
    final Object? w = raw['w_px'];
    final Object? h = raw['h_px'];
    final Object? dpr = raw['dpr'];
    final Object? name = raw['name'];
    if (monitor is! String || w is! int || h is! int) {
      return null;
    }
    return EyeWindowLock(
      monitor: monitor,
      name: name is String ? name : '',
      found: raw['found'] == true,
      widthPx: w,
      heightPx: h,
      dpr: dpr is num && dpr > 0 ? dpr.toDouble() : 1,
    );
  }

  /// Монитор, на котором стоит окно.
  final String monitor;

  /// Его имя.
  final String name;

  /// Нашёлся ли выбранный монитор. Нет — окно встало на тот, где
  /// стояло, и место записи надо проверить.
  final bool found;

  /// Ширина окна в физических пикселях.
  final int widthPx;

  /// Высота окна в физических пикселях.
  final int heightPx;

  /// Масштаб Windows: физических пикселей на логический.
  final double dpr;

  /// Для журнала (`eye.window`) и сведений записи.
  Map<String, Object?> toJson() => <String, Object?>{
    'monitor': monitor,
    'name': name,
    'found': found,
    'w_px': widthPx,
    'h_px': heightPx,
    'dpr': dpr,
  };
}

/// Окно, которое айтрекер ставит на монитор и держит там.
abstract interface class EyeWindow {
  /// Мониторы системы; пусто — платформа не ответила.
  Future<List<EyeMonitor>> monitors();

  /// Ставит окно на весь монитор [monitor] под замок; `null` —
  /// платформа отказала.
  Future<EyeWindowLock?> lock(String monitor);

  /// Снимает замок и возвращает окну прежний вид.
  Future<void> unlock();

  /// Стоит ли окно под замком.
  bool get locked;

  /// Монитор замка сменился: сменили разрешение, отключили монитор.
  Stream<EyeWindowLock> get changes;
}

/// Окно приложения на ПК: чтение во весь экран (F-READ-35) и замок
/// айтрекера (SNO-F-EYE-07) — по одному каналу.
///
/// Пока окно под замком, кнопки и клавиши чтения во весь экран нет
/// ([available] — `false`): окно и так на весь экран, а `Esc` и `F11`
/// не выводят его из полного экрана.
class LockableWindow implements FullScreenWindow, EyeWindow {
  /// Создаёт окно поверх [inner] — разворота для чтения.
  LockableWindow(
    this._inner, [
    this._channel = const MethodChannel('memoria/window'),
  ]) {
    _channel.setMethodCallHandler(_onCall);
  }

  final FullScreenWindow _inner;
  final MethodChannel _channel;
  final StreamController<EyeWindowLock> _changes =
      StreamController<EyeWindowLock>.broadcast();
  bool _locked = false;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'lockChanged') {
      final EyeWindowLock? lock = EyeWindowLock.fromJson(call.arguments);
      if (lock != null) {
        _changes.add(lock);
      }
    }
    return null;
  }

  @override
  bool get available => _inner.available && !_locked;

  @override
  Future<bool> setFullScreen(bool on) async {
    if (_locked) {
      return false;
    }
    return _inner.setFullScreen(on);
  }

  @override
  bool get locked => _locked;

  @override
  Stream<EyeWindowLock> get changes => _changes.stream;

  @override
  Future<List<EyeMonitor>> monitors() async {
    try {
      final List<Object?>? raw = await _channel.invokeListMethod<Object?>(
        'monitors',
      );
      return <EyeMonitor>[
        for (final Object? item in raw ?? const <Object?>[])
          ?EyeMonitor.fromJson(item),
      ];
    } on PlatformException {
      return const <EyeMonitor>[];
    } on MissingPluginException {
      return const <EyeMonitor>[];
    }
  }

  @override
  Future<EyeWindowLock?> lock(String monitor) async {
    try {
      final EyeWindowLock? lock = EyeWindowLock.fromJson(
        await _channel.invokeMethod<Object?>('lock', monitor),
      );
      _locked = lock != null;
      return lock;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Закрывает поток [changes]: окно приложения живёт до его конца,
  /// и закрывают его только тесты.
  Future<void> dispose() => _changes.close();

  @override
  Future<void> unlock() async {
    if (!_locked) {
      return;
    }
    _locked = false;
    try {
      await _channel.invokeMethod<Object?>('unlock');
    } on PlatformException {
      // Окно не вернулось — запись от этого не страдает.
    } on MissingPluginException {
      // Канала нет — сборка без нашего `windows/runner`.
    }
  }
}
