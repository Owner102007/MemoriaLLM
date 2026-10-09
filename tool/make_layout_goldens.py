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


def main():
    out = {'schema': 'sno2026-layout-golden/1', 'cases': []}
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
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('эталон:', OUT)


if __name__ == '__main__':
    main()
