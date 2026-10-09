/// Самопроверка журнала записи (SNO-F-REC-13).
///
/// Что журнал лёг на диск весь, до сих пор было известно только по
/// отсутствию ошибок записи. После остановки он перечитывается с диска
/// таким, каков он там есть, и сверяется сам с собой: сколько в нём
/// целых строк, все ли сквозные номера на месте, цела ли последняя
/// строка. Итог — в сведениях записи и строкой на экране завершения:
/// экспериментатор узнаёт о неполной записи, пока участник ещё рядом.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода. Проверка ничего не
/// чинит и файла не трогает.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Итог самопроверки журнала.
@immutable
class JournalCheck {
  /// Создаёт итог.
  const JournalCheck({
    required this.lines,
    required this.gaps,
    required this.torn,
    this.late = false,
  });

  /// Сколько в журнале целых строк.
  final int lines;

  /// Сколько сквозных номеров пропущено: событий, которые запись
  /// посчитала, а на диске их нет или их строка не читается.
  final int gaps;

  /// Оборвана ли последняя строка: за ней нет перевода строки.
  final bool torn;

  /// Проверена ли оборванная запись — при следующем запуске, а не в
  /// миг остановки. Сколько событий она успела посчитать, спросить не
  /// у кого: пропуски искались только между первым и последним
  /// номером, что есть на диске, а событий, потерянных за последней
  /// строкой, проверка не видит.
  final bool late;

  /// Цел ли журнал: все номера на месте, хвост не оборван.
  bool get intact => gaps == 0 && !torn;

  /// Запись для сведений о записи и отметки сессии.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'lines': lines,
      'gaps': gaps,
      'torn': torn,
      if (late) 'late': true,
    };
  }

  /// Читает запись; `null` — её нет или она не читается.
  static JournalCheck? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final Object? lines = raw['lines'];
    final Object? gaps = raw['gaps'];
    final Object? torn = raw['torn'];
    if (lines is! int || gaps is! int || torn is! bool) {
      return null;
    }
    return JournalCheck(
      lines: lines,
      gaps: gaps,
      torn: torn,
      late: raw['late'] == true,
    );
  }
}

/// Сверяет журнал [bytes] — файл `events.jsonl`, как он лежит на диске.
///
/// [expected] — сколько событий запись посчитала к этому мигу; `null`
/// — неизвестно (запись оборвалась), и пропуски ищутся только между
/// первым и последним номером, что есть в файле.
///
/// Строка считается целой, если за ней стоит перевод строки; пустые
/// строки не считаются. Строка, которая не разбирается или не несёт
/// номера, — мусор: её номер окажется среди пропущенных.
///
/// [key] — поле сквозного номера: `seq` у журнала событий, `n` у
/// потока сырого ввода (`input.jsonl`, SNO-F-REC-11). Порядок строк
/// значения не имеет: строка касания пишется, когда палец поднят, а
/// номер получает, когда он опущен.
JournalCheck checkJournal(
  List<int> bytes, {
  int? expected,
  bool late = false,
  String key = 'seq',
}) {
  const int newline = 0x0A;
  final int end = bytes.lastIndexOf(newline);
  final bool torn = bytes.isNotEmpty && end != bytes.length - 1;
  final Set<int> seen = <int>{};
  int lines = 0;
  int highest = 0;
  if (end >= 0) {
    final String text = utf8.decode(
      bytes.sublist(0, end),
      allowMalformed: true,
    );
    for (final String line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) {
        continue;
      }
      lines++;
      final int? seq = _seqOf(line, key);
      if (seq != null && seq > 0) {
        seen.add(seq);
        if (seq > highest) {
          highest = seq;
        }
      }
    }
  }
  final int wanted = expected != null && expected > highest
      ? expected
      : highest;
  return JournalCheck(
    lines: lines,
    gaps: wanted - seen.length,
    torn: torn,
    late: late,
  );
}

int? _seqOf(String line, String key) {
  try {
    final Object? raw = jsonDecode(line);
    if (raw is Map<String, Object?>) {
      final Object? seq = raw[key];
      return seq is int ? seq : null;
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// «строка» с числом: 1 строка, 2 строки, 5 строк, 21 строка.
String describeLineCount(int count) {
  final int tens = count % 100;
  final int ones = count % 10;
  final String word;
  if (ones == 1 && tens != 11) {
    word = 'строка';
  } else if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) {
    word = 'строки';
  } else {
    word = 'строк';
  }
  return '$count $word';
}

/// «кадр» с числом: 1 кадр, 2 кадра, 5 кадров, 21 кадр.
String describeFrameCount(int count) {
  final int tens = count % 100;
  final int ones = count % 10;
  final String word;
  if (ones == 1 && tens != 11) {
    word = 'кадр';
  } else if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) {
    word = 'кадра';
  } else {
    word = 'кадров';
  }
  return '$count $word';
}

/// Итог самопроверки потока сырого ввода словами — вторая строка
/// экрана завершения (SNO-F-REC-11): «Ввод цел: 312 строк, пропусков
/// нет» или «Ввод неполон: …». `null` на входе — потока в записи нет
/// (запись прежней сборки) или он не перечитался: строки нет.
String? describeInputCheck(JournalCheck? check) {
  if (check == null) {
    return null;
  }
  final String lines = describeLineCount(check.lines);
  if (check.intact) {
    return check.late
        ? 'Ввод цел до обрыва записи: $lines, пропусков нет'
        : 'Ввод цел: $lines, пропусков нет';
  }
  return <String>[
    'Ввод неполон: $lines',
    if (check.gaps > 0) 'пропущено строк ${check.gaps}',
    if (check.torn) 'последняя оборвана',
  ].join(', ');
}

/// Итог самопроверки потока кадров раскладки словами — третья строка
/// экрана завершения (SNO-F-REC-03): «Кадры раскладки целы: 96 кадров,
/// пропусков нет» или «Кадры раскладки неполны: …». `null` на входе —
/// потока в записи нет (запись прежней сборки) или он не перечитался:
/// строки нет.
String? describeLayoutCheck(JournalCheck? check) {
  if (check == null) {
    return null;
  }
  final String frames = describeFrameCount(check.lines);
  if (check.intact) {
    return check.late
        ? 'Кадры раскладки целы до обрыва записи: $frames, пропусков нет'
        : 'Кадры раскладки целы: $frames, пропусков нет';
  }
  return <String>[
    'Кадры раскладки неполны: $frames',
    if (check.gaps > 0) 'пропущено кадров ${check.gaps}',
    if (check.torn) 'последний оборван',
  ].join(', ');
}

/// Итог самопроверки словами — строка экрана завершения:
/// «Запись цела: 1482 строки, пропусков нет» или «Запись неполная:
/// пропущено строк 3, последняя оборвана».
///
/// У оборванной записи «цела» не говорится: проверка видит только то,
/// что успело лечь на диск, — «Журнал цел до обрыва записи: …».
/// `null` на входе — журнал перечитать не удалось.
String describeJournalCheck(JournalCheck? check) {
  if (check == null) {
    return 'Запись не проверена: журнал не перечитался с диска.';
  }
  if (check.intact) {
    final String lines = describeLineCount(check.lines);
    return check.late
        ? 'Журнал цел до обрыва записи: $lines, пропусков нет'
        : 'Запись цела: $lines, пропусков нет';
  }
  return <String>[
    'Запись неполная: ${describeLineCount(check.lines)}',
    if (check.gaps > 0) 'пропущено строк ${check.gaps}',
    if (check.torn) 'последняя оборвана',
  ].join(', ');
}
