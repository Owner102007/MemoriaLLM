"""Шаг 7б — момент долгого взгляда без действий (SNO-ALG-RES-09; шаг 40).

Откуда данные: «Разбор записи» (`report.analyse`) без изменений —
фиксации порогом сессии в версии взгляда исследования (с поправкой
дрейфа), кадры с видами (`_labels`: смотрел ли участник на экран),
отрезки движения раскладки (`_spans`), опоры поправки дрейфа
(`_anchors`), группы звёзд карты с подписями (`_zones`); поток ввода
`input.jsonl` и кадры раскладки записи; ход сессии (`report.timeline`).
Технология: стандартная библиотека — отрезки режутся проходом по
отсортированным разрезам, кадры и фиксации ищутся `bisect`.
Метод: SNO-ALG-RES-09, «Момент»:
* разрез — любая строка потока ввода, кроме пути мыши без нажатия
  (`dev: hover`), всем своим отрезком `[t, t + dt]`; новый кадр
  раскладки и отрезок движения; отлучка; смена экрана; края изучения и
  смена окна;
* кандидат — отрезок между разрезами на чтении или на поиске (полка и
  карта, `study.actions.SEARCH_SCREENS`), не короче
  `portrait.moment_min_s`;
* «смотрел» — годный взгляд на экране не меньше `portrait.look_share`
  времени отрезка и не меньше `portrait.moment_min_fix` фиксаций;
  меньше фиксаций — «взгляд стоял»: помечен, не берётся;
* мера отрезка — секунды смотрения, а не длина (Holmqvist, Nyström,
  Mulvey, ETRA 2012: потерянный взгляд — не время внимания);
* два момента — самый долгий в чтении и самый долгий в поиске (АЛ2).
Вход → выход: разбор записи, запись и ход → моменты двух фаз с
фиксациями, точностью и σ пятна, разрезанные кандидаты для
`моменты.csv`, два числа участника для семьи «Д. Портрет».

Почему «восстанавливать», а не снимать экран, и как рисуется снимок —
`study.screen_shot`.
"""

from __future__ import annotations

import bisect
import math

from ..report.measures import margin_deg
from .actions import SEARCH_SCREENS, _screen_time

READING = "reading"
SEARCH = "search"
PHASES = (READING, SEARCH)
PHASE_WORDS = {READING: "чтение", SEARCH: "поиск"}

# Виды кадров «Разбора записи», в которые участник на экран не смотрел
# (`report.measures.label_samples`): вне приложения, лица нет, моргание
# и негодные кадры, взгляд за краем экрана, кадров взгляда нет.
NOT_LOOKING = ("away", "no_face", "blink", "outside", "no_frames")

# Путь мыши без нажатия — не действие (# Выбор наш: от него в
# приложении ничего не меняется); пишется пачкой, точка — раз в 100 мс
# (`kHoverMs`, `lib/sno/recording/input_tap.dart`).
HOVER = "hover"
HOVER_POINT_MS = 100.0

OK = "ok"
SHORT = "short"
LITTLE = "little"
STARE = "stare"
STATUS_WORDS = {
    OK: "взят",
    SHORT: "короче порога",
    LITTLE: "на экран смотрел мало",
    STARE: "взгляд стоял — фиксаций мало",
}


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None


# --- разрезы и отрезки ------------------------------------------------------

def cuts(record, line, spans: list, lo: float, hi: float
         ) -> tuple[list[tuple[float, float]], list[tuple[float, float]]]:
    """Что режет момент: `(разрезы, путь мыши)`.

    Разрез — отрезок `[a, b]` (точка — `a == b`): строка ввода, кроме
    пути мыши, — всем отрезком `[t, t + dt]` (удержание и протяжка режут
    целиком); новый кадр раскладки; отрезок движения раскладки; отлучка;
    смена экрана по журналу (у записей без кадров раскладки экран иначе
    не виден). Путь мыши — точки `(миг, 1)` для доли «мышь двигалась»."""
    out: list[tuple[float, float]] = []
    hover: list[tuple[float, float]] = []
    for row in record.inputs.values():
        t = _num(row.get("t"))
        if t is None:
            continue
        if row.get("dev") == HOVER:
            for point in row.get("trail") or []:
                if isinstance(point, (list, tuple)) and point:
                    dt = _num(point[0])
                    if dt is not None:
                        hover.append((t + dt, 1.0))
            continue
        dt = max(0.0, _num(row.get("dt")) or 0.0)
        out.append((t, t + dt))
    for frame in record.frames:
        t = float(frame["t"])
        out.append((t, t))
    for a, b in spans:
        out.append((a, b))
    for a, b, _ in line.away:
        out.append((a, b))
    for t, _ in line.screens:
        out.append((t, t))
    out = [(max(a, lo), min(b, hi)) for a, b in out if b >= lo and a <= hi]
    out.sort()
    hover.sort()
    return out, hover


def gaps(blocks: list[tuple[float, float]], lo: float, hi: float
         ) -> list[tuple[float, float]]:
    """Отрезки `[lo, hi)` между разрезами [blocks] (отсортированы по
    началу). Разрез-точка делит отрезок на два."""
    out = []
    edge = lo
    for a, b in blocks:
        if a > edge:
            out.append((edge, a))
        edge = max(edge, b)
    if hi > edge:
        out.append((edge, hi))
    return out


def phase_of(screen: str | None) -> str | None:
    if screen == "reader":
        return READING
    if screen in SEARCH_SCREENS:
        return SEARCH
    return None


# --- отрезок: сколько смотрел -----------------------------------------------

class Labels:
    """Кадры с видами «Разбора записи» `(t, ms, строго, мягко)` и время
    взгляда на экране в отрезке."""

    def __init__(self, labels: list[tuple]):
        self.labels = labels
        self.times = [row[0] for row in labels]

    def looked_ms(self, a: float, b: float) -> float:
        """Сколько мс отрезка [a, b) годный взгляд был на экране: кадр
        занимает `[t, t + ms)` и идёт в счёт пересечением с отрезком."""
        i = max(0, bisect.bisect_right(self.times, a) - 1)
        total = 0.0
        while i < len(self.labels):
            t, ms, _, soft = self.labels[i]
            if t >= b:
                break
            if soft not in NOT_LOOKING:
                total += max(0.0, min(t + ms, b) - max(t, a))
            i += 1
        return total


def fixations_in(fixes: list[dict], a: float, b: float) -> list[dict]:
    """Фиксации отрезка: начались в нём и не на отрезке движения;
    длительность обрезана концом отрезка."""
    out = []
    for f in fixes:
        if f.get("moving") or not a <= f["start"] < b:
            continue
        end = min(float(f["end"]), b)
        out.append({"start": f["start"], "end": end,
                    "d": end - f["start"], "x": f["x"], "y": f["y"],
                    "zone": f.get("zone"), "book": f.get("book"),
                    "category": f.get("category")})
    return out


def hover_share(points: list[tuple[float, float]], a: float, b: float
                ) -> float:
    """Доля отрезка, где мышь двигалась без нажатия: точка пути — 100 мс
    движения (запись пишет путь десять точек в секунду)."""
    if b <= a:
        return 0.0
    i = bisect.bisect_left(points, (a, 0.0))
    j = bisect.bisect_left(points, (b, 0.0))
    return min(1.0, (j - i) * HOVER_POINT_MS / (b - a))


def assess(a: float, b: float, labels: Labels, fixes: list[dict],
           pc: dict) -> dict:
    """Кандидат [a, b): секунды смотрения, доля, фиксации и вердикт."""
    length = b - a
    looked = labels.looked_ms(a, b)
    own = fixations_in(fixes, a, b)
    share = looked / length if length > 0 else 0.0
    if length < float(pc["moment_min_s"]) * 1000:
        status = SHORT
    elif share < float(pc["look_share"]):
        status = LITTLE
    elif len(own) < int(pc["moment_min_fix"]):
        status = STARE
    else:
        status = OK
    return {"a": a, "b": b, "length_ms": length, "looked_ms": looked,
            "share": share, "fixations": own, "status": status}


def nearest_anchor_s(anchors: list[float], t: float) -> float | None:
    """Секунд от мига [t] до ближайшей опоры поправки дрейфа."""
    if not anchors:
        return None
    i = bisect.bisect_left(anchors, t)
    near = [abs(anchors[k] - t) for k in (i - 1, i)
            if 0 <= k < len(anchors)]
    return min(near) / 1000


# --- одна запись --------------------------------------------------------------

def prepare(res: dict, record, cfg: dict, report_cfg: dict) -> dict:
    """Моменты одной записи и кандидаты для `моменты.csv`.

    Ответ: `moments` — по фазе момент или `None`; `reasons` — почему
    момента нет; `candidates` — отрезки не короче порога (взятые и
    отвергнутые, с причиной); `numbers` — два числа участника."""
    pc = cfg["portrait"]
    line = res["_timeline"]
    screen = res["_screen"]
    lo = line.study_start
    hi = line.study_end if line.window_changed is None else \
        min(line.study_end, line.window_changed)
    blocks, hover = cuts(record, line, res.get("_spans") or [], lo, hi)
    labels = Labels(res.get("_labels") or [])
    fixes = res.get("fixations") or []
    frame_times = [float(f["t"]) for f in record.frames]
    # Опоры дрейфа — только у версии с поправкой: у `raw` поправки нет.
    anchors = (res.get("_anchors") or []) \
        if report_cfg.get("version") == "drift" else []
    zones = res.get("_zones")
    min_ms = float(pc["moment_min_s"]) * 1000
    best: dict = {p: None for p in PHASES}
    stronger: dict = {p: None for p in PHASES}
    candidates = []
    search_ok_ms = 0.0
    longest_search = 0.0
    for a, b in gaps(blocks, lo, hi):
        phase = phase_of(line.screen_at((a + b) / 2))
        if phase is None or b <= a:
            continue
        seg = assess(a, b, labels, fixes, pc)
        seg["phase"] = phase
        if phase == SEARCH and seg["share"] >= float(pc["look_share"]) \
                and len(seg["fixations"]) >= int(pc["moment_min_fix"]):
            # Мера «самый долгий взгляд без действий в поиске» — без
            # порога длины: # Выбор наш — короткий отрезок, где
            # смотрели, честнее нуля.
            longest_search = max(longest_search, seg["looked_ms"])
        if seg["length_ms"] < min_ms:
            continue
        candidates.append(seg)
        if seg["status"] == OK:
            if phase == SEARCH:
                search_ok_ms += seg["length_ms"]
            if best[phase] is None or \
                    seg["looked_ms"] > best[phase]["looked_ms"]:
                best[phase] = seg
        elif seg["status"] == STARE and (
                stronger[phase] is None or
                seg["looked_ms"] > stronger[phase]["looked_ms"]):
            stronger[phase] = seg
    moments: dict = {}
    reasons: dict = {}
    for phase in PHASES:
        seg = best[phase]
        if seg is None:
            moments[phase] = None
            reasons[phase] = (
                "в поиске не было долгих взглядов без действий — искал "
                "быстро" if phase == SEARCH else
                "в чтении не было долгих взглядов без действий")
            continue
        mid = (seg["a"] + seg["b"]) / 2
        i = bisect.bisect_right(frame_times, seg["a"]) - 1
        frame = record.frames[i] if i >= 0 else None
        acc = margin_deg(mid, line)
        sigma = math.sqrt(1.0 + acc * acc)
        stare = stronger[phase]
        moments[phase] = {
            **seg, "frame": frame, "screen": line.screen_at(mid),
            "minute": (seg["a"] - lo) / 60_000,
            "accuracy_deg": acc, "sigma_deg": sigma,
            "sigma_px": screen.px_for_deg(sigma),
            "hover_share": hover_share(hover, seg["a"], seg["b"]),
            "anchor_s": nearest_anchor_s(anchors, mid),
            "groups": ([{"name": g["name"], "label": g["label"]}
                        for g in zones.groups(frame)]
                       if zones is not None and frame is not None else []),
            "stare_longer": (stare["looked_ms"] if stare is not None and
                             stare["looked_ms"] > seg["looked_ms"] else None),
        }
        for seg2 in candidates:
            if seg2 is seg:
                seg2["taken"] = True
    search_ms = _screen_time(line, lo, hi, SEARCH_SCREENS)
    numbers = {
        "portrait.search_still_s": (longest_search / 1000
                                    if search_ms > 0 else None),
        "portrait.search_still_share": (search_ok_ms / search_ms
                                         if search_ms > 0 else None),
    }
    return {"moments": moments, "reasons": reasons,
            "candidates": [{k: v for k, v in c.items() if k != "fixations"}
                           | {"fix_count": len(c["fixations"])}
                           for c in candidates],
            "numbers": numbers, "study_start": lo,
            # Названия и категории книг — для снимка полки и карты.
            "titles": dict(line.titles),
            "categories": dict(line.categories)}
