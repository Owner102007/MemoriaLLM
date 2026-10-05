import 'dart:async';

import 'package:flutter/material.dart';

import 'records.dart';

/// Открывает «Записи на устройстве» поверх всего.
Future<void> openDeviceRecords(
  NavigatorState navigator,
  DeviceRecords records,
) {
  return navigator.push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) {
        return DeviceRecordsScreen(records: records);
      },
    ),
  );
}

/// Спрашивает, отдавать ли окну «Поделиться» большой архив
/// (SNO-F-REC-06); без предупреждения отвечает «да» сразу.
Future<bool> confirmLargeShare(
  BuildContext context,
  List<DeviceRecord> records,
) async {
  final String? warning = describeLargeShare(records);
  if (warning == null) {
    return true;
  }
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Большой архив'),
        content: Text(warning),
        actions: <Widget>[
          TextButton(
            key: const Key('sno-share-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('sno-share-anyway'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Всё равно поделиться'),
          ),
        ],
      );
    },
  );
  return go ?? false;
}

/// Записи на устройстве (SNO-SCR-03, SNO-F-REC-07, SNO-F-REC-06).
///
/// Все записи сессий, что лежат на устройстве, от новых к старым:
/// отдать экспериментатору, увидеть, что уже отдано, удалить отданное.
/// Экран ведёт экспериментатор; во время записи сюда не попасть.
///
/// На телефоне запись «отправляют» — системным окном «Поделиться»,
/// одну или все неотправленные разом; отправленной она считается,
/// когда в окне выбрано приложение (SNO-F-REC-14), а вторая её копия
/// сама ложится в «Загрузки» (SNO-F-REC-13) — отметок у записи две.
/// На ПК «сохраняют копию» в выбранную папку и открывают папку записей
/// в «Проводнике».
///
/// Удаление — с подтверждением; запись, которая ещё никуда не ушла,
/// удаляется только вторым подтверждением.
class DeviceRecordsScreen extends StatefulWidget {
  /// Создаёт экран.
  const DeviceRecordsScreen({required this.records, super.key});

  /// Записи на устройстве.
  final DeviceRecords records;

  @override
  State<DeviceRecordsScreen> createState() => _DeviceRecordsScreenState();
}

class _DeviceRecordsScreenState extends State<DeviceRecordsScreen> {
  /// Идёт ли действие над записями: второе, пока идёт первое, не
  /// начинается.
  bool _busy = false;

  /// Чем кончилось последнее действие — словами.
  String? _notice;

  @override
  void initState() {
    super.initState();
    widget.records.addListener(_changed);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(DeviceRecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records)) {
      oldWidget.records.removeListener(_changed);
      widget.records.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.records.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.records.refresh();
    } on Object {
      // Папка записей не прочиталась: список остаётся каким был.
    }
  }

  /// Выполняет действие [body] и говорит, чем оно кончилось.
  Future<void> _act(Future<String?> Function() body) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
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
    setState(() {
      _busy = false;
      _notice = told;
    });
  }

  Future<void> _share(List<DeviceRecord> records) async {
    if (!await confirmLargeShare(context, records) || !mounted) {
      return;
    }
    await _act(() async {
      return describeShared(await widget.records.share(records));
    });
  }

  Future<void> _save(DeviceRecord record) {
    return _act(() async {
      return describeCopied(await widget.records.saveCopy(record));
    });
  }

  Future<void> _reveal() {
    return _act(() async {
      return await widget.records.reveal()
          ? null
          : 'Папка записей не открылась.';
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: <Widget>[
            TextButton(
              key: const Key('sno-record-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('sno-record-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        );
      },
    );
    return yes ?? false;
  }

  /// Удаляет запись: одно подтверждение у той, что уже ушла с
  /// устройства, два — у остальных (SNO-F-REC-07).
  Future<void> _delete(DeviceRecord record) async {
    if (_busy) {
      return;
    }
    // SNO-F-REC-13: у записи, которая не отправлена, но лежит копией в
    // «Загрузках» телефона, подтверждение одно — и в нём сказано, что
    // от неё останется.
    final bool first = await _confirm(
      title: 'Удалить запись с устройства?',
      body: widget.records.backs && record.keepsOnlyCopy
          ? '${record.fileName}\n\n'
                'Запись не отправлена. Её копия останется в «Загрузках» '
                'телефона — в папке $kBackupFolder.'
          : record.fileName,
      action: 'Удалить',
    );
    if (!first || !mounted) {
      return;
    }
    if (!record.taken) {
      final bool second = await _confirm(
        title: widget.records.shares
            ? 'Эта запись никуда не отправлена'
            : 'Копии этой записи нет',
        body: 'Удалить безвозвратно? Восстановить её будет нечем.',
        action: 'Удалить безвозвратно',
      );
      if (!second || !mounted) {
        return;
      }
    }
    await _act(() async {
      return await widget.records.delete(record)
          ? 'Запись удалена.'
          : 'Запись не удалилась.';
    });
  }

  Widget _row(ThemeData theme, DeviceRecord record) {
    final DeviceRecords records = widget.records;
    return Padding(
      key: Key('sno-record-${record.rowId}'),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(record.name, style: theme.textTheme.titleSmall),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  describeRecord(
                    record,
                    shares: records.shares,
                    backs: records.backs,
                  ),
                  key: Key('sno-record-about-${record.rowId}'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (records.shares && record.packed)
                IconButton(
                  key: Key('sno-record-share-${record.rowId}'),
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Поделиться',
                  onPressed: _busy
                      ? null
                      : () => unawaited(_share(<DeviceRecord>[record])),
                ),
              if (records.saves && record.packed)
                TextButton(
                  key: Key('sno-record-save-${record.rowId}'),
                  onPressed: _busy ? null : () => unawaited(_save(record)),
                  child: const Text('Сохранить как…'),
                ),
              IconButton(
                key: Key('sno-record-delete-${record.rowId}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить',
                onPressed: _busy ? null : () => unawaited(_delete(record)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DeviceRecords records = widget.records;
    final List<DeviceRecord> entries = records.entries;
    final List<DeviceRecord> pending = unshared(entries);
    final String? notice = _notice;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Записи на устройстве'),
        actions: <Widget>[
          if (records.saves)
            TextButton.icon(
              key: const Key('sno-records-reveal'),
              onPressed: _busy ? null : () => unawaited(_reveal()),
              icon: const Icon(Icons.folder_open),
              label: const Text('Открыть папку'),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // На широком окне ПК строки во всю ширину читать неудобно.
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              if (!records.loaded)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Читаю записи…'),
                )
              else if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Записей нет. Старт — в «Тестировании».',
                    key: Key('sno-records-empty'),
                  ),
                ),
              if (records.shares && pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: FilledButton.tonalIcon(
                    key: const Key('sno-records-share-all'),
                    onPressed: _busy ? null : () => unawaited(_share(pending)),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(
                      'Поделиться неотправленными (${pending.length})',
                    ),
                  ),
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(notice, key: const Key('sno-records-notice')),
                ),
              for (final DeviceRecord record in entries) _row(theme, record),
            ],
          ),
        ),
      ),
    );
  }
}
