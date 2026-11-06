"""Стенд «Галактики» (S61): выбор набора проверки — 100 книг, один раз и навсегда.

Правило (детерминированно, без случайности — порядок книг по отпечатку файла):
- 12 крупных категорий по 8 книг, 4 редкие темы по 1 книге (D-050, план цикла);
- внутри категории сперва берутся трудные книги: сканы без слоя (до 2), сломанный
  слой (до 1), шумное OCR (до 2); затем книги второго языка категории (до 2), тонкая
  (≤ 150 стр.) и толстая (> 800 стр.) книги; остаток — по порядку отпечатков;
- один и тот же файл в двух папках (тот же отпечаток) берётся один раз.
Сканов в библиотеке 17 (10 — в «Анатомии»): все в набор из 8 книг на категорию не
входят; оставшиеся идут в проверку устойчивости (+10 книг вне набора, S66).
Выход — набор.csv: номер, отпечаток, папка (только эталон), путь, язык, качество, страниц.

Запуск: python tool/galaxy_bench/select_set.py <опись.csv> <набор.csv>
"""
import csv
import sys

BIG = ['Анатомия', 'Медицина', 'Языки', 'Нейрофизиология СНО2026', 'Айти', 'Биология',
       'Физиология', 'Гистология', 'Химия', 'Биохимия', 'Саморазвитие', 'Патология']
RARE = ['Фармакология', 'История', 'Здоровье', 'Философия']
PER_BIG = 8


def quality(r):
    """Качество текста краёв: скан / сломанный / шумный / чистый."""
    if int(r['edge_chars']) < 2000:
        return 'скан'
    ok = float(r['ru_ok'] if language(r) == 'ru' else r['en_ok'])
    return 'чистый' if ok >= 0.85 else ('шумный' if ok >= 0.5 else 'сломанный')


def language(r):
    """Язык краёв: ru, en или «?» (букв меньше 500)."""
    cyr, lat = int(r['cyr']), int(r['lat'])
    if cyr + lat < 500:
        return '?'
    return 'ru' if cyr >= lat else 'en'


def pick_category(rows):
    """Восемь книг одной категории по правилу из шапки файла."""
    rows = sorted(rows, key=lambda r: r['fp'])
    chosen = []

    def take(pred, limit):
        for r in rows:
            if len(chosen) >= PER_BIG or limit <= 0:
                return
            if r not in chosen and pred(r):
                chosen.append(r)
                limit -= 1

    take(lambda r: quality(r) == 'скан', 2)
    take(lambda r: quality(r) == 'сломанный', 1)
    take(lambda r: quality(r) == 'шумный', 2)
    langs = [language(r) for r in rows if language(r) in ('ru', 'en')]
    if langs:
        minor = 'en' if langs.count('ru') >= langs.count('en') else 'ru'
        have = sum(1 for r in chosen if language(r) == minor)
        take(lambda r: language(r) == minor, max(0, 2 - have))
    if not any(int(r['pages']) <= 150 for r in chosen):
        take(lambda r: int(r['pages']) <= 150, 1)
    if not any(int(r['pages']) > 800 for r in chosen):
        take(lambda r: int(r['pages']) > 800, 1)
    take(lambda r: True, PER_BIG)
    return chosen


def main(src, dst):
    # Дубль решается по пути, а не по порядку строк: иначе набор зависел бы от обхода папок.
    rows, seen = [], set()
    for r in sorted(csv.DictReader(open(src, encoding='utf-8')), key=lambda r: (r['fp'], r['path'])):
        if int(r['pages']) > 0 and r['fp'] not in seen:
            seen.add(r['fp'])
            rows.append(r)
    by = {}
    for r in rows:
        by.setdefault(r['category'], []).append(r)
    out = []
    for cat in BIG:
        out += pick_category(by.get(cat, []))
    for cat in RARE:
        out += sorted(by.get(cat, []), key=lambda r: r['fp'])[:1]
    with open(dst, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['n', 'fp', 'folder', 'path', 'lang', 'quality', 'pages'])
        for i, r in enumerate(out, 1):
            w.writerow([i, r['fp'], r['category'], r['path'], language(r), quality(r), r['pages']])
    print(len(out), 'книг в наборе')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
