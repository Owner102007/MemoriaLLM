import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Объявление версии движка в хуке сборки пакета `pdfium_dart`.
final RegExp _hookRelease = RegExp(r"_pdfiumRelease\s*=\s*'([^']+)'");

const String _disagreeReason =
    'Версия PDFium записана в двух местах: у нас в tool/pdfium_version.txt '
    '(её берёт CI для корпус-тестов) и в хуке пакета pdfium_dart (он '
    'приносит движок в сборки). Разошлись — значит, тесты гоняют один '
    'движок, а телефон получает другой. Лечится правкой нашего файла под '
    'версию из замка, отдельной сессией подъёма.';

/// Согласие версии PDFium у нас и у пакета, который приносит её в сборки.
///
/// `tool/pdfium_version.txt` — единственное место, где версия написана
/// нами (S6.2.1). Вторая запись живёт в чужом пакете и приезжает вместе
/// с `pdfrx`, поэтому сверять их обязан автотест: руками это согласие
/// держалось с S3 и один раз уже разошлось бы незаметно.
///
/// Без `.dart_tool/package_config.json` проверять нечего — пакета нет на
/// диске; в CI он есть всегда, потому что тесты идут после `pub get`.
void main() {
  test('версия PDFium у нас и в хуке pdfium_dart совпадает', () {
    final File spec = File('tool/pdfium_version.txt');
    expect(spec.existsSync(), isTrue);
    final String text = spec.readAsStringSync();
    final String? release = _field(text, 'release');
    final String? sha256 = _field(text, 'sha256');
    final String? asset = _field(text, 'asset');
    expect(release, isNotNull, reason: 'нет поля release=');
    expect(asset, isNotNull, reason: 'нет поля asset=');
    expect(sha256, matches(r'^[0-9a-f]{64}$'), reason: 'сумма не SHA-256');

    final Uri? root = _packageRoot('pdfium_dart');
    if (root == null) {
      return;
    }
    final File hook = File.fromUri(root.resolve('hook/build.dart'));
    expect(hook.existsSync(), isTrue, reason: 'нет ${hook.path}');
    final String source = hook.readAsStringSync();
    final RegExpMatch? match = _hookRelease.firstMatch(source);
    expect(match, isNotNull, reason: 'в хуке не нашлось _pdfiumRelease');
    final String theirs = match!.group(1)!.replaceAll('%2F', '/');
    expect(theirs, release, reason: _disagreeReason);
  });
}

/// Значение поля `имя=значение` из `tool/pdfium_version.txt`.
String? _field(String text, String name) {
  final RegExp field = RegExp('^$name=(.+)\$', multiLine: true);
  return field.firstMatch(text)?.group(1)?.trim();
}

/// Корень пакета по данным `.dart_tool/package_config.json`.
Uri? _packageRoot(String name) {
  final File config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    return null;
  }
  final Object? parsed = jsonDecode(config.readAsStringSync());
  if (parsed is! Map<String, Object?>) {
    return null;
  }
  final Object? packages = parsed['packages'];
  if (packages is! List<Object?>) {
    return null;
  }
  for (final Object? entry in packages) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    if (entry['name'] != name) {
      continue;
    }
    final Object? root = entry['rootUri'];
    if (root is! String) {
      return null;
    }
    final String slashed = root.endsWith('/') ? root : '$root/';
    return config.uri.resolve(slashed);
  }
  return null;
}
