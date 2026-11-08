"""Стенд «Галактики» (S61): сравнение результата сортировки с идеалом.

Вход:
- идеал.csv — для каждой книги набора: fp, n, название, тема, допустимые (через «;»),
  раздел, без_темы_ок (да/нет), вид, трудная; составлен по содержимому книг до прогонов;
- набор.csv — язык, качество текста и объём каждой книги (слои отчёта);
- результат.csv — что сделала система: fp, группа (−1 — «без темы»), имя группы.

Как считается. Группы системы возникают сами и называются как угодно (D-050), поэтому
сначала каждая группа сопоставляется теме идеала:
- строго — один к одному, венгерским алгоритмом по числу общих книг
  (вторая группа той же темы — ошибка: тема «рассыпана»);
- мягко — каждая группа получает свою главную тему.
Потом каждая книга — «верно» (её группа = её тема), «допустимо» (соседняя тема из
идеала или «без темы», где идеал это разрешает), «неподходящая» или «без темы».

Выход: отчёт в Markdown (сводка, по темам, строение, группы, ошибки, слои, разница
с прошлым прогоном) и строка журнала итераций.

Запуск: python tool/galaxy_bench/bench.py <идеал.csv> <набор.csv> <результат.csv> <отчёт.md>
        [--прошлый <результат.csv>] [--журнал <журнал.md>] [--версия "<что меняли>"]
"""
import argparse
import collections
import csv
import datetime

from scipy.optimize import linear_sum_assignment

GOOD = ('верно', 'допустимо')


def load(path):
    return list(csv.DictReader(open(path, encoding='utf-8')))


def match(groups_of, topic_of, strict):
    """Группа → тема. strict: один к одному (венгерский алгоритм), иначе главная тема группы."""
    groups = sorted({g for g in groups_of.values() if g != '-1'})
    topics = sorted(set(topic_of.values()))
    count = collections.Counter((groups_of[b], topic_of[b]) for b in groups_of if groups_of[b] != '-1')
    if not strict:
        return {g: max(topics, key=lambda t: (count[(g, t)], -topics.index(t))) for g in groups}
    if not groups:
        return {}
    cost = [[-count[(g, t)] for t in topics] for g in groups]
    rows, cols = linear_sum_assignment(cost)
    return {groups[r]: topics[c] for r, c in zip(rows, cols) if count[(groups[r], topics[c])] > 0}


def outcome(group, mapping, row):
    allowed = [x.strip() for x in row['допустимые'].split(';') if x.strip()]
    if group == '-1':
        return 'допустимо' if row['без_темы_ок'] == 'да' else 'без темы'
    topic = mapping.get(group)
    if topic == row['тема']:
        return 'верно'
    if topic in allowed:
        return 'допустимо'
    if topic is None and row['без_темы_ок'] == 'да':
        return 'допустимо'
    return 'неподходящая'


def score(ideal, result, strict):
    groups_of = {r['fp']: r['группа'] for r in result if r['fp'] in ideal}
    topic_of = {b: ideal[b]['тема'] for b in groups_of}
    mapping = match(groups_of, topic_of, strict)
    return mapping, {b: outcome(groups_of[b], mapping, ideal[b]) for b in groups_of}, groups_of


def _comb2(k):
    return k * (k - 1) / 2


def ari(a, b):
    """Скорректированный индекс Рэнда двух разбиений (списки меток одной длины).

    1 — разбиения совпадают, около 0 — сходство как у случайной раскладки.
    Считает пары книг: «вместе в обоих» против ожидаемого случайно (Hubert, Arabie, 1985).
    """
    n = len(a)
    pairs = collections.Counter(zip(a, b))
    sum_ij = sum(_comb2(v) for v in pairs.values())
    sum_a = sum(_comb2(v) for v in collections.Counter(a).values())
    sum_b = sum(_comb2(v) for v in collections.Counter(b).values())
    expected = sum_a * sum_b / _comb2(n) if n > 1 else 0.0
    top = (sum_a + sum_b) / 2
    return 1.0 if top == expected else (sum_ij - expected) / (top - expected)


def nmi(a, b):
    """Нормированная взаимная информация двух разбиений (среднее арифметическое энтропий).

    1 — одно разбиение полностью предсказывает другое, 0 — ничего о нём не говорит.
    """
    import math
    n = len(a)
    ca, cb, cab = collections.Counter(a), collections.Counter(b), collections.Counter(zip(a, b))
    h = lambda c: -sum(v / n * math.log(v / n) for v in c.values())
    mi = sum(v / n * math.log(v * n / (ca[x] * cb[y])) for (x, y), v in cab.items())
    ha, hb = h(ca), h(cb)
    return 1.0 if ha + hb == 0 else 2 * mi / (ha + hb)


def sections(ideal, result, out):
    """S68, мерка 7 «Разделы»: созвездия внутри темы против разделов идеала.

    Меряются только книги с верной темой: книга в чужой теме уже ошибка, и созвездие её не спасёт.
    Внутри каждой темы идеала созвездия системы сопоставляются разделам идеала один к одному
    (тот же венгерский алгоритм, что для тем, `match`): второе созвездие того же раздела — ошибка
    («раздел рассыпан»), созвездие из двух разделов засчитывается только за один.
    Возвращает ({книга: в разделе ли}, {тема идеала: [книги с верной темой]}, {книга: созвездие}).
    """
    cons = {r['fp']: r.get('созвездие') or '-' for r in result}
    by_topic = collections.defaultdict(list)
    for b, o in out.items():
        if o == 'верно':
            by_topic[ideal[b]['тема']].append(b)
    hit = {}
    for t, bs in by_topic.items():
        mapping = match({b: cons[b] for b in bs}, {b: ideal[b]['раздел'] for b in bs}, strict=True)
        for b in bs:
            hit[b] = mapping.get(cons[b]) == ideal[b]['раздел']
    return hit, by_topic, cons


def layers_of(layer_row, ideal_row):
    # Язык — из идеала (судья читал книгу): опись по доле латиницы пишет «en» и польской,
    # и испанской книге, а у сканов её догадка — по случайным буквам обложки.
    yield 'язык ' + (ideal_row.get('язык') or layer_row['lang'])
    yield 'качество ' + layer_row['quality']
    yield 'вид ' + (ideal_row.get('вид') or '?')
    p = int(layer_row['pages'])
    yield 'объём ' + ('≤ 150' if p <= 150 else ('> 800' if p > 800 else '150–800'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ideal')
    ap.add_argument('set')
    ap.add_argument('result')
    ap.add_argument('report')
    ap.add_argument('--прошлый', dest='prev')
    ap.add_argument('--журнал', dest='journal')
    ap.add_argument('--версия', dest='version', default='')
    a = ap.parse_args()

    ideal = {r['fp']: r for r in load(a.ideal)}
    layer = {r['fp']: r for r in load(a.set)}
    result = load(a.result)
    names = {r['группа']: r.get('имя', '') for r in result}
    seen = {r['fp'] for r in result}
    missing = [b for b in ideal if b not in seen]
    mapping, out, groups_of = score(ideal, result, strict=True)
    _, soft, _ = score(ideal, result, strict=False)
    tally, soft_tally = collections.Counter(out.values()), collections.Counter(soft.values())
    n_groups = len({g for g in groups_of.values() if g != '-1'})
    n_topics = len({r['тема'] for r in ideal.values()})

    L = [f'# Сравнение с идеалом — {a.version or a.result}', '',
         f'Книг: {len(out)} (нет в результате: {len(missing)}). Групп у системы: {n_groups}, тем в идеале: {n_topics}.',
         '', '## 1. Сводка', '',
         '| Исход | Строго (1 группа = 1 тема) | Мягко (группа → её главная тема) |', '|---|---|---|']
    for k in ('верно', 'допустимо', 'неподходящая', 'без темы'):
        L.append(f'| {k} | {tally[k]} | {soft_tally[k]} |')

    by_topic = collections.defaultdict(list)
    for b in out:
        by_topic[ideal[b]['тема']].append(b)
    L += ['', '## 2. По темам идеала (строго)', '',
          '| Тема | Книг | Верно | Допустимо | Ушли (тема группы → книг) | Без темы |', '|---|---|---|---|---|---|']
    for t in sorted(by_topic):
        bs = by_topic[t]
        c = collections.Counter(out[b] for b in bs)
        gone = collections.Counter(mapping.get(groups_of[b], 'лишняя группа') for b in bs if out[b] == 'неподходящая')
        gone_text = ', '.join(f'{k} → {v}' for k, v in gone.most_common()) or '—'
        L.append(f'| {t} | {len(bs)} | {c["верно"]} | {c["допустимо"]} | {gone_text} | {c["без темы"]} |')

    members = collections.defaultdict(list)
    for b, g in groups_of.items():
        if g != '-1':
            members[g].append(b)
    split = []
    for t, bs in by_topic.items():
        gs = collections.Counter(groups_of[b] for b in bs if groups_of[b] != '-1')
        big = [g for g, k in gs.items() if k >= max(2, 0.2 * len(bs))]
        if len(big) >= 2:
            split.append(f'{t} ({len(big)} групп)')
    merged = []
    for g, bs in members.items():
        ts = collections.Counter(ideal[b]['тема'] for b in bs)
        many = [t for t, k in ts.items() if k >= 2]
        if len(many) >= 2:
            merged.append(f'«{names.get(g) or g}»: ' + ', '.join(f'{t} {ts[t]}' for t in many))
    extra = [g for g in members if g not in mapping]
    singles = sum(1 for bs in members.values() if len(bs) == 1)
    # «Без темы» у каждой книги — своя группа: иначе все такие книги считались бы одной темой.
    order = sorted(out)
    system = [groups_of[b] if groups_of[b] != '-1' else 'без:' + b for b in order]
    truth = [ideal[b]['тема'] for b in order]
    agree_ari, agree_nmi = ari(truth, system), nmi(truth, system)
    L += ['', '## 3. Строение', '',
          f'- Рассыпанные темы (книги темы в ≥ 2 крупных группах): {len(split)} — {"; ".join(split) or "нет"}',
          f'- Слитые группы (≥ 2 тем по ≥ 2 книги): {len(merged)} — {"; ".join(merged) or "нет"}',
          f'- Лишние группы (без своей темы при строгом сопоставлении): {len(extra)}; групп из одной книги: {singles}',
          f'- Согласие разбиений с идеалом: ARI {agree_ari:.2f}, NMI {agree_nmi:.2f} (1 — совпадают)']

    L += ['', '## 4. Группы системы', '', '| Группа | Имя | Тема (строго) | Книг | Состав по темам идеала |', '|---|---|---|---|---|']
    for g in sorted(members, key=lambda g: -len(members[g])):
        ts = collections.Counter(ideal[b]['тема'] for b in members[g])
        L.append(f'| {g} | {names.get(g, "")} | {mapping.get(g, "—")} | {len(members[g])} | '
                 + ', '.join(f'{t} {k}' for t, k in ts.most_common()) + ' |')

    L += ['', '## 5. Ошибки (строго)', '', '| № | Книга | Тема идеала | Группа системы → тема | Язык, качество | Трудная |', '|---|---|---|---|---|---|']
    for b in sorted(out, key=lambda b: int(ideal[b]['n'])):
        if out[b] in GOOD:
            continue
        g = groups_of[b]
        where = 'без темы' if g == '-1' else f'{names.get(g) or g} → {mapping.get(g, "лишняя")}'
        L.append(f'| {ideal[b]["n"]} | {ideal[b]["название"][:60]} | {ideal[b]["тема"]} | {where} | '
                 f'{layer[b]["lang"]}, {layer[b]["quality"]} | {ideal[b].get("трудная", "")} |')

    ly = collections.defaultdict(lambda: [0, 0])
    for b in out:
        for k in layers_of(layer[b], ideal[b]):
            ly[k][0] += 1
            ly[k][1] += out[b] in GOOD
    L += ['', '## 6. По слоям (верно + допустимо, строго)', '', '| Слой | Книг | Верно + допустимо |', '|---|---|---|']
    for k in sorted(ly):
        L.append(f'| {k} | {ly[k][0]} | {ly[k][1]} ({100 * ly[k][1] // ly[k][0]} %) |')

    if a.prev:
        _, prev_out, _ = score(ideal, load(a.prev), strict=True)
        num = lambda bs: ', '.join(ideal[b]['n'] for b in sorted(bs, key=lambda b: int(ideal[b]['n']))) or '—'
        fixed = [b for b in out if b in prev_out and out[b] in GOOD and prev_out[b] not in GOOD]
        broke = [b for b in out if b in prev_out and out[b] not in GOOD and prev_out[b] in GOOD]
        L += ['', '## 7. Разница с прошлым прогоном', '',
              f'- Исправились ({len(fixed)}): {num(fixed)}', f'- Сломались ({len(broke)}): {num(broke)}']

    in_section = ''
    if result and 'созвездие' in result[0]:  # S68: результат со вторым уровнем — мерка «Разделы»
        hit, sec_topics, cons = sections(ideal, result, out)
        n_hit = sum(hit.values())
        in_section = f'разделы {n_hit} из {len(hit)}'
        L += ['', '## 8. Разделы (созвездия внутри темы)', '',
              f'В разделе идеала: **{n_hit}** из {len(hit)} книг с верной темой '
              f'({100 * n_hit // max(1, len(hit))} %); из всех книг набора — {n_hit} из {len(out)}.', '',
              '| Тема идеала | Книг с верной темой | В разделе | Созвездия системы (книг) |', '|---|---|---|---|']
        for t in sorted(sec_topics):
            bs = sec_topics[t]
            cs = collections.Counter(cons[b] for b in bs)
            L.append(f'| {t} | {len(bs)} | {sum(hit[b] for b in bs)} | '
                     + ', '.join(f'{c} {k}' for c, k in cs.most_common()) + ' |')
        L += ['', '| № | Книга | Раздел идеала | Созвездие системы |', '|---|---|---|---|']
        for b in sorted(hit, key=lambda b: int(ideal[b]['n'])):
            if not hit[b]:
                L.append(f'| {ideal[b]["n"]} | {ideal[b]["название"][:60]} | {ideal[b]["раздел"]} | {cons[b]} |')
        print(in_section)

    open(a.report, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    version = f'{a.version} — {in_section}' if in_section else a.version
    line = (f'| {datetime.date.today():%d.%m} | {version} | {tally["верно"]} | {tally["допустимо"]} | '
            f'{tally["неподходящая"]} | {tally["без темы"]} | {soft_tally["верно"] + soft_tally["допустимо"]} | '
            f'{n_groups} | {len(split)} / {len(merged)} | {agree_ari:.2f} |')
    if a.journal:
        open(a.journal, 'a', encoding='utf-8').write(line + '\n')
    print(line)


if __name__ == '__main__':
    main()
