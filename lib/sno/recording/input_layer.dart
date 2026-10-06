/// Перехват сырого ввода на время записи (SNO-F-REC-11,
/// SNO-ALG-REC-07, шаг 1).
///
/// Каждое касание экрана, нажатие мыши, прокрутка колеса и клавиша —
/// где бы они ни пришлись и сделали ли что-нибудь — уходят в поток
/// `input.jsonl` записи. Слушатель стоит не в дереве виджетов, а на
/// общем маршруте указателей: он видит события любого экрана и диалога,
/// в споре жестов не участвует и ничего не поглощает — приложение под
/// ним ведёт себя так же, как без записи. Клавиши слушает обработчик,
/// который всегда отвечает «не обработано».
///
/// Слушатели заводятся стартом записи и снимаются её остановкой: вне
/// записи перехватчика не существует. В основном приложении этот код
/// недостижим — слой записи есть только в сборках ветвей СНО2026.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'input_tap.dart';
import 'session.dart';

/// Как экран называется в строке ввода, когда касание пришлось на
/// точку записи: это экспериментатор, в карты участника оно не идёт.
const String kInputDotScreen = 'recording_dot';

/// То же для касаний, пока открыт вопрос об остановке записи.
const String kInputStopScreen = 'stop_dialog';

final Map<LogicalKeyboardKey, String> _namedKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
  LogicalKeyboardKey.arrowRight: 'ArrowRight',
  LogicalKeyboardKey.arrowUp: 'ArrowUp',
  LogicalKeyboardKey.arrowDown: 'ArrowDown',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'Enter',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.insert: 'Insert',
  LogicalKeyboardKey.contextMenu: 'ContextMenu',
  LogicalKeyboardKey.goBack: 'Back',
  LogicalKeyboardKey.browserBack: 'Back',
  LogicalKeyboardKey.audioVolumeUp: 'VolumeUp',
  LogicalKeyboardKey.audioVolumeDown: 'VolumeDown',
  LogicalKeyboardKey.f1: 'F1',
  LogicalKeyboardKey.f2: 'F2',
  LogicalKeyboardKey.f3: 'F3',
  LogicalKeyboardKey.f4: 'F4',
  LogicalKeyboardKey.f5: 'F5',
  LogicalKeyboardKey.f6: 'F6',
  LogicalKeyboardKey.f7: 'F7',
  LogicalKeyboardKey.f8: 'F8',
  LogicalKeyboardKey.f9: 'F9',
  LogicalKeyboardKey.f10: 'F10',
  LogicalKeyboardKey.f11: 'F11',
  LogicalKeyboardKey.f12: 'F12',
};

final Map<LogicalKeyboardKey, String> _modifierKeys =
    <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.shiftLeft: 'Shift',
      LogicalKeyboardKey.shiftRight: 'Shift',
      LogicalKeyboardKey.shift: 'Shift',
      LogicalKeyboardKey.controlLeft: 'Ctrl',
      LogicalKeyboardKey.controlRight: 'Ctrl',
      LogicalKeyboardKey.control: 'Ctrl',
      LogicalKeyboardKey.altLeft: 'Alt',
      LogicalKeyboardKey.altRight: 'Alt',
      LogicalKeyboardKey.alt: 'Alt',
      LogicalKeyboardKey.metaLeft: 'Meta',
      LogicalKeyboardKey.metaRight: 'Meta',
      LogicalKeyboardKey.meta: 'Meta',
      LogicalKeyboardKey.capsLock: 'CapsLock',
    };

/// Имя клавиши для потока ввода (SNO-ALG-REC-07, шаг 5).
///
/// У управляющей клавиши — название (`PageDown`, `Escape`, `F3`), с
/// `Shift+` впереди, если он зажат; у сочетания с `Ctrl`, `Alt` или
/// `Meta` — сочетание целиком (`Ctrl+F`). Печатная клавиша без них —
/// `char`, **без самой буквы**: что набрано, журнал пишет запросом
/// целиком, а по клавишам набранное не восстанавливается.
String inputKeyName(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool ctrl = false,
  bool alt = false,
  bool meta = false,
}) {
  final String? modifier = _modifierKeys[key];
  if (modifier != null) {
    return modifier;
  }
  final String? named = _namedKeys[key];
  final bool combined = ctrl || alt || meta;
  if (named == null && !combined) {
    return 'char';
  }
  final String label = key.keyLabel;
  final String base =
      named ?? (label.length == 1 ? label.toUpperCase() : 'Key');
  return <String>[
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (meta) 'Meta',
    if (shift) 'Shift',
    base,
  ].join('+');
}

/// Указатель словом для потока ввода.
String inputDeviceName(PointerDeviceKind kind) {
  return switch (kind) {
    PointerDeviceKind.mouse => 'mouse',
    PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 'stylus',
    PointerDeviceKind.trackpad => 'trackpad',
    PointerDeviceKind.touch || PointerDeviceKind.unknown => 'touch',
  };
}

/// Кнопка мыши словом; `null` — у указателя кнопок нет.
String? inputButtonName(PointerDeviceKind kind, int buttons) {
  if (kind != PointerDeviceKind.mouse) {
    return null;
  }
  if (buttons & kSecondaryMouseButton != 0) {
    return 'secondary';
  }
  if (buttons & kMiddleMouseButton != 0) {
    return 'middle';
  }
  return 'primary';
}

/// Слушатели сырого ввода: от общего маршрута указателей и клавиатуры —
/// к потоку ввода идущей записи.
class InputLayer {
  /// Создаёт слой для записи [session].
  ///
  /// [size] отвечает размером окна в логических пикселях; [stage] —
  /// особым именем экрана для касаний, которые начинаются сейчас
  /// (вопрос об остановке), либо `null`.
  InputLayer({
    required this.session,
    required this.size,
    this.stage,
  });

  /// Запись, в поток которой уходит ввод.
  final RecordingSession session;

  /// Размер окна сейчас.
  final ({double width, double height}) Function() size;

  /// Особое имя экрана для касаний, которые начинаются сейчас.
  final String? Function()? stage;

  bool _attached = false;

  /// Сколько слоёв слушает ввод прямо сейчас — во всём приложении.
  /// Вне записи обязан быть ноль.
  static int listening = 0;

  /// Слушает ли слой ввод.
  bool get attached => _attached;

  /// Заводит слушателей. Повторный вызов ничего не делает.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    listening++;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    HardwareKeyboard.instance.addHandler(_key);
  }

  /// Снимает слушателей. Повторный вызов ничего не делает.
  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    listening--;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    HardwareKeyboard.instance.removeHandler(_key);
  }

  /// Касание указателя [pointer] забрала точка записи: это
  /// экспериментатор.
  void claimedByDot(int pointer) {
    session.input?.mark(pointer, kInputDotScreen);
  }

  String _screen() => stage?.call() ?? session.context.screen;

  void _pointer(PointerEvent event) {
    final InputTracker? input = session.input;
    if (input == null) {
      return;
    }
    final int t = session.inputNow;
    final Offset at = event.position;
    if (event is PointerDownEvent) {
      final ({double width, double height}) window = size();
      input.down(
        pointer: event.pointer,
        t: t,
        x: at.dx,
        y: at.dy,
        dev: inputDeviceName(event.kind),
        button: inputButtonName(event.kind, event.buttons),
        vw: window.width,
        vh: window.height,
        screen: _screen(),
      );
    } else if (event is PointerMoveEvent) {
      input.move(pointer: event.pointer, t: t, x: at.dx, y: at.dy);
    } else if (event is PointerUpEvent) {
      input.up(pointer: event.pointer, t: t, x: at.dx, y: at.dy);
    } else if (event is PointerCancelEvent) {
      input.cancel(pointer: event.pointer, t: t);
    } else if (event is PointerHoverEvent) {
      if (event.kind == PointerDeviceKind.mouse) {
        final ({double width, double height}) window = size();
        input.hover(
          t: t,
          x: at.dx,
          y: at.dy,
          vw: window.width,
          vh: window.height,
          screen: _screen(),
        );
      }
    } else if (event is PointerScrollEvent) {
      final ({double width, double height}) window = size();
      input.wheel(
        t: t,
        x: at.dx,
        y: at.dy,
        dx: event.scrollDelta.dx,
        dy: event.scrollDelta.dy,
        vw: window.width,
        vh: window.height,
        screen: _screen(),
      );
    } else if (event is PointerPanZoomStartEvent) {
      // Жест тачпада: путь — по сдвигу жеста, а не по курсору.
      final ({double width, double height}) window = size();
      input.down(
        pointer: event.pointer,
        t: t,
        x: at.dx,
        y: at.dy,
        dev: 'trackpad',
        vw: window.width,
        vh: window.height,
        screen: _screen(),
      );
    } else if (event is PointerPanZoomUpdateEvent) {
      input.move(
        pointer: event.pointer,
        t: t,
        x: at.dx + event.pan.dx,
        y: at.dy + event.pan.dy,
      );
    } else if (event is PointerPanZoomEndEvent) {
      input.up(pointer: event.pointer, t: t);
    }
  }

  bool _key(KeyEvent event) {
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    session.keyInput(
      event.physicalKey.usbHidUsage,
      inputKeyName(
        event.logicalKey,
        shift: keyboard.isShiftPressed,
        ctrl: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      ),
      pressed: event is! KeyUpEvent,
      repeat: event is KeyRepeatEvent,
    );
    // Клавишу слой не забирает никогда: она идёт дальше, как без него.
    return false;
  }
}
