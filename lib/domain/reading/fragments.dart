/// Режимы отображения: деление страницы на фрагменты — чистая математика.
///
/// Смысл режима половины — кегль вырастает вдвое **без изменения вёрстки**.
/// Этого не может ни бумага, ни переформатируемый текст: там увеличение
/// шрифта переливает абзацы заново и ломает всё, что автор выстроил на
/// странице. Здесь же меняется только то, какая часть страницы занимает
/// экран.
///
/// Правило деления:
///
/// | Режим | Одна колонка | Две колонки |
/// |---|---|---|
/// | `full` | вся рамка | вся рамка |
/// | `half` | две полосы сверху вниз | две колонки |
/// | `third` | три полосы | две колонки, каждая пополам |
/// | `spread` | вся рамка (разворот собирается раскладкой) | вся рамка |
/// | `spreadHalf` | две полосы сверху вниз | две полосы сверху вниз |
///
/// На двухколоночной странице колонка **и есть** половина, поэтому режим
/// трети даёт там половину колонки — следующий шаг увеличения. Делить
/// колонку на три было бы уже не чтение, а разглядывание.
///
/// **Половина без поворота экрана ничего не даёт.** Полоса вдвое ниже
/// страницы, но той же ширины, а в вертикальный экран телефона страница
/// вписывается именно по ширине — увеличение выходит ровно единица.
/// Кегль растёт только тогда, когда широкую и низкую полосу показывают на
/// широком и низком экране, поэтому режимы деления неразрывно связаны с
/// [preferredOrientationFor].
library;

import 'columns.dart';
import 'reading.dart';

/// Насколько соседние полосы налезают друг на друга, в долях высоты полосы.
///
/// Ноль: половины делятся **чёткой линией**. Нахлёст задумывался как
/// забота о строке на границе, но на деле повторял её на обоих экранах,
/// и читатель спотыкался — глаз видит знакомый текст и теряет место.
/// Разрезанная строка — цена меньшая, чем сбитое чтение.
const double kFragmentOverlap = 0;

/// Фрагменты страницы в порядке чтения.
///
/// Всегда возвращает хотя бы один прямоугольник: пустой список означал бы
/// пустой экран.
List<CropBox> fragmentsFor({
  required CropBox content,
  required PageDisplayMode mode,
  List<ColumnBand> columns = const <ColumnBand>[],
  double overlap = kFragmentOverlap,
}) {
  if (!content.isValid) {
    return const <CropBox>[CropBox.full];
  }
  final bool twoColumns = columns.length >= 2;
  switch (mode) {
    case PageDisplayMode.full:
    case PageDisplayMode.spread:
      return <CropBox>[content];
    case PageDisplayMode.spreadHalf:
      // Разворот делится только по горизонтали: колонки внутри страниц
      // тут ни при чём, полоса идёт через обе страницы сразу.
      return _rows(content, 2, overlap);
    case PageDisplayMode.half:
      if (twoColumns) {
        return <CropBox>[
          for (final ColumnBand band in columns)
            CropBox(
              left: band.left,
              top: content.top,
              right: band.right,
              bottom: content.bottom,
            ),
        ];
      }
      return _rows(content, 2, overlap);
    case PageDisplayMode.third:
      if (twoColumns) {
        return <CropBox>[
          for (final ColumnBand band in columns)
            ..._rows(
              CropBox(
                left: band.left,
                top: content.top,
                right: band.right,
                bottom: content.bottom,
              ),
              2,
              overlap,
            ),
        ];
      }
      return _rows(content, 3, overlap);
  }
}

/// Сколько фрагментов даёт режим при таком числе колонок.
int fragmentCountFor({
  required PageDisplayMode mode,
  required int columnCount,
}) {
  final bool twoColumns = columnCount >= 2;
  switch (mode) {
    case PageDisplayMode.full:
    case PageDisplayMode.spread:
      return 1;
    case PageDisplayMode.half:
    case PageDisplayMode.spreadHalf:
      return 2;
    case PageDisplayMode.third:
      return twoColumns ? 4 : 3;
  }
}

/// Показывает ли режим сразу две страницы.
bool isSpreadMode(PageDisplayMode mode) =>
    mode == PageDisplayMode.spread || mode == PageDisplayMode.spreadHalf;

/// В каком положении экрана этот режим имеет смысл.
///
/// Деление страницы на полосы увеличивает текст только на широком и
/// низком экране: см. пояснение в заголовке файла. Поэтому выбор режима
/// сам поворачивает чтение, а не оставляет читателя гадать, почему
/// «половина» выглядит как целая страница.
ScreenOrientation preferredOrientationFor(PageDisplayMode mode) {
  switch (mode) {
    case PageDisplayMode.full:
      return ScreenOrientation.portrait;
    case PageDisplayMode.half:
    case PageDisplayMode.third:
    case PageDisplayMode.spread:
    case PageDisplayMode.spreadHalf:
      return ScreenOrientation.landscape;
  }
}

/// Во сколько раз фрагмент крупнее на экране, чем страница целиком.
///
/// Обе величины — доли сторон: фрагмент и экран описываются отношением
/// ширины к высоте, а масштаб считается вписыванием прямоугольника в
/// прямоугольник. Функция существует ради одного вопроса, ради которого
/// затевались режимы: **действительно ли текст стал крупнее**. Ответ
/// «нет» — это ошибка, и её должен ловить тест, а не глаз читателя.
double fragmentScale({
  required double fragmentWidth,
  required double fragmentHeight,
  required double screenWidth,
  required double screenHeight,
}) {
  if (fragmentWidth <= 0 ||
      fragmentHeight <= 0 ||
      screenWidth <= 0 ||
      screenHeight <= 0) {
    return 0;
  }
  final double byWidth = screenWidth / fragmentWidth;
  final double byHeight = screenHeight / fragmentHeight;
  return byWidth < byHeight ? byWidth : byHeight;
}

/// Куда попадает фрагмент [index] при смене числа фрагментов на странице.
///
/// Читатель, сменивший режим на середине страницы, должен остаться
/// примерно там же, где был. Считается по середине старого фрагмента:
/// первый из двух — это верхняя четверть страницы, и при переходе на три
/// полосы он обязан попасть в первую, а не во вторую.
int remapFragment({
  required int index,
  required int oldCount,
  required int newCount,
}) {
  if (newCount <= 1) {
    return 0;
  }
  if (oldCount <= 1) {
    return 0;
  }
  final int safeIndex = index < 0
      ? 0
      : (index > oldCount - 1 ? oldCount - 1 : index);
  final double middle = (safeIndex + 0.5) / oldCount;
  final int mapped = (middle * newCount).floor();
  if (mapped < 0) {
    return 0;
  }
  if (mapped > newCount - 1) {
    return newCount - 1;
  }
  return mapped;
}

/// Приводит номер фрагмента к допустимому диапазону.
int clampFragment(int index, int count) {
  if (count <= 1 || index < 0) {
    return 0;
  }
  return index > count - 1 ? count - 1 : index;
}

/// Страницы разворота для страницы [page].
///
/// Первая страница стоит одна — она обложка или титул, и клеить её к
/// второй значило бы всю книгу листать не теми парами. Дальше идут пары
/// (2, 3), (4, 5) и так далее, как в переплёте.
List<int> spreadPages(int page, int pageCount) {
  if (pageCount <= 0) {
    return const <int>[1];
  }
  final int safe = page < 1 ? 1 : (page > pageCount ? pageCount : page);
  if (safe == 1) {
    return const <int>[1];
  }
  final int left = safe.isEven ? safe : safe - 1;
  if (left + 1 > pageCount) {
    return <int>[left];
  }
  return <int>[left, left + 1];
}

List<CropBox> _rows(CropBox content, int count, double overlap) {
  final double step = content.height / count;
  final double margin = step * overlap;
  return <CropBox>[
    for (int i = 0; i < count; i++)
      CropBox(
        left: content.left,
        top: _clamp01(content.top + i * step - (i == 0 ? 0 : margin)),
        right: content.right,
        bottom: _clamp01(
          content.top + (i + 1) * step + (i == count - 1 ? 0 : margin),
        ),
      ),
  ];
}

double _clamp01(double value) {
  if (!value.isFinite || value < 0) {
    return 0;
  }
  return value > 1 ? 1 : value;
}
