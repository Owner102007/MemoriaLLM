import 'package:flutter/services.dart';

/// Куда листает клавиша.
enum TurnKey {
  /// Вперёд: следующий фрагмент.
  forward,

  /// Назад: предыдущий фрагмент.
  back,
}

/// Клавиша листания: сама клавиша и зажат ли вместе с ней `Shift`.
///
/// `Shift` — часть клавиши, а не довесок: «пробел» листает вперёд, а
/// «Shift+пробел» — назад, и это две разные строки таблицы.
class KeyStroke {
  /// Создаёт клавишу.
  const KeyStroke(this.key, {this.shift = false});

  /// Сама клавиша.
  final LogicalKeyboardKey key;

  /// Зажат ли `Shift`.
  final bool shift;

  /// Запись для настроек: номер клавиши, с буквой `s` — если с `Shift`.
  String encode() => shift ? 's${key.keyId}' : '${key.keyId}';

  /// Клавиша из записи настроек; `null` — запись не читается.
  static KeyStroke? decode(String text) {
    final String trimmed = text.trim();
    final bool shift = trimmed.startsWith('s');
    final int? id = int.tryParse(shift ? trimmed.substring(1) : trimmed);
    if (id == null || id <= 0) {
      return null;
    }
    return KeyStroke(
      LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id),
      shift: shift,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is KeyStroke &&
        other.key.keyId == key.keyId &&
        other.shift == shift;
  }

  @override
  int get hashCode => Object.hash(key.keyId, shift);

  @override
  String toString() => 'KeyStroke(${keyStrokeLabel(this)})';
}

/// Таблица клавиш листания (F-READ-25, ALG-READ-05).
///
/// Два действия — вперёд и назад — и клавиши каждого. Настройка
/// устройства: клавиатура, педаль или кольцо-листалка лежат у этого
/// компьютера, а не у книги. Bluetooth-листалки шлют те же коды, что
/// стрелки и `PgUp`/`PgDn`, и работают без настройки; листалку с другими
/// кодами назначают сюда, как любую клавишу.
///
/// Поиск, шаг по совпадениям, `Esc` и `F11` в таблицу не входят и занять
/// их нельзя ([isAssignableKey]): клавиша, которой привыкли закрывать
/// панель, не должна начать листать книгу.
class KeyBindings {
  /// Создаёт таблицу.
  const KeyBindings({required this.forward, required this.back});

  /// Таблица из сохранённой строки.
  ///
  /// Нет строки — таблица из коробки. Строка есть, но не читается —
  /// тоже она: клавиатура, которая перестала листать из-за испорченной
  /// настройки, хуже забытой настройки. Пустой список при этом — законное
  /// значение: читатель вправе убрать у действия все клавиши.
  factory KeyBindings.parse(String? saved) {
    if (saved == null) {
      return standard;
    }
    List<KeyStroke>? forward;
    List<KeyStroke>? back;
    for (final String part in saved.split(';')) {
      if (part.startsWith(_forwardTag)) {
        forward = _decodeList(part.substring(_forwardTag.length));
      } else if (part.startsWith(_backTag)) {
        back = _decodeList(part.substring(_backTag.length));
      }
    }
    if (forward == null || back == null) {
      return standard;
    }
    // Клавиша принадлежит одному действию: что уже листает вперёд,
    // назад листать не может.
    final Set<KeyStroke> taken = forward.toSet();
    return KeyBindings(
      forward: forward,
      back: <KeyStroke>[
        for (final KeyStroke stroke in back)
          if (!taken.contains(stroke)) stroke,
      ],
    );
  }

  static const String _forwardTag = 'f:';
  static const String _backTag = 'b:';

  /// Таблица из коробки — та, что была зашита до F-READ-25.
  static const KeyBindings standard = KeyBindings(
    forward: <KeyStroke>[
      KeyStroke(LogicalKeyboardKey.space),
      KeyStroke(LogicalKeyboardKey.pageDown),
      KeyStroke(LogicalKeyboardKey.arrowRight),
      KeyStroke(LogicalKeyboardKey.arrowDown),
    ],
    back: <KeyStroke>[
      KeyStroke(LogicalKeyboardKey.space, shift: true),
      KeyStroke(LogicalKeyboardKey.pageUp),
      KeyStroke(LogicalKeyboardKey.arrowLeft),
      KeyStroke(LogicalKeyboardKey.arrowUp),
      KeyStroke(LogicalKeyboardKey.backspace),
    ],
  );

  /// Клавиши, листающие вперёд.
  final List<KeyStroke> forward;

  /// Клавиши, листающие назад.
  final List<KeyStroke> back;

  /// Клавиши действия [turn].
  List<KeyStroke> keysOf(TurnKey turn) =>
      turn == TurnKey.forward ? forward : back;

  /// Какому действию назначена ровно эта клавиша; `null` — никакому.
  TurnKey? ownerOf(KeyStroke stroke) {
    if (forward.contains(stroke)) {
      return TurnKey.forward;
    }
    if (back.contains(stroke)) {
      return TurnKey.back;
    }
    return null;
  }

  /// Куда листает нажатая клавиша; `null` — никуда.
  ///
  /// Сочетание с `Shift` ищется первым. Если его в таблице нет, `Shift`
  /// не мешает: «Shift+→» листает туда же, куда «→», — так было и до
  /// таблицы.
  TurnKey? turnFor(LogicalKeyboardKey key, {bool shift = false}) {
    final TurnKey? exact = ownerOf(KeyStroke(key, shift: shift));
    if (exact != null || !shift) {
      return exact;
    }
    return ownerOf(KeyStroke(key));
  }

  /// Таблица, в которой [stroke] назначена действию [turn].
  ///
  /// У другого действия клавиша при этом отбирается: одна клавиша не
  /// может листать и вперёд, и назад.
  KeyBindings assign(TurnKey turn, KeyStroke stroke) {
    final List<KeyStroke> mine = <KeyStroke>[
      ...keysOf(turn).where((KeyStroke other) => other != stroke),
      stroke,
    ];
    final TurnKey otherTurn = turn == TurnKey.forward
        ? TurnKey.back
        : TurnKey.forward;
    final List<KeyStroke> others = <KeyStroke>[
      ...keysOf(otherTurn).where((KeyStroke other) => other != stroke),
    ];
    return turn == TurnKey.forward
        ? KeyBindings(forward: mine, back: others)
        : KeyBindings(forward: others, back: mine);
  }

  /// Таблица, в которой у действия [turn] клавиши [stroke] больше нет.
  KeyBindings without(TurnKey turn, KeyStroke stroke) {
    final List<KeyStroke> mine = <KeyStroke>[
      ...keysOf(turn).where((KeyStroke other) => other != stroke),
    ];
    return turn == TurnKey.forward
        ? KeyBindings(forward: mine, back: back)
        : KeyBindings(forward: forward, back: mine);
  }

  /// Запись для настроек.
  String encode() =>
      '$_forwardTag${_encodeList(forward)};'
      '$_backTag${_encodeList(back)}';

  static String _encodeList(List<KeyStroke> strokes) =>
      strokes.map((KeyStroke stroke) => stroke.encode()).join(',');

  /// Клавиши из записи: нечитаемые, служебные и повторные пропускаются.
  static List<KeyStroke> _decodeList(String text) {
    final List<KeyStroke> strokes = <KeyStroke>[];
    for (final String item in text.split(',')) {
      if (item.trim().isEmpty) {
        continue;
      }
      final KeyStroke? stroke = KeyStroke.decode(item);
      if (stroke != null &&
          isAssignableKey(stroke.key) &&
          !strokes.contains(stroke)) {
        strokes.add(stroke);
      }
    }
    return strokes;
  }

  @override
  bool operator ==(Object other) {
    return other is KeyBindings &&
        _sameStrokes(other.forward, forward) &&
        _sameStrokes(other.back, back);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(forward), Object.hashAll(back));

  @override
  String toString() => 'KeyBindings(${encode()})';

  static bool _sameStrokes(List<KeyStroke> a, List<KeyStroke> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Клавиши, у которых в чтении своё дело.
///
/// `Esc` закрывает панели, `Enter` и `F3` ведут по совпадениям поиска,
/// `F11` разворачивает окно, `Tab` принадлежит фокусу.
final Set<int> _busyKeys = <int>{
  LogicalKeyboardKey.escape.keyId,
  LogicalKeyboardKey.enter.keyId,
  LogicalKeyboardKey.numpadEnter.keyId,
  LogicalKeyboardKey.f3.keyId,
  LogicalKeyboardKey.f11.keyId,
  LogicalKeyboardKey.tab.keyId,
};

/// Модификаторы и переключатели: сами по себе они не клавиша, а
/// половина сочетания.
final Set<int> _modifierKeys = <int>{
  LogicalKeyboardKey.shift.keyId,
  LogicalKeyboardKey.shiftLeft.keyId,
  LogicalKeyboardKey.shiftRight.keyId,
  LogicalKeyboardKey.control.keyId,
  LogicalKeyboardKey.controlLeft.keyId,
  LogicalKeyboardKey.controlRight.keyId,
  LogicalKeyboardKey.alt.keyId,
  LogicalKeyboardKey.altLeft.keyId,
  LogicalKeyboardKey.altRight.keyId,
  LogicalKeyboardKey.altGraph.keyId,
  LogicalKeyboardKey.meta.keyId,
  LogicalKeyboardKey.metaLeft.keyId,
  LogicalKeyboardKey.metaRight.keyId,
  LogicalKeyboardKey.capsLock.keyId,
  LogicalKeyboardKey.numLock.keyId,
  LogicalKeyboardKey.scrollLock.keyId,
  LogicalKeyboardKey.fn.keyId,
  LogicalKeyboardKey.fnLock.keyId,
};

/// Модификатор ли это: `Shift`, `Ctrl`, `Alt` и им подобные.
///
/// Окно «нажмите клавишу» на них не отвечает: читатель, зажавший `Shift`,
/// ещё не закончил сочетание.
bool isModifierKey(LogicalKeyboardKey key) =>
    _modifierKeys.contains(key.keyId);

/// Можно ли назначить клавишу листанию (F-READ-25).
///
/// Нельзя — клавиши, у которых в чтении своё дело, и модификаторы.
bool isAssignableKey(LogicalKeyboardKey key) =>
    !_busyKeys.contains(key.keyId) && !_modifierKeys.contains(key.keyId);

/// Подписи клавиш, у которых нет печатного знака или он ни о чём не
/// говорит: пробел на кнопке — это пустое место.
final Map<int, String> _keyLabels = <int, String>{
  LogicalKeyboardKey.space.keyId: 'Пробел',
  LogicalKeyboardKey.pageDown.keyId: 'PgDn',
  LogicalKeyboardKey.pageUp.keyId: 'PgUp',
  LogicalKeyboardKey.arrowRight.keyId: '→',
  LogicalKeyboardKey.arrowLeft.keyId: '←',
  LogicalKeyboardKey.arrowUp.keyId: '↑',
  LogicalKeyboardKey.arrowDown.keyId: '↓',
  LogicalKeyboardKey.backspace.keyId: 'Backspace',
  LogicalKeyboardKey.home.keyId: 'Home',
  LogicalKeyboardKey.end.keyId: 'End',
  LogicalKeyboardKey.delete.keyId: 'Delete',
  LogicalKeyboardKey.insert.keyId: 'Insert',
};

/// Как клавиша подписана в таблице: «Пробел», «Shift+Пробел», «PgDn».
String keyStrokeLabel(KeyStroke stroke) {
  final LogicalKeyboardKey key = stroke.key;
  String label = _keyLabels[key.keyId] ?? key.keyLabel;
  if (label.trim().isEmpty) {
    label = key.debugName ?? 'Клавиша ${key.keyId}';
  }
  return stroke.shift ? 'Shift+$label' : label;
}
