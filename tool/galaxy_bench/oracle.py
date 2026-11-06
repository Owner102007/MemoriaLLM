"""Стенд «Галактики» (S62): оракул — хватает ли паспорта, чтобы угадать тему (ALG-MAP-20, ALG-MAP-21).

Как устроено. Паспорта книг набора (`passport.text_of`) выкладываются под случайными номерами
(«К001» …), без папки, идеала и порядка набора — номера набора идут по категориям, это была бы
подсказка. Судья (человек или LLM) по одному паспорту ставит тему из закрытого списка или
«не понять». Этот скрипт сверяет ответы с идеалом: верно, допустимо (соседняя тема из идеала),
неверно, «не понять». Цель плана цикла: верно ≥ 95 %; иначе в бюджет чтения добавляются
страницы середины.

Запуск:
  python tool/galaxy_bench/oracle.py prepare <набор.csv> <паспорта> <папка оракула> [зерно]
  python tool/galaxy_bench/oracle.py score <идеал.csv> <папка оракула> [<отчёт.md>]
"""
import collections
import csv
import glob
import json
import os
import random
import sys

import passport

TOC_WORDS = 250


def prepare(set_path, passports, out, seed=20261106):
    """Паспорта под случайными номерами двумя файлами по 50 и ключ «номер → n набора»."""
    rows = list(csv.DictReader(open(set_path, encoding='utf-8')))
    ids = list(range(1, len(rows) + 1))
    random.Random(int(seed)).shuffle(ids)
    os.makedirs(out, exist_ok=True)
    half = len(rows) // 2
    files = {1: [], 2: []}
    for r, i in zip(rows, ids):
        p = json.load(open(os.path.join(passports, r['fp'] + '.json'), encoding='utf-8'))
        files[1 if i <= half else 2].append((i, passport.text_of(p, max_toc_words=TOC_WORDS)))
    for k, items in files.items():
        with open(os.path.join(out, f'паспорта-{k}.md'), 'w', encoding='utf-8') as f:
            for i, text in sorted(items):
                f.write(f'## Книга К{i:03d}\n{text}\n\n')
    with open(os.path.join(out, 'ключ.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(['id', 'n'])
        w.writerows(sorted((i, r['n']) for r, i in zip(rows, ids)))


def judge(answer, row):
    """Исход ответа оракула для строки идеала."""
    if answer in ('', 'не понять'):
        return 'не понять'
    if answer == row['тема']:
        return 'верно'
    allowed = [x.strip() for x in row['допустимые'].split(';') if x.strip()]
    return 'допустимо' if answer in allowed else 'неверно'


def score(ideal_path, folder, report=None):
    ideal = {r['n']: r for r in csv.DictReader(open(ideal_path, encoding='utf-8'))}
    key = {r['id']: r['n'] for r in csv.DictReader(open(os.path.join(folder, 'ключ.csv'), encoding='utf-8'))}
    answers = {}
    for path in sorted(glob.glob(os.path.join(folder, 'ответ-*.csv'))):
        for r in csv.DictReader(open(path, encoding='utf-8-sig')):
            answers[str(int(r['id'].strip().lstrip('КK')))] = r
    out = {n: judge(answers.get(i, {}).get('тема', '').strip(), ideal[n]) for i, n in key.items()}
    tally = collections.Counter(out.values())
    lines = ['# Оракул — тема по одному паспорту', '',
             f'Книг: {len(out)}; ответов: {len(answers)}.', '',
             '| Исход | Книг |', '|---|---|']
    lines += [f'| {k} | {tally[k]} |' for k in ('верно', 'допустимо', 'неверно', 'не понять')]
    lines += ['', '## Промахи', '', '| № | Книга | Тема идеала | Ответ оракула | Уверенность | Почему |', '|---|---|---|---|---|---|']
    back = {n: i for i, n in key.items()}
    for n in sorted(out, key=int):
        if out[n] in ('верно', 'допустимо'):
            continue
        a = answers.get(back[n], {})
        lines.append(f'| {n} | {ideal[n]["название"][:50]} | {ideal[n]["тема"]} | {a.get("тема", "—")} | '
                     f'{a.get("уверенность", "")} | {a.get("почему", "")[:80]} |')
    text = '\n'.join(lines) + '\n'
    if report:
        open(report, 'w', encoding='utf-8').write(text)
    print(f'верно {tally["верно"]}, допустимо {tally["допустимо"]}, неверно {tally["неверно"]}, '
          f'не понять {tally["не понять"]} из {len(out)}')
    return tally


if __name__ == '__main__':
    if sys.argv[1] == 'prepare':
        prepare(*sys.argv[2:6])
    else:
        score(*sys.argv[2:5])
