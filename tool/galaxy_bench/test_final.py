"""Тесты итогового отчёта вехи В2 (ALG-MAP-20, S69).

Проверяют, что итоговая таблица честная:
- выборка «библиотека без 10 книг» — одна и та же при любом порядке строк, у разных выборок — разные книги;
- смена темы и созвездия книги набора считается по каждой книге;
- мерка «верно» не засчитывается, если хоть одна тема ниже 85 %; мерка 9 краснеет, когда
  10 книг библиотеки меняют тему двух книг набора; мерка 10 остаётся за владельцем.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import os
import random
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import final as F  # noqa: E402


def ideal_row(fp, n, topic, section):
    return {'fp': fp, 'n': str(n), 'название': fp, 'тема': topic, 'допустимые': '',
            'без_темы_ок': 'нет', 'раздел': section, 'вид': 'учебник', 'язык': 'ru'}


class Samples(unittest.TestCase):
    def test_alg_map_20_sample_does_not_depend_on_order(self):
        """ALG-MAP-20 (S69): выборка без 10 книг — по хэшу: порядок строк не важен, выборки разные."""
        rows = [{'fp': f'{i:04x}'} for i in range(100)]
        shuffled = rows[:]
        random.Random(3).shuffle(shuffled)
        kept, gone = F.drop_sample(rows, 10, 1)
        self.assertEqual(len(gone), 10)
        self.assertEqual(len(kept), 90)
        self.assertEqual(gone, F.drop_sample(shuffled, 10, 1)[1])
        self.assertNotEqual(gone, F.drop_sample(rows, 10, 2)[1])

    def test_alg_map_20_changes_per_book(self):
        """ALG-MAP-20 (S69): смена темы и созвездия — по каждой книге набора."""
        a = [{'fp': 'x', 'тема каркаса': 'MED.ANAT', 'созвездие': 'MED.ANAT: Миология'},
             {'fp': 'y', 'тема каркаса': 'MED.HIST', 'созвездие': 'MED.HIST: Цитология'}]
        b = [{'fp': 'x', 'тема каркаса': 'MED.ANAT', 'созвездие': 'MED.ANAT: Остеология и артрология'},
             {'fp': 'y', 'тема каркаса': 'MED.PATH', 'созвездие': 'MED.PATH: Общая патология'}]
        self.assertEqual(F.changes(a, b, ['x', 'y']), (['y'], ['x', 'y']))


class Measures(unittest.TestCase):
    def setUp(self):
        rows = [ideal_row(f'a{i}', i, 'Анатомия', 'кости') for i in range(8)]
        rows += [ideal_row(f'h{i}', 10 + i, 'Гистология', 'ткани') for i in range(2)]
        self.ideal = {r['fp']: r for r in rows}
        self.layer = {b: {'lang': 'ru', 'quality': 'чистый', 'pages': '300'} for b in self.ideal}
        self.pp = {b: {'read': 30} for b in self.ideal}

    def result(self, wrong=()):
        return [{'fp': b, 'группа': '9' if b in wrong else ('0' if b[0] == 'a' else '1'), 'имя': '',
                 'тема каркаса': 'X' if b in wrong else ('MED.ANAT' if b[0] == 'a' else 'MED.HIST'),
                 'созвездие': 'кости' if b[0] == 'a' else 'ткани'} for b in self.ideal]

    def rows(self, **kw):
        return {r[0]: r for r in F.measures(self.ideal, self.layer, kw.pop('result', self.result()), self.pp, **kw)}

    def test_alg_map_20_every_topic_must_reach_85(self):
        """ALG-MAP-20 (S69): мерка 1 — не только число «верно», но и каждая тема ≥ 85 %."""
        self.assertIs(self.rows()[1][4], False)  # 10 книг — меньше 90
        got = self.rows(result=self.result(wrong={'h0'}))[1]
        self.assertIn('тем ниже 85 %: 1 из 2', got[2])

    def test_alg_map_20_stability_two_books_is_red(self):
        """ALG-MAP-20 (S69): мерка 9 — 10 книг библиотеки сменили тему двух книг набора → не достигнута."""
        base = self.result()
        one = self.result(wrong={'a0'})
        two = self.result(wrong={'a0', 'a1'})
        self.assertIs(self.rows(repeat=base, stable=[one], leak=True)[9][4], True)
        self.assertIs(self.rows(repeat=base, stable=[one, two], leak=True)[9][4], False)
        self.assertIs(self.rows(repeat=one, leak=True)[9][4], False)  # повтор не тот же
        self.assertIsNone(self.rows()[10][4])  # имена — за владельцем

    def test_alg_map_20_reading_median_and_time(self):
        """ALG-MAP-20 (S69): мерка 8 — медиана страниц ≤ 30 и каждая книга без OCR ≤ 1 с."""
        self.assertIs(self.rows(seconds={'1': 0.3, '2': 0.9})[8][4], True)
        self.assertIs(self.rows(seconds={'1': 0.3, '2': 1.2})[8][4], False)
        self.pp = {b: {'read': 40} for b in self.ideal}
        self.assertIs(self.rows()[8][4], False)


if __name__ == '__main__':
    unittest.main()
