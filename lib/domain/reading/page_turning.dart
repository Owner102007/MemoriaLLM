/// Скорость показа страницы — чистая математика (F-READ-02).
///
/// Читатель нажал «вперёд» и ждёт текст, а не белый лист. Для этого
/// страница показывается раньше, чем досчитана её рамка, рамки соседних
/// листов считаются заранее, а просмотрщик держит наготове грубые
/// картинки соседних страниц. Здесь собрано всё, что в этом можно
/// посчитать без движка PDF и без виджетов: какие рамки готовить, чью
/// рамку взять взаймы, какой запас просить у просмотрщика и в каком
/// масштабе рисовать грубую картинку.
///
/// Алгоритм — ALG-PDF-03, дефект, который он закрывает, — BUG-23.
library;

import 'dart:math' as math;

import 'fragments.dart';
import 'reading.dart';
import 'spread.dart';

/// Сколько переход ждёт рамку страницы, прежде чем показать её без рамки.
///
/// BUG-23: прежде переход ждал рамку всегда, а на скане это рендер и
/// попиксельный разбор до показа. Теперь рамка из кэша берётся сразу, а
/// непосчитанную ждут не дольше этого срока — около четырёх кадров.
/// Страница с текстом почти всегда успевает и встаёт сразу по своей
/// рамке; скан показывается по чужой и подрезается следом.
const Duration kFrameWait = Duration(milliseconds: 60);

/// Сколько открытие книги ждёт рамку первой страницы.
///
/// Дольше, чем переход: читатель всё равно смотрит на индикатор, и
/// четверть секунды здесь дешевле, чем страница, которая встала целиком
/// и тут же подрезалась на глазах.
const Duration kOpenFrameWait = Duration(milliseconds: 250);

/// На сколько листов вперёд по ходу чтения считать рамки заранее.
const int kFramesAhead = 2;

/// На сколько листов назад считать рамки заранее.
const int kFramesBehind = 1;

/// Страницы, рамки которых стоит посчитать заранее, в порядке надобности.
///
/// Сначала листы по ходу чтения — туда читатель уйдёт следующим
/// нажатием, — потом лист с другой стороны: назад возвращаются реже, но
/// возвращаются. В развороте лист — две страницы, и готовятся обе.
List<int> framesAhead({
  required int page,
  required int pageCount,
  required bool spread,
  required bool forward,
  int ahead = kFramesAhead,
  int behind = kFramesBehind,
}) {
  final List<int> pages = <int>[];
  void walk({required bool onward, required int sheets}) {
    int at = page;
    for (int i = 0; i < sheets; i++) {
      final int? next = onward
          ? nextSheetPage(page: at, pageCount: pageCount, spread: spread)
          : previousSheetPage(page: at, pageCount: pageCount, spread: spread);
      if (next == null) {
        return;
      }
      pages.addAll(spread ? spreadPages(next, pageCount) : <int>[next]);
      at = next;
    }
  }

  walk(onward: forward, sheets: ahead);
  walk(onward: !forward, sheets: behind);
  return pages;
}

/// Как далеко от страницы искать посчитанную рамку, в страницах.
const int kBorrowReach = 6;

/// Рамка взаймы для страницы, своя рамка которой ещё не посчитана.
///
/// Берётся рамка ближайшей посчитанной страницы **той же чётности**: в
/// книге из переплёта поля чётных и нечётных страниц зеркальны, и рамка
/// через одну страницу подходит точнее, чем рамка соседней. Нет такой —
/// годится ближайшая любая. Дальше [reach] страниц не ищем: рамка из
/// другой главы хуже страницы целиком.
///
/// `null` — занять не у кого, и страница показывается целиком: лишнее
/// поле лучше срезанного текста.
CropBox? borrowedContent({
  required int page,
  required int pageCount,
  required CropBox? Function(int page) known,
  int reach = kBorrowReach,
}) {
  CropBox? other;
  for (int distance = 1; distance <= reach; distance++) {
    for (final int candidate in <int>[page - distance, page + distance]) {
      if (candidate < 1 || candidate > pageCount) {
        continue;
      }
      final CropBox? box = known(candidate);
      if (box == null || !box.isValid) {
        continue;
      }
      if (distance.isEven) {
        return box;
      }
      other ??= box;
    }
  }
  return other;
}

/// На какую долю листа запас заходит в самый дальний из соседних листов.
///
/// Запас просмотрщика откладывается от краёв видимой области, а она
/// стоит по центру листа лишь примерно: поля книги несимметричны. Пятой
/// части листа хватает, чтобы дальняя страница соседнего разворота попала
/// в запас при любом перекосе полей и чтобы лист за ним туда не попал.
const double kNeighbourReach = 0.2;

/// Запас кэша просмотрщика по горизонтали, в ширинах видимой области.
///
/// Страницы книги лежат в один ряд, и просмотрщик держит грубые картинки
/// тех, что попадают в видимую область, расширенную на этот запас. Нам
/// нужно ровно [sheets] листов с каждой стороны: меньше — следующая
/// страница не готова к переходу, больше — память уходит на страницы, до
/// которых читатель дойдёт нескоро.
///
/// [sheetWidth] и [visibleWidth] — в одних единицах (точках PDF). Ноль
/// означает, что запас не нужен: соседние листы и так видны (широкое
/// окно ПК) или запас выключен.
double neighbourCacheExtent({
  required double sheetWidth,
  required double visibleWidth,
  required int sheets,
}) {
  if (sheets <= 0 || sheetWidth <= 0 || visibleWidth <= 0) {
    return 0;
  }
  final double reach =
      sheetWidth * (sheets + kNeighbourReach) - visibleWidth / 2;
  return reach <= 0 ? 0 : reach / visibleWidth;
}

/// Сколько пикселей отдаётся грубой картинке одной страницы.
///
/// Три мегапикселя — двенадцать мегабайт на страницу. Грубая картинка
/// живёт на экране доли секунды, пока рисуется резкая, и платить за неё
/// десятками мегабайт незачем. Тем более что просмотрщик pdfrx 2.6.1 не
/// вытесняет картинки страниц, оставшихся **правее** запаса (BUG-35):
/// при листании назад и после прыжков они копятся до закрытия книги, и
/// чем мельче картинка, тем меньше копится.
///
/// Упирается в предел только крупный показ — полоса страницы на телефоне
/// в альбомном положении, широкое окно ПК: там грубая картинка заметно
/// мягче резкой. Страница целиком на телефоне и на обычном окне ПК в
/// предел не упирается.
const int kPreviewPixels = 3000000;

/// На сколько придерживается запас соседних страниц после смены листа.
///
/// Просмотрщик рисует картинки в том порядке, в каком их попросили, а
/// грубую картинку страницы, попавшей в запас впервые, просит сразу —
/// раньше резкой картинки страницы на экране. Поэтому на время смены
/// листа запас убирается: сначала в очередь встаёт то, что читатель
/// видит, и только потом соседи. Нескольких кадров на это хватает.
const Duration kReserveHold = Duration(milliseconds: 50);

/// Наибольший масштаб грубой картинки страницы, в пикселях на точку PDF.
double previewScaleCap({
  required double pageWidth,
  required double pageHeight,
  int maxPixels = kPreviewPixels,
}) {
  if (pageWidth <= 0 || pageHeight <= 0 || maxPixels <= 0) {
    return 0;
  }
  return math.sqrt(maxPixels / (pageWidth * pageHeight));
}

/// Какую долю нужного экрану масштаба получает грубая картинка.
///
/// Чуть меньше единицы, и это осознанно. Грубая картинка крупнее нужного
/// стала бы окончательной: просмотрщик резкую уже не рисует, а
/// уменьшенная картинка мягче нарисованной точно в пиксель — чтение
/// стало бы хуже, чем было. Картинка чуть мельче нужного показывается
/// сразу, а резкая, пиксель в пиксель, дорисовывается следом всегда.
const double kPreviewShare = 0.9;

/// До какой доли нужного масштаба грубая картинка ещё годится.
///
/// Рамки страниц одной книги чуть разные, и нужный масштаб от страницы к
/// странице гуляет на проценты. Перерисовывать ради этого грубые
/// картинки всех соседей на каждом нажатии незачем.
const double kPreviewKeep = 0.7;

/// Масштаб грубых картинок, который стоит держать дальше.
///
/// [held] — масштаб, в котором картинки уже нарисованы (ноль — ещё ни в
/// каком), [wanted] — масштаб, которого просит экран сейчас. Пока
/// удерживаемый масштаб не крупнее нужного и не намного мельче, он
/// остаётся: перерисовка всех соседей стоит дороже нескольких процентов
/// резкости, которые всё равно доберёт резкая картинка.
double heldPreviewScale({required double held, required double wanted}) {
  if (!wanted.isFinite || wanted <= 0) {
    return held;
  }
  if (held > 0 && held <= wanted && held >= wanted * kPreviewKeep) {
    return held;
  }
  return wanted * kPreviewShare;
}

/// Настройки скорости показа страницы.
///
/// Обе — настройки устройства, а не книги: сколько памяти не жалко и
/// раздражает ли ступенька «грубо → резко», зависит от телефона и глаз,
/// а не от того, что читают.
class PageTurnSettings {
  /// Создаёт настройки.
  const PageTurnSettings({required this.preview, required this.reserve});

  /// Настройки из сохранённых строк; чего нет — берётся по умолчанию.
  ///
  /// [desktop] выбирает запас по умолчанию: на ПК памяти больше, а окно
  /// шире, и готовить там стоит на страницу дальше.
  factory PageTurnSettings.parse({
    required String? preview,
    required String? reserve,
    required bool desktop,
  }) {
    final int? parsed = reserve == null ? null : int.tryParse(reserve);
    final int pages = parsed ?? defaultReserve(desktop: desktop);
    return PageTurnSettings(
      preview: preview != 'false',
      reserve: pages < 0 ? 0 : (pages > maxReserve ? maxReserve : pages),
    );
  }

  /// Наибольший запас соседних страниц.
  static const int maxReserve = 2;

  /// Запас соседних страниц по умолчанию.
  static int defaultReserve({required bool desktop}) => desktop ? 2 : 1;

  /// Показывать страницу сразу — грубо, а через миг резко.
  ///
  /// Выключено — страница появляется только резкой, как до F-READ-02:
  /// без ступеньки, но и без запаса соседних страниц.
  final bool preview;

  /// Сколько соседних листов держать наготове с каждой стороны.
  final int reserve;

  /// Запас, который на самом деле уходит просмотрщику.
  ///
  /// Наготове держатся грубые картинки; без них держать нечего.
  int get effectiveReserve => preview ? reserve : 0;

  @override
  bool operator ==(Object other) {
    return other is PageTurnSettings &&
        other.preview == preview &&
        other.reserve == reserve;
  }

  @override
  int get hashCode => Object.hash(preview, reserve);

  @override
  String toString() => 'PageTurnSettings(сразу: $preview, запас: $reserve)';
}
