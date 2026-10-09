"""Шаг 30, SNO-F-REC-03, SNO-ALG-REC-02: обратный перевод кадра
раскладки при разборе.

Приложение пишет, где на экране лежал лист и что было поверх него;
разбор переводит точку экрана в зону, страницу и символ. Эталон —
`test/goldens/layout_frame.json`: его считает вторая реализация прямой
формулы (`tool/make_layout_goldens.py`), а приложение сверяет с ним
свой кадр (`test/sno/layout_frames_test.dart`). Здесь — третья
сторона: обратный перевод разбора по кадру из эталона.
"""

import json
from pathlib import Path

import pytest

from sno_eye import layout

GOLDEN = (Path(__file__).resolve().parents[2] / 'test' / 'goldens' /
          'layout_frame.json')


def cases():
    return json.loads(GOLDEN.read_text(encoding='utf-8'))['cases']


@pytest.mark.parametrize('case', cases(), ids=lambda case: case['name'])
def test_sno_alg_rec_02_point_returns_to_its_symbol(case):
    """SNO-ALG-REC-02: точка на символе → пиксели → обратно в тот же
    символ; зона поверх страницы важнее страницы; затемнение, сосед,
    фон и «мимо окна» узнаются."""
    frame = case['frame']
    symbols = case['input']['symbols']
    for point in case['points']:
        expect = point['expect']
        hit = layout.locate(frame, point['x'], point['y'])
        assert hit['zone'] == expect['zone'], point
        if expect['zone'] == 'page':
            assert hit['page'] == expect['page'], point
            assert hit['dimmed'] == expect['dimmed'], point
            char = layout.symbol_at(symbols, hit['page'], hit['x_pt'],
                                    hit['y_pt'])
            assert char == expect['char'], point
        elif 'id' in expect:
            assert hit.get('id', '') == expect['id'], point


def test_sno_alg_rec_02_frame_without_sheet_names_the_zone():
    """SNO-ALG-REC-02: без листа точка относится к верхней зоне, а без
    зон — к экрану целиком."""
    frame = {
        'viewport': {'w': 800, 'h': 600},
        'regions': [
            {'kind': 'page', 'id': '', 'rect': [0, 0, 800, 600], 'z': 0},
            {'kind': 'dialog', 'id': 'note', 'rect': [100, 100, 600, 400],
             'z': 1},
        ],
    }
    assert layout.locate(frame, 50, 50) == {'zone': 'page', 'id': ''}
    assert layout.locate(frame, 300, 300)['zone'] == 'dialog'
    assert layout.locate({'viewport': {'w': 800, 'h': 600}}, 1, 1) == {
        'zone': 'screen'}


def test_sno_alg_rec_02_frame_in_force_is_the_last_one_not_later(tmp_path):
    """SNO-ALG-REC-02, шаг 5: для мига `t` берётся последний кадр с `t`
    не больше; строка, которая не читается, пропускается."""
    path = tmp_path / 'layout.jsonl'
    rows = [
        {'n': 1, 't': 0, 'moving': False, 'viewport': {'w': 1, 'h': 1}},
        {'n': 2, 't': 500, 'moving': True, 'viewport': {'w': 1, 'h': 1}},
        {'n': 3, 't': 700, 'moving': False, 'viewport': {'w': 1, 'h': 1}},
    ]
    text = '\n'.join(json.dumps(row) for row in rows)
    path.write_text(text + '\n{"n": 4, "t": 9\n', encoding='utf-8')
    frames = layout.read_frames(str(path))
    assert [frame['n'] for frame in frames] == [1, 2, 3]
    assert layout.frame_at(frames, -1) is None
    assert layout.frame_at(frames, 499)['n'] == 1
    assert layout.frame_at(frames, 600)['moving'] is True
    assert layout.frame_at(frames, 10_000)['n'] == 3


def test_sno_alg_rec_02_symbol_near_the_point_on_its_line():
    """Точка между символами строки — ближайший; мимо строк — ничего."""
    symbols = [
        {'page': 1, 'char': 'а', 'box': [10, 10, 18, 22]},
        {'page': 1, 'char': 'б', 'box': [30, 10, 38, 22]},
    ]
    assert layout.symbol_at(symbols, 1, 20, 15) == 'а'
    assert layout.symbol_at(symbols, 1, 27, 15) == 'б'
    assert layout.symbol_at(symbols, 1, 20, 40) is None
    assert layout.symbol_at(symbols, 2, 12, 15) is None


def screens():
    return json.loads(GOLDEN.read_text(encoding='utf-8'))['screens']


@pytest.mark.parametrize('case', screens(), ids=lambda case: case['name'])
def test_sno_alg_rec_02_screen_point_names_zone_info_and_star(case):
    """Шаг 31, SNO-ALG-REC-02: на экранах без листа — полка, поиск по
    названию, карта — точка относится к верхней зоне; ответ несёт
    сведения зоны (категория книги, место строки найденного) и звезду
    карты под точкой — ближайшую в пределах её радиуса или 24 пикселей."""
    for point in case['points']:
        expect = point['expect']
        hit = layout.locate(case['frame'], point['x'], point['y'])
        assert hit['zone'] == expect['zone'], point
        if 'id' in expect:
            assert hit.get('id', '') == expect['id'], point
        assert hit.get('info') == expect.get('info'), point
        assert hit.get('mark') == expect.get('mark'), point
        assert ('mark' in hit) == ('mark' in expect), point


def test_sno_alg_rec_02_clipped_zone_keeps_its_name():
    """Шаг 31: зона, подрезанная краем прокрутки, остаётся той же зоной
    — пометка `clip` на ответ не влияет."""
    frame = {
        'viewport': {'w': 400, 'h': 800},
        'regions': [
            {'kind': 'shelf_book', 'id': 'h', 'rect': [0, 60, 100, 40],
             'z': 0, 'clip': True, 'info': {'category': 'А'}},
        ],
    }
    assert layout.locate(frame, 50, 70) == {
        'zone': 'shelf_book', 'id': 'h', 'info': {'category': 'А'}}
