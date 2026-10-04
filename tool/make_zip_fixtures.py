#!/usr/bin/env python3
"""Генератор архивов-образцов для читателя ZIP (`test/fixtures/zip`).

Читатель архивов в приложении свой (`lib/infrastructure/files/
zip_reader.dart`, SNO-ALG-LIT-01), поэтому проверяется он на архивах,
собранных **другими** реализациями: модулем `zipfile` из Python и
программой `zip` от Info-ZIP. Свой писатель в тестах проверял бы читателя
его же ошибками.

Содержимое каждого файла выводится из его пути в архиве одним правилом —
`content()` ниже; то же правило записано в `test/library/
zip_reader_test.dart`. Так тест сверяет разом и имя (кодировку), и байты.

Запуск (нужна программа `zip` от Info-ZIP):

    python3 tool/make_zip_fixtures.py

Скрипт перезаписывает файлы целиком и детерминирован: повторный запуск не
должен давать diff. Исключение одно — `encrypted_infozip.zip`: шифрование
подмешивает случайные байты, поэтому готовый архив не перезаписывается.
"""

from __future__ import annotations

import io
import os
import shutil
import struct
import subprocess
import tempfile
import zipfile
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "test" / "fixtures" / "zip"

# Время у всех записей одно: иначе архив менялся бы от запуска к запуску.
STAMP = (2026, 10, 4, 12, 0, 0)
EPOCH = 1791115200  # 2026-10-04 12:00:00 UTC

BOOKS = [
    "01 Анатомия/01 Анатомия человека, т. 1.pdf",
    "01 Анатомия/02 Атлас.pdf",
    "02 Физиология/Нормальная физиология.pdf",
    "Латинский язык.pdf",
]


def content(path: str) -> bytes:
    """Содержимое файла архива: выводится из его пути."""
    return ("%PDF-1.4\n" + (path + "\n") * 40).encode("utf-8")


def info(path: str, method: int) -> zipfile.ZipInfo:
    item = zipfile.ZipInfo(path, STAMP)
    item.compress_type = method
    item.external_attr = 0o644 << 16
    return item


class Cp866Info(zipfile.ZipInfo):
    """Запись, имя которой пишется в 866-й кодовой странице без признака
    UTF-8 — так пишут имена «Проводник» и 7-Zip на русской Windows."""

    def _encodeFilenameFlags(self):
        # `zipfile` ставит признак UTF-8 сам, как только видит не-ASCII
        # имя; здесь он снимается.
        return self.filename.encode("cp866"), self.flag_bits & ~0x800


def cp866_info(path: str, method: int) -> zipfile.ZipInfo:
    item = Cp866Info(path, STAMP)
    item.compress_type = method
    item.external_attr = 0o644 << 16
    return item


class Pipe(io.RawIOBase):
    """Поток, по которому нельзя перескакивать: `zipfile` пишет в такой
    записи с описателем данных после содержимого."""

    def __init__(self) -> None:
        self.data = bytearray()

    def writable(self) -> bool:
        return True

    def write(self, chunk) -> int:
        self.data += bytes(chunk)
        return len(chunk)


def shelf_stored() -> bytes:
    """Полка без сжатия, имена в UTF-8 с признаком, записи-папки."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for folder in ("01 Анатомия/", "02 Физиология/"):
            archive.writestr(info(folder, zipfile.ZIP_STORED), b"")
        for path in BOOKS:
            archive.writestr(info(path, zipfile.ZIP_STORED), content(path))
    return buffer.getvalue()


CP866 = [
    "Латинский язык.pdf",
    "Thumbs.db",
    "02 Физиология/Нормальная физиология.pdf",
    "Заметки.txt",
    "01 Анатомия/02 Атлас.pdf",
    "__MACOSX/._Латинский язык.pdf",
    "01 Анатомия/01 Анатомия человека, т. 1.pdf",
    ".DS_Store",
    "01 Анатомия/обложка.JPG",
]


def shelf_deflate_cp866() -> bytes:
    """Та же полка в Deflate, имена в 866-й странице, записи вразнобой,
    рядом не-PDF и служебные файлы систем."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for path in CP866:
            archive.writestr(
                cp866_info(path, zipfile.ZIP_DEFLATED),
                content(path),
                compresslevel=6,
            )
    return buffer.getvalue()


def descriptor() -> bytes:
    """Архив, записанный в поток: длины и суммы стоят после данных."""
    pipe = Pipe()
    with zipfile.ZipFile(pipe, "w") as archive:
        for path in BOOKS[:2]:
            with archive.open(info(path, zipfile.ZIP_DEFLATED), "w") as entry:
                entry.write(content(path))
    return bytes(pipe.data)


def zip64_python() -> bytes:
    """ZIP64 от Python: пределы занижены, и `zipfile` пишет «длинные»
    поля оглавления и запись ZIP64 так, как писал бы у архива больше
    4 ГБ."""
    limit = zipfile.ZIP64_LIMIT
    count = zipfile.ZIP_FILECOUNT_LIMIT
    zipfile.ZIP64_LIMIT = 1
    zipfile.ZIP_FILECOUNT_LIMIT = 1
    try:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", allowZip64=True) as archive:
            for path in BOOKS:
                archive.writestr(
                    info(path, zipfile.ZIP_DEFLATED),
                    content(path),
                    compresslevel=6,
                )
        return buffer.getvalue()
    finally:
        zipfile.ZIP64_LIMIT = limit
        zipfile.ZIP_FILECOUNT_LIMIT = count


def bzip2() -> bytes:
    """Сжатие, которого читатель не понимает."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for path in BOOKS[:2]:
            archive.writestr(info(path, zipfile.ZIP_BZIP2), content(path))
    return buffer.getvalue()


def unicode_extra() -> bytes:
    """Имя в Юникоде рядом с обычным — так пишет WinRAR.

    У первой записи поле верное: имя берётся из него. У второй сумма
    обычного имени не сходится — поле относится к другому имени и
    не принимается.
    """

    def field(plain: str, real: str, crc: int | None = None) -> bytes:
        name = real.encode("utf-8")
        if crc is None:
            crc = zlib.crc32(plain.encode("ascii"))
        body = struct.pack("<BL", 1, crc) + name
        return struct.pack("<HH", 0x7075, len(body)) + body

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        first = info("Anatomiya.pdf", zipfile.ZIP_STORED)
        first.extra = field("Anatomiya.pdf", "Анатомия.pdf")
        archive.writestr(first, content("Анатомия.pdf"))
        second = info("Atlas.pdf", zipfile.ZIP_STORED)
        second.extra = field("Atlas.pdf", "Атлас.pdf", crc=0x12345678)
        archive.writestr(second, content("Atlas.pdf"))
    return buffer.getvalue()


def backslash() -> bytes:
    """Папки разделены обратной чертой — так пишут некоторые архиваторы
    Windows. Содержимое выведено из пути с прямой чертой."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(
            info("Папка\\Книга.pdf", zipfile.ZIP_STORED),
            content("Папка/Книга.pdf"),
        )
    return buffer.getvalue()


def twins() -> bytes:
    """Одна и та же книга в двух папках: один раз без сжатия, второй —
    в Deflate. Содержимое у обеих выведено из одного пути."""
    same = content("Анатомия.pdf")
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(info("Блок 1/Анатомия.pdf", zipfile.ZIP_STORED), same)
        archive.writestr(
            info("Блок 2/Анатомия.pdf", zipfile.ZIP_DEFLATED),
            same,
            compresslevel=6,
        )
        path = "Блок 2/Гистология.pdf"
        archive.writestr(info(path, zipfile.ZIP_STORED), content(path))
    return buffer.getvalue()


def empty() -> bytes:
    """Архив без единой записи."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w"):
        pass
    return buffer.getvalue()


def bad_crc(stored: bytes) -> bytes:
    """Полка без сжатия, в которой испорчен один байт второй книги."""
    marker = content(BOOKS[1])
    at = stored.index(marker) + len(marker) // 2
    broken = bytearray(stored)
    broken[at] ^= 0x20
    return bytes(broken)


def infozip(paths: list[str], *options: str) -> bytes:
    """Архив от программы `zip` (Info-ZIP) — другая реализация."""
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        for path in paths:
            file = root / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(content(path))
            os.utime(file, (EPOCH, EPOCH))
        target = root.parent / (root.name + ".zip")
        environment = dict(os.environ, TZ="UTC", LANG="C.UTF-8")
        # `-X` — без полей владельца и времени: они свои на каждой машине.
        # `-D` — без записей-папок: у них время создания, а не наше.
        subprocess.run(
            ["zip", "-q", "-X", "-D", *options, str(target), *paths],
            cwd=root,
            env=environment,
            check=True,
        )
        try:
            return target.read_bytes()
        finally:
            target.unlink()


WRAPPED = [
    "Литература/2 Биохимия/Биохимия.pdf",
    "Литература/10 Гистология/Гистология.pdf",
    "Литература/1 Анатомия/Атласы/Синельников.pdf",
    "Литература/1 Анатомия/Анатомия.pdf",
    "Литература/Словарь.pdf",
    "Литература/список.docx",
]


def check(
    name: str,
    data: bytes,
    paths: dict[str, str],
    legacy: str = "utf-8",
) -> None:
    """Сверяет архив второй реализацией: `zipfile` читает его и находит
    в нём ровно те файлы и то содержимое, которых ждут тесты.

    [legacy] — кодировка имён без признака UTF-8: Info-ZIP пишет такие в
    UTF-8, русская Windows — в 866-й странице; сам `zipfile` читает их
    как 437-ю.
    """
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        assert archive.testzip() is None, name
        files = [item for item in archive.infolist() if not item.is_dir()]
        assert len(files) == len(paths), (name, len(files), len(paths))
        for item in files:
            raw = item.orig_filename
            if not item.flag_bits & 0x800:
                raw = raw.encode("cp437").decode(legacy)
            assert raw in paths, (name, raw)
            assert archive.read(item) == content(paths[raw]), (name, raw)


def main() -> None:
    if shutil.which("zip") is None:
        raise SystemExit("нужна программа zip (Info-ZIP)")
    OUT.mkdir(parents=True, exist_ok=True)

    stored = shelf_stored()
    same = {path: path for path in BOOKS}
    archives: dict[str, bytes] = {
        "shelf_stored.zip": stored,
        "shelf_deflate_cp866.zip": shelf_deflate_cp866(),
        "descriptor_python.zip": descriptor(),
        "zip64_python.zip": zip64_python(),
        "zip64_infozip.zip": infozip(BOOKS, "-fz"),
        "wrapped_infozip.zip": infozip(WRAPPED),
        "encrypted_infozip.zip": infozip(BOOKS[:2], "-P", "memoria"),
        "bzip2_python.zip": bzip2(),
        "unicode_extra.zip": unicode_extra(),
        "backslash.zip": backslash(),
        "twins_python.zip": twins(),
        "empty.zip": empty(),
        "truncated.zip": stored[: len(stored) * 6 // 10],
        "bad_crc.zip": bad_crc(stored),
        "not_a_zip.zip": b"This is not a zip archive.\n" * 4,
    }

    check("shelf_stored.zip", archives["shelf_stored.zip"], same)
    check(
        "shelf_deflate_cp866.zip",
        archives["shelf_deflate_cp866.zip"],
        {path: path for path in CP866},
        legacy="cp866",
    )
    check("zip64_python.zip", archives["zip64_python.zip"], same)
    check("zip64_infozip.zip", archives["zip64_infozip.zip"], same)
    check(
        "descriptor_python.zip",
        archives["descriptor_python.zip"],
        {path: path for path in BOOKS[:2]},
    )
    check(
        "wrapped_infozip.zip",
        archives["wrapped_infozip.zip"],
        {path: path for path in WRAPPED},
    )
    check(
        "bzip2_python.zip",
        archives["bzip2_python.zip"],
        {path: path for path in BOOKS[:2]},
    )

    for name, data in archives.items():
        target = OUT / name
        # Шифрование Info-ZIP подмешивает случайные байты: такой архив
        # от запуска к запуску разный, поэтому готовый не перезаписывается.
        if name == "encrypted_infozip.zip" and target.exists():
            print(f"{name}: оставлен как есть")
            continue
        target.write_bytes(data)
        print(f"{name}: {len(data)} байт")


if __name__ == "__main__":
    main()
