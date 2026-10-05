import '../../domain/settings/app_settings.dart';
import 'action_log.dart';
import 'event.dart';

/// Сколько знаков значения настройки попадает в событие.
///
/// Таблица клавиш листания — строка в сотни знаков; журналу довольно
/// знать, что её меняли, и видеть начало.
const int kSettingValueLimit = 200;

/// Настройки приложения, каждая запись в которые видна журналу
/// (SNO-F-REC-02).
///
/// Экран настроек пишет в хранилище напрямую, и мест записи в нём много.
/// Вместо провода у каждого переключателя между экраном и хранилищем
/// стоит эта прослойка: что записано — то и попало в журнал событием
/// `settings.change`. Чтение идёт мимо неё как шло.
class LoggedSettings implements AppSettingsRepository {
  /// Создаёт прослойку над [inner]; события пишутся в [log].
  const LoggedSettings({
    required AppSettingsRepository inner,
    required ActionLog log,
  }) : _inner = inner,
       _log = log;

  final AppSettingsRepository _inner;
  final ActionLog _log;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Stream<String?> watch(String key) => _inner.watch(key);

  @override
  Future<void> write(String key, String value) async {
    await _inner.write(key, value);
    if (_log.recording) {
      final bool long = value.length > kSettingValueLimit;
      _log.log(
        SnoEventType.settingsChange,
        data: <String, Object?>{
          'key': key,
          'value': long ? value.substring(0, kSettingValueLimit) : value,
          if (long) 'truncated': true,
        },
      );
    }
  }

  @override
  Future<void> remove(String key) async {
    await _inner.remove(key);
    if (_log.recording) {
      _log.log(
        SnoEventType.settingsChange,
        data: <String, Object?>{'key': key, 'removed': true},
      );
    }
  }
}
