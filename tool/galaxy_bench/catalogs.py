"""Стенд «Галактики» (S64): открытые каталоги библиотек → обучающие записи «текст → тема»
(ALG-MAP-24, D-052, RS-10).

Что делает. Читает выгрузки каталогов из `_данные/каталоги/` (вне git: записи не
распространяются, в приложение пойдут только веса) и пишет `обучение.tsv`: источник, язык,
тема каркаса, текст. Тема записи — по её классу через переходники `taxonomy.py`; запись без
узнанного класса пропускается. Текст — название, подзаголовок и оглавление: то же, что паспорт
книги на стенде (S62), только без кодов — иначе классификатор выучил бы коды, а у половины
книг их нет.

Источники:
- Славянская библиотека NKP (`nkp/slk.xml.gz`, MARCXML, CC0) — русские книги: УДК (080),
  название кириллицей (880, связанное с 245), оглавление (505 или его 880). Только книги
  (лидер, позиция 7 = «m») на русском (008, позиции 35–37). Чешские рубрики 650 не берутся.
- Project Gutenberg (`gutenberg/pg_catalog.csv`) — английские книги: LoCC, название, рубрики
  LCSH (английские — годятся как «оглавление в словах»).
- Open Library (`openlibrary/ol_dump_editions_latest.txt.gz`) — издания с LCC
  (`lc_classifications`) и DDC (`dewey_decimal_class`): название, подзаголовок, оглавление.
  Английские, немецкие, испанские — источник `openlibrary`; русские — `openlibrary_ru`: их
  названия записаны латиницей ALA-LC и переводятся обратно в кириллицу (`cyrillic_from_alalc`).

Сколько. Не больше `CAP` записей на тему из каждого источника: иначе тема с миллионом записей
(художественная проза) заглушает тему с тысячей. Отбор — по хэшу ключа записи, детерминированно.

Запуск (из папки MemoriaLLM): python tool/galaxy_bench/catalogs.py <папка каталогов> [источники]
Файлы каталогов — чужие данные: скрипт только читает их и не исполняет ничего из них.
"""
import collections
import csv
import gzip
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

import taxonomy as T

CAP = 6000
MARC = '{http://www.loc.gov/MARC21/slim}'
csv.field_size_limit(10 ** 7)


def rank(key):
    """Детерминированный «случайный» порядок записи — по SHA-1 её ключа."""
    return hashlib.sha1(key.encode('utf-8')).hexdigest()


def clean(text):
    """Строка без служебных знаков MARC (« :», « /», «--») и лишних пробелов."""
    text = re.sub(r'\s*[:/;=]\s*$', '', text.strip())
    text = re.sub(r'\s+[:/=]\s+', ' ', text)  # « : » между названием и подзаголовком
    return re.sub(r'\s+', ' ', text.replace(' -- ', '; '))


# --- NKP: MARCXML ---------------------------------------------------------------------------
def nkp_records(path):
    """(ключ, язык, коды УДК, текст) по книгам NKP; разбор потоком, память не растёт."""
    with gzip.open(path) as stream:  # закрыть файл и при раннем выходе (иначе Windows держит его)
        yield from _nkp_parse(stream)


def _nkp_parse(stream):
    for _, rec in ET.iterparse(stream, events=('end',)):
        if rec.tag != MARC + 'record':
            continue
        leader = (rec.findtext(MARC + 'leader') or '').ljust(8)
        fields = {}
        for cf in rec.findall(MARC + 'controlfield'):
            fields[cf.get('tag')] = cf.text or ''
        udc, latin, cyr = [], {}, {}
        for df in rec.findall(MARC + 'datafield'):
            tag = df.get('tag')
            sub = [(s.get('code'), s.text or '') for s in df.findall(MARC + 'subfield')]
            if tag == '080':
                udc += [v for c, v in sub if c == 'a']
            elif tag in ('245', '505'):
                latin[tag] = ' '.join(v for c, v in sub if c in 'abnpt')
            elif tag == '880':
                link = next((v for c, v in sub if c == '6'), '')
                cyr[link[:3]] = ' '.join(v for c, v in sub if c in 'abnpt')
        rec.clear()
        lang = fields.get('008', '')[35:38]
        if leader[7] != 'm' or lang != 'rus' or not udc:
            continue
        title = cyr.get('245') or latin.get('245', '')
        toc = cyr.get('505') or (latin.get('505', '') if re.search('[а-яА-Я]', latin.get('505', '')) else '')
        text = clean(title) + ('\n' + clean(toc) if toc else '')
        if re.search('[а-яА-Я]', text):
            yield fields.get('001', ''), 'ru', [['УДК', u] for u in udc], text


# --- Gutenberg: CSV -------------------------------------------------------------------------
def gutenberg_records(path):
    for r in csv.DictReader(open(path, encoding='utf-8')):
        if r.get('Type') != 'Text' or not r.get('LoCC'):
            continue
        lang = r.get('Language', '')
        if lang not in ('en', 'ru', 'de', 'es'):
            continue
        codes = [['LCC', c.strip()] for c in r['LoCC'].split(';') if c.strip()]
        subjects = '; '.join(s.split('--')[0].strip() for s in r.get('Subjects', '').split(';') if s.strip())
        text = clean(r.get('Title', '')) + ('\n' + subjects if subjects else '')
        yield 'pg' + r['Text#'], lang, codes, text


# --- обратная транслитерация ALA-LC (русский) ------------------------------------------------
# Open Library пишет русские названия латиницей по таблице ALA-LC: «Gistologii͡a︡» = «Гистология».
# Связка двух букв (U+0361 между ними, U+FE20/FE21 — её половинки) — одна русская буква:
# t͡s = ц, i͡a = я, i͡u = ю, i͡e = ѣ (дореформенная «ять», пишем «е»). Без связки «ts» — это «тс».
_PAIRS = [('shch', 'щ'), ('zh', 'ж'), ('kh', 'х'), ('ch', 'ч'), ('sh', 'ш')]
_ONE = dict(zip('abvgdeziklmnoprstufy', 'абвгдезиклмнопрстуфы'))
_ONE.update({'ĭ': 'й', 'ė': 'э', 'ī': 'и', 'ë': 'ё', 'ʹ': 'ь', 'ʺ': 'ъ', 'j': 'й', 'h': 'х', 'c': 'ц', 'w': 'в', 'x': 'кс', 'q': 'к'})
_TIED = {'ts': 'ц', 'ia': 'я', 'iu': 'ю', 'ie': 'е'}
_TIE = re.compile('([A-Za-z])[︠͡]([A-Za-z])︡?')


def cyrillic_from_alalc(text):
    """Русский текст из записи ALA-LC; латинские слова с чужими знаками остаются как есть."""
    def tied(m):
        pair = (m.group(1) + m.group(2)).lower()
        cyr = _TIED.get(pair, m.group(1) + m.group(2))
        return cyr.upper() if m.group(1).isupper() else cyr
    text = _TIE.sub(tied, text).replace('︡', '').replace('︠', '').replace('͡', '')
    out, i = [], 0
    while i < len(text):
        for lat, cyr in _PAIRS:
            chunk = text[i:i + len(lat)]
            if chunk.lower() == lat:
                out.append(cyr.upper() if chunk[0].isupper() else cyr)
                i += len(lat)
                break
        else:
            ch = text[i]
            cyr = _ONE.get(ch.lower())
            out.append((cyr.upper() if ch.isupper() else cyr) if cyr else ch)
            i += 1
    return ''.join(out)


# --- Open Library: строки «тип \t ключ \t ревизия \t дата \t JSON» ---------------------------
OL_LANG = {'/languages/eng': 'en', '/languages/rus': 'ru', '/languages/ger': 'de', '/languages/spa': 'es'}


def openlibrary_records(path, want=('en', 'de', 'es')):
    """Издания Open Library с LCC или DDC на языках `want`; русские — кириллицей из ALA-LC."""
    with gzip.open(path, 'rt', encoding='utf-8', errors='replace') as stream:
        yield from _openlibrary_parse(stream, want)


def openlibrary_ru_records(path):
    return openlibrary_records(path, want=('ru',))


def _openlibrary_parse(stream, want):
    for line in stream:
        if '"lc_classifications"' not in line and '"dewey_decimal_class"' not in line:
            continue
        try:
            d = json.loads(line.split('\t', 4)[4])
        except (IndexError, ValueError):
            continue
        langs = [OL_LANG.get(x.get('key', '')) for x in d.get('languages', []) if isinstance(x, dict)]
        lang = next((x for x in langs if x), None)
        if lang not in want:
            continue
        codes = [['LCC', c] for c in d.get('lc_classifications', []) if isinstance(c, str)]
        codes += [['DDC', c] for c in d.get('dewey_decimal_class', []) if isinstance(c, str)]
        toc = d.get('table_of_contents') or []
        items = [x.get('title', '') if isinstance(x, dict) else str(x) for x in toc]
        title = ' '.join(x for x in (d.get('title', ''), d.get('subtitle', '')) if isinstance(x, str))
        text = clean(title) + ('\n' + '; '.join(i for i in items if i) if items else '')
        if lang == 'ru':
            text = cyrillic_from_alalc(text)
        yield d.get('key', ''), lang, codes, text


SOURCES = {
    'nkp': ('nkp/slk.xml.gz', nkp_records),
    'gutenberg': ('gutenberg/pg_catalog.csv', gutenberg_records),
    'openlibrary': ('openlibrary/ol_dump_editions_latest.txt.gz', openlibrary_records),
    'openlibrary_ru': ('openlibrary/ol_dump_editions_latest.txt.gz', openlibrary_ru_records),
}


def collect(folder, name):
    """Записи одного источника с темой; не больше CAP на тему (меньший хэш ключа — раньше)."""
    rel, reader = SOURCES[name]
    by_topic = collections.defaultdict(list)
    seen = 0
    for key, lang, codes, text in reader(os.path.join(folder, rel)):
        seen += 1
        topic = T.topic_of_codes(codes)
        if not topic or len(text) < 8:
            continue
        bucket = by_topic[topic]
        bucket.append((rank(name + key), lang, text))
        if len(bucket) > 4 * CAP:  # держим память: оставляем лучшие по хэшу
            bucket.sort()
            del bucket[CAP:]
    out = []
    for topic, items in sorted(by_topic.items()):
        items.sort()
        out += [(name, lang, topic, text, h) for h, lang, text in items[:CAP]]
    print(f'{name}: просмотрено {seen}, с темой {sum(len(v) for v in by_topic.values())}, '
          f'взято {len(out)}, тем {len(by_topic)}', flush=True)
    return out


def main(folder, wanted=None):
    names = (wanted or 'nkp,gutenberg,openlibrary,openlibrary_ru').split(',')
    rows = []
    for name in names:
        rows += collect(folder, name)
    path = os.path.join(folder, 'обучение.tsv')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, delimiter='\t')
        w.writerow(['источник', 'язык', 'тема', 'текст', 'хэш'])
        for r in rows:
            w.writerow([r[0], r[1], r[2], r[3].replace('\t', ' '), r[4]])
    tally = collections.Counter(r[2] for r in rows)
    print('записей', len(rows), 'тем', len(tally))
    print(sorted(tally.items(), key=lambda x: -x[1]))


if __name__ == '__main__':
    main(*sys.argv[1:3])
