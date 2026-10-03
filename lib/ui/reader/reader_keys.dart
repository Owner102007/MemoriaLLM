import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Набирает ли читатель текст прямо сейчас.
///
/// Спрашивается у указателя ввода, а не у того, открыта ли панель поиска:
/// панель может быть открыта, а курсор стоять в списке найденного — тогда
/// клавиши чтения работать обязаны.
bool isTypingInField() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) {
    return false;
  }
  if (context.widget is EditableText) {
    return true;
  }
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

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

  /// Развернуть чтение во весь экран или вернуть окно (F-READ-35).
  fullScreen,
}

/// Что означает нажатая клавиша.
///
/// Чистая функция, потому что раскладка клавиш — это правило, а не
/// виджет: её проверяют таблицей, а не тыканьем. Ctrl (на маке — Cmd)
/// приходит одним признаком [control]: соответствие платформ решает тот,
/// кто ловит событие.
///
/// **Клавиши работают всегда**, выделен текст или нет: собственная
/// навигация просмотрщика выключена намеренно, чтобы его страница не
/// уехала от нашей.
///
/// **Кроме одного случая: [typing].** Пока указатель ввода стоит в поле,
/// клавиши чтения не разбираются вовсе — иначе пробел и `Backspace`
/// уходят на листание, а до поля не доходят. Ровно это и сломалось в
/// S6.1: клавиатурный узел стоит над `Scaffold` и отвечал «разобрано», не
/// спросив, не набирает ли читатель текст прямо сейчас. Исключение —
/// клавиши, которых поле не ждёт никогда: `Ctrl+F` и `F3`. `Esc` в
/// исключения **не** входит: его разбирает сама панель поиска, ей ближе.
///
/// `F11` — чтение во весь экран (F-READ-35), и тоже из любого места: поле
/// его не ждёт. Но только там, где окно умеет разворачиваться
/// ([canFullScreen]): на телефоне клавиша не значит ничего.
ReaderKeyAction? readerKeyAction({
  required LogicalKeyboardKey key,
  bool control = false,
  bool shift = false,
  bool searching = false,
  bool hasHits = false,
  bool typing = false,
  bool canFullScreen = false,
}) {
  if (control) {
    return key == LogicalKeyboardKey.keyF ? ReaderKeyAction.openSearch : null;
  }
  if (key == LogicalKeyboardKey.f11) {
    return canFullScreen ? ReaderKeyAction.fullScreen : null;
  }
  if (key == LogicalKeyboardKey.f3) {
    return hasHits
        ? (shift ? ReaderKeyAction.previousHit : ReaderKeyAction.nextHit)
        : null;
  }
  if (typing) {
    return null;
  }
  if (key == LogicalKeyboardKey.escape) {
    return ReaderKeyAction.dismiss;
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

/// Что закрывает `Esc`.
enum EscapeTarget {
  /// Панель поиска.
  search,

  /// Оглавление.
  outline,

  /// То, что лежит на странице: выделение и панели чтения.
  page,

  /// Чтение во весь экран: окно возвращается к обычному виду.
  fullScreen,
}

/// Что закроет `Esc` прямо сейчас.
///
/// Закрывается то, что открыто ближе всего к читателю, по одному за
/// нажатие: поиск, оглавление, выделение с панелями. **Из чтения во весь
/// экран `Esc` выводит последним** (F-READ-35) — когда закрывать больше
/// нечего. Иначе клавиша, которой привыкли снимать выделение, каждый раз
/// заодно сворачивала бы окно.
EscapeTarget escapeTarget({
  required bool searching,
  required bool outline,
  required bool selecting,
  required bool panels,
  required bool fullScreen,
}) {
  if (searching) {
    return EscapeTarget.search;
  }
  if (outline) {
    return EscapeTarget.outline;
  }
  if (fullScreen && !selecting && !panels) {
    return EscapeTarget.fullScreen;
  }
  return EscapeTarget.page;
}
