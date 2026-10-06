/// Сессия записи (SNO-F-REC-01, SNO-F-CFG-05, SNO-ALG-REC-01).
///
/// Запись — то, ради чего существуют ветви исследования СНО2026: сорок
/// минут работы участника с литературой, сложенные в журнал событий.
/// Здесь её ход: код участника, старт, часы, сердцебиение, остановка —
/// сама через сорок минут или экспериментатором, — и завершение сессии.
///
/// У сессии три состояния ([RecordingPhase]). Пока она не завершена,
/// полка стоит под замком (SNO-F-LIB-02): между остановкой записи и
/// завершением сессии участник заполняет бланк, и расположение книг
/// меняться не должно.
///
/// Состояние сессии лежит в настройках и переживает перезапуск
/// приложения. Запись, которую застал перезапуск, не продолжается:
/// она считается остановленной сбоем.
///
/// Виджетов здесь нет; время, диск и устройство подменяются в тестах.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/settings/app_settings.dart';
import '../participant_code.dart';
import '../settings_keys.dart';
import 'action_log.dart';
import 'clock.dart';
import 'device_passport.dart';
import 'device_status.dart';
import 'event.dart';
import 'input_tap.dart';
import 'journal.dart';
import 'journal_check.dart';
import 'recording_guard.dart';
import 'store.dart';
import 'summary.dart';

/// Сколько длится запись.
const Duration kRecordingLength = Duration(minutes: 40);

/// Как часто пишется сердцебиение, в тиках записи (тик — секунда).
const int kHeartbeatTicks = 10;

/// Ниже какого заряда перед стартом звучит предупреждение, в процентах.
const int kLowBatteryPercent = 30;

/// Меньше какого свободного места перед стартом звучит предупреждение.
const int kLowSpaceBytes = 200 * 1024 * 1024;

/// Ниже какого заряда посреди записи журнал уходит на диск сразу, в
/// процентах (SNO-F-REC-13).
const int kCriticalBatteryPercent = 5;

/// Меньше какого свободного места посреди записи журнал уходит на
/// диск сразу (SNO-F-REC-13).
const int kCriticalSpaceBytes = 20 * 1024 * 1024;

/// Заголовок уведомления, которое висит в шторке, пока идёт запись
/// (SNO-F-REC-13). Ни времени, ни кода участника в нём нет: сколько
/// осталось, участнику не показывается нигде.
const String kGuardTitle = 'Идёт запись';

/// Строка под заголовком уведомления.
const String kGuardText = 'Не закрывайте приложение';

/// Версия сведений о записи.
const String kRecordingSchema = 'sno2026-recording/1';

/// Что происходит с записью.
enum RecordingPhase {
  /// Сессии нет: можно начинать запись.
  idle,

  /// Запись идёт.
  recording,

  /// Запись остановлена, сессия ждёт завершения.
  stopped,
}

/// Кем остановлена запись.
enum StopReason {
  /// Сама: вышли сорок минут.
  auto('auto'),

  /// Экспериментатором — удержанием индикатора и подтверждением.
  experimenter('experimenter'),

  /// Приложение закрыли или оно упало, пока запись шла.
  crash('crash');

  const StopReason(this.wire);

  /// Имя причины в журнале и в сведениях записи.
  final String wire;

  /// Причина по имени; `null` — имя незнакомо.
  static StopReason? named(Object? wire) {
    for (final StopReason reason in StopReason.values) {
      if (reason.wire == wire) {
        return reason;
      }
    }
    return null;
  }
}

/// Готово ли устройство к записи: заряд, свободное место и совпадает
/// ли оно с эталоном.
class Readiness {
  /// Создаёт ответ.
  const Readiness({this.batteryPercent, this.freeBytes, this.matchesReference});

  /// Заряд в процентах; `null` — батареи нет или устройство не ответило.
  final int? batteryPercent;

  /// Свободное место там, где лежат записи; `null` — не узнать.
  final int? freeBytes;

  /// Совпадает ли устройство с эталоном (SNO-F-REC-13); `null` —
  /// эталона нет или сверить не удалось.
  final bool? matchesReference;

  /// Отличается ли устройство от эталона: предупреждение, не запрет.
  bool get differs => matchesReference == false;

  /// Тот же ответ с итогом сверки с эталоном.
  Readiness withReference(bool? matches) {
    return Readiness(
      batteryPercent: batteryPercent,
      freeBytes: freeBytes,
      matchesReference: matches,
    );
  }

  /// Мало ли заряда: предупреждение, не запрет.
  bool get lowBattery {
    final int? percent = batteryPercent;
    return percent != null && percent < kLowBatteryPercent;
  }

  /// Мало ли места: предупреждение, не запрет.
  bool get lowSpace {
    final int? free = freeBytes;
    return free != null && free < kLowSpaceBytes;
  }
}

/// Незавершённая сессия: всё, что о ней надо помнить между запусками.
class SessionState {
  /// Создаёт состояние.
  const SessionState({
    required this.id,
    required this.folder,
    required this.participant,
    required this.startedAt,
    required this.plannedSeconds,
    required this.phase,
    this.stoppedBy,
    this.durationMs,
    this.events = 0,
    this.lastT = 0,
    this.resyncs,
    this.failed = false,
    this.away,
    this.blocks = const <BlockMark>[],
    this.inBackground = false,
    this.check,
    this.passport = const <String, Object?>{},
    this.inputs,
    this.inputCheck,
  });

  /// Идентификатор записи.
  final String id;

  /// Имя папки записи.
  final String folder;

  /// Код участника.
  final ParticipantCode participant;

  /// Настенное время старта.
  final DateTime startedAt;

  /// Сколько запись должна длиться, в секундах.
  final int plannedSeconds;

  /// Идёт запись или остановлена.
  final RecordingPhase phase;

  /// Кем остановлена; `null` — идёт.
  final StopReason? stoppedBy;

  /// Сколько длилась, в миллисекундах; `null` — идёт.
  final int? durationMs;

  /// Сколько строк в журнале на миг остановки.
  final int events;

  /// Время `t` события остановки: у событий, записанных после
  /// перезапуска приложения, оно не меньше.
  final int lastT;

  /// Сколько раз за запись переставляли якорь настенных часов; `null`
  /// — неизвестно: запись оборвалась, и счёт остался в умершем
  /// приложении.
  final int? resyncs;

  /// Не всё записанное легло на диск; `null` — неизвестно: запись
  /// оборвалась, и приложение, которое её писало, умерло. Помнится
  /// между запусками: приложение, перезапущенное до завершения сессии,
  /// иначе написало бы в сведениях записи, что журнал цел.
  final bool? failed;

  /// Отлучки участника за запись (SNO-F-REC-10); `null` — неизвестно:
  /// запись идёт или оборвалась, и счёт остался в умершем приложении.
  final AwaySummary? away;

  /// Блоки тестирования, отмеченные за запись.
  final List<BlockMark> blocks;

  /// Остановилась ли запись, пока приложения не было на переднем плане
  /// (SNO-F-REC-10).
  final bool inBackground;

  /// Итог самопроверки журнала после остановки (SNO-F-REC-13); `null`
  /// — запись идёт, или журнал перечитать не удалось.
  final JournalCheck? check;

  /// Паспорт устройства, каким он был в миг старта (SNO-F-REC-13).
  ///
  /// Помнится между запусками: сведения записи переписываются при
  /// остановке, после сбоя и при завершении, а окно на ПК к тому
  /// времени может быть другим — и до первого кадра его нет вовсе.
  final Map<String, Object?> passport;

  /// Сколько строк потока сырого ввода запись посчитала (SNO-F-REC-11);
  /// `null` — запись идёт, потока у неё нет (запись прежней сборки)
  /// или она оборвалась, и счёт остался в умершем приложении.
  final int? inputs;

  /// Итог самопроверки потока сырого ввода после остановки; `null` —
  /// запись идёт, потока нет или он не перечитался.
  final JournalCheck? inputCheck;

  /// То же состояние с итогом потока сырого ввода (SNO-F-REC-11).
  SessionState withInput({required int? lines, required JournalCheck? check}) {
    return SessionState(
      id: id,
      folder: folder,
      participant: participant,
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      phase: phase,
      stoppedBy: stoppedBy,
      durationMs: durationMs,
      events: events,
      lastT: lastT,
      resyncs: resyncs,
      failed: failed,
      away: away,
      blocks: blocks,
      inBackground: inBackground,
      check: this.check,
      passport: passport,
      inputs: lines,
      inputCheck: check,
    );
  }

  /// То же состояние с итогом самопроверки журнала.
  SessionState withCheck(JournalCheck? check) {
    return SessionState(
      id: id,
      folder: folder,
      participant: participant,
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      phase: phase,
      stoppedBy: stoppedBy,
      durationMs: durationMs,
      events: events,
      lastT: lastT,
      resyncs: resyncs,
      failed: failed,
      away: away,
      blocks: blocks,
      inBackground: inBackground,
      check: check,
      passport: passport,
      inputs: inputs,
      inputCheck: inputCheck,
    );
  }

  /// То же состояние с отметкой о том, лёг ли журнал на диск.
  SessionState withFailure(bool? failed) {
    return SessionState(
      id: id,
      folder: folder,
      participant: participant,
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      phase: phase,
      stoppedBy: stoppedBy,
      durationMs: durationMs,
      events: events,
      lastT: lastT,
      resyncs: resyncs,
      failed: failed,
      away: away,
      blocks: blocks,
      inBackground: inBackground,
      check: check,
      passport: passport,
      inputs: inputs,
      inputCheck: inputCheck,
    );
  }

  /// То же состояние после остановки.
  ///
  /// Отлучки, блоки и признак «остановилась в фоне» остаются прежними,
  /// если не названы: завершение сессии их не пересчитывает.
  SessionState stopped({
    required StopReason by,
    required int durationMs,
    required int events,
    required int lastT,
    required int? resyncs,
    AwaySummary? away,
    List<BlockMark>? blocks,
    bool? inBackground,
  }) {
    return SessionState(
      id: id,
      folder: folder,
      participant: participant,
      startedAt: startedAt,
      plannedSeconds: plannedSeconds,
      phase: RecordingPhase.stopped,
      stoppedBy: by,
      durationMs: durationMs,
      events: events,
      lastT: lastT,
      resyncs: resyncs,
      failed: failed,
      away: away ?? this.away,
      blocks: blocks ?? this.blocks,
      inBackground: inBackground ?? this.inBackground,
      check: check,
      passport: passport,
      inputs: inputs,
      inputCheck: inputCheck,
    );
  }

  /// Запись для настроек.
  String encode() {
    return jsonEncode(<String, Object?>{
      'id': id,
      'folder': folder,
      'participant': participant.toJson(),
      'started_at': startedAt.toUtc().toIso8601String(),
      'planned_s': plannedSeconds,
      'phase': phase.name,
      'stopped_by': stoppedBy?.wire,
      'duration_ms': durationMs,
      'events': events,
      'last_t': lastT,
      'resyncs': resyncs,
      'write_failed': failed,
      'away': away?.toJson(),
      'blocks': <Object?>[for (final BlockMark mark in blocks) mark.toJson()],
      'in_background': inBackground,
      'check': check?.toJson(),
      'passport': passport,
      'inputs': inputs,
      'input_check': inputCheck?.toJson(),
    });
  }

  /// Читает запись; `null` — записи нет или она не читается.
  static SessionState? decode(String? text) {
    if (text == null || text.isEmpty) {
      return null;
    }
    try {
      final Object? raw = jsonDecode(text);
      if (raw is! Map<String, Object?>) {
        return null;
      }
      final Object? id = raw['id'];
      final Object? folder = raw['folder'];
      final Object? startedAt = raw['started_at'];
      final Object? planned = raw['planned_s'];
      final Object? phase = raw['phase'];
      final Object? duration = raw['duration_ms'];
      final Object? events = raw['events'];
      final Object? lastT = raw['last_t'];
      final Object? resyncs = raw['resyncs'];
      final Object? failed = raw['write_failed'];
      final Object? passport = raw['passport'];
      final Object? inputs = raw['inputs'];
      final ParticipantCode? participant = ParticipantCode.fromJson(
        raw['participant'],
      );
      if (id is! String ||
          folder is! String ||
          startedAt is! String ||
          planned is! int ||
          participant == null) {
        return null;
      }
      final DateTime? started = DateTime.tryParse(startedAt);
      if (started == null) {
        return null;
      }
      final bool recording = phase == RecordingPhase.recording.name;
      if (!recording && phase != RecordingPhase.stopped.name) {
        return null;
      }
      return SessionState(
        id: id,
        folder: folder,
        participant: participant,
        startedAt: started.toLocal(),
        plannedSeconds: planned,
        phase: recording ? RecordingPhase.recording : RecordingPhase.stopped,
        stoppedBy: StopReason.named(raw['stopped_by']),
        durationMs: duration is int ? duration : null,
        events: events is int ? events : 0,
        lastT: lastT is int ? lastT : 0,
        resyncs: resyncs is int ? resyncs : null,
        failed: failed is bool ? failed : null,
        away: AwaySummary.fromJson(raw['away']),
        blocks: BlockMark.listFromJson(raw['blocks']),
        inBackground: raw['in_background'] == true,
        check: JournalCheck.fromJson(raw['check']),
        passport: passport is Map<String, Object?>
            ? passport
            : const <String, Object?>{},
        inputs: inputs is int ? inputs : null,
        inputCheck: JournalCheck.fromJson(raw['input_check']),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Заводит тикающий раз в секунду счёт; отвечает тем, как его
/// остановить.
typedef SessionTicker = void Function() Function(void Function() onTick);

/// Заводит монотонные часы; отвечает счётом миллисекунд от старта.
typedef MonotonicSource = int Function() Function();

/// Снимок состояния устройства в начале записи.
typedef SnapshotSource = Future<Map<String, Object?>> Function();

void Function() _timerTicker(void Function() onTick) {
  final Timer timer = Timer.periodic(
    const Duration(seconds: 1),
    (Timer _) => onTick(),
  );
  return timer.cancel;
}

int Function() _stopwatchSource() {
  final Stopwatch stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
}

const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Идентификатор записи — ULID: время и случайный хвост.
///
/// Упорядочен по времени: записи одного устройства встают в списке в
/// том порядке, в каком шли.
String newRecordingId(DateTime now, Random random) {
  final StringBuffer id = StringBuffer();
  int time = now.millisecondsSinceEpoch;
  final List<int> head = List<int>.filled(10, 0);
  for (int i = 9; i >= 0; i--) {
    head[i] = time % 32;
    time ~/= 32;
  }
  for (final int digit in head) {
    id.write(_crockford[digit]);
  }
  for (int i = 0; i < 16; i++) {
    id.write(_crockford[random.nextInt(32)]);
  }
  return id.toString();
}

/// Имя папки записи — то же, что получит её архив:
/// `sno2026_I_67954332_a91f3c_20261103-1402`.
String recordingFolderName({
  required String branch,
  required String code,
  required String device,
  required DateTime startedAt,
}) {
  final DateTime local = startedAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final String day =
      '${local.year.toString().padLeft(4, '0')}'
      '${two(local.month)}${two(local.day)}';
  final String time = '${two(local.hour)}${two(local.minute)}';
  return 'sno2026_${branch}_${code}_${device}_$day-$time';
}

/// Время записи словами: `23:10`.
String describeRecordingTime(int milliseconds) {
  final int seconds = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
}

/// Сессия записи.
///
/// Слушатели узнают о смене состояния ([phase]); [ticks] тикает раз в
/// секунду, пока запись идёт, — по нему обновляется оставшееся время,
/// и остальное дерево от этого не перестраивается.
class RecordingSession extends ChangeNotifier implements ActionLog {
  /// Создаёт сессию.
  ///
  /// [branch], [device] и [build] попадают в сведения записи: ветвь,
  /// первые шесть знаков идентификатора устройства, версия и коммит
  /// сборки. [endSnapshot] — снимок конца записи (SNO-ALG-REC-03): то
  /// же состояние и то, что участник оставил; не назван — берётся
  /// [snapshot]. [guard] держит приложение живым в фоне, [passport]
  /// называет устройство в сведениях записи (SNO-F-REC-13). [now],
  /// [monotonic], [ticker] и [random] подменяются в тестах.
  RecordingSession({
    required AppSettingsRepository settings,
    required RecordingStore store,
    required String nodeId,
    required SnapshotSource snapshot,
    SnapshotSource? endSnapshot,
    this.branch = '',
    this.device = '',
    this.build = const <String, Object?>{},
    DeviceStatus status = const NoDeviceStatus(),
    RecordingGuard guard = const NoRecordingGuard(),
    PassportSource passport = noPassport,
    Duration planned = kRecordingLength,
    DateTime Function()? now,
    MonotonicSource? monotonic,
    SessionTicker? ticker,
    Random? random,
  }) : _settings = settings,
       _store = store,
       _nodeId = nodeId,
       _snapshot = snapshot,
       _endSnapshot = endSnapshot ?? snapshot,
       _status = status,
       _guard = guard,
       _passport = passport,
       _planned = planned,
       _now = now ?? DateTime.now,
       _monotonic = monotonic ?? _stopwatchSource,
       _ticker = ticker ?? _timerTicker,
       _random = random ?? Random.secure();

  final AppSettingsRepository _settings;
  final RecordingStore _store;
  final String _nodeId;
  final SnapshotSource _snapshot;
  final SnapshotSource _endSnapshot;
  final DeviceStatus _status;
  final RecordingGuard _guard;
  final PassportSource _passport;
  final Duration _planned;
  final DateTime Function() _now;
  final MonotonicSource _monotonic;
  final SessionTicker _ticker;
  final Random _random;

  /// Ветвь сборки: `I` или `II`.
  final String branch;

  /// Код устройства: первые шесть знаков идентификатора узла.
  final String device;

  /// Сведения о сборке для записи: версия, коммит, флаги.
  final Map<String, Object?> build;

  /// Где участник находится: подставляется в каждое событие.
  final RecordingContext context = RecordingContext();

  /// Тикает раз в секунду, пока запись идёт.
  final ValueNotifier<int> ticks = ValueNotifier<int>(0);

  /// Открыт ли экран завершения сессии: пока он открыт, плашка,
  /// ведущая на него, не нужна.
  final ValueNotifier<bool> finishOpen = ValueNotifier<bool>(false);

  /// Перечитан ли журнал остановленной записи с диска (SNO-F-REC-13):
  /// итог — в [check]. Остановка меняет состояние раньше диска, и
  /// экран завершения узнаёт об итоге отсюда.
  final ValueNotifier<bool> checked = ValueNotifier<bool>(false);

  SessionState? _state;
  RecordingClock? _clock;
  EventJournal? _journal;

  /// Поток сырого ввода идущей записи (SNO-F-REC-11): его писатель и
  /// сборщик строк; `null` — запись не идёт или поток не открылся.
  EventJournal? _inputJournal;
  InputTracker? _input;

  /// Строка ввода, которой участник открыл экран чтения: открытие
  /// книги — ответ на неё, сколько бы книга ни открывалась.
  int? _readerInput;
  void Function()? _stopTicker;
  int _seq = 0;
  int _beats = 0;
  bool _starting = false;
  Future<void>? _startTail;
  Future<void>? _stopRun;
  Future<void>? _finishRun;
  DateTime? _leftAt;
  int _leftT = 0;
  String? _deepest;
  bool _disposed = false;

  /// В каком состоянии приложение сейчас: `resumed`, `inactive`,
  /// `hidden`, `paused` (SNO-F-REC-10). Ведётся и вне записи — запись
  /// может начаться в любом.
  String _appState = _onScreen;

  /// С какого мига приложения не видно; `null` — оно на виду.
  DateTime? _hiddenAt;
  int _hiddenT = 0;

  /// Записана ли уже сверка часов за идущую отлучку: шагов к переднему
  /// плану несколько, и сверка, которая ничего не сдвинула, пишется
  /// один раз — по возвращении и только если сдвигов не было.
  bool _resyncSaid = false;

  /// Сколько за идущую отлучку приложения не было видно.
  int _hiddenMs = 0;

  /// Погашен ли экран за идущую отлучку — по ответу устройства.
  bool _screenOff = false;

  /// Номер отлучки: запоздавший ответ устройства о прежней не
  /// принимается.
  int _leaveRun = 0;

  /// Отлучки за идущую запись.
  AwaySummary _away = const AwaySummary();

  /// Открытый блок тестирования и время его начала; `null` — блока нет.
  int? _block;
  int _blockT = 0;

  /// Сколько записи прошло к началу открытого блока — тем же счётом,
  /// каким считаются сорок минут.
  int _blockPassed = 0;

  /// Блоки, закрытые за идущую запись.
  List<BlockMark> _blocks = const <BlockMark>[];

  /// Сколько раз за запись открывали каждую книгу.
  final Map<String, int> _visits = <String, int>{};

  /// Когда открыта книга, по часам записи; `null` — книга не открыта
  /// или открыта до записи.
  int? _bookOpenedT;

  /// Не удалось ли записать что-то на диск за эту сессию — и тогда,
  /// когда журнал уже закрыт.
  bool _failed = false;

  /// Известно ли, есть ли незавершённая сессия: отметка о ней
  /// прочитана ([restore]) или записана заново (старт записи).
  bool _known = false;

  /// Заряд и свободное место по последнему ответу устройства
  /// (SNO-F-REC-13): их несёт сердцебиение.
  int? _vitalBattery;
  int? _vitalFree;

  /// Сказано ли уже, что заряд или место на исходе: строка об этом
  /// пишется один раз, а не каждые десять секунд.
  bool _lowBattery = false;
  bool _lowSpace = false;

  /// Номер вопроса о заряде и месте: запоздавший ответ прежнего не
  /// принимается.
  int _vitalsRun = 0;

  /// Состояние незавершённой сессии; `null` — сессии нет.
  SessionState? get state => _state;

  /// Известно ли, какая папка записи принадлежит незавершённой сессии.
  ///
  /// Пока отметка о сессии не прочитана — запуск, на котором база не
  /// ответила, — [state] пуст, но это не значит, что сессии нет: чья
  /// папка лежит среди записей, неизвестно, и трогать папки нельзя
  /// (SNO-F-REC-08).
  bool get known => _known;

  /// Что происходит с записью.
  RecordingPhase get phase => _state?.phase ?? RecordingPhase.idle;

  /// Идёт ли запись.
  @override
  bool get recording => phase == RecordingPhase.recording;

  /// Стоит ли полка под замком: сессия начата и не завершена
  /// (SNO-F-LIB-02).
  bool get locked => phase != RecordingPhase.idle;

  /// Код участника идущей или остановленной сессии.
  ParticipantCode? get participant => _state?.participant;

  /// Сколько запись должна длиться.
  Duration get planned => _planned;

  /// Сколько событий записано.
  int get events => recording ? _seq : (_state?.events ?? 0);

  /// Отлучки участника за остановленную запись (SNO-F-REC-10); `null`
  /// — запись идёт или её нет. У оборванной записи итог собран по
  /// журналу.
  AwaySummary? get away => recording ? null : _state?.away;

  /// Итог самопроверки журнала остановленной записи (SNO-F-REC-13);
  /// `null` — запись идёт, ещё не проверена ([checked]) или журнал не
  /// перечитался.
  JournalCheck? get check => recording ? null : _state?.check;

  /// Сборщик потока сырого ввода (SNO-F-REC-11); `null` — запись не
  /// идёт, и ни одна строка ввода не пишется никуда.
  ///
  /// Сюда слой записи приносит события указателя, колеса и клавиш
  /// (`input_layer.dart`); время для них — [inputNow].
  InputTracker? get input => _logging ? _input : null;

  /// Время `t` по часам записи для строки ввода.
  int get inputNow => _tNow();

  /// Сколько строк ввода посчитала остановленная запись; `null` —
  /// запись идёт, потока нет или счёт неизвестен.
  int? get inputs => recording ? null : _state?.inputs;

  /// Итог самопроверки потока сырого ввода остановленной записи
  /// (SNO-F-REC-11); `null` — запись идёт, потока нет или он не
  /// перечитался.
  JournalCheck? get inputCheck => recording ? null : _state?.inputCheck;

  /// Клавиша, которую Flutter не видит, — кнопка громкости телефона,
  /// перехваченная для листания (SNO-F-REC-11): [name] — её имя в
  /// потоке, [id] отличает одну клавишу от другой.
  void keyInput(
    Object id,
    String name, {
    required bool pressed,
    bool repeat = false,
  }) {
    final InputTracker? tracker = input;
    if (tracker == null) {
      return;
    }
    final int t = _tNow();
    if (!pressed) {
      tracker.keyUp(id, t: t);
    } else if (repeat) {
      tracker.keyRepeat(id, t: t);
    } else {
      tracker.keyDown(id, t: t, name: name, screen: context.screen);
    }
  }

  /// Строка потока сырого ввода — в его файл. Строка, которая не
  /// пишется в JSON, не роняет экран: пишется без данных, с тем же
  /// номером.
  void _writeInput(Map<String, Object?> line) {
    final EventJournal? journal = _inputJournal;
    if (journal == null) {
      return;
    }
    String encoded;
    try {
      encoded = jsonEncode(line);
    } on Object {
      encoded = jsonEncode(<String, Object?>{
        'n': line['n'],
        't': line['t'],
        'unencodable': true,
      });
    }
    journal.add(encoded);
  }

  /// Блоки тестирования, закрытые за запись.
  List<BlockMark> get blocks {
    return recording ? _blocks : (_state?.blocks ?? const <BlockMark>[]);
  }

  /// Номер открытого блока; `null` — блок не идёт.
  int? get block => recording ? _block : null;

  /// Сколько идёт открытый блок, в миллисекундах.
  ///
  /// Счёт тот же, что у сорока минут: сон устройства в блок входит, а
  /// время после конца записи — нет.
  int get blockElapsedMs {
    final SessionState? state = _state;
    if (state == null || !recording || _block == null) {
      return 0;
    }
    final int passed = _countedMs(state) - _blockPassed;
    return passed < 0 ? 0 : passed;
  }

  /// Какой номер предложить следующему блоку: за последним закрытым.
  int get nextBlock => _blocks.isEmpty ? 1 : _blocks.last.number + 1;

  /// Не удалось ли записать что-то на диск.
  bool get writeFailed => _failed || (_journal?.failed ?? false);

  /// Сколько запись идёт или шла, в миллисекундах.
  int get elapsedMs {
    final SessionState? state = _state;
    if (state == null) {
      return 0;
    }
    final int? done = state.durationMs;
    if (done != null) {
      return done;
    }
    final int limit = _planned.inMilliseconds;
    final int passed = _passedMs(state);
    return passed > limit ? limit : passed;
  }

  /// Сколько записи осталось, в миллисекундах.
  int get remainingMs => _planned.inMilliseconds - elapsedMs;

  int _wallElapsedMs(SessionState state) {
    return _now().difference(state.startedAt).inMilliseconds;
  }

  /// Сколько прошло от старта: большее из настенного и монотонного
  /// счёта, не меньше нуля.
  ///
  /// Сорок минут считаются по настенным часам: монотонные во сне
  /// устройства стоят. Монотонные учитываются тоже — на случай, если
  /// настенные перевели назад: запись не должна от этого растянуться,
  /// а её длительность — обнулиться.
  int _passedMs(SessionState state) {
    final RecordingClock? clock = _clock;
    final int wall = clock?.wallElapsedMs ?? _wallElapsedMs(state);
    final int monotonic = clock?.t ?? 0;
    final int passed = wall > monotonic ? wall : monotonic;
    return passed < 0 ? 0 : passed;
  }

  /// Сколько записи прошло, не больше положенного ей.
  int _countedMs(SessionState state) {
    final int limit = _planned.inMilliseconds;
    final int passed = _passedMs(state);
    return passed > limit ? limit : passed;
  }

  /// Большее из настенного и монотонного счёта от мига [at] (`t` —
  /// [atT]) до мига [now] (`t` — [nowT]), не меньше нуля: монотонные
  /// часы стоят во сне устройства, настенные могут перевести назад.
  static int _span(DateTime at, int atT, DateTime now, int nowT) {
    final int byWall = now.difference(at).inMilliseconds;
    final int byT = nowT - atT;
    final int span = byWall > byT ? byWall : byT;
    return span < 0 ? 0 : span;
  }

  /// Поднимает сессию после запуска приложения.
  ///
  /// Запись, которую застал перезапуск, не продолжается: приложение
  /// закрыли или оно упало. Она становится остановленной сбоем, длиной
  /// по последнему событию журнала, и ждёт завершения.
  Future<void> restore() async {
    final String? stored = await _settings.read(SnoSettingsKeys.session);
    final SessionState? state = SessionState.decode(stored);
    if (state == null) {
      if (stored != null) {
        // Запись не читается — сессии по ней не поднять; замок, который
        // нечем снять, хуже потерянной отметки.
        await _settings.remove(SnoSettingsKeys.session);
      }
      _known = true;
      _releaseGuard();
      return;
    }
    // SNO-F-REC-13: служба переднего плана пережить запуск не должна —
    // запись, которую застал перезапуск, не продолжается.
    _releaseGuard();
    if (state.phase == RecordingPhase.stopped) {
      // Запись остановлена прежней сборкой, которая журнал не
      // перечитывала: он сверяется сейчас, пока его не открыли.
      // У записи, закрытой после сбоя, «цела» не говорится и теперь:
      // потерянного за последней строкой проверка не видит.
      final JournalCheck? check =
          state.check ??
          await _checkJournal(
            state.folder,
            expected: state.events,
            late: state.stoppedBy == StopReason.crash,
          );
      final List<EventMarks> tail = await _tail(state.folder);
      _state = state.withCheck(check);
      _setChecked(true);
      _known = true;
      _failed = state.failed ?? false;
      // Номер продолжает журнал: отметка сессии могла отстать от него.
      final int written = tail.isEmpty ? 0 : tail.last.seq;
      _seq = written > state.events ? written : state.events;
      _notify();
      return;
    }
    // SNO-F-REC-13: журнал сверяется таким, каким его оставило умершее
    // приложение, — до того, как чтение отрежет оборванный хвост.
    final JournalCheck? check = await _checkJournal(state.folder, late: true);
    // SNO-F-REC-11: поток ввода сверяется так же — каким он остался.
    // Сколько строк запись посчитала, спросить не у кого.
    final JournalCheck? inputCheck = await _checkJournal(
      state.folder,
      late: true,
      name: kInputFile,
      key: 'n',
    );
    // Оборванной записи нужен журнал целиком: блоки и отлучки остались
    // только в нём.
    _state = await _stoppedByCrash(
      state.withInput(lines: null, check: inputCheck),
      await _tail(state.folder, count: _wholeJournal),
      check,
    );
    _setChecked(true);
    _known = true;
    _notify();
  }

  /// Перечитывает журнал записи [folder] с диска и сверяет его сам с
  /// собой (SNO-F-REC-13); `null` — журнал не прочитался.
  ///
  /// [expected] — сколько событий запись посчитала; [late] — проверка
  /// идёт при следующем запуске, а не в миг остановки. [name] и [key]
  /// — какой поток строк и поле его сквозного номера: журнал событий
  /// либо поток сырого ввода (SNO-F-REC-11).
  Future<JournalCheck?> _checkJournal(
    String folder, {
    int? expected,
    bool late = false,
    String name = kEventsFile,
    String key = 'seq',
  }) async {
    try {
      final List<int>? bytes = await _store.journalBytes(folder, name: name);
      if (bytes == null) {
        return null;
      }
      return checkJournal(bytes, expected: expected, late: late, key: key);
    } on Object {
      return null;
    }
  }

  /// Столько строк, чтобы журнал прочитался целиком.
  static const int _wholeJournal = 1 << 30;

  /// Последние читаемые события журнала; пусто — журнала нет или он не
  /// читается.
  Future<List<EventMarks>> _tail(
    String folder, {
    int count = kTailLines,
  }) async {
    try {
      return readableEvents(await _store.lastLines(folder, count: count));
    } on Object {
      return const <EventMarks>[];
    }
  }

  /// Закрывает запись, оборванную перезапуском приложения.
  ///
  /// Журнал [tail] говорит, сколько она длилась, какие блоки в ней
  /// отмечены и сколько участник отсутствовал: в памяти этого не
  /// осталось (SNO-F-REC-10, SNO-F-CFG-03). Если в нём уже есть
  /// остановка — приложение умерло между остановкой и отметкой о ней,
  /// — запись закрывается ею, а не второй остановкой поверх.
  Future<SessionState> _stoppedByCrash(
    SessionState state,
    List<EventMarks> tail,
    JournalCheck? check,
  ) async {
    final int limit = state.plannedSeconds * 1000;
    int clip(int value) => value < 0 ? 0 : (value > limit ? limit : value);

    final EventMarks? last = tail.isEmpty ? null : tail.last;
    EventMarks? stop;
    for (final EventMarks event in tail) {
      if (event.type == SnoEventType.recordingStop.wire) {
        stop = event;
      }
    }
    _seq = last?.seq ?? 0;
    // SNO-F-REC-10: оборвалась ли запись, пока приложения не было на
    // переднем плане, — по последнему слову журнала о его состоянии.
    bool away = false;
    for (final EventMarks event in tail) {
      if (event.type == SnoEventType.appState.wire) {
        away = event.data['to'] != _onScreen;
      } else if (event.type == SnoEventType.appBackground.wire) {
        away = true;
      } else if (event.type == SnoEventType.appForeground.wire) {
        away = false;
      } else if (event.type == SnoEventType.heartbeat.wire) {
        away = event.data['state'] is String;
      }
    }
    final JournalSummary told = summarizeJournal(tail);
    final BlockMark? open = told.openBlock;
    final SessionState stopped;
    if (stop != null) {
      final Object? duration = stop.data['duration_ms'];
      stopped = state.stopped(
        by: StopReason.named(stop.data['stopped_by']) ?? StopReason.crash,
        durationMs: clip(duration is int ? duration : stop.t),
        events: _seq,
        lastT: last?.t ?? stop.t,
        resyncs: null,
        away: told.away,
        blocks: told.blocks,
        inBackground: stop.data['in_background'] == true,
      );
    } else {
      final int t = last?.t ?? 0;
      // Длительность — как у живой записи: большее из настенного и
      // монотонного счёта. Сон устройства в неё входит, а перевод
      // часов назад её не обнуляет.
      final DateTime? wall = last?.wall;
      final int byWall = wall == null
          ? 0
          : wall.difference(state.startedAt).inMilliseconds;
      final int duration = clip(byWall > t ? byWall : t);
      try {
        final EventJournal journal = EventJournal(
          await _store.openJournal(state.folder),
        );
        final DateTime now = _now();
        int written = 0;
        if (open != null) {
          // Блок, который некому было закрыть, закрывается здесь — тем
          // же последним мигом журнала (SNO-F-CFG-03).
          written++;
          journal.add(
            encodeEvent(
              seq: _seq + written,
              t: t,
              wall: now,
              type: SnoEventType.blockEnd,
              context: context,
              data: <String, Object?>{
                'n': open.number,
                'duration_ms': open.durationMs,
                'by': open.closedBy,
                'late': true,
              },
            ),
          );
        }
        written++;
        journal.add(
          encodeEvent(
            seq: _seq + written,
            t: t,
            wall: now,
            type: SnoEventType.recordingStop,
            context: context,
            data: <String, Object?>{
              'stopped_by': StopReason.crash.wire,
              'duration_ms': duration,
              'late': true,
              if (away) 'in_background': true,
            },
          ),
        );
        await journal.close();
        if (journal.failed) {
          _failed = true;
        } else {
          _seq += written;
        }
      } on Object {
        // Строка остановки не легла: запись всё равно закрывается —
        // замок на полке обязан сниматься.
        _failed = true;
      }
      stopped = state.stopped(
        by: StopReason.crash,
        durationMs: duration,
        events: _seq,
        lastT: t,
        resyncs: null,
        away: told.away,
        blocks: <BlockMark>[...told.blocks, if (open != null) open],
        inBackground: away,
      );
    }
    // Снимок конца оборванной записи — сейчас, при первом же запуске:
    // раньше его снять было некому. И до отметки о сессии: запуск,
    // оборванный между ними, снимет его в следующий раз, а отказ диска
    // на нём попадёт в отметку. Снимок, который уже лежит, остаётся,
    // что бы ни говорил журнал: его положило прежнее приложение в миг
    // остановки или прошлый запуск — и он не позже нового. Журнал мог
    // и не прочитаться, и тогда остановки в нём «нет».
    if (!await _hasEndSnapshot(state.folder)) {
      await _putEndSnapshot(state.folder, late: true);
    }
    // Лёг ли журнал умершего приложения на диск, узнать не у кого:
    // известно только то, что не записалось сейчас.
    final SessionState marked = stopped
        .withFailure(_failed ? true : null)
        .withCheck(check);
    try {
      await _settings.write(SnoSettingsKeys.session, marked.encode());
    } on Object {
      // Отметка не записалась: при следующем запуске запись закроется
      // так же — по строке остановки, которая уже лежит в журнале.
    }
    await _putInfo(marked, finished: false);
    return marked;
  }

  Future<bool> _hasEndSnapshot(String folder) async {
    try {
      return await _store.has(folder, kSnapshotEndFile);
    } on Object {
      return false;
    }
  }

  /// Заряд и свободное место — перед стартом.
  Future<Readiness> readiness() async {
    return Readiness(
      batteryPercent: await _battery(),
      freeBytes: await _freeBytes(),
    );
  }

  Future<int?> _battery() async {
    try {
      return await _status.batteryPercent();
    } on Object {
      return null;
    }
  }

  Future<int?> _freeBytes() async {
    try {
      return await _status.freeBytes(await _store.location());
    } on Object {
      return null;
    }
  }

  /// Семёрки цифр кодов, уже встречавшихся на этом устройстве.
  Future<Set<String>> _knownCodes() async {
    return decodeKnownCodes(await _settings.read(SnoSettingsKeys.knownCodes));
  }

  /// Выдаёт код для нового участника (SNO-F-CFG-05).
  ///
  /// Код ещё не действует: он станет кодом сессии, когда участник
  /// подтвердит, что записал его, и запись начнётся ([start]).
  Future<ParticipantCode> proposeCode() async {
    return generateParticipantCode(
      nodeId: _nodeId,
      now: _now(),
      known: await _knownCodes(),
    );
  }

  /// Код, введённый вместо выданного; `null` — контрольная цифра не
  /// сходится.
  ParticipantCode? enteredCode(String input) {
    return enteredParticipantCode(input, _now());
  }

  /// Начинает запись с кодом участника [participant] (SNO-F-REC-01).
  ///
  /// Отвечает, началась ли запись: вторая запись поверх идущей или
  /// незавершённой сессии не начинается.
  Future<bool> start(ParticipantCode participant) async {
    if (_starting || _state != null || _disposed) {
      return false;
    }
    _starting = true;
    try {
      return await _start(participant);
    } finally {
      _starting = false;
    }
  }

  Future<bool> _start(ParticipantCode participant) async {
    // Снимок — до первой своей записи в настройки: в нём состояние, с
    // которого участник начинает, а не следы самой записи.
    final Map<String, Object?> snapshot = await _takeSnapshot();
    final String? sort = await _settings.read(SettingsKeys.shelfSort);
    final String? lastReset = await _settings.read(SnoSettingsKeys.lastReset);
    final int since =
        int.tryParse(
          await _settings.read(SnoSettingsKeys.recordingsSinceReset) ?? '',
        ) ??
        0;

    final String folder;
    final EventJournal journal;
    try {
      folder = await _store.create(
        recordingFolderName(
          branch: branch,
          code: participant.code,
          device: device,
          startedAt: _now(),
        ),
      );
    } on Object {
      // Папку записи завести не удалось: записи нет, сессии тоже.
      return false;
    }
    try {
      journal = EventJournal(await _store.openJournal(folder));
    } on Object {
      await _discard(folder);
      return false;
    }
    // SNO-F-REC-11: поток сырого ввода — вторым писателем того же вида.
    // Не открылся — запись идёт без него, и об отказе диска сказано.
    EventJournal? inputJournal;
    try {
      inputJournal = EventJournal(
        await _store.openJournal(folder, name: kInputFile),
      );
    } on Object {
      inputJournal = null;
    }

    // SNO-F-REC-13: паспорт — до часов записи: вопрос к устройству в
    // её время не входит.
    final Map<String, Object?> passport = await _passportOf();
    final int Function() elapsed = _monotonic();
    final RecordingClock clock = RecordingClock(now: _now, elapsedMs: elapsed);
    final SessionState state = SessionState(
      id: newRecordingId(clock.anchor, _random),
      folder: folder,
      participant: participant,
      startedAt: clock.anchor,
      plannedSeconds: _planned.inSeconds,
      phase: RecordingPhase.recording,
      passport: passport,
    );
    try {
      // Код — раньше отметки о сессии: отказ на нём не оставит сессии,
      // которой не было.
      final Set<String> known = await _knownCodes();
      if (known.add(participant.base)) {
        await _settings.write(
          SnoSettingsKeys.knownCodes,
          encodeKnownCodes(known),
        );
      }
      // Отметка о сессии — до первого события: приложение, упавшее
      // сразу после, найдёт сессию и закроет её.
      await _settings.write(SnoSettingsKeys.session, state.encode());
      // Счёт записей после сброса — последним: несостоявшийся старт
      // его не увеличит.
      await _settings.write(
        SnoSettingsKeys.recordingsSinceReset,
        '${since + 1}',
      );
    } on Object {
      await _abandon(journal, inputJournal, folder);
      return false;
    }
    if (_disposed) {
      await _abandon(journal, inputJournal, folder);
      return false;
    }
    // Отметка о сессии теперь наша: чья папка — известно.
    _known = true;
    _clock = clock;
    _journal = journal;
    _inputJournal = inputJournal;
    _input = inputJournal == null ? null : InputTracker(_writeInput);
    _readerInput = null;
    _failed = inputJournal == null;
    _seq = 0;
    _beats = 0;
    _leftAt = null;
    _deepest = null;
    _hiddenAt = null;
    _hiddenMs = 0;
    _screenOff = false;
    _resyncSaid = false;
    _away = const AwaySummary();
    _block = null;
    _blocks = const <BlockMark>[];
    _visits.clear();
    _bookOpenedT = null;
    _vitalBattery = null;
    _vitalFree = null;
    _lowBattery = false;
    _lowSpace = false;
    _setChecked(false);
    _state = state;

    final Object? reference = snapshot['reference'];
    // Старт — это `t = 0` по определению: обращения к базе между
    // заведением часов и этой строкой в него не входят.
    _write(
      SnoEventType.recordingStart,
      at: 0,
      data: <String, Object?>{
        'recording': state.id,
        'planned_s': state.plannedSeconds,
        'clock_anchor': isoWithOffset(clock.anchor),
        'participant': participant.code,
        'code_generated': participant.generated,
        // Под замком полка стоит в порядке «Как расставил»; если был
        // выбран другой, участник до старта видел её иначе.
        'shelf_sort': sort ?? 'default',
        'shelf_sort_forced': sort != null && sort != 'manual',
        if (reference is Map<String, Object?>)
          'matches_reference': reference['matches'],
      },
    );
    if (lastReset != null) {
      // Сброс записан с числом записей, начатых после него: ноль —
      // участник начинает с только что сброшенного устройства.
      _write(
        SnoEventType.stateReset,
        at: 0,
        data: <String, Object?>{'at': lastReset, 'recordings_since': since},
      );
    }
    if (_appState != _onScreen) {
      // SNO-F-REC-10: запись началась, когда приложение уже не на
      // переднем плане (окно потеряло фокус, пока шёл старт), — отлучка
      // идёт с первого мига, иначе её начало не знал бы никто.
      _openAbsence(_appState, clock.anchor, 0);
      unawaited(_readScreen(_leaveRun));
    }
    _stopTicker = _ticker(tick);
    // SNO-F-REC-13: служба переднего плана — на всё время записи;
    // заряд и место — для первого же сердцебиения. Ни того, ни
    // другого запись не ждёт.
    unawaited(_holdGuard());
    unawaited(_readVitals());
    // Замок и точка записи появляются сразу; диск догоняет.
    final Future<void> tail = _startFiles(state, journal, snapshot);
    _startTail = tail;
    _notify();
    await tail;
    if (identical(_startTail, tail)) {
      _startTail = null;
    }
    return true;
  }

  /// Файлы начала записи: снимок, сведения, первые строки журнала.
  Future<void> _startFiles(
    SessionState state,
    EventJournal journal,
    Map<String, Object?> snapshot,
  ) async {
    try {
      await _store.put(state.folder, kSnapshotStartFile, _pretty(snapshot));
    } on Object {
      _failed = true;
    }
    await _putInfo(state, finished: false);
    await journal.flush();
    _keepScreen(true);
  }

  /// Просит устройство держать экран включённым или отпускает его.
  ///
  /// Ответа не ждёт: запись, её остановка и завершение сессии не
  /// должны стоять за устройством, которое молчит.
  void _keepScreen(bool on) {
    unawaited(_askScreen(on));
  }

  Future<void> _askScreen(bool on) async {
    try {
      await _status.keepScreenOn(on);
    } on Object {
      // Экран погаснет или останется включённым — запись от этого не
      // пропадает.
    }
  }

  /// Разрешены ли приложению уведомления (SNO-F-REC-13); `null` —
  /// спрашивать не о чем: защиты записи у устройства нет, или система
  /// не ответила.
  Future<bool?> notificationsAllowed() async {
    if (!_guard.guards) {
      return null;
    }
    try {
      return await _guard.notificationsAllowed();
    } on Object {
      return null;
    }
  }

  /// Готовит защиту записи перед стартом (SNO-F-REC-13): если
  /// уведомления не разрешены, один раз за всё время спрашивает о них
  /// системным окном. Отвечает, разрешены ли они теперь.
  ///
  /// Отказ старту не мешает: без уведомления запись идёт, но в фоне
  /// защищена хуже — об этом говорит раздел «Тестирование».
  Future<bool?> prepareGuard() async {
    final bool? allowed = await notificationsAllowed();
    if (allowed != false) {
      return allowed;
    }
    try {
      if (await _settings.read(SnoSettingsKeys.notificationsAsked) != null) {
        return false;
      }
    } on Object {
      // Спрашивали или нет, неизвестно: второй вопрос подряд хуже
      // пропущенного.
      return false;
    }
    bool? answer;
    try {
      answer = await _guard.askNotifications();
    } on Object {
      answer = null;
    }
    if (answer == null) {
      // Система не ответила — окно могло и не показаться: спросим ещё
      // раз при следующем старте.
      return false;
    }
    try {
      await _settings.write(SnoSettingsKeys.notificationsAsked, 'true');
    } on Object {
      // Отметка не легла: спросим ещё раз при следующем старте.
    }
    return answer;
  }

  /// Заводит службу переднего плана и пишет в журнал, заведена ли она
  /// (SNO-F-REC-13).
  Future<void> _holdGuard() async {
    if (!_guard.guards) {
      return;
    }
    bool held;
    try {
      held = await _guard.hold(title: kGuardTitle, text: kGuardText);
    } on Object {
      held = false;
    }
    final bool? allowed = await notificationsAllowed();
    if (!_logging) {
      // Запись остановили, пока служба заводилась: держать ей нечего.
      _releaseGuard();
      return;
    }
    _write(
      SnoEventType.recordingGuard,
      data: <String, Object?>{
        'service': held,
        if (allowed != null) 'notifications': allowed,
      },
    );
  }

  /// Снимает службу переднего плана; ответа не ждёт.
  void _releaseGuard() {
    if (_guard.guards) {
      unawaited(_askRelease());
    }
  }

  Future<void> _askRelease() async {
    try {
      await _guard.release();
    } on Object {
      // Уведомление осталось висеть: его снимет закрытие приложения.
    }
  }

  /// Спрашивает у устройства заряд и свободное место — для следующего
  /// сердцебиения (SNO-F-REC-13).
  ///
  /// Заряд ниже [kCriticalBatteryPercent] или места меньше
  /// [kCriticalSpaceBytes] — журнал уходит на диск сразу, а в журнале
  /// остаётся строка о причине: устройство может выключиться раньше
  /// следующей секунды. Строка пишется один раз на каждое падение ниже
  /// порога.
  Future<void> _readVitals() async {
    final int run = ++_vitalsRun;
    final int? battery = await _battery();
    final int? free = await _freeBytes();
    if (run != _vitalsRun || !_logging) {
      return;
    }
    _vitalBattery = battery;
    _vitalFree = free;
    final bool lowBattery =
        battery != null && battery < kCriticalBatteryPercent;
    final bool lowSpace = free != null && free < kCriticalSpaceBytes;
    final List<String> what = <String>[
      if (lowBattery && !_lowBattery) 'battery',
      if (lowSpace && !_lowSpace) 'space',
    ];
    _lowBattery = lowBattery;
    _lowSpace = lowSpace;
    if (what.isEmpty) {
      return;
    }
    _write(
      SnoEventType.deviceLow,
      data: <String, Object?>{'what': what, ..._vitals()},
    );
    unawaited(_journal?.flush());
  }

  /// Заряд и свободное место для события; чего устройство не сказало,
  /// того нет.
  Map<String, Object?> _vitals() {
    final int? battery = _vitalBattery;
    final int? free = _vitalFree;
    return <String, Object?>{
      if (battery != null) 'battery': battery,
      if (free != null) 'free_mb': free ~/ (1024 * 1024),
    };
  }

  /// Паспорт устройства для сведений о записи; не отдали — пустой.
  Future<Map<String, Object?>> _passportOf() async {
    try {
      return await _passport();
    } on Object {
      return const <String, Object?>{};
    }
  }

  /// Запись не началась: журнал закрыт, отметки и папки не остаётся.
  Future<void> _abandon(
    EventJournal journal,
    EventJournal? inputJournal,
    String folder,
  ) async {
    await journal.close();
    await inputJournal?.close();
    try {
      await _settings.remove(SnoSettingsKeys.session);
    } on Object {
      // Отметка осталась: запуск приложения закроет её как оборванную.
    }
    await _discard(folder);
  }

  Future<void> _discard(String folder) async {
    try {
      await _store.discard(folder);
    } on Object {
      // Пустая папка осталась среди незавершённых.
    }
  }

  /// Снимок состояния; не удался — так в нём и сказано.
  Future<Map<String, Object?>> _takeSnapshot() async {
    try {
      return await _snapshot();
    } on Object {
      return <String, Object?>{'failed': true};
    }
  }

  /// Кладёт в папку записи снимок её конца (SNO-ALG-REC-03): с чем
  /// участник закончил — места чтения, цитаты, заметки, настройки.
  ///
  /// [late] — запись оборвалась, и снимок снят при следующем запуске
  /// приложения, а не в миг остановки.
  Future<void> _putEndSnapshot(String folder, {required bool late}) async {
    Map<String, Object?> snapshot;
    try {
      snapshot = await _endSnapshot();
    } on Object {
      snapshot = <String, Object?>{'failed': true};
    }
    try {
      await _store.put(
        folder,
        kSnapshotEndFile,
        _pretty(<String, Object?>{...snapshot, if (late) 'late': true}),
      );
    } on Object {
      _failed = true;
    }
  }

  String _pretty(Map<String, Object?> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Легло ли записанное на диск: `true` — не всё, и журналу нельзя
  /// верить без оглядки; `null` — неизвестно: запись закрыта после
  /// сбоя, и приложение, которое её писало, умерло.
  bool? _failureOf(SessionState state) {
    if (writeFailed) {
      return true;
    }
    return state.failed == null ? null : false;
  }

  /// Пишет сведения о записи — участник, устройство, сборка, часы,
  /// остановка. Из них соберётся манифест архива (SNO-F-REC-05).
  Future<void> _putInfo(SessionState state, {required bool finished}) async {
    final int? duration = state.durationMs;
    final bool running = state.phase == RecordingPhase.recording;
    final JournalCheck? check = state.check;
    final int? inputs = state.inputs;
    final JournalCheck? inputCheck = state.inputCheck;
    final Map<String, Object?> info = <String, Object?>{
      'schema': kRecordingSchema,
      'branch': branch,
      'app': build,
      // SNO-F-REC-13: паспорт устройства — производитель, модель,
      // система, экран, масштаб шрифта, какими они были в миг старта;
      // узел и код стоят последними: паспорт их не подменит.
      'device': <String, Object?>{
        ...state.passport,
        'node_id': _nodeId,
        'code': device,
      },
      'participant': state.participant.toJson(),
      'recording': <String, Object?>{
        'id': state.id,
        'clock_anchor': isoWithOffset(state.startedAt),
        'planned_s': state.plannedSeconds,
        'duration_s': duration == null ? null : duration ~/ 1000,
        'duration_ms': duration,
        'stopped_by': state.stoppedBy?.wire,
        'resyncs': running ? null : state.resyncs,
        'events': running ? null : state.events,
        'write_failed': _failureOf(state),
        'finished': finished,
        // SNO-F-REC-10: итог отлучек — после остановки; у оборванной
        // записи он собран по журналу.
        'away': running ? null : state.away?.toJson(),
        'in_background': running ? null : state.inBackground,
        'blocks': running
            ? null
            : <Object?>[
                for (final BlockMark mark in state.blocks) mark.toJson(),
              ],
        // SNO-F-REC-13: итог самопроверки журнала после остановки.
        if (!running && check != null) 'check': check.toJson(),
      },
      // SNO-F-REC-11: поток сырого ввода — сколько строк запись
      // посчитала, цел ли он на диске и чего он не видит: разбор не
      // должен принять отсутствие строк за отсутствие нажатий.
      if (!running && (inputs != null || inputCheck != null))
        'input': <String, Object?>{
          'file': kInputFile,
          'lines': inputs,
          if (inputCheck != null) 'check': inputCheck.toJson(),
          'blind': kInputBlind,
        },
    };
    try {
      await _store.put(state.folder, kRecordingFile, _pretty(info));
    } on Object {
      _failed = true;
    }
  }

  /// Время `t` для события сейчас.
  ///
  /// Пока часы записи живы — по ним. После перезапуска приложения
  /// часов нет: время считается от настенного старта, но не меньше
  /// времени остановки — `t` в журнале не убывает.
  int _tNow() {
    final RecordingClock? clock = _clock;
    if (clock != null) {
      return clock.t;
    }
    final SessionState? state = _state;
    if (state == null) {
      return 0;
    }
    final int wall = _wallElapsedMs(state);
    return wall > state.lastT ? wall : state.lastT;
  }

  /// Пишет событие в журнал записи (SNO-F-REC-02).
  ///
  /// Вне записи не делает ничего: пока запись не идёт, ни одна строка
  /// не пишется никуда. Места вызова стоят рядом с действиями
  /// участника и помечены `// SNO-F-REC-02`.
  @override
  void log(
    SnoEventType type, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!_logging) {
      return;
    }
    _write(type, data: data);
  }

  /// Пишутся ли сейчас события: запись идёт и не останавливается.
  bool get _logging => recording && _stopRun == null;

  @override
  void screen(String name) {
    final String from = context.screen;
    if (from == name) {
      return;
    }
    // Экран стоит в событии перехода уже новый: событие — о том, куда
    // участник пришёл.
    context.screen = name;
    log(
      SnoEventType.navScreen,
      data: <String, Object?>{'from': from, 'to': name},
    );
    // SNO-F-REC-11: нажатие, которым открыли экран чтения, помнится —
    // книга может открываться дольше окна связи.
    _readerInput = name == 'reader' ? input?.linkAt(_tNow()) : null;
  }

  @override
  void bookOpened(
    String book, {
    required String via,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    context.book = book;
    if (!_logging) {
      _bookOpenedT = null;
      return;
    }
    final int visit = (_visits[book] ?? 0) + 1;
    _visits[book] = visit;
    final int t = _tNow();
    _bookOpenedT = t;
    _write(
      SnoEventType.bookOpen,
      at: t,
      data: <String, Object?>{'via': via, 'visit': visit, ...data},
      input: _readerInput,
    );
    _readerInput = null;
  }

  @override
  void bookClosed({Map<String, Object?> data = const <String, Object?>{}}) {
    if (context.book == null) {
      return;
    }
    if (_logging) {
      final int t = _tNow();
      final int? opened = _bookOpenedT;
      _write(
        SnoEventType.bookClose,
        at: t,
        data: <String, Object?>{
          if (opened != null) 'open_ms': t - opened,
          ...data,
        },
      );
    }
    _bookOpenedT = null;
    context
      ..book = null
      ..page = null
      ..strip = null
      ..mode = null;
  }

  @override
  void place({required int page, required int strip, required String mode}) {
    context
      ..page = page
      ..strip = strip
      ..mode = mode;
  }

  /// Начинает блок тестирования номер [number] (SNO-F-CFG-03).
  ///
  /// Блок один: пока открыт прежний, новый не начинается. Отвечает,
  /// начат ли блок.
  bool startBlock(int number) {
    if (!_logging || _block != null || number < 1) {
      return false;
    }
    final SessionState? state = _state;
    final int t = _tNow();
    _block = number;
    _blockT = t;
    _blockPassed = state == null ? 0 : _countedMs(state);
    _write(
      SnoEventType.blockStart,
      at: t,
      data: <String, Object?>{'n': number},
    );
    _notify();
    return true;
  }

  /// Заканчивает открытый блок. Отвечает, было ли что заканчивать.
  bool endBlock() {
    if (!_logging || _block == null) {
      return false;
    }
    _closeBlock(by: 'experimenter', at: _tNow());
    _notify();
    return true;
  }

  /// Закрывает открытый блок событием и отметкой; [by] — чем закрыт.
  void _closeBlock({required String by, required int at}) {
    final int? number = _block;
    if (number == null) {
      return;
    }
    // Длительность — по счёту записи, а не по `t`: блок, в который
    // попал сон устройства, не выходит короче, а блок, который закрыла
    // запоздавшая остановка, не длиннее записи.
    final int duration = blockElapsedMs;
    _block = null;
    _blocks = List<BlockMark>.unmodifiable(<BlockMark>[
      ..._blocks,
      BlockMark(
        number: number,
        startMs: _blockT,
        durationMs: duration,
        closedBy: by,
      ),
    ]);
    _write(
      SnoEventType.blockEnd,
      at: at,
      data: <String, Object?>{'n': number, 'duration_ms': duration, 'by': by},
    );
  }

  /// События, которые запись пишет сама, а не в ответ на действие
  /// участника: на строку ввода они не ссылаются (SNO-F-REC-11).
  static const Set<SnoEventType> _unprompted = <SnoEventType>{
    SnoEventType.recordingStart,
    SnoEventType.recordingStop,
    SnoEventType.appState,
    SnoEventType.appBackground,
    SnoEventType.appForeground,
    SnoEventType.clockResync,
    SnoEventType.heartbeat,
    SnoEventType.recordingGuard,
    SnoEventType.deviceLow,
    SnoEventType.stateReset,
    SnoEventType.sessionFinish,
    SnoEventType.indexProgress,
  };

  /// Строка журнала с номером и временем; без открытого журнала не
  /// делает ничего. [at] — время события, если оно известно заранее.
  /// [input] — строка ввода, на которую событие ссылается, если окно
  /// связи её уже не помнит.
  void _write(
    SnoEventType type, {
    Map<String, Object?> data = const <String, Object?>{},
    bool post = false,
    int? at,
    int? input,
  }) {
    final EventJournal? journal = _journal;
    if (journal == null) {
      return;
    }
    final RecordingClock? clock = _clock;
    final int t = at ?? _tNow();
    // SNO-F-REC-11: событие, записанное, пока палец на экране или
    // сразу после, — ответ на это касание.
    int? prompted;
    final InputTracker? tracker = _input;
    if (tracker != null && !post && !_unprompted.contains(type)) {
      prompted =
          tracker.linkAt(
            t,
            window: type == SnoEventType.searchQuery
                ? kInputLateLinkMs
                : kInputLinkMs,
          ) ??
          input;
    }
    // После остановки часы записи больше не сверяются: у таких событий
    // настенное время берётся прямо у устройства.
    final DateTime wall = clock == null || post ? _now() : clock.wallAt(t);
    String line(Map<String, Object?> payload) {
      return encodeEvent(
        seq: _seq + 1,
        t: t,
        wall: wall,
        type: type,
        context: context,
        data: payload,
        post: post,
        input: prompted,
      );
    }

    // Данные, которые не пишутся в JSON, не должны ни уронить экран,
    // ни оставить в журнале пропуск номера: событие пишется без них.
    String safe() {
      try {
        return line(data);
      } on Object {
        return line(const <String, Object?>{'unencodable': true});
      }
    }

    final String encoded = safe();
    _seq++;
    journal.add(encoded);
  }

  /// Вышло ли время записи.
  bool get _due {
    final SessionState? state = _state;
    if (state == null || _clock == null) {
      return false;
    }
    return _passedMs(state) >= _planned.inMilliseconds;
  }

  /// Секунда записи: сброс журнала на диск, сердцебиение, конец
  /// времени.
  ///
  /// Зовётся счётом записи раз в секунду; в тестах — руками.
  void tick() {
    if (!recording || _stopRun != null) {
      return;
    }
    if (_due) {
      unawaited(stop(StopReason.auto));
      return;
    }
    _beats++;
    if (_beats % kHeartbeatTicks == 0) {
      // SNO-F-REC-10: вне переднего плана сердцебиение называет
      // состояние — приложение жило, но участник на него не смотрел.
      // SNO-F-REC-13: заряд и свободное место — по последнему ответу
      // устройства; новый вопрос уходит сейчас, к следующему разу.
      _write(
        SnoEventType.heartbeat,
        data: <String, Object?>{
          if (_appState != _onScreen) 'state': _appState,
          ..._vitals(),
        },
      );
      unawaited(_readVitals());
    }
    unawaited(_journal?.flush());
    // SNO-F-REC-11: поток ввода ложится на диск той же секундой;
    // прокрутка, которая кончилась, и путь мыши уходят строками.
    _input?.poll(_tNow());
    unawaited(_inputJournal?.flush());
    ticks.value++;
  }

  static const String _onScreen = 'resumed';

  static const List<String> _depth = <String>['inactive', 'hidden', 'paused'];

  static String _deeper(String? known, String state) {
    if (known == null) {
      return state;
    }
    return _depth.indexOf(state) > _depth.indexOf(known) ? state : known;
  }

  /// Видно ли приложение в состоянии [state]: без фокуса оно на виду,
  /// свёрнутое и остановленное — нет.
  static bool _visible(String state) {
    return state == _onScreen || state == 'inactive';
  }

  /// Приложение ушло с переднего плана; [state] — куда: `inactive`,
  /// `hidden`, `paused`.
  void appLeft(String state) => appState(state);

  /// Приложение вернулось на передний план.
  void appReturned() => appState(_onScreen);

  /// Приложение сменило состояние на [to]: `resumed` — на экране и в
  /// фокусе, `inactive` — на виду, но без фокуса, `hidden` — его не
  /// видно, `paused` — остановлено системой (SNO-F-REC-10).
  ///
  /// Запись при этом не останавливается. Пишется **каждая** смена
  /// (`app.state`): миг, когда окно свернули, известен временем
  /// события, а не выводится по возвращении. Отлучка — от ухода с
  /// переднего плана до возвращения — по-прежнему обрамлена парой
  /// `app.background` / `app.foreground`; возвращение говорит, была ли
  /// она на виду (`unfocused`) или приложения не было видно (`hidden`)
  /// и сколько.
  ///
  /// При возвращении часы сверяются: монотонные могли стоять, пока
  /// устройство спало. И если сорок минут вышли, пока приложения не
  /// было на экране, запись останавливается сразу — временем их
  /// окончания.
  void appState(String to) {
    final String from = _appState;
    if (to == from) {
      return;
    }
    _appState = to;
    if (!_logging) {
      // Вне записи отлучки не считаются; состояние помнится — запись
      // может начаться в любом.
      _leftAt = null;
      _deepest = null;
      _hiddenAt = null;
      _hiddenMs = 0;
      _screenOff = false;
      _resyncSaid = false;
      return;
    }
    final bool returned = to == _onScreen;
    // Сверка — на каждом шаге к переднему плану и до его события:
    // монотонные часы стояли, пока устройство спало, и без сверки шаги
    // возвращения получили бы настенное время ухода.
    final ({int driftMs, bool applied})? check = _rank(to) < _rank(from)
        ? _clock?.resync()
        : null;
    final DateTime now = _now();
    final int t = _tNow();
    _write(
      SnoEventType.appState,
      at: t,
      data: <String, Object?>{'from': from, 'to': to},
    );
    final DateTime? hiddenAt = _hiddenAt;
    if (_visible(from) && !_visible(to)) {
      _hiddenAt = now;
      _hiddenT = t;
    } else if (!_visible(from) && _visible(to) && hiddenAt != null) {
      _hiddenMs += _span(hiddenAt, _hiddenT, now, t);
      _hiddenAt = null;
    }
    if (!returned) {
      if (_leftAt == null) {
        _openAbsence(to, now, t);
      } else {
        _deepest = _deeper(_deepest, to);
      }
      // Сверка, сдвинувшая часы, пишется сразу: устройство может уснуть
      // снова, не дойдя до переднего плана, и каждый сдвиг нужен
      // разбору отдельно.
      if (check != null && check.applied) {
        _sayResync(check);
        _resyncSaid = true;
      }
      unawaited(_readScreen(_leaveRun));
      unawaited(_journal?.flush());
      return;
    }
    // Сорок минут могли выйти, пока участника не было: тогда запись
    // кончилась во время отлучки, и в итог отлучка входит только до
    // конца записи.
    final SessionState? state = _state;
    final bool over = _due;
    final int late = state == null ? 0 : _lateMs(state);
    final DateTime? leftAt = _leftAt;
    if (leftAt != null) {
      final int away = _span(leftAt, _leftT, now, t);
      final String? deepest = _deepest;
      final bool unseen =
          _hiddenMs > 0 || (deepest != null && !_visible(deepest));
      _write(
        SnoEventType.appForeground,
        at: t,
        data: <String, Object?>{
          'away_ms': away,
          'deepest': deepest,
          'kind': unseen ? 'hidden' : 'unfocused',
          'hidden_ms': _hiddenMs,
          if (_screenOff) 'reason': 'screen_off',
        },
      );
      _away = _away.plus(awayMs: away - late, hiddenMs: _hiddenMs);
    }
    _leftAt = null;
    _deepest = null;
    _hiddenAt = null;
    _hiddenMs = 0;
    _screenOff = false;
    if (check != null && (check.applied || !_resyncSaid)) {
      _sayResync(check);
    }
    _resyncSaid = false;
    if (over) {
      unawaited(_stopOnce(StopReason.auto, endedAway: leftAt != null));
    } else {
      unawaited(_journal?.flush());
    }
  }

  void _sayResync(({int driftMs, bool applied}) check) {
    _write(
      SnoEventType.clockResync,
      data: <String, Object?>{
        'drift_ms': check.driftMs,
        'applied': check.applied,
      },
    );
  }

  /// Место состояния на пути от переднего плана: `resumed` — 0,
  /// `inactive` — 1, `hidden` — 2, `paused` — 3.
  static int _rank(String state) => _depth.indexOf(state) + 1;

  /// На сколько запись пережила положенное ей время; ноль — время не
  /// вышло.
  int _lateMs(SessionState state) {
    final int late = _passedMs(state) - _planned.inMilliseconds;
    return late < 0 ? 0 : late;
  }

  /// Начинает отлучку в состоянии [state] в миг [now] (`t` — [t]).
  void _openAbsence(String state, DateTime now, int t) {
    _leftAt = now;
    _leftT = t;
    _deepest = state;
    _leaveRun++;
    _screenOff = false;
    if (!_visible(state) && _hiddenAt == null) {
      _hiddenAt = now;
      _hiddenT = t;
    }
    _write(
      SnoEventType.appBackground,
      at: t,
      data: <String, Object?>{'state': state},
    );
  }

  /// Спрашивает устройство, горит ли экран, — в миг ухода
  /// (SNO-F-REC-10): экран, погашенный кнопкой, отличается от
  /// свёрнутого приложения только этим ответом.
  ///
  /// Ответ, пришедший после возвращения или к другой отлучке, не
  /// принимается.
  Future<void> _readScreen(int run) async {
    bool? lit;
    try {
      lit = await _status.screenOn();
    } on Object {
      lit = null;
    }
    if (lit == false && run == _leaveRun && _leftAt != null) {
      _screenOff = true;
    }
  }

  /// Останавливает запись (SNO-F-REC-01).
  ///
  /// Сессия при этом не завершена: полка остаётся под замком, пока
  /// экспериментатор не завершит сессию ([finish]).
  Future<void> stop(StopReason by) => _stopOnce(by);

  /// [endedAway] — время записи вышло, пока участника не было, а узнали
  /// об этом по его возвращении.
  Future<void> _stopOnce(StopReason by, {bool endedAway = false}) {
    final SessionState? state = _state;
    final Future<void>? running = _stopRun;
    if (running != null) {
      return running;
    }
    if (state == null || !recording) {
      return Future<void>.value();
    }
    final Future<void> run = _stop(state, by, endedAway: endedAway);
    _stopRun = run;
    return run.whenComplete(() => _stopRun = null);
  }

  Future<void> _stop(
    SessionState state,
    StopReason by, {
    required bool endedAway,
  }) async {
    _stopTicker?.call();
    _stopTicker = null;
    final RecordingClock? clock = _clock;
    final int limit = _planned.inMilliseconds;
    final int passed = _passedMs(state);
    // Запись, которая кончилась сама, длилась ровно сколько положено,
    // даже если приложение узнало об этом позже.
    final int duration = by == StopReason.auto || passed > limit
        ? limit
        : passed;
    final int t = _tNow();
    // SNO-F-REC-11: касание, которое ещё на экране, пишется сейчас —
    // с пометкой, что его оборвала остановка; дальше ввод не пишется.
    final InputTracker? tracker = _input;
    final EventJournal? inputJournal = _inputJournal;
    tracker?.finish(t);
    _input = null;
    _inputJournal = null;
    _readerInput = null;
    // Открытый блок закрывает остановка — тем же мигом (SNO-F-CFG-03).
    _closeBlock(by: 'stop', at: t);
    // SNO-F-REC-10: запись остановилась, пока участника не было —
    // отлучка входит в итог до этого мига, и об этом сказано.
    // Время после конца записи в отлучку не входит: запись, о конце
    // которой узнали позже, кончилась вовремя.
    final DateTime? leftAt = _leftAt;
    final bool inBackground = leftAt != null || endedAway;
    if (leftAt != null) {
      final DateTime now = _now();
      final int late = passed > limit ? passed - limit : 0;
      final DateTime? hiddenAt = _hiddenAt;
      final int hidden = hiddenAt == null
          ? _hiddenMs
          : _hiddenMs + _span(hiddenAt, _hiddenT, now, t);
      _away = _away.plus(
        awayMs: _span(leftAt, _leftT, now, t) - late,
        hiddenMs: hidden,
      );
    }
    _write(
      SnoEventType.recordingStop,
      at: t,
      data: <String, Object?>{
        'stopped_by': by.wire,
        'duration_ms': duration,
        if (passed > limit) 'late_ms': passed - limit,
        if (inBackground) 'in_background': true,
      },
    );
    final SessionState stopped = state.stopped(
      by: by,
      durationMs: duration,
      events: _seq,
      lastT: t,
      resyncs: clock?.resyncs ?? 0,
      away: _away,
      blocks: _blocks,
      inBackground: inBackground,
    );
    _state = stopped;
    _leftAt = null;
    _deepest = null;
    _hiddenAt = null;
    _hiddenMs = 0;
    _screenOff = false;
    _resyncSaid = false;
    _bookOpenedT = null;
    // Замок и точка записи меняются сразу; диск догоняет.
    _notify();
    // Файлы начала записи ещё могут писаться: остановка идёт после них.
    final Future<void>? starting = _startTail;
    if (starting != null) {
      await starting;
    }
    // Сначала журнал, потом отметка: приложение, умершее между ними,
    // найдёт в журнале остановку и закроет запись ею.
    await _journal?.flush();
    // SNO-F-REC-11: поток ввода дописан и закрыт — после остановки в
    // него не пишет никто.
    await inputJournal?.close();
    if (inputJournal?.failed ?? false) {
      _failed = true;
    }
    // Снимок конца — сразу за журналом, пока устройство не трогали
    // (SNO-ALG-REC-03); и до отметки: отказ диска на нём попадёт в неё.
    await _putEndSnapshot(state.folder, late: false);
    // SNO-F-REC-13: журнал перечитывается с диска и сверяется сам с
    // собой — все ли посчитанные события на месте, цел ли хвост.
    final JournalCheck? check = await _checkJournal(
      state.folder,
      expected: stopped.events,
    );
    // SNO-F-REC-11: и поток ввода — все ли посчитанные строки на месте.
    final JournalCheck? inputCheck = tracker == null
        ? null
        : await _checkJournal(
            state.folder,
            expected: tracker.count,
            name: kInputFile,
            key: 'n',
          );
    // Отказ диска — в отметку сессии: его помнят и после перезапуска.
    final SessionState marked = stopped
        .withFailure(writeFailed)
        .withCheck(check)
        .withInput(lines: tracker?.count, check: inputCheck);
    _state = marked;
    _setChecked(true);
    try {
      await _settings.write(SnoSettingsKeys.session, marked.encode());
    } on Object {
      // Отметка не записалась: после перезапуска запись закроется по
      // строке остановки из журнала.
    }
    await _putInfo(marked, finished: false);
    _keepScreen(false);
    _releaseGuard();
    if (writeFailed) {
      // Экран завершения открыт сразу после остановки, раньше диска:
      // о том, что журнал не лёг, он узнаёт отсюда.
      _notify();
    }
  }

  /// Завершает сессию: замок снят, код участника забыт (SNO-F-CFG-05).
  ///
  /// Папка записи переезжает к завершённым; в архив её упаковывает
  /// тот, кто завершал, — `DeviceRecords.pack` (SNO-F-REC-05).
  Future<void> finish() {
    final Future<void>? running = _finishRun;
    if (running != null) {
      return running;
    }
    final Future<void> run = _finish();
    _finishRun = run;
    return run.whenComplete(() => _finishRun = null);
  }

  Future<void> _finish() async {
    // Остановка ещё дописывает своё: завершение идёт после неё.
    final Future<void>? stopping = _stopRun;
    if (stopping != null) {
      await stopping;
    }
    final SessionState? state = _state;
    if (state == null || state.phase != RecordingPhase.stopped) {
      return;
    }
    if (_journal == null) {
      // Сессию подняли после перезапуска: журнал открывается заново.
      try {
        _journal = EventJournal(await _store.openJournal(state.folder));
      } on Object {
        _journal = null;
      }
    }
    _write(SnoEventType.sessionFinish, post: true);
    final SessionState done = state.stopped(
      by: state.stoppedBy ?? StopReason.crash,
      durationMs: state.durationMs ?? 0,
      events: _seq,
      lastT: state.lastT,
      resyncs: state.resyncs,
    );
    final EventJournal? journal = _journal;
    // Закрытый журнал больше не держится: повторное завершение
    // откроет его заново, а не напишет в никуда.
    _journal = null;
    await journal?.close();
    if (journal?.failed ?? false) {
      _failed = true;
    }
    await _putInfo(done, finished: true);
    try {
      await _store.finish(state.folder);
    } on Object {
      // Папка осталась среди незавершённых: её подберёт упаковка.
    }
    try {
      await _settings.remove(SnoSettingsKeys.session);
    } on Object {
      // Отметка осталась: после перезапуска сессию завершат ещё раз.
      // Замок при этом снимается сейчас — участник уже ушёл.
    }
    _clock = null;
    _state = null;
    _seq = 0;
    _failed = false;
    _setChecked(false);
    _notify();
  }

  /// Ждёт, пока остановка и завершение допишут своё на диск.
  ///
  /// Замок и точка записи меняются раньше диска: приложение, закрытое
  /// в этот миг, оставило бы запись без строки остановки — и следующий
  /// запуск принял бы её за оборванную.
  Future<void> settled() async {
    try {
      final Future<void>? stopping = _stopRun;
      if (stopping != null) {
        await stopping;
      }
      final Future<void>? finishing = _finishRun;
      if (finishing != null) {
        await finishing;
      }
    } on Object {
      // Не дописалось — ждать больше нечего.
    }
  }

  /// Отмечает, открыт ли экран завершения сессии.
  ///
  /// Экран может закрыться и после того, как сессию сняли: тогда
  /// отмечать уже нечего.
  void setFinishOpen(bool open) {
    if (!_disposed) {
      finishOpen.value = open;
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Отмечает, перечитан ли журнал; сессию могли снять, пока остановка
  /// дописывала своё, — тогда отмечать уже некому.
  void _setChecked(bool value) {
    if (!_disposed) {
      checked.value = value;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker?.call();
    _stopTicker = null;
    ticks.dispose();
    finishOpen.dispose();
    checked.dispose();
    super.dispose();
  }
}
