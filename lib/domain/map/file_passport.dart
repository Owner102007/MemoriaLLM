/// Паспорт файла книги — что это за PDF, без чтения текста и без
/// нейросети (ALG-MAP-18, F-MAP-18, шаг S58).
///
/// Прежде чем верить тексту книги, надо знать, что за файл перед нами:
/// электронный оригинал, скан с распознанным слоем или скан вовсе без
/// текста. Паспорт отвечает по фактам о страницах, которые собирает один
/// проход по объектам PDF без отрисовки
/// (`infrastructure/pdf/pdfium_passport.dart`). Здесь — только правило:
/// чистые функции, ни PDFium, ни файлов.
///
/// Правило — дословный перенос `паспорт.py` шага 46 (исследование
/// СНО2026, `Система сортировки/`): там же проверено на 18 книгах
/// литературы. Расширяет ALG-PDF-24 («есть ли текст» по первым
/// страницам): здесь вид каждой страницы и книги целиком.
library;

/// Картинка не меньше этой доли страницы — «лист-картинка», то есть скан.
const double kBigImageShare = 0.6;

/// Меньше этого числа знаков слоя — текста на странице нет.
const int kMinPageChars = 40;

/// Вид страницы.
enum PageKind {
  /// Знаки есть, большой картинки нет — набранный текст.
  text,

  /// Большая картинка и знаки поверх неё — скан с распознанным слоем.
  scanWithLayer,

  /// Большая картинка без знаков — скан без текста.
  scanNoLayer,

  /// Ни знаков, ни большой картинки.
  empty,
}

/// Вид книги.
enum BookKind {
  /// Набранная книга: текст у ≥ 80 % страниц.
  digital,

  /// Скан с распознанным слоем у ≥ половины страниц.
  scanWithLayer,

  /// Скан без текста у ≥ половины страниц.
  scanNoLayer,

  /// Ни то ни другое.
  mixed,
}

/// Цветность скана.
enum ScanColor {
  /// Чёрно-белый: 1 бит на точку.
  blackWhite,

  /// Серый: до 8 бит.
  gray,

  /// Цветной.
  color,
}

/// Что проход по объектам узнал об одной странице.
class PageFacts {
  /// Создаёт факты страницы.
  const PageFacts({
    required this.chars,
    required this.imageShare,
    this.textObjects = 0,
    this.invisibleTextObjects = 0,
    this.images = 0,
    this.paths = 0,
    this.dpi,
    this.bitsPerPixel,
  });

  /// Сколько знаков в текстовом слое страницы.
  final int chars;

  /// Доля площади страницы под самой большой картинкой, от 0 до 1.
  final double imageShare;

  /// Сколько текстовых объектов.
  final int textObjects;

  /// Из них невидимых (режим вывода 3): так кладут слой распознавания
  /// поверх картинки.
  final int invisibleTextObjects;

  /// Сколько картинок.
  final int images;

  /// Сколько векторных объектов (линии, заливки).
  final int paths;

  /// Разрешение самой большой картинки, точек на дюйм; `null` — не
  /// узнать.
  final double? dpi;

  /// Бит на точку у самой большой картинки; `null` — не узнать.
  final int? bitsPerPixel;

  /// Есть ли на странице лист-картинка.
  bool get bigImage => imageShare >= kBigImageShare;
}

/// Вид страницы по её фактам (ALG-MAP-18, шаг 2).
PageKind pageKindOf(PageFacts page) {
  final bool hasText = page.chars >= kMinPageChars;
  if (page.bigImage) {
    return hasText ? PageKind.scanWithLayer : PageKind.scanNoLayer;
  }
  return hasText ? PageKind.text : PageKind.empty;
}

/// Цветность по числу бит на точку.
ScanColor colorOf(int bitsPerPixel) {
  if (bitsPerPixel <= 1) return ScanColor.blackWhite;
  if (bitsPerPixel <= 8) return ScanColor.gray;
  return ScanColor.color;
}

/// Паспорт книги.
class FilePassport {
  /// Создаёт паспорт.
  const FilePassport({
    required this.pageKinds,
    required this.kind,
    this.dpiMedian,
    this.color,
    this.producer = '',
    this.creator = '',
    this.bookmarks = 0,
  });

  /// Вид каждой страницы, по порядку.
  final List<PageKind> pageKinds;

  /// Вид книги.
  final BookKind kind;

  /// Медиана разрешения по страницам-сканам; `null` — сканов нет.
  final double? dpiMedian;

  /// Самая частая цветность сканов; `null` — сканов нет.
  final ScanColor? color;

  /// Программа, сохранившая файл (`Producer`).
  final String producer;

  /// Программа, создавшая документ (`Creator`).
  final String creator;

  /// Сколько закладок (пунктов оглавления) в файле.
  final int bookmarks;

  /// Сколько страниц такого вида.
  int count(PageKind kind) =>
      pageKinds.where((PageKind page) => page == kind).length;
}

/// Паспорт книги по фактам её страниц (ALG-MAP-18, шаги 3–5).
///
/// Вид книги: «текст» у ≥ 80 % страниц — электронный оригинал; «скан
/// со слоем» у ≥ половины — скан со слоем; «скан без слоя» у ≥ половины
/// — скан без слоя; иначе — смешанный. Пустые страницы в знаменателе
/// считаются, как в шаге 46. Сломанный слой паспорт не видит — это
/// работа доверия (ALG-MAP-19).
FilePassport passportOf(
  List<PageFacts> pages, {
  String producer = '',
  String creator = '',
  int bookmarks = 0,
}) {
  final List<PageKind> kinds = <PageKind>[
    for (final PageFacts page in pages) pageKindOf(page),
  ];
  final int n = kinds.length;
  int countOf(PageKind kind) => kinds.where((PageKind k) => k == kind).length;
  final BookKind kind;
  if (n > 0 && countOf(PageKind.text) >= 0.8 * n) {
    kind = BookKind.digital;
  } else if (n > 0 && countOf(PageKind.scanWithLayer) >= 0.5 * n) {
    kind = BookKind.scanWithLayer;
  } else if (n > 0 && countOf(PageKind.scanNoLayer) >= 0.5 * n) {
    kind = BookKind.scanNoLayer;
  } else {
    kind = BookKind.mixed;
  }
  // Качество скана — только по страницам-сканам.
  final List<double> dpis = <double>[];
  final List<int> bits = <int>[];
  for (int i = 0; i < n; i++) {
    if (kinds[i] != PageKind.scanWithLayer &&
        kinds[i] != PageKind.scanNoLayer) {
      continue;
    }
    final double? dpi = pages[i].dpi;
    if (dpi != null && dpi > 0) dpis.add(dpi);
    final int? bpp = pages[i].bitsPerPixel;
    if (bpp != null && bpp > 0) bits.add(bpp);
  }
  dpis.sort();
  return FilePassport(
    pageKinds: kinds,
    kind: kind,
    // Как в шаге 46: средний элемент, при чётном числе — верхний из двух.
    dpiMedian: dpis.isEmpty ? null : dpis[dpis.length ~/ 2],
    color: bits.isEmpty ? null : colorOf(_mostFrequent(bits)),
    producer: producer.trim(),
    creator: creator.trim(),
    bookmarks: bookmarks,
  );
}

/// Самое частое число; при равенстве — большее (в шаге 46 равенство
/// решал порядок множества — здесь правило явное).
int _mostFrequent(List<int> values) {
  final Map<int, int> counts = <int, int>{};
  for (final int value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  int best = values.first;
  for (final MapEntry<int, int> entry in counts.entries) {
    final int have = counts[best]!;
    if (entry.value > have || (entry.value == have && entry.key > best)) {
      best = entry.key;
    }
  }
  return best;
}
