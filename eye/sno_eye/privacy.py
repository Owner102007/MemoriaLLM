"""Запрет камеры в параметрах Windows (SNO-ALG-EYE-04, строка «камера»).

OpenCV не отличает «камера запрещена» от «камера занята»: в обоих
случаях она просто не открывается. Запрет читается из реестра:
`…\\CapabilityAccessManager\\ConsentStore\\webcam` и его подраздел
`NonPackaged` (классические приложения), значение `Value` = `Deny` в
HKCU или HKLM.
"""

from __future__ import annotations

import sys
from typing import Callable, Optional

KEY = r"SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
SUBKEYS = (KEY, KEY + r"\NonPackaged")
SETTINGS_URI = "ms-settings:privacy-webcam"

# (корень, путь) → значение `Value` или None.
Reader = Callable[[str, str], Optional[str]]


def camera_denied(read: Reader) -> bool:
    for root in ("HKCU", "HKLM"):
        for key in SUBKEYS:
            value = read(root, key)
            if value is not None and value.strip().lower() == "deny":
                return True
    return False


def windows_reader(root: str, key: str) -> Optional[str]:
    import winreg  # только Windows

    hive = winreg.HKEY_CURRENT_USER if root == "HKCU" else winreg.HKEY_LOCAL_MACHINE
    try:
        with winreg.OpenKey(hive, key) as k:
            value, _ = winreg.QueryValueEx(k, "Value")
            return str(value)
    except OSError:
        return None


def denied_here() -> bool:
    if sys.platform != "win32":
        return False
    return camera_denied(windows_reader)
