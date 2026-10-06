import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/input_tap.dart';

/// SNO-ALG-REC-07 (функция SNO-F-REC-11): сырой ввод — чистое правило.
///
/// События здесь придуманы руками: время и место каждого в руках
/// теста, виджетов и часов нет.
void main() {
  late List<Map<String, Object?>> lines;
  late InputTracker tracker;

  setUp(() {
    lines = <Map<String, Object?>>[];
    tracker = InputTracker(lines.add);
  });

  void down(
    int pointer,
    int t,
    double x,
    double y, {
    String dev = 'touch',
    String? button,
    String screen = 'reader',
  }) {
    tracker.down(
      pointer: pointer,
      t: t,
      x: x,
      y: y,
      dev: dev,
      button: button,
      vw: 411,
      vh: 914,
      screen: screen,
    );
  }

  group('SNO-ALG-REC-07: вид касания', () {
    test('SNO-ALG-REC-07: коротко и на месте — tap, одна строка на '
        'касание', () {
      down(1, 1000, 312.5, 640);
      expect(lines, isEmpty, reason: 'строка пишется, когда палец поднят');
      tracker.up(pointer: 1, t: 1096, x: 313, y: 641.5);

      expect(lines, hasLength(1));
      expect(lines.single, <String, Object?>{
        'n': 1,
        't': 1000,
        'dt': 96,
        'dev': 'touch',
        'kind': 'tap',
        'x': 312.5,
        'y': 640.0,
        'x1': 313.0,
        'y1': 641.5,
        'path': 1.6,
        'vw': 411.0,
        'vh': 914.0,
        'screen': 'reader',
      });
    });

    test('SNO-ALG-REC-07: держали на месте дольше порога — long', () {
      down(1, 0, 100, 100);
      tracker.up(pointer: 1, t: kLongPressMs, x: 101, y: 100);

      expect(lines.single['kind'], 'long');
      expect(lines.single.containsKey('trail'), isFalse);
    });

    test('SNO-ALG-REC-07: ушло дальше порога — drag, и порог у мыши '
        'меньше, чем у пальца', () {
      down(1, 0, 100, 100);
      tracker.up(pointer: 1, t: 80, x: 100 + kTouchSlop - 1, y: 100);
      down(2, 200, 100, 100);
      tracker.up(pointer: 2, t: 280, x: 100 + kTouchSlop + 1, y: 100);
      down(3, 400, 100, 100, dev: 'mouse', button: 'primary');
      tracker.up(pointer: 3, t: 480, x: 100 + kMouseSlop + 1, y: 100);

      expect(lines.map((Map<String, Object?> line) => line['kind']), <String>[
        'tap',
        'drag',
        'drag',
      ]);
      expect(lines.last['dev'], 'mouse');
      expect(lines.last['button'], 'primary');
    });

    test('SNO-ALG-REC-07: вернулся к месту касания — всё равно drag: '
        'считается наибольшее удаление', () {
      down(1, 0, 100, 100);
      tracker
        ..move(pointer: 1, t: 60, x: 180, y: 100)
        ..up(pointer: 1, t: 120, x: 100, y: 100);

      expect(lines.single['kind'], 'drag');
      expect(lines.single['path'], 160.0);
      expect(lines.single['x1'], 100.0);
    });

    test('SNO-ALG-REC-07: два пальца — у каждого своя строка, вид multi '
        'и общая группа', () {
      down(1, 0, 100, 100);
      down(2, 30, 300, 300);
      tracker
        ..up(pointer: 1, t: 200, x: 100, y: 100)
        ..up(pointer: 2, t: 220, x: 300, y: 300);

      expect(lines, hasLength(2));
      expect(lines[0]['kind'], 'multi');
      expect(lines[1]['kind'], 'multi');
      expect(lines[0]['group'], 1);
      expect(lines[1]['group'], 1);
      expect(lines[0]['n'], 1);
      expect(lines[1]['n'], 2);
    });

    test('SNO-ALG-REC-07: жест забрала система — cancel', () {
      down(1, 0, 5, 400);
      tracker.cancel(pointer: 1, t: 40);

      expect(lines.single['kind'], 'cancel');
      expect(lines.single['dt'], 40);
    });

    test('SNO-ALG-REC-07: запись остановилась при опущенном пальце — '
        'строка с пометкой cut', () {
      down(1, 0, 50, 50);
      tracker.finish(700);

      expect(lines.single['kind'], 'cut');
      expect(lines.single['dt'], 700);
      expect(tracker.held, 0);
    });

    test('SNO-ALG-REC-07: чужое отпускание и движение без касания строк '
        'не дают', () {
      tracker
        ..move(pointer: 9, t: 10, x: 1, y: 1)
        ..up(pointer: 9, t: 20, x: 1, y: 1)
        ..cancel(pointer: 9, t: 30);

      expect(lines, isEmpty);
      expect(tracker.count, 0);
    });

    test('SNO-ALG-REC-07: касание точки записи помечено — в карты '
        'участника оно не идёт', () {
      down(1, 0, 16, 16, screen: 'shelf');
      tracker
        ..mark(1, 'recording_dot')
        ..up(pointer: 1, t: 2300, x: 16, y: 16);

      expect(lines.single['screen'], 'recording_dot');
    });
  });

  group('SNO-ALG-REC-07: след касания', () {
    test('SNO-ALG-REC-07: точка следа — не чаще раза в $kTrailGapMs мс, '
        'и последняя обязательно', () {
      down(1, 0, 0, 0);
      // Сто событий движения за секунду: каждые 10 мс.
      for (int i = 1; i <= 100; i++) {
        tracker.move(pointer: 1, t: i * 10, x: i * 2.0, y: 0);
      }
      tracker.up(pointer: 1, t: 1004, x: 201, y: 0);

      final List<Object?> trail = lines.single['trail']! as List<Object?>;
      // Не больше двадцати точек в секунду и последняя.
      expect(trail.length, lessThanOrEqualTo(21));
      expect(trail.length, greaterThanOrEqualTo(19));
      expect(trail.last, <num>[1004, 201.0, 0.0]);
      final List<int> times = <int>[
        for (final Object? point in trail) (point! as List<Object?>)[0]! as int,
      ];
      for (int i = 1; i < times.length - 1; i++) {
        expect(times[i] - times[i - 1], greaterThanOrEqualTo(kTrailGapMs));
      }
    });

    test('SNO-ALG-REC-07: у нажатия на месте следа нет', () {
      down(1, 0, 10, 10);
      tracker
        ..move(pointer: 1, t: 60, x: 11, y: 10)
        ..up(pointer: 1, t: 90, x: 11, y: 11);

      expect(lines.single['kind'], 'tap');
      expect(lines.single.containsKey('trail'), isFalse);
    });

    test('SNO-ALG-REC-07: след длиннее предела не растёт, а последняя '
        'точка — настоящая', () {
      down(1, 0, 0, 0);
      for (int i = 1; i <= kTrailLimit + 50; i++) {
        tracker.move(pointer: 1, t: i * kTrailGapMs, x: i.toDouble(), y: 0);
      }
      final int end = (kTrailLimit + 50) * kTrailGapMs + 7;
      tracker.up(pointer: 1, t: end, x: 9999, y: 1);

      final List<Object?> trail = lines.single['trail']! as List<Object?>;
      expect(trail, hasLength(kTrailLimit));
      expect(trail.last, <num>[end, 9999.0, 1.0]);
    });
  });

  group('SNO-ALG-REC-07: колесо, клавиши, путь мыши', () {
    void wheel(int t, double dy) {
      tracker.wheel(
        t: t,
        x: 600,
        y: 400,
        dx: 0,
        dy: dy,
        vw: 1280,
        vh: 800,
        screen: 'shelf',
      );
    }

    test('SNO-ALG-REC-07: щелчки колеса подряд — одна строка с суммой, '
        'после тишины — новая', () {
      wheel(0, 100);
      wheel(60, 100);
      wheel(140, 40);
      expect(lines, isEmpty);
      // Тишина дольше порога: прежняя прокрутка кончилась.
      wheel(140 + kWheelGapMs, -100);
      expect(lines, hasLength(1));
      expect(lines.single, <String, Object?>{
        'n': 1,
        't': 0,
        'dt': 140,
        'dev': 'wheel',
        'x': 600.0,
        'y': 400.0,
        'dy': 240.0,
        'vw': 1280.0,
        'vh': 800.0,
        'screen': 'shelf',
      });

      // Вторая уходит строкой с секундой записи.
      tracker.poll(140 + kWheelGapMs + 10);
      expect(lines, hasLength(1), reason: 'тишины ещё мало');
      tracker.poll(140 + 2 * kWheelGapMs);
      expect(lines, hasLength(2));
      expect(lines.last['dy'], -100.0);
      expect(lines.last['n'], 2);
    });

    test('SNO-ALG-REC-07: клавиша пишется, когда отпущена; автоповтор — '
        'счётом, а не строками', () {
      tracker.keyDown(1, t: 100, name: 'PageDown', screen: 'reader');
      for (int i = 1; i <= 5; i++) {
        tracker.keyRepeat(1, t: 100 + i * 30);
      }
      expect(lines, isEmpty);
      tracker.keyUp(1, t: 300);

      expect(lines.single, <String, Object?>{
        'n': 1,
        't': 100,
        'dt': 200,
        'dev': 'key',
        'key': 'PageDown',
        'repeat': 5,
        'screen': 'reader',
      });
    });

    test('SNO-ALG-REC-07: две клавиши внахлёст — две строки, каждая со '
        'своим номером', () {
      tracker
        ..keyDown(1, t: 0, name: 'char', screen: 'shelf')
        ..keyDown(2, t: 40, name: 'char', screen: 'shelf')
        ..keyUp(1, t: 90)
        ..keyUp(2, t: 130)
        // Отпускание без нажатия — клавишу держали до старта записи.
        ..keyUp(3, t: 140);

      expect(lines, hasLength(2));
      expect(lines.map((Map<String, Object?> line) => line['n']), <int>[1, 2]);
      expect(
        lines.every((Map<String, Object?> line) => line['key'] == 'char'),
        isTrue,
      );
    });

    test('SNO-ALG-REC-07: клавишу держат, а запись остановили — строка '
        'с пометкой cut', () {
      tracker
        ..keyDown(1, t: 0, name: 'ArrowRight', screen: 'reader')
        ..finish(900);

      expect(lines.single['kind'], 'cut');
      expect(lines.single['key'], 'ArrowRight');
    });

    test('SNO-ALG-REC-07: путь мыши без нажатия — не чаще десяти точек '
        'в секунду, пачкой раз в секунду', () {
      // Мышь ведут три секунды, событие каждые 8 мс.
      for (int t = 0; t <= 3000; t += 8) {
        tracker.hover(
          t: t,
          x: t * 0.5,
          y: 300,
          vw: 1280,
          vh: 800,
          screen: 'shelf',
        );
      }
      tracker.finish(3000);

      expect(lines.length, inInclusiveRange(3, 4));
      int points = 0;
      for (final Map<String, Object?> line in lines) {
        expect(line['dev'], 'hover');
        final List<Object?> trail = line['trail']! as List<Object?>;
        expect(trail.length, lessThanOrEqualTo(11));
        points += trail.length;
      }
      expect(points, inInclusiveRange(27, 31));
    });

    test('SNO-ALG-REC-07: мышь, которая стоит, пути не даёт', () {
      for (int t = 0; t <= 5000; t += 16) {
        tracker.hover(
          t: t,
          x: 500 + (t % 32 == 0 ? 1 : 0),
          y: 300,
          vw: 1280,
          vh: 800,
          screen: 'shelf',
        );
      }
      tracker.finish(5000);

      // Одна точка — где мышь встала; дрожь в пиксель не пишется.
      expect(lines, hasLength(1));
      expect(lines.single['trail'], hasLength(1));
    });
  });

  group('SNO-ALG-REC-07: связь с действием', () {
    test('SNO-ALG-REC-07: пока палец на экране — ссылка на его касание', () {
      expect(tracker.linkAt(0), isNull);
      down(1, 100, 10, 10);

      expect(tracker.linkAt(100), 1);
      expect(tracker.linkAt(100000), 1, reason: 'палец всё ещё на экране');
    });

    test('SNO-ALG-REC-07: после отпускания — в окне $kInputLinkMs мс; '
        'событие снаружи ссылки не получает', () {
      down(1, 100, 10, 10);
      tracker.up(pointer: 1, t: 180, x: 10, y: 10);

      expect(tracker.linkAt(180), 1);
      expect(tracker.linkAt(180 + kInputLinkMs), 1);
      expect(tracker.linkAt(180 + kInputLinkMs + 1), isNull);
      // Запоздавшему по своей природе событию окно шире.
      expect(tracker.linkAt(1200, window: kInputLateLinkMs), 1);
      expect(tracker.linkAt(180 + kInputLateLinkMs + 1, window: 1500), isNull);
    });

    test('SNO-ALG-REC-07: новое касание перекрывает прежнее', () {
      down(1, 0, 10, 10);
      tracker.up(pointer: 1, t: 50, x: 10, y: 10);
      down(2, 100, 200, 200);
      tracker.up(pointer: 2, t: 150, x: 200, y: 200);

      expect(tracker.linkAt(200), 2);
    });

    test('SNO-ALG-REC-07: клавиша и колесо тоже дают ссылку — от '
        'нажатия и от последнего щелчка', () {
      tracker.keyDown(7, t: 1000, name: 'PageDown', screen: 'reader');
      expect(tracker.linkAt(1010), 1);
      tracker.keyUp(7, t: 1050);
      expect(tracker.linkAt(1050 + kInputLinkMs + 1), isNull);

      tracker.wheel(
        t: 3000,
        x: 1,
        y: 1,
        dx: 0,
        dy: 100,
        vw: 10,
        vh: 10,
        screen: 'shelf',
      );
      expect(tracker.linkAt(3100), 2);
    });

    test('SNO-ALG-REC-07: после остановки ссылок нет', () {
      down(1, 0, 10, 10);
      tracker.finish(100);

      expect(tracker.linkAt(100), isNull);
    });
  });

  group('SNO-F-REC-11: размер потока', () {
    test('SNO-F-REC-11: три тысячи касаний и путь мыши за сорок минут — '
        'не больше трёх мегабайт', () {
      const int length = 40 * 60 * 1000;
      int pointer = 0;
      // Мышь водят без остановки все сорок минут — худший случай.
      for (int t = 0; t < length; t += 16) {
        tracker.hover(
          t: t,
          x: (t ~/ 16 * 7) % 1280 + 0.5,
          y: (t ~/ 16 * 5) % 800 + 0.5,
          vw: 1280,
          vh: 800,
          screen: 'reader',
        );
        // Касание — каждые 0,8 секунды: три тысячи за запись; каждое
        // десятое — протяжка на полсекунды.
        if (t % 800 == 0) {
          pointer++;
          final double x = (pointer * 37) % 1280 + 0.5;
          final double y = (pointer * 53) % 800 + 0.5;
          down(pointer, t, x, y, dev: 'mouse', button: 'primary');
          if (pointer % 10 == 0) {
            for (int step = 1; step <= 30; step++) {
              tracker.move(
                pointer: pointer,
                t: t + step * 16,
                x: x + step * 9.5,
                y: y + step * 3.5,
              );
            }
            tracker.up(pointer: pointer, t: t + 500);
          } else {
            tracker.up(pointer: pointer, t: t + 90, x: x, y: y);
          }
        }
      }
      tracker.finish(length);

      int bytes = 0;
      for (final Map<String, Object?> line in lines) {
        bytes += utf8.encode(jsonEncode(line)).length + 1;
      }
      // ignore: avoid_print
      print('ЗАМЕР: поток ввода за 40 минут — ${bytes ~/ 1024} КБ, '
          'строк ${lines.length}, касаний $pointer');
      expect(pointer, 3000);
      expect(bytes, lessThan(3 * 1024 * 1024));
    });
  });
}
