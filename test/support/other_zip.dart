import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Что чужая реализация ZIP увидела в архиве.
class OtherZip {
  /// Создаёт ответ.
  const OtherZip({
    required this.names,
    required this.sizes,
    required this.sha256,
    this.problem,
  });

  /// Имена записей в порядке оглавления.
  final List<String> names;

  /// Длины распакованных записей.
  final Map<String, int> sizes;

  /// SHA-256 распакованных записей шестнадцатеричной строкой.
  final Map<String, String> sha256;

  /// Что не так: имя записи с несошедшейся суммой или сообщение об
  /// ошибке; `null` — архив цел.
  final String? problem;
}

/// Читает архив модулем `zipfile` из Python: каждая запись
/// распаковывается, сверяется с её CRC-32, считаются длина и SHA-256.
const String _script = r'''
import hashlib
import json
import sys
import zipfile

out = {"problem": None, "names": [], "sizes": {}, "sha256": {}}
try:
    archive = zipfile.ZipFile(sys.argv[1])
    out["problem"] = archive.testzip()
    for info in archive.infolist():
        data = archive.read(info.filename)
        out["names"].append(info.filename)
        out["sizes"][info.filename] = len(data)
        out["sha256"][info.filename] = hashlib.sha256(data).hexdigest()
except Exception as error:
    out["problem"] = repr(error)
print(json.dumps(out))
''';

/// Открывает [archive] чужой реализацией ZIP — модулем `zipfile` из
/// Python (SNO-ALG-REC-03).
///
/// Свой читатель простил бы своему писателю общие ошибки; архив записи
/// открывают «Проводником» и разбором на Python, поэтому сверяет его
/// чужой код. `null` — Python на машине нет; в CI он есть всегда, и там
/// его отсутствие — отказ теста, а не пропуск.
Future<OtherZip?> readWithPython(File archive) async {
  for (final String python in const <String>['python3', 'python']) {
    final ProcessResult result;
    try {
      result = await Process.run(
        python,
        <String>['-c', _script, archive.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException {
      continue;
    }
    final String output = '${result.stdout}'.trim();
    if (result.exitCode != 0 || output.isEmpty) {
      // Заглушка на месте Python (Windows без него): пробуем другое имя.
      continue;
    }
    final Map<String, Object?> raw =
        jsonDecode(output) as Map<String, Object?>;
    final Object? problem = raw['problem'];
    return OtherZip(
      names: <String>[
        for (final Object? name in raw['names']! as List<Object?>)
          name! as String,
      ],
      sizes: <String, int>{
        for (final MapEntry<String, Object?> size
            in (raw['sizes']! as Map<String, Object?>).entries)
          size.key: size.value! as int,
      },
      sha256: <String, String>{
        for (final MapEntry<String, Object?> sum
            in (raw['sha256']! as Map<String, Object?>).entries)
          sum.key: sum.value! as String,
      },
      problem: problem == null ? null : '$problem',
    );
  }
  if (Platform.environment['CI'] == 'true') {
    fail('в CI нет Python: чужой реализацией архив не проверен');
  }
  return null;
}
