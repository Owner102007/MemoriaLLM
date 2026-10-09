/// Строка «Взгляд: …» экрана завершения сессии (SNO-F-EYE-02,
/// SNO-F-EYE-06, кадр SNO-SCR-08.1): сколько времени взгляд годен,
/// точность в начале и в конце записи — по блоку `eye_tracker` сведений
/// записи.
///
/// Чистый Dart: ни виджетов, ни ввода-вывода.
library;

/// Число с одним знаком после запятой: «2,4».
String _number(num value) =>
    value.toDouble().toStringAsFixed(1).replaceAll('.', ',');

/// Строка «Взгляд: 94 % времени, точность в начале 2,4°, в конце 2,9°»
/// по блоку [block]; `null` — айтрекера у записи нет (телефон, ПК без
/// места записи).
String? describeGaze(Object? block) {
  if (block is! Map<String, Object?> || block['configured'] != true) {
    return null;
  }
  if (block['present'] != true) {
    final String why = switch (block['reason']) {
      'skipped' => 'организатор выбрал «Без взгляда»',
      'selfcheck_failed' => 'самопроверка места — не годится',
      'stopped' => 'запись остановлена до начала изучения',
      'gave_up' => 'спутник терялся слишком часто',
      'limit' => 'калибровка не кончилась за 15 минут',
      'open_failed' => 'камера не открылась',
      _ => 'айтрекер не запустился',
    };
    return 'Взгляд не записан: $why';
  }
  String? deg(Object? v) => v is num ? '${_number(v)}°' : null;
  final Object? share = block['valid_share'];
  final Object? calibration = block['calibration'];
  final Object? end = block['end_check'];
  final String? start = calibration is Map<String, Object?>
      ? deg(calibration['accuracy_deg'])
      : null;
  final String finish;
  if (end is Map<String, Object?>) {
    final String? done = deg(end['accuracy_deg']);
    if (end['skipped'] == true) {
      finish = 'в конце — пропущена';
    } else if (done != null) {
      finish = 'в конце $done';
    } else {
      finish = 'в конце — не завершена';
    }
  } else {
    finish = 'в конце — не было';
  }
  return <String>[
    if (share is num)
      'Взгляд: ${(share * 100).round()} % времени'
    else
      'Взгляд записан',
    if (start != null) 'точность в начале $start',
    finish,
    if (block['quality'] == 'low') 'с пометкой',
  ].join(', ');
}
