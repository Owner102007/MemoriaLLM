/// Сырой ввод: касание, его вид и связь с действием (SNO-F-REC-11,
/// SNO-ALG-REC-07).
///
/// Журнал действий знает только то, что приложение **сделало**. Чтобы
/// увидеть, как участник осваивает интерфейс, нужны и нажатия, которые
/// не сделали ничего: поток `input.jsonl` пишет каждое касание экрана,
/// каждое нажатие мыши, прокрутку колеса и клавишу, а событие журнала,
/// записанное в ответ, ссылается на номер строки ввода. Касание, на
/// которое не сослалось ни одно событие, — пустое.
///
/// Здесь чистая часть: состояние касания, его вид, прореживание следа,
/// склейка колеса, пачки пути мыши и окно связи с действием. Событий
/// Flutter тут нет — их переводит `input_layer.dart`; времени тоже нет:
/// каждый вызов приносит своё `t` по часам записи.
library;

import 'dart:math' as math;

/// Дальше скольких логических пикселей от места касания палец «повёл».
const double kInputSlop = 18;

/// То же для мыши: рука с мышью стоит на месте точнее пальца.
const double kMouseSlop = 4;

/// С какой длительности касание на месте — удержание, в миллисекундах.
const int kLongPressMs = 500;

/// Как часто пишется точка следа касания: не чаще двадцати в секунду.
const int kTrailGapMs = 50;

/// Сколько точек следа хранит одно касание: дальше обновляется только
/// последняя. Минута непрерывного ведения пальцем.
const int kTrailLimit = 1200;

/// Через сколько миллисекунд тишины прокрутка колесом кончилась.
const int kWheelGapMs = 150;

/// Как часто пишется точка пути мыши без нажатия: не чаще десяти в
/// секунду.
const int kHoverGapMs = 100;

/// На сколько логических пикселей мышь должна сдвинуться, чтобы путь
/// получил новую точку.
const double kHoverSlop = 4;

/// Сколько миллисекунд пути мыши ложится одной строкой.
const int kHoverBatchMs = 1000;

/// Сколько миллисекунд после поднятого пальца (нажатой клавиши)
/// событие журнала ещё считается ответом на него.
const int kInputLinkMs = 400;

/// То же для событий, которые по своей природе запаздывают: запрос
/// поиска пишется, когда набранное простояло свой срок.
const int kInputLateLinkMs = 1500;

/// Чего поток не видит (`input.blind` в сведениях записи): касаний
/// экранной клавиатуры, шторки и системных кнопок, системных жестов от
/// края экрана и всего, что за пределами окна приложения. Разбор не
/// должен принять отсутствие строк за отсутствие нажатий.
const List<String> kInputBlind = <String>[
  'soft_keyboard',
  'system_bars',
  'system_gestures',
  'outside_window',
];

/// Куда уходит готовая строка потока.
typedef InputSink = void Function(Map<String, Object?> line);

/// Число с одним знаком после запятой: координате касания больше не
/// нужно, а строка короче.
double _round(double value) {
  if (!value.isFinite) {
    return 0;
  }
  return (value * 10).roundToDouble() / 10;
}

double _distance(double x0, double y0, double x1, double y1) {
  final double dx = x1 - x0;
  final double dy = y1 - y0;
  return math.sqrt(dx * dx + dy * dy);
}

/// Вид завершённого касания (SNO-ALG-REC-07, шаг 3).
///
/// [far] — наибольшее удаление от места касания, [ms] — сколько его
/// держали. Отмена системой сильнее всего; два пальца — сильнее
/// расстояния и времени.
String contactKind({
  required String dev,
  required double far,
  required int ms,
  bool multi = false,
  bool cancelled = false,
  bool cut = false,
}) {
  if (cut) {
    return 'cut';
  }
  if (cancelled) {
    return 'cancel';
  }
  if (multi) {
    return 'multi';
  }
  if (far > slopOf(dev)) {
    return 'drag';
  }
  return ms >= kLongPressMs ? 'long' : 'tap';
}

/// Порог места для указателя [dev].
double slopOf(String dev) => dev == 'mouse' ? kMouseSlop : kInputSlop;

class _Contact {
  _Contact({
    required this.n,
    required this.t,
    required this.x,
    required this.y,
    required this.dev,
    required this.button,
    required this.vw,
    required this.vh,
    required this.screen,
  }) : lastX = x,
       lastY = y,
       trailT = t;

  final int n;
  final int t;
  final double x;
  final double y;
  final String dev;
  final String? button;
  final double vw;
  final double vh;
  String screen;

  double lastX;
  double lastY;
  double path = 0;
  double far = 0;
  bool multi = false;
  int? group;

  /// След: тройки «миллисекунды от касания, x, y».
  final List<List<num>> trail = <List<num>>[];

  /// Когда записана последняя точка следа.
  int trailT;

  /// Точка, пришедшая раньше срока: станет последней точкой следа.
  List<num>? pending;
}

class _Key {
  _Key({
    required this.n,
    required this.t,
    required this.name,
    required this.screen,
  });

  final int n;
  final int t;
  final String name;
  final String screen;
  int repeats = 0;
}

class _Wheel {
  _Wheel({
    required this.n,
    required this.t,
    required this.x,
    required this.y,
    required this.vw,
    required this.vh,
    required this.screen,
  }) : lastT = t;

  final int n;
  final int t;
  final double x;
  final double y;
  final double vw;
  final double vh;
  final String screen;
  int lastT;
  double dx = 0;
  double dy = 0;
}

class _Hover {
  _Hover({
    required this.n,
    required this.t,
    required this.vw,
    required this.vh,
    required this.screen,
  });

  final int n;
  final int t;
  final double vw;
  final double vh;
  final String screen;
  final List<List<num>> trail = <List<num>>[];
}

/// Собирает строки потока сырого ввода из событий указателя, колеса и
/// клавиш (SNO-ALG-REC-07).
///
/// Номер `n` строка получает, когда касание началось: на него ссылается
/// событие журнала, записанное, пока палец ещё на экране. Сама строка
/// пишется, когда палец поднят, — поэтому номера в файле идут не строго
/// по порядку, а пропуск номера значит потерянную строку.
class InputTracker {
  /// Создаёт сборщик; готовые строки уходят в [emit].
  InputTracker(this._emit);

  final InputSink _emit;

  int _n = 0;
  final Map<int, _Contact> _down = <int, _Contact>{};
  final Map<Object, _Key> _keys = <Object, _Key>{};
  _Wheel? _wheel;
  _Hover? _hover;
  double? _hoverX;
  double? _hoverY;
  int _hoverT = 0;

  /// Последняя строка, на которую может сослаться событие, и миг, от
  /// которого считается окно связи.
  int? _linkN;
  int _linkT = 0;

  /// Сколько номеров выдано: столько строк обязано лежать в потоке,
  /// когда запись остановлена.
  int get count => _n;

  /// Сколько касаний сейчас на экране.
  int get held => _down.length;

  /// Указатель [pointer] коснулся экрана в точке ([x], [y]).
  ///
  /// [dev] — `touch`, `mouse`, `stylus`, `trackpad`; [button] — кнопка
  /// мыши; [vw] и [vh] — размер окна в этот миг; [screen] — экран.
  void down({
    required int pointer,
    required int t,
    required double x,
    required double y,
    required String dev,
    required double vw,
    required double vh,
    required String screen,
    String? button,
  }) {
    if (_down.containsKey(pointer)) {
      return;
    }
    final _Contact contact = _Contact(
      n: ++_n,
      t: t,
      x: x,
      y: y,
      dev: dev,
      button: button,
      vw: vw,
      vh: vh,
      screen: screen,
    );
    if (_down.isNotEmpty) {
      // Второй палец: все касания, что сейчас на экране, — одна группа.
      int group = contact.n;
      for (final _Contact other in _down.values) {
        final int known = other.group ?? other.n;
        if (known < group) {
          group = known;
        }
      }
      for (final _Contact other in _down.values) {
        other
          ..multi = true
          ..group = group;
      }
      contact
        ..multi = true
        ..group = group;
    }
    _down[pointer] = contact;
    _linkN = contact.n;
    _linkT = t;
  }

  /// Указатель [pointer] сдвинулся.
  void move({
    required int pointer,
    required int t,
    required double x,
    required double y,
  }) {
    final _Contact? contact = _down[pointer];
    if (contact == null) {
      return;
    }
    _advance(contact, t, x, y);
  }

  void _advance(_Contact contact, int t, double x, double y) {
    contact.path += _distance(contact.lastX, contact.lastY, x, y);
    final double far = _distance(contact.x, contact.y, x, y);
    if (far > contact.far) {
      contact.far = far;
    }
    contact
      ..lastX = x
      ..lastY = y;
    final List<num> point = <num>[t - contact.t, _round(x), _round(y)];
    if (t - contact.trailT >= kTrailGapMs &&
        contact.trail.length < kTrailLimit) {
      contact.trail.add(point);
      contact
        ..trailT = t
        ..pending = null;
    } else {
      contact.pending = point;
    }
  }

  /// Касание [pointer] помечено: оно пришлось на точку записи или на
  /// вопрос об остановке, это экспериментатор — в карты участника оно
  /// не идёт.
  void mark(int pointer, String screen) {
    _down[pointer]?.screen = screen;
  }

  /// Указатель [pointer] поднят; [x] и [y] — где, если известно.
  void up({required int pointer, required int t, double? x, double? y}) {
    _release(pointer, t, x: x, y: y);
  }

  /// Жест указателя [pointer] забрала система.
  void cancel({required int pointer, required int t}) {
    _release(pointer, t, cancelled: true);
  }

  void _release(
    int pointer,
    int t, {
    double? x,
    double? y,
    bool cancelled = false,
    bool cut = false,
  }) {
    final _Contact? contact = _down.remove(pointer);
    if (contact == null) {
      return;
    }
    if (x != null && y != null) {
      _advance(contact, t, x, y);
    }
    final List<num>? pending = contact.pending;
    if (pending != null) {
      // Последняя точка следа пишется обязательно: чем жест кончился,
      // поток знает точно.
      if (contact.trail.length >= kTrailLimit) {
        contact.trail.removeLast();
      }
      contact.trail.add(pending);
    }
    final int ms = t - contact.t < 0 ? 0 : t - contact.t;
    final String kind = contactKind(
      dev: contact.dev,
      far: contact.far,
      ms: ms,
      multi: contact.multi,
      cancelled: cancelled,
      cut: cut,
    );
    final bool led = contact.multi || contact.far > slopOf(contact.dev);
    final String? button = contact.button;
    final int? group = contact.group;
    _emit(<String, Object?>{
      'n': contact.n,
      't': contact.t,
      'dt': ms,
      'dev': contact.dev,
      if (button != null) 'button': button,
      'kind': kind,
      'x': _round(contact.x),
      'y': _round(contact.y),
      'x1': _round(contact.lastX),
      'y1': _round(contact.lastY),
      'path': _round(contact.path),
      'vw': _round(contact.vw),
      'vh': _round(contact.vh),
      'screen': contact.screen,
      if (group != null) 'group': group,
      if (led && contact.trail.isNotEmpty) 'trail': contact.trail,
    });
    _linkN = contact.n;
    _linkT = t;
  }

  /// Колесо мыши или прокрутка тачпада в точке ([x], [y]).
  ///
  /// Щелчки, между которыми меньше [kWheelGapMs], — одна строка с
  /// суммой.
  void wheel({
    required int t,
    required double x,
    required double y,
    required double dx,
    required double dy,
    required double vw,
    required double vh,
    required String screen,
  }) {
    _Wheel? wheel = _wheel;
    if (wheel != null && t - wheel.lastT >= kWheelGapMs) {
      _flushWheel();
      wheel = null;
    }
    wheel ??= _wheel = _Wheel(
      n: ++_n,
      t: t,
      x: x,
      y: y,
      vw: vw,
      vh: vh,
      screen: screen,
    );
    wheel
      ..dx += dx
      ..dy += dy
      ..lastT = t;
    _linkN = wheel.n;
    _linkT = t;
  }

  void _flushWheel() {
    final _Wheel? wheel = _wheel;
    if (wheel == null) {
      return;
    }
    _wheel = null;
    _emit(<String, Object?>{
      'n': wheel.n,
      't': wheel.t,
      'dt': wheel.lastT - wheel.t,
      'dev': 'wheel',
      'x': _round(wheel.x),
      'y': _round(wheel.y),
      if (wheel.dx != 0) 'dx': _round(wheel.dx),
      'dy': _round(wheel.dy),
      'vw': _round(wheel.vw),
      'vh': _round(wheel.vh),
      'screen': wheel.screen,
    });
  }

  /// Клавиша [id] нажата; [name] — её имя для потока: у управляющей —
  /// название, у печатной — `char`, без самой буквы.
  void keyDown(
    Object id, {
    required int t,
    required String name,
    required String screen,
  }) {
    final _Key? held = _keys[id];
    if (held != null) {
      // Второе нажатие без отпускания — автоповтор.
      keyRepeat(id, t: t);
      return;
    }
    final _Key key = _Key(n: ++_n, t: t, name: name, screen: screen);
    _keys[id] = key;
    _linkN = key.n;
    _linkT = t;
  }

  /// Клавишу [id] держат: автоповтор. Строки он не даёт — только счёт.
  void keyRepeat(Object id, {required int t}) {
    final _Key? key = _keys[id];
    if (key == null) {
      return;
    }
    key.repeats++;
    _linkN = key.n;
    _linkT = t;
  }

  /// Клавиша [id] отпущена: её строка пишется сейчас.
  void keyUp(Object id, {required int t}) {
    final _Key? key = _keys.remove(id);
    if (key == null) {
      return;
    }
    _emitKey(key, t);
    _linkN = key.n;
    _linkT = t;
  }

  void _emitKey(_Key key, int t, {bool cut = false}) {
    _emit(<String, Object?>{
      'n': key.n,
      't': key.t,
      'dt': t - key.t < 0 ? 0 : t - key.t,
      'dev': 'key',
      'key': key.name,
      if (key.repeats > 0) 'repeat': key.repeats,
      if (cut) 'kind': 'cut',
      'screen': key.screen,
    });
  }

  /// Мышь без нажатия стоит в точке ([x], [y]).
  ///
  /// Точка пишется не чаще раза в [kHoverGapMs] и только при сдвиге от
  /// [kHoverSlop]; путь за [kHoverBatchMs] — одна строка.
  void hover({
    required int t,
    required double x,
    required double y,
    required double vw,
    required double vh,
    required String screen,
  }) {
    final double? lastX = _hoverX;
    final double? lastY = _hoverY;
    if (lastX != null && lastY != null) {
      if (t - _hoverT < kHoverGapMs ||
          _distance(lastX, lastY, x, y) < kHoverSlop) {
        return;
      }
    }
    _Hover? hover = _hover;
    if (hover != null && t - hover.t >= kHoverBatchMs) {
      _flushHover();
      hover = null;
    }
    hover ??= _hover = _Hover(n: ++_n, t: t, vw: vw, vh: vh, screen: screen);
    hover.trail.add(<num>[t - hover.t, _round(x), _round(y)]);
    _hoverX = x;
    _hoverY = y;
    _hoverT = t;
  }

  void _flushHover() {
    final _Hover? hover = _hover;
    if (hover == null) {
      return;
    }
    _hover = null;
    _emit(<String, Object?>{
      'n': hover.n,
      't': hover.t,
      'dev': 'hover',
      'trail': hover.trail,
      'vw': _round(hover.vw),
      'vh': _round(hover.vh),
      'screen': hover.screen,
    });
  }

  /// Секунда записи: прокрутка, которая кончилась, и путь мыши,
  /// набравший свой срок, уходят строками.
  void poll(int t) {
    final _Wheel? wheel = _wheel;
    if (wheel != null && t - wheel.lastT >= kWheelGapMs) {
      _flushWheel();
    }
    final _Hover? hover = _hover;
    if (hover != null && t - hover.t >= kHoverBatchMs) {
      _flushHover();
    }
  }

  /// Запись остановлена: всё начатое пишется сейчас. Касание, которое
  /// ещё на экране, и клавиша, которую ещё держат, помечены `cut`.
  void finish(int t) {
    for (final int pointer in _down.keys.toList()) {
      _release(pointer, t, cut: true);
    }
    for (final Object id in _keys.keys.toList()) {
      final _Key? key = _keys.remove(id);
      if (key != null) {
        _emitKey(key, t, cut: true);
      }
    }
    _flushWheel();
    _flushHover();
    _linkN = null;
  }

  /// На какую строку ввода сослаться событию журнала, записанному в
  /// миг [t]; `null` — оно не ответ на ввод (SNO-ALG-REC-07, шаг 7).
  ///
  /// Пока палец на экране — на его касание; иначе — на последнюю
  /// строку, если с неё прошло не больше [window] миллисекунд.
  int? linkAt(int t, {int window = kInputLinkMs}) {
    if (_down.isNotEmpty) {
      return _down.values.last.n;
    }
    final int? n = _linkN;
    if (n == null) {
      return null;
    }
    final int passed = t - _linkT;
    return passed >= 0 && passed <= window ? n : null;
  }
}
