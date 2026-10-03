import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/reading/page_turning.dart';
import '../../domain/settings/app_settings.dart';

/// Настройки «Чтение по умолчанию».
///
/// Пока здесь только скорость показа страницы (F-READ-02): показывать ли
/// страницу сразу, грубой картинкой, и сколько соседних страниц держать
/// наготове. Мастер-настройки чтения, автофильтр и подсказка о зонах
/// придут сюда же своими шагами.
///
/// Обе настройки принадлежат устройству и не синхронизируются: сколько
/// памяти не жалко и мешает ли ступенька «грубо → резко», на телефоне и
/// на ПК решается по-разному.
class ReadingDefaultsScreen extends StatefulWidget {
  /// Создаёт экран.
  const ReadingDefaultsScreen({required this.settings, super.key});

  /// Хранилище настроек устройства.
  final AppSettingsRepository settings;

  @override
  State<ReadingDefaultsScreen> createState() => _ReadingDefaultsScreenState();
}

class _ReadingDefaultsScreenState extends State<ReadingDefaultsScreen> {
  /// ПК ли это: от него зависит запас по умолчанию.
  static final bool _desktop =
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  static const String _title = 'Чтение по умолчанию';

  static const String _previewHint =
      'Сначала грубо, через миг резко. Если выключить, страница '
      'появляется только резкой — но после паузы.';

  static const String _reserveHint =
      'Сколько страниц держать наготове с каждой стороны. Больше — '
      'быстрее листать, но больше памяти.';

  static const String _reserveOff =
      'Наготове держатся грубые картинки страниц. Пока страница не '
      'показывается сразу, держать нечего.';

  static const String _deviceNote =
      'Настройки сохраняются на этом устройстве и действуют со '
      'следующего открытия книги.';

  PageTurnSettings? _turning;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? preview = await widget.settings.read(
      SettingsKeys.pagePreview,
    );
    final String? reserve = await widget.settings.read(
      SettingsKeys.pageReserve,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _turning = PageTurnSettings.parse(
        preview: preview,
        reserve: reserve,
        desktop: _desktop,
      );
    });
  }

  Future<void> _setPreview(bool value) async {
    final PageTurnSettings? current = _turning;
    if (current == null || current.preview == value) {
      return;
    }
    setState(() {
      _turning = PageTurnSettings(preview: value, reserve: current.reserve);
    });
    await widget.settings.write(SettingsKeys.pagePreview, value.toString());
  }

  Future<void> _setReserve(int value) async {
    final PageTurnSettings? current = _turning;
    if (current == null || current.reserve == value) {
      return;
    }
    setState(() {
      _turning = PageTurnSettings(preview: current.preview, reserve: value);
    });
    await widget.settings.write(SettingsKeys.pageReserve, value.toString());
  }

  void _onReserve(Set<int> picked) => unawaited(_setReserve(picked.first));

  List<ButtonSegment<int>> _segments() {
    return <ButtonSegment<int>>[
      for (int pages = 0; pages <= PageTurnSettings.maxReserve; pages++)
        ButtonSegment<int>(
          value: pages,
          label: Text('$pages', key: Key('page-reserve-$pages')),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTurnSettings? turning = _turning;
    if (turning == null) {
      // Настройки читаются из базы за один кадр; рисовать выключатель в
      // положении «по умолчанию» и тут же перещёлкивать его — обман.
      return Scaffold(appBar: AppBar(title: const Text(_title)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text(_title)),
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            key: const Key('page-preview-switch'),
            value: turning.preview,
            onChanged: (bool value) => unawaited(_setPreview(value)),
            title: const Text('Показывать страницу сразу'),
            subtitle: const Text(_previewHint),
          ),
          ListTile(
            title: const Text('Запас соседних страниц'),
            subtitle: Text(turning.preview ? _reserveHint : _reserveOff),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SegmentedButton<int>(
              key: const Key('page-reserve'),
              showSelectedIcon: false,
              segments: _segments(),
              selected: <int>{turning.reserve},
              onSelectionChanged: turning.preview ? _onReserve : null,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_deviceNote, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
