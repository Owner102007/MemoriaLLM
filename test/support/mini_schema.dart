/// Проверка JSON по схеме — ровно та часть JSON Schema, которой
/// пользуется `tool/sno_manifest.schema.json` (SNO-ALG-REC-03): `type`,
/// `const`, `enum`, `required`, `properties`, `additionalProperties`,
/// `items`, `pattern`, `minimum`.
///
/// Готового проверяющего в зависимостях нет, а заводить его ради одной
/// схемы значило бы править замок сборки. Ключ схемы, которого этот
/// код не знает, — ошибка теста, а не тихо пропущенное правило.
library;

const Set<String> _known = <String>{
  r'$schema',
  'title',
  'description',
  'type',
  'const',
  'enum',
  'required',
  'properties',
  'additionalProperties',
  'items',
  'pattern',
  'minimum',
};

bool _isType(Object? value, String type) {
  return switch (type) {
    'object' => value is Map<String, Object?>,
    'array' => value is List<Object?>,
    'string' => value is String,
    'integer' => value is int,
    'number' => value is num,
    'boolean' => value is bool,
    'null' => value == null,
    _ => throw ArgumentError('схема: неизвестный тип $type'),
  };
}

/// Чем [value] не сходится со схемой [schema]; пусто — сходится.
///
/// [path] — где в документе стоит значение: с него начинается каждая
/// строка ответа.
List<String> schemaProblems(
  Object? value,
  Map<String, Object?> schema, [
  String path = r'$',
]) {
  final List<String> problems = <String>[];
  for (final String key in schema.keys) {
    if (!_known.contains(key)) {
      throw ArgumentError('схема: проверка не знает ключа «$key» в $path');
    }
  }
  if (schema.containsKey('const') && schema['const'] != value) {
    problems.add('$path: ждали ${schema['const']}, стоит $value');
  }
  final Object? options = schema['enum'];
  if (options is List<Object?> && !options.contains(value)) {
    problems.add('$path: $value не из $options');
  }
  final Object? type = schema['type'];
  final List<String> types = <String>[
    if (type is String) type,
    if (type is List<Object?>)
      for (final Object? one in type) one! as String,
  ];
  if (types.isNotEmpty && !types.any((String one) => _isType(value, one))) {
    problems.add('$path: ждали $types, стоит ${value.runtimeType}');
    return problems;
  }
  final Object? pattern = schema['pattern'];
  if (pattern is String &&
      value is String &&
      !RegExp(pattern).hasMatch(value)) {
    problems.add('$path: «$value» не подходит под $pattern');
  }
  final Object? minimum = schema['minimum'];
  if (minimum is num && value is num && value < minimum) {
    problems.add('$path: $value меньше $minimum');
  }
  if (value is Map<String, Object?>) {
    final Object? required = schema['required'];
    if (required is List<Object?>) {
      for (final Object? key in required) {
        if (!value.containsKey(key)) {
          problems.add('$path: нет поля $key');
        }
      }
    }
    final Object? properties = schema['properties'];
    final Map<String, Object?> known = properties is Map<String, Object?>
        ? properties
        : const <String, Object?>{};
    final Object? rest = schema['additionalProperties'];
    for (final MapEntry<String, Object?> field in value.entries) {
      final Object? own = known[field.key];
      if (own is Map<String, Object?>) {
        problems.addAll(
          schemaProblems(field.value, own, '$path.${field.key}'),
        );
      } else if (rest is Map<String, Object?>) {
        problems.addAll(
          schemaProblems(field.value, rest, '$path.${field.key}'),
        );
      }
    }
  }
  final Object? items = schema['items'];
  if (value is List<Object?> && items is Map<String, Object?>) {
    for (int index = 0; index < value.length; index++) {
      problems.addAll(schemaProblems(value[index], items, '$path[$index]'));
    }
  }
  return problems;
}
