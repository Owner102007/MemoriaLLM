import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:memoria/domain/settings/app_settings.dart';
import 'package:memoria/sno/recording/device_status.dart';
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

  @override
  Future<String?> read(String key) async => values[key];

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
    );
  }

  @override
  Future<void> put(String folder, String name, String content) async {
    files.putIfAbsent(folder, () => <String, String>{})[name] = content;
  }

  @override
  Future<List<String>> lastLines(
    String folder, {
    int count = kTailLines,
  }) async {
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

  @override
  Future<void> finish(String folder) async {
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
  _MemoryJournal(this._text, this._closed);

  final StringBuffer _text;
  final void Function() _closed;

  @override
  Future<void> append(String text) async {
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
