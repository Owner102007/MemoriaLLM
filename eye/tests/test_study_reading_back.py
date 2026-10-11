"""Шаг 38, SNO-ALG-RES-08: взгляд назад при чтении и возвраты на
страницу назад — на чтении, собранном руками: строки сверху вниз,
взгляды назад на известных секундах, вторая колонка, новая строка,
шум меньше порога, порог по прецизионности и остатку, режим половины
страницы, остаток прежней страницы после листания; журнал листания с
навигацией и промахом.
"""

from __future__ import annotations

import random

import pytest

from sno_eye import report
from sno_eye.report.screen import Screen
from sno_eye.report.timeline import Timeline
from sno_eye.report.versions import Sample
from sno_eye.study import portrait, reading_back

SCREEN = Screen(1280.0, 800.0, 340.0, 212.5, 600.0)
PAGE_X, SCALE = 357.4, 0.95
PC = dict(portrait.DEFAULTS)


def frame(t, page=1, strip=None, book="b"):
    rect = [PAGE_X, 0, 595 * SCALE, 842 * SCALE]
    sheet = {"y_down": True, "scale": SCALE,
             "pages": [{"page": page, "x": PAGE_X, "y": 0, "w": 595,
                        "h": 842}],
             "rect": rect, "content": rect, "strip": strip or rect,
             "neighbours": []}
    return {"t": t, "n": 1, "screen": "reader", "book": book,
            "viewport": {"w": 1280.0, "h": 800.0},
            "regions": [{"kind": "page", "id": "", "rect": [0, 0, 1280, 800],
                         "z": 0}], "sheet": sheet}


def line_of(t_end, precision=0.5):
    return Timeline(study_start=0.0, study_end=t_end, gaze_expected=True,
                    latency_ms=0.0, latency_known=True, start_deg=1.0,
                    end_deg=1.0, precision_deg=precision, end_shift_mm=None,
                    screens=[(0.0, "reader")])


def samples_of(looks, noise=2.0, seed=1):
    """Кадры по 33 мс вдоль взглядов `(от, до, x, y)`; между взглядами —
    40 мс скачка без годных кадров."""
    rng = random.Random(seed)
    out = []
    for a, b, x, y in looks:
        t = a
        while t < b:
            out.append(Sample(t, x + rng.gauss(0, noise),
                              y + rng.gauss(0, noise), True, True))
            t += 33
    return out


def reading(lines=15, t0=0.0, x0=420, step=100, cols=5, top=100, gap=45,
            back_at=None, back_up=5, back_ms=600):
    """Чтение строк сверху вниз; на строке [back_at] (по номеру строки,
    в её середине) — взгляд на [back_up] строк вверх на [back_ms]."""
    looks = []
    t = t0
    for line in range(lines):
        for c in range(cols):
            looks.append((t, t + 230, x0 + c * step, top + line * gap))
            t += 270
            if back_at is not None and line == back_at and c == 2:
                looks.append((t, t + back_ms, 470,
                              top + max(0, line - back_up) * gap))
                t += back_ms + 40
    return looks, t


def run(looks, frames, t_end, precision=0.5, implicit=None, **kw):
    pc = dict(PC, **kw)
    return reading_back.lookbacks(samples_of(looks), [], frames, SCREEN,
                                  line_of(t_end, precision), implicit, pc,
                                  report.settings())


def test_sno_alg_res_08_plain_reading_has_no_lookback():
    looks, t = reading()
    out = run(looks, [frame(0)], t + 100)
    assert out["reason"] is None
    assert out["count"] == 0
    # Переход на новую строку — влево и вниз — не взгляд назад.
    assert out["shows"][0]["fixations"] > 20


def test_sno_alg_res_08_planted_lookbacks_found_at_their_seconds():
    looks, t = reading(back_at=8)
    planted = next(a for a, b, x, y in looks if b - a == 600)
    out = run(looks, [frame(0)], t + 100)
    assert out["count"] == 1
    ep = out["episodes"][0]
    assert abs(ep["t0"] - planted) <= 100
    assert ep["t1"] - ep["t0"] >= 500
    # Скачок — пять строк вверх (225 пикселей, около 5,7°) и вбок от
    # места, где взгляд был перед ним.
    assert 5.0 < ep["jump_deg"] < 8.0
    assert ep["up_share"] > 0.2
    assert out["per_min"] == pytest.approx(1 / (t + 100) * 60_000)


def test_sno_alg_res_08_short_look_back_is_not_counted():
    looks, t = reading(back_at=8, back_ms=200)
    out = run(looks, [frame(0)], t + 100)
    assert out["count"] == 0


def test_sno_alg_res_08_noise_below_threshold_is_not_a_lookback():
    """Взгляд на строку-две вверх (меньше порога 2°) — не взгляд назад."""
    looks, t = reading(back_at=8, back_up=1)
    out = run(looks, [frame(0)], t + 100)
    assert out["count"] == 0


def test_sno_alg_res_08_second_column_is_not_a_lookback():
    """Скачок вверх и вправо в верхнюю треть — вторая колонка; скачок
    обратно в первую колонку — взгляд назад."""
    col1, t = reading(lines=14, x0=380, step=90, cols=3)
    col2, t = reading(lines=6, t0=t + 40, x0=720, step=80, cols=3)
    back = [(t + 40, t + 640, 440, 300)]
    rest, t = reading(lines=3, t0=t + 680, x0=720, step=80, cols=3,
                      top=100 + 6 * 45)
    out = run(col1 + col2 + back + rest, [frame(0)], t + 100)
    assert out["shows"][0]["columns"] == 2
    assert out["count"] == 1
    assert out["episodes"][0]["old_column"]
    assert abs(out["episodes"][0]["t0"] - back[0][0]) <= 100


def test_sno_alg_res_08_noisy_session_gets_nothing_with_reason():
    looks, t = reading(back_at=8)
    out = run(looks, [frame(0)], t + 100, precision=1.2)
    assert out["count"] if "count" in out else True
    assert out["episodes"] == []
    assert "шум больше порога" in out["reason"]
    out = run(looks, [frame(0)], t + 100, precision=None)
    assert "неизвестна" in out["reason"]


def test_sno_alg_res_08_threshold_grows_with_precision_and_residual():
    looks, t = reading()
    assert run(looks, [frame(0)], t, precision=0.5)["L_deg"] == 2.0
    assert run(looks, [frame(0)], t, precision=0.9)["L_deg"] == \
        pytest.approx(2.7)
    assert run(looks, [frame(0)], t, precision=0.5,
               implicit=3.2)["L_deg"] == pytest.approx(3.2)
    # Большой порог гасит взгляд на пять строк вверх (225 пикселей ≈
    # 5,9°): при остатке 7° его нет.
    looks, t = reading(back_at=8)
    assert run(looks, [frame(0)], t, implicit=7.0)["count"] == 0


def test_sno_alg_res_08_half_page_top_third_is_of_the_strip():
    """Режим половины страницы: «верхняя треть» — видимой полосы.
    Полоса — нижняя половина листа: скачок к её верху (y = 460) — уже
    верхняя треть полосы, и смена колонки узнаётся."""
    strip = [PAGE_X, 400, 595 * SCALE, 400]
    col1, t = reading(lines=7, x0=380, step=90, cols=3, top=420)
    col2, t = reading(lines=2, t0=t + 40, x0=720, step=80, cols=3, top=430)
    out = run(col1 + col2, [frame(0, strip=strip)], t + 100)
    assert out["shows"][0]["columns"] == 2
    assert out["count"] == 0
    # Во всю страницу та же точка (y = 430 из 800) — не верхняя треть:
    # скачок туда — взгляд назад.
    out = run(col1 + col2, [frame(0)], t + 100)
    assert out["shows"][0]["columns"] == 1
    assert out["count"] == 1


def test_sno_alg_res_08_rest_of_the_old_page_is_not_reading():
    """Перелистнул, а взгляд ещё внизу: вторая половина фиксации на
    новой странице фронта не ставит, и скачок к верху новой страницы —
    не взгляд назад."""
    first, t = reading(lines=14)
    flip = t
    # Взгляд у низа ещё 300 мс после смены страницы, потом — к верху.
    stay = [(t, t + 300, 620, 100 + 13 * 45)]
    second, t = reading(lines=5, t0=t + 340)
    out = run(first + stay + second, [frame(0), frame(flip, page=2)],
              t + 100)
    assert len(out["shows"]) == 2
    assert out["count"] == 0


def test_sno_alg_res_08_leaving_the_reader_ends_the_show():
    looks, t = reading(lines=6)
    more, t2 = reading(lines=6, t0=t + 5000, top=100)
    line = line_of(t2 + 100)
    line.screens = [(0.0, "reader"), (t + 1000, "shelf"),
                    (t + 4000, "reader")]
    out = reading_back.lookbacks(samples_of(looks + more), [], [frame(0)],
                                 SCREEN, line, None, PC, report.settings())
    assert len(out["shows"]) == 2
    assert out["count"] == 0


# --- журнал: возвраты на страницу назад ---------------------------------

def shown(t, page, was, cause="tap_zone", strip=1, was_strip=1):
    return {"t": t, "type": "page.shown", "book": "b", "page": page,
            "strip": strip, "data": {"cause": cause,
                                     "from": {"page": was,
                                              "strip": was_strip}}}


def test_sno_alg_res_08_page_backs_from_the_journal():
    events = [{"t": 0, "type": "book.open", "book": "b"},
              shown(1000, 2, 1), shown(5000, 3, 2),
              shown(9000, 2, 3),                       # назад
              shown(12000, 3, 2), shown(12800, 2, 3),  # промах
              shown(20000, 5, 2, cause="toc"),
              shown(25000, 1, 5, cause="toc"),         # навигация
              shown(30000, 4, 1, cause="search"),
              shown(31000, 4, 4, cause="mode", strip=1, was_strip=2),
              shown(40000, 4, 4, cause="key", strip=1, was_strip=2),
              {"t": 50000, "type": "book.close", "book": "b"},
              shown(55000, 1, 4)]                      # книга закрыта
    line = line_of(60_000)
    out = reading_back.page_backs(events, line, 2.0)
    kinds = [r["kind"] for r in out["rows"]]
    assert kinds == ["назад", "промах листания", "навигация",
                     "не листание", "назад"]
    assert out["backs"] == 2
    assert out["misflips"] == 1 and out["navigation"] == 1
    assert out["rows"][-1]["pages"] == 0      # полоса выше на той же
    assert out["per_min"] == pytest.approx(2 / 1.0)
    assert out["shows"] == 10
    assert out["causes"] == {"tap_zone": 1, "key": 1}


def test_sno_alg_res_08_back_after_slow_forward_is_a_real_back():
    events = [{"t": 0, "type": "book.open", "book": "b"},
              shown(1000, 2, 1), shown(4000, 1, 2)]
    out = reading_back.page_backs(events, line_of(10_000), 2.0)
    assert [r["kind"] for r in out["rows"]] == ["назад"]
