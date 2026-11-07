"""Стенд «Галактики» (S64): универсальная схема — темы каркаса по открытым каталогам библиотек
(ALG-MAP-24, D-052).

Что делает.
1. Учит линейный классификатор «текст → тема каркаса» на `обучение.tsv` (`catalogs.py`):
   основы слов (первые 6 букв, как в S63) → TF-IDF → LinearSVC с уравненными весами тем.
   10 % записей (по хэшу) отложены — на них подбирается порог «без темы», книги владельца
   при обучении и подборе не видны.
2. Раскладывает книги по паспорту: есть однозначный код каталога — тема по коду (`taxonomy`),
   нет — ответ классификатора; перевес лучшей темы над второй меньше порога — «без темы».
3. Меряет: набор стенда против идеала (`bench.py`, тема каркаса → тема идеала по
   `taxonomy.IDEAL`, объявлено до прогона) и 780 книг библиотеки вне набора — против их папок
   (папки здесь — только проверка, D-052).

Запуск (из папки MemoriaLLM):
  python tool/galaxy_bench/universal.py <обучение.tsv> <набор.csv> <обучение-все.csv> <кэш стенда> <папка вывода> [+код|-] [выходные,указатель]
  (+код — дополнить обучение книгами библиотеки с кодом каталога; тогда проверка на библиотеке
  неполная: книги с кодом сами были в обучении — меряется только набор стенда)
"""
import collections
import csv
import hashlib
import json
import os
import sys
import time

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.svm import LinearSVC

import taxonomy as T
import variants as V
import concepts as C

csv.field_size_limit(10 ** 7)
MARGINS = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.8]
TARGET_PRECISION = 0.9  # осторожный порог: на отложенных записях верных ≥ 90 % из решённых
# S65: «выходные» — страница выходных данных (итерация 1, оставлена: 79 → 81 «верно + допустимо»);
# «указатель» — предметный указатель (итерация 2, откат: роста нет). По умолчанию — «выходные».
DEFAULT_PARTS = 'выходные'
PARTS = set()
# S66: «понятия» — метки понятий MeSH из Wikidata в признаках классификатора (итерация 1, `concepts.py`);
# «голос» — понятия голосуют за тему по веткам MeSH, когда перевес классификатора < VOTE_BELOW (итерация 2).
CONCEPTS = None
VOTER = None
VOTE_BELOW = 0.3


def prep(text):
    """Текст для классификатора: с метками понятий, если они включены (S66)."""
    return CONCEPTS.annotate(text) if CONCEPTS else text


def analyzer():
    return C.analyzer if CONCEPTS else V.stems


def passport_words(p):
    """Текст паспорта без кодов каталога: коды решаются отдельно и точнее (taxonomy)."""
    parts = [p['title']] * 2 + [v for v in p['meta'].values() if v] + p['subjects']
    parts.append(' '.join(p['toc'].split()[:V.TOC_WORDS]))
    # S65: доп. части паспорта по одной — каждую меряет отдельный прогон
    if 'выходные' in PARTS:
        parts.append(p.get('imprint_text', ''))  # аннотация, гриф, издательство
    if 'указатель' in PARTS:
        parts.append(p.get('index', ''))  # термины предметного указателя
    return prep('\n'.join(x for x in parts if x))


def load_training(path):
    rows = list(csv.DictReader(open(path, encoding='utf-8'), delimiter='\t'))
    # Отложить ≈ 10 % по КОНЦУ хэша: записи отбирались по его началу (наименьшие — раньше),
    # и деление по началу отложило бы почти все отобранные записи (ошибка первой пробы S64).
    held = [r for r in rows if int(r['хэш'][-2:], 16) < 26]
    train = [r for r in rows if int(r['хэш'][-2:], 16) >= 26]
    return train, held


def fit(train):
    vec = TfidfVectorizer(analyzer=analyzer(), sublinear_tf=True, min_df=3, max_df=0.3, norm='l2')
    X = vec.fit_transform([prep(r['текст']) for r in train])
    model = LinearSVC(C=0.5, class_weight='balanced', random_state=0).fit(X, [r['тема'] for r in train])
    return vec, model


def decide(vec, model, texts, margin):
    """Тема и перевес для каждого текста; перевес < margin — None («без темы»)."""
    scores = model.decision_function(vec.transform(texts))
    out = []
    for s in scores:
        order = np.argsort(-s)
        gap = float(s[order[0]] - s[order[1]])
        out.append((model.classes_[order[0]] if gap >= margin else None, gap))
    return out


def pick_margin(vec, model, held):
    """Наименьший порог, при котором на отложенных записях верных ≥ TARGET_PRECISION из решённых."""
    answers = decide(vec, model, [prep(r['текст']) for r in held], 0.0)
    table = []
    for m in MARGINS:
        done = [(a, r['тема']) for (a, g), r in zip(answers, held) if g >= m]
        prec = sum(a == t for a, t in done) / max(1, len(done))
        table.append((m, round(prec, 3), round(len(done) / len(held), 3)))
    chosen = next((m for m, p, _ in table if p >= TARGET_PRECISION), MARGINS[-1])
    return chosen, table


def classify_books(vec, model, passports, margin):
    """{fp: (тема каркаса или None, откуда: код / слова / нет)}."""
    fps = sorted(passports)
    answers = decide(vec, model, [passport_words(passports[f]) for f in fps], margin)
    out = {}
    for f, (topic, gap) in zip(fps, answers):
        by_code = T.topic_of_codes(passports[f]['codes'])
        if by_code:
            out[f] = (by_code, 'код')
            continue
        if VOTER and gap < VOTE_BELOW:  # S66: классификатор не уверен — голос понятий по веткам MeSH
            by_concepts = C.vote(VOTER.marks(passport_words(passports[f])))
            if by_concepts:
                out[f] = (by_concepts, 'понятия')
                continue
        out[f] = (topic, 'слова') if topic else (None, 'нет')
    return out


def write_result(path, decided):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['fp', 'группа', 'имя', 'тема каркаса', 'откуда'])
        for fp, (topic, how) in sorted(decided.items()):
            group = T.ideal_of(topic) if topic else '-1'
            w.writerow([fp, group, T.TOPICS[topic][1] if topic else '', topic or '', how])


def library_check(decided, rows):
    """780 книг вне набора против папок: верно, соседняя, неверно, без темы."""
    tally = collections.Counter()
    for r in rows:
        if r['fp'] not in decided:
            continue
        folder = V.TOPIC.get(r['category'], r['category'])
        topic, _ = decided[r['fp']]
        if topic is None:
            tally['без темы'] += 1
            continue
        got = T.ideal_of(topic)
        near = V.NEIGHBOURS.get(folder, '').split(';')
        tally['верно' if got == folder else ('соседняя' if got in near else 'неверно')] += 1
    return tally


def coded_library_rows(set_rows, lib_rows, set_pp, lib_pp):
    """Книги библиотеки с однозначным кодом каталога как обучающие записи (вариант «У+код»).

    Ярлык — из кода внутри книги, не из папки (D-052). Книги набора и тома той же работы
    (то же начало названия или почти тот же паспорт, `variants.training_rows`) не берутся.
    """
    cand = [r for r in lib_rows if r['fp'] in lib_pp and T.topic_of_codes(lib_pp[r['fp']]['codes'])]
    titles = {f: p['title'] for f, p in {**set_pp, **lib_pp}.items()}
    c_text = [V.passport_text(lib_pp[r['fp']]) for r in cand]
    s_text = [V.passport_text(set_pp[r['fp']]) for r in set_rows]
    vec = V.tfidf(c_text, s_text)
    kept, _ = V.training_rows(cand, set_rows, titles, V.near_pairs(vec.transform(c_text), vec.transform(s_text)))
    return [dict(источник='библиотека-код', язык=lib_pp[r['fp']]['language'], тема=T.topic_of_codes(lib_pp[r['fp']]['codes']),
                 текст=passport_words(lib_pp[r['fp']]), хэш='ff') for r in kept]


def main(train_path, set_path, lib_path, cache, out, with_library='', parts=''):
    os.makedirs(out, exist_ok=True)
    PARTS.update(x for x in (parts or DEFAULT_PARTS).split(',') if x and x != '-')  # «-» — без доп. частей
    global CONCEPTS, VOTER
    if {'понятия', 'голос'} & PARTS:  # таблица понятий лежит рядом с обучающими записями: <каталоги>/wikidata/mesh.tsv
        table = C.Concepts.load(os.path.join(os.path.dirname(train_path), 'wikidata', 'mesh.tsv'))
        CONCEPTS = table if 'понятия' in PARTS else None
        VOTER = table if 'голос' in PARTS else None
        print(f'понятий в таблице: {len(table.table)} цепочек', flush=True)
    started = time.time()
    train, held = load_training(train_path)
    set_rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    lib_rows = list(csv.DictReader(open(lib_path, encoding='utf-8')))
    set_pp = V.load_passports(set_rows, cache, os.path.join(cache, 'паспорт'), True)
    lib_pp = V.load_passports(lib_rows, cache, os.path.join(cache, 'паспорт-обучение'), False)
    if with_library and with_library != '-':
        extra = coded_library_rows(set_rows, lib_rows, set_pp, lib_pp)
        train += extra
        print(f'+ книг библиотеки с кодом: {len(extra)}', flush=True)
    vec, model = fit(train)
    margin, table = pick_margin(vec, model, held)
    held_acc = table[0][1]
    print(f'обучение: записей {len(train)}, отложено {len(held)}, слов {len(vec.vocabulary_)}, '
          f'тем {len(model.classes_)}; на отложенных верно {held_acc}; порог {margin}; '
          f'{time.time() - started:.0f} с', flush=True)
    log = {'записей': len(train), 'отложено': len(held), 'слов': len(vec.vocabulary_),
           'отложенные: порог → точность, доля решённых': table, 'порог': margin,
           'по источникам': dict(collections.Counter(r['источник'] for r in train)),
           'по языкам': dict(collections.Counter(r['язык'] for r in train))}
    for name, m in (('смело', 0.0), ('осторожно', margin)):
        decided = classify_books(vec, model, set_pp, m)
        write_result(os.path.join(out, f'результат-У-{name}.csv'), decided)
        lib = library_check(classify_books(vec, model, {r['fp']: lib_pp[r['fp']] for r in lib_rows if r['fp'] in lib_pp}, m), lib_rows)
        log[f'библиотека {name}'] = dict(lib)
        print(name, 'библиотека:', dict(lib), flush=True)
    json.dump(log, open(os.path.join(out, 'настройки.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:8])
