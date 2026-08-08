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
