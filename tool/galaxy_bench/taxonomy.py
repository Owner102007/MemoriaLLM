"""Стенд «Галактики» (S64): каркас тем и переходники кодов каталога (ALG-MAP-23, D-052).

Что это. Список тем, которые «Галактика» знает заранее, — как в настоящей библиотеке или
книжном магазине. Структура — по мотивам книготорговой классификации Thema (EDItEUR): ≈20
разделов и темы внутри. Подписи на русском и английском написаны для проекта (Thema целиком
не встраивается: переводить и менять её можно только с разрешения EDItEUR, RS-10).

Переходники. На обороте титула у многих книг напечатан код каталога: УДК, ББК, LCC (Библиотека
Конгресса), NLM (медицинская), DDC (Дьюи). Таблицы ниже переводят код в тему каркаса:
- десятичные коды (УДК, ББК, DDC) — по самому длинному подходящему началу кода;
- буквенно-числовые (LCC, NLM) — по классу и диапазону номера («QM 550–575» — гистология).
Сами номера классов — факты; таблицы соответствия — наш текст (лицензия проекта). Подписи
OCLC для DDC не используются — только номера.

Кто зовёт. `catalogs.py` — ярлыки обучающих записей каталогов; `universal.py` — тема по коду
книги (точный первый голос) и сопоставление тем каркаса темам идеала стенда.
"""
import collections
import re

# --- каркас: раздел → [(код темы, русское имя, английское имя)] -------------------------------
SECTIONS = {
    'ART': ('Искусство', 'Arts', [
        ('ART.FINE', 'Изобразительное искусство', 'Fine arts'),
        ('ART.MUSIC', 'Музыка', 'Music'),
        ('ART.FILM', 'Кино, театр, танец', 'Film, theatre, dance'),
        ('ART.ARCH', 'Архитектура и дизайн', 'Architecture and design'),
        ('ART.PHOTO', 'Фотография', 'Photography'),
    ]),
    'LANG': ('Языки', 'Language', [
        ('LANG.LEARN', 'Изучение языков', 'Language learning'),
        ('LANG.LING', 'Языкознание', 'Linguistics'),
    ]),
    'LIT': ('Литература и биографии', 'Literature and biography', [
        ('LIT.STUDY', 'Литературоведение', 'Literary studies'),
        ('LIT.BIO', 'Биографии и мемуары', 'Biography and memoirs'),
    ]),
    'FIC': ('Художественная литература', 'Fiction', [
        ('FIC.PROSE', 'Проза', 'General fiction'),
        ('FIC.FANT', 'Фантастика и фэнтези', 'Science fiction and fantasy'),
        ('FIC.CRIME', 'Детективы и триллеры', 'Crime and thrillers'),
        ('FIC.POETRY', 'Поэзия и драматургия', 'Poetry and drama'),
        ('FIC.CHILD', 'Детская литература', "Children's books"),
    ]),
    'REF': ('Справочники и знание', 'Reference and information', [
        ('REF.ENC', 'Энциклопедии и справочники', 'Encyclopaedias and reference'),
        ('REF.LIB', 'Библиотеки, книги, информация', 'Libraries and information'),
    ]),
    'SOC': ('Общество', 'Society and social sciences', [
        ('SOC.SOCIOL', 'Социология и антропология', 'Sociology and anthropology'),
        ('SOC.POL', 'Политика и государство', 'Politics and government'),
        ('SOC.PSY', 'Психология', 'Psychology'),
        ('SOC.EDU', 'Образование и педагогика', 'Education'),
        ('SOC.MEDIA', 'Медиа и публицистика', 'Media and journalism'),
        ('SOC.MIL', 'Военное дело', 'Warfare and defence'),
    ]),
    'ECO': ('Экономика и бизнес', 'Economics, finance, business', [
        ('ECO.ECON', 'Экономика', 'Economics'),
        ('ECO.FIN', 'Финансы и деньги', 'Finance and money'),
        ('ECO.MGMT', 'Бизнес и управление', 'Business and management'),
        ('ECO.MARK', 'Маркетинг и продажи', 'Marketing and sales'),
    ]),
    'LAW': ('Право', 'Law', [
        ('LAW.LAW', 'Право', 'Law'),
    ]),
    'MED': ('Медицина', 'Medicine', [
        ('MED.ANAT', 'Анатомия', 'Anatomy'),
        ('MED.HIST', 'Гистология и эмбриология', 'Histology and embryology'),
        ('MED.PHYS', 'Физиология', 'Physiology'),
        ('MED.NEURO', 'Нейрофизиология и нейронауки', 'Neurophysiology and neuroscience'),
        ('MED.PATH', 'Патология', 'Pathology'),
        ('MED.PHARM', 'Фармакология', 'Pharmacology'),
        ('MED.MICRO', 'Микробиология и иммунология', 'Microbiology and immunology'),
        ('MED.INT', 'Внутренние болезни', 'Internal medicine'),
        ('MED.SURG', 'Хирургия', 'Surgery'),
        ('MED.NEUROL', 'Неврология и психиатрия', 'Neurology and psychiatry'),
        ('MED.WOMEN', 'Акушерство, гинекология, педиатрия', 'Obstetrics, gynaecology, paediatrics'),
        ('MED.DIAG', 'Диагностика и лучевая медицина', 'Diagnostics and radiology'),
        ('MED.DENT', 'Стоматология', 'Dentistry'),
        ('MED.NURSE', 'Сестринское дело', 'Nursing'),
        ('MED.PUBLIC', 'Общественное здоровье и гигиена', 'Public health'),
        ('MED.GEN', 'Медицина в целом', 'General medicine'),
    ]),
    'HEALTH': ('Здоровье и саморазвитие', 'Health and personal development', [
        ('HEALTH.FIT', 'Здоровье, питание, фитнес', 'Health, diet, fitness'),
        ('HEALTH.SELF', 'Саморазвитие и популярная психология', 'Self-help and popular psychology'),
        ('HEALTH.FAMILY', 'Семья и отношения', 'Family and relationships'),
    ]),
    'HIST': ('История', 'History', [
        ('HIST.WORLD', 'Всеобщая история', 'World history'),
        ('HIST.RUS', 'История России', 'History of Russia'),
        ('HIST.SCI', 'История науки и медицины', 'History of science and medicine'),
        ('HIST.ARCH', 'Археология', 'Archaeology'),
    ]),
    'MATH': ('Математика', 'Mathematics', [
        ('MATH.MATH', 'Математика', 'Mathematics'),
    ]),
    'SCI': ('Естественные науки', 'Natural sciences', [
        ('SCI.PHYS', 'Физика и астрономия', 'Physics and astronomy'),
        ('SCI.CHEM', 'Химия', 'Chemistry'),
        ('SCI.BIOCHEM', 'Биохимия и молекулярная биология', 'Biochemistry and molecular biology'),
        ('SCI.BIO', 'Биология, клетка, генетика', 'Biology, cell, genetics'),
        ('SCI.PLANT', 'Ботаника и зоология', 'Botany and zoology'),
    ]),
    'PHIL': ('Философия и религия', 'Philosophy and religion', [
        ('PHIL.PHIL', 'Философия', 'Philosophy'),
        ('PHIL.REL', 'Религия', 'Religion'),
        ('PHIL.ESO', 'Эзотерика', 'Esoterica'),
    ]),
    'EARTH': ('Земля и путешествия', 'Earth, geography, environment', [
        ('EARTH.GEO', 'Науки о Земле', 'Earth sciences'),
        ('EARTH.TRAVEL', 'География и путешествия', 'Geography and travel'),
        ('EARTH.ECOL', 'Экология и природа', 'Environment and ecology'),
    ]),
    'SPORT': ('Спорт', 'Sport', [
        ('SPORT.SPORT', 'Спорт и активный отдых', 'Sport and outdoor recreation'),
    ]),
    'TECH': ('Техника', 'Technology and engineering', [
        ('TECH.ENG', 'Инженерия и техника', 'Engineering'),
        ('TECH.ELEC', 'Электроника и связь', 'Electronics and communications'),
        ('TECH.BUILD', 'Строительство', 'Building and construction'),
        ('TECH.AGRI', 'Сельское хозяйство', 'Agriculture'),
        ('TECH.CHEMT', 'Химическая и пищевая технология', 'Chemical and food technology'),
    ]),
    'IT': ('Компьютеры и ИТ', 'Computing and IT', [
        ('IT.PROG', 'Программирование', 'Programming'),
        ('IT.AI', 'Данные и искусственный интеллект', 'Data and artificial intelligence'),
        ('IT.SYS', 'Сети, системы, безопасность', 'Networks, systems, security'),
        ('IT.GEN', 'Компьютеры в целом', 'Computing in general'),
    ]),
    'HOME': ('Дом и досуг', 'Lifestyle and leisure', [
        ('HOME.COOK', 'Кулинария', 'Cooking'),
        ('HOME.HOUSE', 'Дом, сад, рукоделие', 'Home, garden, crafts'),
        ('HOME.GAMES', 'Игры и головоломки', 'Games and puzzles'),
    ]),
}

TOPICS = {code: (sec, ru, en) for sec, (_, _, items) in SECTIONS.items() for code, ru, en in items}
SECTION_OF = {code: v[0] for code, v in TOPICS.items()}

# --- сопоставление с темами идеала стенда (объявлено до прогона, общей таблицей) ---------------
# Идеал — темы библиотеки владельца (D-051). Тема каркаса, которой нет в идеале, — «Прочее».
IDEAL = {
    'MED.ANAT': 'Анатомия', 'MED.HIST': 'Гистология', 'MED.PHYS': 'Физиология',
    'MED.NEURO': 'Нейрофизиология', 'MED.PATH': 'Патология', 'MED.PHARM': 'Фармакология',
    'MED.MICRO': 'Биология', 'MED.INT': 'Медицина', 'MED.SURG': 'Медицина', 'MED.NEUROL': 'Медицина',
    'MED.WOMEN': 'Медицина', 'MED.DIAG': 'Медицина', 'MED.DENT': 'Медицина', 'MED.NURSE': 'Медицина',
    'MED.PUBLIC': 'Медицина', 'MED.GEN': 'Медицина', 'HEALTH.FIT': 'Здоровье',
    'HEALTH.SELF': 'Саморазвитие', 'HEALTH.FAMILY': 'Саморазвитие', 'ECO.MGMT': 'Саморазвитие',
    'ECO.FIN': 'Саморазвитие', 'SCI.CHEM': 'Химия', 'SCI.BIOCHEM': 'Биохимия', 'SCI.BIO': 'Биология',
    'SCI.PLANT': 'Биология', 'LANG.LEARN': 'Языки', 'LANG.LING': 'Языки', 'IT.PROG': 'Айти',
    'IT.AI': 'Айти', 'IT.SYS': 'Айти', 'IT.GEN': 'Айти', 'MATH.MATH': 'Айти',
    'PHIL.PHIL': 'Философия', 'SOC.PSY': 'Саморазвитие', 'HIST.WORLD': 'История', 'HIST.RUS': 'История', 'HIST.SCI': 'История',
}


def ideal_of(topic):
    """Тема идеала стенда для темы каркаса; «Прочее», если в идеале такой нет."""
    return IDEAL.get(topic, 'Прочее')


# --- переходники: десятичные коды (по самому длинному началу) ----------------------------------
UDC = [
    ('004.8', 'IT.AI'), ('004.4', 'IT.PROG'), ('004.7', 'IT.SYS'), ('004.056', 'IT.SYS'), ('004', 'IT.GEN'),
    ('681.3', 'IT.GEN'), ('02', 'REF.LIB'), ('03', 'REF.ENC'), ('070', 'SOC.MEDIA'), ('0', 'REF.ENC'),
    ('159.9', 'SOC.PSY'), ('13', 'PHIL.ESO'), ('1', 'PHIL.PHIL'), ('2', 'PHIL.REL'),
    ('30', 'SOC.SOCIOL'), ('31', 'SOC.SOCIOL'), ('32', 'SOC.POL'), ('336', 'ECO.FIN'),
    ('339.1', 'ECO.MARK'), ('33', 'ECO.ECON'), ('34', 'LAW.LAW'), ('35', 'SOC.POL'), ('355', 'SOC.MIL'),
    ('356', 'SOC.MIL'), ('357', 'SOC.MIL'), ('358', 'SOC.MIL'), ('359', 'SOC.MIL'), ('37', 'SOC.EDU'),
    ('39', 'SOC.SOCIOL'), ('51', 'MATH.MATH'), ('52', 'SCI.PHYS'), ('53', 'SCI.PHYS'), ('54', 'SCI.CHEM'),
    ('55', 'EARTH.GEO'), ('56', 'SCI.BIO'), ('502', 'EARTH.ECOL'), ('504', 'EARTH.ECOL'),
    ('577', 'SCI.BIOCHEM'), ('578', 'MED.MICRO'), ('579', 'MED.MICRO'), ('57', 'SCI.BIO'),
    ('58', 'SCI.PLANT'), ('59', 'SCI.PLANT'),
    ('611.018', 'MED.HIST'), ('611.013', 'MED.HIST'), ('611', 'MED.ANAT'), ('612.8', 'MED.NEURO'),
    ('612', 'MED.PHYS'), ('613', 'HEALTH.FIT'), ('614', 'MED.PUBLIC'), ('615', 'MED.PHARM'),
    ('616-091', 'MED.PATH'), ('616-092', 'MED.PATH'), ('616-07', 'MED.DIAG'), ('616-08', 'MED.INT'),
    ('616.31', 'MED.DENT'), ('616.8', 'MED.NEUROL'), ('616.9', 'MED.MICRO'), ('616', 'MED.INT'),
    ('617', 'MED.SURG'), ('618', 'MED.WOMEN'), ('61', 'MED.GEN'),
    ('621.3', 'TECH.ELEC'), ('62', 'TECH.ENG'), ('63', 'TECH.AGRI'), ('641', 'HOME.COOK'),
    ('64', 'HOME.HOUSE'), ('658', 'ECO.MGMT'), ('659', 'ECO.MARK'), ('65', 'ECO.MGMT'),
    ('66', 'TECH.CHEMT'), ('67', 'TECH.ENG'), ('68', 'TECH.ENG'), ('69', 'TECH.BUILD'),
    ('71', 'ART.ARCH'), ('72', 'ART.ARCH'), ('77', 'ART.PHOTO'), ('78', 'ART.MUSIC'), ('791', 'ART.FILM'),
    ('792', 'ART.FILM'), ('793', 'ART.FILM'), ('794', 'HOME.GAMES'), ('796', 'SPORT.SPORT'),
    ('797', 'SPORT.SPORT'), ('798', 'SPORT.SPORT'), ('799', 'SPORT.SPORT'), ('7', 'ART.FINE'),
    ('811', 'LANG.LEARN'), ('81', 'LANG.LING'), ('82.0', 'LIT.STUDY'), ('82-1', 'FIC.POETRY'),
    ('82-2', 'FIC.POETRY'), ('82', 'FIC.PROSE'), ('821', 'FIC.PROSE'),
    ('929', 'LIT.BIO'), ('91', 'EARTH.TRAVEL'), ('94(47', 'HIST.RUS'), ('902', 'HIST.ARCH'),
    ('903', 'HIST.ARCH'), ('9', 'HIST.WORLD'),
]
BBK = [
    ('32.97', 'IT.GEN'), ('32.973', 'IT.GEN'), ('32.81', 'IT.AI'), ('32', 'TECH.ELEC'), ('22.1', 'MATH.MATH'),
    ('22.3', 'SCI.PHYS'), ('22.6', 'SCI.PHYS'), ('22', 'MATH.MATH'), ('24', 'SCI.CHEM'), ('26', 'EARTH.GEO'),
    ('28.072', 'SCI.BIOCHEM'), ('28.05', 'MED.HIST'), ('28.4', 'MED.MICRO'), ('28.5', 'SCI.PLANT'),
    ('28.6', 'SCI.PLANT'), ('28.706', 'MED.ANAT'), ('28.707.3', 'MED.PHYS'), ('28.991', 'MED.NEURO'),
    ('28.903', 'MED.PHYS'), ('28.7', 'SCI.BIO'), ('28.08', 'EARTH.ECOL'), ('28', 'SCI.BIO'),
    ('30', 'TECH.ENG'), ('31', 'TECH.ENG'), ('33', 'TECH.ENG'), ('34', 'TECH.ENG'), ('35', 'TECH.CHEMT'),
    ('36', 'TECH.CHEMT'), ('37', 'HOME.HOUSE'), ('38', 'TECH.BUILD'), ('39', 'TECH.ENG'), ('4', 'TECH.AGRI'),
    ('51', 'MED.PUBLIC'), ('52.5', 'MED.PATH'), ('52.6', 'MED.MICRO'), ('52.64', 'MED.MICRO'),
    ('52.8', 'MED.PHARM'), ('52', 'MED.GEN'), ('53', 'MED.DIAG'), ('54', 'MED.INT'), ('55', 'MED.MICRO'),
    ('56.1', 'MED.NEUROL'), ('56.6', 'MED.DENT'), ('56', 'MED.INT'), ('54.5', 'MED.SURG'), ('57', 'MED.WOMEN'),
    ('58', 'MED.GEN'), ('5', 'MED.GEN'),
    ('60.5', 'SOC.SOCIOL'), ('60', 'SOC.SOCIOL'), ('63.3(2', 'HIST.RUS'), ('63.4', 'HIST.ARCH'), ('63', 'HIST.WORLD'),
    ('65.26', 'ECO.FIN'), ('65.29', 'ECO.MGMT'), ('65.290', 'ECO.MGMT'), ('65.9', 'ECO.ECON'), ('65', 'ECO.ECON'),
    ('66', 'SOC.POL'), ('67', 'LAW.LAW'), ('68', 'SOC.MIL'), ('71', 'SOC.SOCIOL'), ('74', 'SOC.EDU'),
    ('75', 'SPORT.SPORT'), ('76', 'SOC.MEDIA'), ('77', 'ART.FILM'), ('78', 'REF.LIB'), ('80', 'LANG.LING'),
    ('81.2', 'LANG.LEARN'), ('81', 'LANG.LING'), ('83', 'LIT.STUDY'), ('84', 'FIC.PROSE'), ('85.1', 'ART.FINE'),
    ('85.11', 'ART.ARCH'), ('85.31', 'ART.MUSIC'), ('85.37', 'ART.FILM'), ('85.16', 'ART.PHOTO'), ('85', 'ART.FINE'),
    ('86', 'PHIL.REL'), ('87', 'PHIL.PHIL'), ('88', 'SOC.PSY'), ('92', 'REF.ENC'), ('9', 'REF.ENC'),
]
DDC = [
    ('006.3', 'IT.AI'), ('005.8', 'IT.SYS'), ('005', 'IT.PROG'), ('004.6', 'IT.SYS'), ('004', 'IT.GEN'),
    ('006', 'IT.GEN'), ('01', 'REF.LIB'), ('02', 'REF.LIB'), ('03', 'REF.ENC'), ('07', 'SOC.MEDIA'), ('0', 'REF.ENC'),
    ('13', 'PHIL.ESO'), ('158', 'HEALTH.SELF'), ('15', 'SOC.PSY'), ('1', 'PHIL.PHIL'), ('2', 'PHIL.REL'),
    ('30', 'SOC.SOCIOL'), ('306.8', 'HEALTH.FAMILY'), ('32', 'SOC.POL'), ('332.024', 'ECO.FIN'), ('332', 'ECO.FIN'),
    ('33', 'ECO.ECON'), ('34', 'LAW.LAW'), ('35', 'SOC.POL'), ('355', 'SOC.MIL'), ('36', 'SOC.SOCIOL'),
    ('37', 'SOC.EDU'), ('38', 'ECO.ECON'), ('39', 'SOC.SOCIOL'), ('4', 'LANG.LEARN'), ('41', 'LANG.LING'),
    ('51', 'MATH.MATH'), ('52', 'SCI.PHYS'), ('53', 'SCI.PHYS'), ('54', 'SCI.CHEM'), ('55', 'EARTH.GEO'),
    ('56', 'SCI.BIO'), ('572', 'SCI.BIOCHEM'), ('579', 'MED.MICRO'), ('577', 'EARTH.ECOL'), ('57', 'SCI.BIO'),
    ('58', 'SCI.PLANT'), ('59', 'SCI.PLANT'), ('5', 'SCI.BIO'),
    ('611.018', 'MED.HIST'), ('611', 'MED.ANAT'), ('612.8', 'MED.NEURO'), ('612', 'MED.PHYS'),
    ('613', 'HEALTH.FIT'), ('614', 'MED.PUBLIC'), ('615', 'MED.PHARM'), ('616.07', 'MED.PATH'),
    ('616.075', 'MED.DIAG'), ('616.8', 'MED.NEUROL'), ('616.9', 'MED.MICRO'), ('616.079', 'MED.MICRO'),
    ('616', 'MED.INT'), ('617.6', 'MED.DENT'), ('617', 'MED.SURG'), ('618', 'MED.WOMEN'), ('610.73', 'MED.NURSE'),
    ('61', 'MED.GEN'), ('621.3', 'TECH.ELEC'), ('62', 'TECH.ENG'), ('63', 'TECH.AGRI'), ('641', 'HOME.COOK'),
    ('64', 'HOME.HOUSE'), ('658.8', 'ECO.MARK'), ('65', 'ECO.MGMT'), ('66', 'TECH.CHEMT'), ('67', 'TECH.ENG'),
    ('68', 'TECH.ENG'), ('69', 'TECH.BUILD'), ('72', 'ART.ARCH'), ('74', 'ART.ARCH'), ('77', 'ART.PHOTO'),
    ('78', 'ART.MUSIC'), ('791', 'ART.FILM'), ('792', 'ART.FILM'), ('793', 'HOME.GAMES'), ('794', 'HOME.GAMES'),
    ('795', 'HOME.GAMES'), ('796', 'SPORT.SPORT'), ('797', 'SPORT.SPORT'), ('798', 'SPORT.SPORT'),
    ('799', 'SPORT.SPORT'), ('7', 'ART.FINE'), ('80', 'LIT.STUDY'), ('8', 'FIC.PROSE'), ('920', 'LIT.BIO'),
    ('92', 'LIT.BIO'), ('91', 'EARTH.TRAVEL'), ('947', 'HIST.RUS'), ('930.1', 'HIST.ARCH'), ('9', 'HIST.WORLD'),
]

# --- переходники: LCC и NLM (класс + диапазон номера) ----------------------------------------
# (буквы класса, от, до, тема); номер — целая часть после букв; None — весь класс.
LCC = [
    ('A', None, None, 'REF.ENC'), ('B', 1, 5802, 'PHIL.PHIL'), ('BC', None, None, 'PHIL.PHIL'),
    ('BD', None, None, 'PHIL.PHIL'), ('BF', 1, 990, 'SOC.PSY'), ('BF', 1001, 1389, 'PHIL.ESO'),
    ('BF', 1404, 2055, 'PHIL.ESO'), ('BF', 637, 637, 'HEALTH.SELF'), ('BH', None, None, 'PHIL.PHIL'),
    ('BJ', None, None, 'PHIL.PHIL'), ('BL', None, None, 'PHIL.REL'), ('BM', None, None, 'PHIL.REL'),
    ('BP', None, None, 'PHIL.REL'), ('BQ', None, None, 'PHIL.REL'), ('BR', None, None, 'PHIL.REL'),
    ('BS', None, None, 'PHIL.REL'), ('BT', None, None, 'PHIL.REL'), ('BV', None, None, 'PHIL.REL'),
    ('BX', None, None, 'PHIL.REL'), ('C', None, None, 'HIST.WORLD'), ('CC', None, None, 'HIST.ARCH'),
    ('CT', None, None, 'LIT.BIO'), ('D', None, None, 'HIST.WORLD'), ('DK', None, None, 'HIST.RUS'),
    ('E', None, None, 'HIST.WORLD'), ('F', None, None, 'HIST.WORLD'), ('G', None, None, 'EARTH.TRAVEL'),
    ('GB', None, None, 'EARTH.GEO'), ('GC', None, None, 'EARTH.GEO'), ('GE', None, None, 'EARTH.ECOL'),
    ('GN', None, None, 'SOC.SOCIOL'), ('GT', None, None, 'SOC.SOCIOL'), ('GV', 1, 1197, 'SPORT.SPORT'),
    ('GV', 1199, 1570, 'HOME.GAMES'), ('GV', 1580, 1799, 'ART.FILM'), ('H', None, None, 'SOC.SOCIOL'),
    ('HA', None, None, 'MATH.MATH'), ('HB', None, None, 'ECO.ECON'), ('HC', None, None, 'ECO.ECON'),
    ('HD', 28, 70, 'ECO.MGMT'), ('HD', None, None, 'ECO.ECON'), ('HE', None, None, 'ECO.ECON'),
    ('HF', 5410, 5417, 'ECO.MARK'), ('HF', 5801, 6182, 'ECO.MARK'), ('HF', None, None, 'ECO.MGMT'),
    ('HG', None, None, 'ECO.FIN'), ('HJ', None, None, 'ECO.FIN'), ('HM', None, None, 'SOC.SOCIOL'),
    ('HN', None, None, 'SOC.SOCIOL'), ('HQ', None, None, 'HEALTH.FAMILY'), ('HS', None, None, 'SOC.SOCIOL'),
    ('HT', None, None, 'SOC.SOCIOL'), ('HV', None, None, 'SOC.SOCIOL'), ('HX', None, None, 'SOC.POL'),
    ('J', None, None, 'SOC.POL'), ('K', None, None, 'LAW.LAW'), ('L', None, None, 'SOC.EDU'),
    ('M', None, None, 'ART.MUSIC'), ('N', None, None, 'ART.FINE'), ('NA', None, None, 'ART.ARCH'),
    ('NK', None, None, 'ART.ARCH'), ('P', 1, 1091, 'LANG.LING'), ('PA', None, None, 'LANG.LEARN'),
    ('PB', None, None, 'LANG.LEARN'), ('PC', None, None, 'LANG.LEARN'), ('PD', None, None, 'LANG.LEARN'),
    ('PE', None, None, 'LANG.LEARN'), ('PF', None, None, 'LANG.LEARN'), ('PG', 1, 2790, 'LANG.LEARN'),
    ('PG', 2900, 3698, 'FIC.PROSE'), ('PH', None, None, 'LANG.LEARN'), ('PJ', None, None, 'LANG.LEARN'),
    ('PK', None, None, 'LANG.LEARN'), ('PL', None, None, 'LANG.LEARN'), ('PM', None, None, 'LANG.LEARN'),
    ('PN', 1, 1009, 'LIT.STUDY'), ('PN', 1010, 1590, 'FIC.POETRY'), ('PN', 1991, 1999, 'ART.FILM'),
    ('PN', 2000, 3307, 'ART.FILM'), ('PN', 4699, 5650, 'SOC.MEDIA'), ('PN', None, None, 'LIT.STUDY'),
    ('PQ', None, None, 'FIC.PROSE'), ('PR', None, None, 'FIC.PROSE'), ('PS', None, None, 'FIC.PROSE'),
    ('PT', None, None, 'FIC.PROSE'), ('PZ', None, None, 'FIC.CHILD'), ('Q', None, None, 'SCI.BIO'),
    ('QA', 75, 76, 'IT.GEN'), ('QA', None, None, 'MATH.MATH'), ('QB', None, None, 'SCI.PHYS'),
    ('QC', None, None, 'SCI.PHYS'), ('QD', None, None, 'SCI.CHEM'), ('QE', None, None, 'EARTH.GEO'),
    ('QH', 540, 549, 'EARTH.ECOL'), ('QH', None, None, 'SCI.BIO'), ('QK', None, None, 'SCI.PLANT'),
    ('QL', None, None, 'SCI.PLANT'), ('QM', 550, 699, 'MED.HIST'), ('QM', None, None, 'MED.ANAT'),
    ('QP', 351, 495, 'MED.NEURO'), ('QP', 501, 801, 'SCI.BIOCHEM'), ('QP', None, None, 'MED.PHYS'),
    ('QR', None, None, 'MED.MICRO'), ('R', 131, 687, 'HIST.SCI'), ('R', None, None, 'MED.GEN'),
    ('RA', None, None, 'MED.PUBLIC'), ('RB', None, None, 'MED.PATH'), ('RC', 321, 580, 'MED.NEUROL'),
    ('RC', None, None, 'MED.INT'), ('RD', None, None, 'MED.SURG'), ('RE', None, None, 'MED.SURG'),
    ('RF', None, None, 'MED.SURG'), ('RG', None, None, 'MED.WOMEN'), ('RJ', None, None, 'MED.WOMEN'),
    ('RK', None, None, 'MED.DENT'), ('RL', None, None, 'MED.INT'), ('RM', None, None, 'MED.PHARM'),
    ('RS', None, None, 'MED.PHARM'), ('RT', None, None, 'MED.NURSE'), ('RZ', None, None, 'MED.GEN'),
    ('S', None, None, 'TECH.AGRI'), ('T', None, None, 'TECH.ENG'), ('TA', None, None, 'TECH.ENG'),
    ('TH', None, None, 'TECH.BUILD'), ('TK', None, None, 'TECH.ELEC'), ('TP', None, None, 'TECH.CHEMT'),
    ('TR', None, None, 'ART.PHOTO'), ('TT', None, None, 'HOME.HOUSE'), ('TX', None, None, 'HOME.COOK'),
    ('U', None, None, 'SOC.MIL'), ('V', None, None, 'SOC.MIL'), ('Z', None, None, 'REF.LIB'),
]
NLM = [
    ('QS', 504, 639, 'MED.HIST'), ('QS', None, None, 'MED.ANAT'), ('QT', None, None, 'MED.PHYS'),
    ('QU', None, None, 'SCI.BIOCHEM'), ('QV', None, None, 'MED.PHARM'), ('QW', None, None, 'MED.MICRO'),
    ('QX', None, None, 'MED.MICRO'), ('QY', None, None, 'MED.DIAG'), ('QZ', None, None, 'MED.PATH'),
    ('W', None, None, 'MED.GEN'), ('WA', None, None, 'MED.PUBLIC'), ('WB', None, None, 'MED.INT'),
    ('WC', None, None, 'MED.MICRO'), ('WL', 102, 104, 'MED.NEURO'), ('WL', None, None, 'MED.NEUROL'),
    ('WM', None, None, 'MED.NEUROL'), ('WN', None, None, 'MED.DIAG'), ('WO', None, None, 'MED.SURG'),
    ('WP', None, None, 'MED.WOMEN'), ('WQ', None, None, 'MED.WOMEN'), ('WS', None, None, 'MED.WOMEN'),
    ('WU', None, None, 'MED.DENT'), ('WY', None, None, 'MED.NURSE'), ('WZ', None, None, 'HIST.SCI'),
]
for _l in ('WD', 'WE', 'WF', 'WG', 'WH', 'WI', 'WJ', 'WK', 'WR', 'WT', 'WV', 'WW', 'WX'):
    NLM.append((_l, None, None, 'MED.INT'))

_DECIMAL = {'УДК': UDC, 'UDC': UDC, 'ББК': BBK, 'BBK': BBK, 'DDC': DDC}
_LETTERS = {'LC': LCC, 'LCC': LCC, 'NLM': NLM}
_CLASS = re.compile(r'^([A-Z]{1,3})\s*(\d+)?')


def _norm_decimal(value):
    """Первый код без пробелов, штрихов и слешей: «611'.018—dc23» → «611.018»,
    «32.973.202+32.988.02 УДК 004.73» → «32.973.202» (составной код — по первой части)."""
    v = value.strip().split(' ')[0].split('+')[0]
    v = v.replace("'", '').replace('’', '').replace('/', '')
    return re.split(r'[—–]|dc\d', v)[0]


def topic_and_detail(kind, value):
    """(тема, подробность) для одного кода или (None, 0). Подробность — длина совпавшего
    начала кода (у LCC и NLM: 3 — диапазон номера, 1 — весь класс): чем она больше,
    тем точнее код говорит о теме."""
    if kind in _DECIMAL:
        v = _norm_decimal(value)
        hits = [(len(p), t) for p, t in _DECIMAL[kind] if v.startswith(p)]
        return (max(hits)[1], max(hits)[0]) if hits else (None, 0)
    t = _letters_topic(kind, value)
    return (t[0], t[1]) if t else (None, 0)


def topic_of_code(kind, value):
    """Тема каркаса для одного кода каталога или None (код не узнан)."""
    return topic_and_detail(kind, value)[0]


def _letters_topic(kind, value):
    """LCC и NLM: (тема, подробность) по классу и диапазону номера или None."""
    if kind in _LETTERS:
        m = _CLASS.match(value.strip().upper())
        if not m:
            return None
        letters, number = m.group(1), int(m.group(2)) if m.group(2) else None
        whole, ranges = None, []
        for cls, lo, hi, topic in _LETTERS[kind]:
            if cls != letters:
                continue
            if lo is None:
                whole = whole or topic  # весь класс — если нет подходящего диапазона
            elif number is not None and lo <= number <= hi:
                ranges.append((hi - lo, topic))
        if ranges:
            return min(ranges)[1], 3  # самый узкий диапазон точнее («BF 637» внутри «BF 1–990»)
        if whole:
            return whole, 1
        # нет такого двухбуквенного класса — пробуем первую букву (LCC «QZ…» нет, а «Q» есть)
        for cls, lo, hi, topic in _LETTERS[kind]:
            if cls == letters[0] and lo is None:
                return topic, 1
        return None
    return None


def topic_of_codes(codes):
    """Тема по всем кодам паспорта книги или None.

    Один и тот же код, прочитанный дважды (с титула и с оборота), голосует один раз.
    Побеждает большинство голосов; при равенстве — тема самого подробного кода
    («УДК 611.018» — гистология — точнее «ББК 28.706» — анатомия); полная ничья — None.
    """
    seen, votes, detail = set(), collections.Counter(), collections.defaultdict(int)
    for kind, value in codes:
        key = (kind, _norm_decimal(value) if kind in _DECIMAL else value.strip().upper())
        if key in seen:
            continue
        seen.add(key)
        t, d = topic_and_detail(kind, value)
        if t:
            votes[t] += 1
            detail[t] = max(detail[t], d)
    if not votes:
        return None
    ranked = sorted(votes, key=lambda t: (-votes[t], -detail[t], t))
    first, rest = ranked[0], ranked[1:]
    if rest and (votes[rest[0]], detail[rest[0]]) == (votes[first], detail[first]):
        return None
    return first
