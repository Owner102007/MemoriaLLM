/// Тест нагрузки: сценарий, пароль и прохождение частей
/// (SNO-F-CLT-01, SNO-F-CLT-02, SNO-F-CLT-03).
///
/// Cognitive load test исследования СНО2026 из двух частей: один вопрос
/// об усилии после каждого блока и итоговая часть по паролю после
/// остановки записи. Здесь всё, что о тесте решается без экрана: какой
/// сценарий загружен, открыт ли замок, за какие блоки усилие ещё не
/// оценено, пройдена ли итоговая часть — и само прохождение части
/// ([LoadTestRun]): какой пункт показан, что выбрано, что ушло на диск.
///
/// **Что уже отвечено, знают файлы записи, а не память.** Ответы лежат
/// в подпапке `clt/` папки записи (`results.dart`), и состояние теста
/// читается из них: приложение, закрытое посреди итоговой части,
/// продолжает её с первого неотвеченного пункта, в том же файле.
///
/// Виджетов здесь нет; время и хранилище подменяются в тестах.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../recording/event.dart';
import '../recording/session.dart';
import '../recording/summary.dart';
import 'builtin_scenario.dart';
import 'results.dart';
import 'scenario.dart';

/// Сколько неверных паролей подряд закрывают ввод.
const int kCltPasswordTries = 3;

/// На сколько ввод пароля закрывается после неверных попыток.
const Duration kCltPasswordPause = Duration(seconds: 60);

/// Длиннее этого пароль не набирается.
const int kCltPasswordLimit = 12;

/// Подпапка папки данных приложения, где лежит файл, подменяющий
/// встроенный сценарий: `clt/<id сценария>.json`.
const String kCltOverrideFolder = 'clt';

/// Код «участника» пробного прохода: порядок пунктов у него свой, а
/// ответы никуда не пишутся.
const String kCltDryParticipant = '00000000';

/// Читает файл, подменяющий встроенный сценарий [id]; `null` — такого
/// файла нет. Файл есть, но не читается — исключение: тест с ним не
/// начинается.
typedef ScenarioOverride = Future<String?> Function(String id);

/// Чем кончилась попытка ввести пароль.
enum PasswordOutcome {
  /// Пароль верный.
  accepted,

  /// Пароль неверный; попытки ещё есть.
  wrong,

  /// Ввод закрыт: три неверные попытки подряд.
  locked,
}

int Function() _stopwatch() {
  final Stopwatch stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
}

/// Тест нагрузки сборки ветви СНО2026.
///
/// Есть только в сборке с паролем теста (`SNO_CLT_PASSWORD`,
/// SNO-DIV-06): без пароля теста в приложении нет вовсе.
class LoadTest extends ChangeNotifier {
  /// Создаёт тест поверх сессии записи [session].
  ///
  /// [password] — пароль экспериментатора, каким он пришёл при сборке;
  /// в журнал и в файлы он не попадает. [override] читает файл,
  /// подменяющий встроенный сценарий. [now] и [elapsedMs] подменяются в
  /// тестах: настенные часы — для паузы после неверных паролей,
  /// монотонный счёт — для времени ответа.
  LoadTest({
    required this.session,
    required String password,
    ScenarioOverride? override,
    DateTime Function()? now,
    int Function()? elapsedMs,
  }) : _password = password,
       _override = override,
       _now = now ?? DateTime.now,
       _elapsedMs = elapsedMs ?? _stopwatch() {
    _seen = session.state?.id;
    session.addListener(_sessionChanged);
  }

  /// Сессия записи: в её папку ложатся ответы, в её журнал — события.
  final RecordingSession session;

  final String _password;
  final ScenarioOverride? _override;
  final DateTime Function() _now;
  final int Function() _elapsedMs;

  CltScenario? _scenario;
  String _scenarioText = '';
  bool _overridden = false;
  String? _problem;
  bool _loaded = false;
  Future<void>? _loading;

  List<CltResult> _results = const <CltResult>[];
  String? _resultsOf;
  int _refreshRun = 0;

  String? _seen;
  String? _unlockedFor;
  int _wrong = 0;
  int _attempts = 0;
  DateTime? _lockedUntil;
  bool _disposed = false;

  /// Загруженный сценарий; `null` — ещё не загружен или не принят
  /// ([problem]).
  CltScenario? get scenario => _scenario;

  /// Почему сценарий не принят — словами для экспериментатора; `null`
  /// — принят или ещё не загружен.
  String? get problem => _problem;

  /// Загружен ли сценарий — принят он или нет.
  bool get loaded => _loaded;

  /// Подменён ли встроенный сценарий файлом из папки приложения.
  bool get overridden => _overridden;

  /// Сколько знаков в пароле: столько мест на экране ввода.
  int get passwordLength => _password.length;

  /// Загружает сценарий (SNO-F-CLT-02): встроенный либо файл с тем же
  /// `id` из папки приложения. Сценарий с ошибкой не принимается —
  /// [problem] называет причину, и тест не начинается.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final CltScenario builtin = parseCltScenario(kBuiltinCltScenario);
      String? replaced;
      try {
        replaced = await _override?.call(builtin.id);
      } on Object {
        throw const CltScenarioException('файл сценария не прочитался');
      }
      if (replaced == null) {
        _scenario = builtin;
        _scenarioText = const JsonEncoder.withIndent('  ')
            .convert(kBuiltinCltScenario);
      } else {
        final CltScenario parsed = parseCltScenario(jsonDecode(replaced));
        if (parsed.id != builtin.id) {
          throw CltScenarioException(
            'в файле сценарий «${parsed.id}», а нужен «${builtin.id}»',
          );
        }
        _scenario = parsed;
        _scenarioText = replaced;
        _overridden = true;
      }
    } on CltScenarioException catch (refused) {
      _problem = refused.reason;
    } on FormatException {
      _problem = 'файл сценария — не JSON';
    }
    _loaded = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _sessionChanged() {
    final String? id = session.state?.id;
    if (id != _seen) {
      // Другая сессия или сессии нет: замок закрыт, ответы — чужие.
      _seen = id;
      _unlockedFor = null;
      _attempts = 0;
      _results = const <CltResult>[];
      _resultsOf = null;
    }
    _notify();
  }

  /// Перечитывает ответы теста из папки записи.
  ///
  /// Зовётся, когда открывают экран завершения сессии и перед началом
  /// части: после перезапуска приложения в памяти ответов нет.
  Future<void> refresh() async {
    final int run = ++_refreshRun;
    final String? id = session.state?.id;
    final Map<String, String> files = id == null
        ? const <String, String>{}
        : await session.testFiles();
    if (run != _refreshRun || _disposed) {
      return;
    }
    _results = readCltResults(files);
    _resultsOf = id;
    _notify();
  }

  /// Файлы ответов идущей или остановленной записи.
  List<CltResult> get results {
    return _resultsOf != null && _resultsOf == session.state?.id
        ? _results
        : const <CltResult>[];
  }

  void _remember(CltResult result) {
    final String? id = session.state?.id;
    if (id == null) {
      return;
    }
    final String name = result.name;
    final List<CltResult> kept = <CltResult>[
      if (_resultsOf == id)
        for (final CltResult known in _results)
          if (known.name != name) known,
      result,
    ];
    kept.sort((CltResult a, CltResult b) => a.tStart.compareTo(b.tStart));
    _results = kept;
    _resultsOf = id;
  }

  bool _effortGiven(BlockMark block) {
    for (final CltResult result in results) {
      if (result.complete &&
          result.block == block.number &&
          result.blockStartMs == block.startMs) {
        return true;
      }
    }
    return false;
  }

  /// Блоки записи, за которые усилие ещё не оценено, по порядку
  /// (SNO-F-CLT-02): блок, который закрыла остановка записи, и блок,
  /// после которого приложение закрыли раньше ответа.
  List<BlockMark> get pendingEfforts {
    if (_scenario?.partFor(kCltBlockEnd) == null) {
      return const <BlockMark>[];
    }
    return <BlockMark>[
      for (final BlockMark block in session.blocks)
        if (!_effortGiven(block)) block,
    ];
  }

  /// Ответы итоговой части; `null` — её не начинали.
  CltResult? get finalResult => finalCltResult(results);

  /// Сколько пунктов в итоговой части; ноль — такой части в сценарии
  /// нет.
  int get finalItems => _scenario?.partFor(kCltSessionEnd)?.length ?? 0;

  /// Пройдена ли итоговая часть до конца.
  bool get finalDone => finalResult?.complete ?? false;

  /// Открыт ли тест паролем (SNO-F-CLT-01): после верного пароля
  /// повторный вход до завершения сессии его не спрашивает. Вне
  /// остановленной сессии замок закрыт всегда: пробный проход
  /// спрашивает пароль каждый раз.
  bool get unlocked {
    final SessionState? state = session.state;
    return state != null &&
        state.phase == RecordingPhase.stopped &&
        _unlockedFor == state.id;
  }

  /// Сколько секунд ввод пароля ещё закрыт; ноль — открыт.
  int get lockedSeconds {
    final DateTime? until = _lockedUntil;
    if (until == null) {
      return 0;
    }
    final int left = until.difference(_now()).inMilliseconds;
    return left <= 0 ? 0 : (left + 999) ~/ 1000;
  }

  /// Проверяет пароль [input] (SNO-F-CLT-01).
  ///
  /// Три неверные попытки подряд закрывают ввод на
  /// [kCltPasswordPause]. Попытка пишется в журнал записи — удалась
  /// или нет, без самого ввода.
  Future<PasswordOutcome> enter(String input) async {
    if (lockedSeconds > 0) {
      return PasswordOutcome.locked;
    }
    _lockedUntil = null;
    final bool accepted = input == _password;
    _attempts++;
    bool locked = false;
    if (accepted) {
      _wrong = 0;
      final SessionState? state = session.state;
      _unlockedFor = state != null && state.phase == RecordingPhase.stopped
          ? state.id
          : null;
    } else {
      _wrong++;
      if (_wrong >= kCltPasswordTries) {
        _wrong = 0;
        _lockedUntil = _now().add(kCltPasswordPause);
        locked = true;
      }
    }
    _notify();
    await session.logTest(
      SnoEventType.cltPassword,
      data: <String, Object?>{
        'ok': accepted,
        'n': _attempts,
        if (locked) 'locked_s': kCltPasswordPause.inSeconds,
      },
    );
    if (accepted) {
      return PasswordOutcome.accepted;
    }
    return locked ? PasswordOutcome.locked : PasswordOutcome.wrong;
  }

  /// Начинает часть теста, которая показывается в миг [when]
  /// ([kCltBlockEnd] или [kCltSessionEnd]); `null` — начинать нечего:
  /// сценарий не принят, такой части в нём нет, сессии нет или замок
  /// закрыт.
  ///
  /// [block] — блок, за который оценивается усилие. [dry] — пробный
  /// проход экспериментатора без записи: ответы никуда не пишутся.
  ///
  /// Часть, начатую и не оконченную, продолжает с первого
  /// неотвеченного пункта — в том же файле.
  Future<LoadTestRun?> begin(
    String when, {
    BlockMark? block,
    bool dry = false,
  }) async {
    await load();
    final CltScenario? scenario = _scenario;
    final CltPart? part = scenario?.partFor(when);
    if (scenario == null || part == null) {
      return null;
    }
    if (dry) {
      return LoadTestRun._(
        owner: this,
        scenario: scenario,
        part: part,
        items: orderedCltItems(
          part,
          scenario: scenario.id,
          participant: kCltDryParticipant,
        ),
        dry: true,
      );
    }
    final SessionState? state = session.state;
    if (state == null || (part.password && !unlocked)) {
      return null;
    }
    // Что уже отвечено — с диска и мимо [refresh]: чтение, начатое
    // раньше, этот ответ не подменит.
    _refreshRun++;
    final Map<String, String> files = await session.testFiles();
    if (_disposed || session.state?.id != state.id) {
      return null;
    }
    _results = readCltResults(files);
    _resultsOf = state.id;
    final List<CltItem> items = orderedCltItems(
      part,
      scenario: scenario.id,
      participant: state.participant.code,
    );
    final List<String> order = <String>[
      for (final CltItem item in items) item.id,
    ];
    CltResult? open;
    for (final CltResult result in results) {
      if (!result.complete &&
          result.part == part.id &&
          result.scenario == scenario.id &&
          result.version == scenario.version &&
          result.block == block?.number &&
          result.blockStartMs == block?.startMs &&
          listEquals(result.order, order)) {
        open = result;
      }
    }
    final LoadTestRun run = LoadTestRun._(
      owner: this,
      scenario: scenario,
      part: part,
      items: items,
      dry: false,
      block: block,
      participant: state.participant.code,
      tStart: open?.tStart ?? session.testNow,
      answers: open?.answers ?? const <CltAnswer>[],
    );
    await run._start(resumed: open != null);
    return run;
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

/// Прохождение одной части теста (SNO-F-CLT-02, SNO-F-CLT-03).
///
/// Пункты идут по одному. Пропустить пункт нельзя; вернуться можно на
/// один пункт назад. Каждый принятый ответ сразу ложится в файл части.
class LoadTestRun extends ChangeNotifier {
  LoadTestRun._({
    required LoadTest owner,
    required this.scenario,
    required this.part,
    required this.items,
    required this.dry,
    this.block,
    String participant = kCltDryParticipant,
    int tStart = 0,
    List<CltAnswer> answers = const <CltAnswer>[],
  }) : _owner = owner,
       _participant = participant,
       _tStart = tStart {
    final Set<String> known = <String>{
      for (final CltItem item in items) item.id,
    };
    for (final CltAnswer answer in answers) {
      if (known.contains(answer.item)) {
        _answers[answer.item] = answer;
      }
    }
    int first = 0;
    while (first < items.length - 1 && _answers.containsKey(items[first].id)) {
      first++;
    }
    _index = first;
    _furthest = first;
    _show();
  }

  final LoadTest _owner;
  final String _participant;
  final int _tStart;

  /// Сценарий, по которому идёт часть.
  final CltScenario scenario;

  /// Часть.
  final CltPart part;

  /// Пункты в порядке показа.
  final List<CltItem> items;

  /// Пробный ли это проход: ответы никуда не пишутся.
  final bool dry;

  /// Блок, за который оценивается усилие; `null` — часть не о блоке.
  final BlockMark? block;

  final Map<String, CltAnswer> _answers = <String, CltAnswer>{};
  int _index = 0;
  int _furthest = 0;
  int? _selected;
  int _shownAt = 0;
  int? _chosenAt;
  bool _changed = false;
  bool _finished = false;
  bool _saving = false;
  bool _saveFailed = false;
  int? _tEnd;
  bool _disposed = false;

  /// Номер показанного пункта, считая с нуля.
  int get index => _index;

  /// Сколько в части пунктов.
  int get length => items.length;

  /// Показанный пункт.
  CltItem get item => items[_index];

  /// Выбранное значение; `null` — ещё не выбрано.
  int? get selected => _selected;

  /// Пройдена ли часть до конца.
  bool get finished => _finished;

  /// Идёт ли запись ответа на диск.
  bool get saving => _saving;

  /// Не лёг ли последний ответ на диск.
  bool get saveFailed => _saveFailed;

  /// Сколько пунктов уже отвечено.
  int get answered => _answers.length;

  /// Можно ли идти дальше: значение выбрано.
  bool get canNext => !_finished && !_saving && _selected != null;

  /// Можно ли вернуться: только на один пункт назад от самого дальнего.
  bool get canBack {
    return !_finished && !_saving && _index > 0 && _index == _furthest;
  }

  /// Имя файла ответов этой части в папке записи.
  String get fileName => cltResultName(scenario.id, part.id, _tStart);

  void _show() {
    _selected = _answers[item.id]?.value;
    _shownAt = _owner._elapsedMs();
    _chosenAt = null;
    _changed = false;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Выбирает значение [value] на шкале показанного пункта.
  void choose(int value) {
    if (_finished || _saving || !item.scale.holds(value)) {
      return;
    }
    if (_selected != value) {
      _selected = value;
      _chosenAt = _owner._elapsedMs();
      _changed = true;
      _notify();
    }
  }

  /// Сдвигает выбранное значение на [steps] делений; без выбранного —
  /// встаёт на середину шкалы.
  void nudge(int steps) {
    final CltScale scale = item.scale;
    final int? value = _selected;
    if (value == null) {
      choose(scale.min + (scale.divisions ~/ 2) * scale.step);
      return;
    }
    final int moved = value + steps * scale.step;
    choose(
      moved < scale.min ? scale.min : (moved > scale.max ? scale.max : moved),
    );
  }

  /// Возвращает к предыдущему пункту.
  void back() {
    if (!canBack) {
      return;
    }
    _index--;
    _show();
    _notify();
  }

  /// Принимает ответ и показывает следующий пункт; за последним —
  /// заканчивает часть.
  Future<void> next() async {
    final int? value = _selected;
    if (_finished || _saving || value == null) {
      return;
    }
    final CltItem current = item;
    final CltAnswer? before = _answers[current.id];
    if (before == null || _changed) {
      final int spent = (_chosenAt ?? _owner._elapsedMs()) - _shownAt;
      _answers[current.id] = CltAnswer(
        item: current.id,
        value: value,
        rtMs: spent < 0 ? 0 : spent,
        order: _index + 1,
        min: current.scale.min,
        max: current.scale.max,
        t: dry ? null : _owner.session.testNow,
        reverse: current.reverse,
        revised: before != null,
      );
    }
    if (_index >= items.length - 1) {
      _finished = true;
      _tEnd = dry ? null : _owner.session.testNow;
    } else {
      _index++;
      if (_index > _furthest) {
        _furthest = _index;
      }
      _show();
    }
    _saving = true;
    _notify();
    await _save();
    if (_finished && !dry) {
      final int? ended = _tEnd;
      await _owner.session.logTest(
        SnoEventType.cltFinish,
        data: <String, Object?>{
          'part': part.id,
          if (block != null) 'block': block?.number,
          'file': fileName,
          'answers': _answers.length,
          if (ended != null) 'duration_ms': ended - _tStart,
        },
      );
    }
    _saving = false;
    _notify();
    if (_finished) {
      _owner._notify();
    }
  }

  CltResult _result() {
    return CltResult(
      scenario: scenario.id,
      version: scenario.version,
      participant: _participant,
      part: part.id,
      block: block?.number,
      blockStartMs: block?.startMs,
      tStart: _tStart,
      tEnd: _tEnd,
      order: <String>[for (final CltItem item in items) item.id],
      answers: <CltAnswer>[
        for (final CltItem item in items)
          if (_answers[item.id] != null) _answers[item.id]!,
      ],
      complete: _finished,
    );
  }

  /// Кладёт файл части на диск: каждый ответ — сразу (SNO-F-CLT-03).
  Future<void> _save() async {
    if (dry) {
      return;
    }
    final CltResult result = _result();
    _saveFailed = !await _owner.session.putTestFile(
      result.name,
      result.encode(),
    );
    _owner._remember(result);
  }

  Future<void> _start({required bool resumed}) async {
    final RecordingSession session = _owner.session;
    // Сценарий, каким его видит участник, — рядом с ответами: один раз
    // на запись.
    if (!await session.hasTestFile(kCltScenarioFile)) {
      await session.putTestFile(kCltScenarioFile, _owner._scenarioText);
    }
    await _save();
    await session.logTest(
      SnoEventType.cltStart,
      data: <String, Object?>{
        'part': part.id,
        if (block != null) 'block': block?.number,
        'file': fileName,
        'scenario': scenario.id,
        'version': scenario.version,
        'items': items.length,
        if (resumed) 'resumed_at': _index + 1,
        if (_owner.overridden) 'override': true,
      },
    );
    // Время ответа на первый пункт — от показа, а не от обращения к
    // диску перед ним.
    _shownAt = _owner._elapsedMs();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
