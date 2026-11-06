"""Стенд «Галактики» (S62): OCR краевых страниц, где нет текстового слоя или он сломан (ALG-MAP-21).

Что делает. Для каждой книги набора смотрит её края в кэше (`extract_edges.py`). Страница
непригодна, если на ней меньше 20 слов (скан без слоя) или словарных слов меньше половины даже
после починки кодировки (сломанный слой). Книга идёт в OCR, если непригодна хотя бы половина её
краевых страниц (скан, сломанный слой) или если по слою у неё не нашлось ни оглавления, ни кода
каталога; распознаются только её непригодные страницы. Пустые и рисованные страницы обычных
книг (форзац, иллюстрации атласа) так в OCR не попадают. Такие страницы рисуются в PNG 200 dpi
(`<кэш>/ocr/<fp>/<номер>.png`) и распознаются встроенным OCR Windows двумя движками — ru и en-US
(`ocr.ps1`). Остаётся тот текст, у которого больше доля словарных слов (RS-09: русский движок
портит латиницу, английский — кириллицу). Итог — `<кэш>/ocr/<fp>/<номер>.txt`, его читает
`passport.py`.

Порядок, как в бюджете чтения: сперва первые 12 и последние 6 краевых страниц; остальные краевые —
только если после первого прохода у книги нет ни оглавления, ни кода каталога.

PDF открывается по пути из набора — это работа стенда; в паспорт путь не попадает.

Запуск: python tool/galaxy_bench/ocr_edges.py <набор.csv> <кэш>
"""
import csv
import json
import os
import subprocess
import sys
import time

import fitz

import passport
from probe_library import WORD, dictionary_share

fitz.TOOLS.mupdf_display_errors(False)
HERE = os.path.dirname(os.path.abspath(__file__))
DPI = 200
MIN_WORDS = 20
MIN_SHARE = 0.5
FIRST_PASS_HEAD, FIRST_PASS_TAIL = 12, 6
ENGINES = (('ru', 'ru'), ('en-US', 'en'))


def share(text):
    """Доля словарных слов текста в его языке (по преобладающему алфавиту)."""
    ws = [w.lower() for w in WORD.findall(text)[:3000]]
    ru = [w for w in ws if w[0] >= 'а' or w[0] == 'ё']
    en = [w for w in ws if w[0] < 'а' and w[0] != 'ё']
    best = ru if len(ru) >= len(en) else en
    return dictionary_share(best, 'ru' if best is ru else 'en'), len(ws)


def needs_ocr(text):
    """Нужен ли OCR странице: слоя нет (мало слов) или он сломан (мало словарных слов)."""
    fixed, _ = passport.fix_encoding(text)
    ratio, count = share(fixed)
    return count < MIN_WORDS or ratio < MIN_SHARE


def run_engines(folder):
    """Распознаёт все ещё не распознанные PNG папки обоими движками; секунды работы."""
    started = time.time()
    for engine, _ in ENGINES:
        subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                        os.path.join(HERE, 'ocr.ps1'), '-Dir', folder, '-Lang', engine],
                       check=True, capture_output=True)
    return time.time() - started


def choose(folder, number):
    """Текст страницы от движка с большей долей словарных слов."""
    best, best_share = '', -1.0
    for engine, _ in ENGINES:
        path = os.path.join(folder, f'{number}.{engine}.txt')
        if not os.path.exists(path):
            continue
        text = open(path, encoding='utf-8-sig').read()
        ratio, count = share(text)
        score = ratio if count >= 5 else -0.5
        if score > best_share:
            best, best_share = text, score
    return best


def render(doc, numbers, folder):
    for number in numbers:
        png = os.path.join(folder, f'{number}.png')
        if not os.path.exists(png):
            doc[number - 1].get_pixmap(dpi=DPI).save(png)


def has_passport(cache, fp):
    record = json.load(open(os.path.join(cache, 'края', fp + '.json'), encoding='utf-8'))
    p = passport.build(record, passport.load_ocr(cache, fp))
    return bool(p['toc'] or p['codes'] or p['subjects'])


def main(set_path, cache):
    rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    log = []
    for r in rows:
        fp = r['fp']
        record = json.load(open(os.path.join(cache, 'края', fp + '.json'), encoding='utf-8'))
        numbers = sorted(int(k) for k in record['text'])
        todo = [n for n in numbers if needs_ocr(record['text'][str(n)])]
        unusable = len(todo) >= 0.5 * len(numbers)
        if not todo or not (unusable or not has_passport(cache, fp)):
            continue
        folder = os.path.join(cache, 'ocr', fp)
        os.makedirs(folder, exist_ok=True)
        head, tail = numbers[:FIRST_PASS_HEAD], numbers[-FIRST_PASS_TAIL:]
        passes = [[n for n in todo if n in head or n in tail]]
        passes.append([n for n in todo if n not in passes[0]])
        seconds, done = 0.0, []
        doc = fitz.open(r['path'])
        for i, batch in enumerate(passes):
            if not batch or (i > 0 and has_passport(cache, fp)):
                continue
            render(doc, batch, folder)
            seconds += run_engines(folder)
            for number in batch:
                open(os.path.join(folder, f'{number}.txt'), 'w', encoding='utf-8').write(choose(folder, number))
            done += batch
        doc.close()
        log.append((r['n'], len(done), round(seconds, 1), has_passport(cache, fp)))
        print(f'№ {r["n"]}: OCR {len(done)} стр., {seconds:.1f} с, паспорт {"есть" if log[-1][3] else "нет"}', flush=True)
    print('книг с OCR', len(log), '· страниц', sum(x[1] for x in log), '· секунд', round(sum(x[2] for x in log)))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
