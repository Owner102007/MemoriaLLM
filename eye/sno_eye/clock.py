"""Часы спутника (SNO-ALG-EYE-03, шаг 6).

`perf_counter_ns` на Windows — тот же QueryPerformanceCounter, что у
приложения: одна частота и одно начало у всех процессов машины. Поэтому
метка кадра в микросекундах сравнима с меткой точки калибровки без
перевода. Сдвиг `offset_us` нужен только тестам: им задаётся
расхождение часов, которое рукопожатие `sync` обязано найти.
"""

from __future__ import annotations

import time

_offset_us = 0


def set_offset_us(value: int) -> None:
    global _offset_us
    _offset_us = int(value)


def qpc_us() -> int:
    return time.perf_counter_ns() // 1000 + _offset_us
