"""Стенд «Галактики» (S61): опись библиотеки — какие книги есть и какого они качества.

Что делает. Обходит папки категорий библиотеки, у каждого PDF смотрит только края
(первые 25 и последние 15 страниц): язык (доля кириллицы и латиницы), качество
текстового слоя (доля слов из частотного словаря wordfreq), число страниц,
закладки, метаданные. Пишет CSV — из него `select_set.py` выбирает набор проверки.

Папка книги здесь — только эталон для отбора и проверки; в расчёт сортировки
она не попадает (D-050).

Запуск: python tool/galaxy_bench/probe_library.py D:/ <выход.csv>
"""
import csv
import hashlib
import os
import re
import sys
import time

import fitz  # PyMuPDF — только для стенда на ПК, в приложение не идёт
from wordfreq import zipf_frequency

fitz.TOOLS.mupdf_display_errors(False)

# Папки-категории библиотеки владельца; служебные (_ОТКАТ, _TR, Тестирование СНО …) не берутся.
CATEGORIES = [
    'Анатомия', 'Медицина', 'Языки', 'Нейрофизиология СНО2026', 'Айти', 'Биология',
    'Физиология', 'Гистология', 'Химия', 'Биохимия', 'Саморазвитие', 'Патология',
    'Здоровье', 'Фармакология', 'История', 'Философия', 'Нутрициология',
]
FIRST, LAST = 25, 15
WORD = re.compile(r'[A-Za-zА-Яа-яЁё]{3,}')


def fingerprint(path):
    """Быстрый отпечаток файла: размер + SHA-256 первого и последнего мегабайта."""
    size = os.path.getsize(path)
    h = hashlib.sha256(str(size).encode())
    with open(path, 'rb') as f:
        h.update(f.read(1 << 20))
        if size > 2 << 20:
            f.seek(-(1 << 20), 2)
            h.update(f.read(1 << 20))
    return h.hexdigest()[:16]


def dictionary_share(words, lang):
    """Доля слов, которые есть в частотном словаре языка."""
    if not words:
        return 0.0
    return sum(1 for w in words if zipf_frequency(w, lang) > 1.5) / len(words)


def probe(path):
    """Признаки краёв одной книги."""
    row = dict(pages=-1, edge_chars=0, cyr=0, lat=0, ru_ok=0.0, en_ok=0.0, outline=0, meta_title='')
    try:
        doc = fitz.open(path)
    except Exception:
        return row
    n = doc.page_count
    row['pages'] = n
    row['outline'] = len(doc.get_toc(simple=True))
    row['meta_title'] = ((doc.metadata or {}).get('title') or '').strip()[:120]
    pages = list(range(min(FIRST, n))) + list(range(max(FIRST, n - LAST), n))
    text = ' '.join(doc[i].get_text() for i in pages)
    row['edge_chars'] = len(text)
    row['cyr'] = len(re.findall('[а-яёА-ЯЁ]', text))
    row['lat'] = len(re.findall('[a-zA-Z]', text))
    words = [w.lower() for w in WORD.findall(text)[:4000]]
    row['ru_ok'] = round(dictionary_share([w for w in words if re.match('[а-яё]', w)], 'ru'), 3)
    row['en_ok'] = round(dictionary_share([w for w in words if re.match('[a-z]', w)], 'en'), 3)
    return row


def main(root, out_path):
    fields = ['fp', 'category', 'path', 'mb', 'pages', 'edge_chars', 'cyr', 'lat',
              'ru_ok', 'en_ok', 'outline', 'meta_title', 'sec']
    with open(out_path, 'w', encoding='utf-8', newline='') as out:
        w = csv.DictWriter(out, fieldnames=fields)
        w.writeheader()
        for cat in CATEGORIES:
            files = []
            for base, _, names in os.walk(os.path.join(root, cat)):
                files += [os.path.join(base, x) for x in names if x.lower().endswith('.pdf')]
            for path in sorted(files):
                t0 = time.time()
                row = probe(path)
                row.update(fp=fingerprint(path), category=cat, path=path,
                           mb=round(os.path.getsize(path) / 1e6, 1), sec=round(time.time() - t0, 2))
                w.writerow(row)
            print(cat, len(files), flush=True)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
