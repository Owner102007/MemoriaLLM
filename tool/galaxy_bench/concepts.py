"""Стенд «Галактики» (S66): понятия MeSH из Wikidata — мост между русским и английским
(ALG-MAP-25, D-052, RS-09, RS-10).

Зачем. Классификатор S64–S65 видит слова, а у русской и английской книги об одном слова разные:
«эпителий» и «epithelium». В Wikidata (CC0) у 39,6 тыс. понятий есть номер медицинского
словаря MeSH (свойство P486), ветка дерева MeSH (P672) и названия с синонимами на русском и
английском. Если в тексте нашлось название понятия на любом языке, к тексту добавляется метка
понятия «⟦D004847⟧» и метка его ветки «⟦A10⟧» — одинаковые для обоих языков. Классификатор
учится на английских записях каталогов, а метки срабатывают и в русских книгах.

Как ищется. Название понятия → основы слов (первые 6 букв, как у классификатора) → таблица
«цепочка основ → понятия». В тексте ищется самая длинная цепочка (до 4 слов) с каждого места.
Однословные названия короче 4 букв не берутся — слишком много случайных совпадений.

Данные. `fetch` делает три запроса к query.wikidata.org и пишет `<папка>/mesh.tsv` (понятие,
номер MeSH, ветки, язык, название) и `<папка>/запросы.txt` (запросы и дата). Это вход стенда
на ПК; в приложение пойдёт только таблица весов (D-052).

Запуск (из папки MemoriaLLM): python tool/galaxy_bench/concepts.py fetch <папка>
"""
import collections
import csv
import datetime
import http.client
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import variants as V

ENDPOINT = 'https://query.wikidata.org/sparql'
AGENT = 'MemoriaLLM-bench/1.0 (https://github.com/Owner102007/MemoriaLLM)'
QUERIES = {
    'ветки': 'SELECT ?i ?m ?t WHERE { ?i wdt:P486 ?m . OPTIONAL { ?i wdt:P672 ?t } }',
    # Названия и синонимы — пачками по CHUNK понятий (VALUES): целиком запрос не укладывается в 60 с.
    'названия': 'SELECT ?i ?l WHERE { VALUES ?i { %s } ?i rdfs:label ?l . FILTER(LANG(?l) IN ("ru", "en")) }',
    'синонимы': 'SELECT ?i ?l WHERE { VALUES ?i { %s } ?i skos:altLabel ?l . FILTER(LANG(?l) IN ("ru", "en")) }',
}
CHUNK = 500
MAX_WORDS = 4
MIN_SINGLE = 4
MAX_SENSES = 3  # однословная основа общая у большего числа понятий — неоднозначна
_LITERAL = re.compile(r'^"(.*)"@(ru|en)$')


def _query(sparql):
    """Ответ SPARQL в виде TSV (строки без заголовка)."""
    body = urllib.parse.urlencode({'query': sparql}).encode('utf-8')  # POST: длинный VALUES не лезет в адрес
    req = urllib.request.Request(ENDPOINT, data=body, headers={
        'Accept': 'text/tab-separated-values', 'User-Agent': AGENT,
        'Content-Type': 'application/x-www-form-urlencoded'})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                lines = r.read().decode('utf-8').splitlines()
            return [ln.split('\t') for ln in lines[1:]]
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or attempt == 5:
                raise
        except (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError):
            if attempt == 5:
                raise
        time.sleep(10 * (attempt + 1))  # сервер занят или связь оборвалась — подождать и повторить


def _qid(uri):
    return uri.strip('<>').rsplit('/', 1)[-1]


def fetch(folder):
    """Три запроса к Wikidata → `mesh.tsv`; плюс `запросы.txt` с запросами и датой."""
    os.makedirs(folder, exist_ok=True)
    trees, mesh = collections.defaultdict(set), {}
    for i, m, *t in _query(QUERIES['ветки']):
        q = _qid(i)
        mesh[q] = m.strip('"')
        if t and t[0]:
            trees[q].add(t[0].strip('"'))
    time.sleep(2)
    labels, ids = [], sorted(mesh)
    for name in ('названия', 'синонимы'):
        for s in range(0, len(ids), CHUNK):
            values = ' '.join('wd:' + q for q in ids[s:s + CHUNK])
            for row in _query(QUERIES[name] % values):
                if len(row) < 2:
                    continue
                m = _LITERAL.match(row[1].replace('\\"', '"'))
                if m:
                    labels.append((_qid(row[0]), m.group(2), m.group(1)))
            time.sleep(1)  # бережно к общему серверу Wikidata
    with open(os.path.join(folder, 'mesh.tsv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, delimiter='\t')
        w.writerow(['понятие', 'mesh', 'ветки', 'язык', 'название'])
        for q, lang, text in sorted(set(labels)):
            w.writerow([q, mesh.get(q, ''), ';'.join(sorted(trees.get(q, ()))), lang, text])
    with open(os.path.join(folder, 'запросы.txt'), 'w', encoding='utf-8') as f:
        f.write(f'Wikidata (CC0), {ENDPOINT}, {datetime.date.today().isoformat()}\n')
        for k, v in QUERIES.items():
            f.write(f'{k}: {v}\n')
    print(f'понятий {len(mesh)}, с ветками {len(trees)}, названий и синонимов {len(labels)}')


class Concepts:
    """Таблица «цепочка основ → метки» и поиск понятий в тексте."""

    def __init__(self, rows):
        self.table = collections.defaultdict(set)
        for r in rows:
            seq = tuple(V.stems(r['название']))
            if not seq or len(seq) > MAX_WORDS:
                continue
            if len(seq) == 1 and len(seq[0]) < MIN_SINGLE:
                continue
            marks = {r['mesh']} if r['mesh'] else set()
            marks |= {t[:3] for t in r['ветки'].split(';') if t}  # «A10.615.550» → «A10»
            if marks:
                self.table[seq] |= marks
        # Основа из 6 букв у одного слова бывает общей у десятков понятий («dermat» — дерматология,
        # дерматит, дерматомиозит …): такое слово ничего не различает — убираем его.
        for seq in [s for s in self.table if len(s) == 1]:
            if sum(1 for m in self.table[seq] if m[:1] in 'CD' and len(m) > 3) > MAX_SENSES:
                del self.table[seq]

    @classmethod
    def load(cls, path):
        return cls(csv.DictReader(open(path, encoding='utf-8'), delimiter='\t'))

    def marks(self, text):
        """Метки понятий текста: самая длинная цепочка основ с каждого места, без пересечений."""
        words = V.stems(text)
        out, i = [], 0
        while i < len(words):
            for n in range(min(MAX_WORDS, len(words) - i), 0, -1):
                hit = self.table.get(tuple(words[i:i + n]))
                if hit:
                    out += sorted(hit)
                    i += n
                    break
            else:
                i += 1
        return out

    def annotate(self, text):
        """Текст + метки понятий «⟦…⟧» в конце (их вытаскивает анализатор классификатора)."""
        found = self.marks(text)
        return text + ('\n' + ' '.join(f'⟦{m}⟧' for m in found) if found else '')


# --- голос понятий по веткам дерева MeSH (S66, итерация 2) -------------------------------------
# Ветка MeSH (первые 3 знака) → тема каркаса (taxonomy). Объявлено до прогона, общей таблицей.
BRANCH_TOPIC = {
    **{f'A{n:02d}': 'MED.ANAT' for n in range(1, 10)}, 'A10': 'MED.HIST', 'A11': 'SCI.BIO', 'A13': 'MED.ANAT',
    'A14': 'MED.ANAT', 'A15': 'MED.MICRO', 'A16': 'MED.HIST', 'A17': 'MED.ANAT',
    'B01': 'SCI.PLANT', 'B03': 'MED.MICRO', 'B04': 'MED.MICRO', 'B05': 'SCI.PLANT', 'B06': 'SCI.PLANT',
    'C01': 'MED.MICRO', 'C04': 'MED.PATH', 'C10': 'MED.NEUROL', 'C23': 'MED.PATH', 'C26': 'MED.SURG',
    'D12': 'SCI.BIOCHEM', 'D08': 'SCI.BIOCHEM', 'D13': 'SCI.BIOCHEM', 'D27': 'MED.PHARM', 'D02': 'SCI.CHEM',
    'D01': 'SCI.CHEM', 'D03': 'SCI.CHEM', 'D04': 'MED.PHARM', 'D26': 'MED.PHARM',
    'E01': 'MED.DIAG', 'E04': 'MED.SURG', 'E02': 'MED.INT', 'E06': 'MED.DENT',
    'F01': 'SOC.PSY', 'F02': 'MED.NEURO', 'F03': 'MED.NEUROL', 'F04': 'MED.NEUROL',
    'G01': 'SCI.PHYS', 'G02': 'SCI.CHEM', 'G03': 'SCI.BIOCHEM', 'G04': 'SCI.BIO', 'G05': 'SCI.BIO',
    'G06': 'MED.MICRO', 'G07': 'MED.PHYS', 'G08': 'MED.PHYS', 'G09': 'MED.PHYS', 'G10': 'MED.PHYS',
    'G11': 'MED.PHYS', 'G12': 'MED.MICRO', 'G13': 'MED.PHYS', 'G14': 'MED.PHYS', 'G16': 'SCI.BIO',
    'G17': 'IT.AI', 'H01': None, 'I01': 'SOC.SOCIOL', 'I02': 'SOC.EDU', 'K01': 'HIST.WORLD',
    'L01': 'IT.GEN', 'N01': 'MED.PUBLIC', 'N02': 'MED.PUBLIC', 'N03': 'MED.PUBLIC', 'N04': 'MED.PUBLIC',
    'N05': 'MED.PUBLIC', 'N06': 'MED.PUBLIC', 'J01': 'TECH.ENG', 'J02': 'TECH.CHEMT',
}
MIN_VOTES, MIN_SHARE = 3, 0.5


def vote(marks):
    """Тема по веткам меток понятий или None: голосов ≥ MIN_VOTES и у лучшей темы ≥ MIN_SHARE."""
    votes = collections.Counter(BRANCH_TOPIC.get(m) for m in marks if len(m) == 3 and BRANCH_TOPIC.get(m))
    total = sum(votes.values())
    if total < MIN_VOTES:
        return None
    (top, n), = votes.most_common(1)
    tied = [t for t, k in votes.items() if k == n]
    return top if len(tied) == 1 and n / total >= MIN_SHARE else None


_MARK = re.compile(r'⟦([A-Z]\w*)⟧')


def analyzer(text):
    """Основы слов + метки понятий: то, что видит классификатор."""
    return V.stems(_MARK.sub(' ', text)) + ['⟦' + m.lower() + '⟧' for m in _MARK.findall(text)]


if __name__ == '__main__':
    if sys.argv[1] == 'fetch':
        fetch(sys.argv[2])
