"""Стенд «Галактики» (S63): соревнование схем сортировки на одних паспортах (ALG-MAP-22).

Что делает. Берёт паспорта книг (`passport.py`, S62) и раскладывает книги набора по группам
разными схемами — вариантами А, Б, В, Г, Е из «Варианты конечной схемы сортировки.md».
Каждый вариант пишет `результат-<вариант>.csv` (fp, группа, имя) — его меряет `bench.py`.

Откуда знания. Книги `D:\\` вне набора — **обучающая часть** (D-050: учиться на них можно,
в том числе по их папкам). Книги набора и тома той же работы в неё не идут (`training_rows`).
Все настройки вариантов (порог скоплений, перевес) подбираются только на обучающих книгах —
на «учебных наборах», собранных как набор стенда (`pseudo_sets`); набор и идеал при подборе
не видны. Иначе схема выучила бы сам набор, а не темы.

Варианты (подробно — заметка ALG-MAP-22):
- А  коды каталога (УДК, ББК, NLM, LC, DDC) → дисциплина по общей таблице; без кода — «без темы».
- В  без учителя: слова паспорта (основы — первые 6 букв) → TF-IDF → скопления (косинус).
- Б  обучение на библиотеке: линейный классификатор слов по папкам обучающих книг;
     Б-ярлык — его ответ как группа (готовый ярлык: нарушает «категории возникают сами»,
     только для сравнения); Б-пространство — вероятности тем как признаки → скопления.
- Г  векторы смысла multilingual-e5-base (MIT, модель уже на ПК): Г-статич — своя таблица
     «токен → вектор» (как Model2Vec: каждый токен через модель по одному), вектор книги —
     взвешенная сумма; Г-e5 — модель целиком по тексту паспорта (не побитово, 1 ГБ — потолок).
- Е  ансамбль: Б-пространство + Г-e5 + коды каталога → скопления;
     Е-ярлык — код каталога, а без кода — Б-ярлык (тоже готовый ярлык).
Д (локальная LLM) здесь нет: нужны разведка RS-10 и загрузка модели — с согласия владельца.

Скопления (`cluster`): агломеративная кластеризация со средней связью по косинусному
расстоянию (1 − косинус) и порогом τ: две группы сливаются, пока среднее расстояние между их
книгами меньше τ. Группы меньше `min_size` книг — «без темы» (−1). Число групп не задаётся —
оно возникает из порога.

Запуск (из папки MemoriaLLM):
  python tool/galaxy_bench/variants.py <набор.csv> <обучение-все.csv> <кэш стенда> <папка вывода> [варианты]
"""
import collections
import csv
import json
import os
import random
import re
import sys
import time

import numpy as np
from sklearn.cluster import AgglomerativeClustering
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

import bench
import passport

HERE = os.path.dirname(os.path.abspath(__file__))
TOC_WORDS = 250
STEM = 6
SEEDS = 10
TAUS = [round(0.02 * i, 2) for i in range(1, 50)]  # 0.02 … 0.98: у разных признаков расстояния разного масштаба
MIN_SIZES = (1, 2, 3)

# Папки библиотеки → имена тем идеала (у папки СНО2026 в имени — служебная приписка).
TOPIC = {'Нейрофизиология СНО2026': 'Нейрофизиология'}
BIG = ['Анатомия', 'Медицина', 'Языки', 'Нейрофизиология', 'Айти', 'Биология',
       'Физиология', 'Гистология', 'Химия', 'Биохимия', 'Саморазвитие', 'Патология']
RARE = ['Фармакология', 'История', 'Здоровье', 'Философия', 'Нутрициология']
# Соседние темы для учебных наборов — те же пары, что в идеале v1 (D-051).
NEIGHBOURS = {
    'Медицина': 'Патология;Здоровье;Фармакология', 'Патология': 'Медицина;Здоровье',
    'Здоровье': 'Медицина;Патология', 'Фармакология': 'Медицина',
    'Нейрофизиология': 'Физиология', 'Физиология': 'Нейрофизиология',
    'Биология': 'Гистология;Биохимия', 'Гистология': 'Биология;Биохимия',
    'Биохимия': 'Биология;Гистология;Химия', 'Химия': 'Биохимия',
    'История': 'Философия', 'Философия': 'История',
}

# --- А: коды каталога → дисциплина -------------------------------------------------------
# Общая таблица классификаций (не папки владельца): самый длинный подходящий префикс кода.
# УДК и DDC — десятичные, ББК — свои индексы, NLM и LC — буквенные классы.
CODE_TABLE = {
    'УДК': [('611.018', 'Гистология'), ('611', 'Анатомия'), ('612.8', 'Нейрофизиология'),
            ('612', 'Физиология'), ('615', 'Фармакология'), ('613', 'Здоровье'),
            ('616', 'Патология'), ('61', 'Медицина'), ('577', 'Биохимия'), ('54', 'Химия'),
            ('57', 'Биология'), ('004', 'Айти'), ('681.3', 'Айти'), ('81', 'Языки'),
            ('159.9', 'Саморазвитие'), ('1', 'Философия'), ('9', 'История')],
    'ББК': [('28.706', 'Анатомия'), ('28.707.3', 'Физиология'), ('28.991', 'Нейрофизиология'),
            ('28.903', 'Физиология'), ('28.05', 'Гистология'), ('28.072', 'Биохимия'),
            ('28.0', 'Биология'), ('28', 'Биология'), ('24', 'Химия'), ('52.8', 'Фармакология'),
            ('52.5', 'Патология'), ('5', 'Медицина'), ('32.97', 'Айти'), ('32.973', 'Айти'),
            ('81', 'Языки'), ('88', 'Саморазвитие'), ('87', 'Философия'), ('63', 'История')],
    'DDC': [('611.018', 'Гистология'), ('611', 'Анатомия'), ('612.8', 'Нейрофизиология'),
            ('612', 'Физиология'), ('615', 'Фармакология'), ('613', 'Здоровье'),
            ('616', 'Патология'), ('61', 'Медицина'), ('572', 'Биохимия'), ('54', 'Химия'),
            ('57', 'Биология'), ('00', 'Айти'), ('4', 'Языки'), ('158', 'Саморазвитие'),
            ('1', 'Философия'), ('9', 'История')],
    'NLM': [('QS 5', 'Гистология'), ('QS', 'Анатомия'), ('QT', 'Физиология'), ('QU', 'Биохимия'),
            ('QV', 'Фармакология'), ('QZ', 'Патология'), ('QH', 'Биология'), ('QD', 'Химия'),
            ('WL', 'Нейрофизиология'), ('WA', 'Здоровье'), ('W', 'Медицина')],
    'LC': [('QM55', 'Гистология'), ('QM', 'Анатомия'), ('QP3', 'Нейрофизиология'),
           ('QP4', 'Нейрофизиология'), ('QP5', 'Биохимия'), ('QP6', 'Биохимия'),
           ('QP', 'Физиология'), ('QH', 'Биология'), ('QD', 'Химия'), ('RB', 'Патология'),
           ('RM', 'Фармакология'), ('RA', 'Здоровье'), ('R', 'Медицина'), ('QA7', 'Айти'),
           ('P', 'Языки'), ('BF', 'Саморазвитие'), ('B', 'Философия'), ('D', 'История')],
}


def code_discipline(codes):
    """Дисциплина по кодам каталога паспорта или '' (коды молчат или спорят).

    Каждый код голосует за дисциплину самого длинного подходящего префикса таблицы;
    побеждает большинство, ничья — ''.
    """
    votes = collections.Counter()
    for kind, value in codes:
        v = value.replace(' ', '')
        table = [(p.replace(' ', ''), d) for p, d in CODE_TABLE.get(kind, [])]
        hits = [(len(p), d) for p, d in table if v.startswith(p)]
        if hits:
            votes[max(hits)[1]] += 1
    if not votes:
        return ''
    top = votes.most_common()
    return top[0][0] if len(top) == 1 or top[0][1] > top[1][1] else ''


# --- общий вход: паспорт → слова ---------------------------------------------------------
WORD = re.compile(r'[A-Za-zÀ-ɏА-Яа-яЁё]{3,}')


def stems(text):
    """Основы слов: строчные, ё → е, первые 6 букв (грубая замена стемминга ru и en)."""
    return [w.lower().replace('ё', 'е')[:STEM] for w in WORD.findall(text)]


def passport_text(p):
    """Текст паспорта для сортировки; название — трижды (оно короче и важнее оглавления)."""
    return '\n'.join([p['title']] * 2 + [passport.text_of(p, max_toc_words=TOC_WORDS)])


# --- обучающая часть без утечки ------------------------------------------------------------
NEAR = 0.5  # косинус паспортов, выше которого две книги считаются одной работой


def title_key(title):
    """Начало названия без цифр и знаков («Атлас анатомии человека. Том 2» → «атласанатомиичеловекатом»)."""
    t = re.sub(r'[^a-zа-я]+', '', title.lower().replace('ё', 'е'))
    return t[:30] if len(t) >= 15 else ''


def near_pairs(X_train, X_set):
    """Обучающие книги, чей паспорт почти совпадает с паспортом книги набора (косинус ≥ NEAR).

    Строки X — векторы TF-IDF с нормой 1, поэтому произведение строк — косинус.
    """
    sim = (X_train @ X_set.T).toarray()
    return {i for i in range(sim.shape[0]) if sim[i].max() >= NEAR}


def training_rows(train_rows, set_rows, titles, near=frozenset()):
    """Обучающие книги: не из набора и не тома той же работы, что книга набора.

    Та же работа — совпало начало названия (`title_key`) или паспорт почти тот же (`near` —
    номера строк train_rows из `near_pairs`). Имена файлов библиотеки не помогают: в них
    только папка и номер («Анатомия_00246.pdf»), и в признаки они не идут.
    """
    set_fp = {r['fp'] for r in set_rows}
    set_title = {title_key(titles.get(r['fp'], '')) for r in set_rows} - {''}
    kept, dropped = [], []
    for i, r in enumerate(train_rows):
        if r['fp'] in set_fp or i in near or title_key(titles.get(r['fp'], '')) in set_title:
            dropped.append(r)
        else:
            kept.append(r)
    return kept, dropped


def work_groups(fps, titles, X):
    """Ключ работы каждой обучающей книги — для деления на части без утечки внутри обучения.

    Книги с одним началом названия или с почти одинаковым паспортом — одна работа
    (связные компоненты); ключ — наименьший отпечаток компоненты.
    """
    parent = list(range(len(fps)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    by_title = {}
    for i, f in enumerate(fps):
        k = title_key(titles.get(f, ''))
        if k:
            if k in by_title:
                parent[root(i)] = root(by_title[k])
            else:
                by_title[k] = i
    sim = (X @ X.T).tocoo()
    for i, j, v in zip(sim.row, sim.col, sim.data):
        if i < j and v >= NEAR:
            parent[root(j)] = root(i)
    comp = collections.defaultdict(list)
    for i in range(len(fps)):
        comp[root(i)].append(fps[i])
    key = {}
    for members in comp.values():
        for f in members:
            key[f] = min(members)
    return [key[f] for f in fps]


def pseudo_sets(rows, seeds=SEEDS):
    """Учебные наборы «как набор стенда»: по 8 книг крупной темы и по 1 — редкой."""
    by = collections.defaultdict(list)
    for r in rows:
        by[r['topic']].append(r['fp'])
    out = []
    for s in range(seeds):
        rnd = random.Random(1000 + s)
        chosen = []
        for t in sorted(by):
            pool = sorted(by[t])
            rnd.shuffle(pool)
            chosen += pool[:8 if t in BIG else 1]
        out.append(chosen)
    return out


def pseudo_ideal(rows):
    return {r['fp']: dict(тема=r['topic'], допустимые=NEIGHBOURS.get(r['topic'], ''),
                          без_темы_ок='да' if r['topic'] in RARE else 'нет') for r in rows}


# --- скопления ------------------------------------------------------------------------------
def cluster(X, tau, min_size=1):
    """Группы книг по косинусному расстоянию: средняя связь, порог τ; мелкие группы → −1."""
    X = np.asarray(X, dtype=np.float64)
    # Пустой паспорт (ни одного слова словаря) — вектор из нулей: косинуса у него нет, «без темы».
    live = [i for i in range(len(X)) if np.linalg.norm(X[i]) > 0]
    labels = [-1] * len(X)
    if len(live) < 2:
        for i in live:
            labels[i] = 0
        return labels if min_size <= 1 else [-1] * len(X)
    found = AgglomerativeClustering(n_clusters=None, distance_threshold=tau, metric='cosine',
                                    linkage='average').fit_predict(X[live])
    size = collections.Counter(found)
    for i, g in zip(live, found):
        labels[i] = int(g) if size[g] >= min_size else -1
    return labels


def judge_sets(vectors_of, ideal, sets, tau, min_size):
    """Средний счёт учебных наборов: верно + допустимо (строго) и ARI."""
    good, aris = 0.0, 0.0
    for fps in sets:
        labels = cluster([vectors_of[f] for f in fps], tau, min_size)
        result = [dict(fp=f, группа=str(g)) for f, g in zip(fps, labels)]
        _, out, _ = bench.score(ideal, result, strict=True)
        good += sum(1 for v in out.values() if v in bench.GOOD) / len(fps)
        aris += bench.ari([ideal[f]['тема'] for f in fps], [str(g) if g != -1 else f'-{f}' for f, g in zip(fps, labels)])
    return good / len(sets), aris / len(sets)


def tune(vectors_of, ideal, sets):
    """Порог и наименьшая группа с лучшим средним счётом на учебных наборах."""
    best = None
    for tau in TAUS:
        for m in MIN_SIZES:
            good, a = judge_sets(vectors_of, ideal, sets, tau, m)
            key = (round(good, 4), round(a, 4))
            if best is None or key > best[0]:
                best = (key, tau, m)
    return dict(tau=best[1], min_size=best[2], train_good=best[0][0], train_ari=best[0][1])


# --- признаки вариантов ---------------------------------------------------------------------
def tfidf(train_texts, all_texts):
    vec = TfidfVectorizer(analyzer=stems, sublinear_tf=True, min_df=2, max_df=0.5, norm='l2')
    vec.fit(train_texts + all_texts)
    return vec


def logistic(X, y):
    """Линейный классификатор тем. Веса тем уравнены (`balanced`): иначе тема с 321 книгой
    из 780 (Анатомия) забирает чужие книги. C = 3 — лучшее на учебных наборах (S63)."""
    return LogisticRegression(C=3.0, class_weight='balanced', max_iter=3000).fit(X, y)


def centred(train, other):
    """Вычесть средний вектор обучающих книг и снова нормировать (у векторов e5 все книги
    «похожи» — косинус любой пары около 0,8; без среднего остаётся то, чем книги различаются)."""
    mean = np.asarray(train).mean(axis=0)
    unit = lambda m: (m - mean) / np.maximum(np.linalg.norm(m - mean, axis=1, keepdims=True), 1e-12)
    return unit(np.asarray(train)), unit(np.asarray(other))


def oof_proba(X, y, groups, folds=5):
    """Вероятности тем для обучающих книг «вне выборки»: книга оценивается моделью,
    обученной без неё и без томов её работы (группы — ключ работы)."""
    keys = sorted(set(groups))
    random.Random(7).shuffle(keys)
    fold_of = {k: i % folds for i, k in enumerate(keys)}
    out = np.zeros((X.shape[0], len(sorted(set(y)))))
    classes = sorted(set(y))
    for f in range(folds):
        test = np.array([fold_of[g] == f for g in groups])
        m = logistic(X[~test], [c for c, t in zip(y, test) if not t])
        p = m.predict_proba(X[test])
        idx = [classes.index(c) for c in m.classes_]
        out[np.ix_(np.where(test)[0], idx)] = p
    return out, classes


def e5_vectors(texts, cache_path):
    """Вектор e5 каждого текста (кэш на диске). Модель — локальная копия, без сети."""
    if os.path.exists(cache_path):
        return np.load(cache_path)
    os.environ.setdefault('HF_HUB_OFFLINE', '1')
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('intfloat/multilingual-e5-base', device='cpu')
    v = model.encode(['passage: ' + t for t in texts], batch_size=16, normalize_embeddings=True,
                     show_progress_bar=False)
    np.save(cache_path, v)
    return v


def static_table(texts, cache_path, dims=256):
    """Своя статическая таблица «токен → вектор» из e5 (приём Model2Vec, MIT — идея).

    Каждый токен словаря паспортов проходит через модель один (<s> токен </s>), вектор —
    среднее выходов; затем главные компоненты (PCA) до `dims`. Вектор книги — сумма строк
    таблицы с весом IDF токена и log(1 + частота) — без модели, одним сложением.
    """
    os.environ.setdefault('HF_HUB_OFFLINE', '1')
    from transformers import AutoModel, AutoTokenizer
    import torch
    tok = AutoTokenizer.from_pretrained('intfloat/multilingual-e5-base')
    ids = [tok(t, add_special_tokens=False, truncation=True, max_length=4096)['input_ids'] for t in texts]
    if os.path.exists(cache_path):
        z = np.load(cache_path)
        vocab, table = list(z['vocab']), z['table']
    else:
        vocab = sorted({i for row in ids for i in row})
        model = AutoModel.from_pretrained('intfloat/multilingual-e5-base').eval()
        rows = []
        with torch.no_grad():
            for s in range(0, len(vocab), 1024):
                batch = torch.tensor([[tok.bos_token_id, i, tok.eos_token_id] for i in vocab[s:s + 1024]])
                rows.append(model(input_ids=batch).last_hidden_state.mean(dim=1).numpy())
        table = np.concatenate(rows)
        table = table - table.mean(axis=0)
        _, _, vt = np.linalg.svd(table, full_matrices=False)
        table = table @ vt[:dims].T
        np.savez(cache_path, vocab=np.array(vocab), table=table)
    where = {t: i for i, t in enumerate(vocab)}
    df = collections.Counter(i for row in ids for i in set(row))
    n = len(texts)
    out = []
    for row in ids:
        c = collections.Counter(row)
        v = np.zeros(table.shape[1])
        for t, k in c.items():
            v += table[where[t]] * np.log(1 + k) * np.log((1 + n) / (1 + df[t]))
        out.append(v / (np.linalg.norm(v) or 1.0))
    return np.array(out)


# --- прогон ---------------------------------------------------------------------------------
def write_result(path, fps, labels, names=None):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['fp', 'группа', 'имя'])
        for fp, g in zip(fps, labels):
            w.writerow([fp, g, (names or {}).get(g, '')])


def load_passports(rows, cache, out_dir, use_ocr):
    """Паспорта книг: готовые из `out_dir` или собранные из кэша краёв (S62)."""
    os.makedirs(out_dir, exist_ok=True)
    got = {}
    for r in rows:
        path = os.path.join(out_dir, r['fp'] + '.json')
        if os.path.exists(path):
            cached = json.load(open(path, encoding='utf-8'))
            if 'index' in cached:  # паспорт S65 (с выходными данными и указателем); старый — пересобрать
                got[r['fp']] = cached
                continue
        edge = os.path.join(cache, 'края', r['fp'] + '.json')
        if not os.path.exists(edge):
            continue
        record = json.load(open(edge, encoding='utf-8'))
        p = passport.build(record, passport.load_ocr(cache, r['fp']) if use_ocr else None)
        json.dump(p, open(path, 'w', encoding='utf-8'), ensure_ascii=False)
        got[r['fp']] = p
    return got


def main(set_path, train_path, cache, out, wanted=None):
    os.makedirs(out, exist_ok=True)
    wanted = set((wanted or 'А,В,Б,Г,Е').split(','))
    set_rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    all_train = list(csv.DictReader(open(train_path, encoding='utf-8')))
    set_pp = load_passports(set_rows, cache, os.path.join(cache, 'паспорт'), use_ocr=True)
    train_pp = load_passports(all_train, cache, os.path.join(cache, 'паспорт-обучение'), use_ocr=False)
    titles = {fp: p['title'] for fp, p in {**set_pp, **train_pp}.items()}
    sfp = [r['fp'] for r in set_rows]
    s_text = [passport_text(set_pp[f]) for f in sfp]
    candidates = [r for r in all_train if r['fp'] in train_pp]
    c_text = [passport_text(train_pp[r['fp']]) for r in candidates]
    vec = tfidf(c_text, s_text)
    Xc, Xs = vec.transform(c_text), vec.transform(s_text)
    kept, dropped = training_rows(candidates, set_rows, titles, near_pairs(Xc, Xs))
    keep_idx = [i for i, r in enumerate(candidates) if r in kept]
    Xt = Xc[keep_idx]
    tfp = [r['fp'] for r in kept]
    t_text = [c_text[i] for i in keep_idx]
    for r, w in zip(kept, work_groups(tfp, titles, Xt)):
        r['topic'] = TOPIC.get(r['category'], r['category'])
        r['work'] = w
    print(f'обучающих книг {len(kept)} ({len(set(r["work"] for r in kept))} работ), '
          f'отсеяно как та же работа или набор {len(dropped)}')
    log = {'обучающих': len(kept), 'работ': len(set(r['work'] for r in kept)), 'отсеяно': len(dropped),
           'по темам': dict(collections.Counter(r['topic'] for r in kept))}
    y = [r['topic'] for r in kept]
    ideal_t = pseudo_ideal(kept)
    sets = pseudo_sets(kept)

    def run(name, s_vec, t_vec, extra=''):
        started = time.time()
        conf = tune(dict(zip(tfp, t_vec)), ideal_t, sets)
        labels = cluster(s_vec, conf['tau'], conf['min_size'])
        write_result(os.path.join(out, f'результат-{name}.csv'), sfp, labels)
        conf['сек'] = round(time.time() - started, 1)
        conf['групп'] = len({g for g in labels if g != -1})
        log[name] = {**conf, 'что': extra}
        print(name, conf, flush=True)

    if 'А' in wanted:
        d = [code_discipline(set_pp[f]['codes']) for f in sfp]
        names = sorted({x for x in d if x})
        labels = [names.index(x) if x else -1 for x in d]
        write_result(os.path.join(out, 'результат-А.csv'), sfp, labels, dict(enumerate(names)))
        dt = [code_discipline(train_pp[f]['codes']) for f in tfp]
        hit = sum(1 for a, b in zip(dt, y) if a and a == b)
        log['А'] = {'с кодом в наборе': sum(1 for x in d if x), 'обучение: с кодом': sum(1 for x in dt if x),
                    'обучение: код = папке': hit}
        print('А', log['А'], flush=True)

    if 'В' in wanted:
        run('В', Xs.toarray(), Xt.toarray(), 'TF-IDF основ, без учителя')

    if {'Б', 'Е'} & wanted:
        model = logistic(Xt, y)
        proba_s = model.predict_proba(Xs)
        proba_t, classes = oof_proba(Xt, y, [r['work'] for r in kept])
        order = [list(model.classes_).index(c) for c in classes]
        proba_s = proba_s[:, order]
    if 'Б' in wanted:
        # Б-ярлык: готовый ярлык классификатора; перевес над второй темой < порога — «без темы».
        best = None
        for m in [0.0, 0.05, 0.1, 0.15, 0.2, 0.3]:
            good = 0.0
            for fps in sets:
                idx = [tfp.index(f) for f in fps]
                res = []
                for i, f in zip(idx, fps):
                    p = np.sort(proba_t[i])[::-1]
                    res.append(dict(fp=f, группа=classes[int(np.argmax(proba_t[i]))] if p[0] - p[1] >= m else '-1'))
                _, o, _ = bench.score(ideal_t, res, strict=True)
                good += sum(1 for v in o.values() if v in bench.GOOD) / len(fps)
            if best is None or good / len(sets) > best[0]:
                best = (good / len(sets), m)
        labels = []
        for p in proba_s:
            q = np.sort(p)[::-1]
            labels.append(classes[int(np.argmax(p))] if q[0] - q[1] >= best[1] else -1)
        write_result(os.path.join(out, 'результат-Б-ярлык.csv'), sfp, labels)
        log['Б-ярлык'] = {'перевес': best[1], 'train_good': round(best[0], 4)}
        print('Б-ярлык', log['Б-ярлык'], flush=True)
        # Е-ярлык: код каталога, если он есть и однозначен (А почти не ошибается), иначе Б-ярлык.
        mixed = [code_discipline(set_pp[f]['codes']) or g for f, g in zip(sfp, labels)]
        write_result(os.path.join(out, 'результат-Е-ярлык.csv'), sfp, mixed)
        run('Б-пространство', proba_s, proba_t, 'вероятности тем классификатора → скопления')

    if {'Г', 'Е'} & wanted:
        e5_s = e5_vectors(s_text, os.path.join(cache, 'e5-набор.npy'))
        e5_t = e5_vectors(t_text, os.path.join(cache, 'e5-обучение.npy'))
        e5_t, e5_s = centred(e5_t, e5_s)
    if 'Г' in wanted:
        st = static_table(t_text + s_text, os.path.join(cache, 'e5-статич.npz'))
        st_t, st_s = centred(st[:len(t_text)], st[len(t_text):])
        run('Г-статич', st_s, st_t, 'своя статическая таблица из e5')
        run('Г-e5', e5_s, e5_t, 'e5 целиком (потолок векторов)')

    if 'Е' in wanted:
        def code_hot(fps, pp):
            return np.array([[1.0 if code_discipline(pp[f]['codes']) == c else 0.0 for c in classes] for f in fps])
        # Сумма трёх голосов, каждый нормирован: вероятности тем, вектор e5, код каталога.
        def unit(m):
            m = np.asarray(m, dtype=np.float64)
            return m / np.maximum(np.linalg.norm(m, axis=1, keepdims=True), 1e-12)
        es = np.hstack([unit(proba_s), unit(e5_s), 0.7 * code_hot(sfp, set_pp)])
        et = np.hstack([unit(proba_t), unit(e5_t), 0.7 * code_hot(tfp, train_pp)])
        run('Е', es, et, 'Б-пространство + e5 + коды → скопления')

    json.dump(log, open(os.path.join(out, 'настройки.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:6])
