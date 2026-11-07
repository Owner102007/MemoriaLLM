"""Тесты универсальной схемы (S64): каркас тем и переходники кодов (ALG-MAP-23), разбор
каталогов и решение по паспорту (ALG-MAP-24).

Случаи — общие правила классификаций, а не книги стенда:
- УДК и DDC — самое длинное начало кода; LCC и NLM — самый узкий диапазон номера;
- спор двух кодов решает более подробный; один код дважды — один голос;
- каждая тема переходников и сопоставления с идеалом есть в каркасе;
- запись MARC из NKP: название кириллицей из поля 880, УДК из 080, только русские книги;
- книги tgpathfinder (S67): ярлык из кода, отсев книг стенда, база только читается.

Запуск (из папки MemoriaLLM): python -m unittest discover tool/galaxy_bench -v
"""
import gzip
import hashlib
import io
import os
import pathlib
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import catalogs as C  # noqa: E402
import taxonomy as T  # noqa: E402
import universal as U  # noqa: E402


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


class Transliteration(unittest.TestCase):
    def test_alg_map_24_alalc_back_to_cyrillic(self):
        """ALG-MAP-24: ALA-LC → кириллица: связки (i͡a — я, t͡s — ц), ʹ — ь, ĭ — й, ė — э; без связки «ts» — «тс»."""
        self.assertEqual(C.cyrillic_from_alalc('Gistologii͡a︡'), 'Гистология')
        self.assertEqual(C.cyrillic_from_alalc('Biosfera i t͡s︡ivilizat͡s︡ii͡a︡'), 'Биосфера и цивилизация')
        self.assertEqual(C.cyrillic_from_alalc('gruzinskoĭ zhivopisi, AĖS, Rospisʹ'), 'грузинской живописи, АЭС, Роспись')
        self.assertEqual(C.cyrillic_from_alalc('Shchedrin'), 'Щедрин')
        self.assertEqual(C.cyrillic_from_alalc('otsenka'), 'отсенка')


class Tgpathfinder(unittest.TestCase):
    """S67 (D-053): тексты книг tgpathfinder — ярлык из кода, отсев стенда, база только читается."""

    def make_db(self, d, stand_size, stand_print):
        """Маленький индекс tgpathfinder: только нужные стенду столбцы."""
        path = os.path.join(d, 'index.db')
        db = sqlite3.connect(path)
        db.executescript('''
            create table files (id integer primary key, size integer, head_tail_hash text);
            create table books (id integer primary key, file_id integer, title text, inner_path text);
            create table page_texts (book_id integer, page_no integer, text text, primary key (book_id, page_no));''')
        books = [
            # id, название, размер, отпечаток, путь в архиве, страницы
            (1, 'Гистология', 123456, 'aaa', '', ['Гистология\nучебник для студентов вузов', 'УДК 611.018(075.8)\nББК 28.706я73']),
            (2, 'Записки', 2000, None, '', ['Записки путешественника\nо дальних странах', 'глава первая']),
            (3, 'Нормальная физиология', stand_size, stand_print, '', ['Нормальная физиология\nучебник', 'УДК 612']),
            (4, 'Фармакология', stand_size, stand_print, 'том/фарм.pdf', ['Фармакология\nлекарства рецепты', 'УДК 615']),
            (5, 'Атлас анатомии человека. Том 2', 3000, None, '', ['Атлас\nкниги', 'УДК 611']),
            (6, 'Анатомия', 4000, None, '', ['Анатомия\nкости суставы связки мышцы остеология артрология миология', 'УДК 611']),
        ]
        for bid, title, size, fp, inner, pages in books:
            db.execute('insert into files values (?, ?, ?)', (bid, size, fp))
            db.execute('insert into books values (?, ?, ?, ?)', (bid, bid, title, inner))
            for no, text in enumerate(pages, 1):
                db.execute('insert into page_texts values (?, ?, ?)', (bid, no, text))
        db.commit()
        db.close()
        return path

    def test_alg_map_24_tgpathfinder_label_from_codes_and_stand_excluded(self):
        """ALG-MAP-24: ярлык — из кода УДК/ББК в тексте; без кода — не берётся; книга стенда отсеяна
        по отпечатку и размеру файла (но не книга внутри архива того же размера), по началу названия
        и по почти тому же паспорту; база не меняется и рядом не появляется файлов."""
        with tempfile.TemporaryDirectory() as d:
            stand = os.path.join(d, 'стенд.pdf')
            with open(stand, 'wb') as f:
                f.write(b'%PDF-1.4 ' + bytes(range(256)) * 40)
            db = self.make_db(d, os.path.getsize(stand), C.file_fingerprint(stand))
            before = pathlib.Path(db).read_bytes()
            set_rows = [{'fp': 's1', 'path': stand}]
            set_pp = {'s1': dict(title='Атлас анатомии человека. Том 1', meta={}, codes=[], subjects=[],
                                 toc='кости суставы связки мышцы остеология артрология миология')}
            rows, tally = U.tgpathfinder_rows(db, set_rows, set_pp)
            self.assertEqual(pathlib.Path(db).read_bytes(), before)
            self.assertEqual(sorted(os.listdir(d)), ['index.db', 'стенд.pdf'])
        self.assertEqual(sorted(r['тема'] for r in rows), ['MED.HIST', 'MED.PHARM'])
        self.assertEqual(tally, {'книг с текстом': 6, 'без кода': 1, 'тот же файл': 1, 'то же название': 1,
                                 'тот же паспорт': 1, 'сверх предела': 0, 'взято': 2})
        self.assertTrue(all(r['источник'] == 'tgpathfinder' and r['хэш'] == 'ff' for r in rows))
        self.assertTrue(all('УДК' not in r['текст'] and '611' not in r['текст'] for r in rows))  # коды не в словах

    def test_alg_map_24_fingerprint_like_tgpathfinder(self):
        """ALG-MAP-24: отпечаток — sha1 «размер:» и кусков по 4 КБ: малый файл — все куски подряд,
        большой — голова, середина, хвост (как F-RUN-09 в tgpathfinder: 1 000 000 → 0, 499712, 999424)."""
        with tempfile.TemporaryDirectory() as d:
            for size, offsets in ((9000, [0, 4096, 8192]), (1_000_000, [0, 499712, 999424])):
                data = hashlib.sha256(str(size).encode()).digest() * (size // 32 + 1)
                data = data[:size]
                path = os.path.join(d, f'{size}.pdf')
                pathlib.Path(path).write_bytes(data)
                want = hashlib.sha1(f'{size}:'.encode() + b''.join(data[o:o + 4096] for o in offsets)).hexdigest()
                self.assertEqual(C.file_fingerprint(path), want)


if __name__ == '__main__':
    unittest.main()
