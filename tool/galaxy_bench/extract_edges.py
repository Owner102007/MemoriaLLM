"""Стенд «Галактики» (S61): края книги в кэш — то, что вправе читать система (D-050).

Для каждой книги — первые 25 и последние 15 страниц (текст каждой страницы),
закладки PDF, метаданные (Title, Author, Subject, Keywords) и метки страниц.
Имени файла и пути в кэше нет: ключ — отпечаток файла. Кэш — `_данные/стенд/края/<fp>.json`
(вне git: тексты чужих книг). С флагом --all — ещё и весь текст (только для базовой
линии «как сейчас»), `_данные/стенд/полный/<fp>.json`.

Запуск: python tool/galaxy_bench/extract_edges.py <опись-или-набор.csv> <папка кэша> [--all]
"""
import csv
import json
import os
import sys

import fitz

fitz.TOOLS.mupdf_display_errors(False)
FIRST, LAST = 25, 15


def edges(doc):
    n = doc.page_count
    idx = list(range(min(FIRST, n))) + list(range(max(FIRST, n - LAST), n))
    return {str(i + 1): doc[i].get_text() for i in idx}


def main(src, cache, everything):
    os.makedirs(os.path.join(cache, 'края'), exist_ok=True)
    if everything:
        os.makedirs(os.path.join(cache, 'полный'), exist_ok=True)
    rows = list(csv.DictReader(open(src, encoding='utf-8')))
    done = 0
    for r in rows:
        fp = r['fp']
        edge_path = os.path.join(cache, 'края', fp + '.json')
        full_path = os.path.join(cache, 'полный', fp + '.json')
        if os.path.exists(edge_path) and (not everything or os.path.exists(full_path)):
            continue
        try:
            doc = fitz.open(r['path'])
        except Exception as e:
            print('не открылся', fp, e)
            continue
        meta = doc.metadata or {}
        rec = dict(
            fp=fp, pages=doc.page_count,
            meta={k: (meta.get(k) or '') for k in ('title', 'author', 'subject', 'keywords')},
            outline=[[lvl, title] for lvl, title, _ in doc.get_toc(simple=True)],
            labels={str(i + 1): doc[i].get_label() for i in range(min(FIRST, doc.page_count))},
            text=edges(doc),
        )
        json.dump(rec, open(edge_path, 'w', encoding='utf-8'), ensure_ascii=False)
        if everything:
            json.dump(dict(fp=fp, text=[p.get_text() for p in doc]),
                      open(full_path, 'w', encoding='utf-8'), ensure_ascii=False)
        doc.close()  # иначе Windows держит файл занятым
        done += 1
    print('извлечено', done, 'из', len(rows))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], '--all' in sys.argv)
