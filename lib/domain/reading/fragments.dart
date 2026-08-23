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
/// **Деление и форма области показа — одно решение, а не два.** Полоса
/// вдвое ниже страницы, но той же ширины, а в вертикальный экран телефона
/// страница вписывается именно по ширине: увеличение выходит ровно
/// единица. Колонка, наоборот, узкая и высокая, и на широком экране она
/// вписывается по высоте — текст становится **мельче**, чем на целой
/// странице. Поэтому положение экрана не назначается по режиму, а
/// выбирается счётом: см. [chooseFragmentLayout].
library;

import 'columns.dart';
import 'reading.dart';

/// Насколько соседние полосы налезают там, где просвет **нашёлся**.
///
/// Ноль: половины делятся чёткой линией. Нахлёст задумывался как забота о
/// строке на границе, но на деле повторял её на обоих экранах, и читатель
/// спотыкался — глаз видит знакомый текст и теряет место. Раз граница
/// проходит между строк, повторять нечего.
const double kFragmentOverlap = 0;

/// Насколько полосы налезают там, где просвет **не нашёлся**.
///
/// В долях высоты полосы; примерно строка текста. Просвета нет там, где
/// строк не видно вовсе (испорченный текстовый слой, страница-картинка,
/// набор без междустрочья) — и тогда граница неизбежно рассекает строку.
/// Из двух зол выбрано меньшее: строка **повторяется** на обоих экранах,
/// а не исчезает между ними. Потерянную строку читатель не восстановит
/// никак; повторённую — просто пропустит глазом.
const double kBlindOverlap = 0.03;

/// Насколько далеко граница может уехать к просвету между строками.
///
/// В долях высоты полосы. Слишком щедрый допуск сделал бы полосы разными
/// по высоте настолько, что кегль скакал бы между экранами; слишком
/// скупой не спас бы строку, которая стоит чуть в стороне от середины.
const double kBreakSearch = 0.18;

/// Как режим режет содержимое страницы.
///
/// Направление деления определяется вёрсткой, а не вкусом: двухколоночную
/// страницу нельзя резать поперёк — полоса накроет верх **обеих** колонок
/// сразу, и порядок чтения станет «левый верх, левый низ, правый верх,
/// правый низ», то есть читателю придётся возвращаться назад через экран.
/// Поэтому кандидат на деление у каждой вёрстки один, а выбор, который
/// действительно есть, — это форма области показа (см.
/// [chooseFragmentLayout]).
enum FragmentSplit {
  /// Не режется вовсе.
  whole,

  /// Полосами сверху вниз.
  rows,

  /// По колонкам.
  columns,

  /// По колонкам, каждая — полосами.
  columnRows,
}

/// Каким делением обслуживается режим на такой вёрстке.
FragmentSplit splitFor({
  required PageDisplayMode mode,
  required bool twoColumns,
}) {
  switch (mode) {
    case PageDisplayMode.full:
    case PageDisplayMode.spread:
      return FragmentSplit.whole;
    case PageDisplayMode.spreadHalf:
      // Разворот делится только по горизонтали: колонки внутри страниц
      // тут ни при чём, строка идёт через обе страницы сразу.
      return FragmentSplit.rows;
    case PageDisplayMode.half:
      return twoColumns ? FragmentSplit.columns : FragmentSplit.rows;
    case PageDisplayMode.third:
      return twoColumns ? FragmentSplit.columnRows : FragmentSplit.rows;
  }
}

/// Фрагменты страницы в порядке чтения.
///
/// Всегда возвращает хотя бы один прямоугольник: пустой список означал бы
/// пустой экран.
List<CropBox> fragmentsFor({
  required CropBox content,
  required PageDisplayMode mode,
  List<ColumnBand> columns = const <ColumnBand>[],
  List<double> breaks = const <double>[],
  double blindOverlap = kBlindOverlap,
}) {
  if (!content.isValid) {
    return const <CropBox>[CropBox.full];
  }
  final bool twoColumns = columns.length >= 2;
  final int rows = mode == PageDisplayMode.third && !twoColumns ? 3 : 2;
  switch (splitFor(mode: mode, twoColumns: twoColumns)) {
    case FragmentSplit.whole:
      return <CropBox>[content];
    case FragmentSplit.rows:
      return _rows(content, rows, blindOverlap, breaks);
    case FragmentSplit.columns:
      return <CropBox>[
        for (final ColumnBand band in columns) _column(band, content),
      ];
    case FragmentSplit.columnRows:
      return <CropBox>[
        for (final ColumnBand band in columns)
          ..._rows(_column(band, content), 2, blindOverlap, breaks),
      ];
  }
}

CropBox _column(ColumnBand band, CropBox content) {
  return CropBox(
    left: band.left,
    top: content.top,
    right: band.right,
    bottom: content.bottom,
  );
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

/// Ниже какого выигрыша режим деления не имеет смысла включать.
///
/// Ровно единица не годится порогом: доли процента выигрыша читатель не
/// увидит, а решение «поворачивать экран или нет» будет скакать от
/// страницы к странице из-за двоичной арифметики.
const double kMinFragmentGain = 1.02;

/// Выбранная раскладка: чем режем и в какой форме области показываем.
///
/// Главное здесь — [gain]: во сколько раз текст крупнее, чем при показе
/// страницы целиком. Ради этого числа затевались режимы, и оно же служит
/// приговором: выигрыша нет — режим не включается.
class FragmentLayout {
  /// Создаёт раскладку.
  const FragmentLayout({
    required this.mode,
    required this.split,
    required this.area,
    required this.scale,
    required this.wholeScale,
  });

  /// Режим отображения.
  final PageDisplayMode mode;

  /// Чем режется содержимое.
  final FragmentSplit split;

  /// Форма области показа, при которой режим выгоднее всего.
  final DisplayArea area;

  /// Масштаб **худшего** фрагмента страницы.
  ///
  /// Именно худшего: показывать разные фрагменты одной страницы разным
  /// кеглем нельзя, а обещать выигрыш по лучшему из них — обманывать.
  final double scale;

  /// Масштаб страницы целиком в самой выгодной для неё форме области.
  final double wholeScale;

  /// Посчитана ли раскладка на настоящих числах.
  bool get isKnown => area.isKnown && scale > 0 && wholeScale > 0;

  /// В каком положении экрана эту раскладку показывать.
  ScreenOrientation get orientation => area.orientation;

  /// Во сколько раз текст крупнее, чем при показе страницы целиком.
  double get gain => isKnown ? scale / wholeScale : 0;

  /// Затевается ли режим ради увеличения кегля.
  ///
  /// Развороты — нет: они показывают **больше** книги сразу, и мерить их
  /// выигрышем в кегле бессмысленно. Гасить их за «отрицательный
  /// выигрыш» было бы отменой самой возможности.
  bool get magnifies =>
      mode == PageDisplayMode.half || mode == PageDisplayMode.third;

  /// Стоит ли включать этот режим.
  ///
  /// Пока область показа не измерена, ответ «да»: запрещать по незнанию
  /// хуже, чем разрешить и пересчитать через кадр.
  bool get isWorthwhile => !isKnown || !magnifies || gain >= kMinFragmentGain;

  @override
  String toString() =>
      'FragmentLayout($mode, $split, $area, выигрыш '
      '${gain.toStringAsFixed(2)})';
}

/// Выбирает деление и форму области показа как **одно** решение.
///
/// Прежде решений было два, и принимались они порознь: `fragmentsFor`
/// отдавала на двухколоночной странице колонку (узкую и высокую), а
/// положение экрана назначалось по режиму и для половины всегда просило
/// альбом. Вместе выходило худшее из двух — узкий высокий фрагмент
/// вписывался в широкий низкий экран по высоте, и текст становился
/// **мельче**, чем на целой странице. Читалка не имеет права уменьшить
/// текст в ответ на просьбу его увеличить.
///
/// Теперь для режима считается его деление (одно — второе сломало бы
/// порядок чтения, см. [FragmentSplit]), а форма области показа
/// перебирается: на телефоне это два положения экрана, на ПК — одна
/// фактическая форма окна, потому что ориентации там нет вовсе.
/// Выигрывает форма с наибольшим масштабом **худшего** фрагмента.
///
/// [sheetWidth] и [sheetHeight] — размеры листа в любых одинаковых
/// единицах: одна страница или две страницы разворота рядом.
FragmentLayout chooseFragmentLayout({
  required PageDisplayMode mode,
  required CropBox content,
  required double sheetWidth,
  required double sheetHeight,
  required DisplayArea area,
  List<ColumnBand> columns = const <ColumnBand>[],
  List<double> breaks = const <double>[],
  bool canTurn = true,
}) {
  final FragmentSplit split = splitFor(
    mode: mode,
    twoColumns: columns.length >= 2,
  );
  if (!area.isKnown ||
      !content.isValid ||
      sheetWidth <= 0 ||
      sheetHeight <= 0 ||
      !sheetWidth.isFinite ||
      !sheetHeight.isFinite) {
    return FragmentLayout(
      mode: mode,
      split: split,
      area: area,
      scale: 0,
      wholeScale: 0,
    );
  }

  final List<CropBox> parts = fragmentsFor(
    content: content,
    mode: mode,
    columns: columns,
    breaks: breaks,
  );
  final List<DisplayArea> candidates = canTurn
      ? <DisplayArea>[
          area.oriented(ScreenOrientation.portrait),
          area.oriented(ScreenOrientation.landscape),
        ]
      : <DisplayArea>[area];

  DisplayArea best = candidates.first;
  double bestScale = -1;
  double wholeScale = 0;
  for (final DisplayArea candidate in candidates) {
    final double whole = fragmentScale(
      fragmentWidth: sheetWidth * content.width,
      fragmentHeight: sheetHeight * content.height,
      screenWidth: candidate.width,
      screenHeight: candidate.height,
    );
    if (whole > wholeScale) {
      wholeScale = whole;
    }
    double worst = double.infinity;
    for (final CropBox part in parts) {
      final double scale = fragmentScale(
        fragmentWidth: sheetWidth * part.width,
        fragmentHeight: sheetHeight * part.height,
        screenWidth: candidate.width,
        screenHeight: candidate.height,
      );
      if (scale < worst) {
        worst = scale;
      }
    }
    if (worst.isFinite && worst > bestScale) {
      bestScale = worst;
      best = candidate;
    }
  }

  return FragmentLayout(
    mode: mode,
    split: split,
    area: best,
    scale: bestScale < 0 ? 0 : bestScale,
    wholeScale: wholeScale,
  );
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

/// Границы полос, притянутые к просветам между строками.
///
/// Геометрическая середина почти всегда попадает на строку и режет её
/// пополам: верхняя половина строки остаётся на одном экране, нижняя на
/// другом, и читать нельзя ни там, ни там. Поэтому граница ищет
/// ближайший просвет и переезжает в него, но не дальше [kBreakSearch]
/// от исходного места: иначе полосы разъедутся по высоте так, что кегль
/// начнёт скакать от экрана к экрану.
List<_Edge> _edges(CropBox content, int count, List<double> breaks) {
  final double step = content.height / count;
  final double reach = step * kBreakSearch;
  final List<_Edge> edges = <_Edge>[];
  for (int i = 1; i < count; i++) {
    final double ideal = content.top + step * i;
    double best = ideal;
    double bestDistance = reach;
    bool snapped = false;
    for (final double candidate in breaks) {
      if (candidate <= content.top || candidate >= content.bottom) {
        continue;
      }
      final double distance = (candidate - ideal).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
        snapped = true;
      }
    }
    edges.add(_Edge(at: best, snapped: snapped));
  }
  return edges;
}

/// Граница между полосами и то, попала ли она в просвет между строками.
class _Edge {
  const _Edge({required this.at, required this.snapped});

  final double at;

  /// Нашёлся ли просвет. Если нет — граница режет строку, и полосы вокруг
  /// неё расходятся на [kBlindOverlap], чтобы строка не пропала.
  final bool snapped;
}

List<CropBox> _rows(
  CropBox content,
  int count,
  double blindOverlap,
  List<double> breaks,
) {
  final List<_Edge> edges = _edges(content, count, breaks);
  final double step = content.height / count;
  final List<double> margins = <double>[
    for (final _Edge edge in edges)
      edge.snapped ? step * kFragmentOverlap : step * blindOverlap,
  ];
  return <CropBox>[
    for (int i = 0; i < count; i++)
      CropBox(
        left: content.left,
        top: _clamp01(i == 0 ? content.top : edges[i - 1].at - margins[i - 1]),
        right: content.right,
        bottom: _clamp01(
          i == count - 1 ? content.bottom : edges[i].at + margins[i],
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
