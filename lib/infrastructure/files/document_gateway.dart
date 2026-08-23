import 'package:flutter/services.dart';
import 'package:saf_util/saf_util.dart';

import 'uri_permissions.dart';

/// Документы Android глазами хранилища книг.
///
/// Узкий порт вокруг Storage Access Framework: ровно пять действий,
/// которые нужны книге, и ни одного лишнего. Благодаря ему хранилище
/// проверяется тестами на настоящих файловых дескрипторах, без телефона
/// и без платформенных каналов.
abstract interface class DocumentGateway {
  /// Длина документа в байтах или `null`, если документа больше нет,
  /// разрешение на него отозвано либо провайдер длины не знает.
  Future<int?> sizeOf(String uri);

  /// Открывает документ и возвращает номер файлового дескриптора.
  Future<int> openDescriptor(String uri);

  /// Закрывает дескриптор.
  Future<void> closeDescriptor(int descriptor);

  /// Закрепляет разрешение на чтение. `false` — провайдер не дал.
  Future<bool> persist(String uri);

  /// Отпускает закреплённое разрешение.
  Future<void> releasePersisted(String uri);
}

/// Порт поверх пакета `saf_util` и собственного канала разрешений.
///
/// Разрешение закрепляется своим каналом, а не пакетом: `saf_util`
/// закрепляет только папки, а нам нужен единственный документ. Всё
/// остальное — дескрипторы и сведения о документе — пакет умеет, и
/// переписывать это своей рукой было бы работой ради работы.
class SafDocumentGateway implements DocumentGateway {
  /// Создаёт порт.
  SafDocumentGateway({SafUtil? saf, UriPermissions? permissions})
    : _saf = saf ?? SafUtil(),
      _permissions = permissions ?? const UriPermissions();

  final SafUtil _saf;
  final UriPermissions _permissions;

  @override
  Future<int?> sizeOf(String uri) async {
    // `stat` возвращает null для того, чего больше нет: файл
    // переименовали, унесли карту памяти, отозвали разрешение. Это
    // состояние книги, а не ошибка, и бросаться исключением здесь
    // незачем.
    try {
      final SafDocumentFile? file = await _saf.stat(uri, false, throws: false);
      // Длину провайдер вправе не знать вовсе — тогда приходит -1.
      final int length = file?.length ?? -1;
      return length < 0 ? null : length;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<int> openDescriptor(String uri) => _saf.getFileDescriptor(uri);

  @override
  Future<void> closeDescriptor(int descriptor) =>
      _saf.closeFileDescriptor(descriptor);

  @override
  Future<bool> persist(String uri) => _permissions.persist(uri);

  @override
  Future<void> releasePersisted(String uri) => _permissions.release(uri);
}
