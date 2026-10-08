/// Калибровка айтрекера — чистая часть приложения (SNO-ALG-EYE-02,
/// SNO-F-EYE-01, SNO-F-EYE-03): где стоят точки, в каком порядке они
/// идут, куда ведёт точку слежение и как итог называется словами.
///
/// Точки рисует приложение, считает спутник. Порядок точек перемешан
/// тем же правилом, что пункты теста нагрузки (FNV-1a и Mulberry32):
/// один код участника даёт один порядок на любом ПК, а разбор может
/// пересчитать его без приложения.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../clt/scenario.dart' show cltPermutation, cltSeedOf;
import 'eye_protocol.dart';

/// Точки калибровки — 13, в долях окна: сетка 3×3 у краёв с отступом
/// 8 % и четыре точки между ними.
const List<(double, double)> kCalibrationPoints = <(double, double)>[
  (0.08, 0.08),
  (0.5, 0.08),
  (0.92, 0.08),
  (0.08, 0.5),
  (0.5, 0.5),
  (0.92, 0.5),
  (0.08, 0.92),
  (0.5, 0.92),
  (0.92, 0.92),
  (0.29, 0.29),
  (0.71, 0.29),
  (0.29, 0.71),
  (0.71, 0.71),
];

/// Точки быстрой калибровки «Проверки айтрекера» — 9: сетка 3×3 у
/// краёв, как у полной.
const List<(double, double)> kQuickPoints = <(double, double)>[
  (0.08, 0.08),
  (0.5, 0.08),
  (0.92, 0.08),
  (0.08, 0.5),
  (0.5, 0.5),
  (0.92, 0.5),
  (0.08, 0.92),
  (0.5, 0.92),
  (0.92, 0.92),
];

/// Точки проверки — 9: сетка 20 / 50 / 80 % окна.
const List<(double, double)> kValidationPoints = <(double, double)>[
  (0.2, 0.2),
  (0.5, 0.2),
  (0.8, 0.2),
  (0.2, 0.5),
  (0.5, 0.5),
  (0.8, 0.5),
  (0.2, 0.8),
  (0.5, 0.8),
  (0.8, 0.8),
];

/// Сколько стоит точка калибровки.
const Duration kCalibrationPointTime = Duration(seconds: 2);

/// Сколько стоит точка проверки.
const Duration kValidationPointTime = Duration(milliseconds: 1500);

/// Сколько идёт слежение за движущейся точкой.
const Duration kPursuitTime = Duration(seconds: 20);

/// Сколько идёт фаза движения головы (BUG-60): точка в середине, человек
/// водит головой, глядя на неё, — первые [kHeadTurnTime] влево-вправо,
/// остальное вверх-вниз.
const Duration kHeadPhaseTime = Duration(seconds: 12);

/// Сколько из фазы движения головы — влево-вправо.
const Duration kHeadTurnTime = Duration(seconds: 6);

/// Подсказка перед фазой движения головы.
const String kHeadIntro = 'Теперь смотрите на точку и медленно водите головой';

/// Подсказка первой половины фазы движения головы.
const String kHeadHintTurn =
    'Смотрите на точку и медленно поворачивайте голову\n← влево-вправо →';

/// Подсказка второй половины.
const String kHeadHintNod =
    'Смотрите на точку и медленно наклоняйте голову\n↑ вверх-вниз ↓';

/// Подсказка перед точками проверки точности без новой калибровки.
const String kCheckIntro = 'Смотрите на точки — проверка точности';

/// Сколько висит подсказка перед точками и перед слежением.
const Duration kIntroTime = Duration(milliseconds: 1500);

/// За сколько кольцо сжимается к точке.
const Duration kRingTime = Duration(milliseconds: 600);

/// Сколько попыток калибровки: первая и два повтора (SNO-F-EYE-01).
const int kCalibrationAttempts = 3;

/// Поперечник точки, логических пикселей.
const double kTargetDot = 16;

/// Поперечник кольца в начале, логических пикселей.
const double kTargetRing = 56;

/// Наибольшая угловая скорость точки слежения, градусов в секунду.
const double kPursuitMaxSpeedDeg = 10;

/// Размах слежения по x и по y, в долях окна.
const double kPursuitSpanX = 0.4;

/// Размах слежения по y, в долях окна.
const double kPursuitSpanY = 0.35;

/// Какая калибровка: полная — как у участника; быстрая — девять точек
/// без слежения и без проверки, только для глаза экспериментатора.
enum EyeCalibrationKind {
  /// Полная.
  full('full'),

  /// Быстрая.
  quick('quick');

  const EyeCalibrationKind(this.wire);

  /// Имя в обмене.
  final String wire;
}

/// Фаза точки: калибровка, слежение, проверка.
enum EyeTargetPhase {
  /// Точка калибровки.
  calib('calib'),

  /// Движущаяся точка.
  pursuit('pursuit'),

  /// Точка проверки.
  validate('validate'),

  /// Точка фазы движения головы (BUG-60).
  head('head'),

  /// Точка проверки точности без новой калибровки (BUG-60).
  check('check');

  const EyeTargetPhase(this.wire);

  /// Имя в обмене.
  final String wire;
}

/// Неподвижная точка.
class EyeTargetPoint {
  /// Создаёт точку.
  const EyeTargetPoint({
    required this.id,
    required this.fx,
    required this.fy,
    required this.phase,
  });

  /// Имя точки: у одной и той же точки при повторе оно то же.
  final String id;

  /// Место по x, доля окна.
  final double fx;

  /// Место по y, доля окна.
  final double fy;

  /// Фаза.
  final EyeTargetPhase phase;

  /// Место в окне размера [window], логических пикселей.
  Offset at(Size window) => Offset(fx * window.width, fy * window.height);

  @override
  bool operator ==(Object other) =>
      other is EyeTargetPoint &&
      other.id == id &&
      other.fx == fx &&
      other.fy == fy &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(id, fx, fy, phase);
}

/// Зерно порядка точек по коду участника; у «Проверки айтрекера» кода
/// нет, и зерно берётся случайное.
int eyeSeedOf(String participant) => cltSeedOf('$participant/eye/calibration');

List<EyeTargetPoint> _ordered(
  List<(double, double)> points,
  String prefix,
  EyeTargetPhase phase,
  int seed,
) {
  final List<int> order = cltPermutation(points.length, seed);
  return <EyeTargetPoint>[
    for (final int i in order)
      EyeTargetPoint(
        id: '$prefix$i',
        fx: points[i].$1,
        fy: points[i].$2,
        phase: phase,
      ),
  ];
}

/// Точки калибровки в порядке показа.
List<EyeTargetPoint> calibrationSequence(EyeCalibrationKind kind, int seed) {
  return kind == EyeCalibrationKind.full
      ? _ordered(kCalibrationPoints, 'c', EyeTargetPhase.calib, seed)
      : _ordered(kQuickPoints, 'q', EyeTargetPhase.calib, seed);
}

/// Точки проверки в порядке показа: порядок свой, не как у калибровки.
List<EyeTargetPoint> validationSequence(int seed) {
  return _ordered(
    kValidationPoints,
    'v',
    EyeTargetPhase.validate,
    (seed ^ 0x5bd1e995) & 0xFFFFFFFF,
  );
}

/// Точка фазы движения головы — середина окна.
const EyeTargetPoint kHeadPoint = EyeTargetPoint(
  id: 'head',
  fx: 0.5,
  fy: 0.5,
  phase: EyeTargetPhase.head,
);

/// Точки проверки точности [n] без новой калибровки: те же девять, что у
/// проверки сразу после неё, в своём порядке у каждой проверки.
List<EyeTargetPoint> checkSequence(int seed, int n) {
  return _ordered(
    kValidationPoints,
    'k',
    EyeTargetPhase.check,
    (seed ^ 0x2545f491 ^ (n * 0x9e3779b9)) & 0xFFFFFFFF,
  );
}

/// Путь движущейся точки — фигура Лиссажу с отношением периодов 3 : 2.
class PursuitPath {
  /// Создаёт путь.
  const PursuitPath({
    required this.cx,
    required this.cy,
    required this.ax,
    required this.ay,
    required this.txMs,
    required this.tyMs,
  });

  /// Середина по x, логических пикселей.
  final double cx;

  /// Середина по y.
  final double cy;

  /// Размах по x.
  final double ax;

  /// Размах по y.
  final double ay;

  /// Период по x, мс.
  final int txMs;

  /// Период по y, мс.
  final int tyMs;

  /// Где точка через [elapsed] после появления.
  Offset at(Duration elapsed) {
    final double t = elapsed.inMicroseconds / 1e6;
    return Offset(
      cx + ax * math.sin(2 * math.pi * t * 1000 / txMs),
      cy + ay * math.sin(2 * math.pi * t * 1000 / tyMs),
    );
  }

  /// Поле `path` команды `target`.
  Map<String, Object?> toJson() => <String, Object?>{
    'cx': cx,
    'cy': cy,
    'ax': ax,
    'ay': ay,
    'tx_ms': txMs,
    'ty_ms': tyMs,
  };
}

/// Путь слежения для окна [screen] на расстоянии [distanceMm]: размах
/// 0,4 ширины и 0,35 высоты окна; периоды — такие, чтобы точка нигде не
/// шла быстрее [kPursuitMaxSpeedDeg]. Быстрее всего точка в середине, где
/// обе скорости наибольшие разом; период по x — вверх до целой секунды.
/// Для экрана 527×296 мм на 60 см — 16 с и 10,7 с.
PursuitPath pursuitPathFor(EyeScreen screen, int distanceMm) {
  final double axMm = kPursuitSpanX * screen.widthMm;
  final double ayMm = kPursuitSpanY * screen.heightMm;
  final double limit = kPursuitMaxSpeedDeg * math.pi / 180 * distanceMm;
  final double tx =
      (2 * math.pi * math.sqrt(axMm * axMm + 2.25 * ayMm * ayMm) / limit)
          .ceilToDouble();
  final double txS = math.max(4, tx);
  return PursuitPath(
    cx: screen.width / 2,
    cy: screen.height / 2,
    ax: kPursuitSpanX * screen.width,
    ay: kPursuitSpanY * screen.height,
    txMs: (txS * 1000).round(),
    // Вверх, а не к ближайшему: короче период — быстрее точка.
    tyMs: (txS * 1000 / 1.5).ceil(),
  );
}

/// Наибольшая угловая скорость точки пути [path], градусов в секунду, —
/// в середине экрана.
double pursuitMaxSpeedDeg(PursuitPath path, EyeScreen screen, int distanceMm) {
  final double mmPerPxX = screen.widthMm / screen.width;
  final double mmPerPxY = screen.heightMm / screen.height;
  final double vx = path.ax * mmPerPxX * 2 * math.pi / (path.txMs / 1000);
  final double vy = path.ay * mmPerPxY * 2 * math.pi / (path.tyMs / 1000);
  return math.sqrt(vx * vx + vy * vy) / distanceMm * 180 / math.pi;
}

/// Число с одним знаком после запятой: «2,4».
String eyeNumber(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

/// Строка итога проверки (кадр SNO-SCR-07.2): «Точность 2,2° (≈ 2,3 см) ·
/// худшая точка 4,1° · попытка 1 из 3».
String validationLine(
  EyeValidation v, {
  required int attempt,
  int attempts = kCalibrationAttempts,
}) {
  final double? acc = v.accuracyDeg;
  final double? cm = v.accuracyCm;
  final double? worst = v.worstDeg;
  final String inCm = cm == null ? '' : ' (≈ ${eyeNumber(cm)} см)';
  return <String>[
    if (acc != null) 'Точность ${eyeNumber(acc)}°$inCm',
    if (worst != null) 'худшая точка ${eyeNumber(worst)}°',
    'попытка $attempt из $attempts',
  ].join(' · ');
}

/// Что сказать, когда калибровка не принята.
String rejectAdvice(EyeValidation v) {
  final double? acc = v.accuracyDeg;
  return switch (v.reason) {
    EyeRejectReason.worst =>
      'Одна точка ушла на ${eyeNumber(v.worstDeg ?? 0)}° (порог — '
          '${eyeNumber(v.worstMaxDeg)}°) — поправьте посадку и свет',
    EyeRejectReason.fewPoints =>
      'Камера мало видела глаза на точках проверки — поправьте посадку '
          'и свет',
    _ =>
      'Точность ${eyeNumber(acc ?? 0)}° (порог — ${eyeNumber(v.acceptDeg)}°) — '
          'поправьте посадку и свет',
  };
}

/// Голова на проверке против калибровки словами (BUG-60): «голова
/// повёрнута вправо на 6°, наклонена вниз на 3°, сдвинута на 2 см, ближе
/// на 8 %»; ничего заметного — «голова как при калибровке».
String headMoveWords(EyeHeadMove m) {
  String deg(double v) => '${v.abs().round()}°';
  final double shiftMm = math.sqrt(m.dxMm * m.dxMm + m.dyMm * m.dyMm);
  final List<String> parts = <String>[
    if (m.turnDeg.abs() >= 1.5)
      'повёрнута ${m.turnDeg > 0 ? 'вправо' : 'влево'} на ${deg(m.turnDeg)}',
    if (m.tiltDeg.abs() >= 1.5)
      'наклонена ${m.tiltDeg > 0 ? 'вниз' : 'вверх'} на ${deg(m.tiltDeg)}',
    if (m.rollDeg.abs() >= 2)
      'к ${m.rollDeg > 0 ? 'правому' : 'левому'} плечу на ${deg(m.rollDeg)}',
    if (shiftMm >= 10) 'сдвинута на ${eyeNumber(shiftMm / 10)} см',
    if (m.dzPct.abs() >= 3)
      '${m.dzPct < 0 ? 'ближе' : 'дальше'} на ${m.dzPct.abs().round()} %',
  ];
  return parts.isEmpty ? 'голова как при калибровке' : 'голова ${parts.join(', ')}';
}

String _accuracy(EyeAccuracy a) {
  final double? acc = a.accuracyDeg;
  final double? cm = a.accuracyCm;
  if (acc == null) {
    return 'камера мало видела глаза';
  }
  return '${eyeNumber(acc)}°${cm == null ? '' : ' (≈ ${eyeNumber(cm)} см)'}';
}

/// Строка итога проверки точности из живого взгляда (кадр SNO-SCR-07.3):
/// «Проверка 2: 1,9° (≈ 1,9 см) · голова повёрнута вправо на 6°».
String checkLine(EyeAccuracy a) {
  final EyeHeadMove? head = a.head;
  return <String>[
    'Проверка ${a.n}: ${_accuracy(a)}',
    if (head != null) headMoveWords(head),
  ].join(' · ');
}

/// Строка проверки в конце пробной калибровки: «В конце: 2,1° (в начале
/// 1,4°) · голова как при калибровке».
String endCheckLine(EyeAccuracy a) {
  final double? start = a.startDeg;
  final EyeHeadMove? head = a.head;
  return <String>[
    'В конце: ${_accuracy(a)}'
        '${start == null ? '' : ', в начале ${eyeNumber(start)}°'}',
    if (head != null) headMoveWords(head),
  ].join(' · ');
}

/// Способы поправки на голову словами — по порядку показа.
const Map<String, String> kHeadModelNames = <String, String>{
  'phase': 'по движению головы',
  'geometry': 'по геометрии',
  'learned': 'прежний',
};

/// Точность всех способов поправки на голову (BUG-60): «Способы: по
/// движению головы 1,9° · по геометрии 2,0° · прежний 3,8°»; `null` —
/// спутник их не прислал.
String? variantsLine(EyeAccuracy a) {
  final List<String> parts = <String>[
    for (final MapEntry<String, String> e in kHeadModelNames.entries)
      if (a.variants[e.key] case final double v) '${e.value} ${eyeNumber(v)}°',
  ];
  return parts.isEmpty ? null : 'Способы: ${parts.join(' · ')}';
}

/// Как прошла фаза движения головы (итог калибровки, кадр SNO-SCR-07.2);
/// `null` — спутник о ней не сказал.
String? headPhaseLine(EyeFit fit) {
  final EyeHeadPhase? h = fit.headPhase;
  if (h == null) {
    return null;
  }
  if (h.frames == 0) {
    return 'Движение головы не записалось — поправка только по геометрии';
  }
  if (!h.moved) {
    return 'Голова почти не двигалась — поправка только по геометрии';
  }
  return 'Движение головы: влево-вправо ${(h.turnDeg ?? 0).round()}°, '
      'вверх-вниз ${(h.tiltDeg ?? 0).round()}°';
}
