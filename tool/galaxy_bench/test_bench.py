"""Тесты стенда «Галактики» (ALG-MAP-20, S61).

Проверяют линейку, а не сортировку: если линейка врёт, все числа вехи В2 врут.
- сравнение с идеалом: «верно», «допустимо», «неподходящая», «без темы»; вторая группа
  той же темы — ошибка (тема «рассыпана»); ARI и NMI сверены с scikit-learn;
- отбор набора: один и тот же при любом порядке строк описи, дубль файла — один раз;
- тест утечки: книга под другим именем в другой папке даёт тот же кэш до байта —
  значит, расчёт после кэша имени файла и папки не видит.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
Нужны PyMuPDF, SciPy, wordfreq (scikit-learn — по желанию, для сверки ARI).
"""
import csv
import json
import os
import random
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bench  # noqa: E402
import extract_edges  # noqa: E402
import probe_library  # noqa: E402
import select_set  # noqa: E402

FIXTURES = os.path.join(HERE, '..', '..', 'test', 'fixtures')


def ideal_row(fp, n, topic, allowed='', untopic_ok='нет'):
    return {'fp': fp, 'n': str(n), 'название': fp, 'тема': topic,
            'допустимые': allowed, 'без_темы_ок': untopic_ok}


class CompareWithIdeal(unittest.TestCase):
    def setUp(self):
        rows = [ideal_row('a1', 1, 'Анатомия'), ideal_row('a2', 2, 'Анатомия'),
                ideal_row('a3', 3, 'Анатомия', 'Гистология'),
                ideal_row('h1', 4, 'Гистология'), ideal_row('h2', 5, 'Гистология'),
                ideal_row('r1', 6, 'История', untopic_ok='да'),
                ideal_row('m1', 7, 'Медицина')]
        self.ideal = {r['fp']: r for r in rows}

    def outcomes(self, groups):
        result = [{'fp': fp, 'группа': g} for fp, g in groups.items()]
        return bench.score(self.ideal, result, strict=True)[1]

    def test_alg_map_20_exact_match_is_correct(self):
        """ALG-MAP-20: группы совпали с темами — все книги «верно», редкая без темы — «допустимо»."""
        out = self.outcomes({'a1': '0', 'a2': '0', 'a3': '0', 'h1': '1', 'h2': '1',
                             'r1': '-1', 'm1': '2'})
        self.assertEqual([out[b] for b in ('a1', 'a2', 'a3', 'h1', 'h2', 'm1')], ['верно'] * 6)
        self.assertEqual(out['r1'], 'допустимо')

    def test_alg_map_20_neighbour_topic_is_allowed(self):
        """ALG-MAP-20: книга в соседней теме из идеала — «допустимо», в чужой — «неподходящая»."""
        out = self.outcomes({'a1': '0', 'a2': '0', 'a3': '1', 'h1': '1', 'h2': '1',
                             'r1': '-1', 'm1': '1'})
        self.assertEqual(out['a3'], 'допустимо')
        self.assertEqual(out['m1'], 'неподходящая')

    def test_alg_map_20_split_topic_is_an_error(self):
        """ALG-MAP-20: вторая группа той же темы при строгом сопоставлении — ошибка, а не «верно»."""
        out = self.outcomes({'a1': '0', 'a2': '0', 'a3': '5', 'h1': '1', 'h2': '1',
                             'r1': '-1', 'm1': '2'})
        self.assertEqual(out['a3'], 'неподходящая')
        self.assertEqual(out['a1'], 'верно')

    def test_alg_map_20_no_topic_where_ideal_knows_it(self):
        """ALG-MAP-20: «без темы» там, где идеал тему знает, — исход «без темы»."""
        out = self.outcomes({'a1': '0', 'a2': '0', 'a3': '0', 'h1': '-1', 'h2': '1',
                             'r1': '-1', 'm1': '2'})
        self.assertEqual(out['h1'], 'без темы')

    def test_alg_map_20_ari_nmi_known_values(self):
        """ALG-MAP-20: ARI и NMI — 1 для одинаковых разбиений и совпадают с scikit-learn."""
        a = ['x', 'x', 'x', 'y', 'y', 'z', 'z', 'z']
        b = ['1', '1', '2', '2', '2', '3', '3', '1']
        self.assertAlmostEqual(bench.ari(a, a), 1.0)
        self.assertAlmostEqual(bench.nmi(a, a), 1.0)
        try:
            from sklearn.metrics import adjusted_rand_score, normalized_mutual_info_score
        except ImportError:
            self.skipTest('нет scikit-learn')
        self.assertAlmostEqual(bench.ari(a, b), adjusted_rand_score(a, b), places=12)
        self.assertAlmostEqual(bench.nmi(a, b), normalized_mutual_info_score(a, b), places=12)

    def test_alg_map_20_sections_one_constellation_per_section(self):
        """ALG-MAP-20 (S68): разделы — внутри темы созвездие = раздел один к одному; книга
        с неверной темой не меряется; второе созвездие того же раздела — ошибка."""
        sec = {'a1': 'кости', 'a2': 'кости', 'a3': 'мышцы', 'h1': 'ткани', 'h2': 'ткани', 'm1': 'хирургия'}
        for b, s in sec.items():
            self.ideal[b]['раздел'] = s
        self.ideal['r1']['раздел'] = 'медицина'
        groups = {'a1': '0', 'a2': '0', 'a3': '0', 'h1': '1', 'h2': '1', 'r1': '-1', 'm1': '0'}
        cons = {'a1': 'Остеология', 'a2': 'Остеология', 'a3': 'Миология',
                'h1': 'Ткани', 'h2': 'Ткани плюс', 'r1': '', 'm1': 'Хирургия'}
        result = [{'fp': b, 'группа': g, 'созвездие': cons[b]} for b, g in groups.items()]
        _, out, _ = bench.score(self.ideal, result, strict=True)
        hit, by_topic, _ = bench.sections(self.ideal, result, out)
        self.assertEqual(out['m1'], 'неподходящая')
        self.assertNotIn('m1', hit)                      # чужая тема — вне мерки
        self.assertEqual(sorted(by_topic), ['Анатомия', 'Гистология'])
        self.assertEqual([hit[b] for b in ('a1', 'a2', 'a3')], [True, True, True])
        self.assertEqual(sorted(hit[b] for b in ('h1', 'h2')), [False, True])  # «ткани» рассыпаны


class SelectSet(unittest.TestCase):
    def inventory(self):
        rows, rnd = [], random.Random(7)
        for cat in select_set.BIG + select_set.RARE:
            for i in range(12):
                cyr = rnd.choice([0, 5000])
                rows.append(dict(fp=f'{cat[:3]}{i:02d}{rnd.randrange(999):03d}', category=cat,
                                 path=f'D:/{cat}/{i}.pdf', pages=rnd.choice([90, 400, 900]),
                                 edge_chars=rnd.choice([500, 50000]), cyr=cyr, lat=5000 - cyr,
                                 ru_ok=rnd.random(), en_ok=rnd.random()))
        rows.append(dict(rows[0], category='Медицина', path='D:/Медицина/копия.pdf'))
        return rows

    def run_select(self, rows, folder):
        src, dst = os.path.join(folder, 'опись.csv'), os.path.join(folder, 'набор.csv')
        with open(src, 'w', encoding='utf-8', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)
        select_set.main(src, dst)
        return [r['fp'] for r in csv.DictReader(open(dst, encoding='utf-8'))]

    def test_alg_map_20_selection_is_deterministic(self):
        """ALG-MAP-20: набор не зависит от порядка строк описи; дубль файла берётся один раз; 100 книг."""
        rows = self.inventory()
        with tempfile.TemporaryDirectory() as tmp:
            first = self.run_select(rows, tmp)
            shuffled = rows[:]
            random.Random(1).shuffle(shuffled)
            second = self.run_select(shuffled, tmp)
        self.assertEqual(len(first), 100)
        self.assertEqual(len(set(first)), 100)
        self.assertEqual(sorted(first), sorted(second))


class Leak(unittest.TestCase):
    def test_alg_map_20_renamed_books_give_same_cache(self):
        """ALG-MAP-20: тест утечки — три книги под случайными именами в другой папке дают тот же кэш до байта."""
        names = ['basic_text.pdf', 'book_120_pages.pdf', 'hyphen_breaks.pdf']
        with tempfile.TemporaryDirectory() as tmp:
            caches = []
            for variant in ('как есть', 'переименованы'):
                folder = os.path.join(tmp, variant, 'другая папка' if variant != 'как есть' else '')
                os.makedirs(folder, exist_ok=True)
                rows = []
                for name in names:
                    target = name if variant == 'как есть' else f'{random.random():.8f}.pdf'
                    path = os.path.join(folder, target)
                    shutil.copy(os.path.join(FIXTURES, name), path)
                    rows.append({'fp': probe_library.fingerprint(path), 'path': path})
                listing = os.path.join(tmp, variant + '.csv')
                with open(listing, 'w', encoding='utf-8', newline='') as f:
                    w = csv.DictWriter(f, fieldnames=['fp', 'path'])
                    w.writeheader()
                    w.writerows(rows)
                cache = os.path.join(tmp, 'кэш ' + variant)
                extract_edges.main(listing, cache, True)
                caches.append({fp: open(os.path.join(cache, kind, fp + '.json'), 'rb').read()
                               for fp in (r['fp'] for r in rows) for kind in ('края',)}
                              | {fp + '+': open(os.path.join(cache, 'полный', fp + '.json'), 'rb').read()
                                 for fp in (r['fp'] for r in rows)})
            self.assertEqual(caches[0], caches[1])
            for blob in caches[0].values():
                record = json.loads(blob)
                self.assertNotIn('path', record)
                for name in names:
                    self.assertNotIn(name.encode('utf-8'), blob)


if __name__ == '__main__':
    unittest.main()
