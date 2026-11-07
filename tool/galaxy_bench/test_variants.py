"""Тесты соревнования схем сортировки (ALG-MAP-22, S63) и обучающей части стенда (ALG-MAP-20).

Проверяется то, от чего зависит честность чисел:
- коды каталога дают дисциплину по самому длинному префиксу, спор кодов — «без темы»;
- тома той же работы, что книга набора, не попадают в обучение (иначе утечка);
- учебные наборы собраны как набор стенда и одинаковы при каждом запуске;
- скопления не зависят от случайности, мелкие группы уходят в «без темы».

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import variants as V  # noqa: E402


class Codes(unittest.TestCase):
    def test_alg_map_22_code_longest_prefix(self):
        """ALG-MAP-22: УДК 611.018 — гистология, 611.1 — анатомия; NLM QS 504 — гистология, QS 4 — анатомия."""
        self.assertEqual(V.code_discipline([['УДК', '611.018(075.8)']]), 'Гистология')
        self.assertEqual(V.code_discipline([['УДК', '611.1']]), 'Анатомия')
        self.assertEqual(V.code_discipline([['NLM', 'QS 504']]), 'Гистология')
        self.assertEqual(V.code_discipline([['NLM', 'QS 4']]), 'Анатомия')
        self.assertEqual(V.code_discipline([['LC', 'QA76.73 .P98']]), 'Айти')

    def test_alg_map_22_codes_disagree_or_missing(self):
        """ALG-MAP-22: нет кодов или два кода спорят поровну — дисциплины нет; большинство побеждает."""
        self.assertEqual(V.code_discipline([]), '')
        self.assertEqual(V.code_discipline([['УДК', '612.1'], ['ББК', '24.1']]), '')
        self.assertEqual(V.code_discipline([['УДК', '612.1'], ['ББК', '28.707.3'], ['ББК', '24.1']]), 'Физиология')


class Training(unittest.TestCase):
    def test_alg_map_20_same_work_not_in_training(self):
        """ALG-MAP-20: другой том (то же начало названия), почти тот же паспорт и сама книга — не в обучении."""
        set_rows = [dict(fp='a', path=r'D:\Анатомия\Анатомия_00001.pdf')]
        train = [dict(fp='b', path=r'D:\Анатомия\Анатомия_00002.pdf'),
                 dict(fp='c', path=r'D:\Анатомия\Анатомия_00003.pdf'),
                 dict(fp='d', path=r'D:\Анатомия\Анатомия_00004.pdf'),
                 dict(fp='a', path=r'D:\Копии\Анатомия_00001.pdf')]
        titles = {'a': 'Атлас анатомии человека. Том 1', 'b': 'Атлас анатомии человека. Том 2',
                  'c': 'Анатомия для художников', 'd': 'Без названия'}
        kept, dropped = V.training_rows(train, set_rows, titles, near={2})
        self.assertEqual([r['fp'] for r in kept], ['c'])
        self.assertEqual(sorted(r['fp'] for r in dropped), ['a', 'b', 'd'])

    def test_alg_map_20_near_passports_and_work_groups(self):
        """ALG-MAP-20: почти одинаковые паспорта — одна работа; разные — разные работы."""
        from sklearn.feature_extraction.text import TfidfVectorizer
        texts = ['гистология эпителий хрящ кость', 'гистология эпителий хрящ кость кровь', 'python функции классы']
        X = TfidfVectorizer(norm='l2').fit_transform(texts)
        self.assertEqual(V.near_pairs(X[1:], X[:1]), {0})
        self.assertEqual(V.work_groups(['f1', 'f2', 'f3'], {}, X), ['f1', 'f1', 'f3'])

    def test_alg_map_22_pseudo_sets_like_bench_set(self):
        """ALG-MAP-22: учебный набор — по 8 книг крупной темы и по 1 редкой; повтор — те же книги."""
        rows = [dict(fp=f'{t}{i}', topic=t) for t in ('Анатомия', 'Айти') for i in range(12)]
        rows += [dict(fp=f'ф{i}', topic='Фармакология') for i in range(3)]
        first, again = V.pseudo_sets(rows, seeds=3), V.pseudo_sets(rows, seeds=3)
        self.assertEqual(first, again)
        self.assertEqual(len(first[0]), 8 + 8 + 1)
        self.assertNotEqual(first[0], first[1])


class Clusters(unittest.TestCase):
    def test_alg_map_22_cluster_threshold_and_small_groups(self):
        """ALG-MAP-22: две плотные кучки — две группы; одиночка при min_size=2 — «без темы» (−1)."""
        X = [[1, 0, 0], [0.95, 0.05, 0], [0.9, 0.1, 0], [0, 1, 0], [0.05, 0.95, 0], [0, 0, 1]]
        labels = V.cluster(X, tau=0.3, min_size=2)
        self.assertEqual(labels[0], labels[1])
        self.assertEqual(labels[0], labels[2])
        self.assertEqual(labels[3], labels[4])
        self.assertNotEqual(labels[0], labels[3])
        self.assertEqual(labels[5], -1)
        self.assertEqual(V.cluster(X, tau=0.3, min_size=2), labels)

    def test_alg_map_22_empty_passport_is_no_topic(self):
        """ALG-MAP-22: пустой паспорт (вектор из нулей) — «без темы», остальные книги группируются."""
        X = [[1, 0], [0.9, 0.1], [0, 0], [0, 1]]
        labels = V.cluster(X, tau=0.3)
        self.assertEqual(labels[2], -1)
        self.assertEqual(labels[0], labels[1])
        self.assertNotEqual(labels[0], labels[3])

    def test_alg_map_22_stems_join_word_forms(self):
        """ALG-MAP-22: основы из 6 букв сводят словоформы: «гистологии» и «гистология» — одна основа."""
        self.assertEqual(V.stems('Гистология гистологии ЁЖИК of'), ['гистол', 'гистол', 'ежик'])


if __name__ == '__main__':
    unittest.main()
