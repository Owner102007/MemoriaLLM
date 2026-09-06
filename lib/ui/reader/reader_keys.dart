import 'package:flutter/services.dart';

/// Что делает клавиша в чтении.
enum ReaderKeyAction {
  /// Предыдущий фрагмент.
  previous,

  /// Следующий фрагмент.
  next,

  /// Открыть поиск по книге.
  openSearch,

  /// Следующее совпадение поиска.
  nextHit,

  /// Предыдущее совпадение поиска.
  previousHit,

  /// Закрыть то, что открыто: выделение, поиск, панели.
  dismiss,
}

/// Что означает нажатая клавиша.
///
/// Чистая функция, потому что раскладка клавиш — это правило, а не
/// виджет: её проверяют таблицей, а не тыканьем. Ctrl (на маке — Cmd)
/// приходит одним признаком [control]: соответствие платформ решает тот,
/// кто ловит событие.
///
/// **Клавиши работают всегда**, выделен текст или нет: слой выделения
/// поднят над страницей, но событие клавиатуры до него не доходит —
/// собственная навигация просмотрщика в слое выключена намеренно.
ReaderKeyAction? readerKeyAction({
  required LogicalKeyboardKey key,
  bool control = false,
  bool shift = false,
  bool searching = false,
  bool hasHits = false,
}) {
  if (control) {
    return key == LogicalKeyboardKey.keyF ? ReaderKeyAction.openSearch : null;
  }
  if (key == LogicalKeyboardKey.escape) {
    return ReaderKeyAction.dismiss;
  }
  if (key == LogicalKeyboardKey.f3) {
    return hasHits
        ? (shift ? ReaderKeyAction.previousHit : ReaderKeyAction.nextHit)
        : null;
  }
  // Enter ведёт себя по обстановке: пока ищут — это «следующее
  // совпадение», в остальное время он к листанию отношения не имеет.
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return searching && hasHits ? ReaderKeyAction.nextHit : null;
  }
  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.pageUp ||
      key == LogicalKeyboardKey.backspace) {
    return ReaderKeyAction.previous;
  }
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.space) {
    // Shift+пробел листает назад — привычка из просмотрщиков и браузеров.
    return shift && key == LogicalKeyboardKey.space
        ? ReaderKeyAction.previous
        : ReaderKeyAction.next;
  }
  return null;
}
