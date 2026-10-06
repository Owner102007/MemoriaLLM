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

/// Итог теста для манифеста архива записи (SNO-F-CLT-03): сколько
/// блоков получили оценку усилия и пройдена ли итоговая часть. По
/// `final` список записей помечает запись «без теста нагрузки».
Map<String, Object?> summarizeClt(List<CltResult> results) {
  int efforts = 0;
  for (final CltResult result in results) {
    if (result.block != null && result.complete) {
      efforts++;
    }
  }
  final CltResult? last = finalCltResult(results);
  return <String, Object?>{
    'effort_answers': efforts,
    'final': last == null
        ? kCltFinalNone
        : (last.complete ? kCltFinalComplete : kCltFinalPartial),
    if (last != null) 'final_answers': last.answers.length,
    if (last != null) 'final_items': last.order.length,
    'files': <String>[for (final CltResult result in results) result.name],
  };
}

/// Среднее с тремя знаками после запятой.
double _mean(int sum, int count) => (sum * 1000 / count).round() / 1000;

/// Показатели по группам пунктов файла [result]: группа — идентификатор
/// пункта до последней точки.
Map<String, Object?> _groups(CltResult result) {
  final Map<String, int> total = <String, int>{};
  for (final String id in result.order) {
    final String group = cltGroupOf(id);
    total[group] = (total[group] ?? 0) + 1;
  }
  final Map<String, List<CltAnswer>> answered = <String, List<CltAnswer>>{};
  for (final CltAnswer answer in result.answers) {
    answered.putIfAbsent(cltGroupOf(answer.item), () => <CltAnswer>[]).add(
      answer,
    );
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
/// сценария это даёт усилие по блоку (`paas`), Raw TLX (`tlx`),
/// внутреннюю, внешнюю и полезную нагрузку (`icl`, `ecl`, `gcl`) и
/// ориентацию (`orient`). Одного общего числа нет — намеренно: шкалы
/// меряют разное.
///
/// Ответы лежат рядом, в файлах частей: пересчитать можно всегда.
Map<String, Object?> cltScores(List<CltResult> results) {
  final CltResult? last = finalCltResult(results);
  final CltResult? any = results.isEmpty ? null : results.first;
  return <String, Object?>{
    'schema': kCltScoresSchema,
    if (any != null) 'scenario': any.scenario,
    if (any != null) 'version': any.version,
    if (any != null) 'participant': any.participant,
    'rule':
        'mean — среднее ответов группы с тремя знаками; группа — '
        'идентификатор пункта до последней точки; ответ пункта с '
        'reverse перевёрнут: min + max − value; n из of — на сколько '
        'пунктов группы ответили',
    'blocks': <Object?>[
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
    ],
    'final': last == null
        ? null
        : <String, Object?>{
            'file': last.name,
            'complete': last.complete,
            'answers': last.answers.length,
            'items': last.order.length,
            'scores': _groups(last),
          },
  };
}
