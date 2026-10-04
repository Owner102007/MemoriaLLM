/// Место панели поиска рядом со страницей (F-TEXT-11, F-TEXT-12,
/// ALG-UI-31).
///
/// Поиск — не окно, которое закрывает страницу, а её спутник: читатель
/// выбирает результат, страница переходит к нему, а список остаётся на
/// экране.
///
/// На широком окне места хватает обоим: панель стоит справа, а лист
/// раскладывается в оставшейся ширине. На узком экране панель лежит
/// поверх страницы полупрозрачной полосой **всегда у нижнего края**
/// (F-TEXT-12, замечание владельца 04.10.2026): и пока запрос набирают,
/// и после выбора результата, в портрете и в альбоме. К другому краю
/// она не переезжает, куда бы ни пришлось найденное: под полосой оно
/// видно сквозь неё.
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

/// Высота строки счёта `‹ 3 из 17 ›`.
const double kSearchCounterExtent = 48;

/// Сколько места полоса занимает, пока в ней набирают запрос, не меньше.
///
/// Поле, строка счёта и одна строка списка: с поднятой клавиатурой
/// 40 % оставшегося экрана на них не хватает, а полоса, в которой не
/// видно ни одного результата, бесполезна (F-TEXT-12).
const double kSearchTypingExtent = 168;

/// Ниже этой высоты полосе тесно: поле и строка счёта вместе в неё не
/// помещаются, и остаётся что-то одно — поле при вводе, счёт при
/// просмотре. Так бывает на телефоне, лежащем на боку, с высокой
/// клавиатурой.
const double kSearchCrampedExtent = 120;

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
  /// У правого края — рядом со страницей, на широком окне.
  right,

  /// У нижнего края — полосой поверх страницы, на узком экране.
  bottom,
}

/// Где и какой стоит панель поиска.
class SearchDock {
  /// Создаёт место панели.
  const SearchDock({
    required this.side,
    required this.extent,
    this.beside = false,
    this.lift = 0,
  });

  /// У какого края.
  final SearchDockSide side;

  /// Размер поперёк края: ширина у правого края, высота у нижнего.
  final double extent;

  /// Стоит ли панель рядом со страницей (`true`) или поверх неё.
  ///
  /// Рядом — лист раскладывается в оставшейся ширине, и найденное под
  /// панелью оказаться не может. Поверх — лист не перекладывается.
  final bool beside;

  /// На сколько панель поднята над нижним краем: высота клавиатуры.
  ///
  /// Страница под клавиатурой не перекладывается, а панель обязана
  /// стоять над ней — иначе поле запроса оказалось бы под клавишами.
  final double lift;

  /// Сколько ширины панель отнимает у листа.
  double get taken => beside ? extent : 0;

  /// Прямоугольник панели в области [area].
  Rect rectIn(Size area) {
    switch (side) {
      case SearchDockSide.right:
        return Rect.fromLTWH(
          area.width - extent,
          0,
          extent,
          area.height - lift,
        );
      case SearchDockSide.bottom:
        return Rect.fromLTWH(
          0,
          area.height - lift - extent,
          area.width,
          extent,
        );
    }
  }

  @override
  bool operator ==(Object other) {
    return other is SearchDock &&
        other.side == side &&
        other.extent == extent &&
        other.beside == beside &&
        other.lift == lift;
  }

  @override
  int get hashCode => Object.hash(side, extent, beside, lift);

  @override
  String toString() {
    final String how = beside ? 'рядом' : 'поверх';
    return 'SearchDock($side, $how, $extent, над клавиатурой $lift)';
  }
}

/// Широкое ли окно: панель встаёт рядом со страницей.
bool isSearchWide(Size screen) => screen.width >= kSearchWideWindow;

/// Выбирает место панели поиска.
///
/// [screen] — экран или окно целиком: по нему решается, широкое ли окно.
/// [area] — место, в котором стоят страница и панель: оно бывает меньше
/// экрана. [keyboard] — сколько высоты [area] снизу закрыла экранная
/// клавиатура. [typing] — набирают ли запрос: тогда в полосе стоит поле
/// ввода, и ей нужно место хотя бы под одну строку списка.
///
/// Правила — ALG-UI-31:
///
/// 1. Широкое окно — панель у правого края, рядом со страницей.
/// 2. Узкий экран — полоса во всю ширину у нижнего края, в портрете и в
///    альбоме, при вводе и при просмотре (F-TEXT-12). Найденное её не
///    двигает и размера ей не меняет.
/// 3. Высота полосы — не больше 40 % того, что осталось от места над
///    клавиатурой; при вводе — не меньше [kSearchTypingExtent], но и не
///    больше оставшегося места.
/// 4. Клавиатура поднимает панель над собой и места под лист не меняет.
SearchDock placeSearchPanel({
  required Size screen,
  required Size area,
  double keyboard = 0,
  bool typing = false,
}) {
  final double height = area.height;
  final double lift = keyboard <= 0
      ? 0
      : (keyboard > height ? height : keyboard);
  if (isSearchWide(screen)) {
    return SearchDock(
      side: SearchDockSide.right,
      extent: kSearchPanelWidth,
      beside: true,
      lift: lift,
    );
  }
  final double free = height - lift;
  double extent = free * kSearchStripShare;
  if (typing && extent < kSearchTypingExtent) {
    extent = kSearchTypingExtent;
  }
  if (extent > free) {
    extent = free;
  }
  return SearchDock(side: SearchDockSide.bottom, extent: extent, lift: lift);
}
