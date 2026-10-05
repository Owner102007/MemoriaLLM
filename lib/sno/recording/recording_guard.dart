import 'package:flutter/services.dart';

/// Защита записи от выгрузки в фоне (SNO-F-REC-13).
///
/// Свёрнутое приложение Android вправе выгрузить в любой миг — и
/// запись оборвётся. Пока идёт запись, на телефоне работает служба
/// переднего плана: приложение с такой службой система ненужным не
/// считает. Разрешает она её только с постоянным уведомлением в
/// шторке — «Идёт запись», — и участник его видит.
///
/// Здесь только договор. Ни один отказ записи не мешает: без службы
/// запись идёт, как шла до неё, — журнал уходит на диск раз в секунду,
/// а оборванная запись закрывается при следующем запуске.
abstract interface class RecordingGuard {
  /// Есть ли у устройства такая защита: телефон — да, ПК — нет (там
  /// свёрнутое окно никто не выгружает).
  bool get guards;

  /// Разрешены ли приложению уведомления; `null` — спрашивать не о чем
  /// или система не ответила.
  Future<bool?> notificationsAllowed();

  /// Просит разрешение на уведомления системным окном. Отвечает,
  /// выдано ли; `null` — спрашивать не о чем или система не ответила.
  Future<bool?> askNotifications();

  /// Заводит службу с уведомлением: [title] — заголовок, [text] —
  /// строка под ним. Отвечает, заведена ли.
  Future<bool> hold({required String title, required String text});

  /// Снимает службу и уведомление.
  Future<void> release();
}

/// Устройство без защиты: ПК, основное приложение и тесты.
class NoRecordingGuard implements RecordingGuard {
  /// Создаёт заглушку.
  const NoRecordingGuard();

  @override
  bool get guards => false;

  @override
  Future<bool?> notificationsAllowed() async => null;

  @override
  Future<bool?> askNotifications() async => null;

  @override
  Future<bool> hold({required String title, required String text}) async {
    return false;
  }

  @override
  Future<void> release() async {}
}

/// Телефон: служба переднего плана `RecordingService` через канал
/// `memoria/guard` в `MainActivity`.
///
/// Своего плагина не заводится — та же причина, что у канала
/// `memoria/device`. Договор канала: `notifications` → разрешены ли
/// уведомления; `askNotifications` → выдано ли разрешение (ответ
/// приходит, когда системное окно закрыто); `hold` с `title` и `text`
/// → заведена ли служба; `release`.
///
/// Служба и её разрешения объявлены только в манифестах сборок ветвей
/// СНО2026: в основном приложении канал ответит «не заведена».
class AndroidRecordingGuard implements RecordingGuard {
  /// Создаёт доступ к каналу.
  const AndroidRecordingGuard([
    this._channel = const MethodChannel('memoria/guard'),
  ]);

  final MethodChannel _channel;

  @override
  bool get guards => true;

  @override
  Future<bool?> notificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('notifications');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool?> askNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('askNotifications');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> hold({required String title, required String text}) async {
    try {
      final bool? held = await _channel.invokeMethod<bool>(
        'hold',
        <String, Object?>{'title': title, 'text': text},
      );
      return held ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // Служба осталась: её снимет закрытие приложения.
    } on MissingPluginException {
      // Канала нет — сборка без нашего кода платформы.
    }
  }
}
