import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/library/drag_scroll.dart';

/// Высота области показа на телефоне в логических точках — примерно
/// столько остаётся под полку на экране 1080×2400.
const double _phone = 873;

void main() {
  group('зоны самопрокрутки', () {
    test('чувствительная полоса стала много шире прежних 90 точек', () {
      // Ради этого сессия и затевалась: попасть пальцем в узкую полосу у
      // края, ведя книгу, оказалось неудобно (замечание владельца).
      final ({double slow, double fast}) zones = dragScrollZones(_phone);
      expect(zones.slow, greaterThan(150));
      expect(zones.slow, closeTo(_phone * kDragScrollSlowZone, 0.001));
      expect(zones.fast, closeTo(_phone * kDragScrollFastZone, 0.001));
    });

    test('быстрая зона лежит внутри медленной на любой высоте', () {
      for (final double height in <double>[80, 200, 480, 873, 1400, 3000]) {
        final ({double slow, double fast}) zones = dragScrollZones(height);
        expect(zones.fast, lessThan(zones.slow), reason: 'высота $height');
        expect(zones.fast, greaterThanOrEqualTo(0), reason: 'высота $height');
      }
    });

    test('зоны не съедают середину даже на низком окне', () {
      // Иначе полка ехала бы всегда, и остановить её было бы нечем.
      for (final double height in <double>[60, 120, 240, 400]) {
        final ({double slow, double fast}) zones = dragScrollZones(height);
        expect(zones.slow * 2, lessThan(height), reason: 'высота $height');
        expect(
          dragScrollSpeed(y: height / 2, height: height),
          0,
          reason: 'середина при высоте $height',
        );
      }
    });

    test('на высоком мониторе полоса упирается в потолок', () {
      // Доля от высоты дала бы у краёв полосы шире, чем спокойная
      // середина между ними.
      expect(dragScrollZones(4000).slow, kDragScrollMaxZone);
    });

    test('нулевая и мусорная высота дают пустые зоны', () {
      expect(dragScrollZones(0).slow, 0);
      expect(dragScrollZones(-10).slow, 0);
      expect(dragScrollZones(double.nan).slow, 0);
      expect(dragScrollZones(double.infinity).slow, 0);
    });
  });

  group('скорость самопрокрутки', () {
    test('в середине экрана полка стоит', () {
      expect(dragScrollSpeed(y: _phone / 2, height: _phone), 0);
      expect(dragScrollSpeed(y: _phone * 0.4, height: _phone), 0);
      expect(dragScrollSpeed(y: _phone * 0.6, height: _phone), 0);
    });

    test('верх везёт к началу списка, низ — к концу', () {
      expect(dragScrollSpeed(y: 10, height: _phone), lessThan(0));
      expect(dragScrollSpeed(y: _phone - 10, height: _phone), greaterThan(0));
    });

    test('у самого края — полная скорость', () {
      expect(dragScrollSpeed(y: 0, height: _phone), -kDragScrollFastSpeed);
      expect(dragScrollSpeed(y: _phone, height: _phone), kDragScrollFastSpeed);
    });

    test('на границе зон скорость ровно медленная', () {
      final ({double slow, double fast}) zones = dragScrollZones(_phone);
      expect(
        dragScrollSpeed(y: zones.fast, height: _phone),
        closeTo(-kDragScrollSlowSpeed, 1e-9),
      );
      expect(dragScrollSpeed(y: zones.slow, height: _phone), closeTo(0, 1e-9));
    });

    test('в медленной зоне медленно, в быстрой быстро', () {
      // Ровно то, о чём просил владелец: две зоны, а не одна.
      final ({double slow, double fast}) zones = dragScrollZones(_phone);
      final double slow = dragScrollSpeed(
        y: (zones.fast + zones.slow) / 2,
        height: _phone,
      ).abs();
      final double fast = dragScrollSpeed(
        y: zones.fast / 2,
        height: _phone,
      ).abs();
      expect(slow, greaterThan(0));
      expect(slow, lessThanOrEqualTo(kDragScrollSlowSpeed));
      expect(fast, greaterThan(kDragScrollSlowSpeed));
      expect(fast, lessThanOrEqualTo(kDragScrollFastSpeed));
    });

    test('скорость нигде не прыгает', () {
      // Рывок под пальцем ощущается поломкой сильнее, чем слишком быстрая
      // прокрутка. Проверяется тем, что соседние точки экрана не могут
      // отличаться по скорости больше чем на её наклон в быстрой зоне.
      double previous = dragScrollSpeed(y: 0, height: _phone);
      for (double y = 0.5; y <= _phone; y += 0.5) {
        final double current = dragScrollSpeed(y: y, height: _phone);
        expect(
          (current - previous).abs(),
          lessThan(40),
          reason: 'скачок скорости в точке $y',
        );
        previous = current;
      }
    });

    test('чем ближе к краю, тем быстрее', () {
      double previous = 0;
      for (double y = dragScrollZones(_phone).slow; y >= 0; y -= 1) {
        final double speed = dragScrollSpeed(y: y, height: _phone).abs();
        expect(speed, greaterThanOrEqualTo(previous - 1e-9), reason: 'y = $y');
        previous = speed;
      }
    });

    test('палец за краем экрана — та же полная скорость', () {
      // Книгу нередко уводят за край, и выключать там прокрутку значит
      // остановить полку ровно в тот момент, когда она нужнее всего.
      expect(dragScrollSpeed(y: -50, height: _phone), -kDragScrollFastSpeed);
      expect(
        dragScrollSpeed(y: _phone + 50, height: _phone),
        kDragScrollFastSpeed,
      );
    });

    test('мусорные числа не роняют расчёт', () {
      expect(dragScrollSpeed(y: 10, height: 0), 0);
      expect(dragScrollSpeed(y: 10, height: -100), 0);
      expect(dragScrollSpeed(y: double.nan, height: _phone), 0);
      expect(dragScrollSpeed(y: 10, height: double.nan), 0);
      expect(dragScrollSpeed(y: double.infinity, height: _phone), 0);
    });

    test('расчёт один и тот же на телефоне и на ПК', () {
      // Платформы здесь нет вовсе, и это решение: колесо мыши полку
      // прокрутит, но вести книгу и крутить колесо одновременно — не то,
      // чего стоит требовать от читателя.
      const double desktop = 1000;
      expect(
        dragScrollSpeed(y: 0, height: desktop),
        dragScrollSpeed(y: 0, height: _phone),
      );
    });
  });
}
