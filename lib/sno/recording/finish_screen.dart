import 'dart:async';

import 'package:flutter/material.dart';

import '../clt/load_test.dart';
import '../clt/results.dart';
import '../clt/test_screens.dart';
import '../hold_button.dart';
import 'journal_check.dart';
import 'records.dart';
import 'records_screen.dart';
import 'session.dart';
import 'summary.dart';

/// Чем кончилась запись — заголовком экрана завершения.
String describeStop(StopReason? by) {
  return switch (by) {
    StopReason.auto => 'Запись завершена',
    StopReason.crash => 'Запись прервана',
    StopReason.experimenter || null => 'Запись остановлена',
  };
}

/// Имя маршрута экрана завершения сессии в навигаторе приложения.
const String kSessionFinishRoute = 'sno-session-finish';

/// Открывает экран завершения сессии поверх всего.
///
/// Экран один: пока он открыт, второй не открывается
/// ([RecordingSession.finishOpen]). Открывает его слой записи — сам и
/// сразу, как только запись остановилась (SNO-F-REC-16): от остановки
/// до завершения сессии в приложении виден только он. Поэтому маршрут
/// встаёт без перехода — под уезжающей страницей была бы видна полка.
/// [records] — записи на устройстве: с ними завершённая сессия тут же
/// упаковывается в архив (SNO-F-REC-05). [test] — тест нагрузки: экран
/// ведёт к нему до завершения сессии (SNO-F-CLT-01).
Future<void> openSessionFinish(
  NavigatorState navigator,
  RecordingSession session, {
  DeviceRecords? records,
  LoadTest? test,
}) async {
  if (session.finishOpen.value || session.phase != RecordingPhase.stopped) {
    return;
  }
  session.setFinishOpen(true);
  // Отметку снимает только тот экран, который её поставил: снятый
  // экран, чей уход досчитался позже, не вправе объявить закрытым
  // экран, вставший после него.
  final int mine = ++_finishOpens;
  void gone() {
    if (_finishOpens == mine) {
      session.setFinishOpen(false);
    }
  }

  try {
    await navigator.push(
      _FinishRoute(
        onGone: gone,
        builder: (BuildContext context) {
          return SessionFinishScreen(
            session: session,
            records: records,
            test: test,
          );
        },
      ),
    );
  } finally {
    gone();
  }
}

/// Сколько раз экран завершения открывали: номер открытия — его право
/// снять отметку «экран открыт».
int _finishOpens = 0;

/// Маршрут экрана завершения: встаёт и уходит без перехода.
class _FinishRoute extends MaterialPageRoute<void> {
  _FinishRoute({required super.builder, required this.onGone})
    : super(settings: const RouteSettings(name: kSessionFinishRoute));

  /// Маршрута больше нет, каким бы путём его ни сняли: снятый не
  /// `pop`, а `removeRoute` своего ожидающего не завершает.
  final void Function() onGone;

  @override
  void dispose() {
    onGone();
    super.dispose();
  }

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

/// Завершение сессии (SNO-SCR-08, SNO-F-REC-01, SNO-F-CFG-05).
///
/// Всё, что происходит между остановкой записи и снятым замком полки.
///
/// **Литература закрыта** (SNO-F-REC-16, кадр SNO-SCR-08.4): экран
/// встаёт сам, как только запись остановилась, и уйти с него нельзя —
/// стрелки «назад» нет, системное «назад» и `Esc` не действуют, а под
/// ним нет ни открытой книги, ни другого экрана. Сверху — то, что
/// нужно участнику: код для бланка и два шага словами; итог записи для
/// организатора — ниже и мельче. Экран не держит устройство
/// включённым: письменная часть длится дольше, чем живёт экран, и
/// после разблокировки он тот же.
///
/// **Сессия завершается только после теста нагрузки** (SNO-F-CLT-05):
/// пока итоговая часть не пройдена целиком, кнопки завершения нет — на
/// её месте сказано, что осталось. Тест открывает организатор паролем
/// (SNO-F-CLT-01); начатую и не оконченную часть экран предлагает
/// продолжить. Когда тест пройти нельзя — участник ушёл, сценарий не
/// принят, — у организатора есть выход «Завершить без теста»: по тому
/// же паролю, удержанием и с подтверждением (решение АЖ4); запись тогда
/// помечена «без теста нагрузки». В сборке без пароля теста теста нет
/// вовсе, и сессия завершается сразу.
///
/// **До завершения журнал перечитан с диска** (SNO-F-REC-13): под
/// числом событий стоит «Запись цела: … пропусков нет» или чего в ней
/// не хватает — организатор узнаёт о неполной записи, пока участник
/// ещё рядом. Завершению это не мешает.
///
/// **После завершения запись упаковывается в архив** (SNO-F-REC-05,
/// кадр SNO-SCR-08.3), и экран не закрывается: на нём имя архива,
/// длительность, число событий и размер — и выход для него
/// (SNO-F-REC-06): «Поделиться» на телефоне, «Сохранить архив как…» и
/// «Открыть папку» на ПК. Упаковка идёт именно здесь, а не в миг
/// остановки записи: между ними стоит тест нагрузки, и его ответы
/// обязаны попасть в тот же архив. Архив не собрался — запись цела и
/// лежит папкой; об этом сказано, упаковка повторится при следующем
/// запуске. На телефоне под архивом сказано, легла ли его вторая копия
/// в «Загрузки» (SNO-F-REC-13).
class SessionFinishScreen extends StatefulWidget {
  /// Создаёт экран.
  ///
  /// Без [records] сессия завершается, и экран закрывается сам: так
  /// было до архива, и так остаётся там, где записей на устройстве
  /// нет. Без [test] теста нагрузки на экране нет.
  const SessionFinishScreen({
    required this.session,
    this.records,
    this.test,
    super.key,
  });

  /// Сессия записи.
  final RecordingSession session;

  /// Записи на устройстве; `null` — упаковывать некому.
  final DeviceRecords? records;

  /// Тест нагрузки; `null` — теста в сборке нет.
  final LoadTest? test;

  @override
  State<SessionFinishScreen> createState() => _SessionFinishScreenState();
}

class _SessionFinishScreenState extends State<SessionFinishScreen> {
  /// Идёт ли завершение.
  bool _closing = false;

  /// Что показано на экране. Запоминается, пока сессия есть: когда её
  /// завершили, экран ещё уходит с глаз и обязан показывать то же, а не
  /// пустой код и нули.
  String _title = '';
  String _code = '';
  int _events = 0;
  bool _failed = false;

  /// Строка об отлучках; `null` — участник не уходил (SNO-F-REC-10).
  String? _away;

  /// Экран, с которого пришли: запись знает, где участник.
  late final String _cameFrom;

  /// Итог самопроверки журнала словами и цел ли он (SNO-F-REC-13);
  /// `null` — журнал ещё не перечитан.
  String? _check;
  bool _intact = true;

  /// То же о потоке сырого ввода (SNO-F-REC-11); `null` — потока в
  /// записи нет или он ещё не перечитан.
  String? _inputCheck;
  bool _inputIntact = true;

  /// Завершена ли сессия: экран показывает архив, а не код.
  bool _finished = false;

  /// Идёт ли упаковка.
  bool _packing = false;

  /// Упакованная запись; `null` — упаковка идёт или записи не нашлось.
  DeviceRecord? _record;

  /// Идёт ли действие над архивом: второе, пока идёт первое, не
  /// начинается.
  bool _acting = false;

  /// Чем кончилось последнее действие над архивом — словами.
  String? _notice;

  /// Открыт ли экран теста нагрузки: второй, пока открыт первый, не
  /// открывается.
  bool _testing = false;

  /// Ушёл ли экран сам — сессию завершили мимо него: второй раз его не
  /// закрывают.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _cameFrom = widget.session.context.screen;
    widget.session.screen('finish');
    widget.session.addListener(_changed);
    widget.session.checked.addListener(_changed);
    widget.test?.addListener(_changed);
    _remember();
    unawaited(_readTest());
  }

  /// Сценарий и уже данные ответы теста — с диска (SNO-F-CLT-03):
  /// после перезапуска приложения в памяти их нет.
  Future<void> _readTest() async {
    final LoadTest? test = widget.test;
    if (test == null) {
      return;
    }
    await test.load();
    await test.refresh();
  }

  void _remember() {
    final RecordingSession session = widget.session;
    final SessionState? state = session.state;
    if (state == null) {
      return;
    }
    _title =
        '${describeStop(state.stoppedBy)} · '
        '${describeRecordingTime(session.elapsedMs)}';
    _code = state.participant.display;
    _events = session.events;
    _failed = session.writeFailed;
    _away = describeAway(state.away);
    if (session.checked.value) {
      final JournalCheck? check = session.check;
      _check = describeJournalCheck(check);
      _intact = check?.intact ?? false;
      final JournalCheck? input = session.inputCheck;
      _inputCheck = describeInputCheck(input);
      _inputIntact = input?.intact ?? true;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    widget.session.checked.removeListener(_changed);
    widget.test?.removeListener(_changed);
    // Следующая запись начнётся с экрана, на котором стоит приложение,
    // а не с экрана завершения прошлой.
    widget.session.screen(_cameFrom);
    super.dispose();
  }

  /// Открывает тест нагрузки: пароль организатора, если замок закрыт,
  /// вступление и пункты.
  Future<void> _openTest(LoadTest test) async {
    if (_testing) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _testing = true);
    try {
      await openFinalTest(navigator, test);
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  /// Выход организатора, когда тест пройти нельзя (SNO-F-CLT-05,
  /// решение АЖ4): пароль, удержание, подтверждение — и сессия
  /// завершается без теста.
  Future<void> _skipTest(LoadTest test) async {
    if (_testing || _closing) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _testing = true);
    bool confirmed = false;
    try {
      confirmed = await openTestSkip(navigator, test);
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
    if (confirmed && mounted) {
      await _finish(withoutTest: true);
    }
  }

  /// Ждёт ли завершение сессии теста нагрузки (SNO-F-CLT-05).
  ///
  /// Ждёт, пока тест в сборке есть и его итоговая часть не пройдена
  /// целиком — в том числе пока сценарий не загружен и когда он не
  /// принят: тогда остаётся только выход организатора. Не ждёт в
  /// сборке без теста и у сценария без итоговой части: проходить там
  /// нечего.
  bool get _waitsTest {
    final LoadTest? test = widget.test;
    if (test == null) {
      return false;
    }
    if (!test.loaded || test.problem != null) {
      return true;
    }
    return test.finalItems > 0 && !test.finalDone;
  }

  /// Тест нагрузки на экране завершения (SNO-F-CLT-01, SNO-F-CLT-05):
  /// что уже сделано и какой шаг следующий.
  List<Widget> _test(ThemeData theme, {required bool open}) {
    final LoadTest? test = widget.test;
    if (test == null || !test.loaded) {
      return const <Widget>[];
    }
    final String? problem = test.problem;
    if (problem != null) {
      return <Widget>[
        const SizedBox(height: 20),
        Text(
          'Тест нагрузки недоступен: $problem.',
          key: const Key('sno-finish-test-problem'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ];
    }
    final CltResult? begun = test.finalResult;
    final int items = test.finalItems;
    if (items <= 0) {
      return const <Widget>[];
    }
    final bool busy = !open || _closing || _testing;
    if (test.finalDone) {
      return <Widget>[
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Icon(Icons.check, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Тест пройден: $items из $items',
                key: const Key('sno-finish-test-done'),
              ),
            ),
          ],
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: 20),
      FilledButton.tonalIcon(
        key: const Key('sno-finish-test'),
        onPressed: busy ? null : () => unawaited(_openTest(test)),
        icon: Icon(
          test.unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
        ),
        label: Text(
          begun == null
              ? 'Cognitive load test'
              : 'Продолжить тест · ${begun.answers.length} из $items',
        ),
      ),
      const SizedBox(height: 4),
      Text('Открывает организатор', style: theme.textTheme.bodySmall),
    ];
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    setState(_remember);
    // Сессию завершили мимо этого экрана: держать на нём некого, а уйти
    // с него иначе нельзя — он уходит сам.
    if (_gone ||
        _closing ||
        _finished ||
        widget.session.phase != RecordingPhase.idle) {
      return;
    }
    _gone = true;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    // Единственный экран навигатора не снимают: под ним ничего нет.
    if (route == null || route.isFirst) {
      return;
    }
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _finish({bool withoutTest = false}) async {
    if (_closing) {
      return;
    }
    // Имя папки и записи — до завершения: после него сессия имя
    // забывает, а экран могут успеть закрыть.
    final RecordingSession session = widget.session;
    final DeviceRecords? records = widget.records;
    final String? folder = session.state?.folder;
    setState(() => _closing = true);
    try {
      await session.finish(withoutTest: withoutTest);
    } on Object {
      // Завершить не удалось: экран остаётся, кнопка снова доступна.
    }
    // SNO-F-REC-05: сессия завершена — запись упаковывается в архив.
    // Упаковка начинается и тогда, когда экран уже закрыли: иначе
    // запись осталась бы папкой до следующего запуска приложения.
    final bool done = session.phase == RecordingPhase.idle;
    final Future<DeviceRecord?>? packing =
        done && records != null && folder != null
        ? _pack(records, folder)
        : null;
    if (!mounted) {
      return;
    }
    setState(() => _closing = false);
    if (!done) {
      return;
    }
    if (packing == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _finished = true;
      _packing = true;
    });
    final DeviceRecord? record = await packing;
    if (!mounted) {
      return;
    }
    setState(() {
      _packing = false;
      _record = record;
    });
  }

  /// Упаковывает запись; не собралась — `null`: папка записи цела,
  /// упаковка повторится при следующем запуске.
  static Future<DeviceRecord?> _pack(
    DeviceRecords records,
    String folder,
  ) async {
    try {
      return await records.pack(folder);
    } on Object {
      return null;
    }
  }

  /// Выполняет действие над архивом и говорит, чем оно кончилось.
  Future<void> _act(Future<String?> Function() body) async {
    if (_acting) {
      return;
    }
    setState(() {
      _acting = true;
      _notice = null;
    });
    String? told;
    try {
      told = await body();
    } on Object {
      told = 'Не получилось: диск не ответил.';
    }
    if (!mounted) {
      return;
    }
    // Отметка «отправлена» или «копия есть» — уже в списке записей.
    final DeviceRecord? known = _record;
    DeviceRecord? fresh;
    if (known != null) {
      for (final DeviceRecord entry
          in widget.records?.entries ?? const <DeviceRecord>[]) {
        // Строку узнают по [DeviceRecord.rowId]: неубранная папка
        // записи носит то же имя, что её архив.
        if (entry.rowId == known.rowId) {
          fresh = entry;
        }
      }
    }
    setState(() {
      _acting = false;
      _notice = told;
      _record = fresh ?? known;
    });
  }

  Future<void> _share(DeviceRecords records, DeviceRecord record) async {
    final List<DeviceRecord> one = <DeviceRecord>[record];
    if (!await confirmLargeShare(context, one) || !mounted) {
      return;
    }
    await _act(() async => describeShared(await records.share(one)));
  }

  /// Экран после завершения сессии: архив и выход для него
  /// (SNO-SCR-08.3).
  List<Widget> _archive(ThemeData theme) {
    final DeviceRecords? records = widget.records;
    final DeviceRecord? record = _record;
    final List<Widget> about;
    if (_packing) {
      about = const <Widget>[
        Text('Собираю архив…', key: Key('sno-finish-packing')),
      ];
    } else if (records == null || record == null || !record.packed) {
      about = <Widget>[
        Text(
          'Архив не собран: запись цела и лежит папкой, упаковка '
          'повторится при следующем запуске.',
          key: const Key('sno-finish-unpacked'),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ];
    } else {
      about = _ready(theme, records, record);
    }
    return <Widget>[
      Text(
        'Сессия завершена',
        key: const Key('sno-finish-done'),
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 28),
      ...about,
      const SizedBox(height: 20),
      OutlinedButton(
        key: const Key('sno-finish-close'),
        onPressed: _packing ? null : () => Navigator.of(context).pop(),
        child: const Text('Готово'),
      ),
    ];
  }

  /// Готовый архив: имя, что в нём, и куда его отдать (SNO-F-REC-06).
  List<Widget> _ready(
    ThemeData theme,
    DeviceRecords records,
    DeviceRecord record,
  ) {
    final String? notice = _notice;
    final String? backup = describeBackup(
      record,
      backs: records.backs,
      shares: records.shares,
    );
    return <Widget>[
      Text('Архив записи готов', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(record.fileName, key: const Key('sno-finish-archive')),
      const SizedBox(height: 4),
      Text(
        describeArchive(record),
        key: const Key('sno-finish-archive-about'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 4),
      Text(
        'Архив лежит в «Записях на устройстве».',
        style: theme.textTheme.bodySmall,
      ),
      if (backup != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            backup,
            key: const Key('sno-finish-backup'),
            style: record.copiedAt != null
                ? theme.textTheme.bodySmall
                : theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
          ),
        ),
      const SizedBox(height: 20),
      if (records.shares)
        FilledButton.icon(
          key: const Key('sno-finish-share'),
          onPressed: _acting ? null : () => unawaited(_share(records, record)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Поделиться'),
        ),
      if (records.saves) ...<Widget>[
        FilledButton.icon(
          key: const Key('sno-finish-save'),
          onPressed: _acting ? null : () => unawaited(_save(records, record)),
          icon: const Icon(Icons.save_alt),
          label: const Text('Сохранить архив как…'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('sno-finish-reveal'),
          onPressed: _acting ? null : () => unawaited(_reveal(records, record)),
          icon: const Icon(Icons.folder_open),
          label: const Text('Открыть папку'),
        ),
      ],
      if (notice != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(notice, key: const Key('sno-finish-notice')),
        ),
    ];
  }

  Future<void> _save(DeviceRecords records, DeviceRecord record) {
    return _act(() async {
      return describeCopied(await records.saveCopy(record));
    });
  }

  Future<void> _reveal(DeviceRecords records, DeviceRecord record) {
    return _act(() async {
      return await records.reveal(record)
          ? null
          : 'Папка записей не открылась.';
    });
  }

  /// Что участнику делать дальше — словами (SNO-F-REC-16).
  List<Widget> _steps({required bool tested}) {
    final List<String> steps = <String>[
      'Сообщите организатору, что закончили, — получите бланк.',
      if (tested)
        'После письменной части позовите организатора снова.'
      else
        'После письменной части организатор завершит сессию.',
    ];
    return <Widget>[
      for (int i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${i + 1}. ${steps[i]}',
            key: Key('sno-finish-step-${i + 1}'),
          ),
        ),
    ];
  }

  /// Итог записи для организатора: мелко и ниже того, что нужно
  /// участнику.
  List<Widget> _recordLines(ThemeData theme) {
    final TextStyle? small = theme.textTheme.bodySmall;
    final TextStyle? wrong = small?.copyWith(color: theme.colorScheme.error);
    final String? away = _away;
    final String? check = _check;
    final String? inputCheck = _inputCheck;
    return <Widget>[
      Text(
        'Записано событий: $_events',
        key: const Key('sno-finish-events'),
        style: small,
      ),
      if (check != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            check,
            key: const Key('sno-finish-check'),
            style: _intact ? small : wrong,
          ),
        ),
      if (inputCheck != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            inputCheck,
            key: const Key('sno-finish-input'),
            style: _inputIntact ? small : wrong,
          ),
        ),
      if (away != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(away, key: const Key('sno-finish-away'), style: small),
        ),
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Часть журнала не записалась на диск: проверьте '
            'свободное место.',
            key: const Key('sno-finish-failed'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
    ];
  }

  /// Экран до завершения сессии: код для бланка, что делать дальше,
  /// тест нагрузки и завершение (SNO-SCR-08.1, SNO-SCR-08.4).
  List<Widget> _summary(ThemeData theme) {
    final bool open = widget.session.phase == RecordingPhase.stopped;
    final LoadTest? test = widget.test;
    final bool waits = _waitsTest;
    final CltResult? begun = test?.finalResult;
    final int items = test?.finalItems ?? 0;
    return <Widget>[
      Text(
        _title,
        key: const Key('sno-finish-title'),
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 28),
      Text('Код участника', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          _code,
          key: const Key('sno-finish-code'),
          style: theme.textTheme.displayMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Text('Впишите код в бланк'),
      if (waits || test == null) ...<Widget>[
        const SizedBox(height: 16),
        ..._steps(tested: test != null),
      ],
      ..._test(theme, open: open),
      const SizedBox(height: 28),
      if (waits)
        // SNO-F-CLT-05: кнопки завершения нет, пока тест не пройден.
        Text(
          begun == null || items <= 0
              ? 'Сессия завершится после теста нагрузки.'
              : 'Тест начат: ${begun.answers.length} из $items. Сессия '
                    'завершится после него.',
          key: const Key('sno-finish-waits'),
        )
      else ...<Widget>[
        HoldToConfirmButton(
          key: const Key('sno-finish-hold'),
          label: _closing ? 'Завершаю…' : 'Удерживайте, чтобы завершить сессию',
          onConfirmed: _closing || _testing || !open
              ? null
              : () => unawaited(_finish()),
        ),
        const SizedBox(height: 8),
        Text(
          widget.records == null
              ? 'После завершения полка открывается, а код участника '
                    'забывается: следующая запись получит новый.'
              : (test == null
                    ? 'После завершения полка открывается, код участника '
                          'забывается, а запись собирается в архив.'
                    : 'Запись и ответы теста лягут в один архив.'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 28),
      ..._recordLines(theme),
      if (waits && test != null && test.loaded) ...<Widget>[
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('sno-finish-skip'),
            onPressed: !open || _closing || _testing
                ? null
                : () => unawaited(_skipTest(test)),
            child: Text(_closing ? 'Завершаю…' : 'Тест пройти нельзя'),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // SNO-F-REC-16: пока сессия не завершена, с экрана не уйти — ни
    // стрелкой, ни системным «назад». Архив готов или не собрался —
    // «Готово» и «назад» возвращают к обычному приложению.
    return PopScope<Object?>(
      canPop: _finished && !_packing,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Завершение сессии'),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: _finished ? _archive(theme) : _summary(theme),
            ),
          ),
        ),
      ),
    );
  }
}
