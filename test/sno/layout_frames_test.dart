import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/sno/recording/journal_check.dart';
import 'package:memoria/sno/recording/layout_frames.dart';

/// Шаг 30, SNO-F-REC-03, SNO-ALG-REC-02: кадр раскладки — чистая часть.
///
/// Что лежит в кадре листа и как из него вернуться от точки экрана к
/// символу страницы, сверяется с эталоном второй реализации
/// (`test/goldens/layout_frame.json`, `tool/make_layout_goldens.py`) —
/// тем же, по которому проверяет себя разбор на Python
/// (`eye/tests/test_layout.py`). Когда кадр писать — правила
/// [LayoutPacer] на придуманных снимках и миллисекундах.
void main() {
  const String goldenPath = 'test/goldens/layout_frame.json';

  List<Map<String, Object?>> cases() {
    final Map<String, Object?> golden =
        jsonDecode(File(goldenPath).readAsStringSync())
            as Map<String, Object?>;
    return <Map<String, Object?>>[
      for (final Object? item in golden['cases']! as List<Object?>)
        item! as Map<String, Object?>,
    ];
  }

  double number(Object? value) => (value! as num).toDouble();

  List<double> numbers(Object? value) => <double>[
    for (final Object? item in value! as List<Object?>) number(item),
  ];

  SheetBox box(Object? value) {
    final List<double> v = numbers(value);
    return SheetBox(v[0], v[1], v[2], v[3]);
  }

  /// Геометрия листа по входу эталона — кодом приложения.
  SheetGeometry geometryOf(Map<String, Object?> input) {
    final Map<String, Object?> sheet = input['sheet']! as Map<String, Object?>;
    final Map<String, Object?> place = input['place']! as Map<String, Object?>;
    return sheetGeometry(
      pages: <({int page, double width, double height})>[
        for (final Object? page in sheet['pages']! as List<Object?>)
          (
            page: (page! as Map<String, Object?>)['page']! as int,
            width: number(page['width']),
            height: number(page['height']),
          ),
      ],
      scale: number(sheet['scale']),
      left: number(sheet['left']),
      top: number(sheet['top']),
      zoom: number(sheet['zoom']),
      dx: number(sheet['dx']),
      dy: number(sheet['dy']),
      content: box(sheet['content']),
      strip: box(sheet['strip']),
      stripIndex: sheet['strip_index']! as int,
      strips: sheet['strips']! as int,
      neighbours: <LayoutNeighbour>[
        for (final Object? neighbour in sheet['neighbours']! as List<Object?>)
          LayoutNeighbour(
            after: (neighbour! as Map<String, Object?>)['side'] == 'after',
            rect: LayoutRect.fromJson(neighbour['rect'])!,
          ),
      ],
    ).placed(
      LayoutPlace(
        scale: number(place['scale']),
        dx: number(place['dx']),
        dy: number(place['dy']),
      ),
    );
  }

  /// Числа [actual] и [expected] равны с точностью до округления
  /// потока — десятой доли пикселя.
  void sameNumbers(Object? actual, Object? expected, String where) {
    if (expected is num) {
      expect(actual, isA<num>(), reason: where);
      expect(
        (actual! as num).toDouble(),
        closeTo(expected.toDouble(), 0.051),
        reason: where,
      );
    } else if (expected is List<Object?>) {
      final List<Object?> list = actual! as List<Object?>;
      expect(list, hasLength(expected.length), reason: where);
      for (int i = 0; i < expected.length; i++) {
        sameNumbers(list[i], expected[i], '$where[$i]');
      }
    } else if (expected is Map<String, Object?>) {
      final Map<String, Object?> map = actual! as Map<String, Object?>;
      expect(map.keys.toSet(), expected.keys.toSet(), reason: where);
      for (final String key in expected.keys) {
        sameNumbers(map[key], expected[key], '$where.$key');
      }
    } else {
      expect(actual, expected, reason: where);
    }
  }

  /// Символ страницы [page] под точкой в пунктах.
  String? symbolAt(Object? symbols, int page, double x, double y) {
    for (final Object? item in symbols! as List<Object?>) {
      final Map<String, Object?> symbol = item! as Map<String, Object?>;
      final List<double> b = numbers(symbol['box']);
      if (symbol['page'] == page &&
          x >= b[0] &&
          x <= b[2] &&
          y >= b[1] &&
          y <= b[3]) {
        return symbol['char']! as String;
      }
    }
    return null;
  }

  group('SNO-ALG-REC-02: кадр листа и обратный перевод — по эталону', () {
    for (final Map<String, Object?> golden in cases()) {
      final String name = golden['name']! as String;
      final Map<String, Object?> input =
          golden['input']! as Map<String, Object?>;
      final Map<String, Object?> frame =
          golden['frame']! as Map<String, Object?>;

      test('SNO-ALG-REC-02: лист в кадре — как у второй реализации ($name)',
          () {
        final Map<String, Object?> sheet = geometryOf(input).toJson();
        sameNumbers(
          jsonDecode(jsonEncode(sheet)),
          frame['sheet'],
          'sheet',
        );
      });

      test('SNO-ALG-REC-02: точка на символе → пиксели → обратно в тот же '
          'символ; зона поверх страницы важнее страницы ($name)', () {
        final LayoutFrame read = LayoutFrame.fromJson(frame)!;
        for (final Object? item in golden['points']! as List<Object?>) {
          final Map<String, Object?> point = item! as Map<String, Object?>;
          final Map<String, Object?> expected =
              point['expect']! as Map<String, Object?>;
          final double x = number(point['x']);
          final double y = number(point['y']);
          final LayoutHit hit = read.locate(x, y);
          expect(hit.zone, expected['zone'], reason: '$point');
          if (expected['zone'] == 'page') {
            expect(hit.page, expected['page'], reason: '$point');
            expect(hit.dimmed, expected['dimmed'], reason: '$point');
            expect(
              symbolAt(input['symbols'], hit.page!, hit.xPt!, hit.yPt!),
              expected['char'],
              reason: '$point',
            );
          } else if (expected.containsKey('id')) {
            expect(hit.id, expected['id'], reason: '$point');
          }
        }
      });
    }

    test('SNO-ALG-REC-02: кадр в строке потока читается тем же, каким '
        'писался', () {
      final Map<String, Object?> golden = cases().first;
      final SheetGeometry sheet = geometryOf(
        golden['input']! as Map<String, Object?>,
      );
      final LayoutSnapshot snapshot = LayoutSnapshot(
        viewport: const LayoutViewport(width: 800, height: 1280, dpr: 2),
        regions: const <LayoutRegion>[
          LayoutRegion(
            kind: LayoutKind.page,
            rect: LayoutRect(0, 24, 800, 1256),
          ),
          LayoutRegion(
            kind: LayoutKind.panelTop,
            rect: LayoutRect(0, 0, 800, 80),
            z: 1,
          ),
        ],
        sheet: sheet,
      );
      final Map<String, Object?> line =
          jsonDecode(
                jsonEncode(<String, Object?>{
                  'n': 7,
                  't': 1200,
                  ...snapshot.toJson(moving: true),
                }),
              )
              as Map<String, Object?>;
      final LayoutFrame read = LayoutFrame.fromJson(line)!;
      expect(read.n, 7);
      expect(read.t, 1200);
      expect(read.moving, isTrue);
      expect(read.viewport.orientation, 'portrait');
      expect(line['viewport'], containsPair('orientation', 'portrait'));
      expect(read.regions.map((LayoutRegion r) => r.kind), <LayoutKind>[
        LayoutKind.page,
        LayoutKind.panelTop,
      ]);
      expect(read.sheet!.pages.single.page, 12);
      expect(read.sheet!.strips, 3);
      expect(read.sheet!.stripIndex, 2);
      expect((line['sheet']! as Map<String, Object?>)['y_down'], isTrue);
      // Незнакомый вид зоны — экран целиком, а не отказ.
      final LayoutFrame strange = LayoutFrame.fromJson(<String, Object?>{
        'viewport': <String, Object?>{'w': 10, 'h': 10},
        'regions': <Object?>[
          <String, Object?>{
            'kind': 'из-будущей-сборки',
            'rect': <Object?>[0, 0, 5, 5],
            'z': 0,
          },
        ],
      })!;
      expect(strange.regions.single.kind, LayoutKind.screen);
      expect(LayoutFrame.fromJson(<String, Object?>{'n': 1}), isNull);
    });
  });

  group('SNO-ALG-REC-02: когда писать кадр', () {
    LayoutSnapshot shot(double top, {double width = 800}) {
      return LayoutSnapshot(
        viewport: LayoutViewport(width: width, height: 600, dpr: 1),
        regions: <LayoutRegion>[
          LayoutRegion(
            kind: LayoutKind.panelTop,
            rect: LayoutRect(0, top, width, 56),
          ),
        ],
      );
    }

    test('SNO-ALG-REC-02: первый снимок записи «в движении» не бывает — '
        'он ложится устоявшимся', () {
      final LayoutPacer pacer = LayoutPacer();

      expect(pacer.observe(shot(0), 0), isNull);
      expect(pacer.changed, isTrue);
      expect(pacer.pending, isTrue);
      expect(pacer.settle(), shot(0));
      expect(pacer.pending, isFalse);
      expect(pacer.settle(), isNull);
    });

    test('SNO-ALG-REC-02: двадцать изменений подряд — кадр «в движении» в '
        'начале, не чаще пяти в секунду, и один устоявшийся', () {
      final LayoutPacer pacer = LayoutPacer()..observe(shot(0), 0);
      pacer.settle();
      final List<int> moving = <int>[];
      // Панель едет двадцать кадров по 16 мс — 320 мс анимации.
      for (int i = 1; i <= 20; i++) {
        if (pacer.observe(shot(-i * 2.8), i * 16) != null) {
          moving.add(i * 16);
        }
        expect(pacer.changed, isTrue);
      }
      expect(moving, <int>[16, 224]);
      expect(pacer.settle(), shot(-56));
      expect(pacer.settle(), isNull);
    });

    test('SNO-ALG-REC-02: тот же снимок изменением не считается; '
        'сдвиг меньше десятой пикселя — тоже', () {
      final LayoutPacer pacer = LayoutPacer()..observe(shot(0), 0);
      pacer.settle();

      expect(pacer.observe(shot(0), 100), isNull);
      expect(pacer.changed, isFalse);
      expect(pacer.observe(shot(0.04), 120), isNull);
      expect(pacer.changed, isFalse);
      expect(pacer.settle(), isNull);
    });

    test('SNO-ALG-REC-02: ушло и вернулось на место — устоявшийся кадр '
        'всё равно пишется: разбор видел начало движения', () {
      final LayoutPacer pacer = LayoutPacer()..observe(shot(0), 0);
      pacer.settle();

      expect(pacer.observe(shot(-20), 100), shot(-20));
      expect(pacer.observe(shot(0), 116), isNull);
      expect(pacer.settle(), shot(0));
    });

    test('SNO-ALG-REC-02: после устоявшегося кадра новое изменение снова '
        'начинается кадром «в движении» сразу', () {
      final LayoutPacer pacer = LayoutPacer()..observe(shot(0), 0);
      pacer.settle();
      expect(pacer.observe(shot(-10), 100), isNotNull);
      pacer.settle();

      expect(pacer.observe(shot(-30), 150), isNotNull);
    });
  });

  group('SNO-F-REC-03: сборщик потока кадров', () {
    LayoutSnapshot shot() {
      return LayoutSnapshot(
        viewport: const LayoutViewport(width: 400, height: 300, dpr: 1.5),
        regions: const <LayoutRegion>[],
      );
    }

    test('SNO-F-REC-03: номер сквозной, время — от записи, «в движении» '
        'помечено', () {
      final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
      final LayoutTracker tracker = LayoutTracker(lines.add)
        ..frame(shot(), t: 10, moving: true)
        ..frame(shot(), t: 110, moving: false);

      expect(tracker.count, 2);
      expect(lines.map((Map<String, Object?> line) => line['n']), <int>[
        1,
        2,
      ]);
      expect(lines.first['t'], 10);
      expect(lines.first['moving'], isTrue);
      expect(lines.last['moving'], isFalse);
      expect(lines.last.containsKey('sheet'), isFalse);
      expect(lines.last['viewport'], <String, Object?>{
        'w': 400.0,
        'h': 300.0,
        'dpr': 1.5,
        'orientation': 'landscape',
      });
    });

    test('SNO-F-REC-03: конец потока дописывает недописанное, а после него '
        'кадры не пишутся', () {
      final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
      final LayoutTracker tracker = LayoutTracker(lines.add);
      int asked = 0;
      tracker
        ..beforeFinish = () {
          asked++;
          tracker.frame(shot(), t: 5, moving: false);
        }
        ..finish()
        ..finish()
        ..frame(shot(), t: 9, moving: false);

      expect(asked, 1);
      expect(tracker.count, 1);
      expect(lines, hasLength(1));
    });

    test('SNO-F-REC-03: итог самопроверки потока словами — третья строка '
        'экрана завершения', () {
      expect(describeLayoutCheck(null), isNull);
      expect(
        describeLayoutCheck(
          const JournalCheck(lines: 96, gaps: 0, torn: false),
        ),
        'Кадры раскладки целы: 96 кадров, пропусков нет',
      );
      expect(
        describeLayoutCheck(
          const JournalCheck(lines: 21, gaps: 2, torn: true),
        ),
        'Кадры раскладки неполны: 21 кадр, пропущено кадров 2, последний '
        'оборван',
      );
      expect(
        describeLayoutCheck(
          const JournalCheck(lines: 3, gaps: 0, torn: false, late: true),
        ),
        'Кадры раскладки целы до обрыва записи: 3 кадра, пропусков нет',
      );
    });

    test('SNO-F-REC-03: ЗАМЕР — сколько весит поток за сорок минут чтения',
        () {
      // Кадр чтения с листом, панелями и точкой записи — как на
      // телефоне посреди книги.
      final LayoutSnapshot reading = LayoutSnapshot(
        viewport: const LayoutViewport(width: 411.4, height: 914.3, dpr: 2.625),
        regions: const <LayoutRegion>[
          LayoutRegion(
            kind: LayoutKind.page,
            rect: LayoutRect(0, 0, 411.4, 914.3),
          ),
          LayoutRegion(
            kind: LayoutKind.panelTop,
            rect: LayoutRect(0, 0, 411.4, 80.3),
            z: 1,
          ),
          LayoutRegion(
            kind: LayoutKind.panelBottom,
            rect: LayoutRect(0, 850, 411.4, 64.3),
            z: 2,
          ),
          LayoutRegion(
            kind: LayoutKind.recordingDot,
            rect: LayoutRect(0, 24, 40, 40),
            z: 3,
          ),
        ],
        sheet: sheetGeometry(
          pages: const <({int page, double width, double height})>[
            (page: 123, width: 595.3, height: 841.9),
          ],
          scale: 0.73333,
          left: -21.7,
          top: -301.2,
          content: const SheetBox(0.05, 0.04, 0.95, 0.96),
          strip: const SheetBox(0.05, 0.34, 0.95, 0.65),
          stripIndex: 2,
          strips: 3,
        ),
      );
      final int bytes =
          utf8
              .encode(
                jsonEncode(<String, Object?>{
                  'n': 1234,
                  't': 1234567,
                  'screen': 'reader',
                  'book': 'f' * 64,
                  'page': 123,
                  'strip': 2,
                  'mode': 'third',
                  ...reading.toJson(moving: false),
                }),
              )
              .length +
          1;
      // Сорок минут: смена полосы раз в 15 с — два кадра, панели раз в
      // минуту — четыре кадра на открытие и закрытие.
      const int frames = 160 * 2 + 40 * 4;
      final int total = bytes * frames;
      // ignore: avoid_print
      print(
        'ЗАМЕР SNO-F-REC-03: кадр чтения $bytes байт; '
        'за 40 минут ~$frames кадров, ~${total ~/ 1024} КБ',
      );
      expect(bytes, lessThan(1500));
      expect(total, lessThan(2 * 1024 * 1024));
    });
  });
}
