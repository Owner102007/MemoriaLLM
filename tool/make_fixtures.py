#!/usr/bin/env python3
"""Генератор корпуса проблемных PDF для тестов (`test/fixtures`).

Корпус собран не из «красивых» файлов, а из тех, на которых читалки ломаются:
скан без текстового слоя, CJK и RTL, битый xref, тысяча с лишним страниц,
двухколоночная вёрстка, шифрование, мусор с расширением .pdf.

Файлы собираются программой, а не качаются из интернета: так они
воспроизводимы, свободны от чужих прав, весят десятки килобайт и в них нет
ничего, кроме того, что нужно тесту. Ожидания тестов описаны рядом —
в `test/fixtures/README.md` и в `test/pdf_corpus_test.dart`.

Запуск (нужен pikepdf; проверка результата — pypdfium2):

    pip install pikepdf pypdfium2
    python3 tool/make_fixtures.py

Скрипт перезаписывает файлы целиком и детерминирован: повторный запуск не
должен давать diff, иначе корпус будет шуметь в истории.
"""

from __future__ import annotations

import os
import zlib
from pathlib import Path

import pikepdf
from pikepdf import Array, Dictionary, Name, Pdf, Stream, String

OUT = Path(__file__).resolve().parent.parent / "test" / "fixtures"

# Дата фиксированная: иначе каждый прогон менял бы файлы и корпус шумел бы
# в истории репозитория.
FIXED_DATE = String("D:20260807120000Z")


def new_pdf() -> Pdf:
    pdf = Pdf.new()
    pdf.docinfo["/CreationDate"] = FIXED_DATE
    pdf.docinfo["/ModDate"] = FIXED_DATE
    pdf.docinfo["/Producer"] = String("Memoria LLM HB fixtures")
    return pdf


def save(pdf: Pdf, name: str, **kwargs) -> None:
    path = OUT / name
    pdf.save(
        path,
        deterministic_id=True,
        compress_streams=True,
        **kwargs,
    )
    print(f"  {name}: {path.stat().st_size / 1024:.1f} КБ")


def content(pdf: Pdf, text: str) -> Stream:
    return Stream(pdf, text.encode("latin-1"))


def simple_font(pdf: Pdf, base: str = "Helvetica") -> Dictionary:
    return pdf.make_indirect(
        Dictionary(
            Type=Name.Font,
            Subtype=Name.Type1,
            BaseFont=Name(f"/{base}"),
            Encoding=Name.WinAnsiEncoding,
        )
    )


def add_page(
    pdf: Pdf,
    stream: Stream,
    resources: Dictionary,
    width: float = 595,
    height: float = 842,
    rotate: int | None = None,
) -> None:
    page = Dictionary(
        Type=Name.Page,
        MediaBox=Array([0, 0, width, height]),
        Contents=stream,
        Resources=resources,
    )
    if rotate is not None:
        page[Name.Rotate] = rotate
    pdf.pages.append(pikepdf.Page(pdf.make_indirect(page)))


# --------------------------------------------------------------------------
# 1. Обычная книга с текстом и плоским оглавлением
# --------------------------------------------------------------------------


def make_basic_text() -> None:
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))

    for i in range(1, 9):
        body = (
            "BT /F1 24 Tf 72 760 Td (Memoria page {n}) Tj ET\n"
            "BT /F1 12 Tf 72 700 Td "
            "(The quick brown fox jumps over the lazy dog.) Tj ET\n"
            "BT /F1 12 Tf 72 680 Td (Marker{n} unique-token-{n}) Tj ET\n"
        ).format(n=i)
        add_page(pdf, content(pdf, body), resources)

    # Плоское оглавление из трёх пунктов.
    with pdf.open_outline() as outline:
        for title, page_index in (
            ("Chapter One", 0),
            ("Chapter Two", 3),
            ("Chapter Three", 6),
        ):
            outline.root.append(
                pikepdf.OutlineItem(title, page_index, "Fit"),
            )

    pdf.docinfo["/Title"] = String("Memoria Basic Text")
    pdf.docinfo["/Author"] = String("Memoria Fixtures")
    save(pdf, "basic_text.pdf")


# --------------------------------------------------------------------------
# 2. Вложенное оглавление в три уровня
# --------------------------------------------------------------------------


def make_outline_nested() -> None:
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))

    for i in range(1, 13):
        body = "BT /F1 20 Tf 72 700 Td (Section page {n}) Tj ET\n".format(n=i)
        add_page(pdf, content(pdf, body), resources)

    with pdf.open_outline() as outline:
        part_one = pikepdf.OutlineItem("Part I", 0, "Fit")
        chapter = pikepdf.OutlineItem("Chapter 1", 1, "Fit")
        chapter.children.append(pikepdf.OutlineItem("Section 1.1", 2, "Fit"))
        chapter.children.append(pikepdf.OutlineItem("Section 1.2", 3, "Fit"))
        part_one.children.append(chapter)
        part_one.children.append(pikepdf.OutlineItem("Chapter 2", 4, "Fit"))

        part_two = pikepdf.OutlineItem("Part II", 6, "Fit")
        part_two.children.append(pikepdf.OutlineItem("Chapter 3", 7, "Fit"))

        outline.root.append(part_one)
        outline.root.append(part_two)

    pdf.docinfo["/Title"] = String("Memoria Nested Outline")
    save(pdf, "outline_nested.pdf")


# --------------------------------------------------------------------------
# 3. Двухколоночная статья
# --------------------------------------------------------------------------


def make_two_columns() -> None:
    """Две колонки с известными координатами.

    Левая колонка занимает x ≈ 60…280, правая ≈ 320…540. На этом файле S4
    будет проверять определение колонок, а S3 — что порядок извлечённого
    текста осмысленный.
    """
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))

    for page_no in range(1, 5):
        parts = [
            "BT /F1 16 Tf 60 790 Td (Two column article {n}) Tj ET\n".format(
                n=page_no
            )
        ]
        for line in range(20):
            y = 740 - line * 24
            parts.append(
                "BT /F1 11 Tf 60 {y} Td (Left column line {l} of page {n}) Tj ET\n"
                .format(y=y, l=line, n=page_no)
            )
            parts.append(
                "BT /F1 11 Tf 320 {y} Td (Right column line {l} of page {n}) Tj ET\n"
                .format(y=y, l=line, n=page_no)
            )
        add_page(pdf, content(pdf, "".join(parts)), resources)

    pdf.docinfo["/Title"] = String("Memoria Two Columns")
    save(pdf, "two_columns.pdf")


# --------------------------------------------------------------------------
# 4. Скан без текстового слоя
# --------------------------------------------------------------------------


def scan_image_bytes(width: int, height: int, page_no: int) -> bytes:
    """Серое изображение с «строками текста» — чёрными полосами."""
    rows = []
    for y in range(height):
        row = bytearray([0xF2] * width)  # чуть сероватая бумага
        line_index = (y - 20) // 18
        if 0 <= line_index < 12 and 4 <= (y - 20) % 18 <= 12:
            length = 20 + ((line_index * 7 + page_no * 3) % (width - 40))
            for x in range(15, 15 + length):
                row[x] = 0x20
        rows.append(bytes(row))
    return b"".join(rows)


def make_scan_no_text() -> None:
    pdf = new_pdf()
    width, height = 240, 340

    pages = []
    for page_no in (1, 2):
        raw = scan_image_bytes(width, height, page_no)
        image = Stream(pdf, zlib.compress(raw, 9))
        image[Name.Type] = Name.XObject
        image[Name.Subtype] = Name.Image
        image[Name.Width] = width
        image[Name.Height] = height
        image[Name.ColorSpace] = Name.DeviceGray
        image[Name.BitsPerComponent] = 8
        image[Name.Filter] = Name.FlateDecode
        pages.append(pdf.make_indirect(image))

    for image in pages:
        resources = Dictionary(XObject=Dictionary(Im0=image))
        body = "q 595 0 0 842 0 0 cm /Im0 Do Q\n"
        add_page(pdf, content(pdf, body), resources)

    pdf.docinfo["/Title"] = String("Memoria Scan Without Text Layer")
    save(pdf, "scan_no_text.pdf")


# --------------------------------------------------------------------------
# 5 и 6. CJK и RTL через Type0 + Identity-H + ToUnicode
# --------------------------------------------------------------------------


def to_unicode_cmap(pdf: Pdf, chars: str) -> Stream:
    """CMap, сопоставляющая CID (начиная с 1) кодовым точкам [chars].

    Именно по ToUnicode PDFium извлекает текст, поэтому файл проверяет
    извлечение независимо от того, есть ли в системе подходящий шрифт.
    """
    lines = [
        "/CIDInit /ProcSet findresource begin",
        "12 dict begin",
        "begincmap",
        "/CMapName /Memoria-Identity-UCS def",
        "/CMapType 2 def",
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
        "1 begincodespacerange",
        "<0000> <FFFF>",
        "endcodespacerange",
    ]
    entries = []
    for index, char in enumerate(chars, start=1):
        entries.append(f"<{index:04X}> <{ord(char):04X}>")
    for start in range(0, len(entries), 100):
        chunk = entries[start : start + 100]
        lines.append(f"{len(chunk)} beginbfchar")
        lines.extend(chunk)
        lines.append("endbfchar")
    lines += ["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"]
    return pdf.make_indirect(Stream(pdf, "\n".join(lines).encode("ascii")))


def type0_font(pdf: Pdf, name: str, chars: str) -> Dictionary:
    """Type0-шрифт без встроенной программы шрифта.

    Файл шрифта не встраивается намеренно: он весил бы мегабайты, а тесту
    нужен разбор кодировки и ToUnicode, а не качество глифов. PDFium при
    рендере подставит системный шрифт или нарисует пусто — падать он
    не должен, это и проверяется.
    """
    descriptor = pdf.make_indirect(
        Dictionary(
            Type=Name.FontDescriptor,
            FontName=Name(f"/{name}"),
            Flags=4,
            FontBBox=Array([0, -200, 1000, 900]),
            ItalicAngle=0,
            Ascent=900,
            Descent=-200,
            CapHeight=700,
            StemV=80,
        )
    )
    cid_font = pdf.make_indirect(
        Dictionary(
            Type=Name.Font,
            Subtype=Name.CIDFontType0,
            BaseFont=Name(f"/{name}"),
            CIDSystemInfo=Dictionary(
                Registry=String("Adobe"),
                Ordering=String("Identity"),
                Supplement=0,
            ),
            FontDescriptor=descriptor,
            DW=1000,
        )
    )
    return pdf.make_indirect(
        Dictionary(
            Type=Name.Font,
            Subtype=Name.Type0,
            BaseFont=Name(f"/{name}"),
            Encoding=Name("/Identity-H"),
            DescendantFonts=Array([cid_font]),
            ToUnicode=to_unicode_cmap(pdf, chars),
        )
    )


def cid_string(chars: str, text: str) -> str:
    """Строка вида <00010002> — CID'ы символов [text] по таблице [chars]."""
    return "<" + "".join(f"{chars.index(ch) + 1:04X}" for ch in text) + ">"


def make_script_fixture(
    filename: str,
    title: str,
    font_name: str,
    lines: list[str],
) -> None:
    chars = "".join(dict.fromkeys("".join(lines)))
    pdf = new_pdf()
    font = type0_font(pdf, font_name, chars)
    resources = Dictionary(Font=Dictionary(F1=font))

    parts = []
    for index, line in enumerate(lines):
        y = 760 - index * 40
        parts.append(
            "BT /F1 22 Tf 72 {y} Td {s} Tj ET\n".format(
                y=y, s=cid_string(chars, line)
            )
        )
    add_page(pdf, content(pdf, "".join(parts)), resources)

    pdf.docinfo["/Title"] = String(title)
    save(pdf, filename)


def make_cjk() -> None:
    make_script_fixture(
        "cjk.pdf",
        "Memoria CJK",
        "MemoriaCJK",
        ["日本語のテキスト", "中文文本示例", "한국어 텍스트"],
    )


def make_rtl() -> None:
    make_script_fixture(
        "rtl.pdf",
        "Memoria RTL",
        "MemoriaRTL",
        ["العربية", "עברית", "مرحبا بالعالم"],
    )


# --------------------------------------------------------------------------
# 7. Повороты страниц
# --------------------------------------------------------------------------


def make_rotated_pages() -> None:
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))
    for rotate in (0, 90, 180, 270):
        body = "BT /F1 28 Tf 72 700 Td (Rotate {r}) Tj ET\n".format(r=rotate)
        add_page(pdf, content(pdf, body), resources, rotate=rotate)
    pdf.docinfo["/Title"] = String("Memoria Rotated Pages")
    save(pdf, "rotated_pages.pdf")


# --------------------------------------------------------------------------
# 8. Разные размеры страниц в одном файле
# --------------------------------------------------------------------------


def make_mixed_page_sizes() -> None:
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))
    sizes = [
        (595, 842),  # A4 портрет
        (842, 595),  # A4 альбом
        (420, 595),  # A5
        (200, 200),  # крошечная квадратная
    ]
    for index, (width, height) in enumerate(sizes, start=1):
        body = "BT /F1 14 Tf 20 {y} Td (Size page {n}) Tj ET\n".format(
            y=height - 40, n=index
        )
        add_page(pdf, content(pdf, body), resources, width=width, height=height)
    pdf.docinfo["/Title"] = String("Memoria Mixed Page Sizes")
    save(pdf, "mixed_page_sizes.pdf")


# --------------------------------------------------------------------------
# 9. Очень большой документ
# --------------------------------------------------------------------------


def make_huge() -> None:
    """1200 страниц с общим потоком содержимого.

    Один поток на все страницы делает файл маленьким, но для читалки
    документ остаётся настоящим: 1200 объектов страниц, длинное дерево
    страниц, долгий разбор.
    """
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = pdf.make_indirect(Dictionary(Font=Dictionary(F1=font)))
    shared = pdf.make_indirect(
        content(pdf, "BT /F1 24 Tf 72 700 Td (Long book page) Tj ET\n")
    )
    for _ in range(1200):
        page = pdf.make_indirect(
            Dictionary(
                Type=Name.Page,
                MediaBox=Array([0, 0, 595, 842]),
                Contents=shared,
                Resources=resources,
            )
        )
        pdf.pages.append(pikepdf.Page(page))
    pdf.docinfo["/Title"] = String("Memoria Huge Book")
    save(pdf, "huge_1200_pages.pdf")


# --------------------------------------------------------------------------
# 10. Зашифрованный файл
# --------------------------------------------------------------------------


def make_encrypted() -> None:
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))
    for i in range(1, 4):
        body = "BT /F1 20 Tf 72 700 Td (Secret page {n}) Tj ET\n".format(n=i)
        add_page(pdf, content(pdf, body), resources)
    pdf.docinfo["/Title"] = String("Memoria Encrypted")
    # Детерминированный ID для зашифрованного файла QPDF выдать не может,
    # поэтому здесь единственный файл корпуса, который меняется побайтово
    # от запуска к запуску. Перегенерировать его без нужды не стоит.
    path = OUT / "encrypted.pdf"
    pdf.save(
        path,
        compress_streams=True,
        encryption=pikepdf.Encryption(user="memoria", owner="memoria", R=6),
    )
    print(f"  encrypted.pdf: {path.stat().st_size / 1024:.1f} КБ")


# --------------------------------------------------------------------------
# 11–13. Битые файлы
# --------------------------------------------------------------------------


def make_broken_xref() -> None:
    """Правильное тело, испорченная таблица xref.

    PDFium умеет пересобирать xref и такой файл обычно открывает — тест
    закрепляет именно это: испорченный указатель не должен стоить читателю
    книги.
    """
    pdf = new_pdf()
    font = simple_font(pdf)
    resources = Dictionary(Font=Dictionary(F1=font))
    for i in range(1, 4):
        body = "BT /F1 20 Tf 72 700 Td (Recovered page {n}) Tj ET\n".format(n=i)
        add_page(pdf, content(pdf, body), resources)
    pdf.docinfo["/Title"] = String("Memoria Broken Xref")

    tmp = OUT / "broken_xref.pdf"
    pdf.save(tmp, deterministic_id=True, compress_streams=False)

    data = bytearray(tmp.read_bytes())
    start = data.rfind(b"startxref")
    if start == -1:
        raise RuntimeError("startxref не найден — файл сохранён иначе, чем ожидалось")
    end = data.find(b"%%EOF", start)
    # Смещение подменяется на заведомо неверное: разбор по таблице
    # обязан провалиться, а восстановление — сработать.
    data[start : end] = b"startxref\n999999\n"
    tmp.write_bytes(bytes(data))
    print(f"  broken_xref.pdf: {tmp.stat().st_size / 1024:.1f} КБ")


def make_garbage() -> None:
    path = OUT / "not_a_pdf.pdf"
    # Похоже на PDF заголовком и больше ничем.
    path.write_bytes(b"%PDF-1.7\n" + bytes(range(256)) * 8)
    print(f"  not_a_pdf.pdf: {path.stat().st_size / 1024:.1f} КБ")

    empty = OUT / "empty_file.pdf"
    empty.write_bytes(b"")
    print("  empty_file.pdf: 0.0 КБ")

    truncated = OUT / "truncated.pdf"
    source = (OUT / "basic_text.pdf").read_bytes()
    # Обрубок в половину файла: заголовок на месте, конца нет.
    truncated.write_bytes(source[: len(source) // 2])
    print(f"  truncated.pdf: {truncated.stat().st_size / 1024:.1f} КБ")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Корпус: {OUT}")
    make_basic_text()
    make_outline_nested()
    make_two_columns()
    make_scan_no_text()
    make_cjk()
    make_rtl()
    make_rotated_pages()
    make_mixed_page_sizes()
    make_huge()
    make_encrypted()
    make_broken_xref()
    make_garbage()

    total = sum(
        f.stat().st_size for f in OUT.iterdir() if f.suffix == ".pdf"
    )
    print(f"Итого: {total / 1024:.1f} КБ")


if __name__ == "__main__":
    main()
