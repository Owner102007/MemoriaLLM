/// Отложенная перекладка окна (F-DESK-02, ALG-UI-27).
///
/// На ПК размер окна меняет человек, и меняет протяжкой: пока он тянет
/// край, окно проходит сотню размеров. Перекладывать лист под каждый —
/// значит сто раз подряд растягивать готовую картинку страницы и сто раз
/// просить у движка новую. Поэтому серия изменений сводится к одному:
/// пока окно меняется, лист стоит в прежнем размере, а перекладывается и
/// рисуется резким один раз — когда окно перестали трогать.
///
/// Здесь — только счёт: какой размер действует и когда пора принять
/// новый. Виджетов класс не знает и проверяется числами.
library;

import 'dart:async';
import 'dart:ui' show Size;

import 'reading.dart';

/// Сколько окно должно простоять неизменным, чтобы лист переложили.
///
/// Меньше — перекладка успевала бы случиться посреди протяжки, на
/// каждой заминке руки. Больше — читатель, отпустивший край окна, ждал
/// бы страницу заметно дольше, чем длится само движение.
const Duration kWindowSettle = Duration(milliseconds: 150);

/// Сколько после разворота окна во весь экран его новый размер
/// принимается сразу, без отсчёта.
///
/// `F11` — не протяжка: размер меняется один раз и известно зачем. Но
/// сообщение о новом размере может прийти чуть позже ответа платформы,
/// поэтому «сразу» действует с запасом.
const Duration kWindowJump = Duration(milliseconds: 300);

/// Держит размер области показа, пока окно меняют.
///
/// Живых размера два, и приходят они в разное время: форма окна целиком
/// ([offerArea], по ней выбирается режим) и место под лист ([offerBox],
/// по нему лист раскладывается). Отсчёт у них общий, и принимаются они
/// вместе — иначе режим успел бы пересчитаться под новое окно, пока лист
/// ещё лежит по старому.
class WindowSettle {
  /// Создаёт счётчик. [onSettled] зовётся, когда принят новый размер.
  WindowSettle({required this.onSettled, this.delay = kWindowSettle});

  /// Окно простояло [delay], и новый размер принят.
  final void Function() onSettled;

  /// Сколько окно должно простоять неизменным.
  final Duration delay;

  DisplayArea _area = DisplayArea.unknown;
  DisplayArea _liveArea = DisplayArea.unknown;
  Size? _box;
  Size? _liveBox;
  Timer? _timer;

  /// Действующая форма окна: по ней выбирается режим.
  DisplayArea get area => _area;

  /// Действующее место под лист; `null` — его ещё не сообщали.
  Size? get box => _box;

  /// Идёт ли отсчёт: окно меняют, а лист ещё лежит по-старому.
  bool get waiting => _timer != null;

  /// Сообщает форму окна. `true` — действующая форма сменилась сразу.
  ///
  /// [hold] — держать ли прежнюю форму до конца серии. Первая форма и
  /// форма после свёрнутого окна принимаются сразу при любом [hold]:
  /// держать нечего.
  bool offerArea(DisplayArea live, {required bool hold}) {
    final bool fresh = live != _liveArea;
    _liveArea = live;
    if (!hold || !_area.isKnown) {
      final bool changed = live != _area;
      _area = live;
      return changed;
    }
    if (fresh && live != _area) {
      _restart();
    }
    return false;
  }

  /// Сообщает место под лист и возвращает то, по которому его
  /// раскладывать: новое или прежнее, если окно ещё меняют.
  Size offerBox(Size live, {required bool hold}) {
    final bool fresh = live != _liveBox;
    _liveBox = live;
    final Size? held = _box;
    if (!hold || held == null || held.isEmpty) {
      _box = live;
      return live;
    }
    if (fresh && live != held) {
      _restart();
    }
    return held;
  }

  /// Забывает место под лист: следующее будет принято сразу.
  ///
  /// Нужно, когда лист уходит с экрана — в ленте места под него не
  /// меряют, и к возвращению запомненное устарело бы.
  void releaseBox() {
    _box = null;
    _liveBox = null;
  }

  /// Прекращает отсчёт: экран закрыт.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(delay, _settle);
  }

  void _settle() {
    _timer = null;
    final Size? box = _liveBox;
    final bool changed = _area != _liveArea || (box != null && box != _box);
    _area = _liveArea;
    if (box != null) {
      _box = box;
    }
    // Окно вернули к прежнему размеру — перекладывать нечего.
    if (changed) {
      onSettled();
    }
  }
}
