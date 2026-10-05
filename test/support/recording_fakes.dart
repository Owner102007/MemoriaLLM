import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/recording/action_log.dart';
import 'package:memoria/sno/recording/device_status.dart';
import 'package:memoria/sno/recording/event.dart';
import 'package:memoria/sno/recording/records.dart';
import 'package:memoria/sno/recording/session.dart';
import 'package:memoria/sno/recording/store.dart';

/// Настройки в памяти: сессии записи база не нужна.
class MemorySettings implements AppSettingsRepository {
  /// Что записано.
  final Map<String, String> values = <String, String>{};

  /// Отказывать ли в записи: «база не ответила».
  bool failWrites = false;

  /// Ключи, запись которых не удаётся.
  final Set<String> failKeys = <String>{};

  /// Отказывать ли в удалении.
  bool failRemoves = false;

  /// Отказывать ли в чтении: «база не ответила».
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) {
      throw StateError('настройки не читаются');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites || failKeys.contains(key)) {
      throw StateError('настройки не пишутся');
    }
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failRemoves) {
      throw StateError('настройки не удаляются');
    }
    values.remove(key);
  }

  @override
  Stream<String?> watch(String key) => Stream<String?>.value(values[key]);
}

/// Записи в памяти: ни диска, ни ожидания.
///
/// Помнит, что лежит среди незавершённых и что уже завершено, — как
/// папки `Записи/.current/` и `Записи/` у настоящего хранилища.
class MemoryRecordingStore implements RecordingStore {
  /// Тексты журналов по папкам.
  final Map<String, StringBuffer> journals = <String, StringBuffer>{};

  /// Файлы папок: имя → содержимое.
  final Map<String, Map<String, String>> files =
      <String, Map<String, String>>{};

  /// Папки незавершённых записей.
  final Set<String> current = <String>{};

  /// Папки завершённых записей.
  final Set<String> finished = <String>{};

  /// Отказывать ли в заведении папки: «места нет».
  bool failCreate = false;

  /// Отказывать ли журналу в записи: «диск отказал».
  bool failAppend = false;

  /// Отказывать ли в чтении хвоста журнала: «диск не ответил».
  bool failTail = false;

  /// Сколько журналов открыто и ещё не закрыто.
  int open = 0;

  @override
  Future<String> location() async => '/records';

  @override
  Future<String> create(String wanted) async {
    if (failCreate) {
      throw StateError('папка не заводится');
    }
    String name = wanted;
    int number = 1;
    while (current.contains(name) || finished.contains(name)) {
      number++;
      name = '$wanted-$number';
    }
    current.add(name);
    files[name] = <String, String>{};
    return name;
  }

  @override
  Future<JournalFile> openJournal(String folder) async {
    open++;
    return _MemoryJournal(
      journals.putIfAbsent(folder, StringBuffer.new),
      () => open--,
      () => failAppend,
    );
  }

  @override
  Future<void> put(String folder, String name, String content) async {
    files.putIfAbsent(folder, () => <String, String>{})[name] = content;
  }

  @override
  Future<bool> has(String folder, String name) async {
    return files[folder]?.containsKey(name) ?? false;
  }

  @override
  Future<List<String>> lastLines(
    String folder, {
    int count = kTailLines,
  }) async {
    if (failTail) {
      throw StateError('журнал не читается');
    }
    final StringBuffer? journal = journals[folder];
    if (journal == null) {
      return const <String>[];
    }
    final String text = journal.toString();
    final int end = text.lastIndexOf('\n');
    if (end < 0) {
      journal.clear();
      return const <String>[];
    }
    if (end != text.length - 1) {
      // Оборванный хвост отрезается, как у настоящего хранилища.
      journal
        ..clear()
        ..write(text.substring(0, end + 1));
    }
    final List<String> lines = <String>[
      for (final String line in const LineSplitter().convert(
        text.substring(0, end),
      ))
        if (line.isNotEmpty) line,
    ];
    return lines.length > count ? lines.sublist(lines.length - count) : lines;
  }

  @override
  Future<void> discard(String folder) async {
    current.remove(folder);
    files.remove(folder);
    journals.remove(folder);
  }

  /// Придерживает перенос завершённой записи, пока тест не отпустит:
  /// по нему видно, что бывает, пока сессия завершается.
  Completer<void>? finishGate;

  @override
  Future<void> finish(String folder) async {
    await finishGate?.future;
    if (current.remove(folder)) {
      finished.add(folder);
    }
  }

  /// Строки журнала папки [folder], как они лежат «на диске».
  List<String> lines(String folder) {
    return <String>[
      for (final String line in const LineSplitter().convert(
        journals[folder]?.toString() ?? '',
      ))
        if (line.isNotEmpty) line,
    ];
  }

  /// Строки журнала папки [folder], разобранные из JSON.
  List<Map<String, Object?>> events(String folder) {
    return <Map<String, Object?>>[
      for (final String line in lines(folder))
        jsonDecode(line) as Map<String, Object?>,
    ];
  }

  /// Виды событий журнала папки [folder], по порядку.
  List<String> types(String folder) {
    return <String>[
      for (final Map<String, Object?> event in events(folder))
        event['type']! as String,
    ];
  }

  /// Файл [name] папки [folder], разобранный из JSON.
  Map<String, Object?> json(String folder, String name) {
    return jsonDecode(files[folder]![name]!) as Map<String, Object?>;
  }
}

class _MemoryJournal implements JournalFile {
  _MemoryJournal(this._text, this._closed, this._failing);

  final StringBuffer _text;
  final void Function() _closed;
  final bool Function() _failing;

  @override
  Future<void> append(String text) async {
    if (_failing()) {
      throw StateError('журнал не пишется');
    }
    _text.write(text);
  }

  @override
  Future<void> close() async => _closed();
}

/// Устройство, которым распоряжается тест.
class FakeDeviceStatus implements DeviceStatus {
  /// Создаёт заглушку.
  FakeDeviceStatus({this.battery, this.free});

  /// Заряд в процентах; `null` — устройство не знает.
  int? battery;

  /// Свободное место в байтах; `null` — устройство не знает.
  int? free;

  /// О чём запись просила экран, по порядку.
  final List<bool> screen = <bool>[];

  /// По какому пути спрашивали свободное место.
  String? asked;

  @override
  Future<int?> batteryPercent() async => battery;

  @override
  Future<int?> freeBytes(String path) async {
    asked = path;
    return free;
  }

  @override
  Future<void> keepScreenOn(bool on) async => screen.add(on);

  /// Горит ли экран; `null` — устройство не знает.
  bool? lit;

  /// Придерживать ли ответы об экране: тогда каждый вопрос ждёт в
  /// [screenAsks], пока тест не ответит сам.
  bool holdScreen = false;

  /// Вопросы об экране, на которые ещё не ответили, по порядку.
  final List<Completer<bool?>> screenAsks = <Completer<bool?>>[];

  @override
  Future<bool?> screenOn() {
    if (!holdScreen) {
      return Future<bool?>.value(lit);
    }
    final Completer<bool?> ask = Completer<bool?>();
    screenAsks.add(ask);
    return ask.future;
  }
}

/// Двое часов записи в руках теста: настенные и монотонные.
class FakeTime {
  /// Заводит часы на миг [wall].
  FakeTime(this.wall);

  /// Настенное время.
  DateTime wall;

  /// Монотонный счёт, в миллисекундах. Начинается не с нуля: настоящий
  /// счёт тоже начинается не со старта записи.
  int monotonic = 5000;

  /// Настенное время сейчас.
  DateTime now() => wall;

  /// Время идёт: обои часов вперёд на [by].
  void pass(Duration by) {
    wall = wall.add(by);
    monotonic += by.inMilliseconds;
  }

  /// Устройство спало: настенные часы ушли вперёд, монотонные стояли.
  void sleep(Duration by) {
    wall = wall.add(by);
  }
}

/// Узел, для которого код участника известен заранее (SNO-ALG-CFG-03).
const String kTestNode = 'a91f3c0b';

/// Время в миллисекундах, для которого код известен заранее.
const int kTestMoment = 1793612000111;

/// Код, который выходит для [kTestNode] в миг [kTestMoment].
const String kTestCode = '67954332';

/// Сессия записи для тестов и всё, чем она пользуется.
class SessionKit {
  /// Собирает сессию на памяти и подменённом времени.
  ///
  /// [settings] и [store] передаются, когда «приложение перезапущено»:
  /// новая сессия поднимается на том, что оставила прежняя.
  SessionKit({
    MemorySettings? settings,
    MemoryRecordingStore? store,
    FakeTime? time,
    FakeDeviceStatus? status,
    Map<String, Object?>? snapshot,
    Duration planned = kRecordingLength,
  }) : settings = settings ?? MemorySettings(),
       store = store ?? MemoryRecordingStore(),
       time =
           time ?? FakeTime(DateTime.fromMillisecondsSinceEpoch(kTestMoment)),
       status = status ?? FakeDeviceStatus(),
       snapshot =
           snapshot ??
           <String, Object?>{
             'schema': 'sno2026-snapshot/1',
             'reference': <String, Object?>{'matches': true},
           } {
    session = RecordingSession(
      settings: this.settings,
      store: this.store,
      nodeId: kTestNode,
      snapshot: () async => this.snapshot,
      branch: 'I',
      device: 'a91f3c',
      build: const <String, Object?>{'version': 'test'},
      status: this.status,
      planned: planned,
      now: this.time.now,
      monotonic: () =>
          () => this.time.monotonic,
      ticker: (void Function() onTick) {
        ticking = true;
        return () => ticking = false;
      },
      random: Random(7),
    );
  }

  /// Настройки.
  final MemorySettings settings;

  /// Хранилище записей.
  final MemoryRecordingStore store;

  /// Часы.
  final FakeTime time;

  /// Устройство.
  final FakeDeviceStatus status;

  /// Снимок состояния, который получит запись.
  final Map<String, Object?> snapshot;

  /// Сессия.
  late final RecordingSession session;

  /// Заведён ли счёт секунд записи.
  bool ticking = false;

  /// Папка идущей или остановленной записи.
  String get folder => session.state!.folder;

  /// Проходит [seconds] секунд записи: часы идут, счёт тикает.
  void run(int seconds) {
    for (int i = 0; i < seconds; i++) {
      time.pass(const Duration(seconds: 1));
      session.tick();
    }
  }

  /// Даёт диску догнать запись.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Журнал действий, который просто копит записанное (SNO-F-REC-02).
///
/// Для проверок проводов: что экран или действие записали, каким видом
/// и с какими данными, — без сессии, часов и хранилища.
class ListActionLog implements ActionLog {
  /// Создаёт журнал; [recording] — идёт ли запись.
  ListActionLog({this.recording = true});

  @override
  bool recording;

  /// Записанные события по порядку.
  final List<({SnoEventType type, Map<String, Object?> data})> events =
      <({SnoEventType type, Map<String, Object?> data})>[];

  /// Сколько раз журнал просили что-то записать — и тогда, когда
  /// запись не идёт: по нему видно, что вне записи событие даже не
  /// собирают.
  int asked = 0;

  /// Где участник: экран, книга, страница, полоса, режим.
  final RecordingContext context = RecordingContext();

  /// Виды записанных событий по порядку.
  List<String> get types {
    return <String>[
      for (final ({SnoEventType type, Map<String, Object?> data}) event
          in events)
        event.type.wire,
    ];
  }

  /// Данные событий вида [type] по порядку.
  List<Map<String, Object?>> dataOf(SnoEventType type) {
    return <Map<String, Object?>>[
      for (final ({SnoEventType type, Map<String, Object?> data}) event
          in events)
        if (event.type == type) event.data,
    ];
  }

  @override
  void log(
    SnoEventType type, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    asked++;
    if (recording) {
      events.add((type: type, data: data));
    }
  }

  @override
  void screen(String name) {
    final String from = context.screen;
    if (from == name) {
      return;
    }
    context.screen = name;
    log(
      SnoEventType.navScreen,
      data: <String, Object?>{'from': from, 'to': name},
    );
  }

  @override
  void bookOpened(
    String book, {
    required String via,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    context.book = book;
    log(
      SnoEventType.bookOpen,
      data: <String, Object?>{'via': via, 'book': book, ...data},
    );
  }

  @override
  void bookClosed() {
    if (context.book == null) {
      return;
    }
    log(SnoEventType.bookClose);
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
}

/// Записи на устройстве в памяти (SNO-F-REC-07): ни диска, ни
/// системных окон.
///
/// Экраны проверяются на них: что показано, что отдано окну
/// «Поделиться», что помечено и что удалено. Настоящие записи на диске
/// проверяются в `device_records_test.dart`.
class MemoryDeviceRecords extends ChangeNotifier implements DeviceRecords {
  /// Создаёт записи: телефон — [shares], ПК — [saves].
  MemoryDeviceRecords({
    this.shares = false,
    this.saves = false,
    List<DeviceRecord> entries = const <DeviceRecord>[],
    DateTime? now,
  }) : _entries = List<DeviceRecord>.of(entries),
       now = now ?? DateTime(2026, 11, 3, 14, 50);

  @override
  bool shares;

  @override
  bool saves;

  @override
  bool loaded = false;

  /// Время отметок «отправлена» и «копия есть».
  DateTime now;

  final List<DeviceRecord> _entries;

  @override
  List<DeviceRecord> get entries => orderRecords(_entries);

  /// Сколько раз список перечитывали.
  int refreshed = 0;

  /// Папки, которые просили упаковать, по порядку.
  final List<String> packed = <String>[];

  /// Что вернёт упаковка папки; не задано — архив этой записи на
  /// двадцать минут и полторы тысячи событий.
  DeviceRecord? Function(String folder)? onPack;

  /// Придерживает упаковку, пока тест не отпустит: по нему видно, что
  /// стоит на экране, пока архив собирается.
  Completer<void>? packGate;

  /// Открывается ли окно «Поделиться».
  bool shareOpens = true;

  /// Что отдавали окну «Поделиться», по вызовам: имена записей.
  final List<List<String>> shared = <List<String>>[];

  /// Чем кончится «Сохранить архив как…».
  CopyOutcome copyOutcome = CopyOutcome.done;

  /// Записи, копию которых просили сохранить.
  final List<String> saved = <String>[];

  /// Открывается ли папка.
  bool revealOpens = true;

  /// Что открывали: имя записи или `null` — саму папку.
  final List<String?> revealed = <String?>[];

  /// Удаляются ли записи.
  bool deleteWorks = true;

  /// Удалённые записи, по порядку.
  final List<String> deleted = <String>[];

  /// Сколько раз подбирали папки без сессии.
  int adopted = 0;

  /// Сколько раз упаковывали оставшееся папками.
  int pending = 0;

  /// Кладёт запись в список — как архив, положенный в папку руками.
  void put(DeviceRecord record) {
    _entries
      ..removeWhere((DeviceRecord known) => known.name == record.name)
      ..add(record);
    notifyListeners();
  }

  DeviceRecord _with(
    DeviceRecord record, {
    DateTime? sharedAt,
    DateTime? copiedAt,
  }) {
    return DeviceRecord(
      name: record.name,
      bytes: record.bytes,
      packed: record.packed,
      damaged: record.damaged,
      branch: record.branch,
      participant: record.participant,
      startedAt: record.startedAt,
      durationMs: record.durationMs,
      events: record.events,
      stoppedBy: record.stoppedBy,
      sharedAt: sharedAt ?? record.sharedAt,
      copiedAt: copiedAt ?? record.copiedAt,
    );
  }

  void _replace(DeviceRecord record) {
    final int at = _entries.indexWhere(
      (DeviceRecord known) => known.name == record.name,
    );
    if (at >= 0) {
      _entries[at] = record;
    }
  }

  @override
  Future<void> refresh() async {
    refreshed++;
    // Как у настоящих записей: список перечитывается не в том же
    // такте, и слушатели узнают об этом позже вызова.
    await null;
    loaded = true;
    notifyListeners();
  }

  @override
  Future<void> adoptOrphans() async {
    adopted++;
  }

  @override
  Future<void> packPending() async {
    pending++;
  }

  @override
  Future<DeviceRecord?> pack(String folder) async {
    packed.add(folder);
    await packGate?.future;
    final DeviceRecord? Function(String folder)? answer = onPack;
    final DeviceRecord? record = answer != null
        ? answer(folder)
        : DeviceRecord(
            name: folder,
            bytes: 412 * 1024,
            branch: 'I',
            participant: kTestCode,
            startedAt: DateTime.fromMillisecondsSinceEpoch(kTestMoment),
            durationMs: 20 * 60 * 1000,
            events: 1482,
            stoppedBy: StopReason.experimenter.wire,
          );
    if (record != null) {
      _entries
        ..removeWhere((DeviceRecord known) => known.name == record.name)
        ..add(record);
    }
    loaded = true;
    notifyListeners();
    return record;
  }

  @override
  Future<int> share(List<DeviceRecord> records) async {
    shared.add(<String>[
      for (final DeviceRecord record in records) record.name,
    ]);
    if (!shareOpens) {
      return 0;
    }
    for (final DeviceRecord record in records) {
      _replace(_with(record, sharedAt: now));
    }
    notifyListeners();
    return records.length;
  }

  @override
  Future<CopyOutcome> saveCopy(DeviceRecord record) async {
    saved.add(record.name);
    if (copyOutcome == CopyOutcome.done) {
      _replace(_with(record, copiedAt: now));
      notifyListeners();
    }
    return copyOutcome;
  }

  @override
  Future<bool> reveal([DeviceRecord? record]) async {
    revealed.add(record?.name);
    return revealOpens;
  }

  @override
  Future<bool> delete(DeviceRecord record) async {
    if (!deleteWorks) {
      return false;
    }
    deleted.add(record.name);
    _entries.removeWhere((DeviceRecord known) => known.name == record.name);
    notifyListeners();
    return true;
  }
}
