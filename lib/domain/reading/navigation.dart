/// Навигация и позиция чтения — чистая математика.
///
/// Здесь нет ни движка PDF, ни виджетов, поэтому всё это тестируется
/// исчерпывающе. Место в книге — то, что читатель теряет болезненнее
/// всего, и вся арифметика вокруг него собрана в одном файле осознанно.
library;

import 'reading.dart';

/// Приводит номер страницы к допустимому диапазону `1…pageCount`.
///
/// Страница вне диапазона — не исключение, а обычное дело: книга могла
/// быть перекачана в другой редакции, а позиция приехать с другого
/// устройства. Читателю в таком случае лучше показать край книги, чем
/// пустой экран.
int clampPage(int page, int pageCount) {
  if (pageCount <= 0) {
    return 1;
  }
  if (page < 1) {
    return 1;
  }
  if (page > pageCount) {
    return pageCount;
  }
  return page;
}

/// Доля прочитанного, от 0 до 1: `(страница + смещение) / всего страниц`.
///
/// Страница засчитывается прочитанной, как только она открыта: в режиме
/// «страница целиком» она видна вся, и держать индикатор на нуле, пока
/// человек читает первую страницу из десяти, попросту неправда. Оттого
/// первая страница из десяти — это 10 %, а последняя — ровно 100 %,
/// а не 90 %, как вышло бы при счёте по верхней границе.
///
/// [offset] — доля страницы, прокрученная вниз (пригодится непрерывному
/// листанию). Она только увеличивает прогресс, поэтому при прокрутке
/// индикатор не дёргается назад.
double progressForPage(int page, int pageCount, {double offset = 0}) {
  if (pageCount <= 0) {
    return 0;
  }
  final int safePage = clampPage(page, pageCount);
  final double safeOffset = offset.isFinite ? offset.clamp(0.0, 1.0) : 0.0;
  final double value = (safePage + safeOffset) / pageCount;
  return value > 1 ? 1 : value;
}

/// Страница по доле прочитанного — обратная операция к [progressForPage].
///
/// Нужна ползунку прогресса: человек тянет ползунок, а перейти надо
/// на страницу.
int pageForProgress(double progress, int pageCount) {
  if (pageCount <= 0) {
    return 1;
  }
  if (!progress.isFinite || progress <= 0) {
    return 1;
  }
  if (progress >= 1) {
    return pageCount;
  }
  // Поправка на двоичную арифметику: `11 / 340 * 340` в double равно
  // `11.000000000000002`, и честный `ceil` вернул бы двенадцатую страницу
  // вместо одиннадцатой. Ползунок от этого прыгал бы на страницу вперёд
  // при каждом касании.
  final int page = (progress * pageCount - 1e-9).ceil();
  return clampPage(page, pageCount);
}

/// Позиция для страницы [page] книги [bookId] из [pageCount] страниц.
ReadingPosition positionForPage({
  required String bookId,
  required int page,
  required int pageCount,
  int fragment = 0,
  double offset = 0,
}) {
  final int safePage = clampPage(page, pageCount);
  return ReadingPosition(
    bookId: bookId,
    page: safePage,
    fragment: fragment < 0 ? 0 : fragment,
    offset: offset.isFinite ? offset.clamp(0.0, 1.0) : 0,
    progress: progressForPage(safePage, pageCount, offset: offset),
  );
}

/// С какой страницы открывать книгу.
///
/// Позиции ещё нет — открываем с первой. Позиция есть, но указывает за
/// край (книга заменена другой редакцией) — открываем с ближайшего края,
/// а не с начала: потерять место в конце книги обиднее всего.
int restorePage(ReadingPosition? position, int pageCount) {
  if (position == null) {
    return 1;
  }
  return clampPage(position.page, pageCount);
}

/// Следующая страница; на последней остаётся на месте.
int nextPage(int page, int pageCount) => clampPage(page + 1, pageCount);

/// Предыдущая страница; на первой остаётся на месте.
int previousPage(int page, int pageCount) => clampPage(page - 1, pageCount);

/// Человекочитаемая позиция для панели: `12 / 340`.
String pageLabel(int page, int pageCount) {
  return '${clampPage(page, pageCount)} / ${pageCount < 1 ? 1 : pageCount}';
}

/// Позиция листа для панели: `12 / 340`, а в развороте — `12–13 / 340`.
///
/// На развороте видны две страницы, и подпись обязана называть обе:
/// «12 / 340» над страницами 12 и 13 — неправда наполовину (F-READ-06).
String sheetLabel(List<int> pages, int pageCount) {
  if (pages.isEmpty) {
    return pageLabel(1, pageCount);
  }
  final int first = clampPage(pages.first, pageCount);
  final int last = clampPage(pages.last, pageCount);
  if (last <= first) {
    return pageLabel(first, pageCount);
  }
  return '$first–$last / ${pageCount < 1 ? 1 : pageCount}';
}

/// Доля прочитанного в процентах, округлённая к целому.
int progressPercent(double progress) {
  if (!progress.isFinite || progress <= 0) {
    return 0;
  }
  if (progress >= 1) {
    return 100;
  }
  return (progress * 100).round();
}

/// Сколько бегунок ползунка страниц обязан простоять на месте, чтобы
/// страница под ним открылась, не дожидаясь, пока его отпустят.
///
/// Достаточно долго, чтобы протяжка через полкниги не открывала страницы
/// по пути (BUG-39), и достаточно коротко, чтобы остановка читалась как
/// «покажи, что здесь», а не как зависание.
const Duration kSliderRest = Duration(milliseconds: 150);

/// Протяжка ползунка страниц: на какую страницу переходить и когда.
///
/// BUG-39: прежде ползунок звал переход на каждое промежуточное
/// значение, и протяжка через полкниги ставила в очередь движка PDF
/// десятки страниц, которые читателю не нужны, — промер, рамку с
/// разбором текста. Страница, на которой он остановился, ждала за ними,
/// и вместо неё был виден белый лист.
///
/// Теперь, пока бегунок тянут, меняется только подпись над ним. Переход
/// один — туда, где бегунок простоял [kSliderRest] или был отпущен.
/// Правило не знает ни про виджет, ни про таймер: срок отсчитывает тот,
/// кто рисует ползунок, а здесь решается, нужен ли переход.
class SliderDrag {
  int? _held;
  int? _sent;

  /// Страница под бегунком; `null` — бегунок никто не трогал, и он стоит
  /// там же, где книга.
  int? get held => _held;

  /// Бегунок сдвинули на [page]. Переход при этом не делается.
  void move(int page) => _held = page;

  /// Бегунок простоял на месте или отпущен: куда перейти.
  ///
  /// `null` — переходить незачем: бегунок не трогали, книга уже на этой
  /// странице ([current]) или переход на неё уже отправлен в эту же
  /// протяжку.
  int? rest({required int current}) {
    final int? page = _held;
    if (page == null || page == _sent) {
      return null;
    }
    if (_sent == null && page == current) {
      return null;
    }
    _sent = page;
    return page;
  }

  /// Бегунок отпущен, и отправленные переходы закончены: он снова
  /// следует за книгой.
  void release() {
    _held = null;
    _sent = null;
  }
}
