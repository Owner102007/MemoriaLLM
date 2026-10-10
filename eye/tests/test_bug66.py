"""BUG-66: запись шла при 10 кадрах в секунду, хотя самопроверка видела 30.

Второй ПК (ноутбук Thunderobot, камера Chicony USB2.0, 10.10.2026):
самопроверка — 29,9 к/с при 1280×720, вся запись — ровно 10. Стенд
«Настройка камеры.cmd» показал: камера отдаёт кадры в YUY2, а не в MJPG,
и окно драйвера частоты не поднимает.

Причина — порядок запросов к камере в `CvSource.open`: формат MJPG, затем
частота, затем размер. DirectShow в OpenCV перенастраивает камеру на
каждый запрос, и частота и размер после формата перенастраивают её без
формата — драйвер встаёт в первый формат этого размера по порядку
OpenCV, несжатый YUY2 раньше MJPG; YUY2 1280×720 по USB 2.0 — 10 к/с.
Самопроверка просила 1080p: такого размера у камеры нет, и DirectShow
брал ближайший в перечне драйвера — MJPG 1280×720, 30 к/с. Запись
открывала ровно 1280×720 и получала YUY2.

Камера здесь — `fake_dshow`: поддельный `cv2`, который настраивает
камеру как `cap_dshow.cpp` OpenCV 5.0.0.
"""

import time

import pytest

import fake_dshow as fd
from sno_eye import capture, privacy, selfcheck
from sno_eye.capture import CameraInfo, CvSource
from sno_eye.landmarks import SyntheticLandmarker
from sno_eye.protocol import Server
from sno_eye.runtime import Runtime
from test_robustness import FakeOut, cmd, wait_no_capture

CHICONY = CameraInfo(0, "Chicony USB2.0 Camera",
                     r"\\?\usb#vid_04f2&pid_b729&mi_00", "dshow")


@pytest.fixture
def camera(monkeypatch):
    """Поддельный `cv2` с камерой [caps] вместо настоящего."""

    def make(caps=fd.CHICONY, **kw):
        fake = fd.FakeCv2(caps, **kw)
        monkeypatch.setitem(__import__("sys").modules, "cv2", fake.module)
        monkeypatch.setattr(privacy, "denied_here", lambda: False)
        return fake

    return make


def old_open(cv2, mode):
    """Как спутник открывал камеру до правки."""
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    cap.set(cv2.CAP_PROP_FPS, 30)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, mode[0])
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, mode[1])
    return cap


# --- причина: поддельная камера ведёт себя как камера второго ПК --------

def test_bug66_old_order_gives_yuy2_at_10_fps():
    fake = fd.FakeCv2()
    cap = old_open(fake.module, (1280, 720))
    # Что видел стенд на втором ПК: YUY2, 1280×720, «30» от драйвера —
    # это запрошенная частота, а кадров 10.
    assert fake.format() == ("YUY2", 1280, 720)
    assert fake.real_fps() == 10.0
    assert capture.fourcc_text(cap.get(fake.module.CAP_PROP_FOURCC)) == "YUY2"
    assert cap.get(fake.module.CAP_PROP_FPS) == 30.0


def test_bug66_old_order_selfcheck_1080p_got_mjpg_720p():
    # Самопроверка просит 1080p, которого нет: ближайший размер в
    # перечне драйвера — MJPG 1280×720, 30 к/с. Отсюда её 29,9.
    fake = fd.FakeCv2()
    old_open(fake.module, (1920, 1080))
    assert fake.format() == ("MJPG", 1280, 720)
    assert fake.real_fps() == 30.0


def test_bug66_fps_or_size_after_fourcc_drops_mjpg():
    fake = fd.FakeCv2()
    cv2 = fake.module
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    assert fake.format() == ("MJPG", 1280, 720)
    cap.set(cv2.CAP_PROP_FPS, 30)
    assert fake.format() == ("YUY2", 1280, 720)


# --- правка: CvSource.open -------------------------------------------------

def test_bug66_open_720p_gives_mjpg_at_30_fps(camera):
    fake = camera()
    src = CvSource(CHICONY)
    src.open((1280, 720))
    try:
        assert fake.format() == ("MJPG", 1280, 720)
        assert fake.real_fps() == 30.0
        assert (src.width, src.height, src.fourcc) == (1280, 720, "MJPG")
        # Формат — последний запрос: после него камеру никто не
        # перенастраивает.
        sets = [e for e in fake.log if e[0] == "set"]
        assert sets[-1][1] == fd.CONSTANTS["CAP_PROP_FOURCC"]
        assert sets[0][1] == fd.CONSTANTS["CAP_PROP_FPS"]
    finally:
        src.close()


def test_bug66_selfcheck_and_record_open_the_same_format(camera):
    fake = camera()
    # Самопроверка — 1080p, ближайший 720p.
    src = CvSource(CHICONY)
    src.open((1920, 1080))
    assert (src.width, src.height, src.fourcc) == (1280, 720, "MJPG")
    assert fake.real_fps() == 30.0
    src.close()
    # Запись — ровно режим самопроверки.
    src = CvSource(CHICONY)
    src.open((1280, 720))
    assert fake.format() == ("MJPG", 1280, 720)
    assert fake.real_fps() == 30.0
    src.close()


def test_bug66_full_hd_camera_keeps_1080p_mjpg(camera):
    fake = camera(fd.FULL_HD)
    src = CvSource(CHICONY)
    src.open((1920, 1080))
    assert fake.format() == ("MJPG", 1920, 1080)
    assert fake.real_fps() == 30.0
    assert src.fourcc == "MJPG"
    src.close()


def test_bug66_camera_without_mjpg_opens_and_names_format(camera):
    fake = camera(fd.YUY2_ONLY)
    src = CvSource(CHICONY)
    src.open((1280, 720))
    assert fake.format() == ("YUY2", 1280, 720)
    assert (src.width, src.height, src.fourcc) == (1280, 720, "YUY2")
    src.close()


def test_bug66_mjpg_without_frames_reopens_without_it(camera):
    # Драйвер принял MJPG, а кадров не отдаёт — камера открывается заново
    # без формата, как могла и до правки.
    fake = camera(broken=("MJPG",))
    src = CvSource(CHICONY)
    src.open((1280, 720))
    assert fake.format() == ("YUY2", 1280, 720)
    assert src.fourcc == "YUY2"
    src.close()


def test_bug66_fourcc_text():
    assert capture.fourcc_text(fd.fourcc("MJPG")) == "MJPG"
    assert capture.fourcc_text(float(fd.fourcc("YUY2"))) == "YUY2"
    for value in (0, -1, None, "x", 1000 + 0):
        assert capture.fourcc_text(value) is None


# --- самопроверка называет формат -----------------------------------------

T = selfcheck.load_thresholds()
GOOD_M = {
    "satellite": True, "camera": "ok", "width": 1280, "height": 720,
    "fps": 29.5, "face_share": 0.99, "iris_px": 22.0, "light": 120.0,
    "backlight": 1.1, "glare": 0.0, "position": 0.05,
    "disk_free_bytes": 50e9, "cpu_percent": 20.0,
}


def fps_row(**m):
    res = selfcheck.evaluate({**GOOD_M, **m}, T)
    return [r for r in res["checks"] if r["id"] == "fps"][0]


def test_bug66_selfcheck_says_uncompressed_not_light():
    row = fps_row(fps=10.0, camera_fps=10.0, drop_share=0.0, proc_ms=12.0,
                  fourcc="YUY2")
    assert row["verdict"] == "fail"
    assert row["text"] == ("Камера даёт 10.0 к/с: кадры идут без сжатия, "
                           "а не в MJPG")
    # MJPG или формат не известен — прежние слова про свет.
    for fourcc in ("MJPG", None):
        row = fps_row(fps=10.0, camera_fps=10.0, drop_share=0.0,
                      proc_ms=12.0, fourcc=fourcc)
        assert "мало света" in row["text"]
    # Годится — формат не важен.
    assert fps_row(fps=29.5, camera_fps=29.5, drop_share=0.0, proc_ms=12.0,
                   fourcc="YUY2")["text"] == "Частота 29.5 к/с"
    # ПК не успевает — дело в ПК, а не в формате.
    assert fps_row(fps=16.0, camera_fps=30.0, drop_share=0.45, proc_ms=60.0,
                   fourcc="YUY2")["text"] == "ПК не успевает: 16.0 к/с"


# --- как на втором ПК: самопроверка, затем запись -------------------------

class ChiconyRuntime(Runtime):
    """Настоящий путь камеры (`CvSource`) с поддельным `cv2` и
    распознаванием без модели."""

    def cameras(self):
        return [CHICONY]

    def landmarker(self):
        if self._landmarker is None:
            self._landmarker = SyntheticLandmarker()
        return self._landmarker


def test_bug66_record_keeps_selfcheck_frame_rate(camera, tmp_path):
    fake = camera(pace=True)
    out = FakeOut()
    s = Server(ChiconyRuntime("camera"), out)
    try:
        s.handle(cmd(cmd="selfcheck", seconds=1.0, warmup=0.2,
                     dir=str(tmp_path / "check")))
        m = out.last("reply")["measures"]
        assert [m["width"], m["height"]] == [1280, 720]
        assert m["camera_fps"] > 25
        # Запись без режима — режим самопроверки: частота та же.
        s.handle(cmd(cmd="open", dir=str(tmp_path / "rec")))
        assert out.last("reply")["frame"] == [1280, 720]
        time.sleep(2.2)
        fps = s.session.fps()
        assert fps > 25, fps
        assert fake.format() == ("MJPG", 1280, 720)
        assert m["fourcc"] == "MJPG"
        assert all(t["fourcc"] == "MJPG" for t in m["tried"])
        s.handle(cmd(cmd="close"))
        summary = (tmp_path / "rec" / "summary.json").read_text("utf-8")
        assert '"fourcc": "MJPG"' in summary
    finally:
        s.shutdown()
    assert wait_no_capture()
