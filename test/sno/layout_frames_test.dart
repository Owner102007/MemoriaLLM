import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memoria/domain/map/map_view.dart';
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
        jsonDecode(File(goldenPath).readAsStringSync()) as Map<String, Object?>;
    return <Map<String, Object?>>[
      for (final Object? item in golden['cases']! as List<Object?>)
        item! as Map<String, Object?>,
    ];
  }

  double number(Object? value) => (value! as num).toDouble();

  List<double> numbers(Object? value) => <double>[
    for (final Object? item in value! as List<Object?>) number(item),
  ];

  List<Map<String, Object?>> maps(Object? value) => <Map<String, Object?>>[
    for (final Object? item in value! as List<Object?>)
      item! as Map<String, Object?>,
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
        for (final Map<String, Object?> page in maps(sheet['pages']))
          (
            page: page['page']! as int,
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
        for (final Map<String, Object?> neighbour in maps(sheet['neighbours']))
          LayoutNeighbour(
            after: neighbour['side'] == 'after',
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

      test(
        'SNO-ALG-REC-02: лист в кадре — как у второй реализации ($name)',
        () {
          final Map<String, Object?> sheet = geometryOf(input).toJson();
          sameNumbers(jsonDecode(jsonEncode(sheet)), frame['sheet'], 'sheet');
        },
      );

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
      final Map<String, Object?> line = jsonDecode(
        jsonEncode(<String, Object?>{
          'n': 7,
          't': 1200,
          ...snapshot.toJson(moving: true),
        }),
      ) as Map<String, Object?>;
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
      expect(lines.map((Map<String, Object?> line) => line['n']), <int>[1, 2]);
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
        describeLayoutCheck(const JournalCheck(lines: 21, gaps: 2, torn: true)),
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

    test('SNO-F-REC-03: ЗАМЕР — сколько весит поток за сорок минут чтения', () {
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

  group('SNO-ALG-REC-02: экраны без листа — по эталону (шаг 31)', () {
    List<Map<String, Object?>> screens() {
      final Map<String, Object?> golden =
          jsonDecode(File(goldenPath).readAsStringSync())
              as Map<String, Object?>;
      return <Map<String, Object?>>[
        for (final Object? item in golden['screens']! as List<Object?>)
          item! as Map<String, Object?>,
      ];
    }

    for (final Map<String, Object?> golden in screens()) {
      final String name = golden['name']! as String;
      test('SNO-ALG-REC-02: точка экрана — верхняя зона, её сведения и '
          'звезда под точкой ($name)', () {
        final LayoutFrame frame = LayoutFrame.fromJson(
          golden['frame']! as Map<String, Object?>,
        )!;
        for (final Object? item in golden['points']! as List<Object?>) {
          final Map<String, Object?> point = item! as Map<String, Object?>;
          final Map<String, Object?> expected =
              point['expect']! as Map<String, Object?>;
          final LayoutHit hit = frame.locate(
            number(point['x']),
            number(point['y']),
          );
          expect(hit.zone, expected['zone'], reason: '$point');
          if (expected.containsKey('id')) {
            expect(hit.id, expected['id'], reason: '$point');
          }
          expect(
            hit.info,
            expected['info'] ?? const <String, Object?>{},
            reason: '$point',
          );
          expect(hit.mark, expected['mark'], reason: '$point');
        }
      });
    }

    test('SNO-ALG-REC-02: звёзды карты в кадре — те же места и та же '
        'выборка, что у второй реализации', () {
      final Map<String, Object?> golden = screens().firstWhere(
        (Map<String, Object?> item) => item.containsKey('map'),
      );
      final Map<String, Object?> map = golden['map']! as Map<String, Object?>;
      final List<double> rect = numbers(map['rect']);
      final Map<String, Object?> extent =
          map['extent']! as Map<String, Object?>;
      final Map<String, Object?> camera =
          map['camera']! as Map<String, Object?>;
      final MapViewport view = MapViewport(
        width: rect[2],
        height: rect[3],
        extent: MapExtent(
          cx: number(extent['cx']),
          cy: number(extent['cy']),
          halfWidth: number(extent['half_width']),
          halfHeight: number(extent['half_height']),
        ),
        camera: MapCamera(
          scale: number(camera['scale']),
          cx: number(camera['cx']),
          cy: number(camera['cy']),
        ),
      );
      expect(view.unit, closeTo(number(map['unit']), 1e-9));
      final List<Map<String, Object?>> stars = maps(map['stars']);
      final List<int> chosen = layoutStars(
        view: view,
        xs: <double>[
          for (final Map<String, Object?> s in stars) number(s['x']),
        ],
        ys: <double>[
          for (final Map<String, Object?> s in stars) number(s['y']),
        ],
        radii: <double>[
          for (final Map<String, Object?> s in stars) number(s['r']),
        ],
      );
      final Map<String, Object?> frame =
          golden['frame']! as Map<String, Object?>;
      final Map<String, Object?> region = maps(frame['regions']).firstWhere(
        (Map<String, Object?> item) => item['kind'] == 'galaxy_map',
      );
      final List<Map<String, Object?>> marks = maps(region['marks']);
      expect(chosen, hasLength(marks.length));
      for (int i = 0; i < chosen.length; i++) {
        final Map<String, Object?> star = stars[chosen[i]];
        expect(star['book'], marks[i]['id'], reason: 'звезда $i');
        sameNumbers(
          <double>[
            rect[0] + view.screenX(number(star['x'])),
            rect[1] + view.screenY(number(star['y'])),
            number(star['r']),
          ],
          <Object?>[marks[i]['x'], marks[i]['y'], marks[i]['r']],
          'звезда $i',
        );
      }
    });

    test('SNO-ALG-REC-02: в кадр — не больше ста звёзд, крупные первыми, '
        'при равном радиусе — по порядку карты', () {
      const MapViewport view = MapViewport(
        width: 400,
        height: 400,
        extent: MapExtent(cx: 0, cy: 0, halfWidth: 1, halfHeight: 1),
        camera: MapCamera(scale: 1, cx: 0, cy: 0),
      );
      final List<double> xs = <double>[for (int i = 0; i < 150; i++) 0];
      final List<double> ys = <double>[for (int i = 0; i < 150; i++) 0];
      final List<double> radii = <double>[
        for (int i = 0; i < 150; i++) i == 120 ? 9 : 3,
      ];
      final List<int> chosen = layoutStars(
        view: view,
        xs: xs,
        ys: ys,
        radii: radii,
      );
      expect(chosen, hasLength(kLayoutStarLimit));
      expect(chosen.first, 120);
      expect(chosen.skip(1).take(3), <int>[0, 1, 2]);
      // Звезда далеко за краем окна в кадр не идёт.
      expect(
        layoutStars(
          view: view,
          xs: const <double>[50],
          ys: const <double>[0],
          radii: const <double>[3],
        ),
        isEmpty,
      );
    });

    test('SNO-ALG-REC-02: подрезанная зона, сведения и метки читаются из '
        'строки потока теми же, какими писались', () {
      final LayoutSnapshot snapshot = LayoutSnapshot(
        viewport: const LayoutViewport(width: 1280, height: 800, dpr: 1),
        regions: const <LayoutRegion>[
          LayoutRegion(
            kind: LayoutKind.shelfBook,
            id: 'hash-1',
            rect: LayoutRect(10, 56, 120, 40),
            clipped: true,
            info: <String, Object?>{'category': 'Анатомия'},
          ),
          LayoutRegion(
            kind: LayoutKind.galaxyMap,
            rect: LayoutRect(0, 100, 1280, 700),
            z: 1,
            marks: <LayoutMark>[
              LayoutMark(id: 'hash-2', x: 640.04, y: 450, r: 4.5),
            ],
          ),
        ],
      );
      final Map<String, Object?> line =
          jsonDecode(jsonEncode(snapshot.toJson(moving: false)))
              as Map<String, Object?>;
      final List<Map<String, Object?>> written = maps(line['regions']);
      expect(written.first['clip'], isTrue);
      expect(written.last.containsKey('clip'), isFalse);
      expect(written.last.containsKey('info'), isFalse);
      expect(written.first.containsKey('marks'), isFalse);
      final LayoutFrame read = LayoutFrame.fromJson(line)!;
      expect(read.regions.first.clipped, isTrue);
      expect(read.regions.first.info, <String, Object?>{
        'category': 'Анатомия',
      });
      expect(read.regions.last.marks.single.id, 'hash-2');
      expect(read.regions.last.marks.single.x, 640);
      expect(read.regions, snapshot.regions);
      expect(read.locate(20, 60).info['category'], 'Анатомия');
      expect(read.locate(20, 60).mark, isNull);
      expect(read.locate(660, 450).mark, 'hash-2');
      expect(read.locate(670, 450).mark, isNull);
    });

    test('SNO-F-REC-03: ЗАМЕР — сколько весит кадр полки и кадр карты', () {
      final String hash = 'f' * 64;
      final LayoutSnapshot shelf = LayoutSnapshot(
        viewport: const LayoutViewport(width: 1280, height: 800, dpr: 2),
        regions: <LayoutRegion>[
          const LayoutRegion(
            kind: LayoutKind.screen,
            id: 'shelf',
            rect: LayoutRect(0, 44, 1280, 756),
            info: <String, Object?>{'scroll': 1234.5},
          ),
          for (int c = 0; c < 4; c++) ...<LayoutRegion>[
            LayoutRegion(
              kind: LayoutKind.shelfCategory,
              id: 'Категория номер $c',
              rect: LayoutRect(12, 100.0 + c * 300, 1256, 40),
              info: const <String, Object?>{'part': 'header'},
            ),
            LayoutRegion(
              kind: LayoutKind.shelfCategory,
              id: 'Категория номер $c',
              rect: LayoutRect(12, 148.0 + c * 300, 1256, 240),
              info: const <String, Object?>{'part': 'area'},
            ),
            for (int b = 0; b < 12; b++)
              LayoutRegion(
                kind: LayoutKind.shelfBook,
                id: hash,
                rect: LayoutRect(
                  22.5 + b * 104.3,
                  158.5 + c * 300,
                  94.3,
                  141.4,
                ),
                info: <String, Object?>{'category': 'Категория номер $c'},
              ),
          ],
          const LayoutRegion(
            kind: LayoutKind.nav,
            id: 'top',
            rect: LayoutRect(0, 0, 1280, 44),
            info: <String, Object?>{'current': 'shelf'},
          ),
        ],
      );
      final LayoutSnapshot galaxy = LayoutSnapshot(
        viewport: const LayoutViewport(width: 1280, height: 800, dpr: 2),
        regions: <LayoutRegion>[
          LayoutRegion(
            kind: LayoutKind.galaxyMap,
            rect: const LayoutRect(0, 100, 1280, 700),
            info: const <String, Object?>{
              'map': <String, Object?>{
                'scale': 2.123456,
                'cx': 0.123456,
                'cy': -0.654321,
                'unit': 612.345678,
              },
              'stars': 60,
            },
            marks: <LayoutMark>[
              for (int i = 0; i < 60; i++)
                LayoutMark(id: hash, x: 100.5 + i * 15, y: 300.5, r: 6.5),
            ],
          ),
        ],
      );
      int bytesOf(LayoutSnapshot snapshot) {
        return utf8
                .encode(
                  jsonEncode(<String, Object?>{
                    'n': 1234,
                    't': 1234567,
                    'screen': 'shelf',
                    ...snapshot.toJson(moving: false),
                  }),
                )
                .length +
            1;
      }

      final int shelfBytes = bytesOf(shelf);
      final int galaxyBytes = bytesOf(galaxy);
      // Минута прокрутки полки — триста кадров «в движении» и
      // устоявшихся вперемешку: пять в секунду, не чаще.
      final int minute = shelfBytes * 300;
      // ignore: avoid_print
      print(
        'ЗАМЕР SNO-F-REC-03: кадр полки (48 книг) $shelfBytes байт, '
        'минута прокрутки ~${minute ~/ 1024} КБ; кадр карты (60 звёзд) '
        '$galaxyBytes байт',
      );
      expect(shelfBytes, lessThan(16 * 1024));
      expect(galaxyBytes, lessThan(8 * 1024));
    });
  });
}
