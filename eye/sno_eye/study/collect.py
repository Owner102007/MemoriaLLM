"""Шаг 1 — приём записей: обход, годность, паспорт, эталон, повторы
(SNO-ALG-RES-01, шаги 1–7 и 10–11).

Откуда данные: архивы `sno2026_*.zip`. Годность — «Проверка записи»
(`record_check.check_archive`) без изменений; чтение архива — «Разбор
записи» (`report.archive.load`), который сам вызывает проверку и не
берёт негодный архив; ход сессии — `report.timeline.build`. Паспорт —
`manifest.json`, эталон — `recording.start` журнала и
`snapshot_start.json`, тест — файлы `clt/` архива.
Технология: стандартная библиотека — `pathlib` обходит папки с
подпапками, `zipfile` и `json` читают архив без распаковки, `hashlib`
считает SHA-256 архива для `исходные.json`.
Метод: SNO-ALG-RES-01; решения владельца АК6 (повторы), АК7 (скрипт
сравнивает то, что ему дали), АК10 (эталон), АК11 (короткое
изучение), Т19 (взгляд не хуже 3°).
Вход → выход: папки и архивы → записи (`dict` на архив): паспорт,
эталон, длина изучения, тест, действия и походы, причины «не идёт».
"""

from __future__ import annotations

import hashlib
import zipfile
from datetime import datetime
from pathlib import Path

from .. import record_check as rc
from ..report import archive as arc
from ..report import timeline as tl
from . import actions, clt

# Эталон словами (SNO-ALG-RES-01, шаг 7).
ETALON_YES = "да"
ETALON_NO = "нет"
ETALON_NOT_RESET = "не сброшено"
ETALON_UNKNOWN = "неизвестно"

PHONE_STRATUM = "телефон"


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def find(paths: list[str]) -> list[Path]:
    """Архивы среди [paths]: файл `.zip` — как есть, папка — все её
    `sno2026_*.zip` **с подпапками** (`Path.rglob`): архивы можно
    разложить по папкам ПК. `record_check.collect` в подпапки не
    заходит — обход здесь свой, а проверка — его. Порядок — по пути."""
    found: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            found.extend(sorted(path.rglob("sno2026_*.zip")))
        elif path.is_file():
            found.append(path)
    seen: set[str] = set()
    unique = []
    for path in found:
        key = str(path.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _anchor(text) -> datetime | None:
    """`recording.clock_anchor` — ISO 8601 со смещением пояса."""
    if not isinstance(text, str):
        return None
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def etalon(record: arc.Record) -> tuple[str, list[str]]:
    """Начата ли запись с эталонного состояния (SNO-F-CFG-04).

    | ответ        | когда                                              |
    |--------------|----------------------------------------------------|
    | да           | приложение сказало «совпадает»                     |
    | нет          | сброс был, следов нет, но приложение сказало       |
    |              | «отличается»                                       |
    | не сброшено  | сброса не было или на старте лежат чужие следы     |
    | неизвестно   | снимка или эталона нет (прежняя сборка)            |

    Чужие следы — то, по чему приложение само говорит «отличается»
    (`StateSnapshot.matches` в `lib/sno/reference_state.dart`): записи
    читателя (`traces`) и настройки (`settings`), среди них — время в
    книгах `sno.book_times`, от которого звёзды карты разного
    размера."""
    said = None
    for e in record.events:
        if e["type"] == "recording.start":
            value = _dict(e.get("data")).get("matches_reference")
            said = value if isinstance(value, bool) else None
            break
    snap = record.snapshot
    reference = _dict(snap.get("reference")) if snap else {}
    if said is None and isinstance(reference.get("matches"), bool):
        said = reference["matches"]
    if said is True:
        return ETALON_YES, []
    if snap is None or not reference:
        return ETALON_UNKNOWN, ["снимка состояния или эталона в записи нет"]
    reasons = []
    reset = snap.get("last_reset")
    traces = snap.get("traces")
    settings = _dict(snap.get("settings"))
    if not reset:
        reasons.append("сброса не было")
    if isinstance(traces, int) and traces > 0:
        reasons.append(f"на старте записей прежнего читателя {traces}")
    if "sno.book_times" in settings:
        reasons.append("на старте время в книгах прежнего участника")
    other = sorted(k for k in settings if k != "sno.book_times")
    if other:
        reasons.append("на старте настройки прежнего участника: "
                       + ", ".join(other[:4]))
    if reasons:
        return ETALON_NOT_RESET, reasons
    return ETALON_NO, ["сброс был, но приложение сказало «отличается от "
                       "эталона»"]


def stratum(passport: dict) -> str:
    """Слой сравнения — ПК: код устройства вместе с камерой. Телефоны —
    один слой: у каждого свой код, а слой из одного участника ничего не
    сравнивает."""
    if passport.get("platform") == "телефон":
        return PHONE_STRATUM
    if passport.get("platform") != "ПК":
        return f"{passport.get('device') or '?'} · платформа неизвестна"
    camera = passport.get("camera")
    device = passport.get("device") or "?"
    return f"{device} · {camera}" if camera else device


def passport(record: arc.Record) -> dict:
    """Паспорт записи из `manifest.json` и итога проверки."""
    m = record.manifest
    check = record.check
    recording = _dict(m.get("recording"))
    eye = _dict(m.get("eye_tracker"))
    camera = _dict(_dict(eye.get("place")).get("camera")).get("name")
    out = {
        "participant": check.get("participant"),
        "branch": check.get("branch"),
        "platform": check.get("platform"),
        "device": check.get("device"),
        "camera": camera if isinstance(camera, str) and camera else None,
        "model": check.get("model"),
        "series": check.get("study_tag"),
        "version": check.get("version"),
        "recording_id": recording.get("id"),
        "clock_anchor": recording.get("clock_anchor"),
        "finished": recording.get("finished") is True,
        "check_verdict": check.get("verdict_text"),
        "check_notes": list(check.get("notes") or []),
    }
    out["stratum"] = stratum(out)
    return out


def gaze(record: arc.Record, limits: dict) -> dict:
    """Взгляд сессии: записан ли и входит ли в анализ — средняя
    точность проверок в начале и в конце не хуже `include_deg` (Т19);
    одна из двух неизвестна — по известной, как у «Разбора записи»."""
    check = record.check
    present = record.eye.get("present") is True and bool(record.gaze)
    start, end = check.get("start_deg"), check.get("end_deg")
    known = [v for v in (start, end) if isinstance(v, (int, float))]
    mean = sum(known) / len(known) if known else None
    included = present and mean is not None and \
        mean <= float(limits["include_deg"])
    if not present:
        why = rc.REASONS.get(str(record.eye.get("reason")),
                             str(record.eye.get("reason") or ""))
        if check.get("platform") != "ПК":
            why = "телефон — взгляд не пишется"
        elif record.eye.get("present") is True:
            why = "в манифесте взгляд есть, а строк взгляда нет"
        reason = why or "взгляда нет"
    elif mean is None:
        reason = "точность взгляда неизвестна"
    elif not included:
        reason = (f"точность {mean:.1f}° хуже "
                  f"{float(limits['include_deg']):.0f}°").replace(".", ",")
    else:
        reason = None
    return {"present": present, "start_deg": start, "end_deg": end,
            "mean_deg": mean, "included": included, "reason": reason,
            "precision_deg": _dict(record.eye.get("calibration"))
            .get("precision_deg"),
            "valid_share": check.get("valid_share"), "fps": check.get("fps")}


def load(path: Path, limits: dict, cfg: dict) -> dict:
    """Одна запись: всё, что нужно сравнению, без самого архива.

    Негодный архив не роняет прогон: он назван с причиной
    (`status: bad`)."""
    entry: dict = {"archive": path.name, "path": str(path),
                   "sha256": None, "status": "ok", "reason": None}
    try:
        entry["sha256"] = sha256(path)
    except OSError as e:
        entry.update(status="bad", reason=f"архив не читается: {e}")
        return entry
    try:
        record = arc.load(path, limits)
    except arc.Refused as e:
        entry.update(status="bad", reason=f"архив не годен: {e.text}")
        return entry
    except Exception as e:  # noqa: BLE001 — одна запись не роняет пачку
        entry.update(status="bad", reason=f"разбор архива упал: {e!r}")
        return entry
    try:
        with zipfile.ZipFile(path) as archive:
            files = clt.load_files(archive, archive.namelist())
        line = tl.build(record)
        info = passport(record)
        entry.update(info)
        entry["study_s"] = actions.study_ms(record, line) / 1000
        entry["etalon"], entry["etalon_reasons"] = etalon(record)
        entry["gaze"] = gaze(record, limits)
        entry["test"] = clt.read(files, record.manifest, record.events,
                                 float(cfg["scale_tolerance"]))
        found = actions.trips(record, line)
        done = actions.measures(record, line, found, info["branch"],
                                tuple(cfg["via_map"]))
        entry["actions"] = done["measures"]
        entry["actions_info"] = done["info"]
        entry["search_mode"] = done["info"]["search_mode"]
        entry["trips"] = [_trip_row(t, line, record) for t in found]
    except Exception as e:  # noqa: BLE001
        entry.update(status="bad", reason=f"разбор записи упал: {e!r}")
    return entry


def _trip_row(trip: actions.Trip, line: tl.Timeline,
              record: arc.Record) -> dict:
    s0 = line.study_start
    return {
        "n": trip.n, "start_s": (trip.start - s0) / 1000,
        "duration_s": (trip.end - trip.start) / 1000,
        "complete": trip.complete, "book": trip.book,
        "title": line.titles.get(trip.book or ""),
        "via": actions.VIA_WORDS.get(trip.via or "", trip.via),
        "time_to_choice_s": trip.search_ms / 1000 if trip.complete
        else None,
        "card_s": None if trip.card_ms is None else trip.card_ms / 1000,
        "shelf_search": trip.shelf_search,
        "map_s": trip.map_ms / 1000, "views": trip.views,
        "first_time": trip.first_time,
        "screens": " → ".join(trip.screens),
    }


def fill_cameras(entries: list[dict]) -> None:
    """Сессия ПК без места записи (айтрекер не настроен) не знает
    камеры. Если у того же устройства в наборе одна камера — это она:
    иначе один ПК распался бы на два слоя."""
    known: dict[str, set] = {}
    for e in entries:
        if e.get("platform") == "ПК" and e.get("camera"):
            known.setdefault(e.get("device"), set()).add(e["camera"])
    for e in entries:
        if e["status"] != "ok" or e.get("platform") != "ПК" or \
                e.get("camera"):
            continue
        cameras = known.get(e.get("device")) or set()
        if len(cameras) == 1:
            e["camera"] = next(iter(cameras))
            e["stratum"] = stratum(e)


def mark_repeats(entries: list[dict]) -> None:
    """Копии и повторы (АК6).

    * Тот же `recording.id` дважды — копия одного архива: берётся
      первый по пути, остальные — «копия».
    * Код участника встретился дважды — в статистике первая по
      `recording.clock_anchor` завершённая сессия, остальные —
      «повтор». Имя файла для порядка не годится: оно сортируется
      сначала по коду ПК."""
    seen_ids: dict[str, str] = {}
    for e in entries:
        if e["status"] != "ok":
            continue
        rid = e.get("recording_id")
        if rid and rid in seen_ids:
            e["duplicate"] = f"копия архива {seen_ids[rid]}"
        elif rid:
            seen_ids[rid] = e["archive"]
    by_code: dict[str, list[dict]] = {}
    for e in entries:
        if e["status"] == "ok" and not e.get("duplicate") and \
                e.get("participant"):
            by_code.setdefault(str(e["participant"]), []).append(e)
    for group in by_code.values():
        if len(group) < 2:
            continue

        def key(e):
            t = _anchor(e.get("clock_anchor"))
            # Без времени — в конец; завершённые раньше незавершённых.
            return (not e.get("finished"), t is None,
                    t.timestamp() if t else 0.0, e["archive"])

        group.sort(key=key)
        for e in group[1:]:
            e["duplicate"] = f"повтор участника — в статистике " \
                             f"{group[0]['archive']}"
