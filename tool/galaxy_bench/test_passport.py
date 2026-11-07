"""Тесты паспорта книги (ALG-MAP-21, S62).

Каждый случай — из настоящих книг стенда, но текст придуман заново (книги чужие):
- CP1251, прочитанная как Latin-1, чинится, а немецкий текст с умлаутами — нет;
- оглавление с латинской «C» в «Cодержание», оглавление без номеров страниц, продолжение
  на следующей странице; предметный указатель и «содержание калия» в тексте — не оглавление;
- коды УДК, ББК, NLM, LC, DDC и рубрики CIP с оборота титула;
- имя файла в метаданных Title — не название.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import passport as P  # noqa: E402

TOC_RU = '\n'.join(['Cодержание'] + [f'Глава {i}. Кости и суставы конечностей . . . . . {10 * i}' for i in range(1, 9)])
TOC_NO_NUMBERS = '\n'.join(['Оглавление', 'Предисловие к изданию'] + [f'Глава {i}. Коды и комбинации' for i in range(1, 9)])
TOC_MORE = '\n'.join(f'{i}.{j} Нейроны и синапсы . . . {100 + i * 10 + j}' for i in range(1, 4) for j in range(1, 6))
INDEX = '\n'.join(['Предметный указатель', 'Содержание'] + [f'аксон {i}, {i + 7}, {i + 30}' for i in range(1, 15)])
PROSE = ('Тот задумался, а потом вспомнил, что содержание калия в крови пациента было низким. '
         'Анализы 12, 14, 17, 21 и 30 ничего не показали. ') * 5


class Encoding(unittest.TestCase):
    def test_alg_map_21_cp1251_as_latin1_is_fixed(self):
        """ALG-MAP-21: «ÑÎÄÅÐÆÀÍÈÅ» (CP1251 как Latin-1) становится «СОДЕРЖАНИЕ»; умлауты не трогаются."""
        broken = ('СОДЕРЖАНИЕ. Критика чистого разума, введение в трансцендентальную эстетику. ' * 3) \
            .encode('cp1251').decode('latin-1')
        fixed, changed = P.fix_encoding(broken)
        self.assertTrue(changed)
        self.assertTrue(fixed.startswith('СОДЕРЖАНИЕ'))
        german = 'Über die Größe der Gefäße und die Müdigkeit der Muskeln während der Übung. ' * 3
        self.assertEqual(P.fix_encoding(german), (german, False))


class TableOfContents(unittest.TestCase):
    def test_alg_map_21_toc_with_latin_c_and_continuation(self):
        """ALG-MAP-21: «Cодержание» с латинской C находится; следующая страница с номерами — продолжение."""
        toc, used = P.toc_from_pages([(5, TOC_RU), (6, TOC_MORE), (7, PROSE)])
        self.assertEqual(used, [5, 6])
        self.assertIn('Кости и суставы', toc)
        self.assertIn('Нейроны и синапсы', toc)
        self.assertNotRegex(toc, r'\d{2,}')

    def test_alg_map_21_toc_without_page_numbers(self):
        """ALG-MAP-21: оглавление электронной книги без номеров страниц принимается."""
        toc, used = P.toc_from_pages([(6, TOC_NO_NUMBERS)])
        self.assertEqual(used, [6])
        self.assertIn('Коды и комбинации', toc)

    def test_alg_map_21_index_and_prose_are_not_toc(self):
        """ALG-MAP-21: предметный указатель и слово «содержание» в тексте — не оглавление."""
        self.assertEqual(P.toc_from_pages([(300, INDEX), (14, PROSE)]), ('', []))

    def test_alg_map_21_outline_without_front_matter(self):
        """ALG-MAP-21: из закладок уходят обложка, предисловие, номера страниц; меньше 5 пунктов — нет оглавления."""
        outline = [[1, 'Cover'], [1, 'Preface'], [1, '12'], [1, 'Epithelium'], [1, 'Connective tissue'],
                   [1, 'Cartilage'], [1, 'Bone'], [2, 'Blood'], [3, 'Too deep'], [1, 'Index']]
        self.assertEqual(P.toc_from_outline(outline), ['Epithelium', 'Connective tissue', 'Cartilage', 'Bone', 'Blood'])
        self.assertEqual(P.toc_from_outline(outline[:6]), [])


class Codes(unittest.TestCase):
    def test_alg_map_21_catalog_codes_ru(self):
        """ALG-MAP-21: УДК и ББК с оборота титула."""
        page = 'УДК 611.018(075.8)\nББК 28.706я73\nISBN 978-5-9704-1234-5\n© Издательство, 2015'
        codes, subjects, at = P.catalog_codes([(1, 'Титул'), (2, page)])
        self.assertEqual(at, 2)
        self.assertIn(['УДК', '611.018(075.8)'], codes)
        self.assertIn(['ББК', '28.706я73'], codes)

    def test_alg_map_21_catalog_codes_en_cip(self):
        """ALG-MAP-21: NLM, LC, DDC и рубрики CIP с американского оборота титула."""
        page = ('Library of Congress Cataloging-in-Publication Data\nJunqueira, Luiz Carlos.\n'
                'Basic histology. ISBN 978-0-07-178033-9\n[DNLM: 1. Histology. 2. Cells—cytology. QS 504]\n'
                'QM551 .J86 2013\n611\'.018—dc23')
        codes, subjects, _ = P.catalog_codes([(4, page)])
        self.assertIn(['NLM', 'QS 504'], codes)
        self.assertIn(['LC', 'QM551 .J86'], codes)
        self.assertIn(['DDC', "611'.018"], codes)
        self.assertEqual(subjects[:2], ['Histology', 'Cells—cytology'])


class Title(unittest.TestCase):
    def test_alg_map_21_title_from_big_font_and_meta_without_file_name(self):
        """ALG-MAP-21: название — крупные строки титула; имя файла в Title метаданных отбрасывается."""
        big = {'1': [[9.0, 'Издательство']], '2': [[28.0, 'ГИСТОЛОГИЯ'], [22.0, 'Атлас для практических занятий'],
                                                   [10.0, 'Москва 2015']]}
        self.assertEqual(P.title_from_big(big), 'ГИСТОЛОГИЯ Атлас для практических занятий')
        self.assertEqual(P.clean_meta('Гистология_00045.pdf'), '')
        self.assertEqual(P.clean_meta('Microsoft Word - glava1.doc'), '')
        self.assertEqual(P.clean_meta('Basic Histology: Text and Atlas'), 'Basic Histology: Text and Atlas')


class ImprintAndIndex(unittest.TestCase):
    def test_alg_map_21_imprint_words_without_codes_and_print_lines(self):
        """ALG-MAP-21 (S65): слова выходных данных — гриф и издательство остаются; УДК, ISBN, ©, тираж уходят."""
        page = '\n'.join(['УДК 616-091(075.8)', 'ББК 52.5я73',
                          'Патологическая анатомия : атлас : учеб. пособие для студентов медицинских вузов',
                          'М. : ГЭОТАР-Медиа, 2014', 'ISBN 978-5-9704-1234-5', '© Коллектив авторов, 2014',
                          'Тираж 1000 экз.'])
        words = P.imprint_words([(1, 'Титул'), (4, page)], 4)
        self.assertIn('медицинских вузов', words)
        self.assertIn('ГЭОТАР-Медиа', words)
        for junk in ('УДК', 'ISBN', '©', 'Тираж'):
            self.assertNotIn(junk, words)
        self.assertEqual(P.imprint_words([(1, 'Просто текст без выходных данных')], None), '')

    def test_alg_map_21_index_terms_from_tail_pages(self):
        """ALG-MAP-21 (S65): термины указателя — с последних страниц, без номеров; первые страницы не смотрятся."""
        names = ['аксон', 'дендрит', 'синапс', 'миелин', 'нейрон', 'глия', 'медиатор', 'рецептор',
                 'потенциал', 'мембрана', 'ганглий', 'рефлекс', 'нерв', 'ствол']
        index = '\n'.join(['Предметный указатель'] + [f'{w} {i}, {i + 7}, {i + 30}' for i, w in enumerate(names, 1)])
        pages = [(n, 'текст') for n in range(1, 26)] + [(300, index)]
        terms = P.index_terms(pages)
        self.assertIn('синапс миелин', terms)
        self.assertNotRegex(terms, r'\d{2}')
        self.assertEqual(P.index_terms([(2, index)] + [(n, 'текст') for n in range(3, 27)]), '')


if __name__ == '__main__':
    unittest.main()
