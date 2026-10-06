/// Сценарий теста нагрузки как данные (SNO-F-CLT-02).
///
/// Что спрашивается у участника исследования СНО2026 и в каком порядке,
/// задаёт не код, а сценарий `sno2026-clt/1`: части (после блока и в
/// конце сессии), разделы и пункты. Пункт одного вида — шкала с
/// делениями и подписями краёв; сценарий с другим видом пункта
/// отвергается целиком, а не показывается наполовину.
///
/// Состав теста и формулировки — в описательной структуре, заметка
/// «Cognitive load test — состав теста». Встроенный сценарий —
/// `builtin_scenario.dart`.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода.
library;

/// Версия формата сценария.
const String kCltScenarioSchema = 'sno2026-clt/1';

/// Часть показывается, когда экспериментатор закончил блок.
const String kCltBlockEnd = 'block_end';

/// Часть показывается в конце сессии, после остановки записи.
const String kCltSessionEnd = 'session_end';

/// Единственный вид пункта: шкала с делениями.
const String kCltScaleType = 'likert';

/// Больше делений у шкалы не бывает: 0…100 с шагом 1.
const int kCltMaxDivisions = 101;

/// Почему сценарий не принят.
class CltScenarioException implements Exception {
  /// Создаёт отказ.
  const CltScenarioException(this.reason);

  /// Причина словами — для экспериментатора.
  final String reason;

  @override
  String toString() => 'CltScenarioException($reason)';
}

/// Шкала пункта: деления от [min] до [max] с шагом [step].
class CltScale {
  /// Создаёт шкалу.
  const CltScale({
    required this.min,
    required this.max,
    required this.step,
    this.labels = const <int, String>{},
  });

  /// Наименьшее значение.
  final int min;

  /// Наибольшее значение.
  final int max;

  /// Шаг между делениями.
  final int step;

  /// Подписи делений: значение → слова. Обычно подписаны края.
  final Map<int, String> labels;

  /// Сколько у шкалы делений.
  int get divisions => (max - min) ~/ step + 1;

  /// Значения делений по порядку.
  List<int> get values {
    return <int>[for (int value = min; value <= max; value += step) value];
  }

  /// Есть ли у шкалы деление [value].
  bool holds(int value) {
    return value >= min && value <= max && (value - min) % step == 0;
  }

  /// Значение [value] на перевёрнутой шкале: у пункта с обратным
  /// счётом «совершенно верно» значит наименьшее.
  int mirrored(int value) => min + max - value;
}

/// Пункт теста: вопрос или утверждение и шкала к нему.
class CltItem {
  /// Создаёт пункт.
  const CltItem({
    required this.id,
    required this.text,
    required this.scale,
    this.reverse = false,
  });

  /// Идентификатор: `tlx.mental`, `ecl.2`.
  final String id;

  /// Что написано на экране.
  final String text;

  /// Шкала.
  final CltScale scale;

  /// Считается ли пункт наоборот.
  final bool reverse;

  /// Группа пункта — его идентификатор до последней точки: `tlx`,
  /// `ecl`. Показатели считаются по группам (`results.dart`).
  String get group => cltGroupOf(id);
}

/// Группа пункта [id]: всё до последней точки; точки нет — сам [id].
String cltGroupOf(String id) {
  final int dot = id.lastIndexOf('.');
  return dot <= 0 ? id : id.substring(0, dot);
}

/// Раздел части: пункты с общей шкалой.
class CltSection {
  /// Создаёт раздел.
  const CltSection({
    required this.id,
    required this.items,
    this.title,
    this.shuffle = false,
  });

  /// Идентификатор раздела.
  final String id;

  /// Название раздела; участнику не показывается.
  final String? title;

  /// Перемешиваются ли пункты раздела — одинаково для одного кода
  /// участника.
  final bool shuffle;

  /// Пункты в порядке сценария.
  final List<CltItem> items;
}

/// Часть теста: то, что проходится за один раз.
class CltPart {
  /// Создаёт часть.
  const CltPart({
    required this.id,
    required this.when,
    required this.password,
    required this.sections,
  });

  /// Идентификатор части: `A`, `B`.
  final String id;

  /// Когда часть показывается: [kCltBlockEnd] или [kCltSessionEnd].
  final String when;

  /// Нужен ли пароль экспериментатора.
  final bool password;

  /// Разделы по порядку.
  final List<CltSection> sections;

  /// Сколько в части пунктов.
  int get length {
    int count = 0;
    for (final CltSection section in sections) {
      count += section.items.length;
    }
    return count;
  }
}

/// Сценарий теста.
class CltScenario {
  /// Создаёт сценарий.
  const CltScenario({
    required this.id,
    required this.version,
    required this.parts,
    this.lang,
  });

  /// Идентификатор сценария.
  final String id;

  /// Версия сценария: поднимается, когда меняются пункты.
  final int version;

  /// Язык формулировок.
  final String? lang;

  /// Части по порядку.
  final List<CltPart> parts;

  /// Часть, которая показывается в миг [when]; `null` — такой нет.
  CltPart? partFor(String when) {
    for (final CltPart part in parts) {
      if (part.when == when) {
        return part;
      }
    }
    return null;
  }
}

Never _refuse(String reason) => throw CltScenarioException(reason);

Map<String, Object?> _object(Object? raw, String what) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  return _refuse('$what — не объект');
}

List<Object?> _list(Object? raw, String what) {
  if (raw is List<Object?> && raw.isNotEmpty) {
    return raw;
  }
  return _refuse('$what — не список или список пуст');
}

/// Идентификатор, который годится в имя файла: по идентификаторам
/// сценария и части называется файл ответов (`results.dart`), а знак
/// пути в имени увёл бы его мимо подпапки теста.
final RegExp _fileSafe = RegExp(r'^[A-Za-z0-9._-]+$');

String _name(Object? raw, String what) {
  final String name = _text(raw, what);
  if (!_fileSafe.hasMatch(name) || name.startsWith('.')) {
    _refuse('$what «$name» — не из латинских букв, цифр, точки, '
        'дефиса и подчёркивания');
  }
  return name;
}

String _text(Object? raw, String what) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  return _refuse('$what — не строка или строка пуста');
}

bool _flag(Object? raw, String what) {
  if (raw == null) {
    return false;
  }
  if (raw is bool) {
    return raw;
  }
  return _refuse('$what — не «да» и не «нет»');
}

/// Шкала из полей [own], недостающее — из общей шкалы [shared].
CltScale _scale(
  Map<String, Object?> own,
  Map<String, Object?>? shared,
  String what,
) {
  Object? pick(String key) => own[key] ?? shared?[key];
  final Object? type = pick('type');
  if (type == null) {
    _refuse('$what: не назван вид пункта');
  }
  if (type != kCltScaleType) {
    _refuse('$what: неизвестный вид пункта «$type»');
  }
  final Object? min = pick('min');
  final Object? max = pick('max');
  final Object step = pick('step') ?? 1;
  if (min is! int || max is! int || step is! int) {
    _refuse('$what: края и шаг шкалы — не целые числа');
  }
  if (min >= max || step < 1 || (max - min) % step != 0) {
    _refuse('$what: шкала от $min до $max с шагом $step не складывается');
  }
  if ((max - min) ~/ step + 1 > kCltMaxDivisions) {
    _refuse('$what: у шкалы больше $kCltMaxDivisions делений');
  }
  final CltScale bare = CltScale(min: min, max: max, step: step);
  final Map<int, String> labels = <int, String>{};
  for (final Object? source in <Object?>[shared?['labels'], own['labels']]) {
    if (source == null) {
      continue;
    }
    for (final MapEntry<String, Object?> label in _object(
      source,
      '$what: подписи шкалы',
    ).entries) {
      final int? value = int.tryParse(label.key);
      if (value == null || !bare.holds(value)) {
        _refuse('$what: подпись «${label.key}» стоит не на делении шкалы');
      }
      labels[value] = _text(label.value, '$what: подпись ${label.key}');
    }
  }
  return CltScale(
    min: min,
    max: max,
    step: step,
    labels: Map<int, String>.unmodifiable(labels),
  );
}

List<CltItem> _items(
  Object? raw,
  Map<String, Object?>? shared,
  String where,
  Set<String> known,
) {
  final List<CltItem> items = <CltItem>[];
  for (final Object? entry in _list(raw, '$where: пункты')) {
    final Map<String, Object?> item = _object(entry, '$where: пункт');
    final String id = _text(item['id'], '$where: идентификатор пункта');
    if (!known.add(id)) {
      _refuse('пункт «$id» встречается дважды');
    }
    items.add(
      CltItem(
        id: id,
        text: _text(item['text'], 'пункт «$id»: текст'),
        scale: _scale(item, shared, 'пункт «$id»'),
        reverse: _flag(item['reverse'], 'пункт «$id»: обратный счёт'),
      ),
    );
  }
  return List<CltItem>.unmodifiable(items);
}

/// Разбирает сценарий из разобранного JSON [raw] (SNO-F-CLT-02).
///
/// Сценарий принимается целиком или не принимается вовсе: незнакомая
/// версия формата, неизвестный вид пункта, шкала, которая не
/// складывается, повтор идентификатора — [CltScenarioException] с
/// причиной словами. Тест с таким сценарием не начинается.
CltScenario parseCltScenario(Object? raw) {
  final Map<String, Object?> root = _object(raw, 'сценарий');
  final Object? schema = root['schema'];
  if (schema != kCltScenarioSchema) {
    _refuse('формат сценария «$schema», а нужен «$kCltScenarioSchema»');
  }
  final String id = _name(root['id'], 'идентификатор сценария');
  final Object? version = root['version'];
  if (version is! int || version < 1) {
    _refuse('версия сценария — не целое число от единицы');
  }
  final Object? lang = root['lang'];
  final Set<String> partIds = <String>{};
  final Set<String> itemIds = <String>{};
  final List<CltPart> parts = <CltPart>[];
  for (final Object? entry in _list(root['parts'], 'части сценария')) {
    final Map<String, Object?> part = _object(entry, 'часть сценария');
    final String partId = _name(part['id'], 'идентификатор части');
    if (!partIds.add(partId)) {
      _refuse('часть «$partId» встречается дважды');
    }
    final Object? when = part['when'];
    if (when != kCltBlockEnd && when != kCltSessionEnd) {
      _refuse('часть «$partId»: неизвестно, когда её показывать («$when»)');
    }
    for (final CltPart other in parts) {
      if (other.when == when) {
        _refuse('части «${other.id}» и «$partId» показываются в один миг');
      }
    }
    final List<CltSection> sections = <CltSection>[];
    if (part['sections'] != null) {
      final Set<String> sectionIds = <String>{};
      for (final Object? one in _list(
        part['sections'],
        'часть «$partId»: разделы',
      )) {
        final Map<String, Object?> section = _object(one, 'раздел');
        final String sectionId = _text(section['id'], 'идентификатор раздела');
        if (!sectionIds.add(sectionId)) {
          _refuse('раздел «$sectionId» встречается дважды');
        }
        final Object? shared = section['scale'];
        final Object? title = section['title'];
        sections.add(
          CltSection(
            id: sectionId,
            title: title is String ? title : null,
            shuffle: _flag(section['shuffle'], 'раздел «$sectionId»: порядок'),
            items: _items(
              section['items'],
              shared == null ? null : _object(shared, 'шкала раздела'),
              'раздел «$sectionId»',
              itemIds,
            ),
          ),
        );
      }
    } else {
      sections.add(
        CltSection(
          id: partId,
          items: _items(part['items'], null, 'часть «$partId»', itemIds),
        ),
      );
    }
    final bool password = _flag(part['password'], 'часть «$partId»: пароль');
    if (password && when == kCltBlockEnd) {
      // Блок закрывает экспериментатор посреди записи, а замок теста
      // открывается только после её остановки: вопрос под паролем не
      // показался бы никогда.
      _refuse('часть «$partId» показывается после блока и не может быть '
          'под паролем');
    }
    parts.add(
      CltPart(
        id: partId,
        when: when == kCltBlockEnd ? kCltBlockEnd : kCltSessionEnd,
        password: password,
        sections: List<CltSection>.unmodifiable(sections),
      ),
    );
  }
  return CltScenario(
    id: id,
    version: version,
    lang: lang is String ? lang : null,
    parts: List<CltPart>.unmodifiable(parts),
  );
}

const int _mask = 0xFFFFFFFF;

/// Зерно порядка из строки: FNV-1a на 32 бита по кодам UTF-16.
int cltSeedOf(String text) {
  int hash = 0x811C9DC5;
  for (final int unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & _mask;
  }
  return hash;
}

/// Перестановка чисел `0…count-1` по зерну [seed]: Mulberry32 и
/// тасование Фишера — Йетса.
///
/// Арифметика только целая и на 32 бита: один и тот же код участника
/// даёт один и тот же порядок на телефоне и на ПК, и разбор может
/// пересчитать его без приложения.
List<int> cltPermutation(int count, int seed) {
  int state = seed & _mask;
  int next() {
    state = (state + 0x6D2B79F5) & _mask;
    int t = state;
    t = ((t ^ (t >> 15)) * (t | 1)) & _mask;
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & _mask))) & _mask;
    return (t ^ (t >> 14)) & _mask;
  }

  final List<int> order = <int>[for (int i = 0; i < count; i++) i];
  for (int i = count - 1; i > 0; i--) {
    final int j = next() % (i + 1);
    final int kept = order[i];
    order[i] = order[j];
    order[j] = kept;
  }
  return order;
}

/// Пункты части [part] в том порядке, в каком их увидит участник с
/// кодом [participant] (SNO-F-CLT-02).
///
/// Разделы идут по порядку сценария; раздел с `shuffle` перемешан по
/// зерну из кода участника, сценария, части и раздела — один код даёт
/// один порядок, сколько бы раз часть ни начинали.
List<CltItem> orderedCltItems(
  CltPart part, {
  required String scenario,
  required String participant,
}) {
  final List<CltItem> ordered = <CltItem>[];
  for (final CltSection section in part.sections) {
    if (!section.shuffle) {
      ordered.addAll(section.items);
      continue;
    }
    final List<int> order = cltPermutation(
      section.items.length,
      cltSeedOf('$participant/$scenario/${part.id}/${section.id}'),
    );
    for (final int index in order) {
      ordered.add(section.items[index]);
    }
  }
  return List<CltItem>.unmodifiable(ordered);
}
