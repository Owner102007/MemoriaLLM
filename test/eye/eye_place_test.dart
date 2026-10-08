import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/eye/eye_place.dart';
import 'package:memoria/sno/eye/eye_protocol.dart';
import 'package:memoria/sno/eye/eye_window.dart';
import 'package:memoria/sno/eye/place_screen.dart';

/// SNO-F-EYE-05: место записи — запись, размер экрана и строка «окно».
void main() {
  final EyePlace place = EyePlace(
    camera: const EyeCamera(
      index: 0,
      name: 'Logitech C920',
      path: r'\\?\usb#vid_046d',
    ),
    monitor: r'\\.\DISPLAY1',
    monitorName: 'DELL P2419H',
    widthPx: 1920,
    heightPx: 1080,
    pxPerMm: 1920 / 527,
    sizeSource: ScreenSizeSource.card,
    distanceMm: 600,
    verdict: EyeVerdict.warn,
    checkedAt: DateTime.utc(2026, 10, 8, 12),
    mode: const <int>[1920, 1080],
    fps: 29.8,
    checks: const <EyeCheckRow>[
      EyeCheckRow(
        id: 'iris',
        verdict: EyeVerdict.warn,
        text: 'Мелко',
        value: 16.0,
      ),
    ],
  );

  group('SNO-F-EYE-05: запись места', () {
    test('SNO-F-EYE-05: место читается таким, каким записано', () {
      final EyePlace back = EyePlace.decode(place.encode())!;
      expect(back.camera, place.camera);
      expect(back.monitor, place.monitor);
      expect(back.monitorName, 'DELL P2419H');
      expect(back.widthPx, 1920);
      expect(back.heightPx, 1080);
      expect(back.pxPerMm, closeTo(place.pxPerMm, 1e-4));
      expect(back.sizeSource, ScreenSizeSource.card);
      expect(back.distanceMm, 600);
      expect(back.verdict, EyeVerdict.warn);
      expect(back.checkedAt, place.checkedAt);
      expect(back.mode, <int>[1920, 1080]);
      expect(back.fps, 29.8);
      expect(back.checks.single.id, 'iris');
      expect(back.encode(), place.encode());
    });

    test('SNO-F-EYE-05: чужая или испорченная запись — места нет', () {
      expect(EyePlace.decode(null), isNull);
      expect(EyePlace.decode(''), isNull);
      expect(EyePlace.decode('{'), isNull);
      expect(EyePlace.decode('{"schema":"другая/1"}'), isNull);
      expect(
        EyePlace.decode(
          place.encode().replaceFirst('"distance_mm":600', '"distance_mm":"60"'),
        ),
        isNull,
      );
    });

    test('SNO-F-EYE-05: место одной строкой', () {
      expect(
        place.summary,
        'камера Logitech C920, 1920×1080, 30 к/с; экран 527×296 мм; 60 см; '
        'проверено ${place.checkedAt.toLocal().day.toString().padLeft(2, '0')}'
        '.${place.checkedAt.toLocal().month.toString().padLeft(2, '0')}',
      );
      expect(place.toJson()['screen'], <String, Object?>{
        'w_px': 1920,
        'h_px': 1080,
        'px_per_mm': 3.6433,
        'w_mm': 527.0,
        'h_mm': 296.4,
        'source': 'card',
      });
    });
  });

  group('SNO-F-EYE-05: размер экрана', () {
    test('SNO-F-EYE-05: по карте — пикселей на мм прямо', () {
      // Рамка в 312 физических пикселей легла по карте 85,6 мм.
      expect(pxPerMmFromCard(312), closeTo(3.6449, 1e-4));
      expect(1920 / pxPerMmFromCard(312), closeTo(526.8, 0.1));
    });

    test('SNO-F-EYE-05: по диагонали — 23,8″ 1920×1080 это 527×296 мм', () {
      final double ppm = pxPerMmFromDiagonal(
        inches: 23.8,
        widthPx: 1920,
        heightPx: 1080,
      );
      expect(1920 / ppm, closeTo(527, 0.5));
      expect(1080 / ppm, closeTo(296, 0.5));
    });

    test('SNO-F-EYE-05: шаг подгонки — 0,1 мм карты', () {
      const double ppm = 4;
      final double wider = nudgePxPerMm(ppm, 1);
      // Рамка карты шире ровно на 0,1 мм по прежней оценке.
      expect(kCardWidthMm * wider - kCardWidthMm * ppm, closeTo(0.1 * ppm, 1e-9));
      expect(nudgePxPerMm(nudgePxPerMm(ppm, 10), -10), closeTo(4, 1e-3));
      expect(nudgePxPerMm(ppm, 0), ppm);
    });

    test('SNO-F-EYE-05: первая оценка — место, система, 96 точек', () {
      const EyeMonitor known = EyeMonitor(
        id: r'\\.\DISPLAY1',
        name: '',
        widthPx: 1920,
        heightPx: 1080,
        widthMm: 527,
      );
      const EyeMonitor unknown = EyeMonitor(
        id: r'\\.\DISPLAY2',
        name: '',
        widthPx: 2560,
        heightPx: 1440,
      );
      expect(initialPxPerMm(known, place, 1), place.pxPerMm);
      expect(initialPxPerMm(known, null, 1), closeTo(1920 / 527, 1e-9));
      expect(initialPxPerMm(unknown, place, 1.5), closeTo(1.5 * 96 / 25.4, 1e-9));
    });
  });

  group('SNO-ALG-EYE-04: строка «окно»', () {
    const EyeMonitor monitor = EyeMonitor(
      id: r'\\.\DISPLAY1',
      name: 'DELL',
      widthPx: 1920,
      heightPx: 1080,
    );
    EyeWindowLock lock({bool found = true, int w = 1920, String? id}) {
      return EyeWindowLock(
        monitor: id ?? monitor.id,
        name: 'DELL',
        found: found,
        widthPx: w,
        heightPx: 1080,
        dpr: 1,
      );
    }

    test('SNO-ALG-EYE-04: на весь выбранный монитор — годится', () {
      final EyeCheckRow row = windowCheckRow(lock: lock(), monitor: monitor);
      expect(row.verdict, EyeVerdict.good);
      expect(row.text, 'Окно на весь экран: 1920×1080');
    });

    test('SNO-ALG-EYE-04: не тот монитор, не весь экран, нет замка', () {
      expect(
        windowCheckRow(lock: lock(found: false), monitor: monitor).text,
        'Окно не на выбранном мониторе',
      );
      expect(
        windowCheckRow(lock: lock(id: r'\\.\DISPLAY2'), monitor: monitor)
            .verdict,
        EyeVerdict.fail,
      );
      expect(
        windowCheckRow(lock: lock(w: 1600), monitor: monitor).text,
        'Окно не на весь экран: 1600×1080 из 1920×1080',
      );
      expect(
        windowCheckRow(lock: null, monitor: monitor).verdict,
        EyeVerdict.fail,
      );
    });

    test('SNO-F-EYE-05: монитор словами', () {
      expect(monitor.label, 'DELL · 1920×1080');
      expect(
        const EyeMonitor(
          id: r'\\.\DISPLAY12',
          name: '',
          widthPx: 1280,
          heightPx: 1024,
          primary: true,
        ).label,
        'Монитор 12 · 1280×1024 · основной',
      );
      expect(
        EyeMonitor.fromJson(<Object?, Object?>{
          'id': r'\\.\DISPLAY1',
          'name': 'DELL',
          'w_px': 1920,
          'h_px': 1080,
          'w_mm': 0,
          'primary': true,
        })!.widthMm,
        isNull,
      );
      expect(EyeMonitor.fromJson('мусор'), isNull);
    });
  });
}
