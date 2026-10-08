/// Время у приложения и спутника взгляда: сверка часов и признак
/// «спутник молчит» (SNO-ALG-EYE-03, шаги 3 и 7).
///
/// Чистые правила: часы и таймеры приходят снаружи, поэтому правило
/// проверяется на придуманных числах, а не на ожидании.
library;

/// Один обмен `sync`: приложение отправило в [sentUs], спутник
/// поставил свою метку [eyeUs], ответ пришёл в [receivedUs] — всё в
/// микросекундах QPC.
class SyncRound {
  /// Создаёт обмен.
  const SyncRound({
    required this.sentUs,
    required this.eyeUs,
    required this.receivedUs,
  });

  /// Когда приложение отправило запрос.
  final int sentUs;

  /// Метка спутника.
  final int eyeUs;

  /// Когда пришёл ответ.
  final int receivedUs;

  /// Время туда и обратно.
  int get rttUs => receivedUs - sentUs;

  /// Смещение часов спутника от часов приложения: метка спутника минус
  /// середина обмена. Округляется к меньшему, чтобы правило давало одно
  /// и то же число на любом устройстве.
  int get offsetUs => eyeUs - ((sentUs + receivedUs) ~/ 2);
}

/// Итог рукопожатия: обмен с наименьшим временем ответа — как в NTP.
class SyncResult {
  /// Создаёт итог.
  const SyncResult({
    required this.offsetUs,
    required this.rttUs,
    required this.atUs,
    required this.rounds,
  });

  /// Итог по обменам [rounds]; `null` — обменов нет.
  ///
  /// Берётся обмен с наименьшим временем ответа: у него середина обмена
  /// ближе всего к мигу, когда спутник ставил метку. При равном времени
  /// — более ранний: правило не зависит от порядка сравнения.
  static SyncResult? best(List<SyncRound> rounds) {
    SyncRound? best;
    for (final SyncRound round in rounds) {
      if (round.rttUs < 0) {
        continue;
      }
      if (best == null || round.rttUs < best.rttUs) {
        best = round;
      }
    }
    if (best == null) {
      return null;
    }
    return SyncResult(
      offsetUs: best.offsetUs,
      rttUs: best.rttUs,
      atUs: (best.sentUs + best.receivedUs) ~/ 2,
      rounds: rounds.length,
    );
  }

  /// Смещение часов спутника, мкс. На Windows оба процесса читают один
  /// QPC, и ожидаемое смещение — ноль ± половина времени ответа.
  final int offsetUs;

  /// Время ответа у лучшего обмена, мкс.
  final int rttUs;

  /// Миг сверки по часам приложения — середина лучшего обмена, мкс QPC.
  final int atUs;

  /// Сколько обменов было.
  final int rounds;

  /// Погрешность смещения — половина времени ответа, мкс.
  int get errorUs => rttUs ~/ 2;
}

/// Сколько обменов при открытии связи.
const int kSyncRoundsOpen = 15;

/// Сколько обменов раз в минуту.
const int kSyncRoundsMinute = 5;

/// Как часто сверяются часы во время записи.
const Duration kSyncEvery = Duration(minutes: 1);

/// Как часто приложение проверяет, не молчит ли спутник.
const Duration kEyeTick = Duration(seconds: 1);

/// Сколько молчания спутника считается молчанием на самом деле.
const int kSilenceMs = 10000;

/// Задержка тика сверх его секунды, после которой молчание спутника не
/// считается: подвисало само приложение, и его сердцебиения просто
/// лежат непрочитанными. Мелкие опоздания таймера (на Windows шаг
/// таймера — около 16 мс) подвисанием не считаются.
const int kAppStallMs = 1000;

/// Ждёт ли спутник, пока его снимут: «сердцебиения нет [kSilenceMs], а
/// таймер приложения всё это время шёл без задержек больше
/// [kAppStallMs] сверх своей секунды» (SNO-ALG-EYE-03, шаг 3).
///
/// Приложение кормит правило каждым своим тиком ([tick]) и каждым
/// сердцебиением спутника ([beat]); время — монотонные миллисекунды.
/// Подвисло приложение — ожидание начинается заново: сердцебиения,
/// может быть, лежат в канале.
class SilenceWatch {
  /// Создаёт правило; [nowMs] — миг, с которого ждут первого
  /// сердцебиения.
  SilenceWatch(int nowMs) : _since = nowMs, _lastTick = nowMs;

  int _since;
  int _lastTick;

  /// Пришло сердцебиение.
  void beat(int nowMs) {
    _since = nowMs;
    _lastTick = nowMs;
  }

  /// Тик таймера приложения. `true` — спутник молчит на самом деле.
  bool tick(int nowMs) {
    if (nowMs - _lastTick > kEyeTick.inMilliseconds + kAppStallMs) {
      // Подвисало приложение: молчание считается с этого тика.
      _since = nowMs;
    }
    _lastTick = nowMs;
    return nowMs - _since >= kSilenceMs;
  }
}

/// Сколько раз за запись спутник поднимается заново, прежде чем
/// приложение сдаётся (SNO-F-EYE-04).
const int kEyeRestarts = 3;

/// Сколько строк мусора подряд — повод перезапустить спутник.
const int kEyeGarbageInRow = 3;
