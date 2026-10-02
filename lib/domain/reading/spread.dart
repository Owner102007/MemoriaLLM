/// Лист из нескольких страниц: листание и рамка — чистая математика.
///
/// Лист — это то, что лежит на экране целиком: одна страница или две
/// страницы разворота рядом. Пока лист был одной страницей, слова
/// «следующая страница» и «рамка страницы» значили то же, что «следующий
/// лист» и «рамка листа». С разворотом это перестало быть правдой, а код
/// продолжал считать по-старому — отсюда два дефекта, которые здесь
/// закрыты (F-READ-06):
///
/// * BUG-01 — шаг вперёд вёл на следующую **страницу**, и каждый разворот
///   показывался дважды: страницы 2 и 3 лежат на одном листе;
/// * BUG-02 — рамка одной страницы, записанная в долях страницы,
///   прикладывалась к листу из двух страниц как доли листа: поле в 0,1
///   ширины страницы превращалось в 0,2, и край текста срезался.
///
/// Ни движка PDF, ни виджетов здесь нет, поэтому всё проверяется
/// исчерпывающе: проход по книге вперёд и назад, чётное и нечётное число
/// страниц, страницы разного размера.
library;

import 'fragments.dart';
import 'navigation.dart';
import 'reading.dart';

/// Насколько могут расходиться просветы двух страниц, чтобы считаться
/// одним просветом.
///
/// В долях высоты листа. Строки соседних страниц одной книги стоят на
/// одной сетке, и середины просветов совпадают почти точно; допуск нужен
/// на погрешность разбора. Он меньше половины обычного междустрочья,
/// поэтому граница, поставленная посередине между двумя просветами, не
/// задевает строку ни на одной из страниц.
const double kSheetBreakTolerance = 0.002;

/// Место на листе: с какой страницы лист и какая на нём полоса.
class SheetPosition {
  /// Создаёт место.
  const SheetPosition({required this.page, required this.fragment});

  /// Страница, с которой начинается лист.
  final int page;

  /// Номер полосы на листе, начиная с нуля.
  final int fragment;

  @override
  bool operator ==(Object other) {
    return other is SheetPosition &&
        other.page == page &&
        other.fragment == fragment;
  }

  @override
  int get hashCode => Object.hash(page, fragment);

  @override
  String toString() => 'SheetPosition(страница $page, полоса $fragment)';
}

/// Первая страница следующего листа; `null` — книга кончилась.
///
/// BUG-01: в развороте следующий лист начинается за **последней**
/// страницей текущего, а не за текущей страницей. Со страницы 2 шаг ведёт
/// на 4, а не на 3: тройка уже на экране.
int? nextSheetPage({
  required int page,
  required int pageCount,
  required bool spread,
}) {
  if (pageCount <= 0) {
    return null;
  }
  final int safe = clampPage(page, pageCount);
  final int last = spread ? spreadPages(safe, pageCount).last : safe;
  return last >= pageCount ? null : last + 1;
}

/// Первая страница предыдущего листа; `null` — это начало книги.
int? previousSheetPage({
  required int page,
  required int pageCount,
  required bool spread,
}) {
  if (pageCount <= 0) {
    return null;
  }
  final int safe = clampPage(page, pageCount);
  final int first = spread ? spreadPages(safe, pageCount).first : safe;
  if (first <= 1) {
    return null;
  }
  return spread ? spreadPages(first - 1, pageCount).first : first - 1;
}

/// Шаг чтения вперёд или назад; `null` — шагать некуда.
///
/// Сначала полосы листа, потом соседний лист: вперёд читатель попадает в
/// его первую полосу, назад — в последнюю, то есть в низ предыдущего
/// листа, а не в его начало.
///
/// Счёт идёт от переданного места, а не от того, что сейчас на экране:
/// так два быстрых нажатия подряд дают два шага, даже если первый переход
/// ещё не закончился (BUG-11).
SheetPosition? stepSheet({
  required int page,
  required int fragment,
  required int pageCount,
  required int fragmentCount,
  required bool spread,
  required bool forward,
}) {
  final int count = fragmentCount < 1 ? 1 : fragmentCount;
  final int safePage = clampPage(page, pageCount);
  final int safeFragment = clampFragment(fragment, count);
  if (forward) {
    if (safeFragment + 1 < count) {
      return SheetPosition(page: safePage, fragment: safeFragment + 1);
    }
    final int? next = nextSheetPage(
      page: safePage,
      pageCount: pageCount,
      spread: spread,
    );
    return next == null ? null : SheetPosition(page: next, fragment: 0);
  }
  if (safeFragment > 0) {
    return SheetPosition(page: safePage, fragment: safeFragment - 1);
  }
  final int? previous = previousSheetPage(
    page: safePage,
    pageCount: pageCount,
    spread: spread,
  );
  return previous == null
      ? null
      : SheetPosition(page: previous, fragment: count - 1);
}

/// Страница листа: её размеры, рамка содержимого и просветы между строк.
///
/// Рамка и просветы записаны в долях **страницы** — так их считает разбор
/// страницы. В доли листа их переводят [sheetContent] и [sheetBreaks].
class SheetPage {
  /// Создаёт страницу листа.
  const SheetPage({
    required this.width,
    required this.height,
    required this.content,
    this.breaks = const <double>[],
  });

  /// Ширина страницы в точках.
  final double width;

  /// Высота страницы в точках.
  final double height;

  /// Рамка содержимого в долях страницы.
  final CropBox content;

  /// Просветы между строками в долях высоты страницы.
  final List<double> breaks;

  /// Есть ли у страницы размеры, с которыми можно считать.
  bool get isUsable =>
      width.isFinite && height.isFinite && width > 0 && height > 0;
}

/// Рамка листа в долях листа — объединение рамок его страниц.
///
/// BUG-02: страницы лежат на листе в ряд, вплотную, прижатые к верхнему
/// краю (так их кладёт просмотрщик). Рамка каждой переводится из долей
/// страницы в доли листа, и берётся прямоугольник, накрывающий все:
/// слева — поле левой страницы, справа — поле правой, сверху и снизу —
/// меньшее из полей. Текст ни одной страницы при этом не срезается.
///
/// Лист из одной страницы возвращает её рамку **как есть**, без единого
/// арифметического действия: иначе погрешность деления сдвинула бы рамку
/// на последний знак, а она сравнивается на равенство.
CropBox sheetContent(List<SheetPage> pages) {
  if (pages.isEmpty) {
    return CropBox.full;
  }
  if (pages.length == 1) {
    return pages.first.content;
  }
  double width = 0;
  double height = 0;
  for (final SheetPage page in pages) {
    if (!page.isUsable) {
      continue;
    }
    width += page.width;
    height = height < page.height ? page.height : height;
  }
  if (width <= 0 || height <= 0) {
    return CropBox.full;
  }

  double left = double.infinity;
  double top = double.infinity;
  double right = double.negativeInfinity;
  double bottom = double.negativeInfinity;
  double x = 0;
  for (final SheetPage page in pages) {
    if (!page.isUsable) {
      continue;
    }
    // Рамки нет или она испорчена — страница входит целиком: лучше
    // показать лишнее поле, чем срезать текст.
    final CropBox box = page.content.isValid ? page.content : CropBox.full;
    final double boxLeft = (x + box.left * page.width) / width;
    final double boxRight = (x + box.right * page.width) / width;
    final double boxTop = box.top * page.height / height;
    final double boxBottom = box.bottom * page.height / height;
    left = boxLeft < left ? boxLeft : left;
    right = boxRight > right ? boxRight : right;
    top = boxTop < top ? boxTop : top;
    bottom = boxBottom > bottom ? boxBottom : bottom;
    x += page.width;
  }

  final CropBox result = CropBox(
    left: _unit(left),
    top: _unit(top),
    right: _unit(right),
    bottom: _unit(bottom),
  );
  return result.isValid ? result : CropBox.full;
}

/// Просветы листа в долях его высоты — общие для всех его страниц.
///
/// Полоса полразворота идёт через обе страницы сразу, и граница между
/// полосами обязана попасть в просвет на **каждой** из них: просвет одной
/// страницы на другой может прийтись на середину строки. Общего просвета
/// рядом с границей нет — значит, список здесь пуст, и деление поступит
/// как на странице без просветов: полосы слегка перекроются, строка
/// повторится, но не пропадёт.
///
/// Страница без просветов (пустая, с одной картинкой, ещё не разобранная)
/// ограничений не ставит: резать её можно где угодно.
List<double> sheetBreaks(
  List<SheetPage> pages, {
  double tolerance = kSheetBreakTolerance,
}) {
  if (pages.isEmpty) {
    return const <double>[];
  }
  if (pages.length == 1) {
    return pages.first.breaks;
  }
  double height = 0;
  for (final SheetPage page in pages) {
    if (page.isUsable && page.height > height) {
      height = page.height;
    }
  }
  if (height <= 0) {
    return const <double>[];
  }
  List<double>? common;
  for (final SheetPage page in pages) {
    if (!page.isUsable || page.breaks.isEmpty) {
      continue;
    }
    final List<double> scaled = <double>[
      for (final double at in page.breaks) at * page.height / height,
    ];
    common = common == null ? scaled : _shared(common, scaled, tolerance);
  }
  return common ?? const <double>[];
}

/// Просветы, которые есть в обоих списках, — серединой между парой.
List<double> _shared(List<double> first, List<double> second, double reach) {
  final List<double> shared = <double>[];
  for (final double at in first) {
    double? nearest;
    double distance = reach;
    for (final double other in second) {
      final double gap = (at - other).abs();
      if (gap <= distance) {
        distance = gap;
        nearest = other;
      }
    }
    if (nearest != null) {
      shared.add((at + nearest) / 2);
    }
  }
  return shared;
}

double _unit(double value) {
  if (!value.isFinite || value < 0) {
    return 0;
  }
  return value > 1 ? 1 : value;
}
