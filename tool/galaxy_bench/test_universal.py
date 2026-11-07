"""Тесты универсальной схемы (S64): каркас тем и переходники кодов (ALG-MAP-23), разбор
каталогов и решение по паспорту (ALG-MAP-24).

Случаи — общие правила классификаций, а не книги стенда:
- УДК и DDC — самое длинное начало кода; LCC и NLM — самый узкий диапазон номера;
- спор двух кодов решает более подробный; один код дважды — один голос;
- каждая тема переходников и сопоставления с идеалом есть в каркасе;
- запись MARC из NKP: название кириллицей из поля 880, УДК из 080, только русские книги.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import gzip
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import catalogs as C  # noqa: E402
import taxonomy as T  # noqa: E402


class Skeleton(unittest.TestCase):
    def test_alg_map_23_every_table_topic_is_in_skeleton(self):
        """ALG-MAP-23: темы всех переходников и сопоставления с идеалом есть в каркасе; разделов ≈ 20."""
        for table in (T.UDC, T.BBK, T.DDC):
            for _, topic in table:
                self.assertIn(topic, T.TOPICS)
        for table in (T.LCC, T.NLM):
            for *_, topic in table:
                self.assertIn(topic, T.TOPICS)
        for topic in T.IDEAL:
            self.assertIn(topic, T.TOPICS)
        self.assertTrue(15 <= len(T.SECTIONS) <= 25)
        self.assertTrue(all(ru and en for _, ru, en in T.TOPICS.values()))


class Codes(unittest.TestCase):
    def test_alg_map_23_decimal_codes_longest_prefix(self):
        """ALG-MAP-23: УДК 611.018 — гистология, 611.1 — анатомия, 004.8 — ИИ; DDC 616.8 — неврология."""
        self.assertEqual(T.topic_of_code('УДК', '611.018(075.8)'), 'MED.HIST')
        self.assertEqual(T.topic_of_code('УДК', '611.1'), 'MED.ANAT')
        self.assertEqual(T.topic_of_code('УДК', '004.85'), 'IT.AI')
        self.assertEqual(T.topic_of_code('DDC', "616.8'3—dc23"), 'MED.NEUROL')
        self.assertEqual(T.topic_of_code('ББК', '32.973.202+32.988.02 УДК 004.73'), 'IT.GEN')

    def test_alg_map_23_letter_codes_narrowest_range(self):
        """ALG-MAP-23: LCC QM551 — гистология (узкий диапазон), QM23 — анатомия, BF637 — саморазвитие; NLM QS 504 — гистология."""
        self.assertEqual(T.topic_of_code('LC', 'QM551 .J86'), 'MED.HIST')
        self.assertEqual(T.topic_of_code('LC', 'QM23.2 .G73'), 'MED.ANAT')
        self.assertEqual(T.topic_of_code('LCC', 'BF637.S4'), 'HEALTH.SELF')
        self.assertEqual(T.topic_of_code('NLM', 'QS 504'), 'MED.HIST')
        self.assertEqual(T.topic_of_code('NLM', 'WL 300'), 'MED.NEUROL')
        self.assertIsNone(T.topic_of_code('LC', '1234'))

    def test_alg_map_23_vote_detail_and_duplicates(self):
        """ALG-MAP-23: спор УДК 611.018 и ББК 28.706 решает подробный код; дважды прочитанный код — один голос."""
        self.assertEqual(T.topic_of_codes([['УДК', '611.018(075.8)'], ['ББК', '28.706я73']]), 'MED.HIST')
        # ББК 24.1 прочитан дважды: голос один, иначе химия победила бы 2 : 1; УДК 612.1 подробнее
        self.assertEqual(T.topic_of_codes([['ББК', '24.1'], ['ББК', '24.1 Х46'], ['УДК', '612.1']]), 'MED.PHYS')
        self.assertEqual(T.topic_of_codes([['NLM', 'QZ 17'], ['LC', 'QH436.P37']]), None)
        self.assertIsNone(T.topic_of_codes([]))
        self.assertEqual(T.ideal_of('MED.INT'), 'Медицина')
        self.assertEqual(T.ideal_of('FIC.PROSE'), 'Прочее')


NKP_RECORD = '''<?xml version="1.0" encoding="UTF-8"?>
<collection xmlns="http://www.loc.gov/MARC21/slim">
<record><leader>00000nam a22 4500</leader>
<controlfield tag="001">slk1</controlfield>
<controlfield tag="008">030617s1985    ru            000 0 rus d</controlfield>
<datafield tag="080" ind1=" " ind2=" "><subfield code="a">611.018</subfield></datafield>
<datafield tag="245" ind1="1" ind2="0"><subfield code="6">880-01</subfield><subfield code="a">Gistologija :</subfield></datafield>
<datafield tag="650" ind1=" " ind2="7"><subfield code="a">histologie</subfield></datafield>
<datafield tag="880" ind1="1" ind2="0"><subfield code="6">245-01/(N</subfield><subfield code="a">Гистология :</subfield><subfield code="b">учебник</subfield></datafield>
</record>
<record><leader>00000nam a22 4500</leader>
<controlfield tag="001">slk2</controlfield>
<controlfield tag="008">030617s1985    xr            000 0 cze d</controlfield>
<datafield tag="080" ind1=" " ind2=" "><subfield code="a">611</subfield></datafield>
<datafield tag="245" ind1="1" ind2="0"><subfield code="a">Anatomie</subfield></datafield>
</record>
</collection>'''


class Catalogs(unittest.TestCase):
    def test_alg_map_24_nkp_cyrillic_title_and_udc_russian_only(self):
        """ALG-MAP-24: из MARC NKP — название кириллицей (880), УДК (080); чешская книга и рубрики 650 не берутся."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'slk.xml.gz')
            with gzip.open(path, 'wt', encoding='utf-8') as f:
                f.write(NKP_RECORD)
            got = list(C.nkp_records(path))
        self.assertEqual(len(got), 1)
        key, lang, codes, text = got[0]
        self.assertEqual((key, lang, codes), ('slk1', 'ru', [['УДК', '611.018']]))
        self.assertEqual(text, 'Гистология учебник')
        self.assertNotIn('histologie', text)
        self.assertEqual(T.topic_of_codes(codes), 'MED.HIST')

    def test_alg_map_24_selection_is_deterministic(self):
        """ALG-MAP-24: порядок отбора записей — по хэшу ключа, одинаковый при каждом запуске."""
        self.assertEqual(C.rank('nkpslk1'), C.rank('nkpslk1'))
        self.assertNotEqual(C.rank('nkpslk1'), C.rank('nkpslk2'))
        self.assertEqual(C.clean('Гистология :  учебник / '), 'Гистология учебник')


if __name__ == '__main__':
    unittest.main()
