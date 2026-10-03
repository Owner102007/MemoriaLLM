import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/reading/volume_keys.dart';
import '../../domain/settings/app_settings.dart';
import '../reader/key_bindings.dart';

/// Настройки «Клавиши и громкость».
///
/// На телефоне здесь листание кнопками громкости (F-READ-26): включено
/// ли оно и какая кнопка листает вперёд. На ПК — таблица клавиш
/// листания (F-READ-25): какие клавиши листают вперёд, какие назад.
///
/// Всё это принадлежит устройству и не синхронизируется: кнопки
/// громкости есть у телефона, клавиатура и педаль — у компьютера, и что
/// из них лежит под рукой, от книги не зависит.
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

  static const String _fixedNote =
      'Не меняются: Ctrl+F — поиск по книге; F3 и Shift+F3 — по '
      'совпадениям; Enter — следующее совпадение, пока открыт поиск; '
      'Esc — закрыть; F11 — во весь экран.';

  static const String _turnNote =
      'Листалки, педали и кольца шлют те же коды, что стрелки и '
      'PgUp/PgDn, и работают без настройки; листалку с другими кодами '
      'назначают как клавишу. Таблица сохраняется на этом устройстве и '
      'действует со следующего открытия книги.';

  VolumeKeySettings? _keys;
  KeyBindings? _turn;

  /// Телефон ли это: у него кнопки громкости, у ПК — клавиатура.
  ///
  /// Спрашивается каждый раз, а не запоминается: тесты одного файла
  /// проверяют обе платформы.
  bool get _phone => defaultTargetPlatform == TargetPlatform.android;

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
    final String? turn = await widget.settings.read(SettingsKeys.turnKeys);
    if (!mounted) {
      return;
    }
    setState(() {
      _keys = VolumeKeySettings.parse(enabled: enabled, downIsForward: down);
      _turn = KeyBindings.parse(turn);
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

  /// Записывает таблицу клавиш (F-READ-25).
  Future<void> _saveTurn(KeyBindings next) async {
    setState(() => _turn = next);
    await widget.settings.write(SettingsKeys.turnKeys, next.encode());
  }

  /// Возвращает таблицу из коробки: настройка убирается вовсе.
  Future<void> _resetTurn() async {
    setState(() => _turn = KeyBindings.standard);
    await widget.settings.remove(SettingsKeys.turnKeys);
  }

  Future<void> _removeKey(TurnKey turn, KeyStroke stroke) async {
    final KeyBindings? current = _turn;
    if (current == null) {
      return;
    }
    await _saveTurn(current.without(turn, stroke));
  }

  /// Спрашивает клавишу и назначает её действию [turn].
  ///
  /// Клавиша, которая уже листала в другую сторону, переезжает — и об
  /// этом говорится: молча отобранная клавиша выглядела бы поломкой.
  Future<void> _addKey(TurnKey turn) async {
    final KeyBindings? current = _turn;
    if (current == null) {
      return;
    }
    final KeyStroke? stroke = await showDialog<KeyStroke>(
      context: context,
      builder: (BuildContext context) => _KeyCaptureDialog(turn: turn),
    );
    if (stroke == null || !mounted) {
      return;
    }
    final TurnKey? owner = current.ownerOf(stroke);
    await _saveTurn(current.assign(turn, stroke));
    if (!mounted || owner == null || owner == turn) {
      return;
    }
    final String now = turn == TurnKey.forward
        ? 'вперёд, а не назад'
        : 'назад, а не вперёд';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('turn-key-moved'),
        duration: const Duration(seconds: 3),
        content: Text('«${keyStrokeLabel(stroke)}» теперь листает $now.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VolumeKeySettings? keys = _keys;
    final KeyBindings? turn = _turn;
    if (keys == null || turn == null) {
      // Настройки читаются из базы за один кадр; рисовать выключатель в
      // положении «по умолчанию» и тут же перещёлкивать его — обман.
      return Scaffold(appBar: AppBar(title: const Text(_title)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text(_title)),
      body: ListView(
        children: _phone ? _volumeSection(keys) : _turnSection(turn),
      ),
    );
  }

  /// Телефон: листание кнопками громкости (F-READ-26).
  List<Widget> _volumeSection(VolumeKeySettings keys) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
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
    ];
  }

  /// ПК: таблица «действие → клавиши» (F-READ-25).
  List<Widget> _turnSection(KeyBindings turn) {
    final ThemeData theme = Theme.of(context);
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text('Клавиши листания', style: theme.textTheme.titleMedium),
      ),
      _TurnRow(
        turn: TurnKey.forward,
        title: 'Вперёд',
        strokes: turn.forward,
        onAdd: () => unawaited(_addKey(TurnKey.forward)),
        onRemove: (KeyStroke stroke) =>
            unawaited(_removeKey(TurnKey.forward, stroke)),
      ),
      _TurnRow(
        turn: TurnKey.back,
        title: 'Назад',
        strokes: turn.back,
        onAdd: () => unawaited(_addKey(TurnKey.back)),
        onRemove: (KeyStroke stroke) =>
            unawaited(_removeKey(TurnKey.back, stroke)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('turn-keys-reset'),
            // Возвращать нечего — кнопка это показывает, а не молчит.
            onPressed: turn == KeyBindings.standard
                ? null
                : () => unawaited(_resetTurn()),
            child: const Text('Вернуть как было'),
          ),
        ),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          _fixedNote,
          key: const Key('turn-keys-fixed'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_turnNote, style: theme.textTheme.bodySmall),
      ),
    ];
  }
}

/// Строка таблицы клавиш: действие и клавиши, которые его делают.
class _TurnRow extends StatelessWidget {
  const _TurnRow({
    required this.turn,
    required this.title,
    required this.strokes,
    required this.onAdd,
    required this.onRemove,
  });

  final TurnKey turn;
  final String title;
  final List<KeyStroke> strokes;
  final VoidCallback onAdd;
  final ValueChanged<KeyStroke> onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final KeyStroke stroke in strokes)
                Chip(
                  key: Key('turn-key-${turn.name}-${stroke.encode()}'),
                  label: Text(keyStrokeLabel(stroke)),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  deleteButtonTooltipMessage: 'Убрать клавишу',
                  onDeleted: () => onRemove(stroke),
                ),
              ActionChip(
                key: Key('turn-key-add-${turn.name}'),
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Клавиша'),
                tooltip: 'Назначить ещё одну клавишу',
                onPressed: onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Окно «нажмите клавишу»: ждёт клавишу и возвращает её.
///
/// Клавиши, у которых в чтении своё дело, и сочетания с `Ctrl` и `Alt`
/// не принимаются — окно говорит почему и ждёт дальше. `Esc` закрывает
/// окно, ничего не назначив.
class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({required this.turn});

  final TurnKey turn;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final FocusNode _focus = FocusNode(debugLabel: 'key-capture');

  /// Почему последняя нажатая клавиша не подошла.
  String? _refusal;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Окно забирает все клавиши: пробел, нажатый ради назначения, не
    // должен заодно нажать кнопку «Отмена».
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (isModifierKey(key)) {
      // Читатель ещё не закончил сочетание.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      setState(() {
        _refusal =
            'Сочетания с Ctrl и Alt не назначаются: в чтении они заняты '
            'поиском и системой.';
      });
      return KeyEventResult.handled;
    }
    if (!isAssignableKey(key)) {
      setState(() {
        _refusal =
            '«${keyStrokeLabel(KeyStroke(key))}» занята: у неё в чтении '
            'своё дело.';
      });
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(KeyStroke(key, shift: keyboard.isShiftPressed));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? refusal = _refusal;
    final bool forward = widget.turn == TurnKey.forward;
    return AlertDialog(
      key: const Key('key-capture-dialog'),
      title: Text(forward ? 'Клавиша «Вперёд»' : 'Клавиша «Назад»'),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Нажмите клавишу — одну или вместе с Shift. Листалка, педаль '
              'и кольцо назначаются так же: нажмите их кнопку.',
            ),
            if (refusal != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                refusal,
                key: const Key('key-capture-refusal'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('key-capture-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}
