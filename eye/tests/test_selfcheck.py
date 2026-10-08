"""SNO-ALG-EYE-04: самопроверка места — каждая строка таблицы на
границах порогов и общий итог."""

import pytest

from sno_eye import privacy, selfcheck

T = selfcheck.load_thresholds()

GOOD_M = {
    "satellite": True, "camera": "ok", "width": 1920, "height": 1080,
    "fps": 29.5, "face_share": 0.99, "iris_px": 22.0, "light": 120.0,
    "backlight": 1.1, "glare": 0.0, "position": 0.05,
    "disk_free_bytes": 50e9, "cpu_percent": 20.0,
}


def verdict_of(row_id, **change):
    res = selfcheck.evaluate({**GOOD_M, **change}, T)
    rows = {r["id"]: r for r in res["checks"]}
    return rows[row_id]["verdict"], res["verdict"], rows[row_id]["text"]


def test_sno_alg_eye_04_all_good():
    res = selfcheck.evaluate(GOOD_M, T)
    assert res["verdict"] == "good" and res["words"] == "годится"
    ids = [r["id"] for r in res["checks"]]
    assert ids == ["satellite", "camera", "mode", "fps", "face", "iris", "light",
                   "backlight", "glare", "position", "disk", "cpu"]


@pytest.mark.parametrize("row,key,value,want,total", [
    ("mode", "height", 1080, "good", "good"),
    ("mode", "height", 720, "warn", "warn"),
    ("mode", "height", 719, "fail", "fail"),
    ("fps", "fps", 27.0, "good", "good"),
    ("fps", "fps", 26.99, "warn", "warn"),
    ("fps", "fps", 25.0, "warn", "warn"),
    ("fps", "fps", 24.99, "fail", "fail"),
    ("face", "face_share", 0.95, "good", "good"),
    ("face", "face_share", 0.80, "warn", "warn"),
    ("face", "face_share", 0.79, "fail", "fail"),
    ("iris", "iris_px", 18.0, "good", "good"),
    ("iris", "iris_px", 14.0, "warn", "warn"),
    ("iris", "iris_px", 13.9, "fail", "fail"),
    ("light", "light", 70.0, "good", "good"),
    ("light", "light", 200.0, "good", "good"),
    ("light", "light", 50.0, "warn", "warn"),
    ("light", "light", 49.9, "fail", "warn"),     # не решающая строка
    ("light", "light", 215.0, "warn", "warn"),
    ("light", "light", 230.1, "fail", "warn"),
    ("backlight", "backlight", 0.7, "good", "good"),
    ("backlight", "backlight", 0.5, "warn", "warn"),
    ("backlight", "backlight", 0.49, "fail", "warn"),
    ("glare", "glare", 0.0049, "good", "good"),
    ("glare", "glare", 0.005, "warn", "warn"),
    ("glare", "glare", 0.02, "warn", "warn"),
    ("glare", "glare", 0.021, "fail", "warn"),
    ("position", "position", 0.15, "good", "good"),
    ("position", "position", 0.25, "warn", "warn"),
    ("position", "position", 0.26, "fail", "warn"),
    ("disk", "disk_free_bytes", 2.0e9, "good", "good"),
    ("disk", "disk_free_bytes", 1.0e9, "warn", "warn"),
    ("disk", "disk_free_bytes", 0.99e9, "fail", "warn"),
    ("cpu", "cpu_percent", 35.0, "good", "good"),
    ("cpu", "cpu_percent", 50.0, "warn", "warn"),
    ("cpu", "cpu_percent", 50.1, "fail", "warn"),
])
def test_sno_alg_eye_04_thresholds(row, key, value, want, total):
    got, overall, _ = verdict_of(row, **{key: value})
    assert (got, overall) == (want, total)


def test_sno_alg_eye_04_words_name_the_cause():
    assert "Мало света или слабый ПК" in verdict_of("fps", fps=20.0)[2]
    assert "Добавьте свет спереди" in verdict_of("light", light=30.0)[2]
    assert "Пересвет" in verdict_of("light", light=240.0)[2]
    assert "Окно или лампа за спиной" in verdict_of("backlight", backlight=0.3)[2]
    assert "Блики на глазах" in verdict_of("glare", glare=0.05)[2]
    assert "нужен 1080p" in verdict_of("iris", iris_px=10.0)[2]
    assert "Сядьте по центру" in verdict_of("position", position=0.4)[2]


@pytest.mark.parametrize("code,words", [
    ("camera_denied", "Камера запрещена в параметрах Windows"),
    ("camera_busy", "Камера занята другой программой"),
    ("no_camera", "Камера не найдена"),
])
def test_sno_alg_eye_04_camera_failures(code, words):
    res = selfcheck.evaluate({"satellite": True, "camera": code,
                              "disk_free_bytes": 5e9}, T)
    assert res["verdict"] == "fail"
    cam = [r for r in res["checks"] if r["id"] == "camera"][0]
    assert words in cam["text"]
    assert [r["id"] for r in res["checks"]] == ["satellite", "camera", "disk"]


def test_sno_alg_eye_04_satellite_did_not_start():
    res = selfcheck.evaluate({"satellite": "нет папки eye"}, T)
    assert res["verdict"] == "fail"
    assert "Айтрекер не запустился: нет папки eye" == res["checks"][0]["text"]


def test_sno_alg_eye_04_no_face_means_no_iris():
    res = selfcheck.evaluate({**GOOD_M, "face_share": 0.0, "iris_px": None}, T)
    rows = {r["id"]: r for r in res["checks"]}
    assert rows["iris"]["verdict"] == "fail" and res["verdict"] == "fail"


def test_sno_alg_eye_04_registry_deny():
    def reader(values):
        return lambda root, key: values.get((root, key))
    base = privacy.KEY
    nonpkg = privacy.KEY + r"\NonPackaged"
    assert not privacy.camera_denied(reader({}))
    assert not privacy.camera_denied(reader({("HKCU", base): "Allow",
                                             ("HKCU", nonpkg): "Allow"}))
    assert privacy.camera_denied(reader({("HKCU", nonpkg): "Deny"}))
    assert privacy.camera_denied(reader({("HKLM", base): "Deny"}))
    assert privacy.camera_denied(reader({("HKCU", base): " deny "}))


def test_sno_alg_eye_04_thresholds_file_matches_table():
    # Числа таблицы из заметки SNO-ALG-EYE-04 — чтобы правка файла была
    # осознанной.
    assert T["fps"] == {"good": 27, "warn": 25}
    assert T["face_share"] == {"good": 0.95, "warn": 0.80}
    assert T["iris_px"] == {"good": 18, "warn": 14}
    assert T["cpu_percent"] == {"good": 35, "warn": 50}
    assert T["warmup_s"] == 2 and T["measure_s"] == 5
