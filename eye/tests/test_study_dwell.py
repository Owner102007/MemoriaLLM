"""Шаг 38, SNO-ALG-RES-07: заходы, возвраты и переходы между зонами —
на рядах, собранных руками: граница зон, смена содержимого под
неподвижным взглядом, разрыв ряда, время захода; ожидание без памяти
цепью против розыгрыша; участник, который помнит, где был, и ищущий
наугад; что под фиксацией на кадре полки; лента сессии.
"""

from __future__ import annotations

import random

import pytest

from sno_eye.report import zones as zn
from sno_eye.study import dwell

GAP = 1000.0
BRIDGE = 150.0
STILL = 177.0
F1, F2 = {"n": 1}, {"n": 2}


def row(t, zone, sure=True, near=(), x=100.0, y=100.0, frame=F1, d=200):
    return {"t": t, "end": t + d, "x": x, "y": y, "frame": frame,
            "zone": zone, "sure": sure, "near": set(near)}


def walk(zones, step=250, **kw):
    return [row(i * step, z, x=100.0 + 300 * (i % 2), **kw)
            for i, z in enumerate(zones)]


def test_sno_alg_res_07_dwells_revisits_and_transitions_by_hand():
    rows, trans = dwell.dwells(walk(["A", "A", "B", "A", "C", "A"]), [],
                               GAP, BRIDGE, STILL)
    assert [d.zone for d in rows] == ["A", "B", "A", "C", "A"]
    assert [d.revisit for d in rows] == [False, False, True, False, True]
    assert [(a, b) for a, b, _ in trans] == [("A", "B"), ("B", "A"),
                                             ("A", "C"), ("C", "A")]
    # Время захода — фиксации и просветы до bridge: 200 + 50 + 200.
    assert rows[0].time == pytest.approx(450)


def test_sno_alg_res_07_border_dither_gives_no_extra_dwell():
    """Дрожание у границы с фиксациями «на границе» не даёт ни одного
    лишнего захода: фиксация на границе продолжает заход, если задевает
    его зону."""
    seq = [row(0, "A"), row(250, "B", sure=False, near=["A"]),
           row(500, "A", sure=False, near=["B"]),
           row(750, "B", sure=False, near=["A"]), row(1000, "A")]
    rows, trans = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert [d.zone for d in rows] == ["A"]
    assert trans == []
    # Фиксация «уверенно» в другой зоне заход кончает.
    seq.append(row(1250, "B"))
    rows, trans = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert [d.zone for d in rows] == ["A", "B"]
    # На границе, но зону захода не задела — тоже новый заход.
    seq = [row(0, "A"), row(250, "C", sure=False, near=["B"])]
    rows, _ = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert [d.zone for d in rows] == ["A", "C"]


def test_sno_alg_res_07_content_change_under_still_gaze():
    """Перелистнул, не глядя в сторону: другой кадр, сдвиг меньше порога
    — новый заход без перехода и без возврата."""
    seq = [row(0, "p3", frame=F1), row(250, "p4", frame=F1, x=600),
           row(500, "p3", frame=F1, x=100),
           row(750, "p4", frame=F2, x=105)]
    rows, trans = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert [d.zone for d in rows] == ["p3", "p4", "p3", "p4"]
    assert rows[3].content and not rows[3].revisit
    assert len(trans) == 2
    # Скачок взгляда при той же смене кадра — обычный переход.
    seq[3] = row(750, "p4", frame=F2, x=600)
    rows, trans = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert rows[3].revisit and not rows[3].content
    assert len(trans) == 3


def test_sno_alg_res_07_broken_row_has_no_transition():
    seq = [row(0, "A"), row(2500, "B"), row(2750, "B"), row(5000, "B"),
           row(5250, "A")]
    rows, trans = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    # A → (разрыв) → B: заход есть, перехода нет; B после разрыва — тот
    # же заход; B → A — переход и возврат.
    assert [d.zone for d in rows] == ["A", "B", "A"]
    assert [(a, b) for a, b, _ in trans] == [("B", "A")]
    assert rows[2].revisit
    # Отрезок движения раскладки между фиксациями тоже рвёт ряд.
    seq = [row(0, "A"), row(250, "B")]
    _, trans = dwell.dwells(seq, [(210.0, 240.0)], GAP, BRIDGE, STILL)
    assert trans == []


def test_sno_alg_res_07_skipped_fixations_do_not_break():
    """Фиксация не на зоне уровня (None) пропускается: страница — панель
    — та же страница остаётся одним заходом."""
    seq = [row(0, 3), row(250, None), row(500, 3)]
    rows, _ = dwell.dwells(seq, [], GAP, BRIDGE, STILL)
    assert len(rows) == 1


# --- ожидание без памяти -----------------------------------------------------

def simulate(m, n, sims, rng):
    total = 0
    for _ in range(sims):
        cur = rng.randrange(n)
        seen = {cur}
        back = 0
        for _ in range(m - 1):
            cur = rng.choice([z for z in range(n) if z != cur])
            back += cur in seen
            seen.add(cur)
        total += back
    return total / sims


@pytest.mark.parametrize("m,n", [(2, 4), (5, 4), (8, 6), (12, 3)])
def test_sno_alg_res_07_expected_by_chain_matches_simulation(m, n):
    rng = random.Random(m * 100 + n)
    assert dwell.expected_revisits(m, n) == pytest.approx(
        simulate(m, n, 20_000, rng), abs=0.05)


def test_sno_alg_res_07_expected_edges():
    assert dwell.expected_revisits(1, 5) == 0.0
    assert dwell.expected_revisits(3, 1) is None
    assert dwell.expected_revisits(0, 5) is None
    # Две зоны: каждый заход после второго — возврат.
    assert dwell.expected_revisits(6, 2) == pytest.approx(4.0)


def test_sno_alg_res_07_memory_versus_random_search():
    """Помнящий, где был, получает отношение «было / без памяти» меньше
    1, ищущий наугад — около 1."""
    rng = random.Random(3)
    n, m = 6, 7
    obs_rand = obs_mem = exp = 0.0
    for _ in range(300):
        cur = rng.randrange(n)
        seq = [cur]
        for _ in range(m - 1):
            cur = rng.choice([z for z in range(n) if z != cur])
            seq.append(cur)
        rows, _ = dwell.dwells(walk(seq), [], GAP, BRIDGE, STILL)
        obs_rand += sum(d.revisit for d in rows)
        memory = list(range(n)) + [0]
        rows, _ = dwell.dwells(walk(memory[:m]), [], GAP, BRIDGE, STILL)
        obs_mem += sum(d.revisit for d in rows)
        exp += dwell.expected_revisits(m, n)
    assert obs_rand / exp == pytest.approx(1.0, abs=0.1)
    assert obs_mem / exp < 0.5


# --- что под фиксацией ---------------------------------------------------------

def shelf_frame():
    return {"t": 0, "n": 1, "viewport": {"w": 1280.0, "h": 800.0},
            "regions": [
                {"kind": "screen", "id": "shelf", "rect": [0, 56, 1280, 744],
                 "z": 0, "info": {"scroll": 0.0}},
                {"kind": "nav", "id": "", "rect": [0, 0, 1280, 56], "z": 1},
                {"kind": "shelf_category", "id": "А",
                 "rect": [16, 70, 1248, 300], "z": 2,
                 "info": {"part": "area"}},
                {"kind": "shelf_book", "id": "b1",
                 "rect": [40, 100, 180, 150], "z": 3,
                 "info": {"category": "А"}},
                {"kind": "shelf_book", "id": "b2",
                 "rect": [240, 100, 180, 150], "z": 4,
                 "info": {"category": "А"}},
            ]}


def test_sno_alg_res_07_touch_on_the_shelf():
    zones = zn.Zones([shelf_frame()], outside_px=80.0)
    frame = shelf_frame()
    mid = dwell.touch(zones, frame, 130, 175, 20)
    assert mid["ui"] == "shelf" and not mid["ui_near"]
    assert mid["book"] == "shelf:b1" and mid["book_sure"]
    assert mid["cat"] == "А" and mid["cat_sure"]
    # Между книгами: категория уверенно, книга — нет.
    gap = dwell.touch(zones, frame, 230, 175, 20)
    assert gap["cat"] == "А" and gap["cat_sure"]
    assert not gap["book_sure"]
    # У навигации — на границе двух зон интерфейса.
    edge = dwell.touch(zones, frame, 600, 60, 20)
    assert edge["ui"] == "shelf" and "other" in edge["ui_near"]
    # Далеко за окном — «вне экрана».
    out = dwell.touch(zones, frame, -200, 300, 20)
    assert out["ui"] == "outside"


# --- лента и годный взгляд ------------------------------------------------------

def test_sno_alg_res_07_ribbon_by_seconds():
    lo = 1000.0
    labels = [(lo + i * 100, 100.0, x, x) for i, x in
              enumerate(["page"] * 15 + ["shelf"] * 5 + ["outside"] * 8
                        + ["page"] * 2)]
    out = dwell.ribbon(labels, lo, lo + 3000)
    # Секунда 0 — чтение; 1 — 5 чтения и 5 полки (ничья — по порядку
    # групп: чтение); 2 — вне экрана.
    assert out == [[0, 2, "reading"], [2, 3, "off"]]


def test_sno_alg_res_07_valid_minutes():
    lo = 0.0
    labels = [(0.0, 30_000.0, "page", "page"),
              (30_000.0, 30_000.0, "no_face", "no_face"),
              (60_000.0, 60_000.0, "shelf", "shelf")]
    total, per = dwell.valid_minutes(labels, lo, 2)
    assert total == pytest.approx(1.5)
    assert per == pytest.approx([0.5, 1.0])


def test_sno_alg_res_07_openings_from_journal():
    events = [{"t": 10, "type": "book.open", "book": "a"},
              {"t": 50, "type": "book.close", "book": "a"},
              {"t": 70, "type": "book.open", "book": "b"},
              {"t": 200, "type": "book.close", "book": "b",
               "phase": "post"}]
    assert dwell.openings(events, 0, 100) == [(10, 50, "a"), (70, 100, "b")]
