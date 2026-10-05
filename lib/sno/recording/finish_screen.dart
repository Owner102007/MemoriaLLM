import 'dart:async';

import 'package:flutter/material.dart';

import '../hold_button.dart';
import 'journal_check.dart';
import 'records.dart';
import 'records_screen.dart';
import 'session.dart';
import 'summary.dart';

/// Чем кончилась запись — заголовком экрана завершения и плашки.
String describeStop(StopReason? by) {
  return switch (by) {
    StopReason.auto => 'Запись завершена',
    StopReason.crash => 'Запись прервана',
    StopReason.experimenter || null => 'Запись остановлена',
  };
}

/// Открывает экран завершения сессии поверх всего.
///
/// Экран один: пока он открыт, второй не открывается, а плашка,
/// ведущая на него, не показывается ([RecordingSession.finishOpen]).
/// [records] — записи на устройстве: с ними завершённая сессия тут же
/// упаковывается в архив (SNO-F-REC-05).
Future<void> openSessionFinish(
  NavigatorState navigator,
  RecordingSession session, {
  DeviceRecords? records,
}) async {
  if (session.finishOpen.value || session.phase != RecordingPhase.stopped) {
    return;
  }
  session.setFinishOpen(true);
  try {
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return SessionFinishScreen(session: session, records: records);
        },
      ),
    );
  } finally {
    session.setFinishOpen(false);
  }
}

/// Завершение сессии (SNO-SCR-08, SNO-F-REC-01, SNO-F-CFG-05).
///
/// Всё, что происходит между остановкой записи и снятым замком полки.
/// Экран ведёт экспериментатор: код участника стоит крупно — его
/// сверяют с бланком, — а сессия завершается удержанием кнопки. Тест
/// нагрузки встанет сюда же вместе со своей функцией.
///
/// **До завершения журнал перечитан с диска** (SNO-F-REC-13): под
/// числом событий стоит «Запись цела: … пропусков нет» или чего в ней
/// не хватает — экспериментатор узнаёт о неполной записи, пока
/// участник ещё рядом. Завершению это не мешает.
///
/// **После завершения запись упаковывается в архив** (SNO-F-REC-05,
/// кадр SNO-SCR-08.3), и экран не закрывается: на нём имя архива,
/// длительность, число событий и размер — и выход для него
/// (SNO-F-REC-06): «Поделиться» на телефоне, «Сохранить архив как…» и
/// «Открыть папку» на ПК. Упаковка идёт именно здесь, а не в миг
/// остановки записи: между ними позже встанет тест нагрузки, и его
/// ответы должны попасть в тот же архив. Архив не собрался — запись
/// цела и лежит папкой; об этом сказано, упаковка повторится при
/// следующем запуске. На телефоне под архивом сказано, легла ли его
/// вторая копия в «Загрузки» (SNO-F-REC-13).
class SessionFinishScreen extends StatefulWidget {
  /// Создаёт экран.
  ///
  /// Без [records] сессия завершается, и экран закрывается сам: так
  /// было до архива, и так остаётся там, где записей на устройстве
  /// нет.
  const SessionFinishScreen({required this.session, this.records, super.key});

  /// Сессия записи.
  final RecordingSession session;

  /// Записи на устройстве; `null` — упаковывать некому.
  final DeviceRecords? records;

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

  /// Строки о блоках и об отлучках; `null` — блоков не отмечали,
  /// участник не уходил (SNO-F-CFG-03, SNO-F-REC-10).
  String? _blocks;
  String? _away;

  /// Итог самопроверки журнала словами и цел ли он (SNO-F-REC-13);
  /// `null` — журнал ещё не перечитан.
  String? _check;
  bool _intact = true;

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

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    widget.session.checked.addListener(_changed);
    _remember();
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
    _blocks = describeBlocks(state.blocks);
    _away = describeAway(state.away);
    if (session.checked.value) {
      final JournalCheck? check = session.check;
      _check = describeJournalCheck(check);
      _intact = check?.intact ?? false;
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    widget.session.checked.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(_remember);
    }
  }

  Future<void> _finish() async {
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
      await session.finish();
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

  /// Экран до завершения сессии: итог записи и код для бланка
  /// (SNO-SCR-08.1).
  List<Widget> _summary(ThemeData theme) {
    final bool open = widget.session.phase == RecordingPhase.stopped;
    final String? blocks = _blocks;
    final String? away = _away;
    final String? check = _check;
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
      const SizedBox(height: 28),
      Text('Записано событий: $_events', key: const Key('sno-finish-events')),
      if (check != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            check,
            key: const Key('sno-finish-check'),
            style: _intact ? null : TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (blocks != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(blocks, key: const Key('sno-finish-blocks')),
        ),
      if (away != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(away, key: const Key('sno-finish-away')),
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
      const SizedBox(height: 28),
      HoldToConfirmButton(
        key: const Key('sno-finish-hold'),
        label: _closing ? 'Завершаю…' : 'Удерживайте, чтобы завершить сессию',
        onConfirmed: _closing || !open ? null : () => unawaited(_finish()),
      ),
      const SizedBox(height: 8),
      Text(
        widget.records == null
            ? 'После завершения полка открывается, а код участника '
                  'забывается: следующая запись получит новый.'
            : 'После завершения полка открывается, код участника '
                  'забывается, а запись собирается в архив.',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Завершение сессии')),
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
    );
  }
}
