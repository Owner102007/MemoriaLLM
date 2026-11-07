"""Стенд «Галактики» (S62): паспорт книги — название, коды каталога, оглавление (ALG-MAP-21).

Зачем. Сортировка не читает книгу целиком (D-050): о теме говорит «паспорт» — что написано
на титуле, какие коды УДК/ББК/LC/NLM стоят на обороте титула и что в оглавлении (RS-09).
Паспорт собирается только из кэша краёв (`extract_edges.py`: первые 25 и последние 15 страниц,
закладки, метаданные, крупные строки титула) и из OCR тех же страниц (`ocr_edges.py`).
Имени файла и пути здесь нет и быть не может — их нет в кэше.

Кто зовёт: прогоны вариантов сортировки (S63) и оракул (S62); в приложение перенос — веха В3.

Запуск: python tool/galaxy_bench/passport.py <набор.csv> <кэш> <папка паспортов> [<сводка.csv>]
"""
import csv
import json
import os
import re
import sys

# --- Починка кодировки -----------------------------------------------------------------
# Русский текст в CP1251, прочитанный как Latin-1: «ÑÎÄÅÐÆÀÍÈÅ» вместо «СОДЕРЖАНИЕ».
# Каждая буква кириллицы стала буквой из диапазона À–ÿ (U+00C0–U+00FF); перекодировка
# назад возвращает текст без OCR (RS-09, опыт на Гайворонском).
_LATIN1_HIGH = re.compile('[À-ÿ]')
_CYRILLIC = re.compile('[Ѐ-ӿ]')
_LETTER = re.compile(r'[^\W\d_]')


def fix_encoding(text):
    """Текст страницы с починенной кодировкой и признак, чинили ли.

    Чинится, только если букв À–ÿ больше 40 % всех букв, а кириллицы почти нет (< 5 %):
    у французского или немецкого текста таких букв несколько процентов.
    """
    letters = len(_LETTER.findall(text))
    if letters < 50:
        return text, False
    high = len(_LATIN1_HIGH.findall(text))
    if high < 0.4 * letters or len(_CYRILLIC.findall(text)) > 0.05 * letters:
        return text, False
    try:
        fixed = text.encode('latin-1', errors='ignore').decode('cp1251', errors='ignore')
    except UnicodeError:
        return text, False
    return fixed, True


# --- Язык ------------------------------------------------------------------------------
def language(text):
    """ru, en или «?» — по доле кириллицы среди букв (не меньше 200 букв)."""
    cyr = len(_CYRILLIC.findall(text))
    lat = len(re.findall('[A-Za-z]', text))
    if cyr + lat < 200:
        return '?'
    return 'ru' if cyr >= lat else 'en'


# --- Коды каталога ---------------------------------------------------------------------
# Оборот титула узнаётся по выходным данным: ISBN, «Library of Congress», УДК, ББК, ©.
_IMPRINT = re.compile(r'ISBN|Library of Congress|Cataloging|УДК|ББК|DNLM|\bNLM\b|©|Copyright', re.I)
_CODES = [
    ('УДК', re.compile(r'УДК\s*:?\s*([0-9][0-9.:()\-–+/=\'"«» ]{1,40})')),
    ('ББК', re.compile(r'ББК\s*:?\s*([0-9][0-9А-Яа-я.()\-–+/ ]{1,30})')),
    # NLM: две буквы класса (QS, QT, QU, QW, QV, QZ, W, WA … WZ) и номер — «QS 517».
    ('NLM', re.compile(r'\b((?:Q[S-Z]|W[A-Z]?)\s?\d{1,3}(?:\.\d+)?)\b(?=[\s.,;\]]|$)')),
    # LC: класс (QH, QM, QP, R, RC …) и номер с точкой автора — «QM551 .J86».
    ('LC', re.compile(r'\b((?:Q[A-R]?|R[A-Z]?|B[A-Z]?|H[A-Z]?|P[A-Z])\s?\d{1,4}(?:\.\d+)?\s?\.[A-Z]\d{1,4})')),
    # DDC: три цифры, точка, цифры и обычно «dc22» рядом — «611'.018—dc23».
    ('DDC', re.compile(r"\b(\d{3}['’]?\.\d{1,6})\s*[-–—]*\s*dc\s?\d{2}", re.I)),
]
# Рубрики CIP: «1. Histology—Atlases. 2. Cells.» или «[DNLM: 1. Histology—Atlases. QS 517]».
_SUBJECT = re.compile(r'(?<![\d.])\b[1-9]\.\s+([A-Z][A-Za-z ,\'()\-]{2,60}?(?:\s?(?:—|--|-)\s?[A-Za-z][A-Za-z ,()\-]{2,40})*)\s?\.')


def catalog_codes(pages):
    """Коды каталога и рубрики с оборота титула: ([[вид, код], …], [рубрика, …], номер страницы)."""
    for number, text in pages:
        if not _IMPRINT.search(text):
            continue
        flat = ' '.join(text.split())
        codes = []
        for kind, pattern in _CODES:
            for m in pattern.finditer(flat):
                value = m.group(1).strip(' .,;:-–')
                if value and [kind, value] not in codes:
                    codes.append([kind, value])
        subjects = []
        for m in _SUBJECT.finditer(flat):
            s = re.sub(r'\s*(—|--)\s*', '—', m.group(1).strip())
            if s not in subjects and not re.match(r'(ISBN|Printed|First|Second|Third)', s):
                subjects.append(s)
        if codes or subjects:
            return codes, subjects, number
    return [], [], None


# --- Название --------------------------------------------------------------------------
_FILE_LIKE = re.compile(r'\.(pdf|docx?|djvu|indd|qxd|tex)\b|^[\w\-]*_\d{2,}|^untitled|^microsoft word', re.I)
_JUNK_TITLE = re.compile(r'^(contents|содержание|оглавление|preface|предисловие|index|copyright|isbn)\b', re.I)


def clean_meta(value):
    """Метаданные PDF без мусора: имя файла внутри Title — не название (иначе подсказка)."""
    value = ' '.join((value or '').split())
    if len(value) < 4 or _FILE_LIKE.search(value):
        return ''
    return value[:200]


def title_from_big(big):
    """Название по крупному шрифту первых страниц.

    Берётся страница из первых пяти с самой крупной строкой, где есть хотя бы 3 буквы,
    и её строки не мельче 70 % этой; не больше 200 знаков.
    """
    best, best_size = None, 0.0
    for number in sorted(big, key=int)[:5]:
        lines = [(size, text) for size, text in big[number] if len(_LETTER.findall(text)) >= 3]
        if lines and lines[0][0] > best_size:
            best, best_size = lines, lines[0][0]
    if not best:
        return ''
    parts = [text for size, text in best if size >= 0.7 * best_size and not _JUNK_TITLE.match(text)]
    return ' '.join(' '.join(parts).split())[:200]


def title_from_text(pages):
    """Запасной способ (скан, OCR): первые содержательные строки первых трёх страниц."""
    for _, text in pages[:3]:
        lines = [ln.strip() for ln in text.splitlines() if len(_LETTER.findall(ln)) >= 4]
        if len(lines) >= 2:
            return ' '.join(lines[:4])[:200]
    return ''


# --- Оглавление ------------------------------------------------------------------------
# Признаки страницы оглавления — по Déjean & Meunier (2009): заголовок, много номеров
# страниц, строки «текст … 123»; предметный указатель отличается строками «термин 12, 45».
_TOC_HEAD = re.compile(r'(оглавлен[иі]е|содержан[иі]е|\bcontents\b|\binhalt(sverzeichnis)?\b|índice|sommaire|spis treści)', re.I)
# Латинские двойники русских букв в заголовке («Cодержание» с латинской C) сводятся к кириллице.
_TWINS = str.maketrans('aceopxyACEOPXYKMHTB', 'асеорхуАСЕОРХУКМНТВ')
_INDEX_LINE = re.compile(r'\d{1,4}\s*[,;–-]\s*\d{1,4}')
_FRONT = re.compile(
    r'^(front cover|cover|cover page|back cover|inside (front|back) cover|ifc|title( page)?|half[- ]title.*|'
    r'copyright.*|dedication|preface.*|foreword.*|acknowledg.*|about (the|this) (authors?|book|editors?)|'
    r'notice|reviewers|contributors|contents|brief contents|detailed contents|table of contents|index.*|'
    r'bibliography|references|glossary|оглавление|содержание|предисловие.*|от автор.*|составители|'
    r'список (авторов|литературы|сокращений)|литература|предметный указатель|\d+|[ivxlc]+)$', re.I)
_NUMBER = re.compile(r'(?<![\d.,])\d{1,4}(?![\d.,])')
MIN_TOC_ITEMS = 5
MAX_TOC_PAGES = 12


def words(text):
    return re.findall(r'[^\W\d_]{3,}', text)


def toc_from_outline(outline):
    """Оглавление из закладок PDF: пункты уровней 1–2 со словами, без служебных."""
    items = [' '.join(t.split()) for level, t in outline if level <= 2]
    items = [t for t in items if t and not _FRONT.match(t.strip(' .')) and words(t)]
    return items if len(items) >= MIN_TOC_ITEMS else []


def _index_like(text):
    lines = [ln for ln in text.splitlines() if re.search(r'\d', ln)]
    return len(lines) > 10 and sum(1 for ln in lines if _INDEX_LINE.search(ln)) > 0.3 * len(lines)


def _is_head_line(line):
    """Строка-заголовок оглавления: «Оглавление», «Table of Contents», «INHALT ARBEITSBUCH» —
    слово заголовка и не больше 4 слов всего (а не фраза «содержание калия в крови …»)."""
    for variant in (line, line.translate(_TWINS)):
        if _TOC_HEAD.search(variant) and len(words(variant)) <= 4:
            return True
    return False


def _head_at(text):
    """Где на странице заголовок оглавления: номер непустой строки (0 — первая; −1 — нет).

    Заголовок ищется в первых 6 непустых строках и в последних 3 (колонтитул внизу:
    «Оглавление 5»); внизу — номер 10**6.
    """
    lines = [ln for ln in text.splitlines() if ln.strip()]
    for i, line in enumerate(lines[:6]):
        if _is_head_line(line):
            return i
    if any(_is_head_line(line) for line in lines[-3:]):
        return 10 ** 6
    return -1


def _headed(text):
    return _head_at(text) >= 0


def _item_lines(text):
    """Строки, похожие на пункты оглавления: 2–20 слов, не длиннее 120 знаков."""
    return [ln for ln in text.splitlines() if 2 <= len(words(ln)) <= 20 and len(ln.strip()) <= 120]


def _toc_start(text):
    """Начало оглавления: заголовок и ≥ 5 номеров страниц — или, у оглавления без номеров
    (электронные книги со ссылками), заголовок в первых двух строках и ≥ 5 строк-пунктов."""
    if _index_like(text):
        return False
    at = _head_at(text)
    if at < 0:
        return False
    if len(_NUMBER.findall(text)) >= 5:
        return True
    return at <= 1 and len(_item_lines(text)) >= MIN_TOC_ITEMS


def toc_from_pages(pages):
    """Оглавление со страниц: первая страница с заголовком «Содержание» и ≥ 5 номерами,
    не похожая на указатель, плюс следующие, пока они похожи на оглавление.

    Возвращает (текст без номеров и отточий, [номера страниц]) или ('', []).
    """
    numbers = [n for n, _ in pages]
    text_of = dict(pages)
    for i, (number, text) in enumerate(pages):
        if not _toc_start(text):
            continue
        numbered = len(_NUMBER.findall(text)) >= 5
        block, used = [text], [number]
        for nxt in numbers[i + 1:]:
            t = text_of[nxt]
            if nxt != used[-1] + 1 or _index_like(t) or len(block) >= MAX_TOC_PAGES:
                break
            # Продолжение: снова заголовок или много номеров; у оглавления без номеров —
            # страница из одних коротких строк-пунктов.
            lines = [ln for ln in t.splitlines() if ln.strip()]
            listy = len(lines) >= 8 and len(_item_lines(t)) >= 0.8 * len(lines)
            if not (_headed(t) or len(_NUMBER.findall(t)) >= 12 or (not numbered and listy)):
                break
            block.append(t)
            used.append(nxt)
        body = re.sub(r'[.·…_]{2,}', ' ', '\n'.join(block))
        body = _NUMBER.sub(' ', body)
        body = '\n'.join(' '.join(ln.split()) for ln in body.splitlines() if words(ln))
        return body, used
    return '', []


# --- Паспорт целиком -------------------------------------------------------------------
def page_texts(record, ocr):
    """Тексты краевых страниц по порядку номеров: слой PDF с починенной кодировкой,
    а где слоя нет или он сломан — OCR той же страницы (если он есть).

    Возвращает ([(номер, текст)], сколько страниц починено, сколько взято из OCR).
    """
    out, fixed, from_ocr = [], 0, 0
    for key in sorted(record['text'], key=int):
        text, was_fixed = fix_encoding(record['text'][key])
        fixed += was_fixed
        if key in ocr:
            text = ocr[key]
            from_ocr += 1
        out.append((int(key), text))
    return out, fixed, from_ocr


# --- Выходные данные и предметный указатель (S65) --------------------------------------------
IMPRINT_WORDS, INDEX_WORDS = 150, 300
_IMPRINT_NOISE = re.compile(r'^(ISBN|©|\(c\)|УДК|ББК|Copyright|All rights reserved|Все права защищены|'
                            r'Printed in|Отпечатано|Подписано в печать|Формат|Тираж|Заказ|www\.|https?:)', re.I)


def imprint_words(pages, imprint):
    """Слова страницы выходных данных — аннотация, гриф, издательство, серия — без кодов,
    ISBN, знака © и типографских строк (тираж, формат). Страница — та, где нашлись коды,
    а без кодов — первая из 12 первых страниц со знаками выходных данных (ISBN, ©).
    Возвращает до IMPRINT_WORDS слов (S65, ALG-MAP-21)."""
    if imprint is None:
        imprint = next((n for n, t in pages[:12] if _IMPRINT.search(t)), None)
    if imprint is None:
        return ''
    text = dict(pages).get(imprint, '')
    kept = [ln for ln in text.splitlines() if ln.strip() and not _IMPRINT_NOISE.match(ln.strip())]
    return ' '.join(' '.join(kept).split()[:IMPRINT_WORDS])


def index_terms(pages, first=25):
    """Термины предметного указателя с последних страниц: «аксон 12, 45» → «аксон».
    Страница указателя — как в `_index_like` (много строк «термин, 12, 45»).
    Возвращает до INDEX_WORDS слов (S65, ALG-MAP-21)."""
    terms = []
    for number, text in pages[first:]:
        if not _index_like(text):
            continue
        for line in text.splitlines():
            term = re.split(r'\d', line, maxsplit=1)[0].strip(' ,;.:–-—')
            if len(term) >= 3 and re.search('[A-Za-zА-Яа-яЁё]{3}', term):
                terms.append(term)
    return ' '.join(' '.join(terms).split()[:INDEX_WORDS])


def build(record, ocr=None):
    """Паспорт одной книги из записи кэша краёв и OCR её страниц ({номер: текст})."""
    ocr = ocr or {}
    pages, fixed, from_ocr = page_texts(record, ocr)
    meta = {k: clean_meta(v) for k, v in record.get('meta', {}).items() if k in ('title', 'subject', 'keywords')}
    title = title_from_big(record.get('big', {})) if not ocr else ''
    title = title or title_from_text(pages)
    codes, subjects, imprint = catalog_codes(pages)
    items = toc_from_outline(record.get('outline', []))
    if items:
        toc, toc_from, toc_pages = '\n'.join(items), 'закладки', []
    else:
        toc, toc_pages = toc_from_pages(pages)
        toc_from = 'страницы' if toc else ''
    all_text = '\n'.join(t for _, t in pages)
    return dict(
        fp=record['fp'], pages=record['pages'], read=len(pages), ocr_pages=from_ocr, fixed_pages=fixed,
        language=language(all_text), title=title, meta=meta, codes=codes, subjects=subjects,
        imprint_page=imprint, toc_from=toc_from, toc_pages=toc_pages, toc=toc, toc_words=len(words(toc)),
        imprint_text=imprint_words(pages, imprint), index=index_terms(pages),
    )


def text_of(passport, max_toc_words=None):
    """Паспорт одним текстом — то, что увидит сортировка (и оракул)."""
    parts = [passport['title']]
    parts += [v for v in passport['meta'].values() if v]
    parts += [f'{k} {v}' for k, v in passport['codes']]
    parts += passport['subjects']
    toc = passport['toc']
    if max_toc_words:
        toc = ' '.join(toc.split()[:max_toc_words])
    parts.append(toc)
    return '\n'.join(p for p in parts if p)


def load_ocr(cache, fp):
    """OCR краевых страниц книги: {номер: текст} из `<кэш>/ocr/<fp>/<номер>.txt`."""
    folder = os.path.join(cache, 'ocr', fp)
    if not os.path.isdir(folder):
        return {}
    return {name[:-4]: open(os.path.join(folder, name), encoding='utf-8').read()
            for name in os.listdir(folder) if name.endswith('.txt') and name[:-4].isdigit()}


def main(set_path, cache, out_dir, summary=None):
    os.makedirs(out_dir, exist_ok=True)
    rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    table = []
    for r in rows:
        record = json.load(open(os.path.join(cache, 'края', r['fp'] + '.json'), encoding='utf-8'))
        p = build(record, load_ocr(cache, r['fp']))
        json.dump(p, open(os.path.join(out_dir, r['fp'] + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        table.append(dict(n=r['n'], fp=r['fp'], read=p['read'], ocr=p['ocr_pages'], fixed=p['fixed_pages'],
                          lang=p['language'], title=p['title'][:80], codes=';'.join(f'{k} {v}' for k, v in p['codes']),
                          subjects=len(p['subjects']), toc_from=p['toc_from'], toc_words=p['toc_words']))
    if summary:
        with open(summary, 'w', encoding='utf-8', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(table[0]))
            w.writeheader()
            w.writerows(table)
    n = len(table)
    toc = sum(1 for t in table if t['toc_from'])
    code = sum(1 for t in table if t['codes'] or t['subjects'])
    either = sum(1 for t in table if t['toc_from'] or t['codes'] or t['subjects'])
    print(f'книг {n}: оглавление {toc}, код или рубрика {code}, оглавление или код {either} '
          f'({100 * either // n} %); OCR страниц {sum(t["ocr"] for t in table)}, '
          f'починено {sum(t["fixed"] for t in table)}; читается до {max(t["read"] for t in table)} стр.')


if __name__ == '__main__':
    main(*sys.argv[1:5])
