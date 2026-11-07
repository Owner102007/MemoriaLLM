"""Тесты понятий MeSH (ALG-MAP-25, S66): мост между русским и английским.

Проверяется: русское и английское название понятия дают одну метку; ищется самая длинная
цепочка слов; короткие однословные названия не берутся; анализатор отдаёт классификатору
и основы слов, и метки понятий.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import concepts as C  # noqa: E402

ROWS = [
    dict(понятие='Q1', mesh='D004847', ветки='A10.272', язык='en', название='Epithelium'),
    dict(понятие='Q1', mesh='D004847', ветки='A10.272', язык='ru', название='Эпителий'),
    dict(понятие='Q2', mesh='D002460', ветки='A11.284', язык='en', название='Cell Membrane'),
    dict(понятие='Q3', mesh='D002477', ветки='A11', язык='en', название='Cells'),
    dict(понятие='Q4', mesh='D000001', ветки='C04', язык='ru', название='Рак'),
]


class Concepts(unittest.TestCase):
    def test_alg_map_25_same_mark_for_russian_and_english(self):
        """ALG-MAP-25: «эпителий» и «epithelium» в любой форме — одна метка D004847 и ветка A10."""
        table = C.Concepts(ROWS)
        self.assertEqual(table.marks('Многослойный эпителий кожи'), ['A10', 'D004847'])
        self.assertEqual(table.marks('Stratified epithelium of skin'), ['A10', 'D004847'])

    def test_alg_map_25_longest_chain_and_short_words(self):
        """ALG-MAP-25: «cell membrane» — одно понятие, а не «cells» + …; «рак» (3 буквы) не берётся."""
        table = C.Concepts(ROWS)
        self.assertEqual(table.marks('The cell membrane'), ['A11', 'D002460'])
        self.assertEqual(table.marks('Рак лёгкого'), [])

    def test_alg_map_25_analyzer_sees_words_and_marks(self):
        """ALG-MAP-25: анализатор — основы слов текста и метки «⟦…⟧» отдельными признаками."""
        text = C.Concepts(ROWS).annotate('Эпителий')
        self.assertIn('⟦D004847⟧', text)
        feats = C.analyzer(text)
        self.assertIn('эпител', feats)
        self.assertIn('⟦d004847⟧', feats)
        self.assertIn('⟦a10⟧', feats)


if __name__ == '__main__':
    unittest.main()
