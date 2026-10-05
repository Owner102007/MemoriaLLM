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
import 'clock.dart';
import 'device_status.dart';
import 'event.dart';
import 'journal.dart';
import 'store.dart';

/// Сколько длится запись.
const Duration kRecordingLength = Duration(minutes: 40);

/// Как часто пишется сердцебиение, в тиках записи (тик — секунда).
const int kHeartbeatTicks = 10;

/// Ниже какого заряда перед стартом звучит предупреждение, в процентах.
const int kLowBatteryPercent = 30;

/// Меньше какого свободного места перед стартом звучит предупреждение.
const int kLowSpaceBytes = 200 * 1024 * 1024;

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

/// Готово ли устройство к записи: заряд и свободное место.
class Readiness {
  /// Создаёт ответ.
  const Readiness({this.batteryPercent, this.freeBytes});

  /// Заряд в процентах; `null` — батареи нет или устройство не ответило.
  final int? batteryPercent;

  /// Свободное место там, где лежат записи; `null` — не узнать.
  final int? freeBytes;

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

  /// То же состояние после остановки.
  SessionState stopped({
    required StopReason by,
    required int durationMs,
    required int events,
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
class RecordingSession extends ChangeNotifier {
  /// Создаёт сессию.
  ///
  /// [branch], [device] и [build] попадают в сведения записи: ветвь,
  /// первые шесть знаков идентификатора устройства, версия и коммит
  /// сборки. [now], [monotonic], [ticker] и [random] подменяются в
  /// тестах.
  RecordingSession({
    required AppSettingsRepository settings,
    required RecordingStore store,
    required String nodeId,
    required SnapshotSource snapshot,
    this.branch = '',
    this.device = '',
    this.build = const <String, Object?>{},
    DeviceStatus status = const NoDeviceStatus(),
    Duration planned = kRecordingLength,
    DateTime Function()? now,
    MonotonicSource? monotonic,
    SessionTicker? ticker,
    Random? random,
  }) : _settings = settings,
       _store = store,
       _nodeId = nodeId,
       _snapshot = snapshot,
       _status = status,
       _planned = planned,
       _now = now ?? DateTime.now,
       _monotonic = monotonic ?? _stopwatchSource,
       _ticker = ticker ?? _timerTicker,
       _random = random ?? Random.secure();

  final AppSettingsRepository _settings;
  final RecordingStore _store;
  final String _nodeId;
  final SnapshotSource _snapshot;
  final DeviceStatus _status;
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

  SessionState? _state;
  RecordingClock? _clock;
  EventJournal? _journal;
  void Function()? _stopTicker;
  int _seq = 0;
  int _beats = 0;
  bool _starting = false;
  Future<void>? _stopRun;
  bool _finishing = false;
  DateTime? _leftAt;
  String? _deepest;
  bool _disposed = false;

  /// Состояние незавершённой сессии; `null` — сессии нет.
  SessionState? get state => _state;

  /// Что происходит с записью.
  RecordingPhase get phase => _state?.phase ?? RecordingPhase.idle;

  /// Идёт ли запись.
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

  /// Не удалось ли записать что-то на диск.
  bool get writeFailed => _journal?.failed ?? false;

  /// Сколько запись идёт или шла, в миллисекундах, по настенным часам.
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
    final int passed = _wallElapsedMs(state);
    return passed < 0 ? 0 : (passed > limit ? limit : passed);
  }

  /// Сколько записи осталось, в миллисекундах.
  int get remainingMs => _planned.inMilliseconds - elapsedMs;

  int _wallElapsedMs(SessionState state) {
    return _now().difference(state.startedAt).inMilliseconds;
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
      return;
    }
    if (state.phase == RecordingPhase.stopped) {
      _state = state;
      _seq = state.events;
      _notify();
      return;
    }
    _state = await _stoppedByCrash(state);
    _notify();
  }

  /// Закрывает запись, оборванную перезапуском приложения.
  Future<SessionState> _stoppedByCrash(SessionState state) async {
    int seq = 0;
    int t = 0;
    try {
      final String? last = await _store.lastLine(state.folder);
      final ({int seq, int t})? marks = last == null ? null : eventMarks(last);
      if (marks != null) {
        seq = marks.seq;
        t = marks.t;
      }
    } on Object {
      // Журнал не прочитался: длительность неизвестна, запись всё равно
      // закрывается — замок на полке обязан сниматься.
    }
    final int limit = state.plannedSeconds * 1000;
    final int duration = t > limit ? limit : t;
    final DateTime moment = _now();
    _seq = seq;
    try {
      final JournalFile file = await _store.openJournal(state.folder);
      final EventJournal journal = EventJournal(file);
      _seq++;
      journal.add(
        encodeEvent(
          seq: _seq,
          t: t,
          wall: moment,
          type: SnoEventType.recordingStop,
          context: context,
          data: <String, Object?>{
            'stopped_by': StopReason.crash.wire,
            'duration_ms': duration,
            'late': true,
          },
        ),
      );
      await journal.close();
    } on Object {
      _seq = seq;
    }
    final SessionState stopped = state.stopped(
      by: StopReason.crash,
      durationMs: duration,
      events: _seq,
    );
    await _settings.write(SnoSettingsKeys.session, stopped.encode());
    await _putInfo(stopped, finished: false);
    return stopped;
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
      journal = EventJournal(await _store.openJournal(folder));
    } on Object {
      // Папку записи завести не удалось: записи нет, сессии тоже.
      return false;
    }

    final int Function() elapsed = _monotonic();
    final RecordingClock clock = RecordingClock(now: _now, elapsedMs: elapsed);
    final SessionState state = SessionState(
      id: newRecordingId(clock.anchor, _random),
      folder: folder,
      participant: participant,
      startedAt: clock.anchor,
      plannedSeconds: _planned.inSeconds,
      phase: RecordingPhase.recording,
    );
    try {
      // Сначала отметка о сессии, потом запись: приложение, упавшее
      // между ними, найдёт сессию и закроет её.
      await _settings.write(SnoSettingsKeys.session, state.encode());
      final Set<String> known = await _knownCodes();
      if (known.add(participant.base)) {
        await _settings.write(
          SnoSettingsKeys.knownCodes,
          encodeKnownCodes(known),
        );
      }
    } on Object {
      await journal.close();
      return false;
    }
    if (_disposed) {
      await journal.close();
      return false;
    }
    _clock = clock;
    _journal = journal;
    _seq = 0;
    _beats = 0;
    _leftAt = null;
    _deepest = null;
    _state = state;

    final Object? reference = snapshot['reference'];
    _write(
      SnoEventType.recordingStart,
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
      _write(SnoEventType.stateReset, data: <String, Object?>{'at': lastReset});
    }
    _stopTicker = _ticker(tick);
    // Замок и точка записи появляются сразу; диск догоняет.
    _notify();

    try {
      await _store.put(folder, kSnapshotStartFile, _pretty(snapshot));
    } on Object {
      journal.failed = true;
    }
    await _putInfo(state, finished: false);
    await journal.flush();
    try {
      await _status.keepScreenOn(true);
    } on Object {
      // Экран может погаснуть — запись от этого не пропадает.
    }
    return true;
  }

  /// Снимок состояния; не удался — так в нём и сказано.
  Future<Map<String, Object?>> _takeSnapshot() async {
    try {
      return await _snapshot();
    } on Object {
      return <String, Object?>{'failed': true};
    }
  }

  String _pretty(Map<String, Object?> json) {
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Пишет сведения о записи — участник, устройство, сборка, часы,
  /// остановка. Из них соберётся манифест архива (SNO-F-REC-05).
  Future<void> _putInfo(SessionState state, {required bool finished}) async {
    final int? duration = state.durationMs;
    final Map<String, Object?> info = <String, Object?>{
      'schema': kRecordingSchema,
      'branch': branch,
      'app': build,
      'device': <String, Object?>{'node_id': _nodeId, 'code': device},
      'participant': state.participant.toJson(),
      'recording': <String, Object?>{
        'id': state.id,
        'clock_anchor': isoWithOffset(state.startedAt),
        'planned_s': state.plannedSeconds,
        'duration_s': duration == null ? null : duration ~/ 1000,
        'duration_ms': duration,
        'stopped_by': state.stoppedBy?.wire,
        'resyncs': _clock?.resyncs ?? 0,
        'events': state.phase == RecordingPhase.recording ? null : state.events,
        'finished': finished,
      },
    };
    try {
      await _store.put(state.folder, kRecordingFile, _pretty(info));
    } on Object {
      _journal?.failed = true;
    }
  }

  int _tNow() {
    final RecordingClock? clock = _clock;
    if (clock != null) {
      return clock.t;
    }
    final SessionState? state = _state;
    return state == null ? 0 : _wallElapsedMs(state);
  }

  /// Пишет событие в журнал записи (SNO-F-REC-02).
  ///
  /// Вне записи не делает ничего: пока запись не идёт, ни одна строка
  /// не пишется никуда. Места вызова стоят рядом с действиями
  /// участника и помечены `// SNO-F-REC-02`.
  void log(
    SnoEventType type, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!recording || _stopRun != null) {
      return;
    }
    _write(type, data: data);
  }

  /// Строка журнала с номером и временем; без открытого журнала не
  /// делает ничего.
  void _write(
    SnoEventType type, {
    Map<String, Object?> data = const <String, Object?>{},
    bool post = false,
  }) {
    final EventJournal? journal = _journal;
    if (journal == null) {
      return;
    }
    final RecordingClock? clock = _clock;
    final int t = _tNow();
    _seq++;
    journal.add(
      encodeEvent(
        seq: _seq,
        t: t,
        wall: clock == null ? _now() : clock.wallAt(t),
        type: type,
        context: context,
        data: data,
        post: post,
      ),
    );
  }

  /// Вышло ли время записи.
  ///
  /// Сорок минут считаются по настенным часам: монотонные во сне
  /// устройства стоят. Монотонные учитываются тоже — на случай, если
  /// настенные перевели назад: запись не должна от этого растянуться.
  bool get _due {
    final RecordingClock? clock = _clock;
    if (clock == null) {
      return false;
    }
    final int limit = _planned.inMilliseconds;
    return clock.wallElapsedMs >= limit || clock.t >= limit;
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
      _write(SnoEventType.heartbeat);
    }
    unawaited(_journal?.flush());
    ticks.value++;
  }

  /// Приложение ушло с переднего плана; [state] — куда: `inactive`,
  /// `hidden`, `paused`.
  ///
  /// Запись при этом не останавливается. Событие пишется одно на
  /// отлучку — в миг ухода; насколько глубоко приложение ушло, скажет
  /// событие возвращения.
  void appLeft(String state) {
    if (!recording || _stopRun != null) {
      return;
    }
    if (_leftAt == null) {
      _leftAt = _now();
      _write(
        SnoEventType.appBackground,
        data: <String, Object?>{'state': state},
      );
      unawaited(_journal?.flush());
    }
    _deepest = _deeper(_deepest, state);
  }

  static const List<String> _depth = <String>['inactive', 'hidden', 'paused'];

  static String _deeper(String? known, String state) {
    if (known == null) {
      return state;
    }
    return _depth.indexOf(state) > _depth.indexOf(known) ? state : known;
  }

  /// Приложение вернулось на передний план.
  ///
  /// Часы сверяются: монотонные могли стоять, пока устройство спало. И
  /// если сорок минут вышли, пока приложения не было на экране, запись
  /// останавливается сразу — временем их окончания.
  void appReturned() {
    final DateTime? leftAt = _leftAt;
    _leftAt = null;
    final String? deepest = _deepest;
    _deepest = null;
    if (!recording || _stopRun != null || leftAt == null) {
      return;
    }
    _write(
      SnoEventType.appForeground,
      data: <String, Object?>{
        'away_ms': _now().difference(leftAt).inMilliseconds,
        'deepest': deepest,
      },
    );
    final RecordingClock? clock = _clock;
    if (clock != null) {
      final ({int driftMs, bool applied}) check = clock.resync();
      _write(
        SnoEventType.clockResync,
        data: <String, Object?>{
          'drift_ms': check.driftMs,
          'applied': check.applied,
        },
      );
    }
    if (_due) {
      unawaited(stop(StopReason.auto));
    } else {
      unawaited(_journal?.flush());
    }
  }

  /// Останавливает запись (SNO-F-REC-01).
  ///
  /// Сессия при этом не завершена: полка остаётся под замком, пока
  /// экспериментатор не завершит сессию ([finish]).
  Future<void> stop(StopReason by) {
    final SessionState? state = _state;
    final Future<void>? running = _stopRun;
    if (running != null) {
      return running;
    }
    if (state == null || !recording) {
      return Future<void>.value();
    }
    final Future<void> run = _stop(state, by);
    _stopRun = run;
    return run.whenComplete(() => _stopRun = null);
  }

  Future<void> _stop(SessionState state, StopReason by) async {
    _stopTicker?.call();
    _stopTicker = null;
    final RecordingClock? clock = _clock;
    final int limit = _planned.inMilliseconds;
    final int passed = clock?.wallElapsedMs ?? _wallElapsedMs(state);
    // Запись, которая кончилась сама, длилась ровно сколько положено,
    // даже если приложение узнало об этом позже.
    final int duration = by == StopReason.auto || passed > limit
        ? limit
        : (passed < 0 ? 0 : passed);
    _write(
      SnoEventType.recordingStop,
      data: <String, Object?>{
        'stopped_by': by.wire,
        'duration_ms': duration,
        if (passed > limit) 'late_ms': passed - limit,
      },
    );
    final SessionState stopped = state.stopped(
      by: by,
      durationMs: duration,
      events: _seq,
    );
    _state = stopped;
    _leftAt = null;
    _deepest = null;
    // Замок и точка записи меняются сразу; диск догоняет.
    _notify();
    try {
      await _settings.write(SnoSettingsKeys.session, stopped.encode());
    } on Object {
      // Отметка не записалась: после перезапуска запись закроется как
      // оборванная — журнал при этом цел.
    }
    await _journal?.flush();
    await _putInfo(stopped, finished: false);
    try {
      await _status.keepScreenOn(false);
    } on Object {
      // Экран останется включённым до закрытия приложения.
    }
  }

  /// Завершает сессию: замок снят, код участника забыт (SNO-F-CFG-05).
  ///
  /// Папка записи переезжает к завершённым и ждёт упаковки в архив.
  Future<void> finish() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    try {
      // Остановка ещё дописывает своё: завершение идёт после неё.
      final Future<void>? stopping = _stopRun;
      if (stopping != null) {
        await stopping;
      }
      final SessionState? state = _state;
      if (state == null || state.phase != RecordingPhase.stopped) {
        return;
      }
      EventJournal? journal = _journal;
      if (journal == null) {
        // Сессию подняли после перезапуска: журнал открывается заново.
        try {
          journal = EventJournal(await _store.openJournal(state.folder));
          _journal = journal;
        } on Object {
          journal = null;
        }
      }
      _write(SnoEventType.sessionFinish, post: true);
      final SessionState done = state.stopped(
        by: state.stoppedBy ?? StopReason.crash,
        durationMs: state.durationMs ?? 0,
        events: _seq,
      );
      await journal?.close();
      await _putInfo(done, finished: true);
      try {
        await _store.finish(state.folder);
      } on Object {
        // Папка осталась среди незавершённых: её подберёт упаковка.
      }
      await _settings.remove(SnoSettingsKeys.session);
      _journal = null;
      _clock = null;
      _state = null;
      _seq = 0;
      _notify();
    } finally {
      _finishing = false;
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

  @override
  void dispose() {
    _disposed = true;
    _stopTicker?.call();
    _stopTicker = null;
    ticks.dispose();
    finishOpen.dispose();
    super.dispose();
  }
}
