"""Кадры раскладки при разборе (SNO-F-REC-03, SNO-ALG-REC-02, шаг 5).

Приложение пишет в запись поток `layout.jsonl`: где в каждый миг лежали
страница и зоны поверх неё — панели, полоса поиска, панель над
выделением, диалоги, точка записи. Здесь — обратный путь: точка экрана
(взгляд или касание) → зона, а на странице — страница и точка в
пунктах PDF, ось `y` вниз; по слою текста страницы — символ.

Координаты кадра — логические пиксели окна, как у потока ввода; точку
взгляда в физических пикселях монитора делят на `dpr` кадра раньше.

Формула та же, что в приложении (`lib/sno/recording/layout_frames.dart`,
`locateInFrame`), и обе сверяются с одним эталоном
(`test/goldens/layout_frame.json`, `tool/make_layout_goldens.py`).
Модуль без зависимостей: разбор (ET-07) возьмёт его как есть.
"""

import json

# Сколько логических пикселей от метки ещё считается попаданием в неё,
# если сама метка меньше (шаг 31): столько же ловит нажатие звезда на
# карте в приложении (`kHitRadius`, `kLayoutMarkReach`).
MARK_REACH = 24.0


def _inside(rect, x, y):
    left, top, width, height = rect
    return left <= x <= left + width and top <= y <= top + height


def mark_at(region, x, y):
    """Метка зоны `region` под точкой (`x`, `y`): ближайшая из тех, до
    чьей середины не дальше её радиуса или `MARK_REACH`; при равном
    расстоянии — первая. `None` — мимо всех (шаг 31: звёзды карты)."""
    best = None
    best_square = None
    for mark in region.get('marks', []):
        dx = mark['x'] - x
        dy = mark['y'] - y
        square = dx * dx + dy * dy
        reach = max(mark['r'], MARK_REACH)
        if square <= reach * reach and (best_square is None or
                                        square < best_square):
            best, best_square = mark, square
    return None if best is None else best['id']


def _zone(region, x, y):
    """Ответ для зоны поверх страницы или кадра без листа: вид, имя,
    сведения зоны и, если у неё есть метки, метка под точкой."""
    hit = {'zone': region['kind'], 'id': region.get('id', '')}
    if region.get('info'):
        hit['info'] = region['info']
    if region.get('marks'):
        hit['mark'] = mark_at(region, x, y)
    return hit


def locate(frame, x, y):
    """Что лежало в точке (`x`, `y`) окна по кадру `frame`.

    Ответ — словарь: `zone` — вид зоны (`page`, `panel_top`, …), для
    листа ещё `neighbour` — соседний лист, `background` — фон вокруг
    листа, `outside` — мимо окна, `screen` — кадр без зон и без листа;
    `id` — имя зоны; на странице — `page`, `x_pt`, `y_pt` и `dimmed`
    (точка на странице, но вне читаемой полосы). С шага 31 у зоны вне
    страницы ещё `info` — что о ней известно (категория книги полки,
    место строки найденного, камера карты), — а у зоны с метками
    (полотно карты) `mark` — отпечаток книги звезды под точкой или
    `None`.

    Зона поверх страницы важнее страницы: берётся верхняя по `z`.
    """
    viewport = frame['viewport']
    if x < 0 or y < 0 or x > viewport['w'] or y > viewport['h']:
        return {'zone': 'outside'}
    top = None
    for region in frame.get('regions', []):
        if _inside(region['rect'], x, y) and (top is None or
                                               region['z'] > top['z']):
            top = region
    sheet = frame.get('sheet')
    if top is not None and (top['kind'] != 'page' or sheet is None):
        return _zone(top, x, y)
    if sheet is None:
        return {'zone': 'screen'}
    scale = sheet['scale']
    for page in sheet['pages']:
        x_pt = (x - page['x']) / scale
        y_pt = (y - page['y']) / scale
        if 0 <= x_pt <= page['w'] and 0 <= y_pt <= page['h']:
            return {
                'zone': 'page',
                'id': '' if top is None else top.get('id', ''),
                'page': page['page'],
                'x_pt': x_pt,
                'y_pt': y_pt,
                'dimmed': not _inside(sheet['strip'], x, y),
            }
    for neighbour in sheet.get('neighbours', []):
        if _inside(neighbour['rect'], x, y):
            return {'zone': 'neighbour', 'id': neighbour['side']}
    return {'zone': 'background'}


def symbol_at(symbols, page, x_pt, y_pt):
    """Символ страницы `page` под точкой (`x_pt`, `y_pt`) или ближайший
    к ней в пределах строки; `None` — точка не на тексте.

    `symbols` — список словарей `{'page', 'char', 'box': [l, t, r, b]}`
    в пунктах PDF, ось `y` вниз, — слой текста страницы.
    """
    best = None
    best_distance = None
    for symbol in symbols:
        if symbol['page'] != page:
            continue
        left, top, right, bottom = symbol['box']
        if left <= x_pt <= right and top <= y_pt <= bottom:
            return symbol['char']
        if top <= y_pt <= bottom:
            distance = min(abs(x_pt - left), abs(x_pt - right))
            if best_distance is None or distance < best_distance:
                best, best_distance = symbol['char'], distance
    return best


def frame_at(frames, t):
    """Кадр, действующий в миг `t`: последний с `t` кадра не больше.

    Внутри отрезка движения (последний кадр — `moving`) ответ — сам этот
    кадр: разбор узнаёт по нему, что точку к зонам не относят.
    """
    found = None
    for frame in frames:
        if frame['t'] <= t:
            found = frame
        else:
            break
    return found


def read_frames(path):
    """Кадры файла `layout.jsonl` по порядку времени; строки, которые
    не читаются, пропускаются."""
    frames = []
    with open(path, encoding='utf-8') as source:
        for line in source:
            line = line.strip()
            if not line:
                continue
            try:
                frame = json.loads(line)
            except ValueError:
                continue
            if isinstance(frame, dict) and 'viewport' in frame:
                frames.append(frame)
    frames.sort(key=lambda frame: (frame.get('t', 0), frame.get('n', 0)))
    return frames
