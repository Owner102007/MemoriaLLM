import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/reading/volume_keys.dart';
import '../../domain/settings/app_settings.dart';

/// Настройки «Клавиши и громкость».
///
/// Пока здесь только листание кнопками громкости (F-READ-26): включено
/// ли оно и какая кнопка листает вперёд. Таблица клавиш для ПК придёт
/// сюда же своим шагом (F-READ-25).
///
/// Обе настройки принадлежат устройству и не синхронизируются: кнопки
/// громкости есть у телефона, и какая из них лежит под пальцем, зависит
/// от телефона и руки.
class KeysScreen extends StatefulWidget {
  /// Создаёт экран.
  const KeysScreen({required this.settings, super.key});

  /// Хранилище настроек устройства.
  final AppSettingsRepository settings;

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  static const String _title = 'Клавиши и громкость';

  static const String _switchHint =
      'Короткое нажатие листает, удержание меняет громкость.';

  static const String _directionOff =
      'Кнопки громкости сейчас только меняют громкость.';

  static const String _note =
      'Кнопки листают, пока открыта книга и поверх страницы ничего нет. '
      'При включённом экранном дикторе они остаются кнопками громкости. '
      'Настройки сохраняются на этом устройстве.';

  VolumeKeySettings? _keys;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String? enabled = await widget.settings.read(SettingsKeys.volumeKeys);
    final String? down = await widget.settings.read(
      SettingsKeys.volumeDownForward,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _keys = VolumeKeySettings.parse(enabled: enabled, downIsForward: down);
    });
  }

  Future<void> _setEnabled(bool value) async {
    final VolumeKeySettings? current = _keys;
    if (current == null || current.enabled == value) {
      return;
    }
    setState(() => _keys = current.copyWith(enabled: value));
    await widget.settings.write(SettingsKeys.volumeKeys, value.toString());
  }

  Future<void> _setDownForward(bool value) async {
    final VolumeKeySettings? current = _keys;
    if (current == null || current.downIsForward == value) {
      return;
    }
    setState(() => _keys = current.copyWith(downIsForward: value));
    await widget.settings.write(
      SettingsKeys.volumeDownForward,
      value.toString(),
    );
  }

  void _onDirection(Set<bool> picked) =>
      unawaited(_setDownForward(picked.first));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VolumeKeySettings? keys = _keys;
    if (keys == null) {
      // Настройки читаются из базы за один кадр; рисовать выключатель в
      // положении «по умолчанию» и тут же перещёлкивать его — обман.
      return Scaffold(appBar: AppBar(title: const Text(_title)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text(_title)),
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            key: const Key('volume-keys-switch'),
            value: keys.enabled,
            onChanged: (bool value) => unawaited(_setEnabled(value)),
            title: const Text('Листать кнопками громкости'),
            subtitle: const Text(_switchHint),
          ),
          ListTile(
            title: const Text('Громкость «вниз» листает'),
            subtitle: keys.enabled ? null : const Text(_directionOff),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SegmentedButton<bool>(
              key: const Key('volume-down-direction'),
              showSelectedIcon: false,
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(
                  value: true,
                  label: Text('вперёд', key: Key('volume-down-forward')),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('назад', key: Key('volume-down-back')),
                ),
              ],
              selected: <bool>{keys.downIsForward},
              onSelectionChanged: keys.enabled ? _onDirection : null,
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_note, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
