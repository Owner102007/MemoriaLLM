import 'package:flutter/services.dart';

/// Закреплённые разрешения на документы Android.
///
/// Канал ведёт в `MainActivity`: `takePersistableUriPermission` —
/// единственное, чего не умеют готовые пакеты, и заводить ради него
/// отдельный плагин было бы дороже, чем сам вызов.
///
/// Без закрепления ссылка живёт до конца процесса: читатель закрывает
/// приложение — и книга «пропадает» вместе с местом, на котором её
/// оставили. Ради этого одного шага вся затея с чтением по ссылке и
/// имеет смысл.
class UriPermissions {
  /// Создаёт доступ к каналу.
  const UriPermissions([
    this._channel = const MethodChannel('memoria/uri_permissions'),
  ]);

  final MethodChannel _channel;

  /// Закрепляет разрешение на чтение документа.
  ///
  /// Возвращает `false`, если провайдер закрепить не дал. Это не ошибка:
  /// книга откроется сейчас, но не переживёт перезапуск, и решение —
  /// копировать её к себе — принимает хранилище.
  Future<bool> persist(String uri) async {
    try {
      final Map<String, String> args = <String, String>{'uri': uri};
      return await _channel.invokeMethod<bool>('persist', args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Канала нет — значит, мы не на Android. Читать по ссылке там
      // всё равно нечего.
      return false;
    }
  }

  /// Отпускает закреплённое разрешение: книгу сняли с полки.
  Future<void> release(String uri) async {
    try {
      final Map<String, String> args = <String, String>{'uri': uri};
      await _channel.invokeMethod<bool>('release', args);
    } on PlatformException {
      // Разрешения уже нет — ровно то, чего мы и добивались.
    } on MissingPluginException {
      // Не Android.
    }
  }
}
