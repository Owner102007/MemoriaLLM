import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_calibration.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';

/// SNO-ALG-EYE-02: точки калибровки и проверки, их порядок, путь
/// слежения и слова итога — чистые правила, без экрана и спутника.
void main() {
  const EyeScreen screen = EyeScreen(
    width: 1920,
    height: 1080,
    widthMm: 527,
    heightMm: 296,
  );

  test('SNO-ALG-EYE-02: 13 точек калибровки, 9 проверки, 9 быстрых', () {
    expect(kCalibrationPoints, hasLength(13));
    expect(kCalibrationPoints.toSet(), hasLength(13));
    // Сетка 3×3 у краёв с отступом 8 % и четыре точки между ними.
    for (final (double, double) p in kCalibrationPoints.take(9)) {
      expect(<double>[0.08, 0.5, 0.92], contains(p.$1));
      expect(<double>[0.08, 0.5, 0.92], contains(p.$2));
    }
    expect(kCalibrationPoints.skip(9), <(double, double)>[
      (0.29, 0.29),
      (0.71, 0.29),
      (0.29, 0.71),
      (0.71, 0.71),
    ]);
    expect(kValidationPoints, hasLength(9));
    for (final (double, double) p in kValidationPoints) {
      expect(<double>[0.2, 0.5, 0.8], contains(p.$1));
      expect(<double>[0.2, 0.5, 0.8], contains(p.$2));
    }
    expect(kQuickPoints, kCalibrationPoints.take(9).toList());
  });

  test('SNO-ALG-EYE-02: порядок точек по коду участника — тот же, что у '
      'второй реализации на Python', () {
    // Числа посчитаны независимой реализацией FNV-1a и Mulberry32 на
    // Python при подготовке шага 28.
    final int seed = eyeSeedOf('12345674');
    expect(seed, 2114350656);
    expect(
      calibrationSequence(
        EyeCalibrationKind.full,
        seed,
      ).map((EyeTargetPoint p) => p.id),
      <String>[
        'c4',
        'c9',
        'c5',
        'c6',
        'c8',
        'c1',
        'c0',
        'c7',
        'c12',
        'c11',
        'c10',
        'c3',
        'c2',
      ],
    );
    expect(
      calibrationSequence(
        EyeCalibrationKind.quick,
        seed,
      ).map((EyeTargetPoint p) => p.id),
      <String>['q2', 'q1', 'q4', 'q7', 'q6', 'q5', 'q8', 'q3', 'q0'],
    );
    expect(validationSequence(seed).map((EyeTargetPoint p) => p.id), <String>[
      'v0',
      'v4',
      'v3',
      'v2',
      'v1',
      'v7',
      'v5',
      'v6',
      'v8',
    ]);
    expect(eyeSeedOf('00000000'), 1641917084);
    // Точка — там, где её назвали: c9 — (0,29; 0,29) окна.
    final EyeTargetPoint c9 = calibrationSequence(
      EyeCalibrationKind.full,
      seed,
    )[1];
    expect(
      c9.at(const Size(1920, 1080)),
      const Offset(0.29 * 1920, 0.29 * 1080),
    );
    expect(c9.phase, EyeTargetPhase.calib);
  });

  test('SNO-ALG-EYE-02: путь слежения не быстрее 10°/с — для 527×296 мм на '
      '60 см это 16 с и 10,7 с', () {
    final PursuitPath path = pursuitPathFor(screen, 600);
    expect(path.txMs, 16000);
    expect(path.tyMs, 10667);
    expect(path.cx, 960);
    expect(path.cy, 540);
    expect(path.ax, closeTo(0.4 * 1920, 1e-9));
    expect(path.ay, closeTo(0.35 * 1080, 1e-9));
    final double speed = pursuitMaxSpeedDeg(path, screen, 600);
    expect(speed, lessThanOrEqualTo(10));
    expect(speed, greaterThan(9));
    // Ближе к экрану — тот же путь медленнее по времени.
    final PursuitPath near = pursuitPathFor(screen, 450);
    expect(near.txMs, greaterThan(path.txMs));
    expect(pursuitMaxSpeedDeg(near, screen, 450), lessThanOrEqualTo(10));
    expect(path.at(Duration.zero), const Offset(960, 540));
    final Offset quarter = path.at(const Duration(seconds: 4));
    expect(quarter.dx, closeTo(960 + 0.4 * 1920, 1e-6));
    expect(path.toJson(), <String, Object?>{
      'cx': 960.0,
      'cy': 540.0,
      'ax': 0.4 * 1920,
      'ay': 0.35 * 1080,
      'tx_ms': 16000,
      'ty_ms': 10667,
    });
  });

  test('SNO-F-EYE-01: итог словами — точность, сантиметры, худшая точка, '
      'попытка', () {
    final EyeValidation ok = EyeValidation.fromMessage(<String, Object?>{
      'accepted': true,
      'accuracy_deg': 2.24,
      'accuracy_cm': 2.31,
      'worst_deg': 4.06,
      'reason': null,
      'thresholds': <String, Object?>{'accept_deg': 2.5, 'worst_deg': 5.0},
    });
    expect(
      validationLine(ok, attempt: 1),
      'Точность 2,2° (≈ 2,3 см) · худшая точка 4,1° · попытка 1 из 3',
    );
    final EyeValidation bad = EyeValidation.fromMessage(<String, Object?>{
      'accepted': false,
      'accuracy_deg': 3.1,
      'accuracy_cm': 3.3,
      'worst_deg': 4.4,
      'reason': 'accuracy',
      'thresholds': <String, Object?>{'accept_deg': 2.5, 'worst_deg': 5.0},
    });
    expect(
      rejectAdvice(bad),
      'Точность 3,1° (порог — 2,5°) — поправьте посадку и свет',
    );
    final EyeValidation worst = EyeValidation.fromMessage(<String, Object?>{
      'accepted': false,
      'accuracy_deg': 1.9,
      'worst_deg': 6.0,
      'reason': 'worst',
    });
    expect(worst.reason, EyeRejectReason.worst);
    expect(rejectAdvice(worst), startsWith('Одна точка ушла на 6,0°'));
    final EyeValidation few = EyeValidation.fromMessage(<String, Object?>{
      'accepted': false,
      'reason': 'few_points',
    });
    expect(rejectAdvice(few), contains('мало видела глаза'));
    expect(validationLine(few, attempt: 3), 'попытка 3 из 3');
  });

  test('SNO-ALG-EYE-03: строки калибровки разбираются', () {
    final EyeSamples samples = EyeSamples.fromMessage(<String, Object?>{
      'counts': <String, Object?>{'c0': 40, 'c3': 2},
      'short': <Object?>['c3'],
      'face': 0.97,
    });
    expect(samples.counts, <String, int>{'c0': 40, 'c3': 2});
    expect(samples.short, <String>['c3']);
    expect(samples.face, 0.97);
    final EyeFit fit = EyeFit.fromMessage(<String, Object?>{
      'model': 'krr',
      'cv_deg': 1.4,
      'cv_cm': 1.5,
      'latency_ms': 70.0,
      'points': 12,
      'excluded': <Object?>['c5'],
    });
    expect(fit.model, 'krr');
    expect(fit.latencyMs, 70);
    expect(fit.excluded, <String>['c5']);
    final EyeGaze? gaze = EyeGaze.fromMessage(<String, Object?>{
      'g': <Object?>[100.5, 200],
      's': <Object?>[101, 199],
      'ok': true,
      't': 123,
    });
    expect(gaze!.ok, isTrue);
    expect(gaze.raw, (100.5, 200.0));
    expect(gaze.smooth, (101.0, 199.0));
    final EyeGaze? lost = EyeGaze.fromMessage(<String, Object?>{
      'g': null,
      'ok': false,
      't': 124,
    });
    expect(lost!.ok, isFalse);
    expect(lost.smooth, isNull);
    expect(EyeGaze.fromMessage(<String, Object?>{'hb': 1}), isNull);
  });

  test('BUG-60: точки проверки точности — те же девять, свой порядок у '
      'каждой проверки, как у второй реализации на Python', () {
    // Числа посчитаны независимой реализацией FNV-1a и Mulberry32 на
    // Python при подготовке шага 29.
    final int seed = eyeSeedOf('12345674');
    final List<EyeTargetPoint> first = checkSequence(seed, 1);
    expect(first.map((EyeTargetPoint p) => p.id), <String>[
      'k7',
      'k4',
      'k2',
      'k6',
      'k0',
      'k5',
      'k3',
      'k8',
      'k1',
    ]);
    expect(checkSequence(seed, 2).map((EyeTargetPoint p) => p.id), <String>[
      'k8',
      'k6',
      'k7',
      'k1',
      'k2',
      'k5',
      'k4',
      'k0',
      'k3',
    ]);
    expect(
      first.every((EyeTargetPoint p) => p.phase == EyeTargetPhase.check),
      isTrue,
    );
    // Точка k7 — та же, что v7 проверки сразу после калибровки.
    expect(first.first.fx, kValidationPoints[7].$1);
    expect(first.first.fy, kValidationPoints[7].$2);
    expect(kHeadPoint.phase, EyeTargetPhase.head);
    expect(kHeadPoint.at(const Size(1920, 1080)), const Offset(960, 540));
    expect(EyeTargetPhase.head.wire, 'head');
    expect(EyeTargetPhase.check.wire, 'check');
    expect(kHeadPhaseTime, const Duration(seconds: 12));
  });

  test('BUG-60: голова на проверке словами', () {
    expect(headMoveWords(const EyeHeadMove()), 'голова как при калибровке');
    expect(
      headMoveWords(const EyeHeadMove(turnDeg: 6.2, dzPct: -8.4)),
      'голова повёрнута вправо на 6°, ближе на 8 %',
    );
    expect(
      headMoveWords(
        const EyeHeadMove(
          turnDeg: -2,
          tiltDeg: 3.4,
          rollDeg: -2.6,
          dxMm: 18,
          dyMm: -12,
          dzPct: 5,
        ),
      ),
      'голова повёрнута влево на 2°, наклонена вниз на 3°, к левому плечу '
      'на 3°, сдвинута на 2,2 см, дальше на 5 %',
    );
    // Мелочи — не в счёт: меньше 1,5°, 2° к плечу, 1 см и 3 %.
    expect(
      headMoveWords(
        const EyeHeadMove(
          turnDeg: 1.4,
          tiltDeg: -1.2,
          rollDeg: 1.9,
          dxMm: 6,
          dyMm: 5,
          dzPct: -2.9,
        ),
      ),
      'голова как при калибровке',
    );
  });

  test('BUG-60: итог проверки точности словами — главный способ, голова, '
      'все способы рядом', () {
    final EyeAccuracy a = EyeAccuracy.fromMessage(<String, Object?>{
      'reply': 'checked',
      'n': 2,
      'accuracy_deg': 1.94,
      'accuracy_cm': 1.96,
      'worst_deg': 3.2,
      'start_deg': 1.42,
      'head_model': 'phase',
      'variants': <String, Object?>{
        'learned': <String, Object?>{'accuracy_deg': 3.81},
        'geometry': <String, Object?>{'accuracy_deg': 2.04},
        'phase': <String, Object?>{'accuracy_deg': 1.94},
      },
      'head': <String, Object?>{
        'turn_deg': 6.2,
        'tilt_deg': 0.4,
        'roll_deg': 0.3,
        'dx_mm': 2.0,
        'dy_mm': -1.0,
        'dz_pct': -8.4,
      },
    });
    expect(a.n, 2);
    expect(a.headModel, 'phase');
    expect(
      checkLine(a),
      'Проверка 2: 1,9° (≈ 2,0 см) · голова повёрнута вправо на 6°, ближе на '
      '8 %',
    );
    expect(
      endCheckLine(a),
      'В конце: 1,9° (≈ 2,0 см), в начале 1,4° · голова повёрнута вправо на '
      '6°, ближе на 8 %',
    );
    expect(
      variantsLine(a),
      'Способы: по движению головы 1,9° · по геометрии 2,0° · прежний 3,8°',
    );
    final EyeAccuracy empty = EyeAccuracy.fromMessage(<String, Object?>{
      'n': 1,
      'accuracy_deg': null,
    });
    expect(checkLine(empty), 'Проверка 1: камера мало видела глаза');
    expect(variantsLine(empty), isNull);
  });

  test('BUG-60: фаза движения головы в итоге калибровки', () {
    EyeFit fit(Map<String, Object?>? head) =>
        EyeFit.fromMessage(<String, Object?>{
          'model': 'ridge',
          'cv_deg': 1.2,
          'points': 9,
          'head_model': 'phase',
          'head': ?head,
        });
    expect(headPhaseLine(fit(null)), isNull);
    expect(fit(null).headModel, 'phase');
    expect(
      headPhaseLine(
        fit(<String, Object?>{
          'frames': 340,
          'moved': true,
          'turn_deg': 17.3,
          'tilt_deg': 13.4,
        }),
      ),
      'Движение головы: влево-вправо 17°, вверх-вниз 13°',
    );
    expect(
      headPhaseLine(
        fit(<String, Object?>{'frames': 300, 'moved': false, 'turn_deg': 0.8}),
      ),
      'Голова почти не двигалась — поправка только по геометрии',
    );
    expect(
      headPhaseLine(fit(<String, Object?>{'frames': 0, 'moved': false})),
      'Движение головы не записалось — поправка только по геометрии',
    );
  });
}
