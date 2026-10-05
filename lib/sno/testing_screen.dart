import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_services.dart';
import '../application/build_info.dart';
import '../application/library/book_importer.dart';
import '../domain/library/archive_scan.dart';
import '../domain/library/book.dart';
import '../domain/library/book_file_picker.dart';
import '../domain/library/device_scan.dart';
import '../domain/library/scan_mark.dart';
import '../domain/library/shelf_archive.dart';
import '../domain/library/storage_access.dart';
import '../domain/reading/reader_document.dart';
import 'flags.dart';
import 'hold_button.dart';
import 'literature_archive.dart';
import 'participant_code.dart';
import 'recording/code_screen.dart';
import 'recording/finish_screen.dart';
import 'recording/records.dart';
import 'recording/records_screen.dart';
import 'recording/session.dart';
import 'reference_state.dart';

export 'participant_code.dart' show deviceCodeOf, kDeviceCodeLength;

/// Сколько неудач названо в сообщении поимённо.
const int kNamedFailures = 3;

/// Почему файл не встал на полку — словами для экспериментатора.
///
/// Слова свои, а не из `describeDocumentProblem`: тот текст написан для
/// экрана чтения и зовёт ввести пароль, а здесь вводить его негде. И
/// «не PDF» названо прямо: движок отличить чужой файл от битого PDF не
/// умеет, и сказать можно только про оба сразу.
String describeAddFailure(ImportFailure failure) {
  return switch (failure.problem) {
    DocumentProblem.passwordRequired ||
    DocumentProblem.wrongPassword => 'защищён паролем',
    DocumentProblem.damaged => 'не PDF или файл повреждён',
    DocumentProblem.empty => 'файл пустой',
    DocumentProblem.missing => 'до файла не добраться',
    DocumentProblem.unknown => 'не удалось открыть',
    null => failure.reason,
  };
}

/// Книга ли это, судя по имени файла.
bool isBookName(String name) => name.toLowerCase().endsWith('.pdf');

/// Что сказать, когда вместо архива выбрали книги (решение владельца П3
/// от 04.10.2026).
///
/// Свои PDF в сборках для тестирования не добавляются: у всех
/// тестировщиков одна и та же полка, и встаёт она только из архива с
/// литературой. Книга, выбранная вручную, названа — и на полку не
/// попадает.
String describeRefusedBooks(List<String> names) {
  final String listed = names
      .take(kNamedFailures)
      .map((String name) => '«$name»')
      .join(', ');
  final int rest = names.length - kNamedFailures;
  final String all = rest > 0 ? '$listed и ещё $rest' : listed;
  return 'Не добавлено: $all. В сборке для тестирования книги встают '
      'на полку только из архива с литературой.';
}

/// Что сказать экспериментатору после добавления архива (SNO-F-LIT-01).
///
/// Архив распаковывается минуты, и итог обязан отвечать на три вопроса:
/// сколько книг встало, чего на полке нет и почему, и надо ли добавлять
/// архив ещё раз.
String describeArchiveReport(ArchiveReport report) {
  final String? refusal = report.refusal;
  if (refusal != null) {
    return 'Архив не добавлен: $refusal.';
  }
  final List<String> lines = <String>[];
  final int added = report.added.length;
  final int categories = report.categories;
  if (added > 0) {
    lines.add(
      categories > 0
          ? 'Добавлено книг: $added, категорий: $categories.'
          : 'Добавлено книг: $added.',
    );
  }
  if (report.already > 0) {
    lines.add(
      added == 0 && report.already == report.total
          ? 'Все книги архива уже на полке: ${report.already}.'
          : 'Уже стояло на полке: ${report.already}.',
    );
  }
  final int scans = report.added
      .where((Book book) => isMarkedScan(book.hasTextLayer))
      .length;
  if (scans > 0) {
    lines.add(
      'Сканов без текста: $scans — в них не работают выделение, поиск '
      'и функции.',
    );
  }
  if (report.repeats > 0) {
    lines.add(
      'Одинаковых файлов в архиве: ${report.repeats} — такая книга '
      'стоит на полке один раз.',
    );
  }
  if (report.skipped > 0) {
    lines.add('Пропущено не-PDF: ${report.skipped}.');
  }
  if (report.failed.isNotEmpty) {
    lines.add('Не открылось: ${report.failed.length}');
    for (final ImportFailure failure in report.failed.take(kNamedFailures)) {
      lines.add('«${failure.name}» — ${describeAddFailure(failure)}');
    }
    final int rest = report.failed.length - kNamedFailures;
    if (rest > 0) {
      lines.add('И ещё не добавлено: $rest');
    }
  }
  final String? stopped = report.stopped;
  if (stopped != null) {
    lines.add(
      'Распаковка остановлена: $stopped. Распакованное осталось на '
      'полке; добавьте архив ещё раз — продолжит с того же места.',
    );
  }
  return lines.join('\n');
}

/// Что известно о поиске архивов на устройстве (SNO-F-LIT-03).
enum ArchiveSearchPhase {
  /// Блок «Для экспериментатора» ещё не раскрывали: ничего не искали.
  idle,

  /// На телефоне нет доступа к файлам: искать нельзя, пока его не дали.
  needsAccess,

  /// Обход идёт; найденное уже стоит в списке.
  searching,

  /// Обход кончился — дошёл до конца или оборвался.
  finished,
}

/// Готовность к записи одной строкой: «место 1,2 ГБ · заряд 84 %».
///
/// Пусто — устройство ничего о себе не сказало. Мало места или заряда
/// — сказано словами: это предупреждение, не запрет (SNO-F-REC-01).
String describeReadiness(Readiness readiness) {
  final int? free = readiness.freeBytes;
  final int? battery = readiness.batteryPercent;
  return <String>[
    if (free != null)
      readiness.lowSpace
          ? 'мало места: ${describeFileSize(free)}'
          : 'место ${describeFileSize(free)}',
    if (battery != null)
      readiness.lowBattery ? 'низкий заряд: $battery %' : 'заряд $battery %',
  ].join(' · ');
}

/// Раздел «Тестирование» сборок ветвей СНО2026 (SNO-F-CFG-03).
///
/// Единственное место инструментов исследования: всё остальное
/// приложение остаётся читалкой. Пунктов-заглушек здесь нет —
/// cognitive load test и записи на устройстве появляются вместе со
/// своими функциями. Сейчас в разделе: код устройства, запись сессии
/// (SNO-F-REC-01), блок «Для экспериментатора» с архивами литературы
/// (SNO-F-LIT-03, SNO-F-LIT-01) и эталонным состоянием (SNO-F-CFG-04),
/// сведения о ветви (SNO-F-CFG-01).
///
/// **Запись сессии** (SNO-F-REC-01, `recording/session.dart`). «Старт
/// записи» выдаёт код участника (SNO-F-CFG-05) и начинает запись только
/// после «Код записан». Пока запись идёт, здесь — и только здесь —
/// видно, сколько её осталось: в чтении счёта нет, он подгонял бы
/// участника. После остановки раздел ведёт на завершение сессии. Пока
/// сессия не завершена, полка под замком, и здесь нельзя ни добавить
/// архив, ни сбросить устройство: и то и другое меняет полку.
///
/// **Записи на устройстве** (SNO-F-REC-07, `recording/records.dart`).
/// Пока сессии нет, под стартом записи стоит строка «Записи на
/// устройстве · 3, не отправлено 1» — она ведёт к списку архивов. Во
/// время записи и до «Завершить сессию» строки нет: участнику чужие
/// записи не показываются.
///
/// **Архив с литературой приложение находит само** (SNO-F-LIT-03).
/// Когда блок «Для экспериментатора» раскрыт, устройство обходится
/// (`AppServices.archiveSearch`), и ZIP-архивы с книгами встают списком;
/// нажатие на архив раскладывает его по полке. Обход начинается только
/// отсюда: запуск приложения и полка ничего не ищут, и тестировщик,
/// который в блок не заходит, запроса на доступ к файлам не видит.
/// Системный диалог выбора остаётся запасным путём.
///
/// **Свои PDF не добавляются** (SNO-F-LIT-02 снята решением владельца
/// П3 от 04.10.2026): книга, выбранная вручную вместо архива, названа
/// отказом и на полку не встаёт.
///
/// **Эталонное состояние** (SNO-F-CFG-04, `reference_state.dart`).
/// Разложенный архив запоминается эталоном; экспериментатор перед новым
/// тестировщиком удерживает «Сбросить» — следы предыдущего стёрты,
/// полка и настройки снова как после архива. Сброс прячется в том же
/// блоке и срабатывает только удержанием: стирает он по-настоящему.
class TestingScreen extends StatefulWidget {
  /// Создаёт раздел.
  ///
  /// [unpack] подменяет распаковку архива в widget-тестах: настоящая
  /// пишет на диск, а в них файлового ввода-вывода быть не должно.
  const TestingScreen({
    required this.services,
    required this.flags,
    this.unpack,
    this.visible = true,
    this.onStateReset,
    this.onRecordingStarted,
    super.key,
  });

  /// Службы приложения.
  final AppServices services;

  /// Флаги сборки — для строки «О ветви».
  final BranchFlags flags;

  /// Распаковка архива; `null` — настоящая.
  final ArchiveUnpack? unpack;

  /// На экране ли раздел сейчас.
  ///
  /// Разделы живут в одном `IndexedStack`, и «Тестирование» не узнаёт
  /// само, что из него уходили читать: вернулись — и слова «совпадает с
  /// эталоном» обязаны быть проверены заново.
  final bool visible;

  /// Устройство сброшено к эталону: оболочке пора перечитать то, что
  /// она держит в памяти, — тему и порядок полки.
  final VoidCallback? onStateReset;

  /// Запись началась: оболочке пора вернуть участника на полку.
  final VoidCallback? onRecordingStarted;

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen>
    with WidgetsBindingObserver {
  /// Идёт ли добавление архива.
  bool _busy = false;

  /// Открыт ли диалог выбора: второе нажатие, пока он открыт, не должно
  /// начать второе добавление.
  bool _picking = false;

  /// Имя архива, который добавляется сейчас; `null` — архив не идёт.
  String? _archiveName;

  /// Какая книга архива распаковывается; `null` — архив ещё открывается
  /// или не идёт вовсе.
  ArchiveProgress? _unpacking;

  /// Раскрыт ли блок «Для экспериментатора».
  bool _expanded = false;

  /// Что известно о поиске архивов.
  ArchiveSearchPhase _phase = ArchiveSearchPhase.idle;

  /// Найденные архивы, в порядке списка.
  List<FoundArchive> _found = const <FoundArchive>[];

  /// Корни обхода — от них считается, где лежит архив.
  List<String> _roots = const <String>[];

  /// Почему обход оборвался; `null` — идёт или дошёл до конца.
  String? _searchFailure;

  /// Идущий обход.
  StreamSubscription<FoundArchive>? _searching;

  /// Номер поиска: ответ прежнего поиска, пришедший после начала
  /// нового, не принимается.
  int _searchRun = 0;

  /// Открывается ли системный экран доступа: второе нажатие, пока он
  /// открывается, второго экрана не заводит.
  bool _asking = false;

  /// Эталонное состояние; `null` — ещё не запомнено.
  ReferenceState? _reference;

  /// Совпадает ли устройство с эталоном; `null` — не знаем.
  bool? _matches;

  /// Когда устройство сбрасывали в последний раз.
  DateTime? _lastReset;

  /// Идёт ли сброс.
  bool _resetting = false;

  /// Чем кончился последний сброс — словами; `null` — не сбрасывали.
  String? _resetResult;

  /// Номер чтения эталона: ответ прежнего чтения, пришедший после
  /// начала нового, не принимается.
  int _referenceRun = 0;

  /// Заряд и свободное место; `null` — ещё не спрашивали.
  Readiness? _readiness;

  /// Номер вопроса о готовности: запоздавший ответ не принимается.
  int _readinessRun = 0;

  /// Идёт ли старт записи: от нажатия до начавшейся записи.
  bool _starting = false;

  /// Почему запись не началась; `null` — такого не было.
  String? _startFailure;

  /// Сессия записи; `null` — в этой сборке записи нет.
  RecordingSession? get _session => widget.services.recording;

  /// Записи на устройстве; `null` — в этой сборке их нет.
  DeviceRecords? get _records => widget.services.records;

  /// Начата ли и не завершена ли сессия: пока это так, полку менять
  /// нельзя ничем — ни архивом, ни сбросом.
  bool get _sessionOpen => _session?.locked ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session?.addListener(_sessionChanged);
    _records?.addListener(_recordsChanged);
    unawaited(_refreshReadiness());
    unawaited(_refreshRecords());
  }

  void _recordsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Перечитывает список записей (SNO-F-REC-07): архив могли убрать
  /// или положить руками, пока раздела не было на экране.
  Future<void> _refreshRecords() async {
    try {
      await _records?.refresh();
    } on Object {
      // Папка записей не прочиталась: строка покажет прежнее.
    }
  }

  void _openRecords(DeviceRecords records) {
    unawaited(
      openDeviceRecords(Navigator.of(context, rootNavigator: true), records),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_sessionChanged);
    _records?.removeListener(_recordsChanged);
    _searchRun++;
    unawaited(_searching?.cancel());
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      // SNO-F-CFG-03: номер блока, набранный руками, живёт одну запись —
      // следующая начинает счёт блоков заново.
      if (_session?.phase != RecordingPhase.recording) {
        _blockNumber = null;
      }
    });
    // Сессию завершили: заряд и место под «Старт записи» — уже не те,
    // что были сорок минут назад.
    if (_session?.phase == RecordingPhase.idle) {
      unawaited(_refreshReadiness());
    }
  }

  /// Спрашивает у устройства заряд и свободное место (SNO-F-REC-01).
  Future<void> _refreshReadiness() async {
    final RecordingSession? session = _session;
    if (session == null) {
      return;
    }
    final int run = ++_readinessRun;
    final Readiness readiness = await session.readiness();
    if (mounted && run == _readinessRun) {
      setState(() => _readiness = readiness);
    }
  }

  /// Начинает запись: код участника, подтверждение, старт
  /// (SNO-F-REC-01, SNO-F-CFG-05).
  Future<void> _startRecording(RecordingSession session) async {
    if (_starting || _busy || _resetting || session.locked) {
      return;
    }
    setState(() {
      _starting = true;
      _startFailure = null;
    });
    try {
      final Readiness readiness = await session.readiness();
      final ParticipantCode proposed = await session.proposeCode();
      if (!mounted) {
        return;
      }
      setState(() => _readiness = readiness);
      final ParticipantCode? code =
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<ParticipantCode>(
              builder: (BuildContext context) {
                return ParticipantCodeScreen(
                  proposed: proposed,
                  readiness: readiness,
                  parse: session.enteredCode,
                  minutes: session.planned.inMinutes,
                );
              },
            ),
          );
      if (code == null) {
        return;
      }
      final bool started = await session.start(code);
      if (!started) {
        _startFailure =
            'Запись не началась: её не удалось завести на устройстве. '
            'Проверьте свободное место и попробуйте ещё раз.';
        return;
      }
      widget.onRecordingStarted?.call();
    } on Object {
      _startFailure = 'Запись не началась из-за ошибки приложения.';
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  /// Открывает завершение сессии (SNO-SCR-08).
  void _openFinish(RecordingSession session) {
    unawaited(
      openSessionFinish(
        Navigator.of(context, rootNavigator: true),
        session,
        records: _records,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Доступ к файлам выдают на системном экране, и ответа Android не
    // даёт: узнать о нём можно, только спросив заново, когда приложение
    // вернулось на передний план.
    if (state == AppLifecycleState.resumed &&
        _expanded &&
        _phase == ArchiveSearchPhase.needsAccess) {
      unawaited(_search());
    }
  }

  @override
  void didUpdateWidget(TestingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // В раздел вернулись: за это время могли читать, выделять и
    // переставлять книги.
    if (widget.visible && !oldWidget.visible && _expanded) {
      // Итог прошлого сброса к нынешнему состоянию уже не относится.
      _resetResult = null;
      unawaited(_refreshReference());
    }
    if (widget.visible && !oldWidget.visible) {
      // Заряд и место за это время изменились.
      unawaited(_refreshReadiness());
      unawaited(_refreshRecords());
    }
    if (!identical(oldWidget.services.recording, widget.services.recording)) {
      oldWidget.services.recording?.removeListener(_sessionChanged);
      _session?.addListener(_sessionChanged);
    }
    if (!identical(oldWidget.services.records, widget.services.records)) {
      oldWidget.services.records?.removeListener(_recordsChanged);
      _records?.addListener(_recordsChanged);
    }
  }

  void _expansionChanged(bool expanded) {
    _expanded = expanded;
    if (expanded) {
      unawaited(_refreshReference());
    }
    // Обход, который уже идёт, заново не начинается: блок свернули и
    // раскрыли, а архивы всё те же.
    if (expanded && _phase != ArchiveSearchPhase.searching) {
      unawaited(_search());
    }
  }

  /// Эталон и сброс — на службах приложения.
  ReferenceKeeper _keeper() {
    return ReferenceKeeper(
      data: widget.services.data,
      storage: widget.services.storage,
    );
  }

  /// Читает эталон и сверяет с ним устройство (SNO-F-CFG-04).
  Future<void> _refreshReference() async {
    final int run = ++_referenceRun;
    final ReferenceKeeper keeper = _keeper();
    final ReferenceState? reference;
    final bool? matches;
    final DateTime? lastReset;
    try {
      reference = await keeper.reference();
      matches = reference == null
          ? null
          : (await keeper.snapshot()).matches(reference);
      lastReset = await keeper.lastReset();
    } on Object {
      // База не ответила — раздел остаётся с тем, что знал.
      return;
    }
    if (!mounted || run != _referenceRun) {
      return;
    }
    setState(() {
      _reference = reference;
      _matches = matches;
      _lastReset = lastReset;
    });
  }

  /// Запоминает эталон после разложенного архива (SNO-F-CFG-04).
  ///
  /// Эталон — полка, какой её кладёт архив: его запоминает сама
  /// распаковка, а не кнопка. В эталон идут все книги архива, стоящие
  /// на полке, — и вставшие сейчас, и стоявшие раньше.
  Future<void> _rememberReference(List<ArchiveReport> unpacked) async {
    try {
      await _keeper().remember(<ArchivePlacement>[
        for (final ArchiveReport report in unpacked) ...report.placed,
      ]);
    } on Object {
      // Эталон не запомнился — книги при этом на полке, и повторное
      // добавление архива запомнит его заново.
    }
    await _refreshReference();
  }

  /// Сбрасывает устройство к эталонному состоянию (SNO-F-CFG-04).
  Future<void> _reset() async {
    // SNO-F-REC-01: пока сессия не завершена, сброса нет — он стёр бы
    // следы участника, чья запись ещё не закрыта.
    if (_busy || _resetting || _starting || _sessionOpen) {
      return;
    }
    setState(() {
      _resetting = true;
      _resetResult = null;
    });
    final String result = await _runReset();
    await _refreshReference();
    if (mounted) {
      setState(() {
        _resetting = false;
        _resetResult = result;
      });
    }
  }

  /// Сам сброс; отвечает словами для экспериментатора и не бросает.
  Future<String> _runReset() async {
    final ResetReport report;
    try {
      report = await _keeper().reset();
    } on Object {
      return 'Сброс не удался: состояние осталось прежним.';
    }
    // Тема и порядок полки лежат в памяти оболочки — пора перечитать.
    widget.onStateReset?.call();
    return describeReset(report);
  }

  /// Ищет архивы с книгами на устройстве (SNO-F-LIT-03).
  ///
  /// На телефоне без доступа ко всем файлам искать нечем: раздел
  /// говорит об этом и предлагает дать доступ — или выбрать архив
  /// вручную. На ПК доступ не нужен.
  Future<void> _search() async {
    final int run = ++_searchRun;
    // Отписка останавливает прежний обход сразу, и ждать её незачем:
    // запоздавший ответ прежнего обхода отсекает его номер.
    unawaited(_searching?.cancel());
    _searching = null;
    final StorageAccessState access = await widget.services.access.state();
    if (!mounted || run != _searchRun) {
      return;
    }
    if (!access.allowsScan) {
      setState(() {
        _phase = ArchiveSearchPhase.needsAccess;
        _found = const <FoundArchive>[];
        _searchFailure = null;
      });
      return;
    }
    final List<String> roots = await widget.services.access.roots();
    if (!mounted || run != _searchRun) {
      return;
    }
    setState(() {
      _phase = ArchiveSearchPhase.searching;
      _found = const <FoundArchive>[];
      _roots = roots;
      _searchFailure = null;
    });
    final Stream<FoundArchive> stream = widget.services.archiveSearch(roots);
    _searching = stream.listen(
      (FoundArchive archive) {
        if (!mounted || run != _searchRun) {
          return;
        }
        // Пока идёт обход, находка встаёт в конец списка: строки, уже
        // стоящие на экране, из-под пальца не уезжают.
        setState(() => _found = <FoundArchive>[..._found, archive]);
      },
      onError: (Object error) {
        if (!mounted || run != _searchRun) {
          return;
        }
        final String reason = error is ScanFailure
            ? error.reason
            : 'обход устройства не удался';
        setState(() => _searchFailure = reason);
      },
      onDone: () {
        if (!mounted || run != _searchRun) {
          return;
        }
        // Обход кончился — список встаёт в свой порядок: новые сверху.
        final List<FoundArchive> found = <FoundArchive>[..._found];
        found.sort(compareFoundArchives);
        setState(() {
          _found = found;
          _phase = ArchiveSearchPhase.finished;
        });
      },
    );
  }

  /// Открывает системный экран выдачи доступа к файлам.
  ///
  /// Ответ приходит не сюда: состояние перепроверяется, когда
  /// приложение снова на переднем плане
  /// ([didChangeAppLifecycleState]). Сразу оно спрашивается на случай,
  /// когда доступ дан без ухода из приложения.
  Future<void> _allowAndSearch() async {
    if (_asking) {
      return;
    }
    _asking = true;
    try {
      await widget.services.access.request();
      if (mounted) {
        await _search();
      }
    } finally {
      _asking = false;
    }
  }

  /// Выбор архива системным диалогом — запасной путь.
  Future<void> _pickArchives() async {
    if (_busy || _picking || _resetting || _starting || _sessionOpen) {
      return;
    }
    final List<PickedFile> files;
    _picking = true;
    try {
      files = await widget.services.picker.pickArchives();
    } finally {
      _picking = false;
    }
    if (files.isEmpty || !mounted) {
      return;
    }
    await _addArchives(files);
  }

  /// Раскладывает архивы [files] по полке (SNO-F-LIT-01).
  ///
  /// Сюда приходит и архив из найденных, и выбранное диалогом. Книга
  /// (PDF) вместо архива не добавляется и названа в итоге (решение П3);
  /// всё остальное уходит в распаковку, и не-архив получает свой отказ
  /// от неё — «это не ZIP-архив».
  Future<void> _addArchives(List<PickedFile> files) async {
    // SNO-F-LIB-02: пока сессия не завершена, полка не меняется ничем.
    if (_busy || _resetting || _starting || _sessionOpen) {
      return;
    }
    final List<PickedFile> archives = <PickedFile>[
      for (final PickedFile file in files)
        if (!isBookName(file.name)) file,
    ];
    final List<String> books = <String>[
      for (final PickedFile file in files)
        if (isBookName(file.name)) file.name,
    ];
    final List<ArchiveReport> unpacked = <ArchiveReport>[];
    if (archives.isNotEmpty) {
      setState(() {
        _busy = true;
        _archiveName = null;
        _unpacking = null;
      });
      try {
        final ArchiveUnpack unpack = widget.unpack ?? _archive().add;
        for (final PickedFile archive in archives) {
          if (mounted) {
            setState(() {
              _archiveName = archive.name;
              _unpacking = null;
            });
          }
          try {
            unpacked.add(
              await unpack(
                archive,
                onProgress: (ArchiveProgress progress) {
                  if (mounted) {
                    setState(() => _unpacking = progress);
                  }
                },
              ),
            );
          } on Object {
            // Распаковка обещает не бросать; если всё же бросила, итог
            // остальных файлов не должен пропасть вместе с ней.
            unpacked.add(
              ArchiveReport(
                archive: archive.name,
                stopped: 'распаковка прервалась из-за ошибки приложения',
              ),
            );
          }
        }
        // SNO-F-CFG-04: эталон — полка, какой её положил архив.
        await _rememberReference(unpacked);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _archiveName = null;
            _unpacking = null;
          });
        }
      }
    }
    if (!mounted) {
      return;
    }
    // Итог — окном, которое само не исчезает: распаковка идёт минуты, и
    // экспериментатор мог отвернуться.
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          key: const Key('sno-archive-report'),
          title: Text(_reportTitle(unpacked)),
          content: SingleChildScrollView(
            child: Text(_describeAll(books, unpacked)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Понятно'),
            ),
          ],
        );
      },
    );
  }

  /// Настоящая распаковка архива — на службах приложения.
  LiteratureArchive _archive() {
    return LiteratureArchive(
      library: widget.services.data.library,
      categories: widget.services.data.categories,
      storage: widget.services.storage,
      opener: widget.services.opener,
    );
  }

  String _reportTitle(List<ArchiveReport> archives) {
    if (archives.isEmpty) {
      return 'Книги добавляются архивом';
    }
    return archives.length == 1
        ? 'Архив «${archives.single.archive}»'
        : 'Архивы: ${archives.length}';
  }

  /// Итог всего выбранного одним текстом.
  String _describeAll(List<String> books, List<ArchiveReport> archives) {
    return <String>[
      if (books.isNotEmpty) describeRefusedBooks(books),
      for (final ArchiveReport archive in archives)
        archives.length == 1
            ? describeArchiveReport(archive)
            : '«${archive.archive}»\n${describeArchiveReport(archive)}',
    ].join('\n\n');
  }

  /// Что написано в строке хода, пока идёт распаковка.
  Widget _progress() {
    final ArchiveProgress? unpacking = _unpacking;
    if (unpacking == null) {
      // Оглавление архива читается до первой книги, а на телефоне архив
      // из облака сначала переносится в приложение — это не миг.
      final String? archive = _archiveName;
      return Text(
        archive == null ? 'Открываю архив…' : 'Открываю архив «$archive»…',
      );
    }
    final String? category = unpacking.category;
    return Column(
      key: const Key('sno-archive-progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Распаковываю архив: ${unpacking.number} из ${unpacking.total}'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LinearProgressIndicator(
            value: (unpacking.number - 1) / unpacking.total,
          ),
        ),
        Text(
          category == null ? unpacking.title : '$category · ${unpacking.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Блок «Для экспериментатора»: архивы с книгами (SNO-F-LIT-03).
  List<Widget> _experimenter(ThemeData theme) {
    final bool needsAccess = _phase == ArchiveSearchPhase.needsAccess;
    final String? failure = _searchFailure;
    return <Widget>[
      if (_busy)
        ListTile(
          key: const Key('sno-archive-busy'),
          leading: const Icon(Icons.unarchive_outlined),
          title: const Text('Добавляю архив'),
          subtitle: _progress(),
          trailing: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Архивы с книгами на устройстве',
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
      if (needsAccess)
        Padding(
          key: const Key('sno-archives-access'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Чтобы найти архив с книгами, нужен доступ к файлам. '
                'Приложение ищет только ZIP-архивы с книгами.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('sno-archives-allow'),
                onPressed: _busy ? null : () => unawaited(_allowAndSearch()),
                child: const Text('Разрешить и найти'),
              ),
            ],
          ),
        ),
      for (final FoundArchive archive in _found)
        ListTile(
          // Строка названа архивом, а не местом в списке: нажатие,
          // начатое на одном архиве, не достанется другому, если
          // список за это время вырос или встал в свой порядок.
          key: ValueKey<String>('sno-archive:${archive.path}'),
          leading: const Icon(Icons.folder_zip_outlined),
          title: Text(
            archive.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(describeFoundArchive(archive, _roots)),
          trailing: const Icon(Icons.chevron_right),
          enabled: !_busy && !_sessionOpen,
          onTap: () => unawaited(_addFound(archive)),
        ),
      if (_phase == ArchiveSearchPhase.searching)
        const Padding(
          key: Key('sno-archives-searching'),
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Ищу архивы…'),
            ],
          ),
        ),
      if (failure != null)
        Padding(
          key: const Key('sno-archives-failure'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Поиск прервался: $failure.'),
          ),
        ),
      if (_phase == ArchiveSearchPhase.finished &&
          _found.isEmpty &&
          failure == null)
        const Padding(
          key: Key('sno-archives-empty'),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Архивов с книгами не найдено. Архив из мессенджера '
              'сначала сохраните в «Загрузки».',
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Wrap(
          children: <Widget>[
            if (!needsAccess)
              TextButton.icon(
                key: const Key('sno-archives-refresh'),
                onPressed: _busy ? null : () => unawaited(_search()),
                icon: const Icon(Icons.refresh),
                label: const Text('Искать заново'),
              ),
            TextButton(
              key: const Key('sno-add-archive'),
              onPressed: _busy || _sessionOpen
                  ? null
                  : () => unawaited(_pickArchives()),
              child: const Text('Выбрать вручную…'),
            ),
          ],
        ),
      ),
      ..._referenceState(theme),
    ];
  }

  /// Блок «Для экспериментатора»: эталонное состояние и сброс
  /// (SNO-F-CFG-04).
  ///
  /// Стоит под архивами: сначала литература добавляется, потом к ней
  /// возвращаются. Пока эталона нет, кнопки сброса нет тоже — кнопка,
  /// которой нечего делать, была бы ложью о сборке.
  List<Widget> _referenceState(ThemeData theme) {
    final ReferenceState? reference = _reference;
    final bool? matches = _matches;
    final DateTime? lastReset = _lastReset;
    final String? result = _resetResult;
    return <Widget>[
      const Divider(indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Эталонное состояние', style: theme.textTheme.titleSmall),
        ),
      ),
      if (reference == null)
        const Padding(
          key: Key('sno-reference-none'),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Эталона ещё нет: он запомнится, когда будет добавлен '
              'архив с литературой.',
            ),
          ),
        )
      else
        Padding(
          key: const Key('sno-reference'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(describeReference(reference)),
              if (matches != null)
                Text(
                  matches
                      ? 'Сейчас: совпадает с эталоном'
                      : 'Сейчас: отличается от эталона',
                  key: const Key('sno-reference-status'),
                ),
              const SizedBox(height: 10),
              HoldToConfirmButton(
                key: const Key('sno-reset-hold'),
                label: _resetting
                    ? 'Сбрасываю…'
                    : 'Удерживайте, чтобы сбросить',
                onConfirmed: _busy || _resetting || _starting || _sessionOpen
                    ? null
                    : () => unawaited(_reset()),
              ),
              const SizedBox(height: 8),
              Text(
                _sessionOpen
                    ? 'Сброс недоступен, пока сессия записи не завершена.'
                    : 'Стирает прогресс, цитаты, заметки, закладки и '
                          'настройки. Книги остаются.',
                key: const Key('sno-reset-note'),
                style: theme.textTheme.bodySmall,
              ),
              if (result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(result, key: const Key('sno-reset-result')),
                ),
              if (lastReset != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Последний сброс: ${describeMoment(lastReset)}',
                    key: const Key('sno-reset-last'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  /// Раскладывает по полке архив из найденных.
  ///
  /// Архив читается там, где лежит, по пути: на телефоне доступ к нему
  /// даёт то же разрешение, с которым он найден.
  Future<void> _addFound(FoundArchive archive) async {
    // Пока открыт диалог ручного выбора, второе добавление не
    // начинается: иначе выбранное в диалоге молча пропало бы.
    if (_picking) {
      return;
    }
    await _addArchives(<PickedFile>[
      PickedFile(name: archive.name, path: archive.path),
    ]);
  }

  /// Запись сессии: старт, ход, завершение (SNO-F-REC-01).
  ///
  /// Что здесь стоит, зависит от того, что с записью: «Старт записи»,
  /// пока сессии нет; оставшееся время, пока запись идёт; путь к
  /// завершению сессии, когда она остановлена.
  List<Widget> _recording(ThemeData theme, RecordingSession session) {
    final ParticipantCode? participant = session.participant;
    final Readiness? readiness = _readiness;
    final String ready = readiness == null ? '' : describeReadiness(readiness);
    final String? failure = _startFailure;
    return <Widget>[
      if (participant != null)
        ListTile(
          key: const Key('sno-participant'),
          title: const Text('Участник'),
          subtitle: Text(participant.display),
        ),
      if (session.phase == RecordingPhase.idle) ...<Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilledButton.icon(
            key: const Key('sno-record-start'),
            onPressed: _busy || _resetting || _starting
                ? null
                : () => unawaited(_startRecording(session)),
            icon: const Icon(Icons.fiber_manual_record),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Старт записи · ${session.planned.inMinutes} мин'),
            ),
          ),
        ),
        if (ready.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              ready,
              key: const Key('sno-record-ready'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              failure,
              key: const Key('sno-record-failure'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
      if (session.phase == RecordingPhase.recording)
        ListTile(
          key: const Key('sno-recording'),
          leading: Icon(
            Icons.fiber_manual_record,
            color: theme.colorScheme.error,
          ),
          // Оставшееся время видно только здесь (решение В6): в чтении
          // счёт подгонял бы участника.
          title: ValueListenableBuilder<int>(
            valueListenable: session.ticks,
            builder: (BuildContext context, int tick, Widget? child) {
              final String left = describeRecordingTime(session.remainingMs);
              return Text(
                'Идёт запись · осталось $left',
                key: const Key('sno-recording-left'),
              );
            },
          ),
          subtitle: const Text('Остановить: удерживайте точку в углу экрана'),
        ),
      if (session.phase == RecordingPhase.recording) _blockRow(theme, session),
      if (session.phase == RecordingPhase.stopped)
        ListTile(
          key: const Key('sno-session-finish'),
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Завершить сессию'),
          subtitle: Text(
            '${describeStop(session.state?.stoppedBy)} · '
            '${describeRecordingTime(session.elapsedMs)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openFinish(session),
        ),
    ];
  }

  /// Номер, который экспериментатор выбрал следующему блоку; `null` —
  /// берётся предложенный записью.
  int? _blockNumber;

  /// «Блок №»: экспериментатор отмечает начало и конец блока
  /// тестирования (SNO-F-CFG-03, кадр SNO-SCR-01.1).
  ///
  /// Строка есть, только пока запись идёт. Блок один: пока он открыт,
  /// на его месте — сколько он идёт и «Закончить». Номер предлагается
  /// следующий по порядку; стрелками его можно поправить.
  Widget _blockRow(ThemeData theme, RecordingSession session) {
    final int? running = session.block;
    if (running != null) {
      return ListTile(
        key: const Key('sno-block-running'),
        title: ValueListenableBuilder<int>(
          valueListenable: session.ticks,
          builder: (BuildContext context, int tick, Widget? child) {
            final String passed = describeRecordingTime(session.blockElapsedMs);
            return Text(
              'Блок $running идёт · $passed',
              key: const Key('sno-block-passed'),
            );
          },
        ),
        trailing: FilledButton.tonalIcon(
          key: const Key('sno-block-end'),
          onPressed: () {
            session.endBlock();
            // Следующему блоку номер предложит запись.
            setState(() => _blockNumber = null);
          },
          icon: const Icon(Icons.stop),
          label: const Text('Закончить'),
        ),
      );
    }
    final int number = _blockNumber ?? session.nextBlock;
    return ListTile(
      key: const Key('sno-block'),
      title: Row(
        children: <Widget>[
          const Flexible(
            child: Text(
              'Блок №',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
          IconButton(
            key: const Key('sno-block-less'),
            icon: const Icon(Icons.remove),
            tooltip: 'Номер меньше',
            visualDensity: VisualDensity.compact,
            onPressed: number > 1
                ? () => setState(() => _blockNumber = number - 1)
                : null,
          ),
          Text('$number', key: const Key('sno-block-number')),
          IconButton(
            key: const Key('sno-block-more'),
            icon: const Icon(Icons.add),
            tooltip: 'Номер больше',
            visualDensity: VisualDensity.compact,
            onPressed: number < 99
                ? () => setState(() => _blockNumber = number + 1)
                : null,
          ),
        ],
      ),
      trailing: FilledButton.tonalIcon(
        key: const Key('sno-block-start'),
        onPressed: () => session.startBlock(number),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Начать'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String device = deviceCodeOf(widget.services.data.clock.nodeId);
    final RecordingSession? session = _session;
    final DeviceRecords? records = _records;
    return Scaffold(
      appBar: AppBar(title: const Text('Тестирование')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // На широком окне ПК строки во всю ширину читать неудобно.
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: <Widget>[
              ListTile(
                key: const Key('sno-device'),
                title: const Text('Устройство'),
                subtitle: Text(device),
              ),
              if (session != null) ..._recording(theme, session),
              // SNO-F-REC-07: записи видны, только пока сессии нет —
              // участнику чужие записи не показываются. Пока идёт
              // старт записи, строки тоже нет: список, открытый в этот
              // миг, остался бы поверх начавшейся записи.
              if (records != null && !_sessionOpen && !_starting)
                ListTile(
                  key: const Key('sno-records'),
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Записи на устройстве'),
                  subtitle: Text(
                    records.loaded
                        ? describeRecordsCount(
                            records.entries,
                            shares: records.shares,
                          )
                        : '…',
                    key: const Key('sno-records-count'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openRecords(records),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  session == null
                      ? 'Запись, тест и записи появятся здесь следующими '
                            'сборками.'
                      : records == null
                      ? 'Тест и записи на устройстве появятся здесь '
                            'следующими сборками.'
                      : 'Тест появится здесь следующей сборкой.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Divider(),
              ExpansionTile(
                key: const Key('sno-experimenter'),
                title: const Text('Для экспериментатора'),
                onExpansionChanged: _expansionChanged,
                children: _experimenter(theme),
              ),
              const Divider(),
              ListTile(
                key: const Key('sno-about'),
                title: const Text('О ветви'),
                subtitle: Text(
                  buildLabelFor(
                    version: appVersion,
                    commit: appCommit,
                    flags: widget.flags,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
