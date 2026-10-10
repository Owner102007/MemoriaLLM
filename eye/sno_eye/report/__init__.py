"""«Разбор записи» — куда смотрел участник (SNO-F-RES-03, шаг 34).

Организатор перетаскивает на `eye\\Разбор записи.cmd` архив записи или
папку с архивами. Рядом с архивом появляется папка `<имя>_eye/`:

* `index.html` — качество взгляда, куда уходило время изучения, ход по
  минутам, походы на полку, схема полки на каждый поход с фиксациями
  поверх и «куда смотрели на странице»;
* `fixations.csv` — фиксации с зонами; `visits.csv` — походы на полку;
* `measures.csv` — меры сессии, строго и мягко;
* `quality.json` — качество взгляда числами.

Для нескольких архивов — ещё и общая таблица `разбор_записей.csv`.

Порядок (SNO-ALG-EYE-05): «Проверка записи» → ход сессии по журналу →
версии взгляда (как записано и с поправкой дрейфа по неявным точкам) →
фиксации I-DT → зоны по кадрам раскладки «уверенно / на границе» →
меры и качество. Исходное не переписывается: каждая версия взгляда —
свой столбец; меры считаются одной версией на всё исследование, она
названа в итоге (`report.version` в `thresholds.json`, `--version`).

**Папки разбора не кладутся в `Записи` приложения**: приложение приняло
бы такую папку за запись и упаковало бы её. Архив оттуда разбирается в
«Документы\\Разбор записей СНО2026».

Только стандартная библиотека: разбор идёт встраиваемым Python спутника
и на любом другом, без сети и без камеры.
"""

from __future__ import annotations

import csv
import json
import os
import statistics
from pathlib import Path

from .. import record_check as rc
from . import archive as arc
from . import html as page
from . import idt, measures, timeline as tl, versions, zones as zn
from .screen import screen_of

# Пороги по умолчанию; настоящие — `report` в `thresholds.json`.
DEFAULTS = {
    "version": "drift",
    "idt_min_deg": 1.5,
    "idt_precision_k": 3.0,
    "min_fix_ms": 100,
    "bridge_ms": 100,
    "merge_gap_ms": 75,
    "pair_from_ms": 300,
    "pair_to_ms": 100,
    "pair_min_samples": 3,
    "pair_max_deg": 5.0,
    "drift_window_s": 300,
    "drift_step_s": 60,
    "drift_k": 5,
    "outside_deg": 2.0,
    "sample_cap_ms": 100,
}

VERSIONS = {"raw": "как записано (raw)",
            "drift": "с поправкой дрейфа (raw+drift)"}

TABLE_NAME = "разбор_записей.csv"
SAFE_FOLDER = "Разбор записей СНО2026"


def settings(path: Path | None = None) -> dict:
    """Пороги разбора: `report` из `thresholds.json` поверх значений по
    умолчанию."""
    values = dict(DEFAULTS)
    if path is None:
        path = Path(__file__).resolve().parent.parent.parent / \
            "thresholds.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        own = raw.get("report") or {}
        for key, default in DEFAULTS.items():
            value = own.get(key)
            if isinstance(default, str):
                if isinstance(value, str) and value in VERSIONS:
                    values[key] = value
            elif isinstance(value, (int, float)) and \
                    not isinstance(value, bool):
                values[key] = value
    except (OSError, ValueError, AttributeError):
        pass
    return values


def _median(values):
    return statistics.median(values) if values else None


def analyse(record: arc.Record, cfg: dict, limits: dict) -> dict:
    """Разбор одной записи: меры, качество, фиксации с зонами."""
    check = record.check
    line = tl.build(record)
    screen = screen_of(record.calibration, record.frames)
    gaze = record.eye.get("present") is True and bool(record.gaze)
    notes: list[str] = []
    result: dict = {
        "archive": record.name, "path": str(record.path),
        "participant": check.get("participant"),
        "branch": check.get("branch"), "platform": check.get("platform"),
        "app_version": check.get("version"),
        "study_tag": check.get("study_tag"),
        "study_start": line.study_start, "study_ms": line.study_ms,
        "layout_known": record.has_layout and bool(record.frames),
        "gaze_used": gaze, "version": cfg["version"],
        "version_words": VERSIONS[cfg["version"]],
        "titles": line.titles, "fixations": [], "notes": notes,
        "check_verdict": check.get("verdict_text"),
    }
    if not result["layout_known"]:
        notes.append("кадров раскладки нет — запись прежней сборки: зоны "
                     "не считаются, только «на экране / вне экрана»")
    if not record.has_input:
        notes.append("потока ввода нет — неявных точек нет")
    if line.window_changed is not None:
        notes.append("окно приложения меняли во время записи — после "
                     "этого зоны не считаются")
    if not gaze:
        reason = rc.REASONS.get(str(record.eye.get("reason")),
                                str(record.eye.get("reason") or ""))
        if record.eye.get("present") is True:
            reason = "в манифесте взгляд есть, а строк взгляда нет"
        elif check.get("platform") != "ПК":
            reason = "запись с телефона — взгляд не пишется"
        result["gaze_reason"] = reason or "причина не названа"
        rows = [measures.visit_measures(v, [], [], False)
                for v in line.visits]
        result["visits"] = rows
        result["visit_summary"] = measures.visit_summary(rows, False)
        result["shares"] = measures.shares([], line.study_ms)
        result["minutes"] = []
        result["quality"] = {}
        result["included"] = False
        return result

    raw = versions.raw_samples(record, line.latency_ms)
    pairs, dropped = versions.implicit_pairs(record, raw, screen, line, cfg)
    end = versions.end_correction(line, screen)
    drift = versions.build_drift(pairs, line, end, cfg)
    fixed = versions.apply(raw, drift)
    residual = versions.residuals(pairs, line, end, screen, cfg)
    samples = fixed if cfg["version"] == "drift" else raw

    precision = line.precision_deg
    idt_deg = max(float(cfg["idt_min_deg"]),
                  float(cfg["idt_precision_k"]) * (precision or 0.0))
    idt_px = screen.px_for_deg(idt_deg)
    spans = idt.moving_spans(record.frames)
    fixes = idt.fixations(samples, idt_px, spans, cfg)
    outside_px = screen.px_for_deg(float(cfg["outside_deg"]))
    zones = zn.Zones(record.frames, outside_px)
    found = []
    for fix in fixes:
        margin = screen.px_for_deg(measures.margin_deg(fix.start, line))
        if result["layout_known"]:
            z = zones.classify(fix.start, fix.x, fix.y, margin)
        else:
            off = fix.x < -outside_px or fix.y < -outside_px or \
                fix.x > screen.w + outside_px or fix.y > screen.h + outside_px
            z = {"zone": "outside" if off else "unknown",
                 "bucket": "outside" if off else "unknown", "sure": True,
                 "key": "outside" if off else "unknown", "near": []}
        found.append(z)
    labels = measures.label_samples(
        samples, fixes, found, line, screen, outside_px,
        float(cfg["sample_cap_ms"]), result["layout_known"])
    result["shares"] = measures.shares(labels, line.study_ms)
    result["minutes"] = measures.per_minute(labels, line)
    rows = [measures.visit_measures(v, fixes, found, True)
            for v in line.visits]
    result["visits"] = rows
    result["visit_summary"] = measures.visit_summary(rows, True)

    for k, (fix, z) in enumerate(zip(fixes, found)):
        rx = _median([raw[i].x for i in fix.members])
        ry = _median([raw[i].y for i in fix.members])
        result["fixations"].append({
            "n": k + 1, "start": fix.start, "end": fix.end,
            "duration": fix.duration, "x": fix.x, "y": fix.y,
            "x_raw": rx, "y_raw": ry, "moving": fix.moving, **z})

    known = [v for v in (line.start_deg, line.end_deg) if v is not None]
    mean = sum(known) / len(known) if known else None
    include = float(limits["include_deg"])
    included = mean is not None and mean <= include
    if mean is None:
        notes.append("точность взгляда неизвестна — меры взгляда в "
                     "анализ не идут")
    elif not included:
        notes.append(f"средняя точность {page.deg(mean)} хуже "
                     f"{page.deg(include)} — меры взгляда помечены "
                     "«не входит в анализ»")
    if line.end_deg is None:
        notes.append("проверки в конце нет — запас зон по точности "
                     "начала")
    if not line.latency_known:
        notes.append("задержка камеры не найдена — взгляд не сдвинут")
    if not screen.known:
        notes.append("экрана места записи в архиве нет — градусы "
                     "посчитаны по типичному монитору")
    if not pairs:
        notes.append("неявных точек нет — поправка дрейфа только по "
                     "проверке в конце" if end is not None else
                     "неявных точек нет и проверки в конце нет — "
                     "поправки дрейфа нет")
    result["included"] = included
    durations = [f.duration for f in fixes if not f.moving]
    result["quality"] = {
        "start_deg": line.start_deg, "end_deg": line.end_deg,
        "mean_deg": mean, "include_deg": include, "included": included,
        "precision_deg": precision, "latency_ms": line.latency_ms,
        "latency_known": line.latency_known,
        "valid_share": measures.valid_share(raw, line),
        "fps_by_screen": measures.fps_by_screen(raw, line),
        "implicit": residual, "dropped": dropped,
        "drift_max_deg": screen.deg_for_px(drift.largest_px),
        "drift": [{"minute": round((c - line.study_start) / 60000, 2),
                   "dx_px": round(s[0], 1), "dy_px": round(s[1], 1),
                   "pairs": n}
                  for c, s, n in zip(drift.centers, drift.shifts,
                                     drift.counts)],
        "end_anchor": end is not None,
        "idt_deg": idt_deg, "idt_px": idt_px,
        "fixations": len(fixes),
        "fixation_median_ms": _median(durations),
        "screen_known": screen.known,
        "screen": {"w": screen.w, "h": screen.h, "w_mm": screen.w_mm,
                   "h_mm": screen.h_mm, "distance_mm": screen.distance_mm},
        "version": cfg["version"],
    }
    result["_frames"] = record.frames
    result["_zones"] = zones
    return result


# --- выход ------------------------------------------------------------

def _cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "да" if value else "нет"
    if isinstance(value, float):
        return f"{value:.3f}".rstrip("0").rstrip(".").replace(".", ",") \
            or "0"
    if isinstance(value, (list, tuple)):
        return " | ".join(str(v) for v in value)
    return str(value)


def _write(path: Path, header: list[str], rows: list[list]) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, delimiter=";")
        writer.writerow(header)
        for row in rows:
            writer.writerow([_cell(v) for v in row])


FIX_COLUMNS = (
    ("n", "n"), ("начало, мс", "start"), ("конец, мс", "end"),
    ("длительность, мс", "duration"), ("x", "x"), ("y", "y"),
    ("x как записано", "x_raw"), ("y как записано", "y_raw"),
    ("движение раскладки", "moving"), ("зона", "zone"),
    ("имя зоны", "id"), ("вид времени", "bucket"), ("уверенно", "sure"),
    ("рядом", "near"), ("категория", "category"),
    ("категория уверенно", "category_sure"), ("книга полки", "book"),
    ("книга уверенно", "book_sure"), ("звезда", "mark"),
    ("страница", "page"), ("x_pt", "x_pt"), ("y_pt", "y_pt"),
    ("вне полосы", "dimmed"), ("книга на экране", "reading"),
    ("экран", "screen"), ("кадр раскладки", "frame"),
)

VISIT_COLUMNS = (
    ("№", "n"), ("экран", "screen"), ("начало, мс", "start_ms"),
    ("длилось, мс", "duration_ms"), ("чем кончился", "outcome"),
    ("книга", "book"), ("как открыта", "via"),
    ("нужная категория", "target"), ("запросов по названию", "searches"),
    ("первый запрос через, мс", "search_after_ms"),
    ("фиксаций", "fixations"),
    ("категорий строго", "categories_strict"),
    ("категорий мягко", "categories_soft"),
    ("книг строго", "books_strict"), ("книг мягко", "books_soft"),
    ("до нужной категории строго, мс", "first_target_ms_strict"),
    ("до нужной категории мягко, мс", "first_target_ms_soft"),
    ("прямая находка строго", "direct_strict"),
    ("прямая находка мягко", "direct_soft"),
    ("путь строго", "path_strict"), ("путь мягко", "path_soft"),
    ("звёзд строго", "stars_strict"), ("звёзд мягко", "stars_soft"),
)

SUMMARY_WORDS = (
    ("visits", "походов на полку"), ("opened", "из них открыта книга"),
    ("median_s", "медиана похода, с"),
    ("with_search", "походов с поиском по названию"),
    ("direct_share", "доля прямых находок"),
    ("first_target_s", "медиана времени до нужной категории, с"),
    ("categories", "категорий осмотрено в среднем"),
    ("books", "книг осмотрено в среднем"),
)


def _summary_rows(result: dict) -> list[list]:
    s = result.get("visit_summary") or {}
    rows = []
    for key, words in SUMMARY_WORDS:
        if key in s:
            rows.append([words, s[key], s[key]])
        elif f"{key}_strict" in s:
            rows.append([words, s[f"{key}_strict"], s[f"{key}_soft"]])
    return rows


def write_outputs(result: dict, folder: Path) -> None:
    """Кладёт файлы разбора в [folder]."""
    folder.mkdir(parents=True, exist_ok=True)
    fixations = result["fixations"]
    _write(folder / "fixations.csv", [t for t, _ in FIX_COLUMNS],
           [[f.get(k) for _, k in FIX_COLUMNS] for f in fixations])
    _write(folder / "visits.csv", [t for t, _ in VISIT_COLUMNS],
           [[v.get(k) for _, k in VISIT_COLUMNS]
            for v in result.get("visits") or []])
    rows = [["изучение, с", result["study_ms"] / 1000,
             result["study_ms"] / 1000],
            ["версия взгляда", result["version"], result["version"]],
            ["входит в анализ взгляда", result.get("included"),
             result.get("included")]]
    strict = result["shares"]["strict"]
    soft = result["shares"]["soft"]
    for key, name in zn.BUCKETS:
        rows.append([f"доля: {name}", strict.get(key), soft.get(key)])
    rows += _summary_rows(result)
    for minute in result.get("minutes") or []:
        for key, name, _ in measures.MINUTE_GROUPS:
            rows.append([f"минута {minute['minute']}: {name}",
                         minute.get(key), minute.get(key)])
    _write(folder / "measures.csv", ["мера", "строго", "мягко"], rows)
    quality = dict(result.get("quality") or {})
    quality.update({"archive": result["archive"],
                    "gaze": result["gaze_used"],
                    "gaze_reason": result.get("gaze_reason"),
                    "notes": result["notes"]})
    (folder / "quality.json").write_text(
        json.dumps(quality, ensure_ascii=False, indent=1),
        encoding="utf-8")
    zones = result.get("_zones")
    text = page.render(result, result.get("_frames") or [],
                       zones.frame_at if zones else (lambda t: None))
    (folder / "index.html").write_text(text, encoding="utf-8")


TABLE_COLUMNS = (
    ("архив", lambda r: r["archive"]),
    ("участник", lambda r: r.get("participant")),
    ("ветвь", lambda r: r.get("branch")),
    ("платформа", lambda r: r.get("platform")),
    ("изучение, с", lambda r: r.get("study_ms", 0) / 1000),
    ("взгляд", lambda r: r.get("gaze_used")),
    ("почему без взгляда", lambda r: r.get("gaze_reason")),
    ("версия взгляда", lambda r: r.get("version")),
    ("входит в анализ взгляда", lambda r: r.get("included")),
    ("точность в начале, °", lambda r: _q(r, "start_deg")),
    ("точность в конце, °", lambda r: _q(r, "end_deg")),
    ("неявных точек", lambda r: (_q(r, "implicit") or {}).get("pairs")),
    ("остаток как записано, °",
     lambda r: (_q(r, "implicit") or {}).get("raw_deg")),
    ("остаток с поправкой, °",
     lambda r: (_q(r, "implicit") or {}).get("drift_deg")),
    ("кадров в секунду на полке",
     lambda r: (_q(r, "fps_by_screen") or {}).get("shelf")),
    ("кадров в секунду на странице",
     lambda r: (_q(r, "fps_by_screen") or {}).get("reader")),
    ("страница строго", lambda r: _share(r, "strict", "page")),
    ("страница мягко", lambda r: _share(r, "soft", "page")),
    ("полка строго", lambda r: _share(r, "strict", "shelf")),
    ("полка мягко", lambda r: _share(r, "soft", "shelf")),
    ("вне экрана", lambda r: _share(r, "soft", "outside")),
    ("лица нет", lambda r: _share(r, "soft", "no_face")),
    ("походов на полку", lambda r: _v(r, "visits")),
    ("открыто книг", lambda r: _v(r, "opened")),
    ("медиана похода, с", lambda r: _v(r, "median_s")),
    ("походов с поиском", lambda r: _v(r, "with_search")),
    ("прямых находок строго", lambda r: _vg(r, "direct_share_strict")),
    ("прямых находок мягко", lambda r: _vg(r, "direct_share_soft")),
    ("до нужной категории строго, с",
     lambda r: _vg(r, "first_target_s_strict")),
    ("до нужной категории мягко, с",
     lambda r: _vg(r, "first_target_s_soft")),
    ("категорий строго", lambda r: _vg(r, "categories_strict")),
    ("категорий мягко", lambda r: _vg(r, "categories_soft")),
    ("оговорки", lambda r: " | ".join(r.get("notes") or [])),
)


def _q(r: dict, key: str):
    return (r.get("quality") or {}).get(key)


def _v(r: dict, key: str):
    return (r.get("visit_summary") or {}).get(key)


def _gaze_ok(r: dict) -> bool:
    return bool(r.get("gaze_used") and r.get("included"))


def _vg(r: dict, key: str):
    # Меры взгляда сессии хуже порога в общую таблицу не идут.
    return _v(r, key) if _gaze_ok(r) else None


def _share(r: dict, mode: str, key: str):
    if not _gaze_ok(r):
        return None
    return ((r.get("shares") or {}).get(mode) or {}).get(key)


def write_table(results: list[dict], path: Path) -> None:
    """Общая таблица сессий: строка на архив."""
    rows = []
    for r in results:
        if r.get("refused"):
            rows.append([r["archive"]] + [None] * (len(TABLE_COLUMNS) - 2)
                        + [f"не разобрана: {r['refused']}"])
            continue
        rows.append([fn(r) for _, fn in TABLE_COLUMNS])
    _write(path, [t for t, _ in TABLE_COLUMNS], rows)


def _documents() -> Path:
    home = Path(os.environ.get("USERPROFILE") or Path.home())
    docs = home / "Documents"
    return (docs if docs.is_dir() else home) / SAFE_FOLDER


def out_folder(archive: Path, out: str | None) -> Path:
    """Куда класть разбор архива: рядом с ним, а из `Записи` приложения
    — в «Документы» (папку в `Записи` приложение приняло бы за
    запись)."""
    stem = archive.name[:-4] if archive.name.lower().endswith(".zip") \
        else archive.name
    if out:
        return Path(out) / f"{stem}_eye"
    parent = archive.resolve().parent
    if parent.name == "Записи":
        return _documents() / f"{stem}_eye"
    return parent / f"{stem}_eye"


def describe(result: dict) -> list[str]:
    """Итог разбора строками для консоли."""
    if result.get("refused"):
        return [f"{result['archive']} — не разобрана: {result['refused']}"]
    lines = [f"{result['archive']} — разобрана"]
    lines.append(f"  участник {result.get('participant') or '—'} · ветвь "
                 f"{result.get('branch') or '—'} · {result.get('platform')}"
                 f" · изучение {page.sec(result['study_ms'])}")
    if result.get("gaze_used"):
        q = result["quality"]
        word = "входит в анализ" if result["included"] else \
            "НЕ входит в анализ взгляда"
        lines.append(f"  взгляд: {result['version_words']}, {word}; "
                     f"точность {page.deg(q.get('start_deg'))} / "
                     f"{page.deg(q.get('end_deg'))}, годных "
                     f"{page.pct(q.get('valid_share'))}")
        fps = q.get("fps_by_screen") or {}
        if fps:
            lines.append("  кадров в секунду: " + ", ".join(
                f"{page.SCREEN_WORDS.get(k, k)} {v}".replace(".", ",")
                for k, v in sorted(fps.items())))
        implicit = q.get("implicit") or {}
        lines.append(f"  неявных точек {implicit.get('pairs', 0)}: остаток "
                     f"{page.deg(implicit.get('raw_deg'))} → "
                     f"{page.deg(implicit.get('drift_deg'))}; дрейф до "
                     f"{page.deg(q.get('drift_max_deg'))}")
        soft = result["shares"]["soft"]
        strict = result["shares"]["strict"]
        lines.append(f"  фиксаций {q.get('fixations', 0)}; страница "
                     f"{page.pct(soft.get('page'))} (строго "
                     f"{page.pct(strict.get('page'))}), полка "
                     f"{page.pct(soft.get('shelf'))} (строго "
                     f"{page.pct(strict.get('shelf'))}), вне экрана "
                     f"{page.pct(soft.get('outside'))}")
    else:
        lines.append(f"  взгляда нет: {result.get('gaze_reason')}")
    s = result.get("visit_summary") or {}
    line = (f"  походов на полку {s.get('visits', 0)}, открыто книг "
            f"{s.get('opened', 0)}")
    if s.get("median_s") is not None:
        line += f", медиана {s['median_s']:.1f} с".replace(".", ",")
    if result.get("gaze_used") and s.get("direct_share_soft") is not None:
        line += (f", прямых находок {page.pct(s['direct_share_soft'])} "
                 f"(строго {page.pct(s.get('direct_share_strict'))})")
    lines.append(line)
    for note in result.get("notes") or []:
        lines.append(f"   - {note}")
    if result.get("folder"):
        lines.append(f"  папка: {result['folder']}")
    return lines


def _public(result: dict) -> dict:
    """Итог для `--json`: без фиксаций и служебного."""
    out = {k: v for k, v in result.items()
           if not k.startswith("_") and k != "fixations"}
    out["fixation_count"] = len(result.get("fixations") or [])
    return out


def run(path: Path, cfg: dict, limits: dict, out: str | None,
        write: bool = True) -> dict:
    """Разбор одного архива; не роняет пачку."""
    try:
        record = arc.load(path, limits)
        result = analyse(record, cfg, limits)
    except arc.Refused as e:
        return {"archive": path.name, "path": str(path), "refused": e.text}
    except Exception as e:  # noqa: BLE001
        return {"archive": path.name, "path": str(path),
                "refused": f"разбор упал: {e!r}"}
    if write:
        folder = out_folder(path, out)
        try:
            write_outputs(result, folder)
            result["folder"] = str(folder)
        except OSError as e:
            result["notes"].append(f"файлы разбора не записались: {e}")
    return result


def main(paths: list[str], *, as_json: bool = False, out: str | None = None,
         version: str | None = None, write: bool = True) -> int:
    """Вход `python -I -m sno_eye report`. Код выхода: 0 — все
    разобраны, 2 — есть неразобранные, 3 — разбирать нечего."""
    if not paths:
        paths = rc.default_folders()
        if paths and not as_json:
            print("Архивы не названы — разбираю записи на этом ПК:")
            for folder in paths:
                print(f"  {folder}")
    archives = rc.collect(paths)
    if not archives:
        print("Архивов записи не нашлось. Перетащите на «Разбор записи» "
              "архив sno2026_….zip или папку с архивами.")
        return 3
    cfg = settings()
    if version in VERSIONS:
        cfg["version"] = version
    limits = rc.thresholds()
    results = [run(path, cfg, limits, out, write) for path in archives]
    if as_json:
        print(json.dumps([_public(r) for r in results], ensure_ascii=False,
                         indent=1, default=str))
    else:
        for result in results:
            print()
            for line in describe(result):
                print(line)
    if write and len(results) > 1:
        first = archives[0]
        folder = Path(out) if out else (
            _documents() if first.resolve().parent.name == "Записи"
            else first.resolve().parent)
        target = folder / TABLE_NAME
        try:
            folder.mkdir(parents=True, exist_ok=True)
            write_table(results, target)
            if not as_json:
                print(f"\nОбщая таблица: {target}")
        except OSError as e:
            if not as_json:
                print(f"\nОбщую таблицу записать не удалось: {e}")
    return 2 if any(r.get("refused") for r in results) else 0
