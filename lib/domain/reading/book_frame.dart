/// Рамка обрезки на книгу — чистая математика (F-READ-15, ALG-PDF-11).
///
/// Прежде прямоугольник содержимого у каждой страницы был свой, и ширина
/// текста менялась от страницы к странице: страница с полосной
/// иллюстрацией давала одну рамку, страница с одной концевой строкой —
/// другую. Читатель видел это как «текст прыгает и меняет кегль при
/// листании». Здесь рамка — статистика книги: по выборке страниц,
/// разбросанных по ней, берётся устойчивый прямоугольник, один на все
/// страницы.
///
/// На книгу переезжает только прямоугольник содержимого. Просветы между
/// строками и колонки остаются у страницы: они у каждой свои, и их
/// подмена вернула бы полосы, рассекающие строку.
library;

import 'reading.dart';
import 'text_geometry.dart';

/// Сколько страниц идёт в выборку.
const int kBookFrameSample = 16;

/// Скольких пригодных страниц выборке хватает; меньше — выборка
/// добирается соседними страницами.
const int kBookFrameEnough = 8;

/// Какая доля книги с каждого края в выборку не идёт.
///
/// Начало книги — титул, посвящение и оглавление, конец — указатели и
/// выходные данные: о вёрстке книги по ним судить нельзя.
const double kBookFrameEdge = 0.05;

/// Сколько страниц каждой чётности нужно, чтобы судить о зеркальных
/// полях.
const int kMirrorMinSamples = 3;

/// Меньший сдвиг между чётными и нечётными страницами зеркальными полями
/// не считается, в долях ширины страницы.
const double kMirrorThreshold = 0.01;

/// На сколько зеркальная рамка обязана быть уже общей, чтобы её взяли,
/// в долях ширины страницы.
const double kMirrorGain = 0.005;

/// На сколько рамка страницы может выходить за рамку книги, не считаясь
/// вышедшей.
///
/// Равно запасу, который автообрезка оставляет вокруг символов
/// (`CropOptions.padding`): пока рамка страницы шире рамки книги не
/// больше чем на запас, сами символы лежат внутри рамки книги. Запас
/// автообрезка округляет наружу, поэтому ошибка здесь — только в сторону
/// «расширить лишний раз».
const double kBookFrameTolerance = 0.01;

/// Рамка одной страницы выборки.
class FrameSample {
  /// Создаёт запись выборки.
  const FrameSample({required this.page, required this.content});

  /// Страница, начиная с единицы.
  final int page;

  /// Прямоугольник содержимого страницы в долях страницы.
  final CropBox content;

  /// Годится ли страница в выборку.
  ///
  /// Пустая страница и страница, на которой содержимого не нашлось,
  /// отдают страницу целиком — о полях книги они не говорят ничего.
  bool get isUsable => content.isValid && content != CropBox.full;
}

/// Страницы выборки для книги из [pageCount] страниц.
///
/// Страницы разбросаны по книге равномерно, а не идут подряд с начала:
/// там титул и пустые листы. Чётные и нечётные чередуются — у книги из
/// переплёта поля зеркальны, и выборке нужны обе стороны разворота.
///
/// [attempt] — номер добора: нулевой отдаёт основную выборку, следующий —
/// страницы через одну от неё, той же чётности. Короткая книга идёт в
/// выборку целиком, и добирать в ней не из чего.
List<int> bookFrameSamplePages(
  int pageCount, {
  int attempt = 0,
  int count = kBookFrameSample,
}) {
  if (pageCount <= 0 || count <= 0 || attempt < 0) {
    return const <int>[];
  }
  if (pageCount <= count) {
    return attempt == 0
        ? <int>[for (int page = 1; page <= pageCount; page++) page]
        : const <int>[];
  }
  final int skip = (pageCount * kBookFrameEdge).floor();
  final int first = 1 + skip;
  final int last = pageCount - skip;
  final double step = (last - first + 1) / count;
  final Set<int> pages = <int>{};
  for (int i = 0; i < count; i++) {
    int page = first + ((i + 0.5) * step).floor();
    // Нечётные места выборки — чётным страницам, чётные — нечётным.
    if (page.isEven == i.isEven) {
      page = page < last ? page + 1 : page - 1;
    }
    page += attempt * 2;
    if (page >= 1 && page <= pageCount) {
      pages.add(page);
    }
  }
  return pages.toList();
}

/// Сколько страниц выборки пригодны для расчёта.
int usableSampleCount(List<FrameSample> samples) {
  int count = 0;
  for (final FrameSample sample in samples) {
    if (sample.isUsable) {
      count++;
    }
  }
  return count;
}

/// Рамка книги по выборке страниц.
///
/// Каждая сторона берётся **почти самой широкой** по выборке: восьмая
/// часть страниц с каждой стороны считается выбросами и в счёт не идёт.
/// Самая широкая рамка растянула бы рамку всей книги из-за одной
/// полосной картинки, средняя срезала бы текст у половины страниц.
/// Ошибка остаётся в сторону «обрезать меньше»: страница с содержимым
/// уже обычного на рамку не влияет вовсе.
///
/// Если поля чётных и нечётных страниц зеркальны, рамка считается по
/// страницам, сдвинутым друг к другу, и получает сдвиг чётных страниц —
/// но только когда так она выходит уже общей.
BookFrame bookFrameFromSamples(
  List<FrameSample> samples, {
  required bool ignoreRunningHeads,
}) {
  final List<FrameSample> usable = <FrameSample>[
    for (final FrameSample sample in samples)
      if (sample.isUsable) sample,
  ];
  if (usable.isEmpty) {
    return BookFrame(odd: CropBox.full, ignoreRunningHeads: ignoreRunningHeads);
  }
  final CropBox plain = _robustBox(usable, evenShift: 0);
  final double shift = _mirrorShift(usable);
  if (shift != 0) {
    final CropBox aligned = _robustBox(usable, evenShift: shift);
    if (aligned != CropBox.full && aligned.width < plain.width - kMirrorGain) {
      // Сдвиг не должен вывести рамку чётных страниц за край страницы.
      final double low = -aligned.left;
      final double high = 1 - aligned.right;
      final double safe = shift < low ? low : (shift > high ? high : shift);
      return BookFrame(
        odd: aligned,
        evenShift: safe,
        samples: usable.length,
        ignoreRunningHeads: ignoreRunningHeads,
      );
    }
  }
  return BookFrame(
    odd: plain,
    samples: plain == CropBox.full ? 0 : usable.length,
    ignoreRunningHeads: ignoreRunningHeads,
  );
}

/// Рамка страницы [page] внутри книги.
///
/// Обычная страница получает рамку книги как есть. Страница, чей текст
/// выходит за рамку книги дальше [tolerance] (широкая таблица, сноска на
/// поле), получает рамку, расширенную до этого текста: на ней одной
/// кегль мельче, зато ни один символ не срезан. [ownText] — рамка самой
/// страницы, посчитанная **по текстовому слою**; у скана её нет, и там
/// рамка книги стоит твёрдо: за неё на скане выходят пыль и тень
/// переплёта, из-за которых рамка и дрожала.
CropBox pageContentInBook({
  required BookFrame book,
  required int page,
  CropBox? ownText,
  double tolerance = kBookFrameTolerance,
}) {
  if (!book.hasContent) {
    return CropBox.full;
  }
  final CropBox base = book.forPage(page);
  final CropBox? own = ownText;
  if (own == null || !own.isValid || own == CropBox.full) {
    return base;
  }
  // Рамка страницы — её символы плюс запас автообрезки. Сравнивать с
  // рамкой книги надо сами символы, поэтому запас снимается; у края
  // страницы он был обрезан, и снимать там нечего.
  final double left = own.left <= 0 ? 0 : own.left + tolerance;
  final double top = own.top <= 0 ? 0 : own.top + tolerance;
  final double right = own.right >= 1 ? 1 : own.right - tolerance;
  final double bottom = own.bottom >= 1 ? 1 : own.bottom - tolerance;
  // Малый запас — на сравнение чисел с плавающей точкой: без него
  // страница, лежащая ровно на границе, считалась бы вышедшей.
  const double epsilon = 1e-9;
  final bool inside =
      left >= base.left - epsilon &&
      top >= base.top - epsilon &&
      right <= base.right + epsilon &&
      bottom <= base.bottom + epsilon;
  if (inside) {
    return base;
  }
  return CropBox(
    left: own.left < base.left ? own.left : base.left,
    top: own.top < base.top ? own.top : base.top,
    right: own.right > base.right ? own.right : base.right,
    bottom: own.bottom > base.bottom ? own.bottom : base.bottom,
  );
}

/// Сдвиг чётных страниц относительно нечётных; ноль — поля не зеркальны.
///
/// Сравниваются середины рамок, а не края: правый край гуляет вместе с
/// короткими строками, середина блока текста устойчивее. Медиана не
/// замечает титул и полосную картинку.
double _mirrorShift(List<FrameSample> usable) {
  final List<double> odd = <double>[];
  final List<double> even = <double>[];
  for (final FrameSample sample in usable) {
    final double center = (sample.content.left + sample.content.right) / 2;
    if (sample.page.isEven) {
      even.add(center);
    } else {
      odd.add(center);
    }
  }
  if (odd.length < kMirrorMinSamples || even.length < kMirrorMinSamples) {
    return 0;
  }
  final double shift = median(even) - median(odd);
  return shift.abs() < kMirrorThreshold ? 0 : shift;
}

/// Почти самая широкая рамка выборки; чётные страницы перед этим
/// сдвинуты на [evenShift] к нечётным.
CropBox _robustBox(List<FrameSample> usable, {required double evenShift}) {
  final List<double> lefts = <double>[];
  final List<double> tops = <double>[];
  final List<double> rights = <double>[];
  final List<double> bottoms = <double>[];
  for (final FrameSample sample in usable) {
    final double shift = sample.page.isEven ? evenShift : 0;
    lefts.add(sample.content.left - shift);
    tops.add(sample.content.top);
    rights.add(sample.content.right - shift);
    bottoms.add(sample.content.bottom);
  }
  lefts.sort();
  tops.sort();
  rights.sort();
  bottoms.sort();
  final int skip = usable.length ~/ 8;
  final int far = usable.length - 1 - skip;
  final double left = lefts[skip];
  final double right = rights[far];
  final CropBox box = CropBox(
    left: left < 0 ? 0 : left,
    top: tops[skip],
    right: right > 1 ? 1 : right,
    bottom: bottoms[far],
  );
  return box.isValid ? box : CropBox.full;
}
