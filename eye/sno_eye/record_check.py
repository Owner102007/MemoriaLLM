"""«Проверка записи» — годна ли запись сессии (SNO-F-RES-01, шаг 33).

Организатор перетаскивает на `eye\\Проверка записи.cmd` архив записи
или папку с архивами — с ПК и с телефонов — и по каждой записи видит,
годна ли она для разбора:

* целы ли файлы — суммы SHA-256, размеры и число строк по манифесту,
  контрольные суммы самого ZIP;
* без пропусков ли потоки — журнал `events.jsonl` (сквозной `seq`),
  ввод `input.jsonl`, кадры раскладки `layout.jsonl` и взгляд
  `eye/gaze.jsonl` (сквозной `n`);
* сколько шло изучение, как остановлена запись, отлучки участника;
* пройден ли тест нагрузки и что сказала самопроверка ответов;
* взгляд — записан ли, почему нет, доля годных кадров, точность в
  начале и в конце, кадров в секунду, вес папки `eye/`;
* на какой сборке записано — сборке исследования или проверочной.

Итог — «годна», «с оговорками» или «не годна» с причинами словами, и
сводная таблица `проверка_записей.csv` рядом с проверенным.

Модуль без зависимостей — только стандартная библиотека: проверка
идёт тем же встраиваемым Python, что спутник, и не открывает ни
камеры, ни сети. Правила сверки потоков — вторая реализация
самопроверки приложения (`lib/sno/recording/journal_check.dart`):
приложение проверяет себя при остановке, здесь — то, что доехало до
организатора.
"""

from __future__ import annotations

import csv
import glob
import hashlib
import json
import os
import zipfile
import zlib
from pathlib import Path

# Схема манифеста, которую проверка понимает.
SCHEMA = "sno2026-recording/1"

# Итоги.
GOOD = "ok"
WARN = "warn"
BAD = "bad"

VERDICT_TEXT = {GOOD: "годна", WARN: "с оговорками", BAD: "не годна"}

# Имя сводной таблицы.
CSV_NAME = "проверка_записей.csv"

# Пороги по умолчанию; настоящие — `record_check` в `thresholds.json`.
DEFAULTS = {
    # Т19: взгляд сессии входит в анализ, если средняя точность проверок
    # в начале и в конце не хуже этого.
    "include_deg": 3.0,
    # Доля годных кадров, ниже которой взгляд под оговоркой.
    "min_valid_share": 0.5,
    # Кадров в секунду, ниже которых — оговорка (тот же порог, что
    # «с оговоркой» у самопроверки места).
    "min_fps": 25.0,
}

# Почему взгляда нет — словами (`eye_tracker.reason`, шаг 32).
REASONS = {
    "not_configured": "место записи на этом ПК не настроено",
    "unavailable": "спутник взгляда не поднялся",
    "selfcheck_failed": "самопроверка места не прошла",
    "open_failed": "камера не открылась",
    "skipped": "организатор выбрал «Без взгляда»",
    "stopped": "запись остановили во время калибровки",
    "gave_up": "спутник падал, и приложение сдалось",
    "limit": "калибровка не кончилась за 15 минут",
}

STOPPED = {
    "auto": "сама через 40 минут",
    "experimenter": "организатором",
    "crash": "оборвалась — сбой или закрытие приложения",
}

# Потоки строк: файл, поле сквозного номера, как назвать.
STREAMS = (
    ("events.jsonl", "seq", "журнал"),
    ("input.jsonl", "n", "ввод"),
    ("layout.jsonl", "n", "кадры раскладки"),
    ("eye/gaze.jsonl", "n", "взгляд"),
)


def thresholds(path: Path | None = None) -> dict:
    """Пороги проверки: `record_check` из `thresholds.json` рядом с
    пакетом поверх значений по умолчанию."""
    values = dict(DEFAULTS)
    if path is None:
        path = Path(__file__).resolve().parent.parent / "thresholds.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        own = raw.get("record_check") or {}
        for key in DEFAULTS:
            if isinstance(own.get(key), (int, float)):
                values[key] = float(own[key])
    except (OSError, ValueError, AttributeError):
        pass
    return values


def check_stream(data: bytes, key: str, expected: int | None = None) -> dict:
    """Сверяет поток строк JSON с самим собой — вторая реализация
    `checkJournal` приложения.

    Целая строка — за ней перевод строки; пустые не считаются. Строка,
    которая не разбирается или без номера [key], — мусор: её номер
    окажется среди пропущенных. Пропуски — от единицы до большего из
    наибольшего номера в файле и [expected]. Порядок строк значения не
    имеет."""
    end = data.rfind(b"\n")
    torn = bool(data) and end != len(data) - 1
    seen: set[int] = set()
    lines = 0
    highest = 0
    junk = 0
    if end >= 0:
        text = data[:end].decode("utf-8", errors="replace")
        for line in text.split("\n"):
            if not line.strip():
                continue
            lines += 1
            number = None
            try:
                raw = json.loads(line)
                if isinstance(raw, dict):
                    value = raw.get(key)
                    if isinstance(value, int) and not isinstance(value, bool):
                        number = value
            except ValueError:
                pass
            if number is None or number <= 0:
                junk += 1
                continue
            seen.add(number)
            highest = max(highest, number)
    wanted = expected if expected is not None and expected > highest \
        else highest
    return {"lines": lines, "gaps": wanted - len(seen), "torn": torn,
            "junk": junk, "highest": highest}


def _int(value) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) \
        else None


def _num(value) -> float | None:
    if isinstance(value, bool):
        return None
    return float(value) if isinstance(value, (int, float)) else None


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def _jsonl(data: bytes):
    for line in data.decode("utf-8", errors="replace").split("\n"):
        if not line.strip():
            continue
        try:
            raw = json.loads(line)
        except ValueError:
            continue
        if isinstance(raw, dict):
            yield raw


def duration_words(seconds: float | None) -> str:
    """«12 мин 05 с», «45 с», «—»."""
    if seconds is None:
        return "—"
    total = int(round(seconds))
    minutes, rest = divmod(total, 60)
    if minutes == 0:
        return f"{rest} с"
    return f"{minutes} мин {rest:02d} с"


def _deg(value: float | None) -> str:
    return "—" if value is None else f"{value:.1f}°".replace(".", ",")


def _share(value: float | None) -> str:
    return "—" if value is None else f"{round(value * 100)} %"


def _gaze_rate(data: bytes) -> tuple[float | None, int]:
    """Кадров в секунду по потоку взгляда: строки делятся на время,
    которое покрывает каждый сегмент (между сегментами — подъём
    спутника заново, это время не кадры). И число сегментов."""
    spans: dict[int, list[int]] = {}
    counts: dict[int, int] = {}
    for row in _jsonl(data):
        t = _int(row.get("t"))
        if t is None:
            continue
        seg = _int(row.get("seg")) or 0
        span = spans.setdefault(seg, [t, t])
        span[0] = min(span[0], t)
        span[1] = max(span[1], t)
        counts[seg] = counts.get(seg, 0) + 1
    time_ms = sum(b - a for a, b in spans.values())
    frames = sum(counts[seg] - 1 for seg in counts if counts[seg] > 1)
    if time_ms <= 0 or frames <= 0:
        return None, len(spans)
    return frames * 1000.0 / time_ms, len(spans)


def _valid_share(data: bytes) -> float | None:
    total = 0
    ok = 0
    for row in _jsonl(data):
        total += 1
        if row.get("ok") is True:
            ok += 1
    return ok / total if total else None


def check_archive(path: Path, limits: dict | None = None) -> dict:
    """Проверяет один архив записи и отвечает итогом."""
    limits = limits or thresholds()
    path = Path(path)
    report: dict = {
        "archive": path.name, "path": str(path), "bytes": None,
        "verdict": GOOD, "problems": [], "notes": [], "info": [],
    }
    problems: list[str] = report["problems"]
    notes: list[str] = report["notes"]
    info: list[str] = report["info"]

    def finish() -> dict:
        report["verdict"] = BAD if problems else WARN if notes else GOOD
        report["verdict_text"] = VERDICT_TEXT[report["verdict"]]
        return report

    try:
        report["bytes"] = path.stat().st_size
        archive = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as e:
        problems.append(f"архив не открывается: {e}")
        return finish()

    with archive:
        names = set(archive.namelist())
        try:
            broken = archive.testzip()
        except (OSError, zipfile.BadZipFile, EOFError, zlib.error) as e:
            broken = f"(не распаковывается: {e})"
        if broken is not None:
            problems.append(f"в архиве испорчен файл {broken}")

        def read(name: str) -> bytes | None:
            if name not in names:
                return None
            try:
                return archive.read(name)
            except (OSError, zipfile.BadZipFile, EOFError, zlib.error):
                message = f"файл {name} не читается"
                if message not in problems:
                    problems.append(message)
                return None

        raw = read("manifest.json")
        manifest = None
        if raw is None:
            problems.append("в архиве нет manifest.json")
        else:
            try:
                manifest = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                problems.append("manifest.json не читается")
        if not isinstance(manifest, dict):
            return finish()
        if manifest.get("schema") != SCHEMA:
            problems.append(
                f"схема манифеста {manifest.get('schema')!r}, а не {SCHEMA}")
            return finish()
        _identity(report, manifest)

        # Файлы по манифесту: на месте ли, те ли байты.
        files = _dict(manifest.get("files"))
        intact = 0
        for name, entry in sorted(files.items()):
            entry = _dict(entry)
            data = read(name)
            if data is None:
                if name in names:
                    continue
                problems.append(f"в архиве нет файла {name}")
                continue
            wrong = []
            if hashlib.sha256(data).hexdigest() != entry.get("sha256"):
                wrong.append("сумма")
            if _int(entry.get("bytes")) not in (None, len(data)):
                wrong.append("размер")
            lines = _int(entry.get("lines"))
            if lines is not None and lines != data.count(b"\n"):
                wrong.append("число строк")
            if wrong:
                problems.append(f"файл {name} не тот: {', '.join(wrong)}")
            else:
                intact += 1
            dropped = _int(entry.get("dropped_lines")) or 0
            if dropped:
                notes.append(f"{name}: последняя строка была оборвана и не "
                             "легла в архив")
        extra = sorted(n for n in names - set(files) - {"manifest.json"}
                       if not n.endswith("/"))
        if extra:
            notes.append("в архиве есть файлы, которых нет в манифесте: "
                         + ", ".join(extra[:5]))
        report["files"] = {"listed": len(files), "intact": intact}
        if manifest.get("info_missing") is True:
            notes.append("сведения о записи не прочитались при упаковке")

        recording = _dict(manifest.get("recording"))
        events = read("events.jsonl")
        if events is None and "events.jsonl" not in names:
            problems.append("в архиве нет журнала events.jsonl")
        _streams(report, manifest, read, names)
        _study(report, manifest, recording, events)
        _test(report, manifest, read, events)
        _eye(report, manifest, read, names, limits)
        _build(report, manifest)
    return finish()


def _identity(report: dict, manifest: dict) -> None:
    participant = _dict(manifest.get("participant"))
    device = _dict(manifest.get("device"))
    app = _dict(manifest.get("app"))
    os_name = str(device.get("os") or "").lower()
    eye = _dict(manifest.get("eye_tracker"))
    pc = os_name == "windows" or any(
        key in eye for key in ("configured", "satellite", "reason"))
    report.update({
        "branch": manifest.get("branch"),
        "participant": participant.get("code"),
        "device": device.get("code"),
        "platform": "ПК" if pc else "телефон" if os_name else "—",
        "model": " ".join(str(device.get(k)) for k in ("manufacturer", "model")
                          if device.get(k)) or None,
        "version": app.get("version"),
        "commit": str(app.get("commit") or "")[:7] or None,
        "study_tag": app.get("study_tag"),
        "built": app.get("built"),
        "pc": pc,
    })


def _streams(report: dict, manifest: dict, read, names) -> None:
    recording = _dict(manifest.get("recording"))
    expected = {
        "events.jsonl": _int(recording.get("events")),
        "input.jsonl": _int(_dict(manifest.get("input")).get("lines")),
        "layout.jsonl": _int(_dict(manifest.get("layout")).get("lines")),
        "eye/gaze.jsonl": None,
    }
    blocks = {
        "events.jsonl": recording,
        "input.jsonl": _dict(manifest.get("input")),
        "layout.jsonl": _dict(manifest.get("layout")),
        "eye/gaze.jsonl": _dict(manifest.get("eye_tracker")),
    }
    streams: dict = {}
    for name, key, title in STREAMS:
        if name not in names:
            if name == "input.jsonl" and "input" not in manifest:
                report["info"].append("потока ввода нет — запись прежней "
                                      "сборки")
            if name == "layout.jsonl" and "layout" not in manifest:
                report["info"].append("кадров раскладки нет — запись "
                                      "прежней сборки")
            continue
        data = read(name)
        if data is None:
            continue
        result = check_stream(data, key, expected[name])
        streams[name] = result
        own = _dict(blocks[name].get("check"))
        if result["gaps"] or result["torn"]:
            words = [f"{title} неполон"]
            if result["gaps"]:
                words.append(f"пропущено строк {result['gaps']}")
            if result["torn"]:
                words.append("последняя оборвана")
            report["notes"].append(": ".join([words[0], ", ".join(words[1:])]))
        if result["junk"]:
            report["notes"].append(
                f"{title}: строк, которые не читаются, {result['junk']}")
        if own and (_int(own.get("gaps")) or own.get("torn") is True):
            report["notes"].append(
                f"{title}: самопроверка приложения нашла пропуски")
    report["streams"] = streams


def _study(report: dict, manifest: dict, recording: dict,
           events: bytes | None) -> None:
    planned = _int(recording.get("planned_s"))
    duration_ms = _int(recording.get("duration_ms"))
    study_t = _int(recording.get("study_t"))
    study_ms = None
    for row in _jsonl(events or b""):
        if row.get("type") == "recording.stop":
            study_ms = _int(_dict(row.get("data")).get("study_ms"))
    if study_ms is None and duration_ms is not None:
        study_ms = max(0, duration_ms - (study_t or 0))
    report["planned_s"] = planned
    report["study_s"] = None if study_ms is None else study_ms / 1000
    stopped = recording.get("stopped_by")
    report["stopped_by"] = stopped
    if stopped == "crash":
        report["notes"].append("запись оборвалась: сбой или закрытие "
                               "приложения, сведения дописаны при запуске")
    elif stopped is None:
        report["notes"].append("неизвестно, как остановлена запись")
    if recording.get("in_background") is True:
        report["notes"].append("запись кончилась, когда приложения не было "
                               "на экране")
    if recording.get("write_failed") is True:
        report["notes"].append("запись на диск во время записи отказывала")
    away = _dict(recording.get("away"))
    count = _int(away.get("count")) or 0
    total = _int(away.get("total_ms")) or 0
    hidden = _int(away.get("hidden_ms")) or 0
    report["away_count"] = count
    report["away_s"] = total / 1000
    if hidden > 0:
        report["notes"].append(
            f"участник уходил из приложения: {count} раз, всего "
            f"{duration_words(total / 1000)}")
    elif count:
        report["info"].append(
            f"окно теряло фокус {count} раз, всего "
            f"{duration_words(total / 1000)}")


def _test(report: dict, manifest: dict, read, events: bytes | None) -> None:
    clt = manifest.get("clt")
    if not isinstance(clt, dict):
        report["test"] = None
        report["info"].append("теста нагрузки в сборке нет")
        return
    final = clt.get("final")
    report["test"] = final
    without = False
    for row in _jsonl(events or b""):
        if row.get("type") == "session.finish":
            without = _dict(row.get("data")).get("without_test") is True
    if final != "complete":
        why = " — закрыт выходом организатора «Тест пройти нельзя»" \
            if without else ""
        report["notes"].append(f"тест нагрузки не пройден{why}")
    scores = read("clt/scores.json")
    verdict = None
    if scores is not None:
        try:
            checks = _dict(_dict(json.loads(scores.decode("utf-8"))
                                 ).get("checks"))
            verdict = checks.get("verdict")
        except (UnicodeDecodeError, ValueError):
            report["notes"].append("clt/scores.json не читается")
    report["test_verdict"] = verdict
    report["test_flags"] = _int(clt.get("checks_flags"))
    if verdict == "review":
        report["notes"].append("самопроверка ответов теста: один флаг — "
                               "посмотреть ответы")
    elif verdict == "doubt":
        report["notes"].append("самопроверка ответов теста: два флага и "
                               "больше — ответам верить с осторожностью")


def _eye(report: dict, manifest: dict, read, names, limits: dict) -> None:
    eye = _dict(manifest.get("eye_tracker"))
    present = eye.get("present") is True
    eye_bytes = 0
    for name, entry in _dict(manifest.get("files")).items():
        if name.startswith("eye/"):
            eye_bytes += _int(_dict(entry).get("bytes")) or 0
    report.update({"gaze": present, "eye_mb": eye_bytes / 1e6,
                   "quality": eye.get("quality"), "reason": eye.get("reason"),
                   "valid_share": None, "start_deg": None, "end_deg": None,
                   "fps": None, "segments": None})
    if not present:
        if report.get("pc"):
            reason = REASONS.get(str(eye.get("reason")),
                                 str(eye.get("reason") or "причина не названа"))
            report["notes"].append(f"взгляд не записан: {reason}")
        else:
            report["info"].append("телефон: взгляд не пишется")
        return
    gaze = read("eye/gaze.jsonl") if "eye/gaze.jsonl" in names else None
    if gaze is None:
        report["notes"].append("в манифесте взгляд есть, а потока "
                               "eye/gaze.jsonl в архиве нет")
        return
    share = _valid_share(gaze)
    fps, segments = _gaze_rate(gaze)
    start = _num(_dict(eye.get("calibration")).get("accuracy_deg"))
    end_check = _dict(eye.get("end_check"))
    end = _num(end_check.get("accuracy_deg"))
    report.update({"valid_share": share, "fps": fps, "segments": segments,
                   "start_deg": start, "end_deg": end})
    if eye.get("quality") == "low":
        report["notes"].append("калибровка не принята — организатор выбрал "
                               "«Писать с пометкой»")
    if end_check.get("skipped") is True:
        report["notes"].append("проверку точности в конце пропустили — "
                               "точность известна только по началу")
    elif end is None:
        report["notes"].append("проверки точности в конце нет")
    known = [v for v in (start, end) if v is not None]
    mean = sum(known) / len(known) if known else None
    report["mean_deg"] = mean
    if mean is None:
        report["notes"].append("точность взгляда неизвестна")
    elif mean > limits["include_deg"]:
        report["notes"].append(
            f"точность {_deg(mean)} хуже {_deg(limits['include_deg'])}: "
            "взгляд этой записи в анализ не войдёт")
    if share is not None and share < limits["min_valid_share"]:
        report["notes"].append(
            f"годных кадров взгляда {_share(share)} — меньше "
            f"{_share(limits['min_valid_share'])}")
    if fps is not None and fps < limits["min_fps"]:
        report["notes"].append(
            f"кадров взгляда в секунду {fps:.1f} — меньше "
            f"{limits['min_fps']:.0f}".replace(".", ","))
    if segments > 1:
        report["info"].append(f"спутник поднимали заново: сегментов "
                              f"{segments}")


def _build(report: dict, manifest: dict) -> None:
    tag = report.get("study_tag")
    if not tag:
        report["notes"].append("записана на проверочной сборке, а не на "
                               "сборке исследования")


def describe(report: dict) -> list[str]:
    """Итог по записи строками для консоли."""
    out = [f"{report['archive']} — {report.get('verdict_text', '')}"]
    if "participant" in report:
        code = str(report.get("participant") or "—")
        if len(code) == 8:
            code = f"{code[:4]} {code[4:]}"
        build = report.get("version") or "—"
        if report.get("study_tag"):
            build = f"{build} ({report['study_tag']})"
        out.append(f"  участник {code} · ветвь {report.get('branch') or '—'}"
                   f" · {report.get('platform')} · сборка {build}")
    if "study_s" in report:
        planned = report.get("planned_s")
        of = f" из {duration_words(planned)}" if planned else ""
        stopped = STOPPED.get(str(report.get("stopped_by")), "—")
        out.append(f"  изучение {duration_words(report['study_s'])}{of} · "
                   f"остановлена {stopped}")
    files = report.get("files")
    if files:
        out.append(f"  файлы целы: {files['intact']} из {files['listed']} "
                   "по суммам")
    streams = report.get("streams") or {}
    parts = []
    for name, _, title in STREAMS:
        result = streams.get(name)
        if result is None:
            continue
        mark = "цел" if not result["gaps"] and not result["torn"] \
            else "неполон"
        parts.append(f"{title} {result['lines']} — {mark}")
    if parts:
        out.append("  " + "; ".join(parts))
    if report.get("test") is not None:
        verdict = report.get("test_verdict")
        test = "пройден" if report["test"] == "complete" else "не пройден"
        if verdict:
            test += f", самопроверка ответов: {verdict}"
        out.append(f"  тест нагрузки {test}")
    if report.get("gaze"):
        out.append(
            f"  взгляд: годных {_share(report.get('valid_share'))}, "
            f"точность в начале {_deg(report.get('start_deg'))}, "
            f"в конце {_deg(report.get('end_deg'))}, "
            + ("кадров в секунду —" if report.get("fps") is None else
               f"кадров в секунду {report['fps']:.1f}".replace(".", ","))
            + f", eye/ {report.get('eye_mb', 0):.0f} МБ")
    elif "gaze" in report and report.get("pc"):
        out.append("  взгляда нет")
    if report.get("bytes") is not None:
        out.append(f"  архив {report['bytes'] / 1e6:.1f} МБ".replace(".", ","))
    for title, items in (("не годна, потому что", report["problems"]),
                         ("оговорки", report["notes"]),
                         ("к сведению", report["info"])):
        if items:
            out.append(f"  {title}:")
            out.extend(f"   - {item}" for item in items)
    return out


CSV_COLUMNS = (
    ("архив", "archive"), ("итог", "verdict_text"), ("ветвь", "branch"),
    ("участник", "participant"), ("устройство", "device"),
    ("платформа", "platform"), ("модель", "model"), ("сборка", "version"),
    ("тег исследования", "study_tag"), ("коммит", "commit"),
    ("изучение, с", "study_s"), ("план, с", "planned_s"),
    ("остановлена", "stopped_by"), ("отлучек", "away_count"),
    ("отлучки, с", "away_s"), ("тест нагрузки", "test"),
    ("самопроверка ответов", "test_verdict"), ("взгляд", "gaze"),
    ("качество", "quality"), ("почему без взгляда", "reason"),
    ("доля годных", "valid_share"), ("точность в начале, °", "start_deg"),
    ("точность в конце, °", "end_deg"), ("кадров в секунду", "fps"),
    ("сегментов", "segments"), ("eye, МБ", "eye_mb"),
    ("архив, МБ", "bytes"),
)


def _cell(key: str, value) -> str:
    if value is None:
        return ""
    if key == "bytes":
        value = value / 1e6
    if isinstance(value, bool):
        return "да" if value else "нет"
    if isinstance(value, float):
        return f"{value:.2f}".replace(".", ",")
    return str(value)


def write_csv(reports: list[dict], path: Path) -> None:
    """Сводная таблица: строка на архив, разделитель «;», UTF-8 с меткой
    порядка байт — так её открывает Excel с русскими настройками."""
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, delimiter=";")
        writer.writerow([title for title, _ in CSV_COLUMNS]
                        + ["причины"])
        for report in reports:
            reasons = report["problems"] + report["notes"]
            writer.writerow([_cell(key, report.get(key))
                             for _, key in CSV_COLUMNS]
                            + [" | ".join(reasons)])


def collect(paths: list[str]) -> list[Path]:
    """Архивы записей среди [paths]: файлы `.zip` как есть, папки — их
    `sno2026_*.zip` без вложенных папок. Порядок — по имени."""
    found: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            found.extend(sorted(path.glob("sno2026_*.zip")))
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


def default_folders() -> list[str]:
    """Папки `Записи` сборок ветвей на этом ПК — когда архивов не
    назвали: `%APPDATA%\\<издатель>\\<программа>\\sno2026-*\\Записи`."""
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return []
    return sorted(glob.glob(os.path.join(appdata, "*", "*", "sno2026-*",
                                         "Записи")))


def main(paths: list[str], *, as_json: bool = False,
         csv_path: str | None = None, write_table: bool = True) -> int:
    """Вход `python -I -m sno_eye check`. Код выхода: 0 — все годны,
    1 — есть с оговорками, 2 — есть негодные, 3 — проверять нечего."""
    if not paths:
        paths = default_folders()
        if paths:
            print("Архивы не названы — проверяю записи на этом ПК:")
            for folder in paths:
                print(f"  {folder}")
    archives = collect(paths)
    if not archives:
        print("Архивов записи не нашлось. Перетащите на «Проверка записи» "
              "архив sno2026_….zip или папку с архивами.")
        return 3
    limits = thresholds()
    reports = [check_archive(path, limits) for path in archives]
    if as_json:
        print(json.dumps(reports, ensure_ascii=False, indent=1))
    else:
        for report in reports:
            print()
            for line in describe(report):
                print(line)
        counts = {v: sum(r["verdict"] == v for r in reports)
                  for v in (GOOD, WARN, BAD)}
        print()
        print(f"Проверено архивов: {len(reports)} — годны {counts[GOOD]}, "
              f"с оговорками {counts[WARN]}, не годны {counts[BAD]}")
    if write_table:
        target = Path(csv_path) if csv_path else _table_place(paths, archives)
        try:
            write_csv(reports, target)
            if not as_json:
                print(f"Таблица: {target}")
        except OSError as e:
            if not as_json:
                print(f"Таблицу записать не удалось: {e}")
    if any(r["verdict"] == BAD for r in reports):
        return 2
    return 1 if any(r["verdict"] == WARN for r in reports) else 0


def _table_place(paths: list[str], archives: list[Path]) -> Path:
    first = Path(paths[0]) if paths else archives[0].parent
    folder = first if first.is_dir() else first.parent
    return folder / CSV_NAME
