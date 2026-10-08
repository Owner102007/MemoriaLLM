"""Моргание (SNO-ALG-EYE-01, шаг 4).

Моргание — эпизод, в котором блендшейп `eyeBlink` любого глаза выше
0,5, и короче 400 мс. Одна открытость век его не определяет: взгляд к
низу страницы тоже опускает веки, и такое правило выбрасывало бы низ
страницы. Долгое прикрытие глаз — не моргание: кадры остаются годными.

Длину эпизода узнаёшь только в его конце, поэтому записи эпизода
придерживаются: не дольше 400 мс, дальше они отпускаются как есть.
"""

from __future__ import annotations

from collections import deque
from typing import Callable, Generic, Iterable, TypeVar

BLINK_SCORE = 0.5
BLINK_MAX_US = 400_000

T = TypeVar("T")


class BlinkGate(Generic[T]):
    """Задержка записей на время возможного моргания.

    `push(item, qpc_us, score)` — запись и наибольший `eyeBlink` её кадра
    (`None` — лица нет). Возвращает записи, решение о которых принято;
    `mark(item)` вызывается у тех, что оказались морганием.
    """

    def __init__(self, mark: Callable[[T], None]):
        self._mark = mark
        self._held: deque[tuple[T, int]] = deque()
        self._start: int | None = None
        self._passing = False  # эпизод уже длиннее 400 мс

    def push(self, item: T, qpc_us: int, score: float | None) -> list[T]:
        blinking = score is not None and score > BLINK_SCORE
        if blinking:
            if self._passing:
                return [item]
            if self._start is None:
                self._start = qpc_us
            self._held.append((item, qpc_us))
            if qpc_us - self._start >= BLINK_MAX_US:
                self._passing = True
                return self._release(blink=False)
            return []
        if self._passing:
            self._reset()
            return [item]
        out = self._end_episode(qpc_us)
        out.append(item)
        return out

    def flush(self) -> list[T]:
        if not self._held:
            self._reset()
            return []
        # Конец записи посреди эпизода: длина считается до последнего
        # придержанного кадра.
        return self._end_episode(self._held[-1][1])

    def _end_episode(self, now_us: int) -> list[T]:
        if self._start is None:
            self._reset()
            return []
        short = now_us - self._start < BLINK_MAX_US
        out = self._release(blink=short)
        self._reset()
        return out

    def _release(self, blink: bool) -> list[T]:
        out = []
        while self._held:
            item, _ = self._held.popleft()
            if blink:
                self._mark(item)
            out.append(item)
        return out

    def _reset(self) -> None:
        self._start = None
        self._passing = False


def run(gate: BlinkGate[T], items: Iterable[tuple[T, int, float | None]]) -> list[T]:
    """Прогнать ряд через затвор целиком — для тестов и разбора."""
    out: list[T] = []
    for item, t, score in items:
        out += gate.push(item, t, score)
    out += gate.flush()
    return out
