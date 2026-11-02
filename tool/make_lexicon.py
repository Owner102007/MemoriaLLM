#!/usr/bin/env python3
"""Срез частотного словаря для доверия текстовому слою (ALG-MAP-19, S58).

Зачем. Доверие тексту скана — доля слов страницы, которые есть в
словаре языка. Пороги τ = 0,25 и доля чистого текста 0,86 подобраны в
шаге 46 исследования СНО2026 (`доверие.py`) на частотных списках
wordfreq: 200 тыс. самых частых форм русского и 100 тыс. английского.
Здесь тот же список кладётся в приложение файлом.

Лицензия. Данные wordfreq — CC BY-SA 4.0 (Robyn Speer и др.; источники:
Google Books Ngrams, SUBTLEX, Википедия, OpenSubtitles и др.). С GPL-3.0
совместима в одну сторону (Creative Commons, 2015). Файл среза остаётся
под CC BY-SA 4.0 — `assets/lexicon/NOTICE` (решение D-047).

Что меняется против исходного списка («изменено» по условиям BY-SA):
остаются только формы, которые вообще могут совпасть со словом страницы
— буквы (`[^\\W\\d_]+`, как у `доверие.py`) не короче трёх знаков;
русский и английский — одним множеством; по кодам знаков; без повторов.
`ё` не сворачивается: приложение, как и `доверие.py`, ищет слово и его
форму с `е`.

Запуск:  pip install wordfreq==3.1.1
         python tool/make_lexicon.py
"""

import gzip
import pathlib
import re

import wordfreq

VERSION = '3.1.1'
RU = 200000
EN = 100000
WORD = re.compile(r'[^\W\d_]+')
MIN_LEN = 3


def main():
    import importlib.metadata
    have = importlib.metadata.version('wordfreq')
    assert have == VERSION, 'нужна wordfreq %s, стоит %s' % (VERSION, have)
    words = set(wordfreq.top_n_list('ru', RU)) | set(
        wordfreq.top_n_list('en', EN)
    )
    kept = sorted(w for w in words if len(w) >= MIN_LEN and WORD.fullmatch(w))
    out = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'lexicon'
    out.mkdir(parents=True, exist_ok=True)
    data = ('\n'.join(kept) + '\n').encode('utf-8')
    # mtime=0 — одинаковые байты при каждом запуске.
    (out / 'words.txt.gz').write_bytes(gzip.compress(data, 9, mtime=0))
    print('форм %d из %d, %.0f КБ сжато' % (
        len(kept), len(words), (out / 'words.txt.gz').stat().st_size / 1024,
    ))


if __name__ == '__main__':
    main()
