"""Шаг 33, SNO-F-RES-01 (часть): «Проверка записи» — годна ли запись.

Архивы собираются здесь по формату приложения (`archive.dart`):
манифест первым, перечень файлов с суммами, байтами и числом строк.
Что тот же разбор понимает архив, собранный самим приложением, —
проверяет `test/sno/record_check_test.dart` на стороне Dart.
"""

import csv
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

from sno_eye import record_check as rc

EYE = Path(__file__).resolve().parent.parent

NAME = "sno2026_II_93461318_d10708_20261010-0002.zip"


def jsonl(rows):
    return "".join(json.dumps(r, ensure_ascii=False) + "\n"
                   for r in rows).encode("utf-8")


def journal(count=6, study_ms=600_000, without_test=False):
    rows = [{"seq": 1, "t": 0, "wall": "w", "type": "recording.start",
             "screen": "testing"}]
    for seq in range(2, count - 1):
        rows.append({"seq": seq, "t": seq * 1000, "wall": "w",
                     "type": "page.shown", "screen": "reader"})
    rows.append({"seq": count - 1, "t": 700_000, "wall": "w",
                 "type": "recording.stop", "screen": "reader",
                 "data": {"by": "experimenter", "study_ms": study_ms}})
    data = {"without_test": True} if without_test else {}
    finish = {"seq": count, "t": 900_000, "wall": "w", "phase": "post",
              "type": "session.finish", "screen": "finish"}
    if data:
        finish["data"] = data
    rows.append(finish)
    return rows


def gaze(frames=300, ok_every=1, seg_break=None, fps=30):
    rows = []
    for i in range(frames):
        seg = 0 if seg_break is None or i < seg_break else 1
        t = 20_000 + i * 1000 // fps + (5000 if seg else 0)
        rows.append({"n": i + 1, "t": t, "x": 100.0, "y": 200.0,
                     "ok": i % ok_every == 0, "conf": 1.0, "seg": seg})
    return rows


def manifest_for(files, *, pc=True, gaze_present=True, study_tag="sno2026-1",
                 info=None, eye=None, clt="complete", verdict="ok",
                 events=None):
    recording = {
        "id": "01KB5Z3M4N7Q8R9S0T1V2W3X4Y",
        "clock_anchor": "2026-10-10T00:02:11.482+03:00",
        "planned_s": 2400, "duration_s": 700, "duration_ms": 700_000,
        "stopped_by": "experimenter", "events": events, "finished": True,
        "in_background": False, "study_t": 100_000,
        "away": {"count": 0, "total_ms": 0, "hidden_ms": 0, "longest_ms": 0},
    }
    eye_tracker = {"present": False}
    if pc:
        eye_tracker = {
            "present": gaze_present, "configured": True, "source": "webcam",
            "quality": "ok",
            "calibration": {"attempts": 1, "accepted": True,
                            "accuracy_deg": 1.4},
            "end_check": {"done": True, "accuracy_deg": 1.8,
                          "drift_deg": 0.4},
            "file": "eye/gaze.jsonl", "segments": 1,
        }
        if not gaze_present:
            eye_tracker = {"present": False, "configured": True,
                           "reason": "selfcheck_failed"}
    if eye:
        eye_tracker.update(eye)
    app = {"version": "0.39.0-sno2026.II", "commit": "a" * 40,
           "flags": ["запись"], "built": "2026-10-10"}
    if study_tag:
        app["study_tag"] = study_tag
    manifest = {
        "schema": "sno2026-recording/1", "branch": "II", "app": app,
        "device": {"node_id": "d10708aa", "code": "d10708",
                   "os": "windows" if pc else "Android"},
        "participant": {"code": "93461318", "generated": True},
        "recording": recording,
        "input": {"file": "input.jsonl", "lines": None, "blind": []},
        "layout": {"file": "layout.jsonl", "lines": None,
                   "units": "logical_px"},
        "eye_tracker": eye_tracker,
        "archive": {"name": NAME, "packer": "memoria-zip/1",
                    "packed_at": "2026-10-10T00:20:00+03:00"},
    }
    if clt is not None:
        manifest["clt"] = {"final": clt, "checks_flags": 0}
    if info:
        for key, value in info.items():
            manifest[key] = value
    entries = {}
    for name, data in files.items():
        entry = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        if name.endswith(".jsonl"):
            entry["lines"] = data.count(b"\n")
            entry["dropped_lines"] = 0
        entries[name] = entry
    manifest["files"] = entries
    return manifest


def usual_files(*, pc=True, gaze_rows=None, journal_rows=None, verdict="ok"):
    files = {
        "events.jsonl": jsonl(journal_rows or journal()),
        "input.jsonl": jsonl({"n": i, "t": i * 100} for i in range(1, 21)),
        "layout.jsonl": jsonl({"n": i, "t": i * 500} for i in range(1, 11)),
        "snapshot_start.json": b'{"schema": "sno2026-snapshot/1"}',
        "snapshot_end.json": b'{"schema": "sno2026-snapshot/1"}',
        "clt/scores.json": json.dumps(
            {"schema": "sno2026-clt-scores/1",
             "checks": {"flags": 0, "verdict": verdict}}).encode(),
    }
    if pc:
        files["eye/gaze.jsonl"] = jsonl(gaze_rows or gaze())
        files["eye/features.bin"] = b"\x00" * 4096
        files["eye/eyes.mp4"] = b"\x01" * 8192
    return files


def write_archive(folder, files, manifest, name=NAME, tamper=None):
    path = Path(folder) / name
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        for entry, data in files.items():
            if tamper and entry in tamper:
                data = tamper[entry](data)
            mode = zipfile.ZIP_STORED if entry.endswith((".bin", ".mp4")) \
                else zipfile.ZIP_DEFLATED
            z.writestr(entry, data, compress_type=mode)
    return path


def make(tmp_path, *, files=None, tamper=None, **kw):
    pc = kw.get("pc", True)
    files = files or usual_files(pc=pc, verdict=kw.pop("verdict", "ok"))
    manifest = manifest_for(files, **kw)
    return write_archive(tmp_path, files, manifest, tamper=tamper)


# --- правило сверки потока: вторая реализация `checkJournal` -----------

def test_sno_f_res_01_stream_rule_counts_gaps_and_torn_tail():
    """SNO-F-RES-01: поток сверяется тем же правилом, что в приложении:
    пропуски — от единицы до большего из наибольшего номера и
    ожидаемого, мусор занимает чужой номер, хвост без перевода строки
    оборван."""
    data = jsonl([{"seq": 1}, {"seq": 2}, {"seq": 4}])
    assert rc.check_stream(data, "seq") == {
        "lines": 3, "gaps": 1, "torn": False, "junk": 0, "highest": 4}
    # Ожидалось шесть — два последних потеряны.
    assert rc.check_stream(data, "seq", expected=6)["gaps"] == 3
    # Мусорная строка считается строкой, но номера не даёт.
    junk = jsonl([{"n": 1}]) + b"not json\n" + jsonl([{"n": 3}])
    result = rc.check_stream(junk, "n")
    assert (result["lines"], result["gaps"], result["junk"]) == (3, 1, 1)
    # Порядок строк не важен: строка ввода пишется, когда палец поднят.
    shuffled = jsonl([{"n": 2}, {"n": 1}, {"n": 3}])
    assert rc.check_stream(shuffled, "n")["gaps"] == 0
    # Оборванный хвост.
    torn = jsonl([{"seq": 1}]) + b'{"seq": 2'
    result = rc.check_stream(torn, "seq")
    assert result["torn"] is True and result["lines"] == 1
    # Пустой поток цел.
    assert rc.check_stream(b"", "seq")["gaps"] == 0
    # Логическое `true` — не номер.
    assert rc.check_stream(jsonl([{"seq": True}]), "seq")["junk"] == 1


# --- годная запись --------------------------------------------------

def test_sno_f_res_01_whole_pc_record_on_study_build_is_good(tmp_path):
    """SNO-F-RES-01: запись ПК со взглядом на сборке исследования, всё
    на месте — «годна»; числа взгляда посчитаны по самому потоку."""
    report = rc.check_archive(make(tmp_path))
    assert report["verdict"] == rc.GOOD, report["notes"] + report["problems"]
    assert report["verdict_text"] == "годна"
    assert report["files"] == {"listed": 9, "intact": 9}
    assert report["platform"] == "ПК"
    assert report["study_tag"] == "sno2026-1"
    assert report["study_s"] == pytest.approx(600)
    assert report["valid_share"] == pytest.approx(1.0)
    assert report["fps"] == pytest.approx(30, abs=0.5)
    assert report["start_deg"] == pytest.approx(1.4)
    assert report["end_deg"] == pytest.approx(1.8)
    assert report["segments"] == 1
    assert report["streams"]["events.jsonl"]["lines"] == 6
    assert report["test"] == "complete"
    text = "\n".join(rc.describe(report))
    assert "годна" in text and "участник 9346 1318" in text
    assert "точность в начале 1,4°, в конце 1,8°" in text


def test_sno_f_res_01_phone_record_without_gaze_is_good(tmp_path):
    """SNO-F-RES-01: на телефоне взгляд не пишется — это не оговорка."""
    report = rc.check_archive(make(tmp_path, pc=False))
    assert report["verdict"] == rc.GOOD, report["notes"]
    assert report["platform"] == "телефон"
    assert "телефон: взгляд не пишется" in report["info"]


# --- не годна -------------------------------------------------------

def test_sno_f_res_01_changed_byte_makes_record_unusable(tmp_path):
    """SNO-F-RES-01: файл не сходится с суммой манифеста — «не годна»."""
    path = make(tmp_path, tamper={
        "events.jsonl": lambda d: d.replace(b"reader", b"readex", 1)})
    report = rc.check_archive(path)
    assert report["verdict"] == rc.BAD
    assert any("events.jsonl не тот: сумма" in p for p in report["problems"])


def test_sno_f_res_01_broken_zip_is_unusable(tmp_path):
    """SNO-F-RES-01: испорченный байт внутри ZIP — контрольная сумма
    самого архива ловит его до манифеста."""
    path = make(tmp_path)
    raw = bytearray(path.read_bytes())
    at = raw.find(b"\x01" * 64)  # полоса глаз лежит без сжатия
    raw[at + 10] ^= 0xFF
    path.write_bytes(bytes(raw))
    report = rc.check_archive(path)
    assert report["verdict"] == rc.BAD
    assert any("испорчен" in p or "не тот" in p for p in report["problems"])


def test_sno_f_res_01_broken_deflate_is_unusable_not_a_crash(tmp_path):
    """SNO-F-RES-01: испорченные сжатые данные журнала ломают распаковку
    — разбор отвечает «не годна», а не падает."""
    path = make(tmp_path)
    raw = bytearray(path.read_bytes())
    head = raw.find(b"PK\x03\x04", raw.find(b"events.jsonl") - 40)
    name_len = int.from_bytes(raw[head + 26:head + 28], "little")
    extra = int.from_bytes(raw[head + 28:head + 30], "little")
    at = head + 30 + name_len + extra
    for i in range(4):
        raw[at + 2 + i] ^= 0xFF
    path.write_bytes(bytes(raw))
    report = rc.check_archive(path)
    assert report["verdict"] == rc.BAD
    assert report["problems"]


def test_sno_f_res_01_missing_file_and_journal(tmp_path):
    """SNO-F-RES-01: файла из перечня в архиве нет — «не годна»; без
    журнала запись не годна тоже."""
    files = usual_files()
    manifest = manifest_for(files)
    del files["events.jsonl"]
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    assert report["verdict"] == rc.BAD
    assert "в архиве нет файла events.jsonl" in report["problems"]
    assert "в архиве нет журнала events.jsonl" in report["problems"]


def test_sno_f_res_01_not_an_archive(tmp_path):
    path = tmp_path / NAME
    path.write_bytes(b"not a zip")
    report = rc.check_archive(path)
    assert report["verdict"] == rc.BAD
    assert report["problems"][0].startswith("архив не открывается")


def test_sno_f_res_01_unknown_schema(tmp_path):
    files = usual_files()
    manifest = manifest_for(files)
    manifest["schema"] = "sno2026-recording/9"
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    assert report["verdict"] == rc.BAD
    assert "схема манифеста" in report["problems"][0]


# --- с оговорками ---------------------------------------------------

def test_sno_f_res_01_trial_build_is_a_note(tmp_path):
    """SNO-F-CFG-06: запись проверочной сборки — с оговоркой."""
    report = rc.check_archive(make(tmp_path, study_tag=None))
    assert report["verdict"] == rc.WARN
    assert ("записана на проверочной сборке, а не на сборке исследования"
            in report["notes"])


def test_sno_f_res_01_journal_gap_is_a_note(tmp_path):
    """SNO-F-RES-01: журнал без строки и с недосчитанным хвостом —
    «с оговорками», с числом пропущенных."""
    rows = journal(8)
    del rows[3]
    files = usual_files(journal_rows=rows)
    report = rc.check_archive(write_archive(
        tmp_path, files, manifest_for(files, events=10)))
    assert report["verdict"] == rc.WARN
    assert "журнал неполон: пропущено строк 3" in report["notes"]


def test_sno_f_res_01_no_gaze_on_pc_names_the_reason(tmp_path):
    """SNO-F-RES-01: на ПК взгляд не записан — причина словами."""
    files = usual_files(pc=False)
    report = rc.check_archive(write_archive(
        tmp_path, files, manifest_for(files, pc=True, gaze_present=False)))
    assert report["verdict"] == rc.WARN
    assert ("взгляд не записан: самопроверка места не прошла"
            in report["notes"])
    assert "взгляда нет" in "\n".join(rc.describe(report))


def test_sno_f_res_01_poor_gaze_is_named(tmp_path):
    """SNO-F-RES-01, Т19: средняя точность хуже 3°, годных кадров меньше
    половины, кадров меньше 25 в секунду, калибровка «с пометкой»."""
    files = usual_files(gaze_rows=gaze(frames=200, ok_every=3, fps=15))
    manifest = manifest_for(files, eye={
        "quality": "low",
        "calibration": {"attempts": 2, "accepted": False,
                        "accuracy_deg": 3.2},
        "end_check": {"done": True, "accuracy_deg": 4.0}})
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    assert report["verdict"] == rc.WARN
    notes = "\n".join(report["notes"])
    assert "«Писать с пометкой»" in notes
    assert "точность 3,6° хуже 3,0°" in notes
    assert "годных кадров взгляда 34 % — меньше 50 %" in notes
    assert "кадров взгляда в секунду 15" in notes


def test_sno_f_res_01_skipped_end_check(tmp_path):
    files = usual_files()
    manifest = manifest_for(files, eye={"end_check": {"skipped": True}})
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    assert ("проверку точности в конце пропустили — точность известна "
            "только по началу" in report["notes"])
    # Средняя — по тому, что есть: по началу.
    assert report["mean_deg"] == pytest.approx(1.4)


def test_sno_f_res_01_segments_count_frames_without_restart_gap(tmp_path):
    """SNO-F-RES-01: подъём спутника заново — не кадры: частота считается
    по времени внутри сегментов."""
    files = usual_files(gaze_rows=gaze(frames=300, seg_break=150))
    report = rc.check_archive(write_archive(tmp_path, files,
                                            manifest_for(files)))
    assert report["segments"] == 2
    assert report["fps"] == pytest.approx(30, abs=0.5)
    assert "спутник поднимали заново: сегментов 2" in report["info"]


def test_sno_f_res_01_test_closed_by_organizer(tmp_path):
    """SNO-F-RES-01: тест нагрузки закрыт выходом организатора; второй
    — самопроверка ответов подняла два флага."""
    files = usual_files(journal_rows=journal(without_test=True))
    report = rc.check_archive(write_archive(
        tmp_path, files, manifest_for(files, clt="none")))
    assert ("тест нагрузки не пройден — закрыт выходом организатора «Тест "
            "пройти нельзя»" in report["notes"])
    files = usual_files(verdict="doubt")
    report = rc.check_archive(write_archive(tmp_path, files,
                                            manifest_for(files),
                                            name="doubt.zip"))
    assert report["test_verdict"] == "doubt"
    assert any("два флага" in n for n in report["notes"])


def test_sno_f_res_01_crash_and_away(tmp_path):
    files = usual_files()
    manifest = manifest_for(files)
    manifest["recording"]["stopped_by"] = "crash"
    manifest["recording"]["away"] = {"count": 2, "total_ms": 65_000,
                                     "hidden_ms": 60_000, "longest_ms": 60_000}
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    notes = "\n".join(report["notes"])
    assert "запись оборвалась" in notes
    assert "участник уходил из приложения: 2 раз, всего 1 мин 05 с" in notes


def test_sno_f_res_01_old_build_without_streams_is_not_a_note(tmp_path):
    """SNO-F-RES-01: у записи прежней сборки нет потоков ввода и кадров —
    это сведения, а не оговорка."""
    files = usual_files(pc=False)
    del files["input.jsonl"], files["layout.jsonl"]
    manifest = manifest_for(files, pc=False)
    del manifest["input"], manifest["layout"]
    report = rc.check_archive(write_archive(tmp_path, files, manifest))
    assert report["verdict"] == rc.GOOD, report["notes"]
    assert "потока ввода нет — запись прежней сборки" in report["info"]


# --- вход и таблица -------------------------------------------------

def test_sno_f_res_01_folder_gives_table_and_exit_code(tmp_path, capsys):
    """SNO-F-RES-01: папка с архивами — итог по каждому, таблица рядом
    (разделитель «;», метка UTF-8 для Excel) и код выхода по худшему."""
    folder = tmp_path / "Записи"
    folder.mkdir()
    files = usual_files()
    write_archive(folder, files, manifest_for(files),
                  name="sno2026_II_1_a_1.zip")
    write_archive(folder, files, manifest_for(files, study_tag=None),
                  name="sno2026_II_2_a_2.zip")
    (folder / "не архив.txt").write_text("x", encoding="utf-8")
    code = rc.main([str(folder)])
    out = capsys.readouterr().out
    assert code == 1
    assert "Проверено архивов: 2 — годны 1, с оговорками 1, не годны 0" in out
    table = folder / rc.CSV_NAME
    raw = table.read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    rows = list(csv.reader(raw.decode("utf-8-sig").splitlines(),
                           delimiter=";"))
    assert rows[0][0] == "архив" and rows[0][-1] == "причины"
    assert [r[1] for r in rows[1:]] == ["годна", "с оговорками"]
    assert rows[1][rows[0].index("точность в начале, °")] == "1,40"


def test_sno_f_res_01_nothing_to_check(tmp_path, capsys, monkeypatch):
    monkeypatch.delenv("APPDATA", raising=False)
    assert rc.main([]) == 3
    assert rc.main([str(tmp_path)]) == 3
    assert "Архивов записи не нашлось" in capsys.readouterr().out


def test_sno_f_res_01_default_folders_find_branch_records(tmp_path,
                                                          monkeypatch):
    """SNO-F-RES-01: без имён — папки «Записи» сборок ветвей в данных
    приложения на этом ПК."""
    records = tmp_path / "HohloBaron" / "Memoria LLM HB" / "sno2026-II" \
        / "Записи"
    records.mkdir(parents=True)
    (tmp_path / "HohloBaron" / "Memoria LLM HB" / "Записи").mkdir()
    monkeypatch.setenv("APPDATA", str(tmp_path))
    assert rc.default_folders() == [str(records)]


def test_sno_f_res_01_thresholds_come_from_file():
    limits = rc.thresholds()
    raw = json.loads((EYE / "thresholds.json").read_text(encoding="utf-8"))
    assert limits["include_deg"] == raw["record_check"]["include_deg"] == 3.0
    assert set(raw["record_check"]) == set(rc.DEFAULTS)


def test_sno_f_res_01_command_line_is_light(tmp_path):
    """SNO-F-RES-01: `python -m sno_eye check` не тянет numpy, OpenCV и
    MediaPipe: проверка не ждёт их загрузки и идёт рядом со спутником,
    не занимая его замка."""
    path = make(tmp_path)
    script = (
        "import sys, json\n"
        "from sno_eye.__main__ import main\n"
        f"code = main(['check', {str(path)!r}, '--json', '--no-csv'])\n"
        "heavy = [m for m in ('numpy', 'cv2', 'mediapipe') if m in sys.modules]\n"
        "print('CODE', code, 'HEAVY', heavy)\n")
    result = subprocess.run([sys.executable, "-c", script], cwd=EYE,
                            capture_output=True, text=True, encoding="utf-8")
    assert result.returncode == 0, result.stderr
    assert "CODE 0 HEAVY []" in result.stdout
    report = json.loads(result.stdout[:result.stdout.rindex("CODE")])
    assert report[0]["verdict"] == "ok"


def test_sno_f_res_01_cmd_shortcut():
    raw = (EYE / "Проверка записи.cmd").read_bytes()
    text = raw.decode("ascii")
    assert '"%~dp0python.exe" -I -m sno_eye check %*' in text
    assert "\r\n" in text


def test_sno_f_cfg_06_organizer_guide_goes_into_the_zip():
    """SNO-F-CFG-06: инструкция организатора лежит в папке eye/ сборки."""
    sys.path.insert(0, str(EYE / "tool"))
    import build_windows
    assert "Инструкция организатора.txt" in build_windows.COPY
    assert "Проверка записи.cmd" in build_windows.COPY
    text = (EYE / "Инструкция организатора.txt").read_text(encoding="utf-8-sig")
    assert "eye\\Проверка записи.cmd" in text
    assert "sno2026-N" in text
