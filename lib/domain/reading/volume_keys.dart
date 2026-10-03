/// Листание кнопками громкости (F-READ-26, ALG-READ-06).
///
/// Flutter кнопок громкости не видит: их перехватывает `MainActivity` и
/// пересылает сюда. Что с нажатием делать — листать или менять громкость,
/// — решается здесь, чистой функцией, а не в Kotlin: тестов Android в
/// проекте нет, и правило, написанное там, проверял бы только владелец
/// на своём телефоне.
///
/// Правило одно: **короткое нажатие листает, удержание меняет
/// громкость**. Поэтому листаем по отпусканию кнопки, а не по нажатию:
/// в момент нажатия ещё неизвестно, удержат её или нет.
library;

/// Кнопка громкости.
enum VolumeKey {
  /// Громче.
  up,

  /// Тише.
  down,
}

/// Одно событие кнопки громкости, как его прислала система.
class VolumeKeyEvent {
  /// Создаёт событие.
  const VolumeKeyEvent({
    required this.key,
    required this.pressed,
    this.repeat = 0,
    this.canceled = false,
  });

  /// Какая кнопка.
  final VolumeKey key;

  /// Нажата (`true`) или отпущена (`false`).
  final bool pressed;

  /// Номер автоповтора: ноль у первого нажатия, дальше растёт, пока
  /// кнопку держат.
  final int repeat;

  /// Система отменила нажатие: отпускание не настоящее.
  final bool canceled;

  @override
  String toString() =>
      'VolumeKeyEvent($key, ${pressed ? 'нажата' : 'отпущена'}, '
      'повтор: $repeat${canceled ? ', отменено' : ''})';
}

/// Что делать по событию кнопки.
enum VolumeKeyOutcome {
  /// Ничего: ждём, чем кончится нажатие.
  none,

  /// Листнуть вперёд.
  forward,

  /// Листнуть назад.
  back,

  /// Сделать громче — как сделала бы система.
  raise,

  /// Сделать тише.
  lower,
}

/// Настройки листания кнопками громкости. Настройка устройства.
class VolumeKeySettings {
  /// Создаёт настройки.
  const VolumeKeySettings({this.enabled = true, this.downIsForward = true});

  /// Настройки из сохранённых строк; чего нет — берётся по умолчанию.
  ///
  /// По умолчанию включено, и «тише» листает вперёд: нижняя кнопка
  /// лежит под пальцем, а вперёд листают чаще.
  factory VolumeKeySettings.parse({
    required String? enabled,
    required String? downIsForward,
  }) {
    return VolumeKeySettings(
      enabled: enabled != 'false',
      downIsForward: downIsForward != 'false',
    );
  }

  /// Листать ли кнопками громкости вовсе.
  final bool enabled;

  /// Листает ли кнопка «тише» вперёд. Иначе вперёд листает «громче».
  final bool downIsForward;

  /// Те же настройки с правкой.
  VolumeKeySettings copyWith({bool? enabled, bool? downIsForward}) {
    return VolumeKeySettings(
      enabled: enabled ?? this.enabled,
      downIsForward: downIsForward ?? this.downIsForward,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VolumeKeySettings &&
        other.enabled == enabled &&
        other.downIsForward == downIsForward;
  }

  @override
  int get hashCode => Object.hash(enabled, downIsForward);

  @override
  String toString() =>
      'VolumeKeySettings(включено: $enabled, «тише» вперёд: $downIsForward)';
}

/// Перехватывать ли кнопки громкости прямо сейчас.
///
/// Только пока читатель смотрит на страницу: книга открыта ([bookOpen])
/// и поверх неё ничего нет ([onTop]) — ни шторки, ни диалога, ни поиска,
/// ни оглавления. Во всех остальных местах кнопки громкости — это
/// громкость, и приложение к ним не прикасается.
///
/// При включённом экранном дикторе ([screenReader]) перехват не
/// включается вовсе: кнопками громкости управляют им самим, и отбирать
/// их у человека, который не видит экрана, нельзя.
bool volumeKeysActive({
  required VolumeKeySettings settings,
  required bool bookOpen,
  required bool onTop,
  required bool screenReader,
}) {
  return settings.enabled && bookOpen && onTop && !screenReader;
}

/// Решает, что делать по каждому событию кнопки громкости.
///
/// Помнит одно: какая кнопка нажата и успела ли она стать удержанием.
class VolumeKeyTurner {
  VolumeKey? _pressed;
  bool _held = false;

  /// Что делать по событию [event].
  ///
  /// [active] — действует ли перехват сейчас ([volumeKeysActive]).
  /// Событие может прийти и когда он уже не действует: выключение
  /// доходит до `MainActivity` не мгновенно. Тогда кнопка ведёт себя как
  /// обычная кнопка громкости — каждое нажатие и каждый автоповтор
  /// меняют громкость, — а не пропадает.
  VolumeKeyOutcome handle(
    VolumeKeyEvent event, {
    required bool active,
    bool downIsForward = true,
  }) {
    if (!active) {
      _pressed = null;
      _held = false;
      return event.pressed ? _volume(event.key) : VolumeKeyOutcome.none;
    }
    if (event.pressed) {
      if (event.repeat == 0) {
        // Первое нажатие: листать рано — кнопку могут удержать.
        _pressed = event.key;
        _held = false;
        return VolumeKeyOutcome.none;
      }
      // Пошёл автоповтор — это удержание, и оно про громкость. Громкость
      // меняет каждый повтор, как у системы.
      _pressed = event.key;
      _held = true;
      return _volume(event.key);
    }
    final bool turn = _pressed == event.key && !_held && !event.canceled;
    _pressed = null;
    _held = false;
    if (!turn) {
      // Отпустили после удержания, отпускание отменено системой или
      // нажатие началось до перехвата — листать не по чему.
      return VolumeKeyOutcome.none;
    }
    final bool forward = (event.key == VolumeKey.down) == downIsForward;
    return forward ? VolumeKeyOutcome.forward : VolumeKeyOutcome.back;
  }

  /// Забыть начатое нажатие: перехват выключился посреди него.
  void reset() {
    _pressed = null;
    _held = false;
  }

  VolumeKeyOutcome _volume(VolumeKey key) =>
      key == VolumeKey.up ? VolumeKeyOutcome.raise : VolumeKeyOutcome.lower;
}

/// Получатель событий кнопок громкости: отвечает, что с ними делать.
typedef VolumeKeyHandler = VolumeKeyOutcome Function(VolumeKeyEvent event);

/// Кнопки громкости как их отдаёт платформа.
///
/// Реализация — в `infrastructure`: на Android это канал в
/// `MainActivity`, на ПК кнопок громкости у читалки нет, и там стоит
/// [NoVolumeKeys]. Тесты подставляют свою.
abstract interface class VolumeKeys {
  /// Подключает получателя событий. Прежний при этом отключается.
  void attach(VolumeKeyHandler handler);

  /// Отключает получателя — если подключён именно он — и выключает
  /// перехват.
  void detach(VolumeKeyHandler handler);

  /// Включает и выключает перехват кнопок.
  ///
  /// Пока он выключен, платформа кнопки не трогает вовсе: громкость
  /// меняет система, своим путём.
  Future<void> setActive(bool active);
}

/// Кнопок громкости нет: ПК и тесты, которым они не нужны.
class NoVolumeKeys implements VolumeKeys {
  /// Создаёт заглушку.
  const NoVolumeKeys();

  @override
  void attach(VolumeKeyHandler handler) {}

  @override
  void detach(VolumeKeyHandler handler) {}

  @override
  Future<void> setActive(bool active) async {}
}
