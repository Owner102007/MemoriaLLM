import os
import sys
from pathlib import Path

EYE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(EYE))

import pytest  # noqa: E402


@pytest.fixture
def eye_dir() -> Path:
    return EYE


@pytest.fixture
def instance_name(monkeypatch, tmp_path):
    """Своё имя экземпляра на тест — тесты не мешают друг другу и
    спутнику, запущенному рядом."""
    name = "SnoEyeTest" + str(abs(hash(str(tmp_path))))
    monkeypatch.setenv("SNO_EYE_INSTANCE", name)
    return name


def satellite_env(instance: str) -> dict:
    env = dict(os.environ)
    env["SNO_EYE_INSTANCE"] = instance
    env["PYTHONPATH"] = str(EYE)
    env["MPLBACKEND"] = "Agg"
    return env
