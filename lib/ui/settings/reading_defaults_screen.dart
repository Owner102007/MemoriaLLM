import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/reading/page_turning.dart';
import '../../domain/reading/reader_gestures.dart';
import '../../domain/settings/app_settings.dart';

/// Настройки «Чтение по умолчанию».
///
/// Скорость показа страницы (F-READ-02): показывать ли страницу сразу,
/// грубой картинкой, и сколько соседних страниц держать наготове. И зоны
/// листания (F-READ-23): какая часть экрана по краям листает и показать
/// ли подсказку о зонах ещё раз. Мастер-настройки чтения и автофильтр
/// придут сюда же своими шагами.
///
/// Всё это принадлежит устройству и не синхронизируется: сколько памяти
/// не жалко, мешает ли ступенька «грубо → резко» и до какого места
/// экрана достаёт палец, на телефоне и на ПК решается по-разному.
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

  /// Сколько шагов у ползунка зоны: от самой узкой до самой широкой.
  static final int _zoneDivisions =
      ((kMaxReaderTapZone - kMinReaderTapZone) * 100).round() ~/
      kReaderTapZoneStep;

  static const String _deviceNote =
      'Настройки сохраняются на этом устройстве и действуют со '
      'следующего открытия книги.';

  static const String _zoneHint =
      'Какая часть экрана с каждой стороны листает книгу. Нажатие между '
      'зонами показывает и прячет панели.';

  static const String _hintAgain =
      'Подсказка о зонах появится при следующем открытии книги.';

  PageTurnSettings? _turning;

  /// Ширина зоны листания, доля ширины экрана (F-READ-23).
  double _zone = kReaderTapZone;

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
    final String? zone = await widget.settings.read(SettingsKeys.tapZone);
    if (!mounted) {
      return;
    }
    setState(() {
      _turning = PageTurnSettings.parse(
        preview: preview,
        reserve: reserve,
        desktop: _desktop,
      );
      _zone = parseReaderTapZone(zone);
    });
  }

  /// Ползунок зоны сдвинули: образец меняется вживую, без записи.
  void _onZone(double percent) {
    setState(() => _zone = clampReaderTapZone(percent / 100));
  }

  /// Ползунок зоны отпустили: значение пора записать.
  Future<void> _saveZone(double percent) async {
    final double zone = clampReaderTapZone(percent / 100);
    setState(() => _zone = zone);
    await widget.settings.write(
      SettingsKeys.tapZone,
      readerTapZonePercent(zone).toString(),
    );
  }

  /// Подсказка о зонах покажется снова — один раз, как в первый.
  Future<void> _showHintAgain() async {
    await widget.settings.remove(SettingsKeys.tapZoneHintSeen);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('tap-zone-hint-again'),
        duration: Duration(seconds: 3),
        content: Text(_hintAgain),
      ),
    );
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
    final int zonePercent = readerTapZonePercent(_zone);
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
          const ListTile(
            title: Text('Зоны листания'),
            subtitle: Text(_zoneHint),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Slider(
                    key: const Key('tap-zone-slider'),
                    min: readerTapZonePercent(kMinReaderTapZone).toDouble(),
                    max: readerTapZonePercent(kMaxReaderTapZone).toDouble(),
                    divisions: _zoneDivisions,
                    value: zonePercent.toDouble(),
                    label: '$zonePercent %',
                    onChanged: _onZone,
                    onChangeEnd: (double value) => unawaited(_saveZone(value)),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$zonePercent %',
                    key: const Key('tap-zone-value'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _ZonePreview(percent: zonePercent),
          ),
          ListTile(
            key: const Key('tap-zone-hint-reset'),
            title: const Text('Показать подсказку ещё раз'),
            subtitle: const Text('При следующем открытии книги'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_showHintAgain()),
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

/// Образец зон листания: слева «Назад», справа «Вперёд», между ними
/// «Панели» — той ширины, какую показывает ползунок (F-READ-23).
class _ZonePreview extends StatelessWidget {
  const _ZonePreview({required this.percent});

  /// Ширина зоны с каждой стороны, в процентах ширины экрана.
  final int percent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color edge = colors.primary.withValues(alpha: 0.28);
    Widget part(String text, Color color) {
      return ColoredBox(
        color: color,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(text, style: theme.textTheme.bodySmall),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        key: const Key('tap-zone-preview'),
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(flex: percent, child: part('Назад', edge)),
            Expanded(
              flex: 100 - percent * 2,
              child: part('Панели', colors.surfaceContainerHighest),
            ),
            Expanded(flex: percent, child: part('Вперёд', edge)),
          ],
        ),
      ),
    );
  }
}
