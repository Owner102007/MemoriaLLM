/// Место записи айтрекера: камера, монитор, размер экрана, расстояние и
/// итог самопроверки (SNO-F-EYE-05).
///
/// Место — настройка устройства, а не сессии: делается один раз на ПК и
/// лежит в настройках (`sno.eye_place`). Сброс к эталону его не трогает:
/// это не след участника.
///
/// Чистый Dart: разбор, запись и арифметика размера экрана.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'eye_protocol.dart';

/// Версия записи места.
const String kEyePlaceSchema = 'sno2026-eyeplace/1';

/// Банковская карта ID-1 (ISO/IEC 7810): ширина, мм.
const double kCardWidthMm = 85.60;

/// Банковская карта ID-1: высота, мм.
const double kCardHeightMm = 53.98;

/// Шаг подгонки рамки под карту: на столько миллиметров карты сдвигается
/// край рамки одним нажатием стрелки.
const double kCardStepMm = 0.1;

/// Расстояние от глаз до экрана по умолчанию, мм (решение Т2: 55–65 см).
const int kDefaultDistanceMm = 600;

/// Наименьшее и наибольшее расстояние, которое можно ввести, мм.
const int kMinDistanceMm = 300;

/// Наибольшее расстояние, мм.
const int kMaxDistanceMm = 1200;

/// Откуда известен размер экрана.
enum ScreenSizeSource {
  /// Сведения системы: часто неверны, только подсказка.
  system('system', 'по сведениям системы'),

  /// Банковская карта, приложенная к экрану.
  card('card', 'по банковской карте'),

  /// Диагональ, введённая руками.
  diagonal('diagonal', 'по диагонали');

  const ScreenSizeSource(this.wire, this.words);

  /// Имя в записи.
  final String wire;

  /// Словами.
  final String words;

  /// Источник по имени; незнакомое — `null`.
  static ScreenSizeSource? named(Object? wire) {
    for (final ScreenSizeSource source in values) {
      if (source.wire == wire) {
        return source;
      }
    }
    return null;
  }
}

/// Пикселей на миллиметр по рамке карты: ширина рамки в физических
/// пикселях, подогнанная под карту, делится на ширину карты.
double pxPerMmFromCard(double cardWidthPx) => cardWidthPx / kCardWidthMm;

/// Пикселей на миллиметр по диагонали в дюймах и размеру экрана в
/// пикселях. Пиксели квадратные: у мониторов, на которых идёт запись,
/// иначе не бывает.
double pxPerMmFromDiagonal({
  required double inches,
  required int widthPx,
  required int heightPx,
}) {
  final double diagonalPx = math.sqrt(
    widthPx * widthPx + heightPx * heightPx.toDouble(),
  );
  return diagonalPx / (inches * 25.4);
}

/// Подгонка рамки под карту на [steps] шагов по [kCardStepMm]: рамка
/// шириной в карту по оценке [pxPerMm] становится шире (или уже) на
/// `steps × 0,1 мм` карты — новая оценка пикселей на миллиметр.
double nudgePxPerMm(double pxPerMm, int steps) {
  final double width = kCardWidthMm + steps * kCardStepMm;
  return pxPerMm * width / kCardWidthMm;
}

/// Наименьшая и наибольшая разумная оценка, пикселей на мм: от
/// телевизора (≈ 1) до плотного ноутбука (≈ 12).
const double kMinPxPerMm = 1;

/// Наибольшая разумная оценка, пикселей на мм.
const double kMaxPxPerMm = 16;

/// Место записи.
class EyePlace {
  /// Создаёт место.
  const EyePlace({
    required this.camera,
    required this.monitor,
    required this.monitorName,
    required this.widthPx,
    required this.heightPx,
    required this.pxPerMm,
    required this.sizeSource,
    required this.distanceMm,
    required this.verdict,
    required this.checkedAt,
    this.mode,
    this.fps,
    this.checks = const <EyeCheckRow>[],
  });

  /// Место из записи в настройках; `null` — записи нет или она не
  /// читается.
  static EyePlace? decode(String? text) {
    if (text == null || text.isEmpty) {
      return null;
    }
    try {
      final Object? raw = jsonDecode(text);
      if (raw is! Map<String, Object?> || raw['schema'] != kEyePlaceSchema) {
        return null;
      }
      final EyeCamera? camera = EyeCamera.fromJson(raw['camera']);
      final Object? monitor = raw['monitor'];
      final Object? screen = raw['screen'];
      if (camera == null ||
          monitor is! Map<String, Object?> ||
          screen is! Map<String, Object?>) {
        return null;
      }
      final Object? id = monitor['id'];
      final Object? name = monitor['name'];
      final Object? w = screen['w_px'];
      final Object? h = screen['h_px'];
      final Object? ppm = screen['px_per_mm'];
      final ScreenSizeSource? source = ScreenSizeSource.named(screen['source']);
      final Object? distance = raw['distance_mm'];
      final Object? checked = raw['checked_at'];
      final Object? mode = raw['mode'];
      final Object? fps = raw['fps'];
      final Object? checks = raw['checks'];
      if (id is! String ||
          w is! int ||
          h is! int ||
          ppm is! num ||
          ppm <= 0 ||
          source == null ||
          distance is! int ||
          checked is! String) {
        return null;
      }
      final DateTime? at = DateTime.tryParse(checked);
      if (at == null) {
        return null;
      }
      return EyePlace(
        camera: camera,
        monitor: id,
        monitorName: name is String ? name : '',
        widthPx: w,
        heightPx: h,
        pxPerMm: ppm.toDouble(),
        sizeSource: source,
        distanceMm: distance,
        verdict: EyeVerdict.named(raw['verdict']),
        checkedAt: at,
        mode:
            mode is List<Object?> &&
                mode.length == 2 &&
                mode.every((Object? v) => v is int)
            ? <int>[mode[0] as int, mode[1] as int]
            : null,
        fps: fps is num ? fps.toDouble() : null,
        checks: <EyeCheckRow>[
          if (checks is List<Object?>)
            for (final Object? row in checks) ?EyeCheckRow.fromJson(row),
        ],
      );
    } on FormatException {
      return null;
    }
  }

  /// Камера над экраном.
  final EyeCamera camera;

  /// Монитор, на котором идёт запись: имя устройства.
  final String monitor;

  /// Имя монитора словами; может быть пустым.
  final String monitorName;

  /// Ширина монитора в физических пикселях.
  final int widthPx;

  /// Высота монитора в физических пикселях.
  final int heightPx;

  /// Пикселей на миллиметр экрана.
  final double pxPerMm;

  /// Откуда известен размер экрана.
  final ScreenSizeSource sizeSource;

  /// Расстояние от глаз до экрана, мм.
  final int distanceMm;

  /// Итог самопроверки.
  final EyeVerdict verdict;

  /// Когда место проверено.
  final DateTime checkedAt;

  /// Режим камеры, выбранный самопроверкой: `[ширина, высота]`.
  final List<int>? mode;

  /// Частота кадров с распознаванием на самопроверке.
  final double? fps;

  /// Строки самопроверки.
  final List<EyeCheckRow> checks;

  /// Ширина экрана, мм.
  double get widthMm => widthPx / pxPerMm;

  /// Высота экрана, мм.
  double get heightMm => heightPx / pxPerMm;

  /// Запись для настроек.
  String encode() => jsonEncode(toJson());

  /// Место как объект JSON: в настройках и в сведениях записи.
  Map<String, Object?> toJson() => <String, Object?>{
    'schema': kEyePlaceSchema,
    'camera': camera.toJson(),
    if (mode != null) 'mode': mode,
    if (fps != null) 'fps': double.parse(fps!.toStringAsFixed(1)),
    'monitor': <String, Object?>{'id': monitor, 'name': monitorName},
    'screen': <String, Object?>{
      'w_px': widthPx,
      'h_px': heightPx,
      'px_per_mm': double.parse(pxPerMm.toStringAsFixed(4)),
      'w_mm': double.parse(widthMm.toStringAsFixed(1)),
      'h_mm': double.parse(heightMm.toStringAsFixed(1)),
      'source': sizeSource.wire,
    },
    'distance_mm': distanceMm,
    'verdict': verdict.wire,
    'checked_at': checkedAt.toUtc().toIso8601String(),
    'checks': <Object?>[for (final EyeCheckRow row in checks) row.toJson()],
  };

  /// Место одной строкой: «камера Logitech C920, 1920×1080, 30 к/с;
  /// экран 527×296 мм; 60 см; проверено 08.10».
  String get summary {
    final List<int>? m = mode;
    final double? f = fps;
    final DateTime local = checkedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return <String>[
      <String>[
        'камера ${camera.name}',
        if (m != null) '${m[0]}×${m[1]}',
        if (f != null) '${f.round()} к/с',
      ].join(', '),
      'экран ${widthMm.round()}×${heightMm.round()} мм',
      '${(distanceMm / 10).round()} см',
      'проверено ${two(local.day)}.${two(local.month)}',
    ].join('; ');
  }
}
