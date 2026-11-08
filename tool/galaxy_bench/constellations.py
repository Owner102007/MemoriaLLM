"""Стенд «Галактики» (S68): созвездия внутри тем каркаса (ALG-MAP-26).

Что это. Второй уровень карты. Тема каркаса (`taxonomy.py`, первый уровень — S64–S67) делится
на созвездия с именами по-русски: «Анатомия» → «Миология», «Нейроанатомия», «Анатомические атласы»…
Созвездия считаются по всей библиотеке (набор стенда + книги библиотеки), а меряются на наборе —
мерка 7 «Разделы» в `bench.py`.

Как устроено (по образцу ALG-GAL-04 из проекта владельца WaLLE, `wiki/build_galaxy.py`, D-053; RS-11).
1. Словарь `constellations.json`: на тему — список созвездий {name, seeds — начала слов, w — вес}.
2. Очки книги для каждого созвездия: совпадения начал слов в названии ×3, в предметных рубриках ×2,
   в выходных данных ×1 (без шаблона об авторском праве), в оглавлении ×0,3; на созвездие и поле — не больше 3 совпадений
   (длинное оглавление не «перекричит» название); итог × вес созвездия.
   Считается в целых числах (веса × 10): на телефоне и ПК — одно и то же (правило карты, RS-01).
3. Книга получает созвездие с наибольшими очками, если очков ≥ 1 (в целых — ≥ 100).
4. Книга без совпадений — к созвездию 8 самых похожих книг той же темы (косинус TF-IDF паспортов).
5. Созвездие меньше порога распускается — по одному, самое мелкое, и раскладка
   пересчитывается: его книги уходят ко второму по очкам созвездию или к соседям.
   Порог — доля темы, по умолчанию «5%» (S68 и4), или число книг, как 6 в WaLLE: в WaLLE 7760 книг, а у нас
   в теме бывает 50 — порог 6 распускает в ней всё, кроме одного созвездия (см. `threshold`).
Тема без списка в словаре — одно созвездие с именем темы.

Кто зовёт. Запускается после `universal.py` (нужны его темы книг); результат — `bench.py`.

Запуск (из папки MemoriaLLM):
  python tool/galaxy_bench/constellations.py <набор.csv> <обучение-все.csv> <кэш стенда> <прогон тем> <папка вывода> [порог: 5% или 6] [словарь|-] [вес оглавления, десятые]
  (словарь «-» — без словаря: одно созвездие на тему, нулевая линия; прогон тем — папка `universal.py` с `результат-У-смело.csv` и `библиотека-У-смело.csv`)
"""
import collections
import csv
import json
import os
import re
import sys

import numpy as np

import taxonomy as T
import variants as V

HERE = os.path.dirname(os.path.abspath(__file__))
DICTIONARY = os.path.join(HERE, 'constellations.json')
MIN_SIZE = 6        # меньше книг — созвездие на карту не выходит (как в WaLLE)
SHARE = '5%'        # порог по умолчанию (S68 и4): доля темы, от 2 до MIN_SIZE книг
NEIGHBOURS = 8      # сколько похожих книг голосуют за созвездие книги без совпадений
MAX_HITS = 3        # совпадений на поле и созвездие не больше
FIELD_WEIGHTS = [('title', 30), ('subjects', 20), ('imprint', 10), ('toc', 3)]  # × 10: 3; 2; 1; 0,3 (как в WaLLE)
ENOUGH = 100        # очков хватает (1,0 в дробях): веса полей и созвездий — в десятых
TOKEN = re.compile(r'[0-9a-zß-ɏа-я]+')  # латиница с умлаутами и «ß», кириллица
FIELD_CHARS = 1500  # из выходных данных и оглавления — только начало (там всё главное)
# S68 и5: шаблон об авторском праве есть почти в каждой книге — «This work is subject to copyright…
# laws…», «Все права защищены…». Он не о теме книги, но слово «law» тянуло хирургию в «Этику и право».
BOILERPLATE = re.compile(r'copyright|©|rights|trademark|publisher|permission|liabilit|warrant'
                         r'|права защищены|авторск|законом|разрешения|воспроизвед', re.I)
SENTENCE = re.compile(r'(?<=[.!?;])\s+(?=[A-ZА-ЯЁ0-9«"(])')  # «etc. does not…» — не конец предложения


def load_dictionary(path=DICTIONARY):
    """Словарь созвездий → {тема: [созвездия]}; служебные ключи «_…» — пояснения для правки."""
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    return {k: v for k, v in d.items() if not k.startswith('_')}


def words(text):
    """Строчные слова без «ё» (как в словаре): «Ёмкость сердца» → ['емкость', 'сердца']."""
    return TOKEN.findall(text.lower().replace('ё', 'е'))


def without_boilerplate(text):
    """Текст выходных данных без предложений об авторском праве, правах и издателе (S68 и5)."""
    return ' '.join(x for x in SENTENCE.split(text) if not BOILERPLATE.search(x))


def fields_of(p):
    """Поля паспорта книги в порядке FIELD_WEIGHTS."""
    return {'title': p.get('title') or '',
            'subjects': ' '.join(p.get('subjects') or []),
            'imprint': ' '.join([v for v in (p.get('meta') or {}).values() if v]
                                + [without_boilerplate(p.get('imprint_text') or '')[:FIELD_CHARS]]),
            'toc': (p.get('toc') or '')[:FIELD_CHARS]}


class Index:
    """Начала слов всех созвездий темы → номера созвездий; фразы из двух слов — отдельным списком.

    Так книга сверяется со всеми созвездиями за один проход по своим словам (приём WaLLE `topic_index`).
    """

    def __init__(self, items):
        self.prefix, self.phrases, lengths = collections.defaultdict(list), [], set()
        for i, c in enumerate(items):
            for seed in c['seeds']:
                parts = seed.lower().replace('ё', 'е').split()
                if len(parts) == 1:
                    self.prefix[parts[0]].append(i)
                    lengths.add(len(parts[0]))
                else:
                    self.phrases.append((parts[0], parts[1], i))
        self.lengths = sorted(lengths)
        self.weights = [round(10 * c.get('w', 1.0)) for c in items]  # вес в десятых: 0,3 → 3

    def scores(self, p):
        """Очки книги для каждого созвездия (целые; 100 = «хватает»)."""
        total = [0] * len(self.weights)
        f = fields_of(p)
        for name, weight in FIELD_WEIGHTS:
            toks = words(f[name])
            hits = collections.Counter()
            for w in toks:
                seen = set()  # одно слово — одно совпадение на созвездие
                for n in self.lengths:
                    if n > len(w):
                        break
                    for i in self.prefix.get(w[:n], ()):
                        if i not in seen:
                            seen.add(i)
                            hits[i] += 1
            for a, b in zip(toks, toks[1:]):
                for p0, p1, i in self.phrases:
                    if a.startswith(p0) and b.startswith(p1):
                        hits[i] += 1
            for i, h in hits.items():
                total[i] += weight * min(h, MAX_HITS) * self.weights[i]
        return total


def threshold(rule, n):
    """Порог роспуска для темы из n книг. rule — число книг (6) или доля темы («4%»).

    Доля — не меньше 2 книг (созвездие из одной книги — не созвездие) и не больше MIN_SIZE.
    Целые числа: 4 % от 51 книги → (51 × 4 + 50) // 100 = 2.
    """
    rule = str(rule)
    if not rule.endswith('%'):
        return int(rule)
    return max(2, min(MIN_SIZE, (n * int(rule[:-1]) + 50) // 100))


def assign(fps, passports, items, vectors, min_size=MIN_SIZE):
    """Книги одной темы → {fp: (номер созвездия, откуда)}.

    fps — книги темы в постоянном порядке (по отпечатку), vectors — их строки TF-IDF (норма 1).
    откуда: «слова» — по очкам словаря, «соседи» — по похожим книгам.
    """
    index = Index(items)
    S = [index.scores(passports[f]) for f in fps]
    alive = set(range(len(items)))
    while True:
        label = [-1] * len(fps)
        for j in range(len(fps)):
            best, top = -1, ENOUGH - 1
            for i in sorted(alive):
                if S[j][i] > top:
                    best, top = i, S[j][i]
            label[j] = best
        known = [j for j in range(len(fps)) if label[j] >= 0]
        how = ['слова' if label[j] >= 0 else 'соседи' for j in range(len(fps))]
        if known:
            sims = (vectors[[j for j in range(len(fps)) if label[j] < 0]] @ vectors[known].T)
            sims = sims.toarray() if hasattr(sims, 'toarray') else np.asarray(sims)
            for row, j in zip(sims, [j for j in range(len(fps)) if label[j] < 0]):
                top = np.argsort(-row, kind='stable')[:NEIGHBOURS]
                votes = collections.Counter(label[known[q]] for q in top)
                label[j] = max(votes, key=lambda i: (votes[i], -i))
        else:
            label = [min(alive)] * len(fps)
        size = collections.Counter(label)
        small = [i for i in alive if size.get(i, 0) < min_size]
        if not small or len(alive) <= 1:
            break
        alive.discard(min(small, key=lambda i: (size.get(i, 0), i)))  # самое мелкое — и пересчёт
    return {f: (label[j], how[j]) for j, f in enumerate(fps)}


def constellations(topics, passports, dictionary, min_size=SHARE):
    """{fp: тема каркаса или None} → {fp: (имя созвездия или '', откуда)}."""
    by_topic = collections.defaultdict(list)
    for f in sorted(topics):
        if topics[f]:
            by_topic[topics[f]].append(f)
    texts = {f: V.passport_text(passports[f]) for f in sorted(topics)}
    # векторы нужны только темам со словарём (соседи книг без совпадений)
    vec = V.tfidf(list(texts.values()), []) if any(dictionary.get(t) for t in by_topic) else None
    out = {f: ('', 'нет темы') for f in topics if not topics[f]}
    for topic, fps in sorted(by_topic.items()):
        items = dictionary.get(topic) or []
        if not items:
            out.update({f: (T.TOPICS[topic][1], 'тема') for f in fps})
            continue
        X = vec.transform([texts[f] for f in fps])
        for f, (i, how) in assign(fps, passports, items, X, threshold(min_size, len(fps))).items():
            out[f] = (items[i]['name'], how)
    return out


def read_topics(path):
    return {r['fp']: r['тема каркаса'] or None for r in csv.DictReader(open(path, encoding='utf-8'))}


def report(out_path, topics, cons, passports, in_set):
    """Список созвездий для владельца: тема → созвездие → книг (из них в наборе), примеры названий."""
    groups = collections.defaultdict(list)
    for f, (name, _) in cons.items():
        if topics[f]:
            groups[(topics[f], name)].append(f)
    sizes = collections.Counter(topics[f] for f in cons if topics[f])
    L = ['# Созвездия внутри тем — вся библиотека', '',
         f'Книг: {len(cons)}, тем: {len(sizes)}, созвездий: {len(groups)}.', '',
         '| Тема | Созвездие | Книг | Из них в наборе | Примеры названий |', '|---|---|---|---|---|']
    for (topic, name), fs in sorted(groups.items(), key=lambda kv: (-sizes[kv[0][0]], kv[0][0], -len(kv[1]), kv[0][1])):
        sample = '; '.join((passports[f]['title'] or '—')[:50] for f in fs[:3])
        L.append(f'| {T.TOPICS[topic][1]} | {name} | {len(fs)} | {sum(f in in_set for f in fs)} | {sample} |')
    open(out_path, 'w', encoding='utf-8').write('\n'.join(L) + '\n')


def main(set_path, lib_path, cache, topics_dir, out, min_size=SHARE, dictionary=DICTIONARY, toc=''):
    if toc and toc != '-':  # S68 и2: вес оглавления (в десятых), по умолчанию — как в WaLLE
        FIELD_WEIGHTS[-1] = ('toc', int(toc))
    os.makedirs(out, exist_ok=True)
    set_rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    lib_rows = list(csv.DictReader(open(lib_path, encoding='utf-8')))
    passports = V.load_passports(set_rows, cache, os.path.join(cache, 'паспорт'), True)
    passports.update(V.load_passports(lib_rows, cache, os.path.join(cache, 'паспорт-обучение'), False))
    topics = read_topics(os.path.join(topics_dir, 'результат-У-смело.csv'))
    in_set = set(topics)
    topics.update(read_topics(os.path.join(topics_dir, 'библиотека-У-смело.csv')))
    topics = {f: t for f, t in topics.items() if f in passports}
    cons = constellations(topics, passports, {} if dictionary == '-' else load_dictionary(dictionary), min_size)
    # результат для bench.py: группа (тема идеала) — как у universal.py, плюс созвездие
    rows = list(csv.DictReader(open(os.path.join(topics_dir, 'результат-У-смело.csv'), encoding='utf-8')))
    with open(os.path.join(out, 'результат-С.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['fp', 'группа', 'имя', 'тема каркаса', 'созвездие', 'откуда созвездие'])
        for r in rows:
            name, how = cons.get(r['fp'], ('', 'нет паспорта'))
            key = f'{r["тема каркаса"]}: {name}' if name else ''
            w.writerow([r['fp'], r['группа'], r['имя'], r['тема каркаса'], key, how])
    with open(os.path.join(out, 'созвездия.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['fp', 'набор', 'тема каркаса', 'созвездие', 'откуда'])
        for fp in sorted(cons):
            w.writerow([fp, 'да' if fp in in_set else 'нет', topics[fp] or '', *cons[fp]])
    report(os.path.join(out, 'созвездия.md'), topics, cons, passports, in_set)
    how = collections.Counter(h for _, h in cons.values())
    print(f'книг {len(cons)}, созвездий {len({(topics[f], n) for f, (n, _) in cons.items() if n})}; откуда: {dict(how)}')


if __name__ == '__main__':
    main(*sys.argv[1:9])
