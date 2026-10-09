#!/usr/bin/env python3
"""Эталон кадра раскладки (SNO-F-REC-03, SNO-ALG-REC-02) — вторая
реализация формулы.

Приложение пишет в кадр раскладки, где на экране лежит лист книги:
страницы, масштаб, рамку обрезки, читаемую полосу, соседей
(`lib/sno/recording/layout_frames.dart`, `sheetGeometry`). Разбор на
ПК переводит точку экрана обратно в страницу и символ
(`eye/sno_eye/layout.py`). Здесь та же прямая формула записана заново,
на Python, и по ней посчитаны:

- кадр двух придуманных листов — страница 595×842 в полосе ⅓ под
  панелью и разворот двух разных страниц, приближенный щипком, рядом с
  панелью поиска;
- места нескольких символов этих страниц на экране и что лежит в
  каждой точке: символ, затемнение, панель поверх страницы, сосед, фон.

Тест Dart (`test/sno/layout_frames_test.dart`) сверяет с этим файлом
свой кадр и свой обратный перевод, тест спутника
(`eye/tests/test_layout.py`) — обратный перевод разбора. Расхождение
значит, что одна из трёх реализаций ошиблась.

С шага 31 (ET-05) здесь же — экраны без листа (раздел `screens`):
полка, прокрученная и подрезанная краем списка, поиск по названию
поверх затемнённой полки и карта «Галактика». У карты прямая формула
своя — места звёзд на экране по камере карты и выборка звёзд для кадра
(видимые, крупные первыми, не больше ста; в приложении —
`layoutStars`); для всех трёх — что лежит в точке: зона, её сведения и
звезда под точкой (`mark`).

Запуск: `python3 tool/make_layout_goldens.py` — переписывает
`test/goldens/layout_frame.json`. Правится осознанно, вместе с кодом.
"""

import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'test', 'goldens', 'layout_frame.json')


def r1(value):
    """Одна десятая пикселя — как в потоке; половина — от нуля."""
    return math.copysign(math.floor(abs(value) * 10 + 0.5) / 10, value)


def r5(value):
    return math.copysign(math.floor(abs(value) * 100000 + 0.5) / 100000,
                         value)


def rect(left, top, right, bottom):
    return [min(left, right), min(top, bottom), abs(right - left),
            abs(bottom - top)]


def forward(case):
    """Геометрия листа в окне — прямая формула."""
    sheet = case['sheet']
    place = case['place']
    zoom = sheet['zoom']
    eff = sheet['scale'] * zoom
    ox = sheet['left'] * zoom + sheet['dx']
    oy = sheet['top'] * zoom + sheet['dy']
    s, px, py = place['scale'], place['dx'], place['dy']

    def at(x, y):
        return x * s + px, y * s + py

    width = 0.0
    height = 0.0
    pages = []
    for page in sheet['pages']:
        x, y = at(ox + width * eff, oy)
        pages.append({'page': page['page'], 'x': x, 'y': y,
                      'w': page['width'], 'h': page['height']})
        width += page['width']
        height = max(height, page['height'])

    def part(box):
        l, t = at(ox + box[0] * width * eff, oy + box[1] * height * eff)
        r, b = at(ox + box[2] * width * eff, oy + box[3] * height * eff)
        return rect(l, t, r, b)

    neighbours = []
    for n in sheet['neighbours']:
        l, t = at(n['rect'][0], n['rect'][1])
        r, b = at(n['rect'][0] + n['rect'][2], n['rect'][1] + n['rect'][3])
        neighbours.append({'side': n['side'], 'rect': rect(l, t, r, b)})
    return {
        'scale': eff * s,
        'pages': pages,
        'rect': part([0, 0, 1, 1]),
        'content': part(sheet['content']),
        'strip': part(sheet['strip']),
        'strip_index': sheet['strip_index'],
        'strips': sheet['strips'],
        'neighbours': neighbours,
    }


def rounded(geometry):
    return {
        'y_down': True,
        'scale': r5(geometry['scale']),
        'pages': [{'page': p['page'], 'x': r1(p['x']), 'y': r1(p['y']),
                   'w': r1(p['w']), 'h': r1(p['h'])}
                  for p in geometry['pages']],
        'rect': [r1(v) for v in geometry['rect']],
        'content': [r1(v) for v in geometry['content']],
        'strip': [r1(v) for v in geometry['strip']],
        'strip_index': geometry['strip_index'],
        'strips': geometry['strips'],
        'neighbours': [{'side': n['side'], 'rect': [r1(v) for v in n['rect']]}
                       for n in geometry['neighbours']],
    }


def inside(r, x, y):
    return r[0] <= x <= r[0] + r[2] and r[1] <= y <= r[1] + r[3]


def expect_at(case, geometry, x, y):
    """Что лежит в точке — по точной (не округлённой) геометрии."""
    vw, vh = case['viewport']['w'], case['viewport']['h']
    if x < 0 or y < 0 or x > vw or y > vh:
        return {'zone': 'outside'}
    top = None
    for region in case['regions']:
        if inside(region['rect'], x, y) and (top is None or
                                              region['z'] > top['z']):
            top = region
    if top is not None and top['kind'] != 'page':
        return {'zone': top['kind'], 'id': top['id']}
    for page in geometry['pages']:
        xp = (x - page['x']) / geometry['scale']
        yp = (y - page['y']) / geometry['scale']
        if 0 <= xp <= page['w'] and 0 <= yp <= page['h']:
            char = None
            for symbol in case['symbols']:
                b = symbol['box']
                if symbol['page'] == page['page'] and \
                        b[0] <= xp <= b[2] and b[1] <= yp <= b[3]:
                    char = symbol['char']
            return {'zone': 'page', 'page': page['page'], 'char': char,
                    'dimmed': not inside(geometry['strip'], x, y)}
    for n in geometry['neighbours']:
        if inside(n['rect'], x, y):
            return {'zone': 'neighbour', 'id': n['side']}
    return {'zone': 'background'}


def symbol_point(geometry, symbol):
    for page in geometry['pages']:
        if page['page'] == symbol['page']:
            b = symbol['box']
            return (page['x'] + (b[0] + b[2]) / 2 * geometry['scale'],
                    page['y'] + (b[1] + b[3]) / 2 * geometry['scale'])
    raise ValueError(symbol)


CASES = [
    {
        'name': 'полоса ⅓ под панелью, телефон',
        'viewport': {'w': 800, 'h': 1280, 'dpr': 2.0},
        # Лист положен в место под страницу, а место начинается под
        # верхним краем окна.
        'place': {'scale': 1.0, 'dx': 0.0, 'dy': 24.0},
        'sheet': {
            'pages': [{'page': 12, 'width': 595.0, 'height': 842.0}],
            'scale': 1.42, 'left': -30.5, 'top': -120.25,
            'zoom': 1.0, 'dx': 0.0, 'dy': 0.0,
            'content': [0.06, 0.05, 0.94, 0.95],
            'strip': [0.06, 0.3, 0.94, 0.62],
            'strip_index': 2, 'strips': 3,
            'neighbours': [],
        },
        'regions': [
            {'kind': 'page', 'id': '', 'rect': [0, 24, 800, 1256], 'z': 0},
            {'kind': 'panel_top', 'id': '', 'rect': [0, 0, 800, 80],
             'z': 1},
            {'kind': 'selection_panel', 'id': '',
             'rect': [240, 600, 280, 52], 'z': 2},
        ],
        'symbols': [
            {'page': 12, 'char': 'а', 'box': [100.0, 300.0, 108.0, 312.0]},
            {'page': 12, 'char': 'б', 'box': [300.0, 420.0, 309.0, 432.0]},
            # Под панелью над выделением: точка уходит панели.
            {'page': 12, 'char': 'в', 'box': [250.0, 490.0, 258.0, 502.0]},
            # Выше полосы — в затемнении.
            {'page': 12, 'char': 'г', 'box': [200.0, 150.0, 208.0, 162.0]},
        ],
        'extra': [[790.0, 1270.0], [10.0, 10.0], [400.0, -5.0]],
    },
    {
        'name': 'разворот, щипок, поиск рядом, ПК',
        'viewport': {'w': 1920, 'h': 1080, 'dpr': 1.25},
        'place': {'scale': 1.0, 'dx': 0.0, 'dy': 0.0},
        'sheet': {
            'pages': [{'page': 12, 'width': 595.0, 'height': 842.0},
                      {'page': 13, 'width': 612.0, 'height': 792.0}],
            'scale': 0.8, 'left': 40.0, 'top': 10.0,
            'zoom': 1.5, 'dx': -60.0, 'dy': -20.0,
            'content': [0.03, 0.04, 0.97, 0.96],
            'strip': [0.0, 0.0, 1.0, 1.0],
            'strip_index': 1, 'strips': 1,
            'neighbours': [
                {'side': 'after', 'rect': [1500.0, 0.0, 40.0, 1080.0]},
            ],
        },
        'regions': [
            {'kind': 'page', 'id': '', 'rect': [0, 0, 1540, 1080], 'z': 0},
            {'kind': 'search_dock', 'id': 'beside',
             'rect': [1540, 0, 380, 1080], 'z': 1},
        ],
        'symbols': [
            {'page': 12, 'char': 'д', 'box': [80.0, 100.0, 90.0, 114.0]},
            {'page': 13, 'char': 'е', 'box': [20.0, 300.0, 29.0, 314.0]},
            {'page': 13, 'char': 'ж', 'box': [400.0, 600.0, 410.0, 614.0]},
        ],
        'extra': [[1520.0, 500.0], [1700.0, 500.0], [5.0, 1070.0]],
    },
]


# Поля карты и сколько звёзд идёт в кадр — как в приложении
# (`kMapMargin`, `kLayoutStarLimit` в `lib/domain/map/map_view.dart`).
MAP_MARGIN = 0.14
STAR_LIMIT = 100
# Сколько пикселей от звезды ещё попадание в неё (`kLayoutMarkReach`).
MARK_REACH = 24.0


def star_marks(case):
    """Звёзды карты в кадре — прямая формула: место на экране по камере
    и выборка видимых, крупные первыми."""
    m = case['map']
    left, top, w, h = m['rect']
    ext = m['extent']
    cam = m['camera']
    usable = 1 - 2 * MAP_MARGIN
    base = min(w * usable / (2 * ext['half_width']),
               h * usable / (2 * ext['half_height']))
    unit = base * cam['scale']
    seen = []
    for i, star in enumerate(m['stars']):
        x = w / 2 + (star['x'] - cam['cx']) * unit
        y = h / 2 + (star['y'] - cam['cy']) * unit
        r = star['r']
        if x + r < 0 or x - r > w or y + r < 0 or y - r > h:
            continue
        seen.append((i, x, y, r))
    seen.sort(key=lambda item: (-item[3], item[0]))
    seen = seen[:STAR_LIMIT]
    marks = [{'id': m['stars'][i]['book'], 'x': left + x, 'y': top + y,
              'r': r} for i, x, y, r in seen]
    return marks, unit


def mark_at(marks, x, y):
    best = None
    best_square = None
    for mark in marks:
        square = (mark['x'] - x) ** 2 + (mark['y'] - y) ** 2
        reach = max(mark['r'], MARK_REACH)
        if square <= reach * reach and (best_square is None or
                                        square < best_square):
            best, best_square = mark, square
    return None if best is None else best['id']


def screen_expect(regions, viewport, x, y):
    """Что лежит в точке кадра без листа — по точным (не округлённым)
    меткам."""
    if x < 0 or y < 0 or x > viewport['w'] or y > viewport['h']:
        return {'zone': 'outside'}
    top = None
    for region in regions:
        if inside(region['rect'], x, y) and (top is None or
                                              region['z'] > top['z']):
            top = region
    if top is None:
        return {'zone': 'screen'}
    hit = {'zone': top['kind'], 'id': top['id']}
    if top.get('info'):
        hit['info'] = top['info']
    if top.get('marks'):
        hit['mark'] = mark_at(top['marks'], x, y)
    return hit


def rounded_region(region):
    out = {'kind': region['kind'], 'id': region['id'],
           'rect': [r1(v) for v in region['rect']], 'z': region['z']}
    if region.get('clip'):
        out['clip'] = True
    if region.get('info'):
        out['info'] = region['info']
    if region.get('marks'):
        out['marks'] = [{'id': mk['id'], 'x': r1(mk['x']), 'y': r1(mk['y']),
                         'r': r1(mk['r'])} for mk in region['marks']]
    return out


H = {name: name * 8 for name in ('a1b2c3d4', 'e5f6a7b8', '0c1d2e3f',
                                  '9a8b7c6d', '5e4f3a2b')}
HA, HB, HC, HD, HE = (H['a1b2c3d4'], H['e5f6a7b8'], H['0c1d2e3f'],
                      H['9a8b7c6d'], H['5e4f3a2b'])

SCREENS = [
    {
        'name': 'полка на телефоне, прокручена и подрезана краем списка',
        'viewport': {'w': 411.4, 'h': 914.3, 'dpr': 2.625},
        'regions': [
            {'kind': 'screen', 'id': 'shelf', 'rect': [0, 0, 411.4, 834.3],
             'z': 0, 'info': {'scroll': 412.5}},
            {'kind': 'shelf_category', 'id': 'Анатомия',
             'rect': [12, 64, 387.4, 290], 'z': 1, 'clip': True,
             'info': {'part': 'area'}},
            {'kind': 'shelf_book', 'id': HA, 'rect': [22, 64, 115.8, 140],
             'z': 2, 'clip': True, 'info': {'category': 'Анатомия'}},
            {'kind': 'shelf_book', 'id': HB, 'rect': [147.8, 64, 115.8, 140],
             'z': 3, 'clip': True, 'info': {'category': 'Анатомия'}},
            {'kind': 'shelf_category', 'id': 'Гистология',
             'rect': [12, 382, 387.4, 40], 'z': 4,
             'info': {'part': 'header'}},
            {'kind': 'shelf_category', 'id': 'Гистология',
             'rect': [12, 430, 387.4, 200], 'z': 5,
             'info': {'part': 'area'}},
            {'kind': 'shelf_book', 'id': HC, 'rect': [22, 440, 115.8, 180],
             'z': 6, 'info': {'category': 'Гистология'}},
            {'kind': 'nav', 'id': 'bottom', 'rect': [0, 834.3, 411.4, 80],
             'z': 7, 'info': {'current': 'shelf'}},
            {'kind': 'nav', 'id': 'shelf', 'rect': [0, 834.3, 102.9, 80],
             'z': 8},
            {'kind': 'nav', 'id': 'galaxy',
             'rect': [102.9, 834.3, 102.8, 80], 'z': 9},
            {'kind': 'recording_dot', 'id': '', 'rect': [371.4, 24, 40, 40],
             'z': 10},
        ],
        'points': [[80, 120], [200, 70], [300, 300], [200, 400], [80, 500],
                   [300, 600], [200, 20], [150, 870], [380, 870],
                   [390, 40], [420, 10]],
    },
    {
        'name': 'поиск по названию на широком окне, полка затемнена',
        'viewport': {'w': 1280, 'h': 800, 'dpr': 2.0},
        'regions': [
            {'kind': 'nav', 'id': 'top', 'rect': [0, 0, 1280, 44], 'z': 0,
             'info': {'current': 'shelf'}},
            {'kind': 'nav', 'id': 'shelf', 'rect': [8, 0, 110, 44], 'z': 1},
            {'kind': 'screen', 'id': 'shelf', 'rect': [0, 44, 1280, 756],
             'z': 2, 'info': {'scroll': 0.0, 'searching': True}},
            {'kind': 'shelf_category', 'id': 'Анатомия',
             'rect': [12, 156, 1256, 300], 'z': 3, 'info': {'part': 'area'}},
            {'kind': 'shelf_book', 'id': HA, 'rect': [22, 166, 120, 170],
             'z': 4, 'info': {'category': 'Анатомия'}},
            {'kind': 'dialog', 'id': 'shelf_search_scrim',
             'rect': [0, 100, 1280, 700], 'z': 5},
            {'kind': 'shelf_results', 'id': '', 'rect': [112, 100, 420, 152],
             'z': 6, 'info': {'hits': 2}},
            {'kind': 'shelf_book', 'id': HB, 'rect': [112, 104, 420, 72],
             'z': 7, 'info': {'category': 'Анатомия', 'in': 'results',
                              'rank': 1}},
            {'kind': 'shelf_book', 'id': HA, 'rect': [112, 176, 420, 72],
             'z': 8, 'info': {'category': 'Анатомия', 'in': 'results',
                              'rank': 2}},
            {'kind': 'shelf_search', 'id': '', 'rect': [112, 50, 420, 44],
             'z': 9},
        ],
        'points': [[300, 70], [300, 140], [300, 200], [300, 250],
                   [60, 200], [700, 500], [50, 20], [600, 20]],
    },
    {
        'name': 'карта «Галактика» на ПК, карточка книги поверх',
        'viewport': {'w': 1280, 'h': 800, 'dpr': 1.25},
        'map': {
            'rect': [0, 100, 1280, 700],
            'extent': {'cx': 0.1, 'cy': -0.05, 'half_width': 1.2,
                       'half_height': 0.9},
            'camera': {'scale': 2.5, 'cx': 0.3, 'cy': 0.1},
            'stars': [
                {'book': HA, 'x': 0.3, 'y': 0.1, 'r': 4.5},
                {'book': HB, 'x': 0.42, 'y': 0.15, 'r': 12.0},
                {'book': HC, 'x': -1.1, 'y': 0.8, 'r': 7.0},
                {'book': HD, 'x': 0.2, 'y': -0.2, 'r': 4.5},
                {'book': HE, 'x': 0.36, 'y': 0.1, 'r': 4.5},
            ],
        },
        'regions': [
            {'kind': 'nav', 'id': 'top', 'rect': [0, 0, 1280, 44], 'z': 0,
             'info': {'current': 'galaxy'}},
            {'kind': 'screen', 'id': 'galaxy', 'rect': [0, 44, 1280, 756],
             'z': 1, 'info': {'shows': 'map'}},
            {'kind': 'galaxy_map', 'id': '', 'rect': [0, 100, 1280, 700],
             'z': 2},
            {'kind': 'galaxy_card', 'id': HB, 'rect': [900, 380, 320, 150],
             'z': 3},
        ],
        # Точки — в долях от мест звёзд: `[номер звезды, dx, dy]` — точка
        # рядом со звездой; `[x, y]` — точка окна.
        'star_points': [[0, 0, 0], [1, 9, -3], [0, 0, 20], [3, 0, 30],
                        [4, -14, 0]],
        'points': [[1000, 450], [50, 70], [100, 700]],
    },
]


def screen_case(case):
    regions = [dict(region) for region in case['regions']]
    marks = None
    unit = None
    if 'map' in case:
        marks, unit = star_marks(case)
        for region in regions:
            if region['kind'] == 'galaxy_map':
                cam = case['map']['camera']
                region['info'] = {
                    'map': {'scale': cam['scale'], 'cx': cam['cx'],
                            'cy': cam['cy'], 'unit': round(unit, 6)},
                    'stars': len(case['map']['stars']),
                }
                region['marks'] = marks
    points = []
    if marks is not None:
        by_id = {mk['id']: mk for mk in marks}
        for index, dx, dy in case['star_points']:
            mk = by_id[case['map']['stars'][index]['book']]
            x, y = round(mk['x'] + dx, 3), round(mk['y'] + dy, 3)
            points.append({'x': x, 'y': y,
                           'expect': screen_expect(regions, case['viewport'],
                                                   x, y)})
    for x, y in case['points']:
        points.append({'x': x, 'y': y,
                       'expect': screen_expect(regions, case['viewport'],
                                               x, y)})
    out = {
        'name': case['name'],
        'frame': {
            'viewport': case['viewport'],
            'regions': [rounded_region(region) for region in regions],
        },
        'points': points,
    }
    if 'map' in case:
        out['map'] = {k: case['map'][k] for k in
                      ('rect', 'extent', 'camera', 'stars')}
        out['map']['unit'] = unit
    return out


def main():
    out = {'schema': 'sno2026-layout-golden/1', 'cases': [], 'screens': []}
    for case in CASES:
        geometry = forward(case)
        points = []
        for symbol in case['symbols']:
            x, y = symbol_point(geometry, symbol)
            points.append({'x': round(x, 3), 'y': round(y, 3),
                           'expect': expect_at(case, geometry, x, y)})
        for x, y in case['extra']:
            points.append({'x': x, 'y': y,
                           'expect': expect_at(case, geometry, x, y)})
        out['cases'].append({
            'name': case['name'],
            'input': {k: case[k] for k in
                      ('viewport', 'place', 'sheet', 'regions', 'symbols')},
            'frame': {
                'viewport': case['viewport'],
                'sheet': rounded(geometry),
                'regions': case['regions'],
            },
            'points': points,
        })
    for case in SCREENS:
        out['screens'].append(screen_case(case))
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('эталон:', OUT)


if __name__ == '__main__':
    main()
