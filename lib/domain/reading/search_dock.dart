/// Место панели поиска рядом с найденным (F-TEXT-11, ALG-UI-31).
///
/// Поиск — не окно, которое закрывает страницу, а её спутник: читатель
/// выбирает результат, страница переходит к нему, а список остаётся на
/// экране. Значит, панель обязана стоять там, где она не закрывает то,
/// ради чего её открыли, — найденное.
///
/// На широком окне места хватает обоим: панель стоит справа, а лист
/// раскладывается в оставшейся ширине. На узком экране панель лежит
/// поверх страницы полупрозрачной полосой и уступает найденному место:
/// переезжает к противоположному краю, а если оно не помещается мимо
/// неё нигде — сжимается до одной строки.
///
/// Здесь — только счёт. Виджетов файл не знает и проверяется числами.
library;

import 'dart:ui' show Rect, Size;

/// С какой ширины экрана панель встаёт рядом со страницей.
///
/// ПК и планшет в альбоме. Принято владельцем 03.10.2026 (решение Ж1) до
/// проверки на устройстве.
const double kSearchWideWindow = 900;

/// Ширина панели рядом со страницей.
const double kSearchPanelWidth = 380;

/// Какую долю экрана панель занимает на узком экране, не больше.
///
/// Принято владельцем 03.10.2026 (решение Ж1) до проверки на устройстве.
const double kSearchStripShare = 0.4;

/// Высота панели, сжатой до одной строки `‹ 3 из 17 ›`.
const double kSearchCompactExtent = 48;

/// На сколько найденное должно отстоять от панели, чтобы не считаться
/// закрытым: подсветка, прижатая к самому краю панели, читается плохо.
const double kSearchFoundMargin = 6;

/// Непрозрачность панели поверх страницы.
///
/// Сквозь панель видно, что под ней, но строки списка обязаны читаться
/// на любой странице — белой, сепийной, тёмной, под каждым
/// светофильтром. При этом значении основной текст любой темы держит
/// контраст не ниже 4,5:1 над самой неудобной подложкой; вторичный и
/// акцентный — нет, поэтому в полупрозрачной панели ими не пишут
/// (проверяется в `search_dock_test`).
const double kSearchPanelOpacity = 0.78;

/// У какого края стоит панель.
enum SearchDockSide {
  /// У правого края.
  right,

  /// У левого края.
  left,

  /// У нижнего края.
  bottom,

  /// У верхнего края.
  top,
}

/// Где и какой стоит панель поиска.
class SearchDock {
  /// Создаёт место панели.
  const SearchDock({
    required this.side,
    required this.extent,
    this.beside = false,
    this.compact = false,
  });

  /// У какого края.
  final SearchDockSide side;

  /// Размер поперёк края: ширина у боковых краёв, высота у верхнего и
  /// нижнего.
  final double extent;

  /// Стоит ли панель рядом со страницей (`true`) или поверх неё.
  ///
  /// Рядом — лист раскладывается в оставшейся ширине, и найденное под
  /// панелью оказаться не может. Поверх — лист не перекладывается.
  final bool beside;

  /// Сжата ли панель до одной строки: найденное не поместилось мимо неё
  /// ни у одного края.
  final bool compact;

  /// Стоит ли панель столбцом у бокового края.
  bool get vertical =>
      side == SearchDockSide.left || side == SearchDockSide.right;

  /// Сколько ширины панель отнимает у листа.
  double get taken => beside ? extent : 0;

  /// Прямоугольник панели в области [area].
  Rect rectIn(Size area) {
    switch (side) {
      case SearchDockSide.right:
        return Rect.fromLTWH(area.width - extent, 0, extent, area.height);
      case SearchDockSide.left:
        return Rect.fromLTWH(0, 0, extent, area.height);
      case SearchDockSide.bottom:
        return Rect.fromLTWH(0, area.height - extent, area.width, extent);
      case SearchDockSide.top:
        return Rect.fromLTWH(0, 0, area.width, extent);
    }
  }

  @override
  bool operator ==(Object other) {
    return other is SearchDock &&
        other.side == side &&
        other.extent == extent &&
        other.beside == beside &&
        other.compact == compact;
  }

  @override
  int get hashCode => Object.hash(side, extent, beside, compact);

  @override
  String toString() {
    final String how = beside ? 'рядом' : 'поверх';
    final String size = compact ? 'одной строкой' : '$extent';
    return 'SearchDock($side, $how, $size)';
  }
}

/// Широкое ли окно: панель встаёт рядом со страницей.
bool isSearchWide(Size screen) => screen.width >= kSearchWideWindow;

/// Выбирает место панели поиска.
///
/// [screen] — экран или окно целиком: по нему решается, широкое ли окно
/// и как повёрнут телефон. [area] — место, в котором стоят страница и
/// панель: оно бывает меньше экрана. [found] — прямоугольник текущего
/// совпадения в координатах [area]; `null` — его нет на экране или у
/// страницы нет координат текста. [current] — где панель стоит сейчас.
///
/// Правила — ALG-UI-31:
///
/// 1. Широкое окно — панель у правого края, рядом со страницей.
/// 2. Узкий экран в портрете — полоса во всю ширину, из коробки снизу.
/// 3. Узкий экран в альбоме — полоса во всю высоту, из коробки справа.
/// 4. Панель закрывает найденное — переезжает к противоположному краю.
///    Не закрывает — стоит где стояла: при шаге по совпадениям она не
///    скачет без нужды.
/// 5. Найденное не помещается мимо панели ни у одного края — панель
///    сжимается до одной строки.
SearchDock placeSearchPanel({
  required Size screen,
  required Size area,
  Rect? found,
  SearchDockSide? current,
}) {
  if (isSearchWide(screen)) {
    return const SearchDock(
      side: SearchDockSide.right,
      extent: kSearchPanelWidth,
      beside: true,
    );
  }
  final bool portrait = screen.height >= screen.width;
  final SearchDockSide first = portrait
      ? SearchDockSide.bottom
      : SearchDockSide.right;
  final SearchDockSide second = portrait
      ? SearchDockSide.top
      : SearchDockSide.left;
  final double extent =
      (portrait ? area.height : area.width) * kSearchStripShare;
  final SearchDockSide preferred = current == second ? second : first;
  final SearchDock here = SearchDock(side: preferred, extent: extent);
  if (found == null || found.isEmpty) {
    return here;
  }
  final Rect kept = found.inflate(kSearchFoundMargin);
  if (!kept.overlaps(here.rectIn(area))) {
    return here;
  }
  final SearchDock there = SearchDock(
    side: preferred == first ? second : first,
    extent: extent,
  );
  if (!kept.overlaps(there.rectIn(area))) {
    return there;
  }
  // Найденное тянется через весь экран: панель остаётся одной строкой —
  // у нижнего края, а если оно и там, то у верхнего.
  const SearchDock low = SearchDock(
    side: SearchDockSide.bottom,
    extent: kSearchCompactExtent,
    compact: true,
  );
  const SearchDock high = SearchDock(
    side: SearchDockSide.top,
    extent: kSearchCompactExtent,
    compact: true,
  );
  if (portrait && preferred == SearchDockSide.top) {
    return kept.overlaps(high.rectIn(area)) && !kept.overlaps(low.rectIn(area))
        ? low
        : high;
  }
  return kept.overlaps(low.rectIn(area)) && !kept.overlaps(high.rectIn(area))
      ? high
      : low;
}
