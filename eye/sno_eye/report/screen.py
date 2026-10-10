"""Экран места записи для разбора: пиксели окна ↔ градусы взгляда.

Размер окна в логических пикселях и в миллиметрах и расстояние до глаз
спутник кладёт в `eye/calibration.json` (`screen`), а приложение — в
команду `open`. Формулы те же, что у калибровки (`calib.Screen`), но
без numpy: разбор идёт тем же встраиваемым Python и на любом другом.

Экрана в записи нет (запись без взгляда, прежняя сборка) — берётся
типичный монитор: 0,277 мм на логический пиксель (24 дюйма, 1920
точек), 60 см до глаз; в итоге это помечено `known: false`.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

# Типичный монитор, когда экрана в записи нет.
FALLBACK_MM_PER_PX = 0.277
FALLBACK_DISTANCE_MM = 600.0


@dataclass
class Screen:
    """Окно приложения: логические пиксели, миллиметры, расстояние."""

    w: float
    h: float
    w_mm: float
    h_mm: float
    distance_mm: float
    known: bool = True

    def mm(self, x: float, y: float) -> tuple[float, float]:
        """Точка окна → миллиметры от середины экрана."""
        return ((x - self.w / 2) * self.w_mm / self.w,
                (y - self.h / 2) * self.h_mm / self.h)

    def angle_deg(self, a: tuple[float, float],
                  b: tuple[float, float]) -> float:
        """Угол между лучами от глаза к точкам окна [a] и [b]; глаз —
        напротив середины экрана."""
        d = self.distance_mm
        ax, ay = self.mm(*a)
        bx, by = self.mm(*b)
        dot = ax * bx + ay * by + d * d
        na = math.sqrt(ax * ax + ay * ay + d * d)
        nb = math.sqrt(bx * bx + by * by + d * d)
        c = max(-1.0, min(1.0, dot / (na * nb)))
        return math.degrees(math.acos(c))

    @property
    def px_per_mm(self) -> float:
        return (self.w / self.w_mm + self.h / self.h_mm) / 2

    def px_for_deg(self, deg: float) -> float:
        """Сколько логических пикселей в [deg] градусах у середины
        экрана."""
        return math.tan(math.radians(deg)) * self.distance_mm \
            * self.px_per_mm

    def deg_for_px(self, px: float) -> float:
        return math.degrees(math.atan(px / self.px_per_mm
                                      / self.distance_mm))


def _num(value) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(value):
        return float(value)
    return None


def screen_of(calibration: dict | None, frames: list[dict]) -> Screen:
    """Экран записи: из `calibration.json`, иначе — окно первого кадра
    раскладки на типичном мониторе."""
    raw = (calibration or {}).get("screen")
    if isinstance(raw, dict):
        values = [_num(raw.get(k)) for k in
                  ("w", "h", "w_mm", "h_mm", "distance_mm")]
        if all(v is not None and v > 0 for v in values):
            return Screen(*values)  # type: ignore[arg-type]
    w, h = 1280.0, 800.0
    for frame in frames:
        viewport = frame.get("viewport") or {}
        fw, fh = _num(viewport.get("w")), _num(viewport.get("h"))
        if fw and fh:
            w, h = fw, fh
            break
    return Screen(w, h, w * FALLBACK_MM_PER_PX, h * FALLBACK_MM_PER_PX,
                  FALLBACK_DISTANCE_MM, known=False)
