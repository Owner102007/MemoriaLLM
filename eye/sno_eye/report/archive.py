"""Архив записи для разбора (SNO-F-RES-03, SNO-ALG-EYE-05, шаг 1).

Сначала архив проходит «Проверку записи» (`record_check`): негодный
(испорченный файл, нет журнала, чужая схема) не разбирается — отказ
словами с тем, что именно не так. Годный читается целиком: журнал,
ввод, кадры раскладки, взгляд, калибровка спутника, проверки точности
и снимок полки на старте.

Строки потоков читаются тем же строгим правилом, что у проверки:
`NaN` и `Infinity` — мусор, строка без своего поля пропускается.
"""

from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from .. import record_check as rc


class Refused(Exception):
    """Архив не разбирается; [text] — почему, словами."""

    def __init__(self, text: str):
        super().__init__(text)
        self.text = text


@dataclass
class Record:
    """Что разбор знает о записи."""

    path: Path
    check: dict
    manifest: dict
    events: list[dict] = field(default_factory=list)
    inputs: dict[int, dict] = field(default_factory=dict)
    frames: list[dict] = field(default_factory=list)
    gaze: list[dict] = field(default_factory=list)
    calibration: dict | None = None
    checks: list[dict] = field(default_factory=list)
    snapshot: dict | None = None
    has_layout: bool = False
    has_input: bool = False

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def stem(self) -> str:
        name = self.path.name
        return name[:-4] if name.lower().endswith(".zip") else name

    @property
    def eye(self) -> dict:
        value = self.manifest.get("eye_tracker")
        return value if isinstance(value, dict) else {}


def rows(data: bytes | None) -> list[dict]:
    """Строки потока JSON по строгому правилу «Проверки записи»."""
    return list(rc._jsonl(data or b""))


def _json(data: bytes | None):
    if data is None:
        return None
    try:
        return json.loads(data.decode("utf-8"),
                          parse_constant=rc._strict_constant)
    except (UnicodeDecodeError, ValueError):
        return None


def _int(value) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) \
        else None


def _num(value) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _rect(value) -> list[float] | None:
    if isinstance(value, list) and len(value) == 4:
        numbers = [_num(v) for v in value]
        if all(v is not None for v in numbers):
            return numbers  # type: ignore[return-value]
    return None


def _frame(row: dict) -> dict | None:
    """Кадр раскладки, у которого есть всё, что нужно обратному
    переводу; зона без вида или места выбрасывается, лист без своих
    чисел — тоже: кадр с мусором не роняет разбор целиком."""
    viewport = row.get("viewport")
    t = _num(row.get("t"))
    if not isinstance(viewport, dict) or t is None:
        return None
    w, h = _num(viewport.get("w")), _num(viewport.get("h"))
    if not w or not h or w <= 0 or h <= 0:
        return None
    regions = []
    for region in row.get("regions") or []:
        if not isinstance(region, dict) or \
                not isinstance(region.get("kind"), str):
            continue
        rect = _rect(region.get("rect"))
        if rect is None:
            continue
        clean = dict(region, rect=rect, z=_num(region.get("z")) or 0.0)
        if not isinstance(clean.get("id"), str):
            clean["id"] = ""
        if not isinstance(clean.get("info"), dict):
            clean.pop("info", None)
        if not isinstance(clean.get("marks"), list):
            clean.pop("marks", None)
        else:
            clean["marks"] = [
                m for m in clean["marks"] if isinstance(m, dict)
                and isinstance(m.get("id"), str)
                and all(_num(m.get(k)) is not None for k in "xyr")]
        regions.append(clean)
    frame = dict(row, t=t, viewport=dict(viewport, w=w, h=h),
                 regions=regions)
    sheet = row.get("sheet")
    if sheet is not None:
        pages = sheet.get("pages") if isinstance(sheet, dict) else None
        ok = isinstance(pages, list) and _num(sheet.get("scale")) and \
            _rect(sheet.get("strip")) is not None and all(
                isinstance(p, dict) and _int(p.get("page")) is not None
                and all(_num(p.get(k)) is not None for k in "xywh")
                for p in pages)
        if ok:
            frame["sheet"] = dict(sheet, neighbours=[
                n for n in sheet.get("neighbours") or []
                if isinstance(n, dict) and _rect(n.get("rect"))
                and isinstance(n.get("side"), str)])
        else:
            frame.pop("sheet", None)
    return frame


def load(path: Path, limits: dict | None = None) -> Record:
    """Читает архив [path]; негодный — [Refused]."""
    path = Path(path)
    report = rc.check_archive(path, limits)
    if report["verdict"] == rc.BAD:
        problems = report.get("problems") or ["архив не годится"]
        raise Refused("; ".join(problems))
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())

        def read(name: str) -> bytes | None:
            if name not in names:
                return None
            try:
                return archive.read(name)
            except Exception as e:  # noqa: BLE001
                raise Refused(f"файл {name} не читается: {e}") from None

        manifest = _json(read("manifest.json"))
        if not isinstance(manifest, dict):
            raise Refused("manifest.json не читается")
        record = Record(path=path, check=report, manifest=manifest)

        events = [r for r in rows(read("events.jsonl"))
                  if _int(r.get("seq")) is not None
                  and _int(r.get("t")) is not None
                  and isinstance(r.get("type"), str)]
        events.sort(key=lambda r: r["seq"])
        record.events = events

        record.has_input = "input.jsonl" in names
        for row in rows(read("input.jsonl")):
            n = _int(row.get("n"))
            if n is not None and _num(row.get("t")) is not None:
                record.inputs[n] = row

        record.has_layout = "layout.jsonl" in names
        frames = [f for f in (_frame(r) for r in rows(read("layout.jsonl")))
                  if f is not None]
        frames.sort(key=lambda r: (r["t"], _int(r.get("n")) or 0))
        record.frames = frames

        gaze = [r for r in rows(read("eye/gaze.jsonl"))
                if _num(r.get("t")) is not None]
        gaze.sort(key=lambda r: (r["t"], _int(r.get("n")) or 0))
        record.gaze = gaze

        calibration = _json(read("eye/calibration.json"))
        record.calibration = calibration if isinstance(calibration, dict) \
            else None
        checks = _json(read("eye/checks.json"))
        record.checks = [c for c in checks if isinstance(c, dict)] \
            if isinstance(checks, list) else []
        snapshot = _json(read("snapshot_start.json"))
        record.snapshot = snapshot if isinstance(snapshot, dict) else None
    return record
