/// Ключи сборки ветви СНО2026 в общей таблице настроек.
///
/// В одном месте — чтобы сброс к эталону (`reference_state.dart`) и
/// запись сессии (`recording/session.dart`) называли одни и те же
/// записи одними и теми же строками и не зависели друг от друга.
abstract final class SnoSettingsKeys {
  /// Эталонное состояние — JSON (`ReferenceState.encode`).
  static const String reference = 'sno.reference_state';

  /// Когда устройство в последний раз сбросили к эталону: время в UTC.
  ///
  /// Попадает в журнал записи событием `state.reset`: по нему видно, с
  /// чистого ли состояния начинал тестировщик.
  static const String lastReset = 'sno.state_reset';

  /// Состояние незавершённой сессии записи — JSON
  /// (`SessionState.encode`); ключа нет — сессии нет (SNO-F-REC-01).
  static const String session = 'sno.session';

  /// Семёрки цифр кодов участников, уже встречавшихся на этом
  /// устройстве (SNO-ALG-CFG-03).
  ///
  /// Сброс к эталону их не трогает: код не должен повториться оттого,
  /// что устройство сбросили.
  static const String knownCodes = 'sno.known_codes';
}
