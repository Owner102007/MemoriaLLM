"""Стенд «Галактики» (S69): итоговый отчёт вехи В2 — 10 мерок конечного результата цикла.

Что это. Цикл сортировки задал 10 мерок с целями (`Материалы/Цикл сортировки Галактики/
Цикл разработки и конечный результат.md`, раздел 5). Этот файл собирает их в одну таблицу:
число, цель, достигнута ли. Мерки 1–7 считаются теми же функциями, что обычный отчёт
(`bench.py`); мерка 8 — по паспортам (сколько страниц прочитано) и по замеру времени;
мерка 9 — тест утечки, повтор прогона и устойчивость; мерка 10 — оценка владельца.

Устойчивость (мерка 9, «+10 книг вне набора меняют тему ≤ 1 книги набора»). Других книг,
кроме набора и библиотеки, у стенда нет, поэтому опыт обратный: из библиотеки убираются
10 книг, и темы книг набора сравниваются с полным прогоном. Книги выбираются по хэшу
(sha1 от «выборка:отпечаток»), не случайно, — опыт повторяется один в один. Темы могут
сдвинуться: из обучения выбрасываются тексты tgpathfinder, совпавшие с книгами библиотеки
(S67), а созвездия считаются по всей библиотеке (S68).

Кто зовёт. Владелец или Claude после `universal.py` и `constellations.py`.

Запуск (из папки MemoriaLLM):
  python tool/galaxy_bench/final.py выборки <обучение-все.csv> <папка> [книг=10] [выборок=3]
      → <папка>/библиотека-без-<i>.csv — библиотеки без 10 книг (для прогонов устойчивости)
  python tool/galaxy_bench/final.py время <набор.csv> <время.csv>
      → секунды на книгу без OCR: открыть PDF, края, паспорт (кэш стенда не пишется)
  python tool/galaxy_bench/final.py отчёт <идеал.csv> <набор.csv> <результат-С.csv> <кэш стенда> <отчёт.md>
      [--повтор <результат-С.csv>] [--устойчивость <результат-С.csv> …] [--время <время.csv>] [--ocr <ocr.log>]
"""
import argparse
import collections
import csv
import hashlib
import json
import os
import re
import statistics
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bench as B  # noqa: E402

WORST_LAYERS = ['качество скан', 'качество шумный', 'язык en', 'вид атлас']  # «худший слой» цикла
RARE = 2  # тема идеала из ≤ 2 книг — редкая (мерка 6)


def drop_sample(lib_rows, k, seed):
    """Библиотека без k книг выборки seed. Книги — с наименьшим sha1(«seed:fp»): без случайности.

    Возвращает (оставшиеся строки, убранные отпечатки).
    """
    key = lambda r: hashlib.sha1(f'{seed}:{r["fp"]}'.encode()).hexdigest()
    gone = {r['fp'] for r in sorted(lib_rows, key=key)[:k]}
    return [r for r in lib_rows if r['fp'] not in gone], gone


def changes(base, other, fps):
    """Сколько книг fps сменили тему каркаса и сколько — созвездие (base, other — строки результат-С)."""
    a, b = {r['fp']: r for r in base}, {r['fp']: r for r in other}
    topic = sorted(f for f in fps if a[f]['тема каркаса'] != b[f]['тема каркаса'])
    cons = sorted(f for f in fps if a[f].get('созвездие') != b[f].get('созвездие'))
    return topic, cons


def ocr_seconds(path):
    """Секунды OCR на книгу из журнала `ocr.log` («№ 95: OCR 16 стр., 6.0 с, …»)."""
    text = open(path, 'rb').read().decode('utf-8', errors='replace')
    return [float(x) for x in re.findall(r'OCR \d+ \S+ (\d+(?:\.\d+)?) с', text)]


def leak_test_green():
    """Мерка 9: тест утечки из `test_bench.py` — зелёный ли сейчас."""
    import test_bench
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(test_bench.Leak)
    return unittest.TextTestRunner(stream=open(os.devnull, 'w'), verbosity=0).run(suite).wasSuccessful()


def measures(ideal, layer, result, passports, repeat=None, stable=None, seconds=None, ocr=None, leak=None):
    """10 мерок → [(№, мерка, что вышло, цель, достигнута: True / False / None — решает владелец)].

    ideal, layer — строки идеала и набора по отпечатку; result — строки результат-С;
    passports — паспорта книг набора (поле read — прочитано страниц);
    repeat — строки повторного прогона; stable — [строки прогонов без 10 книг];
    seconds — {n: секунд без OCR}; ocr — [секунд OCR на книгу]; leak — тест утечки зелёный ли.
    """
    mapping, out, groups_of = B.score(ideal, result, strict=True)
    tally = collections.Counter(out.values())
    good = tally['верно'] + tally['допустимо']
    rows = []
    # 1. Верно, и в каждой теме ≥ 85 %
    by_topic = collections.defaultdict(list)
    for b in out:
        by_topic[ideal[b]['тема']].append(b)
    share = {t: sum(out[b] == 'верно' for b in bs) / len(bs) for t, bs in by_topic.items()}
    weak = sorted((t for t in share if share[t] < 0.85), key=lambda t: share[t])
    rows.append((1, 'Верно (тема = идеал)',
                 f'{tally["верно"]} из {len(out)}; тем ниже 85 %: {len(weak)} из {len(share)}'
                 + (f' (хуже всех: {", ".join(f"{t} {round(100 * share[t])} %" for t in weak[:3])})' if weak else ''),
                 '≥ 90, в каждой теме ≥ 85 %', tally['верно'] >= 90 and not weak))
    rows.append((2, 'Верно + допустимо', f'{good}', '≥ 95', good >= 95))
    rows.append((3, 'Неподходящая тема', f'{tally["неподходящая"]}', '≤ 3', tally['неподходящая'] <= 3))
    rows.append((4, 'Без темы там, где идеал её знает', f'{tally["без темы"]}', '≤ 5', tally['без темы'] <= 5))
    # 5. Худший слой — доля «верно»
    ly = collections.defaultdict(lambda: [0, 0])
    for b in out:
        for k in B.layers_of(layer[b], ideal[b]):
            ly[k][0] += 1
            ly[k][1] += out[b] == 'верно'
    parts = [f'{k.split()[1]} {ly[k][1]} из {ly[k][0]}' for k in WORST_LAYERS if ly[k][0]]
    rows.append((5, 'Худший слой (сканы, шумное OCR, английские, атласы) — верно', '; '.join(parts), '≥ 80 % каждого слоя',
                 all(ly[k][1] >= 0.8 * ly[k][0] for k in WORST_LAYERS if ly[k][0])))
    # 6. Строение: 0 слитых; книги редких тем не втянуты в большие
    st = B.structure(ideal, out, groups_of, {r['группа']: r.get('имя', '') for r in result}, mapping)
    rare = [b for t, bs in by_topic.items() if len(bs) <= RARE for b in bs]
    pulled = [b for b in rare if out[b] not in B.GOOD]
    rows.append((6, 'Строение', f'слитых групп {len(st["merged"])}, рассыпанных тем {len(st["split"])}; '
                 f'книг редких тем втянуто {len(pulled)} из {len(rare)}', '0 слитых; редкие не втянуты',
                 not st['merged'] and not pulled))
    # 7. Разделы
    if any(r.get('созвездие') for r in result):
        hit, _, _ = B.sections(ideal, result, out)
        k = sum(hit.values())
        rows.append((7, 'Разделы (созвездия)', f'{k} из {len(hit)} книг с верной темой ({round(100 * k / len(hit))} %); '
                     f'из всех — {k} из {len(out)}', '≥ 80 % книг', k >= 0.8 * len(hit)))
    # 8. Чтение
    read = [passports[b]['read'] for b in out if b in passports]
    text = f'страниц: больше всего {max(read)}, медиана {statistics.median(read):g}'
    ok = max(read) <= 40 and statistics.median(read) <= 30
    if seconds:
        s = list(seconds.values())
        text += f'; без OCR — медиана {statistics.median(s):.2f} с, > 1 с — {sum(x > 1 for x in s)} книг'
        ok = ok and max(s) <= 1
    if ocr:
        text += f'; с OCR ({len(ocr)} книг) — медиана {statistics.median(ocr):.1f} с, > 15 с — {sum(x > 15 for x in ocr)}'
        ok = ok and max(ocr) <= 15
    rows.append((8, 'Чтение', text, '≤ 40 страниц, медиана ≤ 30; ≤ 1 с без OCR, ≤ 15 с с OCR', ok))
    # 9. Подсказки и повторяемость
    fps = sorted(out)
    bits, ok = [], True
    if leak is not None:
        bits.append('тест утечки ' + ('зелёный' if leak else 'красный'))
        ok = ok and leak
    if repeat is not None:
        t, c = changes(result, repeat, fps)
        bits.append('повтор — ' + ('тот же' if not t and not c else f'другой ({len(t)} тем, {len(c)} созвездий)'))
        ok = ok and not t and not c
    if stable:
        moved = [changes(result, other, fps) for other in stable]
        worst_t, worst_c = max(len(t) for t, _ in moved), max(len(c) for _, c in moved)
        bits.append(f'без 10 книг библиотеки ({len(stable)} выборки): тему меняют до {worst_t}, созвездие — до {worst_c} книг набора')
        ok = ok and worst_t <= 1
    rows.append((9, 'Подсказки и повторяемость', '; '.join(bits) or '—', 'утечки нет; повтор тот же; +10 книг — тема ≤ 1 книги', ok))
    rows.append((10, 'Имена и приложение', 'имена — проверка владельцем (список созвездий); приложение — веха В3',
                 '≥ 80 % имён верны; версия расчёта 5 в приложении', None))
    return rows


def report(path, rows, title):
    mark = {True: 'да', False: 'нет', None: 'владелец'}
    L = [f'# Итог вехи В2 — {title}', '', f'Мерок достигнуто: {sum(r[4] is True for r in rows)} из {len(rows)}.', '',
         '| № | Мерка | Вышло | Цель | Достигнута |', '|---|---|---|---|---|']
    L += [f'| {n} | {name} | {got} | {goal} | {mark[ok]} |' for n, name, got, goal, ok in rows]
    open(path, 'w', encoding='utf-8').write('\n'.join(L) + '\n')


def timing(set_path, out_path):
    """Мерка 8: секунды на книгу без OCR — открыть PDF, края, крупные строки, паспорт (как `extract_edges` + `passport`)."""
    import fitz
    import extract_edges as E
    import passport as P
    with open(out_path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['n', 'fp', 'секунд'])
        for r in csv.DictReader(open(set_path, encoding='utf-8')):
            t = time.perf_counter()
            doc = fitz.open(r['path'])
            meta = doc.metadata or {}
            rec = dict(fp=r['fp'], pages=doc.page_count,
                       meta={k: (meta.get(k) or '') for k in ('title', 'author', 'subject', 'keywords')},
                       outline=[[lvl, name] for lvl, name, _ in doc.get_toc(simple=True)],
                       labels={str(i + 1): doc[i].get_label() for i in range(min(E.FIRST, doc.page_count))},
                       text=E.edges(doc),
                       big={str(i + 1): E.big_lines(doc[i]) for i in range(min(E.BIG_PAGES, doc.page_count))})
            doc.close()
            P.build(rec)
            w.writerow([r['n'], r['fp'], f'{time.perf_counter() - t:.3f}'])


def main(argv):
    if argv[0] == 'выборки':
        lib_path, out = argv[1], argv[2]
        k, n = (int(argv[3]) if len(argv) > 3 else 10), (int(argv[4]) if len(argv) > 4 else 3)
        rows = list(csv.DictReader(open(lib_path, encoding='utf-8')))
        os.makedirs(out, exist_ok=True)
        for i in range(1, n + 1):
            kept, gone = drop_sample(rows, k, i)
            with open(os.path.join(out, f'библиотека-без-{i}.csv'), 'w', encoding='utf-8', newline='') as f:
                w = csv.DictWriter(f, fieldnames=list(rows[0]))
                w.writeheader()
                w.writerows(kept)
            print(f'выборка {i}: убрано {len(gone)}, осталось {len(kept)}')
        return
    if argv[0] == 'время':
        timing(argv[1], argv[2])
        return
    ap = argparse.ArgumentParser()
    ap.add_argument('ideal')
    ap.add_argument('set')
    ap.add_argument('result')
    ap.add_argument('cache')
    ap.add_argument('report')
    ap.add_argument('--повтор', dest='repeat')
    ap.add_argument('--устойчивость', dest='stable', nargs='*', default=[])
    ap.add_argument('--время', dest='seconds')
    ap.add_argument('--ocr', dest='ocr')
    a = ap.parse_args(argv[1:])
    ideal = {r['fp']: r for r in B.load(a.ideal)}
    layer = {r['fp']: r for r in B.load(a.set)}
    passports = {}
    for fp in ideal:
        p = os.path.join(a.cache, 'паспорт', fp + '.json')
        if os.path.exists(p):
            passports[fp] = json.load(open(p, encoding='utf-8'))
    seconds = {r['n']: float(r['секунд']) for r in B.load(a.seconds)} if a.seconds else None
    rows = measures(ideal, layer, B.load(a.result), passports,
                    repeat=B.load(a.repeat) if a.repeat else None,
                    stable=[B.load(p) for p in a.stable], seconds=seconds,
                    ocr=ocr_seconds(a.ocr) if a.ocr else None, leak=leak_test_green())
    report(a.report, rows, a.result)
    for n, name, got, goal, ok in rows:
        print(n, name, '—', got, '|', goal, '|', ok)


if __name__ == '__main__':
    main(sys.argv[1:])
