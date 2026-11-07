"""Тесты созвездий внутри тем (ALG-MAP-26, S68).

Проверяют правила раскладки на маленьких выдуманных паспортах:
- название весит больше оглавления, общий вес (w) уступает частному, совпадений на поле не больше 3;
- книга без совпадений идёт к созвездию похожих книг;
- мелкое созвездие распускается, его книги уходят ко второму по очкам;
- раскладка не зависит от порядка книг на входе; тема без словаря — одно созвездие с именем темы.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import constellations as C  # noqa: E402

ITEMS = [
    {'name': 'Миология', 'seeds': ['мышц', 'muscle']},
    {'name': 'Нейроанатомия', 'seeds': ['мозг', 'brain', 'спинн мозг']},
    {'name': 'Учебники анатомии', 'seeds': ['анатоми', 'anatom'], 'w': 0.3},
]


def pp(title, toc=''):
    return {'title': title, 'toc': toc, 'subjects': [], 'meta': {}, 'imprint_text': '', 'codes': []}


class Scores(unittest.TestCase):
    def test_alg_map_26_title_beats_toc_and_general_weight(self):
        """ALG-MAP-26: слово в названии ×3, в оглавлении ×0,3; «Учебники» с весом 0,3 уступают частному."""
        s = C.Index(ITEMS).scores(pp('Анатомия мышц', 'мозг мозг мозг мозг'))
        self.assertEqual(s, [30 * 10, 3 * 3 * 10, 30 * 3])  # мышцы 300, мозг (≤ 3 раза) 90, анатомия 90

    def test_alg_map_26_phrase_and_yo(self):
        """ALG-MAP-26: фраза из двух слов — ещё одно совпадение; «ё» читается как «е»."""
        idx = C.Index([{'name': 'Ёлки', 'seeds': ['ёлк']}] + ITEMS)
        s = idx.scores(pp('Ёлки и спинной мозг'))
        self.assertEqual(s[0], 300)
        self.assertEqual(s[2], 30 * 2 * 10)  # «мозг» + фраза «спинн мозг»


class Assign(unittest.TestCase):
    def books(self):
        p = {f'm{i}': pp(f'Мышцы том {i}') for i in range(3)}
        p.update({f'b{i}': pp(f'Мозг человека {i}') for i in range(3)})
        p['x'] = pp('Без единого совпадения', 'мышцы')  # оглавление 0,3 × 1 = 30 < 100
        return p

    def run_assign(self, p, order, min_size):
        import numpy as np
        vec = {f: np.array([1.0, 0.0]) if f.startswith('m') or f == 'x' else np.array([0.0, 1.0]) for f in p}
        X = np.array([vec[f] for f in order])
        return C.assign(order, p, ITEMS, X, min_size)

    def test_alg_map_26_no_hits_goes_to_neighbours(self):
        """ALG-MAP-26: книга без совпадений — к созвездию похожих на неё книг."""
        p = self.books()
        got = self.run_assign(p, sorted(p), 1)
        self.assertEqual(got['x'], (0, 'соседи'))
        self.assertEqual({got[f'b{i}'][0] for i in range(3)}, {1})

    def test_alg_map_26_small_constellation_dissolves(self):
        """ALG-MAP-26: созвездие меньше порога распускается — книги уходят ко второму по очкам."""
        p = self.books()
        p['b0'] = pp('Анатомия, анатомия: мозг')  # мозг 300, анатомия 2 × 90 = 180 — при роспуске уйдёт в «Учебники»
        p.update({f'u{i}': pp(f'Анатомия, анатомия {i}') for i in range(4)})  # «Учебники» — 4 книги
        got = self.run_assign(p, sorted(p), 4)
        self.assertEqual(got['b0'], (2, 'слова'))
        self.assertTrue(all(got[f][0] != 1 for f in p))

    def test_alg_map_26_order_does_not_matter(self):
        """ALG-MAP-26: раскладка одна и та же при любом порядке книг (вход сортируется по отпечатку)."""
        p = self.books()
        a = C.constellations({f: 'MED.ANAT' for f in p}, p, {'MED.ANAT': ITEMS}, 2)
        b = C.constellations({f: 'MED.ANAT' for f in reversed(sorted(p))}, dict(reversed(list(p.items()))),
                             {'MED.ANAT': ITEMS}, 2)
        self.assertEqual(a, b)

    def test_alg_map_26_topic_without_dictionary(self):
        """ALG-MAP-26: тема без списка — одно созвездие с именем темы; книга без темы — без созвездия."""
        p = {'a': pp('Linear algebra'), 'b': pp('Calculus'), 'c': pp('Ничего')}
        got = C.constellations({'a': 'MATH.MATH', 'b': 'MATH.MATH', 'c': None}, p, {}, 2)
        self.assertEqual(got['a'], ('Математика', 'тема'))
        self.assertEqual(got['c'], ('', 'нет темы'))

    def test_alg_map_26_dictionary_is_valid(self):
        """ALG-MAP-26: словарь — темы каркаса, у каждого созвездия имя и начала слов, вес 0 < w ≤ 1."""
        import taxonomy as T
        d = C.load_dictionary()
        for topic, items in d.items():
            self.assertIn(topic, T.TOPICS)
            names = [c['name'] for c in items]
            self.assertEqual(len(names), len(set(names)), topic)
            for c in items:
                self.assertTrue(c['name'] and c['seeds'], c)
                self.assertTrue(0 < c.get('w', 1.0) <= 1, c)
                self.assertTrue(all(s == s.lower() and 'ё' not in s for s in c['seeds']), c)


if __name__ == '__main__':
    unittest.main()
