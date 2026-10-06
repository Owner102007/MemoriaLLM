/// Результаты теста нагрузки: файл ответов, итог для манифеста и
/// показатели (SNO-F-CLT-03).
///
/// Каждая пройденная часть теста — свой файл в подпапке `clt/` записи:
/// `clt/<сценарий>_<часть>_<t>.json`. Ответ ложится в файл сразу, а не
/// в конце части: оборванный тест не теряет уже данных ответов. При
/// завершении сессии по этим файлам считаются показатели
/// (`clt/scores.json`) и итог для манифеста архива. Участнику ни то,
/// ни другое не показывается.
///
/// **Файл ответов понимается без сценария**: у каждого ответа стоят
/// края его шкалы и признак обратного счёта, а сам сценарий, каким его
/// видел участник, лежит рядом (`clt/scenario.json`) — формулировки
/// правятся без пересборки, и разбор обязан знать, какие были.
///
/// **Маркеры честности в показатели не входят** (SNO-F-CLT-04): ответ
/// на маркер помечен в файле ответов (`role: check`), а что из него
/// следует — отметка, сверка с записью действий, быстрые и одинаковые
/// ответы — лежит в показателях отдельным разделом `checks`
/// ([cltChecks]). Участнику отметки не показываются, запись из-за них
/// не отвергается: что делать с помеченной записью, решает организатор
/// при разборе.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода.
library;

import 'dart:convert';

import 'scenario.dart';

/// Подпапка теста в папке записи.
const String kCltFolder = 'clt';

/// Версия файла ответов.
const String kCltResultSchema = 'sno2026-clt-result/1';

/// Версия файла показателей.
const String kCltScoresSchema = 'sno2026-clt-scores/1';

/// Имя файла показателей в папке записи.
const String kCltScoresFile = '$kCltFolder/scores.json';

/// Имя файла сценария, каким его видел участник.
const String kCltScenarioFile = '$kCltFolder/scenario.json';

/// Итоговая часть пройдена до конца.
const String kCltFinalComplete = 'complete';

/// Итоговая часть начата и не окончена.
const String kCltFinalPartial = 'partial';

/// Итоговую часть не начинали.
const String kCltFinalNone = 'none';

/// Файлы теста не прочитались: пройдена ли итоговая часть, неизвестно.
const String kCltFinalUnknown = 'unknown';

/// Быстрее этого пункт не прочитать, в миллисекундах (SNO-F-CLT-04).
const int kCltFastMs = 1000;

/// Столько быстрых ответов — отметка.
const int kCltFastFlag = 3;

/// Столько одинаковых ответов подряд в перемешанном разделе — отметка.
const int kCltSameFlag = 6;

/// Отметок нет.
const String kCltVerdictOk = 'ok';

/// Одна отметка: посмотреть ответы глазами.
const String kCltVerdictReview = 'review';

/// Две отметки и больше: ответам теста нельзя верить без разбора.
const String kCltVerdictDoubt = 'doubt';

/// Имя файла ответов части [part] сценария [scenario], начатой в миг
/// [tStart] по часам записи.
String cltResultName(String scenario, String part, int tStart) {
  return '$kCltFolder/${scenario}_${part}_$tStart.json';
}

/// Ответ на один пункт.
class CltAnswer {
  /// Создаёт ответ.
  const CltAnswer({
    required this.item,
    required this.value,
    required this.rtMs,
    required this.order,
    required this.min,
    required this.max,
    this.t,
    this.reverse = false,
    this.revised = false,
    this.check = false,
  });

  /// Идентификатор пункта.
  final String item;

  /// Выбранное значение — как на экране, без переворота.
  final int value;

  /// Сколько прошло от показа пункта до выбора значения, в
  /// миллисекундах.
  final int rtMs;

  /// Каким по счёту пункт показан, считая с единицы.
  final int order;

  /// Края шкалы пункта.
  final int min;

  /// Правый край шкалы.
  final int max;

  /// Когда ответ принят, по часам записи; `null` — неизвестно.
  final int? t;

  /// Считается ли пункт наоборот.
  final bool reverse;

  /// Исправлен ли ответ после возврата к пункту.
  final bool revised;

  /// Ответ ли это на маркер честности (SNO-F-CLT-04): в показатели
  /// нагрузки он не входит.
  final bool check;

  /// Значение для счёта: у пункта с обратным счётом — перевёрнутое.
  int get scored => reverse ? min + max - value : value;

  /// Запись для файла ответов.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'item': item,
      'value': value,
      'rt_ms': rtMs,
      'order': order,
      if (t != null) 't': t,
      'min': min,
      'max': max,
      if (reverse) 'reverse': true,
      if (revised) 'revised': true,
      if (check) 'role': kCltRoleCheck,
    };
  }

  /// Читает запись; `null` — она не читается.
  static CltAnswer? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? item = raw['item'];
    final Object? value = raw['value'];
    final Object? rt = raw['rt_ms'];
    final Object? order = raw['order'];
    final Object? min = raw['min'];
    final Object? max = raw['max'];
    final Object? t = raw['t'];
    if (item is! String ||
        value is! int ||
        order is! int ||
        min is! int ||
        max is! int) {
      return null;
    }
    return CltAnswer(
      item: item,
      value: value,
      rtMs: rt is int ? rt : 0,
      order: order,
      min: min,
      max: max,
      t: t is int ? t : null,
      reverse: raw['reverse'] == true,
      revised: raw['revised'] == true,
      check: raw['role'] == kCltRoleCheck,
    );
  }
}

/// Файл ответов одной части теста.
class CltResult {
  /// Создаёт файл ответов.
  const CltResult({
    required this.scenario,
    required this.version,
    required this.participant,
    required this.part,
    required this.tStart,
    required this.order,
    this.block,
    this.blockStartMs,
    this.tEnd,
    this.answers = const <CltAnswer>[],
    this.complete = false,
    this.checks = const <String>[],
  });

  /// Идентификатор сценария.
  final String scenario;

  /// Версия сценария.
  final int version;

  /// Код участника.
  final String participant;

  /// Идентификатор части: `A`, `B`.
  final String part;

  /// Номер блока, за который отвечали; `null` — часть не о блоке.
  ///
  /// Только в файлах прежних сборок: с шага 25 блоков нет
  /// (SNO-F-REC-15).
  final int? block;

  /// Когда этот блок начат, по часам записи: два блока с одним номером
  /// различаются им.
  final int? blockStartMs;

  /// Когда часть начата, по часам записи.
  final int tStart;

  /// Когда часть окончена; `null` — не окончена.
  final int? tEnd;

  /// Идентификаторы пунктов в порядке показа: порядок перемешанного
  /// раздела известен и у неоконченной части.
  final List<String> order;

  /// Ответы — по пунктам, в порядке показа.
  final List<CltAnswer> answers;

  /// Пройдена ли часть до конца.
  final bool complete;

  /// Идентификаторы маркеров честности среди пунктов части
  /// (SNO-F-CLT-04): в показатели нагрузки они не входят — и тогда,
  /// когда на маркер ещё не ответили.
  final List<String> checks;

  /// Имя файла в папке записи.
  String get name => cltResultName(scenario, part, tStart);

  /// Запись для файла ответов.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': kCltResultSchema,
      'scenario': scenario,
      'version': version,
      'participant': participant,
      'part': part,
      'block': block,
      if (blockStartMs != null) 'block_start_ms': blockStartMs,
      't_start': tStart,
      't_end': tEnd,
      'complete': complete,
      'order': order,
      if (checks.isNotEmpty) 'checks': checks,
      'answers': <Object?>[
        for (final CltAnswer answer in answers) answer.toJson(),
      ],
    };
  }

  /// Текст файла ответов.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Читает файл ответов из текста [text]; `null` — это не он.
  static CltResult? decode(String text) {
    try {
      final Object? raw = jsonDecode(text);
      if (raw is! Map<String, Object?> || raw['schema'] != kCltResultSchema) {
        return null;
      }
      final Object? scenario = raw['scenario'];
      final Object? version = raw['version'];
      final Object? participant = raw['participant'];
      final Object? part = raw['part'];
      final Object? block = raw['block'];
      final Object? blockStart = raw['block_start_ms'];
      final Object? tStart = raw['t_start'];
      final Object? tEnd = raw['t_end'];
      final Object? order = raw['order'];
      final Object? answers = raw['answers'];
      final Object? checks = raw['checks'];
      if (scenario is! String ||
          version is! int ||
          participant is! String ||
          part is! String ||
          tStart is! int) {
        return null;
      }
      final List<CltAnswer> read = <CltAnswer>[];
      if (answers is List<Object?>) {
        for (final Object? entry in answers) {
          final CltAnswer? answer = CltAnswer.fromJson(entry);
          if (answer != null) {
            read.add(answer);
          }
        }
      }
      return CltResult(
        scenario: scenario,
        version: version,
        participant: participant,
        part: part,
        block: block is int ? block : null,
        blockStartMs: blockStart is int ? blockStart : null,
        tStart: tStart,
        tEnd: tEnd is int ? tEnd : null,
        order: <String>[
          if (order is List<Object?>)
            for (final Object? id in order)
              if (id is String) id,
        ],
        answers: List<CltAnswer>.unmodifiable(read),
        complete: raw['complete'] == true,
        checks: <String>[
          if (checks is List<Object?>)
            for (final Object? id in checks)
              if (id is String) id,
        ],
      );
    } on FormatException {
      return null;
    }
  }
}

/// Файлы ответов среди файлов подпапки теста [files] (имя → текст),
/// по времени начала части. Сценарий, показатели и всё, что не
/// читается, пропускаются.
List<CltResult> readCltResults(Map<String, String> files) {
  final List<CltResult> results = <CltResult>[];
  for (final String text in files.values) {
    final CltResult? result = CltResult.decode(text);
    if (result != null) {
      results.add(result);
    }
  }
  results.sort((CltResult a, CltResult b) {
    final int byTime = a.tStart.compareTo(b.tStart);
    return byTime != 0 ? byTime : a.name.compareTo(b.name);
  });
  return results;
}

/// Ответы итоговой части среди [results]: файл без блока, в котором
/// ответов больше всего, при равенстве — начатый позже; `null` —
/// итоговую часть не начинали.
CltResult? finalCltResult(List<CltResult> results) {
  CltResult? best;
  for (final CltResult result in results) {
    if (result.block != null) {
      continue;
    }
    if (best == null || result.answers.length >= best.answers.length) {
      best = result;
    }
  }
  return best;
}

/// Итог теста для манифеста архива записи (SNO-F-CLT-03): пройдена
/// ли итоговая часть. По `final` список записей помечает запись «без
/// теста нагрузки».
///
/// [checks] — раздел `checks` показателей ([cltChecks]): из него в итог
/// идёт одно число — сколько отметок набралось (`checks_flags`,
/// SNO-F-CLT-04). `effort_answers` стоит только у записи прежней
/// сборки, где были блоки и вопрос об усилии после каждого
/// (SNO-F-REC-15).
Map<String, Object?> summarizeClt(
  List<CltResult> results, {
  Map<String, Object?>? checks,
}) {
  int efforts = 0;
  bool blocks = false;
  for (final CltResult result in results) {
    if (result.block != null) {
      blocks = true;
      if (result.complete) {
        efforts++;
      }
    }
  }
  final CltResult? last = finalCltResult(results);
  final Object? flags = checks?['flags'];
  return <String, Object?>{
    if (blocks) 'effort_answers': efforts,
    'final': last == null
        ? kCltFinalNone
        : (last.complete ? kCltFinalComplete : kCltFinalPartial),
    if (last != null) 'final_answers': last.answers.length,
    if (last != null) 'final_items': last.order.length,
    if (flags is int) 'checks_flags': flags,
    'files': <String>[for (final CltResult result in results) result.name],
  };
}

/// Среднее с тремя знаками после запятой.
double _mean(int sum, int count) => (sum * 1000 / count).round() / 1000;

/// Показатели по группам пунктов файла [result]: группа — идентификатор
/// пункта до последней точки.
///
/// Маркеры честности пропускаются (SNO-F-CLT-04): и ответы на них, и
/// сами пункты в счёте «на сколько пунктов группы ответили».
Map<String, Object?> _groups(CltResult result) {
  final Set<String> checks = result.checks.toSet();
  final Map<String, int> total = <String, int>{};
  for (final String id in result.order) {
    if (checks.contains(id)) {
      continue;
    }
    final String group = cltGroupOf(id);
    total[group] = (total[group] ?? 0) + 1;
  }
  final Map<String, List<CltAnswer>> answered = <String, List<CltAnswer>>{};
  for (final CltAnswer answer in result.answers) {
    if (answer.check || checks.contains(answer.item)) {
      continue;
    }
    answered
        .putIfAbsent(cltGroupOf(answer.item), () => <CltAnswer>[])
        .add(answer);
  }
  final Map<String, Object?> groups = <String, Object?>{};
  for (final MapEntry<String, List<CltAnswer>> group in answered.entries) {
    int sum = 0;
    for (final CltAnswer answer in group.value) {
      sum += answer.scored;
    }
    final int count = group.value.length;
    final CltAnswer first = group.value.first;
    groups[group.key] = <String, Object?>{
      'mean': _mean(sum, count),
      'sum': sum,
      'n': count,
      'of': total[group.key] ?? count,
      'min': first.min,
      'max': first.max,
    };
  }
  return groups;
}

/// Показатели теста по файлам ответов [results] (SNO-F-CLT-03, решение
/// владельца АД1 от 06.10.2026: считает приложение, участнику не
/// показывает).
///
/// Правило одно: показатель — среднее ответов группы, группа —
/// идентификатор пункта до последней точки, ответ пункта с обратным
/// счётом переворачивается (`min + max − value`). Для встроенного
/// сценария это даёт Raw TLX (`tlx`), внутреннюю, внешнюю и полезную
/// нагрузку (`icl`, `ecl`, `gcl`) и ориентацию (`orient`). Одного общего
/// числа нет — намеренно: шкалы меряют разное.
///
/// Маркеры честности в показатели не входят; [checks] — что о них
/// известно ([cltChecks]) — ложится рядом отдельным разделом
/// (SNO-F-CLT-04). Раздел `blocks` стоит только у записи прежней
/// сборки, где после каждого блока спрашивали об усилии
/// (SNO-F-REC-15).
///
/// Ответы лежат рядом, в файлах частей: пересчитать можно всегда.
Map<String, Object?> cltScores(
  List<CltResult> results, {
  Map<String, Object?>? checks,
}) {
  final CltResult? last = finalCltResult(results);
  final CltResult? any = results.isEmpty ? null : results.first;
  final List<Object?> blocks = <Object?>[
    for (final CltResult result in results)
      if (result.block != null && result.answers.isNotEmpty)
        <String, Object?>{
          'block': result.block,
          if (result.blockStartMs != null)
            'block_start_ms': result.blockStartMs,
          'file': result.name,
          'complete': result.complete,
          'scores': _groups(result),
        },
  ];
  return <String, Object?>{
    'schema': kCltScoresSchema,
    if (any != null) 'scenario': any.scenario,
    if (any != null) 'version': any.version,
    if (any != null) 'participant': any.participant,
    'rule':
        'mean — среднее ответов группы с тремя знаками; группа — '
        'идентификатор пункта до последней точки; ответ пункта с '
        'reverse перевёрнут: min + max − value; n из of — на сколько '
        'пунктов группы ответили; маркеры честности (role: check) в '
        'группы не входят — они в разделе checks',
    if (blocks.isNotEmpty) 'blocks': blocks,
    'final': last == null
        ? null
        : <String, Object?>{
            'file': last.name,
            'complete': last.complete,
            'answers': last.answers.length,
            'items': last.order.length,
            'scores': _groups(last),
          },
    if (checks != null) 'checks': checks,
  };
}

/// Самая длинная цепочка одинаковых ответов среди [answers], взятых в
/// порядке показа.
int _longestRun(List<CltAnswer> answers) {
  final List<CltAnswer> shown = List<CltAnswer>.of(answers)
    ..sort((CltAnswer a, CltAnswer b) => a.order.compareTo(b.order));
  int longest = 0;
  int run = 0;
  int? value;
  for (final CltAnswer answer in shown) {
    run = answer.value == value ? run + 1 : 1;
    value = answer.value;
    if (run > longest) {
      longest = run;
    }
  }
  return longest;
}

/// Маркеры честности и признаки небрежных ответов по файлу ответов
/// [result] части [part] (SNO-F-CLT-04).
///
/// По каждому маркеру — ответ, отметка по самому ответу и сверка с
/// записью действий: [facts] — числа из журнала этой же записи (сколько
/// раз участник уходил из приложения, сколько раз открывал книги);
/// числа нет — запись без журнала, — и сверка помечена «не знаю»
/// (`null`), а не «расхождений нет». Без вопросов считаются ещё два
/// признака: сколько ответов дано быстрее [kCltFastMs] и самая длинная
/// цепочка одинаковых ответов в перемешанном разделе.
///
/// `flags` — сколько отметок набралось: по одной за каждый маркер, за
/// быстрые ответы и за одинаковые подряд. `verdict`: [kCltVerdictOk] —
/// ни одной, [kCltVerdictReview] — одна, [kCltVerdictDoubt] — две и
/// больше. Расхождение с записью делает отметку маркера весомее, но
/// отдельно не считается. Один-два маркера помечают запись на просмотр,
/// а не доказывают ложь: приложение по ним ничего не решает.
Map<String, Object?> cltChecks(
  CltResult result,
  CltPart part, {
  Map<String, int?> facts = const <String, int?>{},
}) {
  final Map<String, CltAnswer> given = <String, CltAnswer>{
    for (final CltAnswer answer in result.answers) answer.item: answer,
  };
  int flags = 0;
  final Map<String, Object?> items = <String, Object?>{};
  for (final CltItem item in part.items) {
    final CltCheck? check = item.check;
    if (check == null) {
      continue;
    }
    final int? value = given[item.id]?.value;
    final bool? flagged = value == null ? null : check.flag.holds(value);
    if (flagged ?? false) {
      flags++;
    }
    final String? fact = check.fact;
    final int? known = fact == null ? null : facts[fact];
    items[item.id] = <String, Object?>{
      'value': value,
      'flag': flagged,
      if (fact != null) 'record': <String, Object?>{fact: known},
      if (fact != null)
        'contradicts_record': value == null || known == null
            ? null
            : check.contradicts(value, known),
    };
  }
  int fast = 0;
  for (final CltAnswer answer in result.answers) {
    if (answer.rtMs < kCltFastMs) {
      fast++;
    }
  }
  int same = 0;
  for (final CltSection section in part.sections) {
    if (!section.shuffle) {
      continue;
    }
    final int run = _longestRun(<CltAnswer>[
      for (final CltItem item in section.items)
        if (given[item.id] != null) given[item.id]!,
    ]);
    if (run > same) {
      same = run;
    }
  }
  if (fast >= kCltFastFlag) {
    flags++;
  }
  if (same >= kCltSameFlag) {
    flags++;
  }
  return <String, Object?>{
    'rule':
        'flag — отметка по самому ответу на маркер; record — число из '
        'журнала этой записи; contradicts_record — расходится ли ответ '
        'с записью, null — не знаю; fast_answers — ответов быстрее '
        '$kCltFastMs мс, отметка от $kCltFastFlag; longest_same — самая '
        'длинная цепочка одинаковых ответов в перемешанном разделе, '
        'отметка от $kCltSameFlag; flags — сколько отметок; verdict: '
        'ok — ни одной, review — одна, doubt — две и больше',
    'items': items,
    'fast_answers': fast,
    'longest_same': same,
    'flags': flags,
    'verdict': flags == 0
        ? kCltVerdictOk
        : (flags == 1 ? kCltVerdictReview : kCltVerdictDoubt),
  };
}

/// Раздел `checks` показателей для записи с файлами ответов [results]
/// (SNO-F-CLT-04); `null` — считать не по чему: итоговую часть не
/// начинали, сценарий [scenario], каким его видел участник, не лежит
/// рядом или не читается, либо маркеров в части нет.
///
/// Правила маркеров берутся из сценария рядом с ответами, а не из
/// встроенного: показатели обязаны выйти теми же и после обновления
/// приложения.
Map<String, Object?>? cltChecksFor(
  List<CltResult> results, {
  required String? scenario,
  Map<String, int?> facts = const <String, int?>{},
}) {
  final CltResult? last = finalCltResult(results);
  if (last == null || scenario == null) {
    return null;
  }
  final CltScenario parsed;
  try {
    parsed = parseCltScenario(jsonDecode(scenario));
  } on CltScenarioException {
    return null;
  } on FormatException {
    return null;
  }
  for (final CltPart part in parsed.parts) {
    if (part.id != last.part) {
      continue;
    }
    return part.items.any((CltItem item) => item.isCheck)
        ? cltChecks(last, part, facts: facts)
        : null;
  }
  return null;
}
