/// Записи на устройстве: договор и слова (SNO-F-REC-07, SNO-F-REC-06).
///
/// Запись сессии исследования СНО2026 после завершения — один архив в
/// папке `Записи/` (SNO-F-REC-05). Здесь то, что о таких архивах знают
/// экраны: строка списка, что с записью можно сделать и какими словами
/// о ней сказать. Настоящая реализация ходит на диск
/// (`file_records.dart`), экраны проверяются на памяти.
///
/// Ни виджетов, ни ввода-вывода.
library;

import 'package:flutter/foundation.dart';

import '../../domain/library/archive_scan.dart';
import 'session.dart';

/// Папка в «Загрузках» устройства, куда телефон кладёт вторую копию
/// каждого архива (SNO-F-REC-13): она переживает и удаление
/// приложения, и новую сборку.
const String kBackupFolder = 'Memoria-SNO2026';

/// Та же папка словами — как её увидит экспериментатор в файловом
/// менеджере телефона.
const String kBackupPlace = 'Загрузки/$kBackupFolder';

/// Чем кончилось системное окно «Поделиться» (SNO-F-REC-14).
enum ShareOutcome {
  /// В окне выбрано приложение: архив отдан ему. Дошёл ли он до
  /// адресата, система не говорит.
  chosen,

  /// Окно закрыли, ничего не выбрав.
  dismissed,

  /// Система не сообщила, выбрано ли приложение: окно производителя
  /// или пункт окна, за которым приложения нет («Копировать»,
  /// «Печать»). Запись остаётся неотправленной: ошибка в безопасную
  /// сторону — её не удалят одним вопросом.
  untold,

  /// Окно не открылось, или отдавать нечего.
  failed,
}

/// Итог «Поделиться»: чем кончилось окно и сколько записей помечено
/// отправленными.
@immutable
class ShareReport {
  /// Создаёт итог.
  const ShareReport(this.outcome, {this.sent = 0});

  /// Чем кончилось окно.
  final ShareOutcome outcome;

  /// Сколько записей помечено отправленными: все отданные окну, если
  /// в нём выбрано приложение, иначе ноль.
  final int sent;
}

/// Запись на устройстве — строка списка.
@immutable
class DeviceRecord {
  /// Создаёт строку.
  const DeviceRecord({
    required this.name,
    required this.bytes,
    this.packed = true,
    this.damaged = false,
    this.branch,
    this.participant,
    this.startedAt,
    this.durationMs,
    this.events,
    this.stoppedBy,
    this.sharedAt,
    this.copiedAt,
  });

  /// Имя записи — имя архива без `.zip`:
  /// `sno2026_I_67954332_a91f3c_20261103-1402`.
  final String name;

  /// Сколько байт занимает архив (у неупакованной записи — её папка).
  final int bytes;

  /// Архив ли это: `false` — запись осталась папкой, упаковка не
  /// удалась и повторится при следующем запуске.
  final bool packed;

  /// Архив не читается или в нём нет манифеста. Отправить его всё
  /// равно можно: что с ним делать, решит разбор.
  final bool damaged;

  /// Ветвь сборки, записавшей сессию.
  final String? branch;

  /// Код участника.
  final String? participant;

  /// Когда запись началась.
  final DateTime? startedAt;

  /// Сколько длилась, в миллисекундах.
  final int? durationMs;

  /// Сколько событий в журнале.
  final int? events;

  /// Кем остановлена: имя причины, как в журнале ([StopReason.wire]).
  final String? stoppedBy;

  /// Когда в системном окне «Поделиться» для записи выбрали
  /// приложение (SNO-F-REC-14); `null` — не выбирали. Это факт выбора,
  /// а не доставки.
  final DateTime? sharedAt;

  /// Когда копия архива легла вне папки приложения: на ПК — в папку,
  /// выбранную экспериментатором, на телефоне — в «Загрузки»
  /// (SNO-F-REC-13); `null` — копии нет.
  final DateTime? copiedAt;

  /// Имя файла архива.
  String get fileName => '$name.zip';

  /// Чем строка этой записи отличается от остальных в списке.
  ///
  /// Папка и архив могут носить одно имя — упаковку оборвали между
  /// архивом и уборкой папки; строки у них при этом разные.
  String get rowId => packed ? name : '$name/';

  /// Оборвалась ли запись: приложение закрыли или оно упало.
  bool get interrupted => stoppedBy == StopReason.crash.wire;

  /// Есть ли запись где-то, кроме папки приложения, — отправлена или
  /// лежит копией: такую можно удалить одним подтверждением,
  /// остальные — двумя.
  bool get taken => sharedAt != null || copiedAt != null;
}

/// Чем кончилось «Сохранить архив как…».
enum CopyOutcome {
  /// Копия лежит в выбранной папке и сверена с архивом.
  done,

  /// Папку не выбрали.
  cancelled,

  /// Выбрана папка самих записей: копия рядом с архивом ничего не
  /// спасает.
  inside,

  /// Копия не записалась или не сошлась с архивом.
  failed,
}

/// Записи на устройстве.
///
/// Слушатели узнают, когда список перечитан, — и всегда позже вызова,
/// который к этому привёл: экран, зовущий [refresh] при построении,
/// не получает оповещения посреди него.
abstract interface class DeviceRecords implements Listenable {
  /// Есть ли у устройства системное окно «Поделиться» (телефон).
  bool get shares;

  /// Есть ли у устройства папки, куда сохраняют копию (ПК).
  bool get saves;

  /// Кладёт ли устройство вторую копию каждого архива само — в общую
  /// папку «Загрузки» (телефон с Android 10 и новее; SNO-F-REC-13).
  /// До первого чтения списка — «нет».
  bool get backs;

  /// Прочитан ли список хоть раз.
  bool get loaded;

  /// Записи от новых к старым.
  List<DeviceRecord> get entries;

  /// Перечитывает список с диска.
  Future<void> refresh();

  /// Подбирает папки записей, оставшиеся среди незавершённых без
  /// сессии: завершение, которое не успело их перенести, и записи,
  /// чья отметка о сессии потерялась. Зовётся при запуске, до первого
  /// кадра: пока оно идёт, новая запись начаться не может.
  Future<void> adoptOrphans();

  /// Упаковывает всё, что лежит папками: записи прежних сборок, у
  /// которых архива не было, и упаковки, оборванные закрытием
  /// приложения. Запуска приложения не задерживает.
  Future<void> packPending();

  /// Кладёт вторую копию каждого архива, у которого её ещё нет, в
  /// общую папку устройства (SNO-F-REC-13): записи прежних сборок и
  /// те, чья копия в прошлый раз не легла. Запуска приложения не
  /// задерживает; там, где общей папки нет, не делает ничего.
  Future<void> backupPending();

  /// Упаковывает завершённую запись из папки [folder] в архив.
  ///
  /// Отвечает строкой этой записи: архивом, если упаковка удалась, и
  /// папкой, если нет; `null` — записи с таким именем нет вовсе.
  /// Готовый архив тут же получает вторую копию ([backs]).
  Future<DeviceRecord?> pack(String folder);

  /// Отдаёт архивы системному окну «Поделиться».
  ///
  /// Записи помечаются отправленными, только когда в окне выбрано
  /// приложение (SNO-F-REC-14); окно, закрытое без выбора, отметки не
  /// оставляет. «Не открылось» — и тогда, когда отдавать нечего: архив
  /// убрали с диска, пока список был на экране.
  Future<ShareReport> share(List<DeviceRecord> records);

  /// Сохраняет копию архива в папку, которую выберет экспериментатор.
  Future<CopyOutcome> saveCopy(DeviceRecord record);

  /// Открывает папку записей; с [record] — на его файле.
  Future<bool> reveal([DeviceRecord? record]);

  /// Удаляет запись с устройства. Отвечает, удалена ли.
  Future<bool> delete(DeviceRecord record);
}

/// Записи, которых нет нигде, кроме папки приложения.
List<DeviceRecord> untaken(List<DeviceRecord> records) {
  return <DeviceRecord>[
    for (final DeviceRecord record in records)
      if (!record.taken) record,
  ];
}

/// Архивы, которые можно отдать окну «Поделиться» и которые ещё не
/// отдавали.
List<DeviceRecord> unshared(List<DeviceRecord> records) {
  return <DeviceRecord>[
    for (final DeviceRecord record in records)
      if (record.packed && record.sharedAt == null) record,
  ];
}

/// Строка «Записи на устройстве» в разделе «Тестирование»:
/// «3 · не отправлено 1».
///
/// [shares] — телефон: там запись «отправляют», на ПК — «сохраняют
/// копию».
String describeRecordsCount(
  List<DeviceRecord> records, {
  required bool shares,
}) {
  if (records.isEmpty) {
    return 'нет';
  }
  // На телефоне считают неотправленные: вторая копия в «Загрузках»
  // лежит на том же телефоне и отправки не заменяет (SNO-F-REC-13).
  int left = 0;
  for (final DeviceRecord record in records) {
    if (shares ? record.sharedAt == null : !record.taken) {
      left++;
    }
  }
  if (left == 0) {
    return '${records.length}';
  }
  return shares
      ? '${records.length} · не отправлено $left'
      : '${records.length} · без копии $left';
}

/// Строка под именем записи: «40:00 · 0,4 МБ · не отправлена».
///
/// [backs] — телефон сам кладёт вторую копию в «Загрузки»: тогда у
/// записи две независимые отметки, и отсутствие копии названо тоже —
/// «не отправлена · копия есть», «отправлена · копии нет»
/// (SNO-F-REC-13).
String describeRecord(
  DeviceRecord record, {
  required bool shares,
  bool backs = false,
}) {
  final int? duration = record.durationMs;
  final bool sent = record.sharedAt != null;
  final bool copied = record.copiedAt != null;
  final String state;
  if (shares && backs && record.packed) {
    state =
        '${sent ? 'отправлена' : 'не отправлена'} · '
        '${copied ? 'копия есть' : 'копии нет'}';
  } else if (sent) {
    state = copied ? 'отправлена · копия есть' : 'отправлена';
  } else if (copied) {
    state = 'копия есть';
  } else {
    state = shares ? 'не отправлена' : 'копии нет';
  }
  return <String>[
    if (duration != null) describeRecordingTime(duration),
    describeFileSize(record.bytes),
    if (record.interrupted) 'прервана',
    if (!record.packed) 'не упакована',
    if (record.damaged) 'архив повреждён',
    state,
  ].join(' · ');
}

/// «событие» с числом: 1 событие, 2 события, 5 событий, 21 событие.
String describeEventCount(int count) {
  final int tens = count % 100;
  final int ones = count % 10;
  final String word;
  if (ones == 1 && tens != 11) {
    word = 'событие';
  } else if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) {
    word = 'события';
  } else {
    word = 'событий';
  }
  return '$count $word';
}

/// Строка под именем готового архива на экране завершения:
/// «40:00 · 1482 события · 0,4 МБ».
String describeArchive(DeviceRecord record) {
  final int? duration = record.durationMs;
  final int? events = record.events;
  return <String>[
    if (duration != null) describeRecordingTime(duration),
    if (events != null) describeEventCount(events),
    describeFileSize(record.bytes),
  ].join(' · ');
}

/// Что сказать после «Поделиться» (SNO-F-REC-14).
String describeShared(ShareReport report) {
  return switch (report.outcome) {
    ShareOutcome.chosen =>
      report.sent == 1
          ? 'Запись помечена отправленной.'
          : 'Записи помечены отправленными: ${report.sent}.',
    ShareOutcome.dismissed => 'Окно закрыто без выбора — запись не отправлена.',
    ShareOutcome.untold =>
      'Телефон не сообщил, выбрано ли приложение: запись осталась '
          'неотправленной. Если архив ушёл, ничего делать не нужно.',
    ShareOutcome.failed =>
      'Поделиться не получилось: окно не открылось или архива уже '
          'нет на устройстве.',
  };
}

/// Строка о второй копии готового архива на экране завершения
/// (SNO-F-REC-13); `null` — устройство вторых копий само не кладёт.
String? describeBackup(DeviceRecord record, {required bool backs}) {
  if (!backs || !record.packed) {
    return null;
  }
  return record.copiedAt != null
      ? 'Копия: $kBackupPlace'
      : 'Копии в «Загрузках» нет: общая папка телефона файл не '
            'приняла. Архив лежит в приложении — отправьте его.';
}

/// Что сказать после «Сохранить архив как…»; `null` — папку не
/// выбрали, и говорить нечего.
String? describeCopied(CopyOutcome outcome) {
  return switch (outcome) {
    CopyOutcome.done => 'Копия сохранена и сверена с архивом.',
    CopyOutcome.cancelled => null,
    CopyOutcome.inside =>
      'Это папка самих записей — выберите другую: флешку, сетевую '
          'папку или «Загрузки».',
    CopyOutcome.failed =>
      'Копия не сохранилась: проверьте, на месте ли папка и хватает '
          'ли в ней места.',
  };
}

/// Больше этого архив примет не каждый мессенджер и не каждая почта.
const int kLargeRecordBytes = 20 * 1024 * 1024;

/// Предупреждение перед отправкой больших архивов; `null` — не нужно.
String? describeLargeShare(List<DeviceRecord> records) {
  int total = 0;
  for (final DeviceRecord record in records) {
    total += record.bytes;
  }
  if (total <= kLargeRecordBytes) {
    return null;
  }
  return 'Архив большой — ${describeFileSize(total)}: почта и часть '
      'мессенджеров такой файл не примут. Надёжнее — через Диск или '
      'кабель.';
}

/// Записи по порядку списка: от новых к старым; без времени старта —
/// в конце, по имени.
List<DeviceRecord> orderRecords(Iterable<DeviceRecord> records) {
  final List<DeviceRecord> ordered = records.toList();
  ordered.sort((DeviceRecord a, DeviceRecord b) {
    final DateTime? left = a.startedAt;
    final DateTime? right = b.startedAt;
    if (left != null && right != null) {
      final int byTime = right.compareTo(left);
      return byTime != 0 ? byTime : b.name.compareTo(a.name);
    }
    if (left != null) {
      return -1;
    }
    if (right != null) {
      return 1;
    }
    return b.name.compareTo(a.name);
  });
  return ordered;
}

/// Строка списка по сведениям записи [info] — манифесту архива или
/// `recording.json` неупакованной папки.
///
/// [state] — отметки об отправке и копии для этой записи; [damaged]
/// — архив не читается или не сходится со своим манифестом.
DeviceRecord recordFrom({
  required String name,
  required int bytes,
  required bool packed,
  required Map<String, Object?>? info,
  bool damaged = false,
  Map<String, Object?> state = const <String, Object?>{},
}) {
  final Object? recording = info?['recording'];
  final Object? participant = info?['participant'];
  final Object? branch = info?['branch'];
  Object? field(Object? from, String key) {
    return from is Map<String, Object?> ? from[key] : null;
  }

  DateTime? moment(Object? raw) {
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  final Object? duration = field(recording, 'duration_ms');
  final Object? events = field(recording, 'events');
  final Object? stopped = field(recording, 'stopped_by');
  final Object? code = field(participant, 'code');
  return DeviceRecord(
    name: name,
    bytes: bytes,
    packed: packed,
    damaged: damaged,
    branch: branch is String ? branch : null,
    participant: code is String ? code : null,
    startedAt: moment(field(recording, 'clock_anchor')),
    durationMs: duration is int ? duration : null,
    events: events is int ? events : null,
    stoppedBy: stopped is String ? stopped : null,
    sharedAt: moment(state['shared_at']),
    copiedAt: moment(state['copied_at']),
  );
}
