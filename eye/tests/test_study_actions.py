"""Шаг 36, SNO-ALG-RES-02: походы за книгой, момент выбора, эпизоды
поиска и меры действий — на журнале, собранном руками.

Ход сессии — `report.timeline.build` (шаг 34) без изменений; здесь
проверяется то, что сводный анализ строит поверх него.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from sno_eye.report import archive as arc
from sno_eye.report import timeline as tl
from sno_eye.study import actions

A = "book-A"
B = "book-B"
C = "book-C"


class Journal:
    def __init__(self):
        self.events = []
        self.inputs = {}
        self.screen = "testing"

    def e(self, t, kind, data=None, book=None, input=None, phase=None):
        row = {"seq": len(self.events) + 1, "t": t, "type": kind,
               "screen": self.screen}
        if data:
            row["data"] = data
        if book:
            row["book"] = book
        if input is not None:
            row["input"] = input
        if phase:
            row["phase"] = phase
        self.events.append(row)
        return self

    def nav(self, t, to, input=None):
        self.e(t, "nav.screen", {"from": self.screen, "to": to},
               input=input)
        self.screen = to
        return self

    def tap(self, n, t, screen="shelf", dev="mouse", kind="tap"):
        self.inputs[n] = {"n": n, "t": t, "dev": dev, "kind": kind,
                          "screen": screen}
        return n

    def record(self, stop=600_000):
        self.events.insert(0, {"t": 0, "type": "recording.start",
                               "screen": "testing",
                               "data": {"participant": "1"}})
        self.e(stop, "recording.stop", {"study_ms": stop})
        for seq, row in enumerate(sorted(self.events, key=lambda r: r["t"]),
                                  start=1):
            row["seq"] = seq
        r = arc.Record(path=Path("x.zip"), check={}, manifest={
            "recording": {"duration_ms": stop}}, events=sorted(
                self.events, key=lambda r: r["seq"]), inputs=self.inputs)
        return r, tl.build(r)


def test_sno_alg_res_02_transit_shelf_to_map_is_one_trip():
    """Через полку на карту за пару секунд — один поход, не два; выбор
    на карте — касание звезды, время в карточке — отдельно."""
    j = Journal()
    j.nav(0, "shelf").nav(2000, "galaxy")
    j.e(5000, "galaxy.star", {"book": A}).e(5000, "galaxy.card.open",
                                            {"book": A})
    j.nav(6000, "reader").e(6050, "book.open", {"via": "galaxy"}, book=A)
    rec, line = j.record()
    trips = actions.trips(rec, line)
    assert len(trips) == 1
    t = trips[0]
    assert t.complete and t.book == A and t.via == "galaxy"
    assert t.choice == 5000
    assert t.search_ms == 5000
    assert t.card_ms == 1050
    assert t.screens == ["shelf", "galaxy"]


def test_sno_alg_res_02_other_screen_and_away_are_not_search():
    """Заход в «Тестирование» посреди похода поход не рвёт, но время там
    в поиск не идёт; отлучка — тоже."""
    j = Journal()
    j.nav(0, "shelf").nav(1000, "testing").nav(3000, "shelf")
    j.e(4000, "app.background", {"state": "hidden"})
    j.e(6000, "app.foreground", {"away_ms": 2000, "kind": "hidden"})
    j.nav(9000, "reader").e(9040, "book.open", {"via": "shelf"}, book=A)
    rec, line = j.record()
    t = actions.trips(rec, line)[0]
    assert t.choice == 9040
    # До выбора на полке 9 с: − 2 с в «Тестировании» − 2 с отлучки;
    # 40 мс от ухода в читалку до `book.open` — уже не поиск.
    assert t.search_ms == pytest.approx(5000)


def test_sno_alg_res_02_four_queries_are_one_episode():
    """«ане», «аневри», «аневриз», «аневризма» — один поиск."""
    j = Journal()
    j.nav(0, "shelf")
    for k, t in enumerate((1000, 1500, 2000, 2600)):
        j.e(t, "search.query", {"scope": "shelf", "chars": 3 + k})
    j.e(3500, "search.result.open", {"scope": "shelf", "book": B})
    j.nav(3510, "reader").e(3560, "book.open", {"via": "shelf_search"},
                            book=B)
    rec, line = j.record()
    assert actions.episodes(rec.events, "shelf") == [(1000, 3500)]
    t = actions.trips(rec, line)[0]
    assert t.shelf_search
    # Выбор из найденного — открытие строки найденного.
    assert t.choice == 3500


def test_sno_alg_res_02_episode_ends_by_leaving_the_screen():
    j = Journal()
    j.nav(0, "shelf").e(1000, "search.query", {"scope": "shelf"})
    j.nav(2000, "galaxy").e(2500, "search.query", {"scope": "book"})
    rec, _ = j.record()
    assert actions.episodes(rec.events, "shelf") == [(1000, 2000)]


def journal_three_trips():
    j = Journal()
    j.nav(0, "shelf")
    t = 0
    plan = [(A, True), (B, True), (C, False), (A, False)]
    for k, (book, search) in enumerate(plan):
        if search:
            j.e(t + 500, "search.query", {"scope": "shelf"})
            j.e(t + 1500, "search.result.open",
                {"scope": "shelf", "book": book})
            via = "shelf_search"
        else:
            via = "shelf"
        j.nav(t + 2000, "reader").e(t + 2040, "book.open", {"via": via},
                                    book=book)
        j.e(t + 60_000, "book.close", {"read_ms": 58_000}, book=book)
        j.nav(t + 60_000, "shelf")
        t += 70_000
    return j


def test_sno_alg_res_02_last_trip_with_search():
    """Номер последнего похода с поиском / число походов: искали в
    первом и втором из четырёх — 2/4."""
    rec, line = journal_three_trips().record(stop=400_000)
    found = actions.trips(rec, line)
    m = actions.measures(rec, line, found, "I", (1 / 3, 2 / 3))["measures"]
    complete = [t for t in found if t.complete]
    assert len(complete) == 4
    assert m["actions.last_search_trip"] == pytest.approx(2 / 4)
    assert m["actions.search_trip_share"] == pytest.approx(2 / 4)
    assert m["actions.repeat_share"] == pytest.approx(1 / 4)
    # Счёт — в минуту изучения (`data.study_ms`), а не суммой.
    assert m["actions.books_per_min"] == pytest.approx(3 / (400_000 / 60_000))
    assert m["actions.via_found"] == pytest.approx(0.5)
    # После последнего закрытия книги поход не доведён: он есть, но в
    # медиану времени до выбора не идёт.
    assert not found[-1].complete
    assert m["actions.read_per_book"] == pytest.approx(58)
    assert [t.first_time for t in complete] == [True, True, True, False]


def test_sno_alg_res_02_empty_taps():
    """Касание, на которое не сослалось ни одно событие, — пустое; путь
    мыши, колесо, клавиша и касания экспериментатора не в счёт."""
    j = Journal()
    j.nav(0, "shelf")
    for n in range(1, 6):
        j.tap(n, 1000 * n)
    j.tap(6, 6000, dev="hover")
    j.tap(7, 6500, dev="wheel")
    j.tap(8, 7000, screen="recording_dot")
    j.tap(9, 7500, kind="drag")
    j.e(1000, "shelf.scroll", input=1).e(3000, "panel.open", input=3)
    rec, line = j.record()
    m = actions.measures(rec, line, actions.trips(rec, line), "I",
                         (1 / 3, 2 / 3))
    assert m["info"]["taps"] == 5
    assert m["info"]["empty_taps"] == 3
    assert m["measures"]["actions.empty_tap_share"] == pytest.approx(0.6)
    assert m["measures"]["actions.taps_per_min"] == pytest.approx(5 / 10)


def test_sno_alg_res_02_card_without_reading():
    j = Journal()
    j.nav(0, "galaxy")
    j.e(1000, "galaxy.card.open", {"book": A})
    j.e(2000, "galaxy.card.close", {"book": A})
    j.e(3000, "galaxy.star", {"book": B}).e(3000, "galaxy.card.open",
                                             {"book": B})
    j.e(3500, "galaxy.view", {"cause": "drag"})
    j.nav(4000, "reader").e(4050, "book.open", {"via": "galaxy"}, book=B)
    rec, line = j.record()
    found = actions.trips(rec, line)
    m = actions.measures(rec, line, found, "II", (1 / 3, 2 / 3))
    assert m["measures"]["actions.cards_unread_share"] == pytest.approx(0.5)
    assert m["measures"]["actions.map_views_per_trip"] == 1
    assert m["info"]["search_mode"] == "картой"


def test_sno_alg_res_02_phone_record_counts_from_start():
    """Запись без айтрекера: `study.start` нет — счёт от старта записи."""
    j = Journal()
    j.nav(10, "shelf").nav(4000, "reader").e(4040, "book.open",
                                             {"via": "shelf"}, book=A)
    rec, line = j.record(stop=1_200_000)
    assert line.study_start == 0
    t = actions.trips(rec, line)[0]
    assert t.search_ms == pytest.approx(3990)
