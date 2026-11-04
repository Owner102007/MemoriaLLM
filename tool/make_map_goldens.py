#!/usr/bin/env python3
"""Эталон расчёта карты книг — второй, независимой реализацией.

Зачем. Карта «Галактика» обязана быть одной и той же у всех участников
исследования: один набор книг — одна карта, на телефоне и на ПК
(F-MAP-02, SNO-F-MAP-01). Проверить это тестом, который зовёт ту же
функцию, нельзя: он сверял бы её с самой собой. Поэтому здесь тот же
расчёт написан заново, на Python, и результат кладётся в
`test/goldens/book_map.json` — как это сделано для вида категорий
(`tool/make_category_goldens.py`).

Расчёт (ALG-MAP-02 … ALG-MAP-07):

1. словарь корпуса: слово остаётся, если встречается хотя бы в двух
   книгах и не больше чем в 85 % книг;
2. BM25 (k1 = 1,2; b = 0,75) и нормировка строки к единичной длине;
3. матрица Грама и её собственные векторы вращениями Якоби — точное
   разложение вместо рандомизированного: книг десятки;
4. соседи по косинусу в пространстве главных компонент;
5. созвездия адаптивным резонансом (ALG-MAP-16) и их имена c-TF-IDF
   (ALG-MAP-10); группа раскладки — созвездие, а не категория полки;
   типичность книги — косинус со средним её созвездия (ALG-MAP-17);
6. раскладка на плоскости: притяжение по рёбрам соседей, отталкивание
   случайной выборкой, притяжение к центру своей категории, слабое
   тяготение к центру карты, в конце — наименьший просвет между
   точками;
7. внутри созвездия книги пересаживаются по его же точкам: типичная —
   ближе к центру, особенная — на край (F-MAP-17, D-044).

**Только точные операции.** Сложение, вычитание, умножение, деление и
квадратный корень в IEEE 754 дают один и тот же результат на любом
процессоре; логарифм, степень и синус — нет: их считает библиотека
платформы, и последний бит у неё свой. Поэтому логарифм здесь свой
(рядом), степеней и тригонометрии в расчёте нет вовсе, а случайные
числа даёт свой генератор (Mulberry32). Порядок сложений записан
циклами и в Dart повторён дословно — оттого две реализации сходятся
до последнего бита, а не «примерно».

Запуск:  python3 tool/make_map_goldens.py
"""

import json
import math
import pathlib

MASK = 0xFFFFFFFF
LN2 = 0.6931471805599453

# Числа расчёта. Те же стоят в lib/domain/map/.
STOP_PERCENT = 85
MIN_BOOKS = 2
K1 = 1.2
B = 0.75
DIMENSIONS = 48
NEIGHBOURS = 15
EPOCHS = 300
NEGATIVES = 5
CATEGORY_PULL = 0.3
CROSS_WEIGHT = 0.25
GRAVITY = 0.2
GAP_SHARE = 0.5
SPREAD_ROUNDS = 60
SPREAD_LIMIT = 1500
SEED = 20261005
INITIAL_EXTENT = 10.0
JITTER = 0.01
MIN_MAP_BOOKS = 3


def imul(a, b):
    return (a * b) & MASK


class Mulberry:
    """Генератор Mulberry32: 32 бита состояния, целые без знака."""

    def __init__(self, seed):
        self.state = seed & MASK

    def next(self):
        self.state = (self.state + 0x6D2B79F5) & MASK
        t = self.state
        t = imul(t ^ (t >> 15), t | 1)
        t ^= (t + imul(t ^ (t >> 7), t | 61)) & MASK
        return (t ^ (t >> 14)) & MASK

    def unit(self):
        return self.next() / 4294967296.0

    def below(self, n):
        return self.next() % n


def ln_exact(x):
    """Натуральный логарифм одними точными операциями."""
    e = 0
    while x >= 2.0:
        x *= 0.5
        e += 1
    while x < 1.0:
        x *= 2.0
        e -= 1
    z = (x - 1.0) / (x + 1.0)
    z2 = z * z
    total = 0.0
    k = 39
    while k >= 1:
        total = total * z2 + 1.0 / k
        k -= 2
    return 2.0 * z * total + e * LN2


def vocabulary(books):
    n = len(books)
    df = {}
    for book in books:
        for term, _ in book['terms']:
            df[term] = df.get(term, 0) + 1
    kept = sorted(
        term
        for term, count in df.items()
        if count >= MIN_BOOKS and count * 100 <= STOP_PERCENT * n
    )
    return kept, df


def bm25_rows(books, kept, df):
    n = len(books)
    index = {term: i for i, term in enumerate(kept)}
    total = 0
    for book in books:
        total += book['length']
    average = total / n if n > 0 else 0.0
    idf = [ln_exact(1.0 + (n - df[t] + 0.5) / (df[t] + 0.5)) for t in kept]
    rows = []
    for book in books:
        if average > 0.0:
            scale = 1.0 - B + B * (book['length'] / average)
        else:
            scale = 1.0
        cells = []
        for term, count in book['terms']:
            i = index.get(term)
            if i is None:
                continue
            tf = float(count)
            cells.append((i, idf[i] * tf * (K1 + 1.0) / (tf + K1 * scale)))
        cells.sort()
        square = 0.0
        for _, weight in cells:
            square += weight * weight
        if square > 0.0:
            root = math.sqrt(square)
            cells = [(i, weight / root) for i, weight in cells]
        rows.append(cells)
    return rows, idf


def sparse_dot(a, b):
    i = 0
    j = 0
    total = 0.0
    while i < len(a) and j < len(b):
        if a[i][0] == b[j][0]:
            total += a[i][1] * b[j][1]
            i += 1
            j += 1
        elif a[i][0] < b[j][0]:
            i += 1
        else:
            j += 1
    return total


def gram(rows):
    n = len(rows)
    g = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i, n):
            value = sparse_dot(rows[i], rows[j])
            g[i][j] = value
            g[j][i] = value
    return g


def jacobi(matrix, max_sweeps=60, tolerance=1e-24):
    n = len(matrix)
    a = [row[:] for row in matrix]
    v = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    for _ in range(max_sweeps):
        off = 0.0
        total = 0.0
        for i in range(n):
            for j in range(n):
                square = a[i][j] * a[i][j]
                total += square
                if i != j:
                    off += square
        if off <= tolerance * total:
            break
        for p in range(n - 1):
            for q in range(p + 1, n):
                apq = a[p][q]
                if apq == 0.0:
                    continue
                theta = (a[q][q] - a[p][p]) / (2.0 * apq)
                if theta >= 0.0:
                    t = 1.0 / (theta + math.sqrt(theta * theta + 1.0))
                else:
                    t = -1.0 / (-theta + math.sqrt(theta * theta + 1.0))
                c = 1.0 / math.sqrt(t * t + 1.0)
                s = t * c
                for k in range(n):
                    akp = a[k][p]
                    akq = a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                for k in range(n):
                    apk = a[p][k]
                    aqk = a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
                for k in range(n):
                    vkp = v[k][p]
                    vkq = v[k][q]
                    v[k][p] = c * vkp - s * vkq
                    v[k][q] = s * vkp + c * vkq
    return [a[i][i] for i in range(n)], v


def latent(g):
    n = len(g)
    values, vectors = jacobi(g)
    order = sorted(range(n), key=lambda i: (-values[i], i))
    limit = min(DIMENSIONS, n - 1)
    columns = [c for c in order[:limit] if values[c] > 1e-12]
    rows = [[0.0] * len(columns) for _ in range(n)]
    for place, c in enumerate(columns):
        best = 0
        for i in range(1, n):
            if abs(vectors[i][c]) > abs(vectors[best][c]):
                best = i
        sign = -1.0 if vectors[best][c] < 0.0 else 1.0
        root = math.sqrt(values[c])
        for i in range(n):
            rows[i][place] = sign * vectors[i][c] * root
    return rows, [values[c] for c in columns]


def neighbours(rows):
    n = len(rows)
    unit = []
    for row in rows:
        square = 0.0
        for value in row:
            square += value * value
        if square > 1e-24:
            root = math.sqrt(square)
            unit.append([value / root for value in row])
        else:
            unit.append(None)
    sims = [[0.0] * n for _ in range(n)]
    for i in range(n):
        if unit[i] is None:
            continue
        for j in range(i + 1, n):
            if unit[j] is None:
                continue
            total = 0.0
            for k in range(len(unit[i])):
                total += unit[i][k] * unit[j][k]
            sims[i][j] = total
            sims[j][i] = total
    limit = min(NEIGHBOURS, n - 1)
    near = []
    for i in range(n):
        found = [j for j in range(n) if j != i and sims[i][j] > 0.0]
        found.sort(key=lambda j: (-sims[i][j], j))
        near.append(found[:limit])
    return near, sims


def edges_of(near, sims):
    n = len(near)
    sets = [set(found) for found in near]
    edges = []
    top = 0.0
    for i in range(n):
        for j in range(i + 1, n):
            if j in sets[i] or i in sets[j]:
                edges.append((i, j, sims[i][j]))
                if sims[i][j] > top:
                    top = sims[i][j]
    if top > 0.0:
        edges = [(i, j, weight / top) for i, j, weight in edges]
    return edges


def clip(value):
    if value > 4.0:
        return 4.0
    if value < -4.0:
        return -4.0
    return value


def center_scale(xs, ys, size):
    n = len(xs)
    if n == 0:
        return
    mx = 0.0
    my = 0.0
    for i in range(n):
        mx += xs[i]
        my += ys[i]
    mx /= n
    my /= n
    top = 0.0
    for i in range(n):
        xs[i] -= mx
        ys[i] -= my
        if abs(xs[i]) > top:
            top = abs(xs[i])
        if abs(ys[i]) > top:
            top = abs(ys[i])
    if top > 0.0:
        for i in range(n):
            xs[i] = xs[i] / top * size
            ys[i] = ys[i] / top * size


def spread(xs, ys):
    n = len(xs)
    if n < 2 or n > SPREAD_LIMIT:
        return
    gap = GAP_SHARE / math.sqrt(float(n))
    for _ in range(SPREAD_ROUNDS):
        moved = False
        for i in range(n - 1):
            for j in range(i + 1, n):
                dx = xs[j] - xs[i]
                dy = ys[j] - ys[i]
                d2 = dx * dx + dy * dy
                if d2 >= gap * gap:
                    continue
                moved = True
                if d2 > 0.0:
                    d = math.sqrt(d2)
                    push = (gap - d) * 0.5
                    ux = dx / d
                    uy = dy / d
                else:
                    push = gap * 0.5
                    ux = 1.0
                    uy = 0.0
                xs[i] -= ux * push
                ys[i] -= uy * push
                xs[j] += ux * push
                ys[j] += uy * push
        if not moved:
            break


def layout(rows, edges, groups, epochs=EPOCHS):
    n = len(rows)
    rng = Mulberry(SEED)
    xs = [0.0] * n
    ys = [0.0] * n
    dims = len(rows[0]) if n > 0 else 0
    # Первая компонента у неотрицательных векторов — общая для всех
    # книг: раскладке она ничего не говорит.
    cx = 1 if dims > 1 else 0
    cy = cx + 1
    for i in range(n):
        if dims > cx:
            xs[i] = rows[i][cx]
        if dims > cy:
            ys[i] = rows[i][cy]
    center_scale(xs, ys, INITIAL_EXTENT)
    for i in range(n):
        xs[i] += (rng.unit() * 2.0 - 1.0) * JITTER * INITIAL_EXTENT
        ys[i] += (rng.unit() * 2.0 - 1.0) * JITTER * INITIAL_EXTENT
    edges = [
        (a, b, w if groups[a] == groups[b] else w * CROSS_WEIGHT)
        for a, b, w in edges
    ]
    strength = [0.0] * n
    for a, b, w in edges:
        strength[a] += w
        strength[b] += w
    members = {}
    for i, group in enumerate(groups):
        members.setdefault(group, []).append(i)
    # Якорь узла: номер списка узлов, к центру которых он тянется.
    anchors = []
    anchor = [-1] * n
    everyone = -1
    for group in sorted(members):
        found = members[group]
        if group != '' and len(found) >= 2:
            anchors.append(found)
            for i in found:
                anchor[i] = len(anchors) - 1
    for i in range(n):
        if anchor[i] < 0 and strength[i] == 0.0:
            if everyone < 0:
                anchors.append(list(range(n)))
                everyone = len(anchors) - 1
            anchor[i] = everyone
    for epoch in range(epochs):
        alpha = 1.0 - float(epoch) / float(epochs)
        for a, b, w in edges:
            for i, j in ((a, b), (b, a)):
                dx = xs[i] - xs[j]
                dy = ys[i] - ys[j]
                d2 = dx * dx + dy * dy
                if d2 > 0.0:
                    g = -2.0 / (1.0 + d2) * w
                    mx = clip(g * dx) * alpha
                    my = clip(g * dy) * alpha
                    xs[i] += mx
                    ys[i] += my
                    xs[j] -= mx
                    ys[j] -= my
                for _ in range(NEGATIVES):
                    c = rng.below(n)
                    if c == i:
                        continue
                    dx = xs[i] - xs[c]
                    dy = ys[i] - ys[c]
                    d2 = dx * dx + dy * dy
                    if d2 > 0.0:
                        g = 2.0 / ((0.001 + d2) * (1.0 + d2)) * w
                        xs[i] += clip(g * dx) * alpha
                        ys[i] += clip(g * dy) * alpha
        centres = []
        for found in anchors:
            mx = 0.0
            my = 0.0
            for i in found:
                mx += xs[i]
                my += ys[i]
            centres.append((mx / len(found), my / len(found)))
        for i in range(n):
            if anchor[i] < 0:
                continue
            mx, my = centres[anchor[i]]
            w = CATEGORY_PULL * (1.0 + strength[i])
            dx = xs[i] - mx
            dy = ys[i] - my
            d2 = dx * dx + dy * dy
            g = -2.0 / (1.0 + d2) * w
            xs[i] += clip(g * dx) * alpha
            ys[i] += clip(g * dy) * alpha
            for _ in range(NEGATIVES):
                c = rng.below(n)
                if c == i:
                    continue
                dx = xs[i] - xs[c]
                dy = ys[i] - ys[c]
                d2 = dx * dx + dy * dy
                if d2 > 0.0:
                    g = 2.0 / ((0.001 + d2) * (1.0 + d2)) * CATEGORY_PULL
                    xs[i] += clip(g * dx) * alpha
                    ys[i] += clip(g * dy) * alpha
        mx = 0.0
        my = 0.0
        for i in range(n):
            mx += xs[i]
            my += ys[i]
        mx /= n
        my /= n
        for i in range(n):
            xs[i] -= clip((xs[i] - mx) * GRAVITY) * alpha
            ys[i] -= clip((ys[i] - my) * GRAVITY) * alpha
    center_scale(xs, ys, 1.0)
    spread(xs, ys)
    center_scale(xs, ys, 1.0)
    return xs, ys


# --- Созвездия: адаптивный резонанс (ALG-MAP-16) -------------------------
#
# Та же логика, что в lib/domain/map/map_categories.dart, и тот же порядок
# сложений. Всё считается по матрице Грама книг g: x·S — сумма косинусов
# книги с книгами категории, |S|² — сумма всех косинусов внутри неё.
# Эталон правила — резонанс.py шага 45 (описание проекта).

ART_RHO = 0.6
ART_PHI = 0.4
ART_COHESION_BOOKS = 3
ART_ROUNDS = 10


def canon(labels):
    seen = {}
    out = []
    for label in labels:
        if label < 0:
            out.append(-1)
        else:
            if label not in seen:
                seen[label] = len(seen)
            out.append(seen[label])
    return out


def has_words(g, i):
    return g[i][i] > 0.0


def within(g, a, b):
    total = 0.0
    for i in a:
        for j in b:
            total += g[i][j]
    return total


class Cats:
    def __init__(self, g, c0, floor):
        self.g = g
        self.c0 = c0
        self.floor = floor
        self.members = []
        self.counts = []
        self.squares = []

    def cohesion(self, j):
        n = self.counts[j]
        if n < ART_COHESION_BOOKS:
            return self.c0
        return (self.squares[j] - n) / (n * (n - 1))

    def dot(self, j, i):
        total = 0.0
        for m in self.members[j]:
            total += self.g[i][m]
        return total

    def add(self, j, i):
        self.squares[j] += 2.0 * self.dot(j, i) + self.g[i][i]
        members = self.members[j]
        at = len(members)
        while at > 0 and members[at - 1] > i:
            at -= 1
        members.insert(at, i)
        self.counts[j] += 1

    def open(self, i):
        self.members.append([i])
        self.counts.append(1)
        self.squares.append(self.g[i][i])
        return len(self.counts) - 1

    @classmethod
    def of(cls, g, labels, c0, floor):
        out = cls(g, c0, floor)
        k = 0
        for label in labels:
            k = max(k, label + 1)
        for _ in range(k):
            out.members.append([])
            out.counts.append(0)
            out.squares.append(0.0)
        for i, label in enumerate(labels):
            if label >= 0:
                out.members[label].append(i)
                out.counts[label] += 1
        for j in range(k):
            out.squares[j] = within(g, out.members[j], out.members[j])
        return out


def library_measure(g):
    n = len(g)
    present = [i for i in range(n) if has_words(g, i)]
    if len(present) < 2:
        return 0.0
    best = []
    for i in present:
        top = -math.inf
        for j in present:
            if i != j and g[i][j] > top:
                top = g[i][j]
        best.append(top)
    best.sort()
    m = len(best)
    if m % 2:
        return best[m // 2]
    return (best[m // 2 - 1] + best[m // 2]) / 2.0


def art_choose(cats, i, own=None, sticky=False):
    k = len(cats.counts)
    if k == 0:
        return None
    dots = [cats.dot(j, i) for j in range(k)]
    c = [dots[j] / cats.counts[j] for j in range(k)]
    q = [cats.cohesion(j) for j in range(k)]
    skip = None
    if own is not None:
        m = cats.counts[own]
        if m == 1:
            skip = own
        else:
            self_value = cats.g[i][i]
            c[own] = (dots[own] - self_value) / (m - 1)
            rest = m - 1
            if rest >= ART_COHESION_BOOKS:
                square = cats.squares[own] - 2.0 * dots[own] + self_value
                q[own] = (square - rest) / (rest * (rest - 1))
            else:
                q[own] = cats.c0
    if own is not None and skip is None and sticky:
        if c[own] >= cats.floor and q[own] > 0.0 \
                and c[own] >= ART_RHO * q[own]:
            return own
    for j in sorted(range(k), key=lambda j: (-c[j], j)):
        if j == skip:
            continue
        if c[j] < cats.floor:
            break
        if q[j] > 0.0 and c[j] >= ART_RHO * q[j]:
            return j
    return None


def art_day(g, order, c0, floor):
    cats = Cats(g, c0, floor)
    labels = [-1] * len(g)
    for i in order:
        if not has_words(g, i):
            continue
        j = art_choose(cats, i)
        if j is None:
            labels[i] = cats.open(i)
        else:
            cats.add(j, i)
            labels[i] = j
    return labels, cats


def art_merge(g, raw, c0, held_books, floor):
    labels = canon(raw)
    sch = Cats.of(g, labels, c0, floor)
    k = len(sch.counts)
    if k < 2:
        return labels
    held = {labels[i] for i in held_books if labels[i] >= 0}
    alive = [True] * k
    cross = [[sch.squares[a] if a == b
              else within(g, sch.members[a], sch.members[b])
              for b in range(k)] for a in range(k)]
    while True:
        live = [j for j in range(k) if alive[j] and j not in held]
        q = {j: sch.cohesion(j) for j in live}
        best = None
        for ai, a in enumerate(live):
            for b in live[ai + 1:]:
                cab = cross[a][b] / (sch.counts[a] * sch.counts[b])
                if cab < floor or q[a] * q[b] <= 0.0:
                    continue
                r = cab / math.sqrt(q[a] * q[b])
                if r >= ART_RHO and (best is None or r > best[0]):
                    best = (r, a, b)
        if best is None:
            break
        _, a, b = best
        square = cross[a][a] + 2.0 * cross[a][b] + cross[b][b]
        for j in range(k):
            if j != a and j != b:
                value = cross[a][j] + cross[b][j]
                cross[a][j] = value
                cross[j][a] = value
        cross[a][a] = square
        sch.squares[a] = square
        sch.counts[a] += sch.counts[b]
        sch.members[a] = sorted(sch.members[a] + sch.members[b])
        alive[b] = False
    out = list(labels)
    for j in range(k):
        if alive[j]:
            for i in sch.members[j]:
                out[i] = j
    return canon(out)


def art_consolidate(g, start, c0, order, pinned, floor):
    labels = canon(start)
    n = len(g)
    for sticky in (False, True):
        for _ in range(ART_ROUNDS):
            labels = canon(labels)
            sch = Cats.of(g, labels, c0, floor)
            held = {labels[i] for i in pinned if labels[i] >= 0}
            new = list(labels)
            low = []
            for i in range(n):
                if not has_words(g, i) or i in pinned or labels[i] in held:
                    continue
                j = art_choose(sch, i, own=labels[i], sticky=sticky)
                if j is None:
                    low.append(i)
                else:
                    new[i] = j
            if low:
                wait = set(low)
                seeds, _ = art_day(g, [i for i in order if i in wait],
                                   c0, floor)
                for i in low:
                    new[i] = len(sch.counts) + seeds[i]
            merged = art_merge(g, new, c0, pinned, floor)
            if merged == labels:
                return labels
            labels = merged
    return labels


def cohesions_of(g, labels, c0):
    cats = Cats.of(g, labels, c0, 0.0)
    return [cats.cohesion(j) for j in range(len(cats.counts))]


def art_categories(g, order=None, pinned=None):
    """Возвращает (созвездия, c₀, сплочённости) — как ArtResult в Dart."""
    n = len(g)
    order = list(range(n)) if order is None else order
    pinned = pinned or {}
    present = [i for i in range(n) if has_words(g, i)]
    c0 = library_measure(g)
    if len(present) < ART_COHESION_BOOKS:
        labels = [0 if has_words(g, i) else -1 for i in range(n)]
        return labels, c0, cohesions_of(g, labels, c0)
    floor = ART_PHI * c0
    labels, _ = art_day(g, order, c0, floor)
    held = set()
    if pinned:
        nxt = 0
        for label in labels:
            if label >= nxt:
                nxt = label + 1
        of_group = {}
        for i in range(n):
            group = pinned.get(i)
            if group is None or not has_words(g, i):
                continue
            if group not in of_group:
                of_group[group] = nxt
                nxt += 1
            labels[i] = of_group[group]
            held.add(i)
    labels = canon(art_consolidate(g, labels, c0, order, held, floor))
    return labels, c0, cohesions_of(g, labels, c0)


# --- Доверие тексту (F-MAP-18, `categorize`/`place` шага 46) -------------

TRUST_LOW = 0.8
TRUST_CONTRAST = 1.5
MIN_TRUSTED_BUILDERS = 3


def unreliable(trust):
    """`trust`: None — как есть, 'little' — надёжного текста нет, число — T."""
    return trust == 'little' or (trust is not None and trust < TRUST_LOW)


def builders_of(trusts):
    hi = [i for i, t in enumerate(trusts) if not unreliable(t)]
    if len(hi) < MIN_TRUSTED_BUILDERS:
        return list(range(len(trusts)))
    return hi


def place(g, i, built, c0, t):
    """Куда встаёт книга с ненадёжным текстом — `place` шага 46."""
    n = len(g)
    if not g[i][i] > 0.0:
        return -1
    cats = sorted({label for label in built if label >= 0})
    if not cats:
        return -1
    close = []
    for c in cats:
        total = 0.0
        count = 0
        for j in range(n):
            if built[j] == c:
                total += g[i][j]
                count += 1
        close.append(total / count)
    best = 0
    for k in range(1, len(cats)):
        if close[k] > close[best]:
            best = k
    if len(cats) == 1 or close[best] < ART_PHI * c0 * t:
        return -1
    second = 1 if best == 0 else 0
    for k in range(len(cats)):
        if k != best and close[k] > close[second]:
            second = k
    return cats[best] if close[best] >= TRUST_CONTRAST * close[second] else -1


def trusted_categories(g, trusts):
    """Созвездия и причины: 'none', 'littleText', 'unsure'."""
    n = len(g)
    hi = builders_of(trusts)
    reasons = ['none'] * n
    if len(hi) == n:
        return art_categories(g)[0], reasons
    sub = [[g[a][b] for b in hi] for a in hi]
    labels_hi, c0, _ = art_categories(sub)
    labels = [-1] * n
    for k, i in enumerate(hi):
        labels[i] = labels_hi[k]
    built = list(labels)
    building = set(hi)
    for i in range(n):
        if i in building:
            continue
        if trusts[i] == 'little':
            reasons[i] = 'littleText'
            continue
        labels[i] = place(g, i, built, c0, trusts[i] or 0.0)
        if labels[i] == -1 and g[i][i] > 0.0:
            reasons[i] = 'unsure'
    return labels, reasons


def restrict_untrusted(books):
    """Мешок ненадёжной книги — только слова книг с надёжным текстом."""
    trusts = [book.get('trust') for book in books]
    hi = builders_of(trusts)
    if len(hi) == len(books):
        return books
    known = set()
    for i in hi:
        known.update(term for term, _ in books[i]['terms'])
    out = []
    building = set(hi)
    for i, book in enumerate(books):
        if i in building or trusts[i] == 'little':
            out.append(book)
            continue
        terms = [[t, c] for t, c in book['terms'] if t in known]
        out.append(dict(book, terms=terms, length=sum(c for _, c in terms)))
    return out


def group_of(label):
    """Группа раскладки по номеру созвездия — как `constellationGroup`."""
    return '' if label < 0 else 'art:%04d' % label


# --- Имена созвездий: c-TF-IDF (ALG-MAP-10) ------------------------------

def constellation_names(books, kept, labels):
    """Имя созвездия — два слова, характерных для него против остальных.

    Счёт слова в созвездии tf — сумма по его книгам; доля tf / всех слов
    созвездия умножается на ln(1 + A / f), где f — счёт слова по всем
    созвездиям, A — среднее число слов на созвездие (как в BERTopic).
    Слово показывается полной формой из книги, где оно чаще всего.
    Одинаковые имена различаются номером: «… 2», «… 3».
    """
    index = {term: i for i, term in enumerate(kept)}
    k = 0
    for label in labels:
        k = max(k, label + 1)
    tf = [{} for _ in range(k)]
    form = [{} for _ in range(k)]
    totals = [0] * k
    for b, book in enumerate(books):
        label = labels[b]
        if label < 0:
            continue
        forms = book.get('forms') or [t for t, _ in book['terms']]
        for (term, count), word in zip(book['terms'], forms):
            i = index.get(term)
            if i is None:
                continue
            tf[label][i] = tf[label].get(i, 0) + count
            totals[label] += count
            current = form[label].get(i)
            if current is None or count > current[0]:
                form[label][i] = (count, word)
    f = {}
    for label in range(k):
        for i in sorted(tf[label]):
            f[i] = f.get(i, 0) + tf[label][i]
    total_all = 0
    for value in totals:
        total_all += value
    average = total_all / k if k > 0 else 0.0
    names = []
    for label in range(k):
        scored = []
        for i in sorted(tf[label]):
            share = tf[label][i] / totals[label]
            scored.append((share * ln_exact(1.0 + average / f[i]), i))
        scored.sort(key=lambda item: (-item[0], item[1]))
        names.append(' · '.join(form[label][i][1] for _, i in scored[:2]))
    used = set()
    out = []
    for name in names:
        candidate = name
        number = 2
        while candidate in used:
            candidate = '%s %d' % (name, number)
            number += 1
        used.add(candidate)
        out.append(candidate)
    return out


# --- Порядок звёзд в созвездии (ALG-MAP-17, F-MAP-17) -------------------

def members_of(labels):
    """Номера книг каждой группы по возрастанию; группы — по номеру."""
    out = {}
    for key in sorted(set(labels)):
        out[key] = [i for i, label in enumerate(labels) if label == key]
    return out


def typicalities(g, labels):
    """Косинус строки книги со средним группы — по матрице Грама.

    s_i — сумма G[i][j] по книгам группы, S — сумма s_i; косинус со
    средним равен s_i / √S. Складываем по возрастанию номера.
    """
    out = [0.0] * len(labels)
    for group in members_of(labels).values():
        sums = []
        total = 0.0
        for i in group:
            value = 0.0
            for j in group:
                value += g[i][j]
            sums.append(value)
            total += value
        if not total > 0.0:
            continue
        length = math.sqrt(total)
        for i, value in zip(group, sums):
            out[i] = value / length
    return out


def from_center(xs, ys, group):
    """Точки группы от центра к краю; при равенстве — выше, левее."""
    sum_x = 0.0
    sum_y = 0.0
    for i in group:
        sum_x += xs[i]
        sum_y += ys[i]
    cx = sum_x / len(group)
    cy = sum_y / len(group)
    far = {i: (xs[i] - cx) * (xs[i] - cx) + (ys[i] - cy) * (ys[i] - cy)
           for i in group}
    return sorted(group, key=lambda i: (far[i], ys[i], xs[i], i))


def order_within_groups(xs, ys, typical, labels):
    """Типичная книга — на точку ближе к центру группы, особенная — на край."""
    new_x = [0.0] * len(labels)
    new_y = [0.0] * len(labels)
    for group in members_of(labels).values():
        spots = from_center(xs, ys, group)
        books = sorted(group, key=lambda i: (-typical[i], i))
        for book, spot in zip(books, spots):
            new_x[book] = xs[spot]
            new_y[book] = ys[spot]
    return new_x, new_y


def stable_hash(text):
    """FNV-1a, 32 бита, по знакам строки — как `stableHash` в Dart."""
    value = 0x811C9DC5
    for char in text:
        code = ord(char)
        value = ((value ^ (code & 0xFFFF)) * 16777619) & MASK
        if code > 0xFFFF:
            value = ((value ^ ((code >> 16) & 0xFFFF)) * 16777619) & MASK
    return value


def fingerprint(books, xs, ys):
    """Отпечаток карты: по нему две карты сверяют глазами."""
    text = ''
    for book, x, y in zip(books, xs, ys):
        text += '%s:%d:%d\n' % (book['key'], quantum(x), quantum(y))
    return '%08x' % stable_hash(text)


def quantum(value):
    """Координата целым числом миллионных; половина — от нуля."""
    scaled = value * 1000000.0
    if scaled >= 0.0:
        return int(math.floor(scaled + 0.5))
    return -int(math.floor(-scaled + 0.5))


def build(books):
    books = restrict_untrusted(sorted(books, key=lambda book: book['key']))
    kept, df = vocabulary(books)
    rows, idf = bm25_rows(books, kept, df)
    g = gram(rows)
    components, values = latent(g)
    near, sims = neighbours(components)
    edges = edges_of(near, sims)
    _, measure, cohesions = art_categories(g)
    categories, reasons = trusted_categories(
        g, [book.get('trust') for book in books],
    )
    names = constellation_names(books, kept, categories)
    typical = typicalities(g, categories)
    if len(books) >= MIN_MAP_BOOKS:
        placed_x, placed_y = layout(
            components, edges, [group_of(c) for c in categories],
        )
        xs, ys = order_within_groups(placed_x, placed_y, typical, categories)
    else:
        placed_x, placed_y, xs, ys = [], [], [], []
    return {
        'books': books,
        'vocabulary': kept,
        'idf': idf,
        'rows': rows,
        'gram': g,
        'values': values,
        'neighbours': near,
        'edges': edges,
        'categories': categories,
        'reasons': reasons,
        'measure': measure,
        'cohesions': cohesions,
        'names': names,
        'typical': typical,
        'placed_x': placed_x,
        'placed_y': placed_y,
        'xs': xs,
        'ys': ys,
    }


# --- Досадка новой книги (ALG-MAP-08, D-049) -----------------------------
#
# Та же логика, что в lib/domain/map/map_seating.dart, и тот же порядок
# сложений: прежние точки — как есть, новая книга — в старое созвездие,
# если оно её принимает, место — среднее мест старых соседей с весом
# сходства, сдвиг от отпечатка файла, раздвигаются только новые.

SEAT_SHARE = 4


def seat_measure(g, hi):
    n = len(g)
    if len(hi) == n:
        return library_measure(g)
    return library_measure([[g[a][b] for b in hi] for a in hi])


def seat_spot(g_sims, i, old, labels, label, xs, ys):
    n = len(old)
    candidates = [j for j in range(n)
                  if old[j] and (label < 0 or labels[j] == label)]
    if not candidates:
        candidates = [j for j in range(n) if old[j]]
    near = [j for j in candidates if g_sims[i][j] > 0.0]
    near.sort(key=lambda j: (-g_sims[i][j], j))
    used = near[:NEIGHBOURS]
    if used:
        weight = 0.0
        x = 0.0
        y = 0.0
        for j in used:
            w = g_sims[i][j]
            weight += w
            x += w * xs[j]
            y += w * ys[j]
        xs[i] = x / weight
        ys[i] = y / weight
        return
    x = 0.0
    y = 0.0
    for j in candidates:
        x += xs[j]
        y += ys[j]
    xs[i] = x / len(candidates)
    ys[i] = y / len(candidates)


def seat_spread(xs, ys, old, fresh, gap):
    n = len(xs)
    if n > SPREAD_LIMIT:
        return
    for _ in range(SPREAD_ROUNDS):
        moved = False
        for i in fresh:
            for j in range(n):
                if j == i or (not old[j] and j < i):
                    continue
                dx = xs[j] - xs[i]
                dy = ys[j] - ys[i]
                d2 = dx * dx + dy * dy
                if d2 >= gap * gap:
                    continue
                moved = True
                d = 0.0
                ux = 1.0
                uy = 0.0
                if d2 > 0.0:
                    d = math.sqrt(d2)
                    ux = dx / d
                    uy = dy / d
                if old[j]:
                    push = gap - d
                    xs[i] -= ux * push
                    ys[i] -= uy * push
                else:
                    push = (gap - d) * 0.5
                    xs[i] -= ux * push
                    ys[i] -= uy * push
                    xs[j] += ux * push
                    ys[j] += uy * push
        if not moved:
            break


def unit_clamp(value):
    if value > 1.0:
        return 1.0
    if value < -1.0:
        return -1.0
    return value


def seat(books, kept):
    """Досадка: `kept` — отпечаток файла → прежняя точка (x, y, созвездие,
    имя). Возвращает точки всех книг по возрастанию отпечатка."""
    books = restrict_untrusted(sorted(books, key=lambda book: book['key']))
    kept_words, df = vocabulary(books)
    rows, _ = bm25_rows(books, kept_words, df)
    g = gram(rows)
    components, _ = latent(g)
    _, sims = neighbours(components)
    n = len(books)
    old = [book['key'] in kept for book in books]
    labels = [-1] * n
    canon_of = {}
    original = []
    names = {}
    xs = [0.0] * n
    ys = [0.0] * n
    for i in range(n):
        if not old[i]:
            continue
        point = kept[books[i]['key']]
        xs[i] = point['x']
        ys[i] = point['y']
        c = point['constellation']
        if c >= 0:
            if c not in canon_of:
                original.append(c)
                canon_of[c] = len(original) - 1
            labels[i] = canon_of[c]
            names.setdefault(c, point['name'])
    trusts = [book.get('trust') for book in books]
    hi = builders_of(trusts)
    c0 = seat_measure(g, hi)
    cats = Cats.of(g, labels, c0, ART_PHI * c0)
    building = set(hi)
    fresh = [i for i in range(n) if not old[i]]
    joined = list(labels)
    reasons = ['none'] * n
    gap = GAP_SHARE / math.sqrt(float(n))
    for i in fresh:
        if trusts[i] == 'little':
            reasons[i] = 'littleText'
        elif g[i][i] > 0.0:
            if i in building:
                chosen = art_choose(cats, i)
            else:
                placed = place(g, i, labels, c0, trusts[i] or 0.0)
                chosen = None if placed < 0 else placed
            if chosen is not None:
                joined[i] = chosen
            else:
                reasons[i] = 'awaiting' if i in building else 'unsure'
        seat_spot(sims, i, old, labels, joined[i], xs, ys)
        rng = Mulberry(stable_hash(books[i]['key']))
        xs[i] += (rng.unit() * 2.0 - 1.0) * gap * 0.5
        ys[i] += (rng.unit() * 2.0 - 1.0) * gap * 0.5
    seat_spread(xs, ys, old, fresh, gap)
    points = []
    for i in range(n):
        key = books[i]['key']
        if old[i]:
            point = kept[key]
            points.append({
                'key': key, 'x': point['x'], 'y': point['y'],
                'constellation': point['constellation'],
                'name': point['name'], 'reason': point.get('reason', 'none'),
                'seated': False,
            })
            continue
        label = joined[i]
        points.append({
            'key': key,
            'x': unit_clamp(xs[i]),
            'y': unit_clamp(ys[i]),
            'constellation': -1 if label < 0 else original[label],
            'name': '' if label < 0 else names[original[label]],
            'reason': reasons[i],
            'seated': True,
        })
    return points


def seating_case(books):
    """Карта без трёх книг, затем досадка этих трёх к ней."""
    added = ['hash-07', 'hash-12', 'hash-lone']
    before_books = [book for book in books if book['key'] not in added]
    before = build(before_books)
    kept = {}
    for i, book in enumerate(before['books']):
        c = before['categories'][i]
        kept[book['key']] = {
            'x': before['xs'][i],
            'y': before['ys'][i],
            'constellation': c,
            'name': '' if c < 0 else before['names'][c],
            'reason': before['reasons'][i],
        }
    points = seat(books, kept)
    return {
        'added': added,
        'before': [
            [key, kept[key]['x'], kept[key]['y'],
             kept[key]['constellation'], kept[key]['name']]
            for key in sorted(kept)
        ],
        'points': [
            [p['key'], p['x'], p['y'], p['constellation'], p['name'],
             p['reason'], p['seated']]
            for p in points
        ],
        'fingerprint': '%08x' % stable_hash(''.join(
            '%s:%d:%d\n' % (p['key'], quantum(p['x']), quantum(p['y']))
            for p in points
        )),
    }


# --- Корпус эталона -------------------------------------------------------

def golden_corpus():
    """Четырнадцать придуманных книг в трёх группах, скан и одиночка.

    Слова — условные: общие для всех книг, свои у группы, свои у темы
    внутри группы и свои у книги. Счёт слов даёт тот же генератор, что
    и раскладку: корпус не зависит от версии Python.
    """
    rng = Mulberry(7)
    groups = [
        ('Ангиология', ['артерии', 'вены']),
        ('Математика', ['анализ', 'алгебра']),
        ('', ['разное']),
    ]
    common = ['общее%02d' % i for i in range(12)]
    books = []
    number = 0
    for group, topics in groups:
        tag = group[:3].lower() if group else 'без'
        shared = ['%s%02d' % (tag, i) for i in range(14)]
        for topic in topics:
            themed = ['%s%02d' % (topic, i) for i in range(10)]
            count = 3 if group else 2
            for _ in range(count):
                own = ['книга%02d_%d' % (number, i) for i in range(6)]
                counts = {}

                def draw(words, times):
                    for _ in range(times):
                        share = rng.unit()
                        place = int(len(words) * share * share)
                        word = words[place]
                        counts[word] = counts.get(word, 0) + 1

                draw(common, 60)
                draw(shared, 50)
                draw(themed, 40)
                draw(own, 20)
                # Немного чужих слов: без них группы не связаны вовсе.
                other = groups[rng.below(len(groups))]
                other_tag = other[0][:3].lower() if other[0] else 'без'
                draw(['%s%02d' % (other_tag, i) for i in range(14)], 6)
                terms = sorted(counts.items())
                length = 0
                for _, value in terms:
                    length += value
                books.append({
                    'key': 'hash-%02d' % ((number * 7) % 17),
                    'group': group,
                    'terms': [[term, value] for term, value in terms],
                    'length': length,
                })
                number += 1
    # Скан без единого слова и книга из одних редких слов.
    books.append({
        'key': 'hash-scan', 'group': 'Ангиология', 'terms': [], 'length': 0,
    })
    books.append({
        'key': 'hash-lone',
        'group': '',
        'terms': [['одиночка%d' % i, 3] for i in range(5)],
        'length': 15,
    })
    return books


def art_cases():
    """Малые наборы для правила созвездий: порядок поступления и закрепление.

    Шесть тем по четыре книги; у книги слова своей темы и немного общих.
    Разметка после повтора одна при любом порядке поступления; книга,
    закреплённая читателем в чужой теме, остаётся там.
    """
    rng = Mulberry(45)
    books = []
    for topic in range(6):
        for copy in range(4):
            counts = {}
            for _ in range(80):
                share = rng.unit()
                word = 'тема%d_%02d' % (topic, int(12 * share * share))
                counts[word] = counts.get(word, 0) + 1
            for _ in range(20):
                word = 'общее%02d' % rng.below(10)
                counts[word] = counts.get(word, 0) + 1
            terms = sorted(counts.items())
            length = 0
            for _, value in terms:
                length += value
            books.append({
                'key': 'art-%d-%d' % (topic, copy),
                'group': '',
                'terms': [[term, value] for term, value in terms],
                'length': length,
            })
    books.sort(key=lambda book: book['key'])
    kept, df = vocabulary(books)
    rows, _ = bm25_rows(books, kept, df)
    g = gram(rows)
    n = len(books)
    orders = [list(range(n)), list(range(n - 1, -1, -1))]
    shuffle = Mulberry(7)
    for _ in range(3):
        order = list(range(n))
        for i in range(n - 1, 0, -1):
            j = shuffle.below(i + 1)
            order[i], order[j] = order[j], order[i]
        orders.append(order)
    pinned = {0: 1, 5: 1}
    return {
        'books': books,
        'c0': library_measure(g),
        'orders': orders,
        'labels': [art_categories(g, order=o)[0] for o in orders],
        'cohesions': art_categories(g)[2],
        'pinned': [[i, group] for i, group in sorted(pinned.items())],
        'pinnedLabels': art_categories(g, pinned=pinned)[0],
    }


def trust_cases():
    """Набор для доверия тексту (F-MAP-18): три темы по четыре книги и
    три книги с ненадёжным текстом — шумная копия темы 0 (T 0,55),
    смесь тем 1 и 2 (T 0,6) и книга без надёжного текста (только слова
    «названия»). Ждём: шумная встаёт в свою тему, смесь — «не уверены»,
    третья — «мало надёжного текста»; своих созвездий никто не заводит.
    """
    rng = Mulberry(58)

    def draw(counts, words, times):
        for _ in range(times):
            share = rng.unit()
            word = words[int(len(words) * share * share)]
            counts[word] = counts.get(word, 0) + 1

    def book(key, counts, trust):
        terms = sorted(counts.items())
        return {
            'key': key, 'group': '',
            'terms': [[t, c] for t, c in terms],
            'length': sum(c for _, c in terms), 'trust': trust,
        }

    topics = [['тема%d_%02d' % (t, i) for i in range(12)] for t in range(3)]
    common = ['общее%02d' % i for i in range(10)]
    books = []
    for t in range(3):
        for k in range(4):
            counts = {}
            draw(counts, topics[t], 80)
            draw(counts, common, 20)
            books.append(book('tr-%d-%d' % (t, k), counts, None))
    noisy = {}
    draw(noisy, topics[0], 60)
    draw(noisy, ['шум%02d' % i for i in range(30)], 40)
    books.append(book('tr-noisy', noisy, 0.55))
    mixed = {}
    draw(mixed, topics[1], 40)
    draw(mixed, topics[2], 40)
    draw(mixed, common, 20)
    books.append(book('tr-mixed', mixed, 0.6))
    little = {}
    draw(little, topics[2], 6)
    books.append(book('tr-little', little, 'little'))
    result = build(books)
    return {
        # Мешки — исходные, до отсева слов: отсев проверяется в Dart.
        'books': sorted(books, key=lambda b: b['key']),
        'kept': [len(b['terms']) for b in result['books']],
        'categories': result['categories'],
        'reasons': result['reasons'],
        'points': [[x, y] for x, y in zip(result['xs'], result['ys'])],
        'fingerprint': fingerprint(result['books'], result['xs'], result['ys']),
    }


def main():
    books = golden_corpus()
    result = build(books)
    logs = [0.5, 1.0, 1.5, 2.0, 3.0, 10.0, 12.25, 0.001, 123456.789]
    rng = Mulberry(SEED)
    data = {
        'comment': 'Посчитано tool/make_map_goldens.py — не править руками.',
        'random': {'seed': SEED, 'first': [rng.next() for _ in range(8)]},
        'ln': [[x, ln_exact(x)] for x in logs],
        'books': books,
        'order': [book['key'] for book in result['books']],
        'vocabulary': result['vocabulary'],
        'idf': result['idf'],
        'rows': [[[i, w] for i, w in row] for row in result['rows']],
        'gram': result['gram'],
        'values': result['values'],
        'neighbours': result['neighbours'],
        'edges': [[i, j, w] for i, j, w in result['edges']],
        'categories': result['categories'],
        'measure': result['measure'],
        'cohesions': result['cohesions'],
        'names': result['names'],
        'art': art_cases(),
        'trusted': trust_cases(),
        'typical': result['typical'],
        'placed': [
            [x, y] for x, y in zip(result['placed_x'], result['placed_y'])
        ],
        'points': [[x, y] for x, y in zip(result['xs'], result['ys'])],
        'fingerprint': fingerprint(
            result['books'], result['xs'], result['ys'],
        ),        'seating': seating_case(books),
    }
    for x, value in data['ln']:
        assert abs(value - math.log(x)) < 1e-13, (x, value)
    path = pathlib.Path(__file__).resolve().parent.parent
    path = path / 'test' / 'goldens' / 'book_map.json'
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=1) + '\n',
        encoding='utf-8',
    )
    print('книг %d, слов %d, рёбер %d, отпечаток %s' % (
        len(books),
        len(result['vocabulary']),
        len(result['edges']),
        data['fingerprint'],
    ))


if __name__ == '__main__':
    main()
